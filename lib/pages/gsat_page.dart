import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/firebase_database_service.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../services/pos_settings_service.dart';
import '../widgets/error_dialog.dart';
import 'multi_scanner_page.dart';
import 'ocr_scanner_page.dart';
import 'gsat_webview_page.dart';
import 'gsat_subscription_check_page.dart';
import 'gsat_load_page.dart';
import '../utils/snackbar_utils.dart';

class GSatPage extends StatefulWidget {
  const GSatPage({super.key});

  @override
  State<GSatPage> createState() => _GSatPageState();
}

class _GSatPageState extends State<GSatPage> {
  // GSat gradient colors matching admin page
  static const gsatGradient = [Color(0xFF2ECC71), Color(0xFF27AE60)];

  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _filteredCustomers = [];
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isAdmin = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounceTimer;
  int _currentPage = 0;
  int _itemsPerPage = 10;
  String _sortSetting = 'name_asc';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _checkAdminStatus();
  }

  Future<void> _checkAdminStatus() async {
    final currentUser = await AuthService.getCurrentUser();
    if (mounted) {
      setState(() {
        _isAdmin = currentUser != null && AuthService.isAdmin(currentUser);
      });
    }
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);

    // Load sort setting
    final sortSetting = await POSSettingsService.getSortSetting('gsat');

    var customers = await FirebaseDatabaseService.getCustomers(FirebaseDatabaseService.gsat);

    if (mounted) {
      // Pre-cache search strings for better performance
      for (var customer in customers) {
        customer['_searchCache'] = _buildSearchCache(customer);
      }

      // Apply sorting
      customers = POSSettingsService.sortCustomers(customers, sortSetting);

      setState(() {
        _sortSetting = sortSetting;
        _customers = customers;
        _filteredCustomers = customers;
        _isLoading = false;
        _currentPage = 0; // Reset to first page when loading
      });
    }
  }

  String _formatDateForSearch(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}-${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  String _buildSearchCache(Map<String, dynamic> customer) {
    final parts = [
      customer['name'] ?? '',
      customer['serialNumber'] ?? '',
      customer['boxNumber'] ?? '',
      customer['address'] ?? '',
      _formatDateForSearch(customer['dateOfPurchase']),
      _formatDateForSearch(customer['dateOfActivation']),
    ];
    return parts.join(' ').toLowerCase();
  }

  void _filterCustomers(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = query.toLowerCase().trim();
        _currentPage = 0; // Reset to first page when searching
        if (_searchQuery.isEmpty) {
          _filteredCustomers = _customers;
        } else {
          _filteredCustomers = _customers.where((customer) {
            final searchCache = customer['_searchCache'] as String? ?? '';
            return searchCache.contains(_searchQuery);
          }).toList();
        }
      });
    });
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _filterCustomers('');
      }
    });
  }

  List<Map<String, dynamic>> get _paginatedCustomers {
    final start = _currentPage * _itemsPerPage;
    final end = (start + _itemsPerPage).clamp(0, _filteredCustomers.length);
    if (start >= _filteredCustomers.length) return [];
    return _filteredCustomers.sublist(start, end);
  }

  int get _totalPages => (_filteredCustomers.length / _itemsPerPage).ceil();

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      setState(() => _currentPage++);
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      setState(() => _currentPage--);
    }
  }

  void _goToPage(int page) {
    if (page >= 0 && page < _totalPages) {
      setState(() => _currentPage = page);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _openGsatLoadPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const GsatLoadPage(),
      ),
    );
  }

  Future<void> _checkSubscriptionWithOcr() async {
    // First, scan serial number using OCR
    final ocrResult = await Navigator.push<OcrExtractedData>(
      context,
      MaterialPageRoute(
        builder: (context) => OcrScannerPage(
          serviceName: 'GSAT Subscription',
          primaryColor: gsatGradient[0],
          securityCodeOnly: false,
          serviceType: 'gsat',
        ),
      ),
    );

    if (ocrResult == null || !mounted) return;

    // Get serial number from OCR result
    final serialNumber = ocrResult.serialNumber ?? '';

    if (serialNumber.isEmpty) {
      SnackBarUtils.showWarning(context, 'No serial number detected. Please try again.');
      return;
    }

    // Show plan selection dialog
    _showPlanSelectionDialog(serialNumber);
  }

  void _showPlanSelectionDialog(String serialNumber) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Select Subscription Plan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Serial Number: $serialNumber',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
            ),
            const SizedBox(height: 20),
            // Plan 99 (GPinoy)
            _buildPlanOption(
              context,
              title: 'Plan 99 (GPinoy)',
              subtitle: 'gpinoysubscription.php',
              icon: Icons.star,
              color: Colors.amber,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GsatSubscriptionCheckPage(
                      serialNumber: serialNumber,
                      planType: '99',
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            // Plans 69/200/300/500
            _buildPlanOption(
              context,
              title: 'Plans 69/200/300/500',
              subtitle: 'gsatsubscription.php',
              icon: Icons.tv,
              color: gsatGradient[0],
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GsatSubscriptionCheckPage(
                      serialNumber: serialNumber,
                      planType: 'other',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanOption(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: color, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openScanner() async {
    final result = await Navigator.push<MultiScanResult>(
      context,
      MaterialPageRoute(
        builder: (context) => MultiScannerPage(
          serviceType: FirebaseDatabaseService.gsat,
          serviceName: 'GSAT',
          primaryColor: gsatGradient[0],
        ),
      ),
    );

    await _processMultiScanResult(result);
  }

  Future<void> _processMultiScanResult(MultiScanResult? result) async {
    if (result == null || result.allScannedItems.isEmpty) return;

    // For GSAT, use the first scanned code as Serial Number
    String? serialToCheck;
    if (result.allScannedItems.isNotEmpty) {
      serialToCheck = result.allScannedItems.first.code;
    }

    if (serialToCheck != null) {
      final exists = await FirebaseDatabaseService.serialNumberExists(
        FirebaseDatabaseService.gsat,
        serialToCheck,
      );

      if (exists) {
        if (!mounted) return;
        // Show existing customer details
        final customer = await FirebaseDatabaseService.getCustomerBySerialNumber(
          FirebaseDatabaseService.gsat,
          serialToCheck,
        );
        if (mounted) {
          await ErrorDialog.showDuplicate(
            context: context,
            fieldName: 'Serial Number',
            existingCustomerName: customer?['name'],
          );
          if (customer != null && mounted) {
            _showCustomerDetailsDialog(customer);
          }
        }
        return;
      }
    }

    // Show add customer dialog with scanned code as Serial Number
    if (!mounted) return;
    _showAddCustomerDialogWithMultiScan(result);
  }

  void _showAddCustomerDialogWithMultiScan(MultiScanResult scanResult) {
    // For GSAT, use first scanned code as Serial Number
    final scannedSerial = scanResult.allScannedItems.isNotEmpty
        ? scanResult.allScannedItems.first.code
        : '';
    final serialController = TextEditingController(text: scannedSerial);
    final nameController = TextEditingController();
    final boxNumberController = TextEditingController();
    final addressController = TextEditingController();
    final priceController = TextEditingController();
    DateTime? dateOfActivation;
    DateTime? dateOfPurchase;
    String selectedStatus = 'Active';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Add New Customer',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width < 320
                ? MediaQuery.of(context).size.width * 0.9
                : (MediaQuery.of(context).size.width < 500
                    ? MediaQuery.of(context).size.width * 0.85
                    : 480),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Serial Number field (primary identifier for GSAT)
                  _buildTextField(
                    controller: serialController,
                    label: 'Serial Number *',
                    icon: Icons.qr_code,
                  ),
                  const SizedBox(height: 8),
                  // Quick select serial number options
                  Row(
                    children: [
                      Text(
                        'Quick Select: ',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        label: Text(
                          '774053',
                          style: TextStyle(color: gsatGradient[0], fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        backgroundColor: gsatGradient[0].withValues(alpha: 0.15),
                        side: BorderSide(color: gsatGradient[0]),
                        onPressed: () {
                          setDialogState(() {
                            serialController.text = '774053';
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Name
                  _buildTextField(
                    controller: nameController,
                    label: 'Name *',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 16),
                  // Box Number
                  _buildTextField(
                    controller: boxNumberController,
                    label: 'Box Number',
                    icon: Icons.inventory_2,
                  ),
                  const SizedBox(height: 16),
                  // Address
                  _buildTextField(
                    controller: addressController,
                    label: 'Address',
                    icon: Icons.location_on,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  // Date of Activation
                  _buildDateField(
                    context: context,
                    label: 'Date of Activation',
                    value: dateOfActivation,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dateOfActivation ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.dark(
                                primary: gsatGradient[0],
                                surface: const Color(0xFF2A1A1A),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setDialogState(() => dateOfActivation = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Date of Purchase
                  _buildDateField(
                    context: context,
                    label: 'Date of Purchase',
                    value: dateOfPurchase,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dateOfPurchase ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.dark(
                                primary: gsatGradient[0],
                                surface: const Color(0xFF2A1A1A),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setDialogState(() => dateOfPurchase = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Price
                  _buildTextField(
                    controller: priceController,
                    label: 'Price',
                    icon: Icons.attach_money,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  // Status
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    dropdownColor: const Color(0xFF2A1A1A),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                    decoration: InputDecoration(
                      labelText: 'Status',
                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      prefixIcon: Icon(Icons.flag, color: gsatGradient[0]),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: gsatGradient[0]),
                      ),
                    ),
                    items: ['Active', 'Inactive', 'Pending'].map((status) {
                      return DropdownMenuItem(
                        value: status,
                        child: Text(
                          status,
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedStatus = value!);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                // Require at least a name and serial number
                if (nameController.text.isEmpty || serialController.text.isEmpty) {
                  SnackBarUtils.showWarning(context, 'Please enter name and Serial Number');
                  return;
                }

                // Check for duplicate Serial Number
                if (serialController.text.isNotEmpty) {
                  final serialExists = await FirebaseDatabaseService.serialNumberExists(
                    FirebaseDatabaseService.gsat,
                    serialController.text,
                  );
                  if (serialExists) {
                    if (!context.mounted) return;
                    final existingCustomer = await FirebaseDatabaseService.getCustomerBySerialNumber(
                      FirebaseDatabaseService.gsat,
                      serialController.text,
                    );
                    await ErrorDialog.showDuplicate(
                      context: context,
                      fieldName: 'Serial Number',
                      existingCustomerName: existingCustomer?['name'],
                    );
                    return;
                  }
                }

                // Check connectivity before adding
                final hasConnection = await CacheService.hasConnectivity();
                if (!hasConnection) {
                  if (!context.mounted) return;
                  SnackBarUtils.showError(context, 'No internet connection. Cannot add customer offline.');
                  return;
                }

                // Get current user info for tracking
                final currentUser = await AuthService.getCurrentUser();

                // Prepare customer data
                final customerData = <String, dynamic>{
                  'name': nameController.text,
                  'status': selectedStatus,
                };
                if (serialController.text.isNotEmpty) {
                  customerData['serialNumber'] = serialController.text;
                }
                if (boxNumberController.text.isNotEmpty) {
                  customerData['boxNumber'] = boxNumberController.text;
                }
                if (addressController.text.isNotEmpty) {
                  customerData['address'] = addressController.text;
                }
                if (dateOfActivation != null) {
                  customerData['dateOfActivation'] = DateFormat('yyyy-MM-dd').format(dateOfActivation!);
                }
                if (dateOfPurchase != null) {
                  customerData['dateOfPurchase'] = DateFormat('yyyy-MM-dd').format(dateOfPurchase!);
                }
                if (priceController.text.isNotEmpty) {
                  customerData['price'] = double.tryParse(priceController.text);
                }

                // Add customer directly (no approval needed for adding)
                final result = await FirebaseDatabaseService.addCustomer(
                  serviceType: FirebaseDatabaseService.gsat,
                  name: customerData['name'],
                  status: customerData['status'],
                  serialNumber: customerData['serialNumber'],
                  boxNumber: customerData['boxNumber'],
                  address: customerData['address'],
                  dateOfActivation: customerData['dateOfActivation'],
                  dateOfPurchase: customerData['dateOfPurchase'],
                  price: customerData['price'],
                  addedByEmail: currentUser?['email'] ?? '',
                  addedByName: currentUser?['name'] ?? '',
                );

                if (result != null) {
                  if (!context.mounted) return;
                  Navigator.of(context).pop();

                  // Add the new customer incrementally instead of reloading all
                  final newCustomer = Map<String, dynamic>.from(customerData);
                  newCustomer['id'] = result;
                  newCustomer['_searchCache'] = _buildSearchCache(newCustomer);

                  setState(() {
                    _customers.insert(0, newCustomer); // Add to beginning
                    _filteredCustomers = _customers;
                    _currentPage = 0; // Reset to first page to show new customer
                  });

                  SnackBarUtils.showSuccess(context, 'Customer added successfully!');
                } else {
                  if (!context.mounted) return;
                  SnackBarUtils.showError(context, 'Failed to add customer');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: gsatGradient[0],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Add Customer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openOcrScanner() async {
    final ocrData = await Navigator.push<OcrExtractedData>(
      context,
      MaterialPageRoute(
        builder: (context) => OcrScannerPage(
          serviceName: 'GSAT',
          primaryColor: gsatGradient[0],
          serviceType: 'gsat',
        ),
      ),
    );

    await _processOcrData(ocrData);
  }

  Future<void> _processOcrData(OcrExtractedData? ocrData) async {
    if (ocrData == null || !ocrData.hasAnyData) return;

    // For GSAT, use serialNumber from OCR (primary identifier)
    final serialToCheck = ocrData.serialNumber ?? ocrData.ccaNumber;
    if (serialToCheck != null && serialToCheck.isNotEmpty) {
      final exists = await FirebaseDatabaseService.serialNumberExists(
        FirebaseDatabaseService.gsat,
        serialToCheck,
      );

      if (exists) {
        if (!mounted) return;
        final customer = await FirebaseDatabaseService.getCustomerBySerialNumber(
          FirebaseDatabaseService.gsat,
          serialToCheck,
        );
        if (mounted) {
          await ErrorDialog.showDuplicate(
            context: context,
            fieldName: 'Serial Number',
            existingCustomerName: customer?['name'],
          );
          if (customer != null && mounted) {
            _showCustomerDetailsDialog(customer);
          }
        }
        return;
      }
    }

    if (!mounted) return;
    _showAddCustomerDialogWithOcrData(ocrData);
  }

  void _showAddCustomerDialogWithOcrData(OcrExtractedData ocrData) {
    // For GSAT: serialNumber is primary, boxNumber is secondary
    final detectedSerial = ocrData.serialNumber ?? ocrData.ccaNumber ?? '';
    final detectedBoxNumber = ocrData.boxNumber ?? '';
    final serialController = TextEditingController(text: detectedSerial);
    final nameController = TextEditingController(text: ocrData.name ?? '');
    final boxNumberController = TextEditingController(text: detectedBoxNumber);
    final addressController = TextEditingController(text: ocrData.address ?? '');
    final priceController = TextEditingController();
    DateTime? dateOfActivation;
    DateTime? dateOfPurchase;
    String selectedStatus = 'Active';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.document_scanner, color: gsatGradient[0], size: 24),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Add Customer (OCR)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width < 320
                ? MediaQuery.of(context).size.width * 0.9
                : (MediaQuery.of(context).size.width < 500
                    ? MediaQuery.of(context).size.width * 0.85
                    : 480),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // OCR detected indicator
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: gsatGradient[0].withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: gsatGradient[0]),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: gsatGradient[0], size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'OCR data detected - verify and edit as needed',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Serial Number field
                  _buildTextField(
                    controller: serialController,
                    label: 'Serial Number *',
                    icon: Icons.qr_code,
                  ),
                  const SizedBox(height: 8),
                  // Quick select serial number options
                  Row(
                    children: [
                      Text(
                        'Quick Select: ',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        label: Text(
                          '774053',
                          style: TextStyle(color: gsatGradient[0], fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        backgroundColor: gsatGradient[0].withValues(alpha: 0.15),
                        side: BorderSide(color: gsatGradient[0]),
                        onPressed: () {
                          setDialogState(() {
                            serialController.text = '774053';
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Name
                  _buildTextField(
                    controller: nameController,
                    label: 'Name *',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 16),
                  // Box Number
                  _buildTextField(
                    controller: boxNumberController,
                    label: 'Box Number',
                    icon: Icons.inventory_2,
                  ),
                  const SizedBox(height: 16),
                  // Address
                  _buildTextField(
                    controller: addressController,
                    label: 'Address',
                    icon: Icons.location_on,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  // Date of Activation
                  _buildDateField(
                    context: context,
                    label: 'Date of Activation',
                    value: dateOfActivation,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dateOfActivation ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.dark(
                                primary: gsatGradient[0],
                                surface: const Color(0xFF2A1A1A),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setDialogState(() => dateOfActivation = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Date of Purchase
                  _buildDateField(
                    context: context,
                    label: 'Date of Purchase',
                    value: dateOfPurchase,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dateOfPurchase ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.dark(
                                primary: gsatGradient[0],
                                surface: const Color(0xFF2A1A1A),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setDialogState(() => dateOfPurchase = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Price
                  _buildTextField(
                    controller: priceController,
                    label: 'Price',
                    icon: Icons.attach_money,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  // Status
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    dropdownColor: const Color(0xFF2A1A1A),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                    decoration: InputDecoration(
                      labelText: 'Status',
                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      prefixIcon: Icon(Icons.flag, color: gsatGradient[0]),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: gsatGradient[0]),
                      ),
                    ),
                    items: ['Active', 'Inactive', 'Pending'].map((status) {
                      return DropdownMenuItem(
                        value: status,
                        child: Text(
                          status,
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedStatus = value!);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                // Require at least a name and serial number
                if (nameController.text.isEmpty || serialController.text.isEmpty) {
                  SnackBarUtils.showWarning(context, 'Please enter name and Serial Number');
                  return;
                }

                // Check for duplicate Serial Number
                final serialExists = await FirebaseDatabaseService.serialNumberExists(
                  FirebaseDatabaseService.gsat,
                  serialController.text,
                );
                if (serialExists) {
                  if (!context.mounted) return;
                  final existingCustomer = await FirebaseDatabaseService.getCustomerBySerialNumber(
                    FirebaseDatabaseService.gsat,
                    serialController.text,
                  );
                  await ErrorDialog.showDuplicate(
                    context: context,
                    fieldName: 'Serial Number',
                    existingCustomerName: existingCustomer?['name'],
                  );
                  return;
                }

                // Check connectivity before adding
                final hasConnection = await CacheService.hasConnectivity();
                if (!hasConnection) {
                  if (!context.mounted) return;
                  SnackBarUtils.showError(context, 'No internet connection. Cannot add customer offline.');
                  return;
                }

                // Get current user info for tracking
                final currentUser = await AuthService.getCurrentUser();

                // Prepare customer data
                final customerData = <String, dynamic>{
                  'name': nameController.text,
                  'status': selectedStatus,
                  'serialNumber': serialController.text,
                };
                if (boxNumberController.text.isNotEmpty) {
                  customerData['boxNumber'] = boxNumberController.text;
                }
                if (addressController.text.isNotEmpty) {
                  customerData['address'] = addressController.text;
                }
                if (dateOfActivation != null) {
                  customerData['dateOfActivation'] = DateFormat('yyyy-MM-dd').format(dateOfActivation!);
                }
                if (dateOfPurchase != null) {
                  customerData['dateOfPurchase'] = DateFormat('yyyy-MM-dd').format(dateOfPurchase!);
                }
                if (priceController.text.isNotEmpty) {
                  customerData['price'] = double.tryParse(priceController.text);
                }

                // Add customer directly (no approval needed for adding)
                final result = await FirebaseDatabaseService.addCustomer(
                  serviceType: FirebaseDatabaseService.gsat,
                  name: customerData['name'],
                  status: customerData['status'],
                  serialNumber: customerData['serialNumber'],
                  boxNumber: customerData['boxNumber'],
                  address: customerData['address'],
                  dateOfActivation: customerData['dateOfActivation'],
                  dateOfPurchase: customerData['dateOfPurchase'],
                  price: customerData['price'],
                  addedByEmail: currentUser?['email'] ?? '',
                  addedByName: currentUser?['name'] ?? '',
                );

                if (result != null) {
                  if (!context.mounted) return;
                  Navigator.of(context).pop();

                  // Add the new customer incrementally instead of reloading all
                  final newCustomer = Map<String, dynamic>.from(customerData);
                  newCustomer['id'] = result;
                  newCustomer['_searchCache'] = _buildSearchCache(newCustomer);

                  setState(() {
                    _customers.insert(0, newCustomer); // Add to beginning
                    _filteredCustomers = _customers;
                    _currentPage = 0; // Reset to first page to show new customer
                  });

                  SnackBarUtils.showSuccess(context, 'Customer added successfully!');
                } else {
                  if (!context.mounted) return;
                  SnackBarUtils.showError(context, 'Failed to add customer');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: gsatGradient[0],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Add Customer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showScanOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Add New Customer',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose how to enter the Serial Number',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 24),
                // Barcode Scanner option (Multi-scan)
                _buildScanOptionTile(
                  icon: Icons.qr_code_scanner,
                  title: 'Scan Barcodes',
                  subtitle: 'Scan Serial Number and other codes',
                  onTap: () {
                    Navigator.pop(context);
                    _openScanner();
                  },
                ),
                const SizedBox(height: 12),
                // OCR Scanner option
                _buildScanOptionTile(
                  icon: Icons.document_scanner,
                  title: 'OCR Text Scanner',
                  subtitle: 'Take photo of Serial Number text',
                  onTap: () {
                    Navigator.pop(context);
                    _openOcrScanner();
                  },
                ),
                const SizedBox(height: 12),
                // Manual entry option
                _buildScanOptionTile(
                  icon: Icons.edit,
                  title: 'Manual Entry',
                  subtitle: 'Type all details manually',
                  onTap: () {
                    Navigator.pop(context);
                    _showManualEntryDialog();
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScanOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: gsatGradient[0].withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: gsatGradient[0].withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: gsatGradient[0],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.white.withValues(alpha: 0.5),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  void _showManualEntryDialog() {
    final serialController = TextEditingController();
    final nameController = TextEditingController();
    final boxNumberController = TextEditingController();
    final addressController = TextEditingController();
    final priceController = TextEditingController();
    DateTime? dateOfActivation;
    DateTime? dateOfPurchase;
    String selectedStatus = 'Active';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.edit, color: gsatGradient[0], size: 24),
              const SizedBox(width: 8),
              const Text(
                'Manual Entry',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Serial Number
                  _buildTextField(
                    controller: serialController,
                    label: 'Serial Number *',
                    icon: Icons.qr_code,
                  ),
                  const SizedBox(height: 8),
                  // Quick select serial number options
                  Row(
                    children: [
                      Text(
                        'Quick Select: ',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        label: Text(
                          '774053',
                          style: TextStyle(color: gsatGradient[0], fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        backgroundColor: gsatGradient[0].withValues(alpha: 0.15),
                        side: BorderSide(color: gsatGradient[0]),
                        onPressed: () {
                          setDialogState(() {
                            serialController.text = '774053';
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Name
                  _buildTextField(
                    controller: nameController,
                    label: 'Name *',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 16),
                  // Box Number
                  _buildTextField(
                    controller: boxNumberController,
                    label: 'Box Number',
                    icon: Icons.inventory_2,
                  ),
                  const SizedBox(height: 16),
                  // Address
                  _buildTextField(
                    controller: addressController,
                    label: 'Address',
                    icon: Icons.location_on,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  // Date of Activation
                  _buildDateField(
                    context: context,
                    label: 'Date of Activation',
                    value: dateOfActivation,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dateOfActivation ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.dark(
                                primary: gsatGradient[0],
                                surface: const Color(0xFF2A1A1A),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setDialogState(() => dateOfActivation = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Date of Purchase
                  _buildDateField(
                    context: context,
                    label: 'Date of Purchase',
                    value: dateOfPurchase,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dateOfPurchase ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.dark(
                                primary: gsatGradient[0],
                                surface: const Color(0xFF2A1A1A),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setDialogState(() => dateOfPurchase = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Price
                  _buildTextField(
                    controller: priceController,
                    label: 'Price',
                    icon: Icons.attach_money,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  // Status
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    dropdownColor: const Color(0xFF2A1A1A),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                    decoration: InputDecoration(
                      labelText: 'Status',
                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      prefixIcon: Icon(Icons.flag, color: gsatGradient[0]),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: gsatGradient[0]),
                      ),
                    ),
                    items: ['Active', 'Inactive', 'Pending'].map((status) {
                      return DropdownMenuItem(
                        value: status,
                        child: Text(
                          status,
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedStatus = value!);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                // Validate required fields
                final List<String> missingFields = [];

                if (serialController.text.isEmpty) {
                  missingFields.add('Serial Number');
                }
                if (nameController.text.isEmpty) {
                  missingFields.add('Name');
                }

                if (missingFields.isNotEmpty) {
                  SnackBarUtils.showWarning(context, 'Please fill in: ${missingFields.join(', ')}');
                  return;
                }

                // Show save confirmation dialog
                _showSaveConfirmationDialog(
                  context: context,
                  serialNumber: serialController.text,
                  name: nameController.text,
                  boxNumber: boxNumberController.text.isNotEmpty ? boxNumberController.text : null,
                  address: addressController.text.isNotEmpty ? addressController.text : null,
                  dateOfActivation: dateOfActivation,
                  dateOfPurchase: dateOfPurchase,
                  price: double.tryParse(priceController.text),
                  status: selectedStatus,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: gsatGradient[0],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSaveConfirmationDialog({
    required BuildContext context,
    required String serialNumber,
    required String name,
    String? boxNumber,
    String? address,
    DateTime? dateOfActivation,
    DateTime? dateOfPurchase,
    double? price,
    required String status,
  }) {
    showDialog(
      context: context,
      builder: (confirmContext) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Confirm Save',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Please confirm the following details:',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
              ),
              const SizedBox(height: 16),
              _buildConfirmRow('Serial Number', serialNumber),
              _buildConfirmRow('Name', name),
              if (boxNumber != null) _buildConfirmRow('Box Number', boxNumber),
              if (address != null) _buildConfirmRow('Address', address),
              if (dateOfActivation != null)
                _buildConfirmRow('Activation', DateFormat('MMM dd, yyyy').format(dateOfActivation)),
              if (dateOfPurchase != null)
                _buildConfirmRow('Purchase', DateFormat('MMM dd, yyyy').format(dateOfPurchase)),
              if (price != null) _buildConfirmRow('Price', '₱${price.toStringAsFixed(2)}'),
              _buildConfirmRow('Status', status),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(confirmContext).pop(),
            child: Text(
              'Edit',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(confirmContext).pop();

              // Check for duplicate Serial Number
              final serialExists = await FirebaseDatabaseService.serialNumberExists(
                FirebaseDatabaseService.gsat,
                serialNumber,
              );
              if (serialExists) {
                if (!context.mounted) return;
                final existingCustomer = await FirebaseDatabaseService.getCustomerBySerialNumber(
                  FirebaseDatabaseService.gsat,
                  serialNumber,
                );
                await ErrorDialog.showDuplicate(
                  context: context,
                  fieldName: 'Serial Number',
                  existingCustomerName: existingCustomer?['name'],
                );
                return;
              }

              // Check connectivity before adding
              final hasConnection = await CacheService.hasConnectivity();
              if (!hasConnection) {
                if (!context.mounted) return;
                SnackBarUtils.showError(context, 'No internet connection. Cannot add customer offline.');
                return;
              }

              // Get current user info for tracking
              final currentUser = await AuthService.getCurrentUser();

              // Prepare customer data
              final customerData = <String, dynamic>{
                'name': name,
                'status': status,
                'serialNumber': serialNumber,
              };
              if (boxNumber != null) {
                customerData['boxNumber'] = boxNumber;
              }
              if (address != null) {
                customerData['address'] = address;
              }
              if (dateOfActivation != null) {
                customerData['dateOfActivation'] = DateFormat('yyyy-MM-dd').format(dateOfActivation);
              }
              if (dateOfPurchase != null) {
                customerData['dateOfPurchase'] = DateFormat('yyyy-MM-dd').format(dateOfPurchase);
              }
              if (price != null) {
                customerData['price'] = price;
              }

              // Add customer directly (no approval needed for adding)
              final result = await FirebaseDatabaseService.addCustomer(
                serviceType: FirebaseDatabaseService.gsat,
                name: customerData['name'],
                status: customerData['status'],
                serialNumber: customerData['serialNumber'],
                boxNumber: customerData['boxNumber'],
                address: customerData['address'],
                dateOfActivation: customerData['dateOfActivation'],
                dateOfPurchase: customerData['dateOfPurchase'],
                price: customerData['price'],
                addedByEmail: currentUser?['email'] ?? '',
                addedByName: currentUser?['name'] ?? '',
              );

              if (result != null) {
                if (!context.mounted) return;
                Navigator.of(context).pop(); // Close manual entry dialog
                SnackBarUtils.showTopSnackBar(context, message: 'Customer $name added successfully!', backgroundColor: gsatGradient[0]);
                _loadCustomers();
              } else {
                if (!context.mounted) return;
                SnackBarUtils.showError(context, 'Failed to add customer');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: gsatGradient[0],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      cursorColor: gsatGradient[0],
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        prefixIcon: Icon(icon, color: gsatGradient[0]),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: gsatGradient[0]),
        ),
      ),
    );
  }

  Widget _buildDateField({
    required BuildContext context,
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: gsatGradient[0]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value != null
                    ? DateFormat('MMM dd, yyyy').format(value)
                    : label,
                style: TextStyle(
                  color: value != null ? Colors.white : Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomerDetailsDialog(Map<String, dynamic> customer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(Icons.public, color: gsatGradient[0], size: 24),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Customer Details',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Serial Number', customer['serialNumber'] ?? 'N/A'),
              _detailRow('Name', customer['name'] ?? 'N/A'),
              _detailRow('Box Number', customer['boxNumber'] ?? 'N/A'),
              if (customer['address'] != null)
                _detailRow('Address', customer['address']),
              _detailRow('Status', customer['status'] ?? 'N/A'),
              if (customer['dateOfActivation'] != null)
                _detailRow('Activation', _formatDate(customer['dateOfActivation'])),
              if (customer['dateOfPurchase'] != null)
                _detailRow('Purchase', _formatDate(customer['dateOfPurchase'])),
              if (customer['price'] != null)
                _detailRow('Price', '₱${customer['price']}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GSatWebViewPage(
                    accountNumber: customer['serialNumber'] ?? '',
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: gsatGradient[0],
              foregroundColor: Colors.white,
            ),
            child: const Text('Open GSAT'),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'N/A';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditCustomerDialog(Map<String, dynamic> customer) {
    final serialController = TextEditingController(text: customer['serialNumber'] ?? '');
    final nameController = TextEditingController(text: customer['name'] ?? '');
    final boxNumberController = TextEditingController(text: customer['boxNumber'] ?? '');
    final addressController = TextEditingController(text: customer['address'] ?? '');
    final priceController = TextEditingController(
      text: customer['price'] != null ? customer['price'].toString() : '',
    );
    DateTime? dateOfActivation;
    DateTime? dateOfPurchase;
    String selectedStatus = customer['status'] ?? 'Active';

    // Parse existing dates
    if (customer['dateOfActivation'] != null) {
      try {
        dateOfActivation = DateTime.parse(customer['dateOfActivation']);
      } catch (e) {
        // ignore
      }
    }
    if (customer['dateOfPurchase'] != null) {
      try {
        dateOfPurchase = DateTime.parse(customer['dateOfPurchase']);
      } catch (e) {
        // ignore
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Edit Customer',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width < 320
                ? MediaQuery.of(context).size.width * 0.9
                : (MediaQuery.of(context).size.width < 500
                    ? MediaQuery.of(context).size.width * 0.85
                    : 480),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Serial Number field
                  _buildTextField(
                    controller: serialController,
                    label: 'Serial Number *',
                    icon: Icons.qr_code,
                  ),
                  const SizedBox(height: 8),
                  // Quick select serial number options
                  Row(
                    children: [
                      Text(
                        'Quick Select: ',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        label: Text(
                          '774053',
                          style: TextStyle(color: gsatGradient[0], fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        backgroundColor: gsatGradient[0].withValues(alpha: 0.15),
                        side: BorderSide(color: gsatGradient[0]),
                        onPressed: () {
                          setDialogState(() {
                            serialController.text = '774053';
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Name
                  _buildTextField(
                    controller: nameController,
                    label: 'Name *',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 16),
                  // Box Number
                  _buildTextField(
                    controller: boxNumberController,
                    label: 'Box Number',
                    icon: Icons.inventory_2,
                  ),
                  const SizedBox(height: 16),
                  // Address
                  _buildTextField(
                    controller: addressController,
                    label: 'Address',
                    icon: Icons.location_on,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  // Date of Activation
                  _buildDateField(
                    context: context,
                    label: 'Date of Activation',
                    value: dateOfActivation,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dateOfActivation ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.dark(
                                primary: gsatGradient[0],
                                surface: const Color(0xFF2A1A1A),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setDialogState(() => dateOfActivation = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Date of Purchase
                  _buildDateField(
                    context: context,
                    label: 'Date of Purchase',
                    value: dateOfPurchase,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dateOfPurchase ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.dark(
                                primary: gsatGradient[0],
                                surface: const Color(0xFF2A1A1A),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setDialogState(() => dateOfPurchase = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Price
                  _buildTextField(
                    controller: priceController,
                    label: 'Price',
                    icon: Icons.attach_money,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  // Status
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    dropdownColor: const Color(0xFF2A1A1A),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                    decoration: InputDecoration(
                      labelText: 'Status',
                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      prefixIcon: Icon(Icons.flag, color: gsatGradient[0]),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: gsatGradient[0]),
                      ),
                    ),
                    items: ['Active', 'Inactive', 'Pending'].map((status) {
                      return DropdownMenuItem(
                        value: status,
                        child: Text(
                          status,
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedStatus = value!);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                // Store context-dependent objects at the start
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                final dialogContext = context;

                if (nameController.text.isEmpty || serialController.text.isEmpty) {
                  SnackBarUtils.showWarning(context, 'Please enter name and Serial Number');
                  return;
                }

                // Check connectivity before adding
                final hasConnection = await CacheService.hasConnectivity();
                if (!hasConnection) {
                  if (!dialogContext.mounted) return;
                  SnackBarUtils.showError(dialogContext, 'No internet connection. Cannot add customer offline.');
                  return;
                }

                // Get current user info for tracking
                final currentUser = await AuthService.getCurrentUser();

                // Prepare customer data
                final customerData = <String, dynamic>{
                  'name': nameController.text,
                  'status': selectedStatus,
                };
                if (serialController.text.isNotEmpty) {
                  customerData['serialNumber'] = serialController.text;
                }
                if (boxNumberController.text.isNotEmpty) {
                  customerData['boxNumber'] = boxNumberController.text;
                }
                if (addressController.text.isNotEmpty) {
                  customerData['address'] = addressController.text;
                }
                if (dateOfActivation != null) {
                  customerData['dateOfActivation'] = DateFormat('yyyy-MM-dd').format(dateOfActivation!);
                }
                if (dateOfPurchase != null) {
                  customerData['dateOfPurchase'] = DateFormat('yyyy-MM-dd').format(dateOfPurchase!);
                }
                if (priceController.text.isNotEmpty) {
                  customerData['price'] = double.tryParse(priceController.text);
                }

                if (!mounted) return;

                // Close dialog immediately and show saving indicator
                navigator.pop();

                SnackBarUtils.showTopSnackBar(
                  this.context,
                  message: 'Saving changes...',
                  backgroundColor: const Color(0xFF3498DB),
                  duration: const Duration(seconds: 30),
                  content: const Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text('Saving changes...'),
                    ],
                  ),
                );

                // Update customer in background
                final success = await FirebaseDatabaseService.updateCustomer(
                  serviceType: FirebaseDatabaseService.gsat,
                  customerId: customer['id'],
                  serialNumber: customerData['serialNumber'],
                  name: customerData['name'],
                  boxNumber: customerData['boxNumber'],
                  address: customerData['address'],
                  dateOfActivation: customerData['dateOfActivation'],
                  dateOfPurchase: customerData['dateOfPurchase'],
                  price: customerData['price'],
                  status: customerData['status'],
                  updatedByEmail: currentUser?['email'] ?? '',
                  updatedByName: currentUser?['name'] ?? '',
                );

                if (!mounted) return;

                scaffoldMessenger.hideCurrentSnackBar();

                if (success) {
                  // Update customer incrementally instead of reloading all
                  final customerId = customer['id'];
                  final index = _customers.indexWhere((c) => c['id'] == customerId);

                  if (index != -1) {
                    final updatedCustomer = Map<String, dynamic>.from(_customers[index]);
                    updatedCustomer.addAll(customerData);
                    updatedCustomer['_searchCache'] = _buildSearchCache(updatedCustomer);

                    setState(() {
                      _customers[index] = updatedCustomer;
                      // Re-filter to update the filtered list
                      if (_searchQuery.isEmpty) {
                        _filteredCustomers = _customers;
                      } else {
                        _filteredCustomers = _customers.where((c) {
                          final searchCache = c['_searchCache'] as String? ?? '';
                          return searchCache.contains(_searchQuery);
                        }).toList();
                      }
                    });
                  }

                  SnackBarUtils.showTopSnackBar(this.context, message: 'Customer ${nameController.text} updated successfully!', backgroundColor: gsatGradient[0]);
                } else {
                  SnackBarUtils.showError(this.context, 'Failed to update customer');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: gsatGradient[0],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _addToActivation(Map<String, dynamic> customer) {
    final serialNumber = customer['serialNumber'] ?? '';
    final name = customer['name'] ?? '';
    final address = customer['address'] ?? '';
    const defaultDealer = 'Romeo dalocanog';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(Icons.add_circle, color: gsatGradient[0], size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Add to Activation?',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to add this customer to GSAT Activation?',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fields to be filled:',
                    style: TextStyle(
                      color: gsatGradient[0],
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (serialNumber.isNotEmpty)
                    _buildActivationPreviewRow('Serial Number', serialNumber),
                  if (name.isNotEmpty)
                    _buildActivationPreviewRow('Name', name),
                  if (address.isNotEmpty)
                    _buildActivationPreviewRow('Address', address),
                  _buildActivationPreviewRow('Dealer', '$defaultDealer (default)'),
                  const SizedBox(height: 8),
                  Text(
                    'Note: Contact Number will need to be filled manually.',
                    style: TextStyle(
                      color: Colors.orange.withValues(alpha: 0.8),
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await FirebaseDatabaseService.addGsatActivation(
                  serialNumber: serialNumber,
                  name: name,
                  address: address,
                  contactNumber: '', // Not available in customer table
                  dealer: defaultDealer,
                );
                if (mounted) {
                  SnackBarUtils.showTopSnackBar(this.context, message: 'Added to GSAT Activation successfully!', backgroundColor: gsatGradient[0]);
                }
              } catch (e) {
                if (mounted) {
                  SnackBarUtils.showError(this.context, 'Error: $e');
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: gsatGradient[0],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildActivationPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, size: 14, color: gsatGradient[0]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, Map<String, dynamic> customer) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          _isAdmin ? 'Delete Customer?' : 'Request Deletion',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isAdmin
                  ? 'Are you sure you want to delete ${customer['name']}? This action cannot be undone.'
                  : 'Request to delete ${customer['name']}. This will be sent to an admin for approval.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
            if (!_isAdmin) ...[
              const SizedBox(height: 16),
              Text(
                'Reason for deletion',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reasonController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Please explain why this customer should be deleted...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();

              // Get current user info
              final currentUser = await AuthService.getCurrentUser();
              final isAdmin = currentUser != null && AuthService.isAdmin(currentUser);

              if (isAdmin) {
                // Admin: Delete directly
                final success = await FirebaseDatabaseService.deleteCustomer(
                  FirebaseDatabaseService.gsat,
                  customer['id'],
                );

                if (!mounted) return;

                if (success) {
                  // Remove customer incrementally instead of reloading all
                  final customerId = customer['id'];
                  setState(() {
                    _customers.removeWhere((c) => c['id'] == customerId);
                    _filteredCustomers.removeWhere((c) => c['id'] == customerId);
                  });

                  SnackBarUtils.showError(this.context, '${customer['name']} deleted');
                } else {
                  SnackBarUtils.showError(this.context, 'Failed to delete customer');
                }
              } else {
                // Non-admin: Submit delete suggestion with reason
                final customerData = Map<String, dynamic>.from(customer);
                customerData.remove('id'); // Don't include id in customerData

                final result = await FirebaseDatabaseService.submitSuggestion(
                  serviceType: FirebaseDatabaseService.gsat,
                  type: 'delete',
                  customerId: customer['id'],
                  customerData: customerData,
                  submittedByEmail: currentUser?['email'] ?? '',
                  submittedByName: currentUser?['name'] ?? '',
                  reason: reasonController.text.trim(),
                );

                if (!mounted) return;

                if (result == 'duplicate') {
                  await ErrorDialog.show(
                    context: context,
                    title: 'Duplicate Request',
                    message: 'A pending delete request already exists for this customer.\n\nPlease wait for admin to review the existing request.',
                  );
                } else if (result != null) {
                  SnackBarUtils.showSuccess(this.context, 'Delete request for ${customer['name']} submitted for admin approval!');
                } else {
                  await ErrorDialog.showSaveError(
                    context: context,
                    customMessage: 'Failed to submit delete request.\n\nPlease check your internet connection and try again.',
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE74C3C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(_isAdmin ? 'Delete' : 'Submit Request'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final isCompact = isMobile && isLandscape;
    final activeCount = _customers.where((c) => c['status'] == 'Active').length;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF1A0A0A),
            const Color(0xFF2A1A1A),
          ],
        ),
      ),
      child: Column(
        children: [
          // Header with logo and gradient - compact for mobile
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 8 : (isMobile ? 10 : 24),
              vertical: isCompact ? 4 : (isMobile ? 8 : 24),
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gsatGradient,
              ),
            ),
            child: Row(
              children: [
                // Logo - smaller on mobile
                Container(
                  width: isMobile ? 40 : 80,
                  height: isMobile ? 40 : 80,
                  padding: EdgeInsets.all(isMobile ? 6 : 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(isMobile ? 10 : 20),
                  ),
                  child: Image.asset(
                    'Photos/GSAT.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.public,
                        size: isMobile ? 20 : 40,
                        color: gsatGradient[0],
                      );
                    },
                  ),
                ),
                SizedBox(width: isMobile ? 10 : 20),
                Expanded(
                  child: Text(
                    isMobile ? 'GSAT' : 'GSAT Services',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isMobile ? 18 : 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // GSAT Web Load button with image (no background)
                GestureDetector(
                  onTap: _openGsatLoadPage,
                  child: Tooltip(
                    message: 'Load GSAT',
                    child: Image.asset(
                      'Photos/GSAT.png',
                      width: isMobile ? 28 : 36,
                      height: isMobile ? 28 : 36,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.public,
                          size: isMobile ? 24 : 30,
                          color: Colors.white,
                        );
                      },
                    ),
                  ),
                ),
                SizedBox(width: isMobile ? 4 : 8),
                // Action buttons - compact on mobile
                IconButton(
                  icon: Icon(Icons.fact_check, color: Colors.white, size: isMobile ? 20 : 24),
                  onPressed: _checkSubscriptionWithOcr,
                  tooltip: 'Check Subscription',
                  padding: EdgeInsets.all(isMobile ? 6 : 8),
                  constraints: BoxConstraints(
                    minWidth: isMobile ? 32 : 48,
                    minHeight: isMobile ? 32 : 48,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.qr_code_scanner, color: Colors.white, size: isMobile ? 20 : 24),
                  onPressed: _showScanOptions,
                  tooltip: 'Scan',
                  padding: EdgeInsets.all(isMobile ? 6 : 8),
                  constraints: BoxConstraints(
                    minWidth: isMobile ? 32 : 48,
                    minHeight: isMobile ? 32 : 48,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _isSearching ? Icons.close : Icons.search,
                    color: Colors.white,
                    size: isMobile ? 20 : 24,
                  ),
                  onPressed: _toggleSearch,
                  padding: EdgeInsets.all(isMobile ? 6 : 8),
                  constraints: BoxConstraints(
                    minWidth: isMobile ? 32 : 48,
                    minHeight: isMobile ? 32 : 48,
                  ),
                ),
              ],
            ),
          ),

          // Search bar
          if (_isSearching)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 10 : 24,
                vertical: isMobile ? 8 : 12,
              ),
              color: const Color(0xFF2A1A1A),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search by name, serial, date...',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                        prefixIcon: Icon(Icons.search, color: gsatGradient[0]),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.white54),
                                onPressed: () {
                                  _searchController.clear();
                                  _filterCustomers('');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onChanged: _filterCustomers,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Date picker button
                  Container(
                    decoration: BoxDecoration(
                      color: gsatGradient[0].withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: gsatGradient[0]),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.calendar_month, color: gsatGradient[0]),
                      tooltip: 'Search by date',
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: ColorScheme.dark(
                                  primary: gsatGradient[0],
                                  surface: const Color(0xFF2A1A1A),
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          final dateStr = '${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}-${picked.year}';
                          _searchController.text = dateStr;
                          _filterCustomers(dateStr);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

          // Content area
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF2ECC71),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadCustomers,
                    color: gsatGradient[0],
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.all(isMobile ? 8 : 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Stats cards - compact for mobile landscape
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: screenWidth < 360 ? 1 : (screenWidth < 600 ? 2 : 4),
                            mainAxisSpacing: isCompact ? 4 : (isMobile ? 4 : 16),
                            crossAxisSpacing: isCompact ? 4 : (isMobile ? 4 : 16),
                            childAspectRatio: isCompact ? 2.0 : (isMobile ? 1.0 : 1.3),
                            children: [
                              _StatCard(
                                title: 'Total',
                                value: '${_customers.length}',
                                icon: Icons.people,
                                gradientColors: gsatGradient,
                                isMobile: isMobile,
                                isCompact: isCompact,
                              ),
                              _StatCard(
                                title: 'Active',
                                value: '$activeCount',
                                icon: Icons.check_circle,
                                gradientColors: const [Color(0xFF3498DB), Color(0xFF2980B9)],
                                isMobile: isMobile,
                                isCompact: isCompact,
                              ),
                              _StatCard(
                                title: 'Inactive',
                                value: '${_customers.length - activeCount}',
                                icon: Icons.cancel,
                                gradientColors: const [Color(0xFFE74C3C), Color(0xFFC0392B)],
                                isMobile: isMobile,
                                isCompact: isCompact,
                              ),
                              _StatCard(
                                title: 'Rate',
                                value: _customers.isEmpty
                                    ? '0%'
                                    : '${(activeCount / _customers.length * 100).toStringAsFixed(0)}%',
                                icon: Icons.trending_up,
                                gradientColors: const [Color(0xFF9B59B6), Color(0xFF8E44AD)],
                                isMobile: isMobile,
                                isCompact: isCompact,
                              ),
                            ],
                          ),

                          SizedBox(height: isMobile ? 8 : 32),

                          // Section header - compact for mobile
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Customers',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isMobile ? 14 : 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _showScanOptions,
                                icon: Icon(Icons.qr_code_scanner, size: isMobile ? 14 : 18),
                                label: Text(isMobile ? 'Add' : 'Scan & Add'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: gsatGradient[0],
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isMobile ? 12 : 20,
                                    vertical: isMobile ? 8 : 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(isMobile ? 20 : 25),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: isMobile ? 8 : 16),

                          // Customer list
                          if (_customers.isEmpty)
                            _EmptyState(isMobile: isMobile, onScan: _showScanOptions)
                          else if (_filteredCustomers.isEmpty && _searchQuery.isNotEmpty)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.search_off,
                                      size: 64,
                                      color: Colors.white.withValues(alpha: 0.3),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No results found for "$_searchQuery"',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.5),
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Try a different search term',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.3),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            Column(
                              children: [
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _paginatedCustomers.length,
                                  itemBuilder: (context, index) {
                                    final customer = _paginatedCustomers[index];
                                    return _CustomerCard(
                                      customer: customer,
                                      isMobile: isMobile,
                                      isAdmin: _isAdmin,
                                      onEdit: () => _showEditCustomerDialog(customer),
                                      onDelete: () => _showDeleteConfirmation(context, customer),
                                      onTap: () => _showCustomerDetailsDialog(customer),
                                      onOpenGsat: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => GSatWebViewPage(
                                              accountNumber: customer['serialNumber'] ?? '',
                                            ),
                                          ),
                                        );
                                      },
                                      onAddToActivation: () => _addToActivation(customer),
                                    );
                                  },
                                ),
                                if (_filteredCustomers.length > _itemsPerPage)
                                  _PaginationControls(
                                    currentPage: _currentPage,
                                    totalPages: _totalPages,
                                    totalItems: _filteredCustomers.length,
                                    itemsPerPage: _itemsPerPage,
                                    onNextPage: _nextPage,
                                    onPreviousPage: _previousPage,
                                    onGoToPage: _goToPage,
                                    isMobile: isMobile,
                                    primaryColor: gsatGradient[0],
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final List<Color> gradientColors;
  final bool isMobile;
  final bool isCompact;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.gradientColors,
    required this.isMobile,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    // Reduced sizes to match reports page style
    final borderRadius = isCompact ? 8.0 : (isMobile ? 10.0 : 16.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Rounded rectangle decorative element - hide on mobile
            if (!isCompact && !isMobile)
              Positioned(
                top: -20,
                right: -20,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.all(isCompact ? 4 : (isMobile ? 8 : 14)),
              child: isCompact
                  ? Row(
                      children: [
                        Icon(icon, color: Colors.white, size: 12),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                value,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                title,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 7,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: Colors.white, size: isMobile ? 16 : 24),
                        SizedBox(height: isMobile ? 2 : 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            value,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isMobile ? 13 : 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            title,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: isMobile ? 8 : 11,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerCard extends StatefulWidget {
  final Map<String, dynamic> customer;
  final bool isMobile;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  final VoidCallback onOpenGsat;
  final VoidCallback onAddToActivation;
  final bool isAdmin;

  const _CustomerCard({
    required this.customer,
    required this.isMobile,
    required this.onEdit,
    required this.onDelete,
    required this.onTap,
    required this.onOpenGsat,
    required this.onAddToActivation,
    required this.isAdmin,
  });

  @override
  State<_CustomerCard> createState() => _CustomerCardState();
}

class _CustomerCardState extends State<_CustomerCard> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      final date = DateTime.fromMillisecondsSinceEpoch(
          timestamp is int ? timestamp : (timestamp as num).toInt());
      return DateFormat('MMM dd, yyyy \'at\' hh:mm a').format(date);
    } catch (e) {
      return 'N/A';
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'N/A';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    SnackBarUtils.showSuccess(context, 'Copied: $text', duration: const Duration(seconds: 1));
  }

  void _showCheckSubscriptionDialog() {
    final serialNumber = widget.customer['serialNumber'] ?? '';
    if (serialNumber.isEmpty) {
      SnackBarUtils.showWarning(context, 'No serial number available');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.subscriptions, color: Color(0xFF2ECC71)),
            SizedBox(width: 8),
            Text(
              'Check Subscription',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Serial Number: $serialNumber',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Plan Type:',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 12),
            // Plan 99 option
            _buildPlanOption(
              context,
              title: 'Plan 99 (GPinoy)',
              subtitle: 'gpinoysubscription.php',
              icon: Icons.looks_one,
              color: const Color(0xFF9B59B6),
              onTap: () {
                Navigator.pop(context);
                _openSubscriptionCheck(serialNumber, '99');
              },
            ),
            const SizedBox(height: 8),
            // Other plans option
            _buildPlanOption(
              context,
              title: 'Plans 69/200/300/500',
              subtitle: 'gsatsubscription.php',
              icon: Icons.grid_view,
              color: const Color(0xFF2ECC71),
              onTap: () {
                Navigator.pop(context);
                _openSubscriptionCheck(serialNumber, 'other');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanOption(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white.withValues(alpha: 0.5),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSubscriptionCheck(String serialNumber, String planType) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GsatSubscriptionCheckPage(
          serialNumber: serialNumber,
          planType: planType,
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool copiable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: widget.isMobile ? 11 : 12,
              ),
            ),
          ),
          Expanded(
            child: copiable && value != 'N/A'
                ? GestureDetector(
                    onTap: () => _copyToClipboard(value),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            value,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: widget.isMobile ? 11 : 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.copy,
                          size: widget.isMobile ? 12 : 14,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ],
                    ),
                  )
                : Text(
                    value,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.isMobile ? 11 : 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.customer['status'] == 'Active';
    final borderRadius = widget.isMobile ? 12.0 : 16.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF2A1A1A),
                const Color(0xFF1F1010),
              ],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: _isExpanded
                  ? const Color(0xFF2ECC71).withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.1),
              width: _isExpanded ? 2 : 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                // Main card row - compact when collapsed
                InkWell(
                  onTap: _toggleExpand,
                  onLongPress: widget.onTap,
                  borderRadius: BorderRadius.circular(borderRadius),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.isMobile ? 12 : 16,
                      vertical: widget.isMobile ? 10 : 12,
                    ),
                    child: Row(
                      children: [
                        // Box Number on left side
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: widget.isMobile ? 8 : 12,
                            vertical: widget.isMobile ? 6 : 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2ECC71).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(widget.isMobile ? 8 : 10),
                            border: Border.all(
                              color: const Color(0xFF2ECC71).withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            widget.customer['boxNumber'] ?? 'N/A',
                            style: TextStyle(
                              color: const Color(0xFF2ECC71),
                              fontSize: widget.isMobile ? 11 : 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(width: widget.isMobile ? 10 : 14),
                        Expanded(
                          child: Text(
                            widget.customer['name'] ?? 'Unknown',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: widget.isMobile ? 14 : 16,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Compact status indicator (dot)
                        Container(
                          width: widget.isMobile ? 10 : 12,
                          height: widget.isMobile ? 10 : 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive
                                ? const Color(0xFF2ECC71)
                                : const Color(0xFFE74C3C),
                          ),
                        ),
                        SizedBox(width: widget.isMobile ? 6 : 8),
                        // Add to Activation button (icon only when collapsed)
                        if (!_isExpanded)
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: widget.onAddToActivation,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: EdgeInsets.all(widget.isMobile ? 6 : 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF9B59B6).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFF9B59B6).withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Icon(
                                  Icons.add,
                                  color: const Color(0xFF9B59B6),
                                  size: widget.isMobile ? 16 : 20,
                                ),
                              ),
                            ),
                          ),
                        if (!_isExpanded) SizedBox(width: widget.isMobile ? 6 : 8),
                        // Load GSAT button (icon only)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: widget.onOpenGsat,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: EdgeInsets.all(widget.isMobile ? 6 : 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2ECC71).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF2ECC71).withValues(alpha: 0.5),
                                ),
                              ),
                              child: Icon(
                                Icons.open_in_browser,
                                color: const Color(0xFF2ECC71),
                                size: widget.isMobile ? 16 : 20,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: widget.isMobile ? 6 : 8),
                        // Expand/collapse icon
                        AnimatedRotation(
                          turns: _isExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 300),
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.white.withValues(alpha: 0.6),
                            size: widget.isMobile ? 18 : 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Expandable details section
                SizeTransition(
                  sizeFactor: _expandAnimation,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(
                      widget.isMobile ? 12 : 16,
                      0,
                      widget.isMobile ? 12 : 16,
                      widget.isMobile ? 12 : 16,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Customer Info Section
                          Text(
                            'Customer Information',
                            style: TextStyle(
                              color: const Color(0xFF2ECC71),
                              fontSize: widget.isMobile ? 12 : 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildDetailRow('Serial Number', widget.customer['serialNumber'] ?? 'N/A', copiable: true),
                          _buildDetailRow('Name', widget.customer['name'] ?? 'N/A'),
                          _buildDetailRow('Box Number', widget.customer['boxNumber'] ?? 'N/A'),
                          _buildDetailRow('Address', widget.customer['address'] ?? 'N/A'),
                          _buildDetailRow('Activation Date', _formatDate(widget.customer['dateOfActivation'])),
                          _buildDetailRow('Purchase Date', _formatDate(widget.customer['dateOfPurchase'])),
                          _buildDetailRow('Price', widget.customer['price'] != null
                              ? '₱${(widget.customer['price'] as num).toStringAsFixed(2)}'
                              : 'N/A'),
                          _buildDetailRow('Status', widget.customer['status'] ?? 'N/A'),

                          const SizedBox(height: 12),
                          Divider(color: Colors.white.withValues(alpha: 0.1)),
                          const SizedBox(height: 8),

                          // Record Tracking Section
                          Text(
                            'Record Tracking',
                            style: TextStyle(
                              color: const Color(0xFF2ECC71),
                              fontSize: widget.isMobile ? 12 : 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Added By
                          Row(
                            children: [
                              const Icon(
                                Icons.person_add,
                                size: 14,
                                color: Color(0xFF2ECC71),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Added by:',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: widget.isMobile ? 11 : 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.only(left: 20),
                            child: widget.customer['addedBy'] != null
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.customer['addedBy']['name'] ?? 'Unknown',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: widget.isMobile ? 11 : 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        widget.customer['addedBy']['email'] ?? '',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.5),
                                          fontSize: widget.isMobile ? 10 : 11,
                                        ),
                                      ),
                                      Text(
                                        _formatTimestamp(widget.customer['addedBy']['timestamp']),
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.4),
                                          fontSize: widget.isMobile ? 10 : 11,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    'Not recorded',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.4),
                                      fontSize: widget.isMobile ? 11 : 12,
                                    ),
                                  ),
                          ),

                          const SizedBox(height: 8),

                          // Last Updated By
                          Row(
                            children: [
                              const Icon(
                                Icons.edit_note,
                                size: 14,
                                color: Color(0xFF3498DB),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Last updated by:',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: widget.isMobile ? 11 : 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.only(left: 20),
                            child: widget.customer['lastUpdatedBy'] != null
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.customer['lastUpdatedBy']['name'] ?? 'Unknown',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: widget.isMobile ? 11 : 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        widget.customer['lastUpdatedBy']['email'] ?? '',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.5),
                                          fontSize: widget.isMobile ? 10 : 11,
                                        ),
                                      ),
                                      Text(
                                        _formatTimestamp(widget.customer['lastUpdatedBy']['timestamp']),
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.4),
                                          fontSize: widget.isMobile ? 10 : 11,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    'Not yet updated',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.4),
                                      fontSize: widget.isMobile ? 11 : 12,
                                    ),
                                  ),
                          ),

                          const SizedBox(height: 12),
                          Divider(color: Colors.white.withValues(alpha: 0.1)),
                          const SizedBox(height: 8),

                          // Action buttons
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              TextButton.icon(
                                onPressed: _showCheckSubscriptionDialog,
                                icon: const Icon(Icons.subscriptions, size: 16, color: Color(0xFF9B59B6)),
                                label: Text(
                                  'Check Sub',
                                  style: TextStyle(
                                    color: const Color(0xFF9B59B6),
                                    fontSize: widget.isMobile ? 12 : 14,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: widget.onAddToActivation,
                                icon: const Icon(Icons.add_circle, size: 16, color: Color(0xFFF39C12)),
                                label: Text(
                                  'Add to Activation',
                                  style: TextStyle(
                                    color: const Color(0xFFF39C12),
                                    fontSize: widget.isMobile ? 12 : 14,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: widget.onOpenGsat,
                                icon: const Icon(Icons.open_in_new, size: 16, color: Color(0xFF2ECC71)),
                                label: Text(
                                  'Open GSAT',
                                  style: TextStyle(
                                    color: const Color(0xFF2ECC71),
                                    fontSize: widget.isMobile ? 12 : 14,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: widget.onEdit,
                                icon: const Icon(Icons.edit, size: 16, color: Color(0xFF3498DB)),
                                label: Text(
                                  'Edit',
                                  style: TextStyle(
                                    color: const Color(0xFF3498DB),
                                    fontSize: widget.isMobile ? 12 : 14,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: widget.onDelete,
                                icon: Icon(
                                  widget.isAdmin ? Icons.delete : Icons.delete_outline,
                                  size: 16,
                                  color: const Color(0xFFE74C3C),
                                ),
                                label: Text(
                                  widget.isAdmin ? 'Delete' : 'Request Delete',
                                  style: TextStyle(
                                    color: const Color(0xFFE74C3C),
                                    fontSize: widget.isMobile ? 12 : 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isMobile;
  final VoidCallback onScan;

  const _EmptyState({required this.isMobile, required this.onScan});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.public,
            size: isMobile ? 64 : 80,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No Customers Yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: isMobile ? 18 : 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scan a serial number to add your first GSAT customer',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: isMobile ? 14 : 16,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onScan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan Serial Number'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2ECC71),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaginationControls extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int totalItems;
  final int itemsPerPage;
  final VoidCallback onNextPage;
  final VoidCallback onPreviousPage;
  final Function(int) onGoToPage;
  final bool isMobile;
  final Color primaryColor;

  const _PaginationControls({
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.itemsPerPage,
    required this.onNextPage,
    required this.onPreviousPage,
    required this.onGoToPage,
    required this.isMobile,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final startItem = currentPage * itemsPerPage + 1;
    final endItem = ((currentPage + 1) * itemsPerPage).clamp(0, totalItems);

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      margin: EdgeInsets.only(top: isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Page info
          Text(
            'Showing $startItem-$endItem of $totalItems',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: isMobile ? 12 : 14,
            ),
          ),
          SizedBox(height: isMobile ? 8 : 12),
          // Navigation controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Previous button
              IconButton(
                onPressed: currentPage > 0 ? onPreviousPage : null,
                icon: const Icon(Icons.chevron_left),
                color: primaryColor,
                disabledColor: Colors.white.withValues(alpha: 0.3),
                iconSize: isMobile ? 24 : 28,
              ),
              SizedBox(width: isMobile ? 8 : 16),
              // Page numbers
              ...List.generate(
                totalPages > 5 ? 5 : totalPages,
                (index) {
                  int pageNumber;
                  if (totalPages <= 5) {
                    pageNumber = index;
                  } else if (currentPage < 3) {
                    pageNumber = index;
                  } else if (currentPage > totalPages - 4) {
                    pageNumber = totalPages - 5 + index;
                  } else {
                    pageNumber = currentPage - 2 + index;
                  }

                  if (pageNumber >= totalPages) return const SizedBox.shrink();

                  final isCurrentPage = pageNumber == currentPage;
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 2 : 4),
                    child: InkWell(
                      onTap: () => onGoToPage(pageNumber),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: isMobile ? 32 : 40,
                        height: isMobile ? 32 : 40,
                        decoration: BoxDecoration(
                          color: isCurrentPage
                              ? primaryColor
                              : Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isCurrentPage
                                ? primaryColor
                                : Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '${pageNumber + 1}',
                            style: TextStyle(
                              color: isCurrentPage
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.7),
                              fontSize: isMobile ? 12 : 14,
                              fontWeight: isCurrentPage ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              SizedBox(width: isMobile ? 8 : 16),
              // Next button
              IconButton(
                onPressed: currentPage < totalPages - 1 ? onNextPage : null,
                icon: const Icon(Icons.chevron_right),
                color: primaryColor,
                disabledColor: Colors.white.withValues(alpha: 0.3),
                iconSize: isMobile ? 24 : 28,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
