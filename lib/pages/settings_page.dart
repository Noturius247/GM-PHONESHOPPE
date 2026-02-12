import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/native_printer_service.dart';
import '../services/pos_settings_service.dart';
import '../services/auth_service.dart';
import '../services/staff_pin_service.dart';
import '../services/firebase_database_service.dart';
import '../services/cache_service.dart';
import '../services/offline_sync_service.dart';
import '../services/inventory_service.dart';
import '../utils/snackbar_utils.dart';

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
  double _cashDrawerOpeningBalance = 0.0;
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
  String? _connectedPrinterName;
  String? _connectedPrinterAddress;
  List<Map<String, String>> _availableDevices = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isPrinting = false;
  StreamSubscription<bool>? _printerConnectionSubscription;

  // Force Sync state
  bool _isForceSyncing = false;
  String _forceSyncMessage = '';
  int _forceSyncCurrent = 0;
  int _forceSyncTotal = 0;

  // Full Sync state
  bool _isFullSyncing = false;
  String _fullSyncMessage = '';
  String _fullSyncPhase = ''; // 'upload', 'clear', 'download', 'complete'

  // SKU Migration state
  bool _isRunningMigration = false;
  String _migrationMessage = '';
  int _migrationFixed = 0;

  // Keep Screen On (wakelock)
  bool _keepScreenOn = false;

  // Section expansion states (all collapsed by default)
  bool _posSettingsExpanded = false;
  bool _sortSettingsExpanded = false;
  bool _printerSettingsExpanded = false;
  bool _staffPinExpanded = false;
  bool _posAccountPinExpanded = false;
  bool _dataSyncExpanded = false;
  bool _skuMigrationExpanded = false;
  bool _generalSettingsExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadUserPin();
    if (widget.isAdmin) {
      _loadPosAccountPin();
    }
    _initPrinter();
    _loadKeepScreenOnSetting();
  }

  @override
  void dispose() {
    _printerConnectionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await POSSettingsService.getSettings();
    if (mounted) {
      setState(() {
        _vatEnabled = settings['vatEnabled'] ?? true;
        _vatRate = (settings['vatRate'] as num?)?.toDouble() ?? 12.0;
        _vatInclusive = settings['vatInclusive'] ?? true;
        _cashDrawerOpeningBalance = (settings['cashDrawerOpeningBalance'] as num?)?.toDouble() ?? 0.0;
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
      SnackBarUtils.showSuccess(context, 'POS Settings saved');
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
    final screenWidth = MediaQuery.of(context).size.width;

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
          content: SizedBox(
            width: screenWidth < 360 ? screenWidth * 0.9 : (screenWidth < 500 ? screenWidth * 0.85 : 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Enter a 4-digit PIN for: $_currentUserName',
                  style: const TextStyle(color: Colors.black),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  autofocus: true,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: screenWidth < 360 ? 18 : 24,
                    letterSpacing: screenWidth < 360 ? 8 : 12,
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
      SnackBarUtils.showError(context, 'No internet connection. Cannot set PIN offline.');
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
      SnackBarUtils.showError(context, error);
    } else {
      setState(() => _currentUserPin = newPin);
      SnackBarUtils.showSuccess(context, 'Staff PIN saved');
    }
  }

  Future<void> _showSetPosPinDialog() async {
    if (!_posAccountExists) return;

    final controller = TextEditingController(text: _posAccountPin ?? '');
    String? errorText;
    final screenWidth = MediaQuery.of(context).size.width;

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
          content: SizedBox(
            width: screenWidth < 360 ? screenWidth * 0.9 : (screenWidth < 500 ? screenWidth * 0.85 : 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Enter a 4-digit PIN for POS Account:\n$_posAccountName',
                  style: const TextStyle(color: Colors.black),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
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
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: screenWidth < 360 ? 18 : 24,
                    letterSpacing: screenWidth < 360 ? 8 : 12,
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
      SnackBarUtils.showError(context, 'No internet connection. Cannot set PIN offline.');
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
      SnackBarUtils.showError(context, error);
    } else {
      setState(() => _posAccountPin = newPin);
      SnackBarUtils.showSuccess(context, 'POS Account PIN saved');
    }
  }

  void _initPrinter() {
    NativePrinterService.initialize();
    _isPrinterConnected = NativePrinterService.isConnected;
    _connectedPrinterName = NativePrinterService.connectedName;
    _connectedPrinterAddress = NativePrinterService.connectedAddress;

    _printerConnectionSubscription =
        NativePrinterService.connectionStatusStream.listen((connected) {
      if (mounted) {
        setState(() {
          _isPrinterConnected = connected;
          _connectedPrinterName = NativePrinterService.connectedName;
          _connectedPrinterAddress = NativePrinterService.connectedAddress;
        });
      }
    });
  }

  Future<bool> _requestBluetoothPermissions() async {
    final connectStatus = await Permission.bluetoothConnect.request();
    final scanStatus = await Permission.bluetoothScan.request();

    if (connectStatus.isDenied || scanStatus.isDenied) {
      if (mounted) {
        SnackBarUtils.showWarning(context, 'Bluetooth permissions are required to find printers');
      }
      return false;
    }

    if (connectStatus.isPermanentlyDenied || scanStatus.isPermanentlyDenied) {
      if (mounted) {
        SnackBarUtils.showTopSnackBar(
          context,
          message: 'Bluetooth permissions denied. Please enable in Settings.',
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Open Settings',
            textColor: Colors.white,
            onPressed: () => openAppSettings(),
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

    final isAvailable = await NativePrinterService.isBluetoothAvailable();
    if (!isAvailable) {
      if (mounted) {
        SnackBarUtils.showError(context, 'Bluetooth is not available on this device');
      }
      return;
    }

    final isOn = await NativePrinterService.isBluetoothEnabled();
    if (!isOn) {
      if (mounted) {
        SnackBarUtils.showWarning(context, 'Please turn on Bluetooth');
      }
      return;
    }

    setState(() {
      _isScanning = true;
      _availableDevices = [];
    });

    // Get paired devices
    final devices = await NativePrinterService.getPairedDevices();

    if (mounted) {
      setState(() {
        _availableDevices = devices;
        _isScanning = false;
      });
    }
  }

  Future<void> _connectToDevice(Map<String, String> device) async {
    setState(() => _isConnecting = true);

    final address = device['address'] ?? '';
    final name = device['name'] ?? 'Unknown';
    final success = await NativePrinterService.connect(address, name: name);

    if (mounted) {
      setState(() => _isConnecting = false);

      if (success) {
        SnackBarUtils.showSuccess(context, 'Connected to $name');
      } else {
        SnackBarUtils.showError(context, 'Failed to connect to $name');
      }
    }
  }

  Future<void> _disconnectPrinter() async {
    await NativePrinterService.disconnect();
  }

  Future<void> _printTestReceipt() async {
    setState(() => _isPrinting = true);

    final success = await NativePrinterService.printTestReceipt();

    if (mounted) {
      setState(() => _isPrinting = false);

      if (success) {
        SnackBarUtils.showSuccess(context, 'Test receipt printed!');
      } else {
        SnackBarUtils.showError(context, 'Failed to print test receipt');
      }
    }
  }

  Future<void> _openCashDrawer() async {
    final success = await NativePrinterService.openCashDrawer();

    if (mounted) {
      if (success) {
        SnackBarUtils.showSuccess(context, 'Cash drawer opened!');
      } else {
        SnackBarUtils.showError(context, 'Failed to open cash drawer');
      }
    }
  }

  Future<void> _forgetPrinter() async {
    await NativePrinterService.forgetSavedPrinter();
    if (mounted) {
      SnackBarUtils.showWarning(context, 'Printer forgotten');
    }
  }

  Future<void> _forceSync() async {
    if (_isForceSyncing) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Row(
          children: [
            Icon(Icons.cloud_upload, color: Color(0xFF3498DB)),
            SizedBox(width: 8),
            Text('Force Sync', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'This will upload ALL local data to Firebase. This may take a while depending on the amount of data.\n\nContinue?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3498DB)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sync Now', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isForceSyncing = true;
      _forceSyncMessage = 'Starting sync...';
      _forceSyncCurrent = 0;
      _forceSyncTotal = 0;
    });

    final result = await OfflineSyncService.forceFullUpload(
      onProgress: (message, current, total) {
        if (mounted) {
          setState(() {
            _forceSyncMessage = message;
            _forceSyncCurrent = current;
            _forceSyncTotal = total;
          });
        }
      },
    );

    if (!mounted) return;

    setState(() {
      _isForceSyncing = false;
      _forceSyncMessage = '';
      _forceSyncCurrent = 0;
      _forceSyncTotal = 0;
    });

    if (result.success) {
      SnackBarUtils.showSuccess(context, result.message, duration: const Duration(seconds: 4));
    } else {
      SnackBarUtils.showError(context, result.message, duration: const Duration(seconds: 4));
    }
  }

  Future<void> _refreshFromFirebase() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Row(
          children: [
            Icon(Icons.cloud_download, color: Color(0xFF2ECC71)),
            SizedBox(width: 8),
            Text('Refresh from Firebase', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'This will:\n'
          '• Clear all local cached data\n'
          '• Download fresh data from Firebase\n'
          '• Fix inventory count discrepancies\n\n'
          'This may take a few moments. Continue?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2ECC71)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Refresh Now', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Show loading dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: const AlertDialog(
            backgroundColor: Color(0xFF2A2A2A),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF2ECC71)),
                SizedBox(height: 16),
                Text(
                  'Refreshing data from Firebase...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      );
    }

    try {
      // Clear all caches
      await CacheService.clearAllCache();

      // Force refresh from Firebase
      InventoryService.forceRefresh();

      // Re-initialize cache service
      await CacheService.initialize();

      if (!mounted) return;

      // Close loading dialog
      Navigator.pop(context);

      // Show success message with instruction
      SnackBarUtils.showSuccess(
        context,
        'Cache cleared successfully! Pull down to refresh on any page to load fresh data.',
        duration: const Duration(seconds: 5),
      );

    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      SnackBarUtils.showError(context, 'Error refreshing data: $e');
    }
  }

  Future<void> _fullBidirectionalSync() async {
    if (_isFullSyncing) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Row(
          children: [
            Icon(Icons.sync, color: Color(0xFF9B59B6)),
            SizedBox(width: 8),
            Text('Full Bi-Directional Sync', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'This will perform a complete sync:\n\n'
          '1️⃣ Upload all local changes to Firebase\n'
          '2️⃣ Clear local cache\n'
          '3️⃣ Download fresh data from Firebase\n'
          '4️⃣ Update all pages automatically\n\n'
          'This ensures your device has the absolute latest data.\n\n'
          'Continue?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9B59B6)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Full Sync', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isFullSyncing = true;
      _fullSyncPhase = 'upload';
      _fullSyncMessage = 'Uploading local changes...';
    });

    int uploadedCount = 0;
    int downloadedCount = 0;

    try {
      // Phase 1: Upload all local changes to Firebase
      setState(() {
        _fullSyncPhase = 'upload';
        _fullSyncMessage = 'Uploading local changes to Firebase...';
      });

      final uploadResult = await OfflineSyncService.forceFullUpload(
        onProgress: (message, current, total) {
          if (mounted) {
            setState(() {
              _fullSyncMessage = 'Uploading: $message ($current/$total)';
            });
          }
        },
      );

      if (!mounted) return;

      if (uploadResult.success) {
        uploadedCount = uploadResult.syncResult?.results?.values.fold<int>(
          0, (sum, r) => sum + r.syncedCount
        ) ?? 0;
      }

      // Phase 2: Clear local cache
      setState(() {
        _fullSyncPhase = 'clear';
        _fullSyncMessage = 'Clearing local cache...';
      });

      await Future.delayed(const Duration(milliseconds: 500)); // Brief pause for UX
      await CacheService.clearAllCache();

      if (!mounted) return;

      // Phase 3: Download fresh data from Firebase
      setState(() {
        _fullSyncPhase = 'download';
        _fullSyncMessage = 'Downloading fresh data from Firebase...';
      });

      // Force refresh from Firebase
      InventoryService.forceRefresh();

      // Re-initialize cache
      await CacheService.initialize();

      // Get fresh inventory count
      final freshItems = await InventoryService.getAllItems();
      downloadedCount = freshItems.length;

      if (!mounted) return;

      // Phase 4: Complete
      setState(() {
        _fullSyncPhase = 'complete';
        _fullSyncMessage = 'Sync complete!';
      });

      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _isFullSyncing = false;
        _fullSyncMessage = '';
        _fullSyncPhase = '';
      });

      // Show success dialog with summary
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF2ECC71), size: 28),
              SizedBox(width: 12),
              Text('Sync Complete!', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '✅ Uploaded: $uploadedCount items to Firebase',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                '✅ Downloaded: $downloadedCount items from Firebase',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2ECC71).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2ECC71).withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFF2ECC71), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your device now has the latest data from Firebase!',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2ECC71)),
              onPressed: () => Navigator.pop(context),
              child: const Text('Done', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isFullSyncing = false;
        _fullSyncMessage = '';
        _fullSyncPhase = '';
      });

      SnackBarUtils.showError(
        context,
        'Sync error: $e',
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<void> _runSkuMigration() async {
    if (_isRunningMigration) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Row(
          children: [
            Icon(Icons.autorenew, color: Color(0xFFE67E22)),
            SizedBox(width: 8),
            Text('Force SKU Migration', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'This will scan all inventory items and:\n\n'
          '• Find duplicate serial numbers (SKUs)\n'
          '• Generate new random SKUs for duplicates\n'
          '• Update them in the database\n'
          '• Log items that need label reprinting\n\n'
          'This operation is safe and can be run multiple times.\n\n'
          'Continue?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE67E22)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Run Migration', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isRunningMigration = true;
      _migrationMessage = 'Scanning for duplicate SKUs...';
      _migrationFixed = 0;
    });

    try {
      // Run the migration with force=true
      final report = await InventoryService.runDuplicateSkuMigration(force: true);

      if (!mounted) return;

      final success = report['success'] as bool? ?? false;
      final duplicatesFound = report['duplicatesFound'] as int? ?? 0;
      final itemsFixed = report['itemsFixed'] as int? ?? 0;
      final offline = report['offline'] as bool? ?? false;
      final lockedByOther = report['lockedByOther'] as bool? ?? false;

      setState(() {
        _isRunningMigration = false;
        _migrationMessage = '';
        _migrationFixed = itemsFixed;
      });

      // Show result dialog
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error,
                color: success ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C),
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                success ? 'Migration Complete!' : 'Migration Failed',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (offline)
                const Text(
                  '❌ Device is offline. Migration requires internet connection.',
                  style: TextStyle(color: Color(0xFFE74C3C), fontSize: 14),
                )
              else if (lockedByOther)
                const Text(
                  '⏳ Migration is already running on another device. Please wait.',
                  style: TextStyle(color: Color(0xFFF39C12), fontSize: 14),
                )
              else if (success) ...[
                Text(
                  '🔍 Duplicates Found: $duplicatesFound',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  '✅ Items Fixed: $itemsFixed',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                if (itemsFixed > 0) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE67E22).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE67E22).withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.print, color: Color(0xFFE67E22), size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Items with new SKUs need new labels. Check Label Printing page.',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2ECC71).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF2ECC71).withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_outline, color: Color(0xFF2ECC71), size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No duplicate SKUs found. All serial numbers are unique!',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ] else
                Text(
                  'Error: ${report['error'] ?? 'Unknown error'}',
                  style: const TextStyle(color: Color(0xFFE74C3C), fontSize: 14),
                ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: success ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Done', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isRunningMigration = false;
        _migrationMessage = '';
      });

      SnackBarUtils.showError(
        context,
        'Migration error: $e',
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<void> _loadKeepScreenOnSetting() async {
    final prefs = await SharedPreferences.getInstance();
    final keepOn = prefs.getBool('keep_screen_on') ?? false;
    if (mounted) {
      setState(() => _keepScreenOn = keepOn);
    }
    // Apply the setting
    if (keepOn) {
      await WakelockPlus.enable();
    }
  }

  Future<void> _toggleKeepScreenOn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('keep_screen_on', value);

    if (value) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }

    if (mounted) {
      setState(() => _keepScreenOn = value);
      SnackBarUtils.showSuccess(context, value ? 'Screen will stay on' : 'Screen timeout restored');
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
                  _buildCollapsibleSection(
                    title: 'POS Settings',
                    icon: Icons.point_of_sale,
                    gradient: const [Color(0xFFE67E22), Color(0xFFD35400)],
                    isExpanded: _posSettingsExpanded,
                    onToggle: (value) => setState(() => _posSettingsExpanded = value),
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
                      // Cash Drawer Opening Balance - Admin Only
                      if (widget.isAdmin) ...[
                        Divider(color: Colors.white.withValues(alpha: 0.1)),
                        Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF27AE60), Color(0xFF1E8449)],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.point_of_sale, color: Colors.white, size: 20),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Cash Drawer Opening Balance',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        'Starting cash amount in drawer',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Text(
                                  '₱',
                                  style: TextStyle(
                                    color: Color(0xFF27AE60),
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: _cashDrawerOpeningBalance.toStringAsFixed(2),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: '0.00',
                                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                                      filled: true,
                                      fillColor: Colors.white.withValues(alpha: 0.1),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    ),
                                    onChanged: (value) {
                                      final parsed = double.tryParse(value) ?? 0.0;
                                      setState(() => _cashDrawerOpeningBalance = parsed);
                                    },
                                    onFieldSubmitted: (value) async {
                                      final parsed = double.tryParse(value) ?? 0.0;
                                      await POSSettingsService.setCashDrawerOpeningBalance(parsed);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Opening balance saved'),
                                            backgroundColor: Color(0xFF27AE60),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () async {
                                    await POSSettingsService.setCashDrawerOpeningBalance(_cashDrawerOpeningBalance);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Opening balance saved'),
                                          backgroundColor: Color(0xFF27AE60),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF27AE60),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text('Save'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      ], // End of admin-only Cash Drawer section
                    ],
                  ),

                  // Service Sort Settings Section
                  _buildCollapsibleSection(
                    title: 'Service Sort Settings',
                    icon: Icons.sort,
                    gradient: const [Color(0xFF9B59B6), Color(0xFF8E44AD)],
                    isExpanded: _sortSettingsExpanded,
                    onToggle: (value) => setState(() => _sortSettingsExpanded = value),
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

                  // Printer Settings Section
                  _buildCollapsibleSection(
                    title: 'Printer Settings',
                    icon: Icons.print,
                    gradient: const [Color(0xFF3498DB), Color(0xFF2980B9)],
                    isExpanded: _printerSettingsExpanded,
                    onToggle: (value) => setState(() => _printerSettingsExpanded = value),
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
                                  if (_isPrinterConnected && _connectedPrinterName != null)
                                    Text(
                                      _connectedPrinterName!,
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
                                        final deviceAddress = device['address'] ?? '';
                                        final deviceName = device['name'] ?? 'Unknown';
                                        final isCurrentDevice =
                                            _connectedPrinterAddress == deviceAddress;

                                        return ListTile(
                                          leading: Icon(
                                            Icons.print,
                                            color: isCurrentDevice
                                                ? const Color(0xFF2ECC71)
                                                : Colors.white.withValues(alpha: 0.6),
                                          ),
                                          title: Text(
                                            deviceName,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: isCurrentDevice
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                          subtitle: Text(
                                            deviceAddress,
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

                  // Staff PIN Section - User's own PIN
                  _buildCollapsibleSection(
                    title: 'Staff PIN',
                    icon: Icons.pin,
                    gradient: const [Color(0xFF2ECC71), Color(0xFF27AE60)],
                    isExpanded: _staffPinExpanded,
                    onToggle: (value) => setState(() => _staffPinExpanded = value),
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
                  if (widget.isAdmin)
                    _buildCollapsibleSection(
                      title: 'POS Account PIN',
                      icon: Icons.point_of_sale,
                      gradient: const [Color(0xFFE67E22), Color(0xFFD35400)],
                      isExpanded: _posAccountPinExpanded,
                      onToggle: (value) => setState(() => _posAccountPinExpanded = value),
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

                  // Data Sync Section
                  _buildCollapsibleSection(
                    title: 'Data Sync',
                    icon: Icons.cloud_sync,
                    gradient: const [Color(0xFF3498DB), Color(0xFF2980B9)],
                    isExpanded: _dataSyncExpanded,
                    onToggle: (value) => setState(() => _dataSyncExpanded = value),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF3498DB), Color(0xFF2980B9)],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.cloud_upload, color: Colors.white, size: 28),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Force Sync to Cloud',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        _isForceSyncing
                                            ? _forceSyncMessage
                                            : 'Upload all local data to Firebase',
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!_isForceSyncing)
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF3498DB),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    ),
                                    onPressed: _forceSync,
                                    icon: const Icon(Icons.sync, size: 18),
                                    label: const Text('Sync'),
                                  ),
                              ],
                            ),
                            if (_isForceSyncing) ...[
                              const SizedBox(height: 16),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: _forceSyncTotal > 0 ? _forceSyncCurrent / _forceSyncTotal : null,
                                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3498DB)),
                                  minHeight: 8,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _forceSyncTotal > 0
                                    ? '$_forceSyncCurrent / $_forceSyncTotal items'
                                    : 'Preparing...',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Divider(color: Colors.white.withValues(alpha: 0.1)),
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3498DB).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF3498DB).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: const Color(0xFF3498DB).withValues(alpha: 0.8), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Force sync uploads all local inventory, customers, suggestions, and GSAT activations to Firebase. Use this if data seems out of sync.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(color: Colors.white.withValues(alpha: 0.1)),
                      Container(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.cloud_download, color: Colors.white, size: 28),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Refresh from Firebase',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'Clear cache & download latest data',
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2ECC71),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                              onPressed: _refreshFromFirebase,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Refresh'),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2ECC71).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF2ECC71).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: const Color(0xFF2ECC71).withValues(alpha: 0.8), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Use this if different devices show different inventory counts. This clears local cache and downloads fresh data from Firebase.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(color: Colors.white.withValues(alpha: 0.1)),
                      Container(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF9B59B6), Color(0xFF8E44AD)],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.sync, color: Colors.white, size: 28),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Full Bi-Directional Sync',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        _isFullSyncing
                                            ? _fullSyncMessage
                                            : 'Upload → Clear → Download (Recommended)',
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!_isFullSyncing)
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF9B59B6),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    ),
                                    onPressed: _fullBidirectionalSync,
                                    icon: const Icon(Icons.sync, size: 18),
                                    label: const Text('Full Sync'),
                                  ),
                              ],
                            ),
                            if (_isFullSyncing) ...[
                              const SizedBox(height: 16),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF9B59B6)),
                                  minHeight: 8,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_fullSyncPhase == 'upload')
                                    const Icon(Icons.cloud_upload, color: Color(0xFF9B59B6), size: 16),
                                  if (_fullSyncPhase == 'clear')
                                    const Icon(Icons.delete_sweep, color: Color(0xFF9B59B6), size: 16),
                                  if (_fullSyncPhase == 'download')
                                    const Icon(Icons.cloud_download, color: Color(0xFF9B59B6), size: 16),
                                  if (_fullSyncPhase == 'complete')
                                    const Icon(Icons.check_circle, color: Color(0xFF2ECC71), size: 16),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      _fullSyncMessage,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.7),
                                        fontSize: 12,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF9B59B6).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF9B59B6).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.recommend, color: const Color(0xFF9B59B6).withValues(alpha: 0.8), size: 18),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'RECOMMENDED: Best solution for inventory count discrepancies. Ensures your device has the exact same data as Firebase.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // SKU Migration Section (Admin Only)
                  if (widget.isAdmin)
                    _buildCollapsibleSection(
                      title: 'SKU Migration',
                      icon: Icons.autorenew,
                      gradient: const [Color(0xFFE67E22), Color(0xFFD35400)],
                      isExpanded: _skuMigrationExpanded,
                      onToggle: (value) => setState(() => _skuMigrationExpanded = value),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFE67E22), Color(0xFFD35400)],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 28),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Fix Duplicate SKUs',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      _isRunningMigration
                                          ? _migrationMessage
                                          : 'Scan & fix duplicate serial numbers',
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              if (!_isRunningMigration)
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFE67E22),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                  onPressed: _runSkuMigration,
                                  icon: const Icon(Icons.autorenew, size: 18),
                                  label: const Text('Run'),
                                ),
                            ],
                          ),
                        ),
                        if (_isRunningMigration) ...[
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: const LinearProgressIndicator(
                                backgroundColor: Colors.white24,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE67E22)),
                                minHeight: 8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Scanning for duplicates...',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Divider(color: Colors.white.withValues(alpha: 0.1)),
                        Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE67E22).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE67E22).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: const Color(0xFFE67E22).withValues(alpha: 0.8), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'This scans all inventory items and generates new random SKUs for any duplicates found. Items with new SKUs will need new labels.',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                  // General Settings Section
                  _buildCollapsibleSection(
                    title: 'General Settings',
                    icon: Icons.settings,
                    gradient: const [Color(0xFF9B59B6), Color(0xFF8E44AD)],
                    isExpanded: _generalSettingsExpanded,
                    onToggle: (value) => setState(() => _generalSettingsExpanded = value),
                    children: [
                      _buildSettingsTile(
                        icon: Icons.screen_lock_portrait,
                        iconGradient: const [Color(0xFF2ECC71), Color(0xFF27AE60)],
                        title: 'Keep Screen On',
                        subtitle: _keepScreenOn
                            ? 'Screen will stay awake'
                            : 'Prevent screen from turning off',
                        trailing: Switch(
                          value: _keepScreenOn,
                          onChanged: _toggleKeepScreenOn,
                          activeColor: const Color(0xFF2ECC71),
                        ),
                      ),
                      Divider(color: Colors.white.withValues(alpha: 0.1)),
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
                    ],
                  ),
                ],
              ),
            ),
          ),
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

  Widget _buildCollapsibleSection({
    required String title,
    required IconData icon,
    required List<Color> gradient,
    required bool isExpanded,
    required ValueChanged<bool> onToggle,
    required List<Widget> children,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Column(
      children: [
        // Header with tap to expand/collapse
        GestureDetector(
          onTap: () => onToggle(!isExpanded),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
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
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: screenWidth < 360 ? 16 : 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.white.withValues(alpha: 0.7),
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Animated content
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _buildSettingsCard(children: children),
          ),
          crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
        const SizedBox(height: 16),
      ],
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
