import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Native Android Bluetooth printer service using platform channels
/// This provides direct access to Android's BluetoothSocket API for reliable
/// SPP communication - the same approach used by Loyverse and other POS apps.
class NativePrinterService {
  static const MethodChannel _channel =
      MethodChannel('com.gm_phoneshoppe/bluetooth_printer');

  static const String _printerAddressKey = 'saved_printer_address';
  static const String _printerNameKey = 'saved_printer_name';

  static String? _connectedAddress;
  static String? _connectedName;
  static bool _isConnected = false;

  // Stream controllers for connection status
  static final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();
  static Stream<bool> get connectionStatusStream =>
      _connectionStatusController.stream;

  // Cash drawer state tracking
  static bool _isCashDrawerOpen = false;
  static Timer? _cashDrawerTimer;
  static const int cashDrawerTimeoutSeconds = 30;
  static final StreamController<bool> _cashDrawerStatusController =
      StreamController<bool>.broadcast();
  static Stream<bool> get cashDrawerStatusStream =>
      _cashDrawerStatusController.stream;
  static bool get isCashDrawerOpen => _isCashDrawerOpen;

  static bool get isConnected => _isConnected;
  static String? get connectedAddress => _connectedAddress;
  static String? get connectedName => _connectedName;

  /// Check if Bluetooth is available on this device
  static Future<bool> isBluetoothAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isBluetoothAvailable');
      return result ?? false;
    } catch (e) {
      debugPrint('NativePrinter: Bluetooth available check error: $e');
      return false;
    }
  }

  /// Check if Bluetooth is enabled/turned on
  static Future<bool> isBluetoothEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isBluetoothEnabled');
      return result ?? false;
    } catch (e) {
      debugPrint('NativePrinter: Bluetooth enabled check error: $e');
      return false;
    }
  }

  /// Initialize the service and try to reconnect to saved printer
  static Future<void> initialize() async {
    // Check if already connected
    await updateConnectionStatus();

    // Try to reconnect to saved printer if not connected
    if (!_isConnected) {
      await _tryReconnectSavedPrinter();
    }
  }

  /// Update connection status from native side
  static Future<void> updateConnectionStatus() async {
    try {
      final connected = await _channel.invokeMethod<bool>('isConnected');
      _isConnected = connected ?? false;
      _connectionStatusController.add(_isConnected);
    } catch (e) {
      debugPrint('NativePrinter: Status check error: $e');
      _isConnected = false;
      _connectionStatusController.add(false);
    }
  }

  /// Get list of paired Bluetooth devices
  static Future<List<Map<String, String>>> getPairedDevices() async {
    try {
      final result = await _channel.invokeMethod<List>('getPairedDevices');
      if (result != null) {
        return result.map((device) {
          final map = Map<String, dynamic>.from(device as Map);
          return {
            'name': map['name']?.toString() ?? 'Unknown',
            'address': map['address']?.toString() ?? '',
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('NativePrinter: Get paired devices error: $e');
    }
    return [];
  }

  /// Connect to a printer by MAC address
  static Future<bool> connect(String address, {String? name}) async {
    try {
      debugPrint('NativePrinter: Connecting to $address...');
      final result = await _channel.invokeMethod<bool>(
        'connect',
        {'address': address},
      );

      if (result == true) {
        _connectedAddress = address;
        _connectedName = name;
        _isConnected = true;
        _connectionStatusController.add(true);

        // Save preference
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_printerAddressKey, address);
        if (name != null) {
          await prefs.setString(_printerNameKey, name);
        }

        debugPrint('NativePrinter: Connected successfully');
        return true;
      }
    } catch (e) {
      debugPrint('NativePrinter: Connection error: $e');
    }

    _isConnected = false;
    _connectionStatusController.add(false);
    return false;
  }

  /// Disconnect from current printer
  static Future<void> disconnect() async {
    try {
      await _channel.invokeMethod('disconnect');
    } catch (e) {
      debugPrint('NativePrinter: Disconnect error: $e');
    }
    _connectedAddress = null;
    _connectedName = null;
    _isConnected = false;
    _connectionStatusController.add(false);
  }

  /// Clear saved printer preference
  static Future<void> forgetSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_printerAddressKey);
    await prefs.remove(_printerNameKey);
    await disconnect();
  }

  /// Try to reconnect to the last saved printer
  static Future<bool> _tryReconnectSavedPrinter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAddress = prefs.getString(_printerAddressKey);
      final savedName = prefs.getString(_printerNameKey);

      if (savedAddress != null && savedAddress.isNotEmpty) {
        return await connect(savedAddress, name: savedName);
      }
    } catch (e) {
      debugPrint('NativePrinter: Reconnect error: $e');
    }
    return false;
  }

  /// Ensure connection before printing (connect-on-demand)
  static Future<bool> _ensureConnection() async {
    // Check current connection status
    await updateConnectionStatus();
    if (_isConnected) {
      return true;
    }

    // Try to reconnect to saved printer
    return await _tryReconnectSavedPrinter();
  }

  /// Write raw bytes to the printer
  static Future<bool> writeBytes(List<int> bytes) async {
    try {
      final connected = await _ensureConnection();
      if (!connected) {
        debugPrint('NativePrinter: Not connected');
        return false;
      }

      debugPrint('NativePrinter: Writing ${bytes.length} bytes...');
      final result = await _channel.invokeMethod<bool>(
        'writeBytes',
        {'bytes': Uint8List.fromList(bytes)},
      );

      debugPrint('NativePrinter: Write result: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('NativePrinter: Write error: $e');
      return false;
    }
  }

  /// Open the cash drawer using native Bluetooth
  static Future<bool> openCashDrawer({int pin = 0}) async {
    try {
      final connected = await _ensureConnection();
      if (!connected) {
        debugPrint('NativePrinter: Not connected - cannot open cash drawer');
        return false;
      }

      debugPrint('NativePrinter: Opening cash drawer (pin: $pin)...');
      final result = await _channel.invokeMethod<bool>(
        'openCashDrawer',
        {'pin': pin},
      );

      debugPrint('NativePrinter: Cash drawer result: $result');

      if (result == true) {
        // Mark drawer as open and start auto-close timer
        _isCashDrawerOpen = true;
        _cashDrawerStatusController.add(true);
        _cashDrawerTimer?.cancel();
        _cashDrawerTimer = Timer(
          const Duration(seconds: cashDrawerTimeoutSeconds),
          markCashDrawerClosed,
        );
      }

      return result ?? false;
    } catch (e) {
      debugPrint('NativePrinter: Cash drawer error: $e');
      return false;
    }
  }

  /// Manually mark the cash drawer as closed
  static void markCashDrawerClosed() {
    _cashDrawerTimer?.cancel();
    _isCashDrawerOpen = false;
    _cashDrawerStatusController.add(false);
  }

  /// Print a test receipt
  static Future<bool> printTestReceipt() async {
    final List<int> bytes = [];

    // Initialize
    bytes.addAll([0x1B, 0x40]);

    // Center, bold, double size
    bytes.addAll([0x1B, 0x61, 0x01]);
    bytes.addAll([0x1B, 0x45, 0x01]);
    bytes.addAll([0x1D, 0x21, 0x11]);
    bytes.addAll(_textToBytes('GM PHONESHOPPE\n'));

    // Normal
    bytes.addAll([0x1D, 0x21, 0x00]);
    bytes.addAll([0x1B, 0x45, 0x00]);

    bytes.addAll(_textToBytes('--------------------------------\n'));
    bytes.addAll([0x1B, 0x45, 0x01]);
    bytes.addAll(_textToBytes('NATIVE PRINTER TEST\n'));
    bytes.addAll([0x1B, 0x45, 0x00]);
    bytes.addAll(
        _textToBytes('${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}\n'));
    bytes.addAll(_textToBytes('--------------------------------\n'));

    // Left
    bytes.addAll([0x1B, 0x61, 0x00]);
    bytes.addAll(_textToBytes('Printer: ${_connectedName ?? 'Unknown'}\n'));
    bytes.addAll(_textToBytes('Using: Native Android Bluetooth\n'));
    bytes.addAll(_textToBytes('Status: Connected\n'));

    // Center
    bytes.addAll([0x1B, 0x61, 0x01]);
    bytes.addAll(_textToBytes('--------------------------------\n'));
    bytes.addAll(_textToBytes('If you can read this,\n'));
    bytes.addAll(_textToBytes('native Bluetooth is working!\n'));

    // Feed
    bytes.addAll([0x1B, 0x64, 0x04]);

    return await writeBytes(bytes);
  }

  /// Print a POS transaction receipt
  static Future<bool> printReceipt(Map<String, dynamic> transaction) async {
    final bytes = _buildReceiptBytes(transaction);
    return await writeBytes(bytes);
  }

  /// Print receipt and open cash drawer
  /// Drawer command is sent FIRST as separate transmission to ensure it opens
  /// before any print data is sent to the printer's buffer
  static Future<bool> printReceiptAndOpenDrawer(
      Map<String, dynamic> transaction) async {
    try {
      final isCashPayment = transaction['paymentMethod'] == 'cash';
      final hasCashOut = transaction['hasCashOut'] == true;
      final needsDrawer = isCashPayment || hasCashOut;

      // STEP 1: Open drawer FIRST (separate transmission)
      // This ensures drawer opens before printer receives any print data
      if (needsDrawer) {
        // Retry drawer command up to 3 times for reliability
        bool drawerSuccess = false;
        for (int attempt = 1; attempt <= 3 && !drawerSuccess; attempt++) {
          debugPrint('NativePrinter: Sending drawer command FIRST (attempt $attempt)...');
          drawerSuccess = await openCashDrawer();
          debugPrint('NativePrinter: Drawer command result: $drawerSuccess');
          if (!drawerSuccess && attempt < 3) {
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }

        // Delay to let drawer kick before sending print data
        // 400ms gives the drawer solenoid time to fully engage
        await Future.delayed(const Duration(milliseconds: 400));
      }

      // STEP 2: Send receipt data (drawer is already opening)
      debugPrint('NativePrinter: Sending receipt data...');
      final bytes = _buildReceiptBytes(transaction, openDrawer: false);
      final printSuccess = await writeBytes(bytes);
      debugPrint('NativePrinter: Print result: $printSuccess');

      return printSuccess;
    } catch (e) {
      debugPrint('NativePrinter: Drawer+Print error: $e');
      return false;
    }
  }

  /// Build receipt bytes using ESC/POS commands
  static List<int> _buildReceiptBytes(Map<String, dynamic> transaction, {bool openDrawer = false}) {
    final List<int> bytes = [];
    final currencyFormat = NumberFormat.currency(symbol: '', decimalDigits: 2);
    final items = transaction['items'] as List<dynamic>? ?? [];

    // Initialize printer
    bytes.addAll([0x1B, 0x40]); // ESC @ - Initialize

    // Open cash drawer IMMEDIATELY after init (before any print content)
    // This makes drawer open first, then receipt prints
    if (openDrawer) {
      bytes.addAll([
        0x1B, 0x70,  // ESC p - Cash drawer kick
        0x00,        // m = 0 (pin 2)
        0x19,        // t1 = 25 × 2ms = 50ms ON
        0x78,        // t2 = 120 × 2ms = 240ms OFF
      ]);
      debugPrint('NativePrinter: Cash drawer command inserted after init');
    }

    // Center alignment
    bytes.addAll([0x1B, 0x61, 0x01]); // ESC a 1 - Center

    // Bold on, double height
    bytes.addAll([0x1B, 0x45, 0x01]); // ESC E 1 - Bold on
    bytes.addAll([0x1D, 0x21, 0x11]); // GS ! - Double height and width

    // Store name
    bytes.addAll(_textToBytes('GM PHONESHOPPE\n'));

    // Normal size
    bytes.addAll([0x1D, 0x21, 0x00]); // GS ! - Normal size
    bytes.addAll([0x1B, 0x45, 0x00]); // ESC E 0 - Bold off

    // Store address
    bytes.addAll(_textToBytes('Corner Soliman - Malvar St,\n'));
    bytes.addAll(_textToBytes('Divisoria, Cawayan,\n'));
    bytes.addAll(_textToBytes('5409 Masbate\n'));
    bytes.addAll(_textToBytes('CP# 09351971394\n'));

    // Separator
    bytes.addAll(_textToBytes('--------------------------------\n'));

    // Transaction info
    bytes.addAll(
        _textToBytes('Transaction #${transaction['transactionId']}\n'));

    // Date and time
    final timestamp = transaction['timestamp'] != null
        ? DateTime.parse(transaction['timestamp'])
        : DateTime.now();
    bytes.addAll(_textToBytes(
        '${DateFormat('MMM dd, yyyy hh:mm a').format(timestamp)}\n'));

    bytes.addAll(_textToBytes('--------------------------------\n'));

    // Left alignment for items
    bytes.addAll([0x1B, 0x61, 0x00]); // ESC a 0 - Left

    // Items header
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
    bytes.addAll(_textToBytes('ITEMS\n'));
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold off

    // Item details
    for (var item in items) {
      final name = item['name'] ?? 'Unknown';
      final qty = item['quantity'] ?? 1;
      final unitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0.0;
      final subtotal = (item['subtotal'] as num?)?.toDouble() ?? 0.0;
      final isCashOut = item['isCashOut'] == true;
      final isCashIn = item['isCashIn'] == true;

      // Item name (truncate if too long)
      final displayName =
          name.length > 32 ? '${name.substring(0, 29)}...' : name;
      bytes.addAll(_textToBytes('$displayName\n'));

      if (isCashOut || isCashIn) {
        // For cash-out/cash-in, show breakdown
        final principal = (item['cashOutAmount'] as num?)?.toDouble() ?? 0.0;
        final serviceFee = (item['serviceFee'] as num?)?.toDouble() ?? 0.0;
        if (isCashOut) {
          bytes.addAll(_textToBytes(
              ' Cash Given: P${currencyFormat.format(principal)}\n'));
        } else {
          bytes.addAll(_textToBytes(
              ' Cash Received: P${currencyFormat.format(principal)}\n'));
        }
        bytes.addAll(
            _textToBytes(' Service Fee: P${currencyFormat.format(serviceFee)}\n'));
      } else {
        // Regular items
        bytes.addAll(_textToBytes(
            ' $qty x ${currencyFormat.format(unitPrice)} = ${currencyFormat.format(subtotal)}\n'));
      }
    }

    // Center for totals
    bytes.addAll([0x1B, 0x61, 0x01]); // Center
    bytes.addAll(_textToBytes('--------------------------------\n'));

    // Left alignment
    bytes.addAll([0x1B, 0x61, 0x00]); // Left

    // Subtotal (if VAT is separate)
    if (transaction['vatEnabled'] == true &&
        transaction['vatInclusive'] != true) {
      bytes.addAll(_textToBytes(
          'Subtotal:       P${currencyFormat.format(transaction['subtotal'] ?? 0)}\n'));
    }

    // VAT
    if (transaction['vatEnabled'] == true) {
      final vatRate =
          (transaction['vatRate'] as num?)?.toStringAsFixed(0) ?? '12';
      final vatLabel = transaction['vatInclusive'] == true
          ? 'VAT Incl. ($vatRate%)'
          : 'VAT ($vatRate%)';
      bytes.addAll(_textToBytes(
          '$vatLabel:   P${currencyFormat.format(transaction['vatAmount'] ?? 0)}\n'));
    }

    // Total - bold
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
    bytes.addAll(_textToBytes(
        'TOTAL:          P${currencyFormat.format(transaction['total'] ?? 0)}\n'));
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold off

    // Center
    bytes.addAll([0x1B, 0x61, 0x01]);
    bytes.addAll(_textToBytes('--------------------------------\n'));

    // Left
    bytes.addAll([0x1B, 0x61, 0x00]);

    // Payment method
    final paymentMethod =
        (transaction['paymentMethod'] ?? 'cash').toString().toUpperCase();
    bytes.addAll(_textToBytes('Payment: $paymentMethod\n'));

    // Cash details (if cash payment)
    if (transaction['paymentMethod'] == 'cash') {
      bytes.addAll(_textToBytes(
          'Cash:           P${currencyFormat.format(transaction['cashReceived'] ?? 0)}\n'));
      bytes.addAll(_textToBytes(
          'Change:         P${currencyFormat.format(transaction['change'] ?? 0)}\n'));
    }

    // Reference number (if card/gcash)
    final referenceNumber = transaction['referenceNumber'];
    if (referenceNumber != null && referenceNumber.toString().isNotEmpty) {
      bytes.addAll(_textToBytes('Ref #:          $referenceNumber\n'));
    }

    // Customer name (if provided)
    final customerName = transaction['customerName'];
    if (customerName != null && customerName.toString().isNotEmpty) {
      bytes.addAll(_textToBytes('Customer: $customerName\n'));
    }

    // Cash-out summary (if transaction has cash-out)
    final hasCashOut = transaction['hasCashOut'] == true;
    if (hasCashOut) {
      final totalCashOut =
          (transaction['totalCashOutAmount'] as num?)?.toDouble() ?? 0;
      final totalServiceFee =
          (transaction['totalServiceFee'] as num?)?.toDouble() ?? 0;

      bytes.addAll([0x1B, 0x61, 0x01]); // Center
      bytes.addAll(_textToBytes('--- CASH-OUT SUMMARY ---\n'));
      bytes.addAll([0x1B, 0x61, 0x00]); // Left
      bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
      bytes.addAll(_textToBytes(
          'CASH GIVEN:     P${currencyFormat.format(totalCashOut)}\n'));
      bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
      bytes.addAll(_textToBytes(
          'Service Fee:    P${currencyFormat.format(totalServiceFee)}\n'));
    }

    // Center
    bytes.addAll([0x1B, 0x61, 0x01]);
    bytes.addAll(_textToBytes('--------------------------------\n'));

    // Served by
    final servedByFull = transaction['processedBy'] ?? 'Staff';
    final servedByFirst = servedByFull.toString().split(' ').first;
    bytes.addAll(_textToBytes('Served by: $servedByFirst\n'));

    // Footer
    bytes.addAll(_textToBytes('\n'));
    bytes.addAll(_textToBytes('Thank you for your purchase!\n'));
    bytes.addAll(_textToBytes('Please come again.\n'));

    // Feed and cut
    bytes.addAll([0x1B, 0x64, 0x04]); // ESC d 4 - Feed 4 lines

    return bytes;
  }

  /// Convert text to bytes
  static List<int> _textToBytes(String text) {
    return text.codeUnits;
  }

  /// Test cash drawer with multiple command formats
  static Future<void> testCashDrawerCommands() async {
    final connected = await _ensureConnection();
    if (!connected) {
      debugPrint('NativePrinter: Not connected - cannot test');
      return;
    }

    debugPrint('');
    debugPrint('============================================');
    debugPrint('  NATIVE CASH DRAWER COMMAND TEST');
    debugPrint('============================================');

    // Test Pin 0
    debugPrint('\n[TEST 1] Native Cash Drawer - Pin 0');
    var result = await openCashDrawer(pin: 0);
    debugPrint('Result: $result');
    await Future.delayed(const Duration(seconds: 3));

    // Test Pin 1
    debugPrint('\n[TEST 2] Native Cash Drawer - Pin 1');
    result = await openCashDrawer(pin: 1);
    debugPrint('Result: $result');
    await Future.delayed(const Duration(seconds: 3));

    // Test with manual bytes - DLE DC4 command (alternative)
    debugPrint('\n[TEST 3] DLE DC4 command');
    final dleDc4 = [0x10, 0x14, 0x01, 0x00, 0x01];
    result = await writeBytes(dleDc4);
    debugPrint('Result: $result');
    await Future.delayed(const Duration(seconds: 3));

    // Test with longer pulse
    debugPrint('\n[TEST 4] Longer pulse (200ms ON)');
    final longPulse = [
      0x1B, 0x40, // Initialize
      0x1B, 0x70, 0x00, 0x64, 0xFA, // ESC p with longer t1
      0x0A // LF
    ];
    result = await writeBytes(longPulse);
    debugPrint('Result: $result');

    debugPrint('\n============================================');
    debugPrint('  TEST COMPLETE');
    debugPrint('============================================');
  }

  /// Dispose resources
  static void dispose() {
    _cashDrawerTimer?.cancel();
    _connectionStatusController.close();
    _cashDrawerStatusController.close();
  }
}
