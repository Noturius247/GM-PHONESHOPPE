import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart' show BluetoothInfo;

/// Service for managing Bluetooth thermal printer (T58W ESC/POS)
/// Paper width: 58mm, Print width: 48mm (384 dots at 203 dpi)
class PrinterService {
  static String? _connectedAddress;
  static String? _connectedName;
  static bool _isConnected = false;
  static const String _printerAddressKey = 'saved_printer_address';
  static const String _printerNameKey = 'saved_printer_name';

  // Heartbeat timer for connection monitoring
  static Timer? _heartbeatTimer;
  static const int _heartbeatIntervalSeconds = 15;
  static int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;

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

    // Try to reconnect to saved printer
    if (!_isConnected) {
      await _tryReconnectSavedPrinter();
    }

    // Start heartbeat monitoring
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

  /// Check connection and attempt reconnect if needed
  static Future<void> _checkConnectionAndReconnect() async {
    final actualStatus = await PrintBluetoothThermal.connectionStatus;

    // Connection state changed
    if (actualStatus != _isConnected) {
      _isConnected = actualStatus;
      _connectionStatusController.add(_isConnected);

      // Lost connection - try to reconnect
      if (!_isConnected && _connectedAddress != null) {
        debugPrint('Printer connection lost, attempting reconnect...');
        await _attemptReconnect();
      }
    }

    // Send keepalive if connected (prevents idle disconnect)
    if (_isConnected) {
      await _sendKeepalive();
    }
  }

  /// Attempt to reconnect to the last connected printer
  static Future<bool> _attemptReconnect() async {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('Max reconnect attempts reached');
      _reconnectAttempts = 0;
      return false;
    }

    _reconnectAttempts++;
    debugPrint('Reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts');

    try {
      // Try saved printer first
      final success = await _tryReconnectSavedPrinter();
      if (success) {
        _reconnectAttempts = 0;
        debugPrint('Reconnected successfully');
        return true;
      }
    } catch (e) {
      debugPrint('Reconnect failed: $e');
    }

    return false;
  }

  /// Send a keepalive command to prevent idle disconnect
  static Future<void> _sendKeepalive() async {
    try {
      // Send empty status query (doesn't print anything)
      // ESC v - Transmit printer status
      await PrintBluetoothThermal.writeBytes([0x1B, 0x76]);
    } catch (e) {
      // Keepalive failed - connection may be dead
      debugPrint('Keepalive failed: $e');
      _isConnected = false;
      _connectionStatusController.add(false);
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
        _reconnectAttempts = 0;
        _connectionStatusController.add(true);

        // Start heartbeat to maintain connection
        _startHeartbeat();

        if (savePreference) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_printerAddressKey, device.macAdress);
          await prefs.setString(_printerNameKey, device.name ?? '');
        }

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
      _reconnectAttempts = 0;
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

  /// Update connection status
  static Future<void> updateConnectionStatus() async {
    _isConnected = await PrintBluetoothThermal.connectionStatus;
    _connectionStatusController.add(_isConnected);
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
  static Future<bool> printReceipt(Map<String, dynamic> transaction) async {
    // Update connection status first
    await updateConnectionStatus();

    if (!_isConnected) {
      debugPrint('Printer not connected');
      return false;
    }

    try {
      final bytes = _buildReceiptBytes(transaction);
      final result = await PrintBluetoothThermal.writeBytes(bytes);
      return result;
    } catch (e) {
      debugPrint('Print error: $e');
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
  static Future<bool> printTestReceipt() async {
    await updateConnectionStatus();

    if (!_isConnected) {
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
      return result;
    } catch (e) {
      debugPrint('Test print error: $e');
      return false;
    }
  }

  /// Open the cash drawer connected to the printer's RJ11 port
  static Future<bool> openCashDrawer({int pin = 0}) async {
    await updateConnectionStatus();

    if (!_isConnected) {
      debugPrint('Printer not connected - cannot open cash drawer');
      return false;
    }

    try {
      // ESC p m t1 t2 command
      final List<int> command = [0x1B, 0x70, pin, 25, 250];
      final result = await PrintBluetoothThermal.writeBytes(command);
      debugPrint('Cash drawer command sent');

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
    final printSuccess = await printReceipt(transaction);

    // Open drawer for cash payments OR cash-out transactions (cash leaves drawer)
    final isCashPayment = transaction['paymentMethod'] == 'cash';
    final hasCashOut = transaction['hasCashOut'] == true;

    if (isCashPayment || hasCashOut) {
      if (!printSuccess) {
        // Print failed — try sending drawer command directly without
        // re-checking connection (the connection may still be alive even
        // though the print reported failure due to no paper).
        try {
          final List<int> command = [0x1B, 0x70, 0, 25, 250];
          final result = await PrintBluetoothThermal.writeBytes(command);
          if (result) {
            _isCashDrawerOpen = true;
            _cashDrawerStatusController.add(true);
            _cashDrawerTimer?.cancel();
            _cashDrawerTimer = Timer(
              const Duration(seconds: cashDrawerTimeoutSeconds),
              markCashDrawerClosed,
            );
          }
        } catch (_) {
          debugPrint('Cash drawer fallback failed');
        }
      } else {
        await openCashDrawer();
      }
    }

    return printSuccess;
  }

  /// Dispose resources
  static void dispose() {
    _stopHeartbeat();
    _cashDrawerTimer?.cancel();
    _connectionStatusController.close();
    _cashDrawerStatusController.close();
  }
}
