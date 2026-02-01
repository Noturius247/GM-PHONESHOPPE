import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/printer_service.dart';

class PrinterSettingsDialog extends StatefulWidget {
  const PrinterSettingsDialog({super.key});

  @override
  State<PrinterSettingsDialog> createState() => _PrinterSettingsDialogState();
}

class _PrinterSettingsDialogState extends State<PrinterSettingsDialog> {
  static const Color _bgColor = Color(0xFF1A1A2E);
  static const Color _cardColor = Color(0xFF16213E);
  static const Color _accentColor = Color(0xFF00D9FF);
  static const Color _textPrimary = Color(0xFFEAEAEA);
  static const Color _textSecondary = Color(0xFF8B8B8B);

  List<BluetoothInfo> _devices = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isPrinting = false;
  StreamSubscription<List<BluetoothInfo>>? _scanSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  bool _isConnected = false;
  BluetoothInfo? _connectedDevice;

  @override
  void initState() {
    super.initState();
    _isConnected = PrinterService.isConnected;
    _connectedDevice = PrinterService.connectedDevice;
    _connectionSubscription =
        PrinterService.connectionStatusStream.listen((connected) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
          _connectedDevice = PrinterService.connectedDevice;
        });
      }
    });
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    PrinterService.stopScan();
    super.dispose();
  }

  Future<bool> _requestBluetoothPermissions() async {
    final connectStatus = await Permission.bluetoothConnect.request();
    final scanStatus = await Permission.bluetoothScan.request();

    if (connectStatus.isDenied || scanStatus.isDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth permissions are required to find printers'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return false;
    }

    if (connectStatus.isPermanentlyDenied || scanStatus.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Bluetooth permissions denied. Please enable in Settings.'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Open Settings',
              textColor: Colors.white,
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      }
      return false;
    }

    return true;
  }

  Future<void> _startScan() async {
    // Request runtime Bluetooth permissions (required on Android 12+)
    final hasPermissions = await _requestBluetoothPermissions();
    if (!hasPermissions) return;

    final isAvailable = await PrinterService.isBluetoothAvailable();
    if (!isAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth is not available on this device'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final isOn = await PrinterService.isBluetoothOn();
    if (!isOn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please turn on Bluetooth'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() {
      _isScanning = true;
      _devices = [];
    });

    // Get paired devices (this package uses paired devices instead of scanning)
    final devices = await PrinterService.getPairedDevices();

    if (mounted) {
      setState(() {
        _devices = devices;
        _isScanning = false;
      });
    }
  }

  Future<void> _connectToDevice(BluetoothInfo device) async {
    setState(() => _isConnecting = true);

    final success = await PrinterService.connectToDevice(device);

    if (mounted) {
      setState(() => _isConnecting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Connected to ${device.name}'
                : 'Failed to connect to ${device.name}',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _disconnect() async {
    await PrinterService.disconnect();
  }

  Future<void> _forgetPrinter() async {
    await PrinterService.forgetSavedPrinter();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Printer forgotten'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _printTest() async {
    setState(() => _isPrinting = true);

    final success = await PrinterService.printTestReceipt();

    if (mounted) {
      setState(() => _isPrinting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Test receipt printed!' : 'Failed to print test receipt',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _cardColor,
      title: Row(
        children: [
          Icon(
            _isConnected ? Icons.print : Icons.print_disabled,
            color: _isConnected ? Colors.green : _textSecondary,
          ),
          const SizedBox(width: 8),
          const Text('Printer Settings', style: TextStyle(color: _textPrimary)),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Connection Status
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _bgColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isConnected
                        ? Colors.green.withValues(alpha: 0.5)
                        : _textSecondary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isConnected ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isConnected ? 'Connected' : 'Not Connected',
                            style: TextStyle(
                              color: _isConnected ? Colors.green : _textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_isConnected && _connectedDevice != null)
                            Text(
                              _connectedDevice!.name ?? 'Unknown Device',
                              style: TextStyle(
                                color: _textSecondary,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_isConnected) ...[
                      IconButton(
                        icon: _isPrinting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _accentColor,
                                ),
                              )
                            : const Icon(Icons.print, color: _accentColor),
                        onPressed: _isPrinting ? null : _printTest,
                        tooltip: 'Print Test',
                      ),
                      IconButton(
                        icon:
                            const Icon(Icons.link_off, color: Colors.redAccent),
                        onPressed: _disconnect,
                        tooltip: 'Disconnect',
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Scan Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Available Devices',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isScanning || _isConnecting ? null : _startScan,
                    icon: _isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _accentColor,
                            ),
                          )
                        : const Icon(Icons.refresh, size: 16),
                    label: Text(_isScanning ? 'Scanning...' : 'Scan'),
                    style: TextButton.styleFrom(foregroundColor: _accentColor),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Device List
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: _bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _devices.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bluetooth_searching,
                                color: _textSecondary,
                                size: 32,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isScanning
                                    ? 'Searching for printers...'
                                    : 'Tap Scan to find printers',
                                style: TextStyle(color: _textSecondary),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Make sure your T58W printer is powered on',
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _devices.length,
                        itemBuilder: (context, index) {
                          final device = _devices[index];
                          final isCurrentDevice =
                              _connectedDevice?.macAdress == device.macAdress;

                          return ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.print,
                              color: isCurrentDevice
                                  ? Colors.green
                                  : _textSecondary,
                            ),
                            title: Text(
                              device.name,
                              style: TextStyle(
                                color: _textPrimary,
                                fontWeight: isCurrentDevice
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              device.macAdress,
                              style: TextStyle(
                                color: _textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            trailing: isCurrentDevice
                                ? const Icon(Icons.check, color: Colors.green)
                                : _isConnecting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: _accentColor,
                                        ),
                                      )
                                    : TextButton(
                                        onPressed: () =>
                                            _connectToDevice(device),
                                        child: const Text('Connect'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: _accentColor,
                                        ),
                                      ),
                          );
                        },
                      ),
              ),

              // Instructions
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.blue[300], size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Connection Guide',
                          style: TextStyle(
                            color: Colors.blue[300],
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. Turn on the printer (wait for boot)\n'
                      '2. Enable Bluetooth on your device\n'
                      '3. Pair with your printer (PIN: 0000)\n'
                      '4. Tap Scan and connect',
                      style: TextStyle(color: _textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),

              if (_isConnected) ...[
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    onPressed: _forgetPrinter,
                    icon: const Icon(Icons.delete_outline,
                        size: 16, color: Colors.redAccent),
                    label: const Text('Forget Saved Printer'),
                    style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close', style: TextStyle(color: _textSecondary)),
        ),
      ],
    );
  }
}

/// Quick printer status button widget for the app bar
class PrinterStatusButton extends StatefulWidget {
  final VoidCallback? onTap;

  const PrinterStatusButton({super.key, this.onTap});

  @override
  State<PrinterStatusButton> createState() => _PrinterStatusButtonState();
}

class _PrinterStatusButtonState extends State<PrinterStatusButton> {
  bool _isConnected = false;
  StreamSubscription<bool>? _subscription;

  @override
  void initState() {
    super.initState();
    _isConnected = PrinterService.isConnected;
    _subscription = PrinterService.connectionStatusStream.listen((connected) {
      if (mounted) {
        setState(() => _isConnected = connected);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _isConnected ? Icons.print : Icons.print_disabled,
        color: _isConnected ? Colors.green : Colors.white70,
        size: 20,
      ),
      onPressed: widget.onTap ??
          () {
            showDialog(
              context: context,
              builder: (context) => const PrinterSettingsDialog(),
            );
          },
      tooltip: _isConnected ? 'Printer Connected' : 'Printer Settings',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}
