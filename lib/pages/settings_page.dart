import 'dart:async';
import 'package:flutter/material.dart';
import '../services/printer_service.dart';
import '../services/pos_settings_service.dart';
import '../services/auth_service.dart';
import '../services/staff_pin_service.dart';
import '../services/firebase_database_service.dart';
import '../services/cache_service.dart';

class SettingsPage extends StatefulWidget {
  final bool isAdmin;
  const SettingsPage({super.key, this.isAdmin = false});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // POS Settings
  bool _vatEnabled = true;
  double _vatRate = 12.0;
  bool _vatInclusive = true;
  bool _isLoadingSettings = true;

  // Sort settings for services
  String _sortCignal = 'name_asc';
  String _sortSky = 'name_asc';
  String _sortSatellite = 'name_asc';
  String _sortGsat = 'name_asc';

  // Staff PIN (current user)
  String? _currentUserPin;
  String _currentUserEmail = '';
  String _currentUserName = '';
  String _currentUserId = '';
  bool _isLoadingPin = false;

  // POS Account PIN (admin only)
  String? _posAccountPin;
  String _posAccountEmail = '';
  String _posAccountName = '';
  String _posAccountUserId = '';
  bool _isLoadingPosPin = false;
  bool _posAccountExists = false;

  // Printer state
  bool _isPrinterConnected = false;
  BluetoothInfo? _connectedDevice;
  List<BluetoothInfo> _availableDevices = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isPrinting = false;
  StreamSubscription<bool>? _printerConnectionSubscription;
  StreamSubscription<List<BluetoothInfo>>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadUserPin();
    if (widget.isAdmin) {
      _loadPosAccountPin();
    }
    _initPrinter();
  }

  @override
  void dispose() {
    _printerConnectionSubscription?.cancel();
    _scanSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await POSSettingsService.getSettings();
    if (mounted) {
      setState(() {
        _vatEnabled = settings['vatEnabled'] ?? true;
        _vatRate = (settings['vatRate'] as num?)?.toDouble() ?? 12.0;
        _vatInclusive = settings['vatInclusive'] ?? true;
        _sortCignal = settings['sortCignal'] ?? 'name_asc';
        _sortSky = settings['sortSky'] ?? 'name_asc';
        _sortSatellite = settings['sortSatellite'] ?? 'name_asc';
        _sortGsat = settings['sortGsat'] ?? 'name_asc';
        _isLoadingSettings = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    await POSSettingsService.updateSettings({
      'vatEnabled': _vatEnabled,
      'vatRate': _vatRate,
      'vatInclusive': _vatInclusive,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('POS Settings saved'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _loadUserPin() async {
    final user = await AuthService.getCurrentUser();
    if (user == null || !mounted) return;

    final email = user['email'] as String? ?? '';
    final name = user['name'] as String? ?? '';

    // Get userId from Firebase (sanitized email key)
    final userId = email.replaceAll('.', ',');

    setState(() {
      _currentUserEmail = email;
      _currentUserName = name;
      _currentUserId = userId;
      _isLoadingPin = true;
    });

    final pin = await StaffPinService.getUserPin(userId);
    if (mounted) {
      setState(() {
        _currentUserPin = pin;
        _isLoadingPin = false;
      });
    }
  }

  Future<void> _loadPosAccountPin() async {
    if (!widget.isAdmin) return;

    setState(() => _isLoadingPosPin = true);

    try {
      // Get all users and find the POS account
      final users = await FirebaseDatabaseService.getAllUsers();
      final posUser = users.firstWhere(
        (u) => u['role'] == 'pos',
        orElse: () => <String, dynamic>{},
      );

      if (posUser.isNotEmpty && mounted) {
        final email = posUser['email'] as String? ?? '';
        final name = posUser['name'] as String? ?? '';
        // Use sanitized email as userId for PIN lookup
        final odooUserId = email.replaceAll('.', ',');

        final pin = await StaffPinService.getUserPin(odooUserId);

        if (mounted) {
          setState(() {
            _posAccountExists = true;
            _posAccountEmail = email;
            _posAccountName = name;
            _posAccountUserId = odooUserId;
            _posAccountPin = pin;
            _isLoadingPosPin = false;
          });
        }
      } else if (mounted) {
        setState(() {
          _posAccountExists = false;
          _isLoadingPosPin = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading POS account PIN: $e');
      if (mounted) {
        setState(() => _isLoadingPosPin = false);
      }
    }
  }

  Future<void> _showSetPinDialog() async {
    final controller = TextEditingController(text: _currentUserPin ?? '');
    String? errorText;

    final newPin = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Row(
            children: [
              Icon(Icons.pin, color: Color(0xFF2ECC71)),
              SizedBox(width: 8),
              Text('Set Staff PIN', style: TextStyle(color: Colors.black)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter a 4-digit PIN for: $_currentUserName',
                style: const TextStyle(color: Colors.black),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 4,
                autofocus: true,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 24,
                  letterSpacing: 12,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '0000',
                  hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.3)),
                  errorText: errorText,
                  errorStyle: const TextStyle(color: Colors.redAccent),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF2ECC71), width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.redAccent),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.redAccent),
                  ),
                  counterStyle: const TextStyle(color: Colors.black54),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.black87)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2ECC71)),
              onPressed: () async {
                final pin = controller.text.trim();
                if (!StaffPinService.isValidPinFormat(pin)) {
                  setDialogState(() => errorText = 'PIN must be exactly 4 digits');
                  return;
                }
                final taken = await StaffPinService.isPinTaken(pin, excludeUserId: _currentUserId);
                if (taken) {
                  setDialogState(() => errorText = 'This PIN is already in use');
                  return;
                }
                Navigator.pop(context, pin);
              },
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (newPin == null || !mounted) return;

    // Check connectivity before setting PIN
    final hasConnection = await CacheService.hasConnectivity();
    if (!hasConnection) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No internet connection. Cannot set PIN offline.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final error = await StaffPinService.setPin(
      userId: _currentUserId,
      email: _currentUserEmail,
      name: _currentUserName,
      pin: newPin,
    );

    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
    } else {
      setState(() => _currentUserPin = newPin);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Staff PIN saved'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _showSetPosPinDialog() async {
    if (!_posAccountExists) return;

    final controller = TextEditingController(text: _posAccountPin ?? '');
    String? errorText;

    final newPin = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Row(
            children: [
              Icon(Icons.point_of_sale, color: Color(0xFFE67E22)),
              SizedBox(width: 8),
              Text('Set POS Account PIN', style: TextStyle(color: Colors.black)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter a 4-digit PIN for POS Account:\n$_posAccountName',
                style: const TextStyle(color: Colors.black),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _posAccountEmail,
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 4,
                autofocus: true,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 24,
                  letterSpacing: 12,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '0000',
                  hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.3)),
                  errorText: errorText,
                  errorStyle: const TextStyle(color: Colors.redAccent),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE67E22), width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.redAccent),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.redAccent),
                  ),
                  counterStyle: const TextStyle(color: Colors.black54),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.black87)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE67E22)),
              onPressed: () async {
                final pin = controller.text.trim();
                if (!StaffPinService.isValidPinFormat(pin)) {
                  setDialogState(() => errorText = 'PIN must be exactly 4 digits');
                  return;
                }
                final taken = await StaffPinService.isPinTaken(pin, excludeUserId: _posAccountUserId);
                if (taken) {
                  setDialogState(() => errorText = 'This PIN is already in use');
                  return;
                }
                Navigator.pop(context, pin);
              },
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (newPin == null || !mounted) return;

    // Check connectivity before setting PIN
    final hasConnection = await CacheService.hasConnectivity();
    if (!hasConnection) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No internet connection. Cannot set PIN offline.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final error = await StaffPinService.setPin(
      userId: _posAccountUserId,
      email: _posAccountEmail,
      name: _posAccountName,
      pin: newPin,
    );

    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
    } else {
      setState(() => _posAccountPin = newPin);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('POS Account PIN saved'), backgroundColor: Colors.green),
      );
    }
  }

  void _initPrinter() {
    PrinterService.initialize();
    _isPrinterConnected = PrinterService.isConnected;
    _connectedDevice = PrinterService.connectedDevice;

    _printerConnectionSubscription =
        PrinterService.connectionStatusStream.listen((connected) {
      if (mounted) {
        setState(() {
          _isPrinterConnected = connected;
          _connectedDevice = PrinterService.connectedDevice;
        });
      }
    });
  }

  Future<void> _startScan() async {
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
      _availableDevices = [];
    });

    // Get paired devices (this package uses paired devices instead of scanning)
    final devices = await PrinterService.getPairedDevices();

    if (mounted) {
      setState(() {
        _availableDevices = devices;
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

  Future<void> _disconnectPrinter() async {
    await PrinterService.disconnect();
  }

  Future<void> _printTestReceipt() async {
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

  Future<void> _openCashDrawer() async {
    final success = await PrinterService.openCashDrawer();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Cash drawer opened!' : 'Failed to open cash drawer',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A0A0A),
            Color(0xFF2A1A1A),
          ],
        ),
      ),
      child: _isLoadingSettings
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE67E22)))
          : RefreshIndicator(
              onRefresh: () async {
                await _loadSettings();
                await _loadUserPin();
                await _loadPosAccountPin();
              },
              color: const Color(0xFFE67E22),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(isMobile ? 16 : 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Settings',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isMobile ? 32 : 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // POS Settings Section
                  _buildSectionHeader('POS Settings', Icons.point_of_sale, const [Color(0xFFE67E22), Color(0xFFD35400)]),
                  const SizedBox(height: 12),
                  _buildSettingsCard(
                    children: [
                      // VAT Enabled Toggle
                      _buildSettingsTile(
                        icon: Icons.receipt_long,
                        iconGradient: const [Color(0xFFE67E22), Color(0xFFD35400)],
                        title: 'Enable VAT',
                        subtitle: 'Show VAT calculation on receipts',
                        trailing: Switch(
                          value: _vatEnabled,
                          onChanged: (value) {
                            setState(() => _vatEnabled = value);
                            _saveSettings();
                          },
                          activeColor: const Color(0xFF2ECC71),
                        ),
                      ),
                      if (_vatEnabled) ...[
                        Divider(color: Colors.white.withValues(alpha: 0.1)),
                        // VAT Rate
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'VAT Rate',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Slider(
                                      value: _vatRate,
                                      min: 0,
                                      max: 25,
                                      divisions: 25,
                                      label: '${_vatRate.toStringAsFixed(0)}%',
                                      activeColor: const Color(0xFFE67E22),
                                      inactiveColor: Colors.white.withValues(alpha: 0.3),
                                      onChanged: (value) {
                                        setState(() => _vatRate = value);
                                      },
                                      onChangeEnd: (value) => _saveSettings(),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE67E22).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${_vatRate.toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                        color: Color(0xFFE67E22),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Divider(color: Colors.white.withValues(alpha: 0.1)),
                        // VAT Inclusive Toggle
                        _buildSettingsTile(
                          icon: Icons.calculate,
                          iconGradient: const [Color(0xFF3498DB), Color(0xFF2980B9)],
                          title: 'VAT Inclusive Pricing',
                          subtitle: _vatInclusive
                              ? 'VAT is included in selling price'
                              : 'VAT is added on top of price',
                          trailing: Switch(
                            value: _vatInclusive,
                            onChanged: (value) {
                              setState(() => _vatInclusive = value);
                              _saveSettings();
                            },
                            activeColor: const Color(0xFF2ECC71),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Service Sort Settings Section
                  _buildSectionHeader('Service Sort Settings', Icons.sort, const [Color(0xFF9B59B6), Color(0xFF8E44AD)]),
                  const SizedBox(height: 12),
                  _buildSettingsCard(
                    children: [
                      _buildSortDropdown(
                        label: 'Cignal',
                        icon: Icons.tv,
                        iconGradient: const [Color(0xFF8B1A1A), Color(0xFF5C0F0F)],
                        value: _sortCignal,
                        onChanged: (value) async {
                          setState(() => _sortCignal = value!);
                          await POSSettingsService.setSortSetting('cignal', value!);
                        },
                      ),
                      Divider(color: Colors.white.withValues(alpha: 0.1)),
                      _buildSortDropdown(
                        label: 'Sky',
                        icon: Icons.satellite_alt,
                        iconGradient: const [Color(0xFF2980B9), Color(0xFF1A5276)],
                        value: _sortSky,
                        onChanged: (value) async {
                          setState(() => _sortSky = value!);
                          await POSSettingsService.setSortSetting('sky', value!);
                        },
                      ),
                      Divider(color: Colors.white.withValues(alpha: 0.1)),
                      _buildSortDropdown(
                        label: 'Satellite',
                        icon: Icons.settings_input_antenna,
                        iconGradient: const [Color(0xFFFF6B35), Color(0xFFCC5528)],
                        value: _sortSatellite,
                        onChanged: (value) async {
                          setState(() => _sortSatellite = value!);
                          await POSSettingsService.setSortSetting('satellite', value!);
                        },
                      ),
                      Divider(color: Colors.white.withValues(alpha: 0.1)),
                      _buildSortDropdown(
                        label: 'GSat',
                        icon: Icons.router,
                        iconGradient: const [Color(0xFF27AE60), Color(0xFF1E8449)],
                        value: _sortGsat,
                        onChanged: (value) async {
                          setState(() => _sortGsat = value!);
                          await POSSettingsService.setSortSetting('gsat', value!);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Printer Settings Section
                  _buildSectionHeader('Printer Settings', Icons.print, const [Color(0xFF3498DB), Color(0xFF2980B9)]),
                  const SizedBox(height: 12),
                  _buildSettingsCard(
                    children: [
                      // Printer Connection Status
                      Container(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: _isPrinterConnected
                                      ? [const Color(0xFF2ECC71), const Color(0xFF27AE60)]
                                      : [const Color(0xFF95A5A6), const Color(0xFF7F8C8D)],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _isPrinterConnected ? Icons.print : Icons.print_disabled,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isPrinterConnected ? 'Printer Connected' : 'No Printer Connected',
                                    style: TextStyle(
                                      color: _isPrinterConnected ? const Color(0xFF2ECC71) : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (_isPrinterConnected && _connectedDevice != null)
                                    Text(
                                      _connectedDevice!.name,
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                                    ),
                                ],
                              ),
                            ),
                            if (_isPrinterConnected) ...[
                              IconButton(
                                icon: _isPrinting
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF3498DB),
                                        ),
                                      )
                                    : const Icon(Icons.print, color: Color(0xFF3498DB)),
                                onPressed: _isPrinting ? null : _printTestReceipt,
                                tooltip: 'Print Test',
                              ),
                              if (widget.isAdmin)
                                IconButton(
                                  icon: const Icon(Icons.point_of_sale, color: Color(0xFF2ECC71)),
                                  onPressed: _openCashDrawer,
                                  tooltip: 'Open Cash Drawer',
                                ),
                              IconButton(
                                icon: const Icon(Icons.link_off, color: Colors.redAccent),
                                onPressed: _disconnectPrinter,
                                tooltip: 'Disconnect',
                              ),
                            ],
                          ],
                        ),
                      ),
                      Divider(color: Colors.white.withValues(alpha: 0.1)),
                      // Scan for Printers
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Available Printers',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                                TextButton.icon(
                                  onPressed: _isScanning || _isConnecting ? null : _startScan,
                                  icon: _isScanning
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFF3498DB),
                                          ),
                                        )
                                      : const Icon(Icons.refresh, size: 18),
                                  label: Text(_isScanning ? 'Scanning...' : 'Scan'),
                                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF3498DB)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 200),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A0A0A),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: _availableDevices.isEmpty
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.bluetooth_searching,
                                              color: Colors.white.withValues(alpha: 0.5),
                                              size: 32,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              _isScanning
                                                  ? 'Searching for printers...'
                                                  : 'Tap Scan to find printers',
                                              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: _availableDevices.length,
                                      itemBuilder: (context, index) {
                                        final device = _availableDevices[index];
                                        final isCurrentDevice =
                                            _connectedDevice?.macAdress == device.macAdress;

                                        return ListTile(
                                          leading: Icon(
                                            Icons.print,
                                            color: isCurrentDevice
                                                ? const Color(0xFF2ECC71)
                                                : Colors.white.withValues(alpha: 0.6),
                                          ),
                                          title: Text(
                                            device.name,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: isCurrentDevice
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                          subtitle: Text(
                                            device.macAdress,
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.5),
                                              fontSize: 12,
                                            ),
                                          ),
                                          trailing: isCurrentDevice
                                              ? const Icon(Icons.check, color: Color(0xFF2ECC71))
                                              : _isConnecting
                                                  ? const SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Color(0xFF3498DB),
                                                      ),
                                                    )
                                                  : TextButton(
                                                      onPressed: () => _connectToDevice(device),
                                                      style: TextButton.styleFrom(
                                                        foregroundColor: const Color(0xFF3498DB),
                                                      ),
                                                      child: const Text('Connect'),
                                                    ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                      // Connection Guide
                      Divider(color: Colors.white.withValues(alpha: 0.1)),
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3498DB).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF3498DB).withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, color: const Color(0xFF3498DB).withValues(alpha: 0.8), size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Connection Guide (T58W Printer)',
                                  style: TextStyle(
                                    color: const Color(0xFF3498DB).withValues(alpha: 0.9),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '1. Turn on the printer and wait for boot\n'
                              '2. Enable Bluetooth on your device\n'
                              '3. Pair with "JP58H" using PIN: 0000\n'
                              '4. Tap Scan and connect to printer',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isPrinterConnected) ...[
                        Divider(color: Colors.white.withValues(alpha: 0.1)),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: TextButton.icon(
                              onPressed: _forgetPrinter,
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Forget Saved Printer'),
                              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Staff PIN Section - User's own PIN
                  _buildSectionHeader(
                    'Staff PIN',
                    Icons.pin,
                    const [Color(0xFF2ECC71), Color(0xFF27AE60)],
                  ),
                  const SizedBox(height: 12),
                  _buildSettingsCard(
                    children: [
                      _buildSettingsTile(
                        icon: Icons.lock,
                        iconGradient: const [Color(0xFF2ECC71), Color(0xFF27AE60)],
                        title: _isLoadingPin
                            ? 'Loading...'
                            : _currentUserPin != null
                                ? 'PIN: ****'
                                : 'No PIN Set',
                        subtitle: _currentUserPin != null
                            ? 'Tap Change to update your 4-digit PIN'
                            : 'Set a 4-digit PIN for POS transactions',
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2ECC71),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                          onPressed: _isLoadingPin ? null : _showSetPinDialog,
                          child: Text(_currentUserPin != null ? 'Change' : 'Set PIN'),
                        ),
                      ),
                    ],
                  ),

                  // POS Account PIN Section - Admin only
                  if (widget.isAdmin) ...[
                    const SizedBox(height: 32),
                    _buildSectionHeader(
                      'POS Account PIN',
                      Icons.point_of_sale,
                      const [Color(0xFFE67E22), Color(0xFFD35400)],
                    ),
                    const SizedBox(height: 12),
                    _buildSettingsCard(
                      children: [
                        _buildSettingsTile(
                          icon: Icons.point_of_sale,
                          iconGradient: const [Color(0xFFE67E22), Color(0xFFD35400)],
                          title: _isLoadingPosPin
                              ? 'Loading...'
                              : !_posAccountExists
                                  ? 'No POS Account'
                                  : _posAccountPin != null
                                      ? 'PIN: ****'
                                      : 'No PIN Set',
                          subtitle: !_posAccountExists
                              ? 'Create a POS account from All Users page'
                              : _posAccountPin != null
                                  ? 'POS Account: $_posAccountName'
                                  : 'Set a 4-digit PIN for the POS account',
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE67E22),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            ),
                            onPressed: (!_posAccountExists || _isLoadingPosPin)
                                ? null
                                : _showSetPosPinDialog,
                            child: Text(_posAccountPin != null ? 'Change' : 'Set PIN'),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Other Settings Section
                  _buildSectionHeader('General Settings', Icons.settings, const [Color(0xFF9B59B6), Color(0xFF8E44AD)]),
                  const SizedBox(height: 12),
                  _buildSettingsCard(
                    children: [
                      _buildSettingsTile(
                        icon: Icons.notifications,
                        iconGradient: const [Color(0xFF8B1A1A), Color(0xFF5C0F0F)],
                        title: 'Notifications',
                        subtitle: 'Manage notification preferences',
                        trailing: Switch(
                          value: true,
                          onChanged: (value) {},
                          activeColor: const Color(0xFF2ECC71),
                        ),
                      ),
                      Divider(color: Colors.white.withValues(alpha: 0.1)),
                      _buildSettingsTile(
                        icon: Icons.backup,
                        iconGradient: const [Color(0xFF1ABC9C), Color(0xFF16A085)],
                        title: 'Backup & Restore',
                        subtitle: 'Data management',
                        trailing: const Icon(Icons.chevron_right, color: Colors.white),
                        onTap: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, List<Color> gradient) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradient),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsCard({required List<Widget> children}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF2A1A1A),
              Color(0xFF1F1010),
            ],
          ),
        ),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required List<Color> iconGradient,
    required String title,
    required String subtitle,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: iconGradient),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _buildSortDropdown({
    required String label,
    required IconData icon,
    required List<Color> iconGradient,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: iconGradient),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButton<String>(
                    value: value,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF2A2A2A),
                    underline: const SizedBox(),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    items: POSSettingsService.sortOptions.map((option) {
                      return DropdownMenuItem<String>(
                        value: option['value'],
                        child: Text(option['label']!),
                      );
                    }).toList(),
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
