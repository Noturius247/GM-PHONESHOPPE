import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart' show BluetoothInfo;

/// Service for managing Bluetooth thermal printer (T58W ESC/POS)
/// Paper width: 58mm, Print width: 48mm (384 dots at 203 dpi)
///
/// Uses "connect-on-demand" strategy like Loyverse POS for reliability:
/// Instead of maintaining a persistent connection (which Bluetooth Classic
/// doesn't handle well), we reconnect fresh before each print operation.
class PrinterService {
  static String? _connectedAddress;
  static String? _connectedName;
  static bool _isConnected = false;
  static const String _printerAddressKey = 'saved_printer_address';
  static const String _printerNameKey = 'saved_printer_name';

  // Heartbeat timer for UI status updates (passive - no commands sent)
  static Timer? _heartbeatTimer;
  static const int _heartbeatIntervalSeconds = 30;

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

  /// Manually mark the cash drawer as closed (e.g. user confirms)
  static void markCashDrawerClosed() {
    _cashDrawerTimer?.cancel();
    _isCashDrawerOpen = false;
    _cashDrawerStatusController.add(false);
  }

  static bool get isConnected => _isConnected;
  static BluetoothInfo? get connectedDevice => _isConnected && _connectedAddress != null
      ? BluetoothInfo(name: _connectedName ?? 'Unknown', macAdress: _connectedAddress!)
      : null;

  /// Initialize the printer service
  static Future<void> initialize() async {
    // Check current connection status
    _isConnected = await PrintBluetoothThermal.connectionStatus;
    _connectionStatusController.add(_isConnected);

    // Try to reconnect to saved printer if not connected
    if (!_isConnected) {
      final reconnected = await _tryReconnectSavedPrinter();
      if (reconnected) {
        debugPrint('Printer reconnected on initialize');
      }
    } else {
      // Already connected - load saved info
      final prefs = await SharedPreferences.getInstance();
      _connectedAddress = prefs.getString(_printerAddressKey);
      _connectedName = prefs.getString(_printerNameKey);
      debugPrint('Printer already connected: $_connectedName');
    }

    // Start heartbeat monitoring (will reconnect if disconnected)
    _startHeartbeat();
  }

  /// Start periodic connection monitoring
  static void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: _heartbeatIntervalSeconds),
      (_) => _checkConnectionAndReconnect(),
    );
  }

  /// Stop heartbeat monitoring
  static void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Check connection status (passive - no commands sent to printer)
  /// We don't aggressively reconnect to avoid confusing the printer's Bluetooth
  static Future<void> _checkConnectionAndReconnect() async {
    try {
      // Just check status - DON'T send any bytes to printer
      // Sending keepalive commands can confuse some printer firmware
      final actualStatus = await PrintBluetoothThermal.connectionStatus;

      if (actualStatus != _isConnected) {
        _isConnected = actualStatus;
        _connectionStatusController.add(_isConnected);
        debugPrint('Printer status changed: ${_isConnected ? "connected" : "disconnected"}');
      }

      // Don't auto-reconnect aggressively - let user trigger reconnect
      // or reconnect will happen automatically when printing
    } catch (e) {
      debugPrint('Status check error: $e');
    }
  }

  // Track when connection was established to know if we need warmup delay
  static DateTime? _lastConnectionTime;
  static const int _connectionWarmupMs = 1000; // 1 second warmup after fresh connect

  /// LOYVERSE-STYLE: Ensure connection before printing
  /// Simple approach: check status, if not connected try to connect
  /// DON'T send test bytes - some printers lock up when receiving unexpected commands
  static Future<bool> _ensureFreshConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final savedAddress = prefs.getString(_printerAddressKey);
    final savedName = prefs.getString(_printerNameKey);

    if (savedAddress == null || savedAddress.isEmpty) {
      debugPrint('No saved printer to connect to');
      return false;
    }

    // Check if already connected - trust the status, don't send test bytes
    try {
      final currentStatus = await PrintBluetoothThermal.connectionStatus;
      if (currentStatus) {
        debugPrint('Printer already connected');
        _isConnected = true;
        _connectedAddress = savedAddress;
        _connectedName = savedName;
        _connectionStatusController.add(true);

        // If recently connected, wait for warmup
        if (_lastConnectionTime != null) {
          final elapsed = DateTime.now().difference(_lastConnectionTime!).inMilliseconds;
          if (elapsed < _connectionWarmupMs) {
            final waitTime = _connectionWarmupMs - elapsed;
            debugPrint('Waiting ${waitTime}ms for connection warmup...');
            await Future.delayed(Duration(milliseconds: waitTime));
          }
        }
        return true;
      }
    } catch (e) {
      debugPrint('Status check failed: $e');
    }

    // Not connected - try to connect (no aggressive disconnect first)
    debugPrint('Connecting to $savedName ($savedAddress)...');
    try {
      final result = await PrintBluetoothThermal.connect(
        macPrinterAddress: savedAddress,
      ).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          debugPrint('Connection timed out');
          return false;
        },
      );

      if (result) {
        _connectedAddress = savedAddress;
        _connectedName = savedName;
        _isConnected = true;
        _connectionStatusController.add(true);
        _lastConnectionTime = DateTime.now();
        debugPrint('Connected successfully - waiting for warmup...');

        // IMPORTANT: Wait for Bluetooth data channel to be fully ready
        await Future.delayed(const Duration(milliseconds: 1000));
        return true;
      } else {
        debugPrint('Connection failed');
        _isConnected = false;
        _connectionStatusController.add(false);
        return false;
      }
    } catch (e) {
      debugPrint('Connection error: $e');
      _isConnected = false;
      _connectionStatusController.add(false);
      return false;
    }
  }

  /// Try to reconnect to the last saved printer
  static Future<bool> _tryReconnectSavedPrinter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAddress = prefs.getString(_printerAddressKey);
      final savedName = prefs.getString(_printerNameKey);

      if (savedAddress != null && savedAddress.isNotEmpty) {
        final device = BluetoothInfo(
          name: savedName ?? 'Saved Printer',
          macAdress: savedAddress,
        );
        return await connectToDevice(device, savePreference: false);
      }
    } catch (e) {
      debugPrint('Failed to reconnect to saved printer: $e');
    }
    return false;
  }

  /// Get list of paired Bluetooth devices
  static Future<List<BluetoothInfo>> getPairedDevices() async {
    try {
      final List<BluetoothInfo> devices = await PrintBluetoothThermal.pairedBluetooths;
      return devices;
    } catch (e) {
      debugPrint('Get paired devices error: $e');
      return [];
    }
  }

  /// Check if Bluetooth is available
  static Future<bool> isBluetoothAvailable() async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (e) {
      return false;
    }
  }

  /// Check if Bluetooth is on (same as available for this package)
  static Future<bool> isBluetoothOn() async {
    return await isBluetoothAvailable();
  }

  /// Connect to a Bluetooth printer device
  static Future<bool> connectToDevice(
    BluetoothInfo device, {
    bool savePreference = true,
  }) async {
    try {
      final result = await PrintBluetoothThermal.connect(
        macPrinterAddress: device.macAdress,
      );

      if (result) {
        _connectedAddress = device.macAdress;
        _connectedName = device.name;
        _isConnected = true;
        _connectionStatusController.add(true);

        if (savePreference) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_printerAddressKey, device.macAdress);
          await prefs.setString(_printerNameKey, device.name ?? '');
        }

        // Small delay to let connection stabilize before starting heartbeat
        await Future.delayed(const Duration(milliseconds: 500));

        // Start heartbeat to maintain connection
        _startHeartbeat();

        debugPrint('Connected to ${device.name} - heartbeat started');
        return true;
      }
    } catch (e) {
      debugPrint('Connection error: $e');
    }

    return false;
  }

  /// Disconnect from current printer
  static Future<void> disconnect() async {
    try {
      _stopHeartbeat();
      await PrintBluetoothThermal.disconnect;
      _connectedAddress = null;
      _connectedName = null;
      _isConnected = false;
      _connectionStatusController.add(false);
    } catch (e) {
      debugPrint('Disconnect error: $e');
    }
  }

  /// Clear saved printer preference
  static Future<void> forgetSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_printerAddressKey);
    await prefs.remove(_printerNameKey);
    await disconnect();
  }

  /// Update connection status and attempt reconnection if disconnected
  static Future<void> updateConnectionStatus() async {
    _isConnected = await PrintBluetoothThermal.connectionStatus;
    _connectionStatusController.add(_isConnected);

    // If not connected, try to reconnect to saved printer
    if (!_isConnected) {
      final reconnected = await _tryReconnectSavedPrinter();
      if (reconnected) {
        debugPrint('Printer auto-reconnected during status update');
      }
    }
  }

  /// Stream of scan results (returns paired devices for this package)
  static Stream<List<BluetoothInfo>> get scanResultsStream async* {
    yield await getPairedDevices();
  }

  /// Start scan (gets paired devices)
  static void startScan({Duration timeout = const Duration(seconds: 4)}) {
    // This package uses paired devices instead of scanning
  }

  /// Stop scan
  static void stopScan() {
    // Not needed for this package
  }

  /// Print a POS transaction receipt
  /// Uses Loyverse-style "connect-on-demand" for reliability
  static Future<bool> printReceipt(Map<String, dynamic> transaction) async {
    // LOYVERSE-STYLE: Always ensure fresh connection before printing
    // This is more reliable than trying to maintain a persistent connection
    final connected = await _ensureFreshConnection();
    if (!connected) {
      debugPrint('Could not establish connection to printer');
      return false;
    }

    try {
      final bytes = _buildReceiptBytes(transaction);
      final result = await PrintBluetoothThermal.writeBytes(bytes);

      if (result) {
        debugPrint('Print successful');
        return true;
      }

      // First attempt failed - try once more with fresh connection
      debugPrint('Print failed, retrying with fresh connection...');

      // Force disconnect and reconnect
      try {
        await PrintBluetoothThermal.disconnect;
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (_) {}

      final reconnected = await _ensureFreshConnection();
      if (reconnected) {
        final retryResult = await PrintBluetoothThermal.writeBytes(bytes);
        if (retryResult) {
          debugPrint('Print successful on retry');
        }
        return retryResult;
      }

      return false;
    } catch (e) {
      debugPrint('Print error: $e');
      _isConnected = false;
      _connectionStatusController.add(false);
      return false;
    }
  }

  /// Build receipt bytes using ESC/POS commands
  static List<int> _buildReceiptBytes(Map<String, dynamic> transaction) {
    final List<int> bytes = [];
    final currencyFormat = NumberFormat.currency(symbol: '', decimalDigits: 2);
    final items = transaction['items'] as List<dynamic>? ?? [];

    // Initialize printer
    bytes.addAll([0x1B, 0x40]); // ESC @ - Initialize

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
    bytes.addAll(_textToBytes('Transaction #${transaction['transactionId']}\n'));

    // Date and time
    final timestamp = transaction['timestamp'] != null
        ? DateTime.parse(transaction['timestamp'])
        : DateTime.now();
    bytes.addAll(_textToBytes('${DateFormat('MMM dd, yyyy hh:mm a').format(timestamp)}\n'));

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
      final displayName = name.length > 32 ? '${name.substring(0, 29)}...' : name;
      bytes.addAll(_textToBytes('$displayName\n'));

      if (isCashOut || isCashIn) {
        // For cash-out/cash-in, show breakdown
        final principal = (item['cashOutAmount'] as num?)?.toDouble() ?? 0.0;
        final serviceFee = (item['serviceFee'] as num?)?.toDouble() ?? 0.0;
        if (isCashOut) {
          bytes.addAll(_textToBytes(' Cash Given: P${currencyFormat.format(principal)}\n'));
        } else {
          bytes.addAll(_textToBytes(' Cash Received: P${currencyFormat.format(principal)}\n'));
        }
        bytes.addAll(_textToBytes(' Service Fee: P${currencyFormat.format(serviceFee)}\n'));
      } else {
        // Regular items
        bytes.addAll(_textToBytes(' $qty x ${currencyFormat.format(unitPrice)} = ${currencyFormat.format(subtotal)}\n'));
      }
    }

    // Center for totals
    bytes.addAll([0x1B, 0x61, 0x01]); // Center
    bytes.addAll(_textToBytes('--------------------------------\n'));

    // Left alignment
    bytes.addAll([0x1B, 0x61, 0x00]); // Left

    // Subtotal (if VAT is separate)
    if (transaction['vatEnabled'] == true && transaction['vatInclusive'] != true) {
      bytes.addAll(_textToBytes('Subtotal:       P${currencyFormat.format(transaction['subtotal'] ?? 0)}\n'));
    }

    // VAT
    if (transaction['vatEnabled'] == true) {
      final vatRate = (transaction['vatRate'] as num?)?.toStringAsFixed(0) ?? '12';
      final vatLabel = transaction['vatInclusive'] == true
          ? 'VAT Incl. ($vatRate%)'
          : 'VAT ($vatRate%)';
      bytes.addAll(_textToBytes('$vatLabel:   P${currencyFormat.format(transaction['vatAmount'] ?? 0)}\n'));
    }

    // Total - bold
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
    bytes.addAll(_textToBytes('TOTAL:          P${currencyFormat.format(transaction['total'] ?? 0)}\n'));
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold off

    // Center
    bytes.addAll([0x1B, 0x61, 0x01]);
    bytes.addAll(_textToBytes('--------------------------------\n'));

    // Left
    bytes.addAll([0x1B, 0x61, 0x00]);

    // Payment method
    final paymentMethod = (transaction['paymentMethod'] ?? 'cash').toString().toUpperCase();
    bytes.addAll(_textToBytes('Payment: $paymentMethod\n'));

    // Cash details (if cash payment)
    if (transaction['paymentMethod'] == 'cash') {
      bytes.addAll(_textToBytes('Cash:           P${currencyFormat.format(transaction['cashReceived'] ?? 0)}\n'));
      bytes.addAll(_textToBytes('Change:         P${currencyFormat.format(transaction['change'] ?? 0)}\n'));
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
      final totalCashOut = (transaction['totalCashOutAmount'] as num?)?.toDouble() ?? 0;
      final totalServiceFee = (transaction['totalServiceFee'] as num?)?.toDouble() ?? 0;

      bytes.addAll([0x1B, 0x61, 0x01]); // Center
      bytes.addAll(_textToBytes('--- CASH-OUT SUMMARY ---\n'));
      bytes.addAll([0x1B, 0x61, 0x00]); // Left
      bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
      bytes.addAll(_textToBytes('CASH GIVEN:     P${currencyFormat.format(totalCashOut)}\n'));
      bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
      bytes.addAll(_textToBytes('Service Fee:    P${currencyFormat.format(totalServiceFee)}\n'));
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

  /// Print a test receipt
  /// Uses Loyverse-style "connect-on-demand" for reliability
  static Future<bool> printTestReceipt() async {
    // LOYVERSE-STYLE: Always ensure fresh connection before printing
    final connected = await _ensureFreshConnection();
    if (!connected) {
      debugPrint('Could not establish connection to printer');
      return false;
    }

    try {
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
      bytes.addAll(_textToBytes('PRINTER TEST\n'));
      bytes.addAll([0x1B, 0x45, 0x00]);
      bytes.addAll(_textToBytes('${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}\n'));
      bytes.addAll(_textToBytes('--------------------------------\n'));

      // Left
      bytes.addAll([0x1B, 0x61, 0x00]);
      bytes.addAll(_textToBytes('Printer: ${_connectedName ?? 'Unknown'}\n'));
      bytes.addAll(_textToBytes('Status: Connected\n'));

      // Center
      bytes.addAll([0x1B, 0x61, 0x01]);
      bytes.addAll(_textToBytes('--------------------------------\n'));
      bytes.addAll(_textToBytes('If you can read this,\n'));
      bytes.addAll(_textToBytes('your printer is working!\n'));

      // Feed
      bytes.addAll([0x1B, 0x64, 0x04]);

      final result = await PrintBluetoothThermal.writeBytes(bytes);

      if (result) {
        debugPrint('Test print successful');
        return true;
      }

      // First attempt failed - try once more with fresh connection
      debugPrint('Test print failed, retrying with fresh connection...');
      try {
        await PrintBluetoothThermal.disconnect;
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (_) {}

      final reconnected = await _ensureFreshConnection();
      if (reconnected) {
        final retryResult = await PrintBluetoothThermal.writeBytes(bytes);
        return retryResult;
      }

      return false;
    } catch (e) {
      debugPrint('Test print error: $e');
      _isConnected = false;
      _connectionStatusController.add(false);
      return false;
    }
  }

  /// Open the cash drawer connected to the printer's RJ11 port
  static Future<bool> openCashDrawer({int pin = 0}) async {
    // LOYVERSE-STYLE: Ensure fresh connection before sending command
    final connected = await _ensureFreshConnection();
    if (!connected) {
      debugPrint('Printer not connected - cannot open cash drawer');
      return false;
    }

    try {
      // Some printers ONLY process cash drawer when embedded in a print job
      // So we send: Init + small print + cash drawer + feed
      final List<int> command = [
        // Initialize printer
        0x1B, 0x40,       // ESC @ - Initialize printer

        // Print a blank space (forces printer into print mode)
        0x20,             // Space character
        0x0A,             // Line feed

        // Cash drawer kick pulse - try both pins with longer pulse
        0x1B, 0x70,       // ESC p
        pin,              // m: pin selector (0 or 1)
        0x32,             // t1: 50 × 2ms = 100ms ON (longer pulse)
        0xFF,             // t2: 255 × 2ms = 510ms OFF

        // Try other pin too (some drawers wired differently)
        0x1B, 0x70,       // ESC p again
        pin == 0 ? 1 : 0, // Try other pin
        0x32,             // t1
        0xFF,             // t2

        // Feed to ensure buffer is flushed
        0x0A, 0x0A, 0x0A, // Multiple line feeds
      ];

      // Log exact bytes being sent (hex format)
      final hexBytes = command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(' ');
      debugPrint('═══════════════════════════════════════');
      debugPrint('CASH DRAWER (embedded in print, both pins)');
      debugPrint('Bytes: $hexBytes');
      debugPrint('Pin: $pin (also trying pin ${pin == 0 ? 1 : 0})');
      debugPrint('═══════════════════════════════════════');

      var result = await PrintBluetoothThermal.writeBytes(command);
      debugPrint('writeBytes() returned: $result');

      // Also try DLE DC4 command (alternative used by some printers)
      if (result) {
        await Future.delayed(const Duration(milliseconds: 200));
        final dleDc4 = [0x10, 0x14, 0x01, 0x00, 0x01];
        final dleDc4Hex = dleDc4.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(' ');
        debugPrint('Also sending DLE DC4: $dleDc4Hex');
        await PrintBluetoothThermal.writeBytes(dleDc4);
      }

      if (result) {
        // Mark drawer as open and start auto-close timer
        _isCashDrawerOpen = true;
        _cashDrawerStatusController.add(true);
        _cashDrawerTimer?.cancel();
        _cashDrawerTimer = Timer(
          const Duration(seconds: cashDrawerTimeoutSeconds),
          markCashDrawerClosed,
        );
      }

      return result;
    } catch (e) {
      debugPrint('Cash drawer error: $e');
      return false;
    }
  }

  /// Print receipt and open cash drawer (for cash payments or cash-out transactions)
  static Future<bool> printReceiptAndOpenDrawer(Map<String, dynamic> transaction) async {
    // Open drawer FIRST for cash payments OR cash-out transactions (cash leaves drawer)
    final isCashPayment = transaction['paymentMethod'] == 'cash';
    final hasCashOut = transaction['hasCashOut'] == true;

    if (isCashPayment || hasCashOut) {
      // Open drawer first so cashier can get cash ready
      await openCashDrawer();
      // Small delay to ensure drawer command is sent before printing starts
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Then print receipt
    final printSuccess = await printReceipt(transaction);

    return printSuccess;
  }

  /// Test different cash drawer commands for debugging
  /// Call this to try various command formats
  static Future<void> testCashDrawerCommands() async {
    final connected = await _ensureFreshConnection();
    if (!connected) {
      debugPrint('Not connected - cannot test');
      return;
    }

    debugPrint('');
    debugPrint('╔═══════════════════════════════════════╗');
    debugPrint('║   CASH DRAWER COMMAND TEST            ║');
    debugPrint('╚═══════════════════════════════════════╝');

    // Test 1: With init + LF (like Loyverse might do)
    debugPrint('\n[TEST 1] ESC @ + ESC p + LF (embedded in print job)');
    var cmd = [0x1B, 0x40, 0x1B, 0x70, 0x00, 0x19, 0xFA, 0x0A];
    debugPrint('Bytes: ${cmd.map((b) => '0x${b.toRadixString(16).toUpperCase()}').join(' ')}');
    var result = await PrintBluetoothThermal.writeBytes(cmd);
    debugPrint('Result: $result');
    await Future.delayed(const Duration(seconds: 3));

    // Test 2: Pin 1 with init
    debugPrint('\n[TEST 2] ESC @ + ESC p Pin 1 + LF');
    cmd = [0x1B, 0x40, 0x1B, 0x70, 0x01, 0x19, 0xFA, 0x0A];
    debugPrint('Bytes: ${cmd.map((b) => '0x${b.toRadixString(16).toUpperCase()}').join(' ')}');
    result = await PrintBluetoothThermal.writeBytes(cmd);
    debugPrint('Result: $result');
    await Future.delayed(const Duration(seconds: 3));

    // Test 3: Just ESC p (standalone)
    debugPrint('\n[TEST 3] Standalone ESC p');
    cmd = [0x1B, 0x70, 0x00, 0x19, 0xFA];
    debugPrint('Bytes: ${cmd.map((b) => '0x${b.toRadixString(16).toUpperCase()}').join(' ')}');
    result = await PrintBluetoothThermal.writeBytes(cmd);
    debugPrint('Result: $result');
    await Future.delayed(const Duration(seconds: 3));

    // Test 4: DLE DC4 (alternative command)
    debugPrint('\n[TEST 4] DLE DC4 command');
    cmd = [0x10, 0x14, 0x01, 0x00, 0x01];
    debugPrint('Bytes: ${cmd.map((b) => '0x${b.toRadixString(16).toUpperCase()}').join(' ')}');
    result = await PrintBluetoothThermal.writeBytes(cmd);
    debugPrint('Result: $result');
    await Future.delayed(const Duration(seconds: 3));

    // Test 5: Longer timings
    debugPrint('\n[TEST 5] Longer pulse (200ms ON, 500ms OFF)');
    cmd = [0x1B, 0x40, 0x1B, 0x70, 0x00, 0x64, 0xFA, 0x0A];
    debugPrint('Bytes: ${cmd.map((b) => '0x${b.toRadixString(16).toUpperCase()}').join(' ')}');
    result = await PrintBluetoothThermal.writeBytes(cmd);
    debugPrint('Result: $result');

    debugPrint('\n═══════════════════════════════════════');
    debugPrint('TEST COMPLETE - Did any test open the drawer?');
    debugPrint('═══════════════════════════════════════');
  }

  /// Dispose resources
  static void dispose() {
    _stopHeartbeat();
    _cashDrawerTimer?.cancel();
    _connectionStatusController.close();
    _cashDrawerStatusController.close();
  }
}
