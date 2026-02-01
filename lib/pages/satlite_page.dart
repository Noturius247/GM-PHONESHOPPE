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

class SatlitePage extends StatefulWidget {
  const SatlitePage({super.key});

  @override
  State<SatlitePage> createState() => _SatlitePageState();
}

class _SatlitePageState extends State<SatlitePage> with TickerProviderStateMixin {
  late AnimationController _scaleAnimationController;
  late Animation<double> _scaleAnimation;

  // Satlite gradient colors matching admin page
  static const satliteGradient = [Color(0xFFFF6B35), Color(0xFFCC5528)];

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
    _scaleAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(
        parent: _scaleAnimationController,
        curve: Curves.easeOut,
      ),
    );
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
    final sortSetting = await POSSettingsService.getSortSetting('satellite');

    var customers = await FirebaseDatabaseService.getCustomers(FirebaseDatabaseService.satellite);

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
      customer['ccaNumber'] ?? '',
      customer['serialNumber'] ?? '',
      customer['boxNumber'] ?? '',
      customer['accountNumber'] ?? '',
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
    _scaleAnimationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openScanner() async {
    final result = await Navigator.push<MultiScanResult>(
      context,
      MaterialPageRoute(
        builder: (context) => MultiScannerPage(
          serviceType: FirebaseDatabaseService.satellite,
          serviceName: 'Satellite',
          primaryColor: satliteGradient[0],
        ),
      ),
    );

    await _processMultiScanResult(result);
  }

  Future<void> _openOcrScanner() async {
    final ocrData = await Navigator.push<OcrExtractedData>(
      context,
      MaterialPageRoute(
        builder: (context) => OcrScannerPage(
          serviceName: 'Satellite',
          primaryColor: satliteGradient[0],
        ),
      ),
    );

    await _processOcrData(ocrData);
  }

  Future<void> _processOcrData(OcrExtractedData? ocrData) async {
    if (ocrData == null || !ocrData.hasAnyData) return;

    // Check if CCA number already exists
    if (ocrData.ccaNumber != null && ocrData.ccaNumber!.isNotEmpty) {
      final exists = await FirebaseDatabaseService.serialNumberExists(
        FirebaseDatabaseService.satellite,
        ocrData.ccaNumber!,
      );

      if (exists) {
        if (!mounted) return;
        final customer = await FirebaseDatabaseService.getCustomerBySerialNumber(
          FirebaseDatabaseService.satellite,
          ocrData.ccaNumber!,
        );
        await ErrorDialog.showDuplicate(
          context: context,
          fieldName: 'CCA Number',
          existingCustomerName: customer?['name'],
        );
        if (customer != null && mounted) {
          _showCustomerDetailsDialog(customer);
        }
        return;
      }
    }

    // Check serial number if present
    if (ocrData.serialNumber != null && ocrData.serialNumber!.isNotEmpty) {
      final exists = await FirebaseDatabaseService.serialNumberExists(
        FirebaseDatabaseService.satellite,
        ocrData.serialNumber!,
      );

      if (exists) {
        if (!mounted) return;
        final customer = await FirebaseDatabaseService.getCustomerBySerialNumber(
          FirebaseDatabaseService.satellite,
          ocrData.serialNumber!,
        );
        await ErrorDialog.showDuplicate(
          context: context,
          fieldName: 'Serial Number',
          existingCustomerName: customer?['name'],
        );
        if (customer != null && mounted) {
          _showCustomerDetailsDialog(customer);
        }
        return;
      }
    }

    if (!mounted) return;
    _showAddCustomerDialogWithOcrData(ocrData);
  }

  void _showAddCustomerDialogWithOcrData(OcrExtractedData ocrData) {
    final ccaNumberController = TextEditingController(text: ocrData.ccaNumber ?? '');
    final serialNumberController = TextEditingController(text: ocrData.serialNumber ?? '');
    final boxNumberController = TextEditingController(text: ocrData.boxNumber ?? '');
    final nameController = TextEditingController(text: ocrData.name ?? '');
    final accountNumberController = TextEditingController();
    final addressController = TextEditingController();
    final priceController = TextEditingController();
    DateTime? dateOfActivation;
    DateTime? dateOfPurchase;
    String selectedStatus = 'Active';
    String selectedSupplier = 'Masbate';

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
              Icon(Icons.document_scanner, color: satliteGradient[0], size: 24),
              const SizedBox(width: 8),
              const Text(
                'OCR Scan Result',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTextField(
                    controller: ccaNumberController,
                    label: 'CCA No.',
                    icon: Icons.qr_code,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: serialNumberController,
                    label: 'Serial No. (S/NO)',
                    icon: Icons.qr_code_scanner,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: boxNumberController,
                    label: 'Box No. / STB ID',
                    icon: Icons.inventory_2,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: nameController,
                    label: 'Name',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: accountNumberController,
                    label: 'Account Number',
                    icon: Icons.account_circle,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: addressController,
                    label: 'Address',
                    icon: Icons.location_on,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
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
                                primary: satliteGradient[0],
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
                                primary: satliteGradient[0],
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
                  _buildTextField(
                    controller: priceController,
                    label: 'Price',
                    icon: Icons.attach_money,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  // Supplier
                  DropdownButtonFormField<String>(
                    value: selectedSupplier,
                    dropdownColor: const Color(0xFF2A1A1A),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                    decoration: InputDecoration(
                      labelText: 'Supplier',
                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      prefixIcon: Icon(Icons.store, color: satliteGradient[0]),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: satliteGradient[0]),
                      ),
                    ),
                    items: ['Masbate', 'Cebu'].map((supplier) {
                      return DropdownMenuItem(
                        value: supplier,
                        child: Text(
                          supplier,
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedSupplier = value!);
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    dropdownColor: const Color(0xFF2A1A1A),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Status',
                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      prefixIcon: Icon(Icons.flag, color: satliteGradient[0]),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: satliteGradient[0]),
                      ),
                    ),
                    items: ['Active', 'Inactive', 'Pending'].map((status) {
                      return DropdownMenuItem(
                        value: status,
                        child: Text(status, style: const TextStyle(color: Colors.white)),
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
                final List<String> missingFields = [];
                if (nameController.text.isEmpty) {
                  missingFields.add('Name');
                }
                if (accountNumberController.text.isEmpty) {
                  missingFields.add('Account Number');
                }
                if (missingFields.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Please fill in: ${missingFields.join(', ')}'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                // Check connectivity before adding
                final hasConnection = await CacheService.hasConnectivity();
                if (!hasConnection) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No internet connection. Cannot add customer offline.'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final currentUser = await AuthService.getCurrentUser();

                final customerData = <String, dynamic>{
                  'name': nameController.text,
                  'status': selectedStatus,
                };
                if (serialNumberController.text.isNotEmpty) {
                  customerData['serialNumber'] = serialNumberController.text;
                }
                if (ccaNumberController.text.isNotEmpty) {
                  customerData['ccaNumber'] = ccaNumberController.text;
                }
                if (boxNumberController.text.isNotEmpty) {
                  customerData['boxNumber'] = boxNumberController.text;
                }
                if (accountNumberController.text.isNotEmpty) {
                  customerData['accountNumber'] = accountNumberController.text;
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
                customerData['supplier'] = selectedSupplier;

                // Add customer directly (no approval needed for adding)
                final result = await FirebaseDatabaseService.addCustomer(
                  serviceType: FirebaseDatabaseService.satellite,
                  serialNumber: customerData['serialNumber'],
                  ccaNumber: customerData['ccaNumber'],
                  name: customerData['name'],
                  status: customerData['status'],
                  boxNumber: customerData['boxNumber'],
                  accountNumber: customerData['accountNumber'],
                  address: customerData['address'],
                  dateOfActivation: customerData['dateOfActivation'],
                  dateOfPurchase: customerData['dateOfPurchase'],
                  price: customerData['price'],
                  supplier: customerData['supplier'],
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

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Customer added successfully!'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  if (!context.mounted) return;
                  await ErrorDialog.showSaveError(context: context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: satliteGradient[0],
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
                  'Choose how to enter the serial number',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 24),
                _buildScanOptionTile(
                  icon: Icons.qr_code_scanner,
                  title: 'Scan Barcodes',
                  subtitle: 'Scan multiple codes (CCA, Serial, STB ID)',
                  onTap: () {
                    Navigator.pop(context);
                    _openScanner();
                  },
                ),
                const SizedBox(height: 12),
                _buildScanOptionTile(
                  icon: Icons.document_scanner,
                  title: 'OCR Text Scanner',
                  subtitle: 'Take photo of serial number text',
                  onTap: () {
                    Navigator.pop(context);
                    _openOcrScanner();
                  },
                ),
                const SizedBox(height: 12),
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
          color: satliteGradient[0].withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: satliteGradient[0].withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: satliteGradient[0],
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
    final ccaNumberController = TextEditingController();
    final serialNumberController = TextEditingController();
    final boxNumberController = TextEditingController();
    final nameController = TextEditingController();
    final accountNumberController = TextEditingController();
    final addressController = TextEditingController();
    final priceController = TextEditingController();
    DateTime? dateOfActivation;
    DateTime? dateOfPurchase;
    String selectedStatus = 'Active';
    String selectedSupplier = 'Masbate';

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
              Icon(Icons.edit, color: satliteGradient[0], size: 24),
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
                  _buildTextField(
                    controller: ccaNumberController,
                    label: 'CCA No.',
                    icon: Icons.qr_code,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: serialNumberController,
                    label: 'Serial No. (S/NO)',
                    icon: Icons.qr_code_scanner,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: boxNumberController,
                    label: 'Box No. / STB ID',
                    icon: Icons.inventory_2,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: nameController,
                    label: 'Name',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: accountNumberController,
                    label: 'Account Number',
                    icon: Icons.account_circle,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: addressController,
                    label: 'Address',
                    icon: Icons.location_on,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
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
                                primary: satliteGradient[0],
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
                                primary: satliteGradient[0],
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
                  _buildTextField(
                    controller: priceController,
                    label: 'Price',
                    icon: Icons.attach_money,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  // Supplier
                  DropdownButtonFormField<String>(
                    value: selectedSupplier,
                    dropdownColor: const Color(0xFF2A1A1A),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                    decoration: InputDecoration(
                      labelText: 'Supplier',
                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      prefixIcon: Icon(Icons.store, color: satliteGradient[0]),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: satliteGradient[0]),
                      ),
                    ),
                    items: ['Masbate', 'Cebu'].map((supplier) {
                      return DropdownMenuItem(
                        value: supplier,
                        child: Text(
                          supplier,
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedSupplier = value!);
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    dropdownColor: const Color(0xFF2A1A1A),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Status',
                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      prefixIcon: Icon(Icons.flag, color: satliteGradient[0]),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: satliteGradient[0]),
                      ),
                    ),
                    items: ['Active', 'Inactive', 'Pending'].map((status) {
                      return DropdownMenuItem(
                        value: status,
                        child: Text(status, style: const TextStyle(color: Colors.white)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedStatus = value!);
                    },
                  ),
                  const SizedBox(height: 16),
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
                final List<String> missingFields = [];
                if (nameController.text.isEmpty) {
                  missingFields.add('Name');
                }
                if (accountNumberController.text.isEmpty) {
                  missingFields.add('Account Number');
                }
                if (missingFields.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Please fill in: ${missingFields.join(', ')}'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                // Check for duplicate CCA number
                if (ccaNumberController.text.isNotEmpty) {
                  final ccaExists = await FirebaseDatabaseService.ccaNumberExists(
                    FirebaseDatabaseService.satellite,
                    ccaNumberController.text,
                  );
                  if (ccaExists) {
                    if (!context.mounted) return;
                    final existingCustomer = await FirebaseDatabaseService.getCustomerByCcaNumber(
                      FirebaseDatabaseService.satellite,
                      ccaNumberController.text,
                    );
                    await ErrorDialog.showDuplicate(
                      context: context,
                      fieldName: 'CCA Number',
                      existingCustomerName: existingCustomer?['name'],
                    );
                    return;
                  }
                }

                // Check for duplicate account number
                if (accountNumberController.text.isNotEmpty) {
                  final accountExists = await FirebaseDatabaseService.accountNumberExists(
                    FirebaseDatabaseService.satellite,
                    accountNumberController.text,
                  );
                  if (accountExists) {
                    if (!context.mounted) return;
                    final existingCustomer = await FirebaseDatabaseService.getCustomerByAccountNumber(
                      FirebaseDatabaseService.satellite,
                      accountNumberController.text,
                    );
                    await ErrorDialog.showDuplicate(
                      context: context,
                      fieldName: 'Account Number',
                      existingCustomerName: existingCustomer?['name'],
                    );
                    return;
                  }
                }

                final currentUser = await AuthService.getCurrentUser();

                final customerData = <String, dynamic>{
                  'name': nameController.text,
                  'status': selectedStatus,
                };
                if (serialNumberController.text.isNotEmpty) {
                  customerData['serialNumber'] = serialNumberController.text;
                }
                if (ccaNumberController.text.isNotEmpty) {
                  customerData['ccaNumber'] = ccaNumberController.text;
                }
                if (boxNumberController.text.isNotEmpty) {
                  customerData['boxNumber'] = boxNumberController.text;
                }
                if (accountNumberController.text.isNotEmpty) {
                  customerData['accountNumber'] = accountNumberController.text;
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
                customerData['supplier'] = selectedSupplier;

                // Add customer directly (no approval needed for adding)
                final result = await FirebaseDatabaseService.addCustomer(
                  serviceType: FirebaseDatabaseService.satellite,
                  serialNumber: customerData['serialNumber'],
                  ccaNumber: customerData['ccaNumber'],
                  name: customerData['name'],
                  status: customerData['status'],
                  boxNumber: customerData['boxNumber'],
                  accountNumber: customerData['accountNumber'],
                  address: customerData['address'],
                  dateOfActivation: customerData['dateOfActivation'],
                  dateOfPurchase: customerData['dateOfPurchase'],
                  price: customerData['price'],
                  supplier: customerData['supplier'],
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

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Customer added successfully!'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  if (!context.mounted) return;
                  await ErrorDialog.showSaveError(context: context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: satliteGradient[0],
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

  Future<void> _processMultiScanResult(MultiScanResult? result) async {
    if (result == null || result.allScannedItems.isEmpty) return;

    // Check if any of the scanned codes already exist
    final serialToCheck = result.serialNumber ?? result.ccaNumber;
    if (serialToCheck != null) {
      final exists = await FirebaseDatabaseService.serialNumberExists(
        FirebaseDatabaseService.satellite,
        serialToCheck,
      );

      if (exists) {
        if (!mounted) return;
        // Show existing customer details
        final customer = await FirebaseDatabaseService.getCustomerBySerialNumber(
          FirebaseDatabaseService.satellite,
          serialToCheck,
        );
        await ErrorDialog.showDuplicate(
          context: context,
          fieldName: 'Code',
          existingCustomerName: customer?['name'],
        );
        if (customer != null && mounted) {
          _showCustomerDetailsDialog(customer);
        }
        return;
      }
    }

    // Show add customer dialog with all scanned codes pre-filled
    if (!mounted) return;
    _showAddCustomerDialogWithMultiScan(result);
  }

  void _showAddCustomerDialogWithMultiScan(MultiScanResult scanResult) {
    final ccaNumberController = TextEditingController(text: scanResult.ccaNumber ?? '');
    final serialNumberController = TextEditingController(text: scanResult.serialNumber ?? '');
    final boxNumberController = TextEditingController(text: scanResult.stbId ?? '');
    final nameController = TextEditingController();
    final accountNumberController = TextEditingController();
    final addressController = TextEditingController();
    final priceController = TextEditingController();
    DateTime? dateOfActivation;
    DateTime? dateOfPurchase;
    String selectedStatus = 'Active';
    String selectedSupplier = 'Masbate';

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
            width: MediaQuery.of(context).size.width * 0.8,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Scanned codes display
                  if (scanResult.allScannedItems.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: satliteGradient[0].withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: satliteGradient[0].withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.qr_code_scanner, color: satliteGradient[0], size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Scanned Codes (${scanResult.allScannedItems.length})',
                                style: TextStyle(
                                  color: satliteGradient[0],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...scanResult.allScannedItems.map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: satliteGradient[0],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    item.label,
                                    style: const TextStyle(color: Colors.white, fontSize: 10),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.code,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          )),
                        ],
                      ),
                    ),
                  // CCA Number field
                  _buildTextField(
                    controller: ccaNumberController,
                    label: 'CCA No.',
                    icon: Icons.qr_code,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  // Serial Number field
                  _buildTextField(
                    controller: serialNumberController,
                    label: 'Serial No. (S/NO)',
                    icon: Icons.qr_code_scanner,
                  ),
                  const SizedBox(height: 16),
                  // Box Number / STB ID
                  _buildTextField(
                    controller: boxNumberController,
                    label: 'Box No. / STB ID',
                    icon: Icons.inventory_2,
                  ),
                  const SizedBox(height: 16),
                  // Name
                  _buildTextField(
                    controller: nameController,
                    label: 'Name',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 16),
                  // Account Number
                  _buildTextField(
                    controller: accountNumberController,
                    label: 'Account Number',
                    icon: Icons.account_circle,
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
                                primary: satliteGradient[0],
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
                                primary: satliteGradient[0],
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
                  // Supplier
                  // Supplier
                  DropdownButtonFormField<String>(
                    value: selectedSupplier,
                    dropdownColor: const Color(0xFF2A1A1A),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                    decoration: InputDecoration(
                      labelText: 'Supplier',
                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      prefixIcon: Icon(Icons.store, color: satliteGradient[0]),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: satliteGradient[0]),
                      ),
                    ),
                    items: ['Masbate', 'Cebu'].map((supplier) {
                      return DropdownMenuItem(
                        value: supplier,
                        child: Text(
                          supplier,
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedSupplier = value!);
                    },
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
                      prefixIcon: Icon(Icons.flag, color: satliteGradient[0]),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: satliteGradient[0]),
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
                final List<String> missingFields = [];
                if (nameController.text.isEmpty) {
                  missingFields.add('Name');
                }
                if (accountNumberController.text.isEmpty) {
                  missingFields.add('Account Number');
                }
                if (missingFields.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Please fill in: ${missingFields.join(', ')}'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                // Check for duplicate CCA number
                if (ccaNumberController.text.isNotEmpty) {
                  final ccaExists = await FirebaseDatabaseService.ccaNumberExists(
                    FirebaseDatabaseService.satellite,
                    ccaNumberController.text,
                  );
                  if (ccaExists) {
                    if (!context.mounted) return;
                    final existingCustomer = await FirebaseDatabaseService.getCustomerByCcaNumber(
                      FirebaseDatabaseService.satellite,
                      ccaNumberController.text,
                    );
                    await ErrorDialog.showDuplicate(
                      context: context,
                      fieldName: 'CCA Number',
                      existingCustomerName: existingCustomer?['name'],
                    );
                    return;
                  }
                }

                // Check for duplicate account number
                if (accountNumberController.text.isNotEmpty) {
                  final accountExists = await FirebaseDatabaseService.accountNumberExists(
                    FirebaseDatabaseService.satellite,
                    accountNumberController.text,
                  );
                  if (accountExists) {
                    if (!context.mounted) return;
                    final existingCustomer = await FirebaseDatabaseService.getCustomerByAccountNumber(
                      FirebaseDatabaseService.satellite,
                      accountNumberController.text,
                    );
                    await ErrorDialog.showDuplicate(
                      context: context,
                      fieldName: 'Account Number',
                      existingCustomerName: existingCustomer?['name'],
                    );
                    return;
                  }
                }

                // Check connectivity before adding
                final hasConnection = await CacheService.hasConnectivity();
                if (!hasConnection) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No internet connection. Cannot add customer offline.'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Get current user info for tracking
                final currentUser = await AuthService.getCurrentUser();

                // Prepare customer data
                final customerData = <String, dynamic>{
                  'name': nameController.text,
                  'status': selectedStatus,
                };
                if (serialNumberController.text.isNotEmpty) {
                  customerData['serialNumber'] = serialNumberController.text;
                }
                if (ccaNumberController.text.isNotEmpty) {
                  customerData['ccaNumber'] = ccaNumberController.text;
                }
                if (boxNumberController.text.isNotEmpty) {
                  customerData['boxNumber'] = boxNumberController.text;
                }
                if (accountNumberController.text.isNotEmpty) {
                  customerData['accountNumber'] = accountNumberController.text;
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
                customerData['supplier'] = selectedSupplier;

                // Add customer directly (no approval needed for adding)
                final result = await FirebaseDatabaseService.addCustomer(
                  serviceType: FirebaseDatabaseService.satellite,
                  serialNumber: customerData['serialNumber'],
                  ccaNumber: customerData['ccaNumber'],
                  name: customerData['name'],
                  status: customerData['status'],
                  boxNumber: customerData['boxNumber'],
                  accountNumber: customerData['accountNumber'],
                  address: customerData['address'],
                  dateOfActivation: customerData['dateOfActivation'],
                  dateOfPurchase: customerData['dateOfPurchase'],
                  price: customerData['price'],
                  supplier: customerData['supplier'],
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

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Customer added successfully!'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  if (!context.mounted) return;
                  await ErrorDialog.showSaveError(context: context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: satliteGradient[0],
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      cursorColor: satliteGradient[0],
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        prefixIcon: Icon(icon, color: satliteGradient[0]),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: satliteGradient[0]),
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
            Icon(Icons.calendar_today, color: satliteGradient[0]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value != null
                        ? DateFormat('MMM dd, yyyy').format(value)
                        : 'Select date',
                    style: TextStyle(
                      color: value != null ? Colors.white : Colors.white.withValues(alpha: 0.5),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              color: Colors.white.withValues(alpha: 0.7),
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
        title: const Text(
          'Customer Details',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (customer['serialNumber'] != null && customer['serialNumber'].toString().isNotEmpty)
                _detailRow('Serial No. (S/N)', customer['serialNumber']),
              if (customer['ccaNumber'] != null && customer['ccaNumber'].toString().isNotEmpty)
                _detailRow('CCA No.', customer['ccaNumber']),
              if (customer['boxNumber'] != null && customer['boxNumber'].toString().isNotEmpty)
                _detailRow('Box No.', customer['boxNumber']),
              _detailRow('Name', customer['name'] ?? 'N/A'),
              if (customer['accountNumber'] != null && customer['accountNumber'].toString().isNotEmpty)
                _detailRow('Account No.', customer['accountNumber']),
              if (customer['address'] != null && customer['address'].toString().isNotEmpty)
                _detailRow('Address', customer['address']),
              if (customer['dateOfActivation'] != null && customer['dateOfActivation'].toString().isNotEmpty)
                _detailRow('Activation Date', _formatDate(customer['dateOfActivation'])),
              if (customer['dateOfPurchase'] != null && customer['dateOfPurchase'].toString().isNotEmpty)
                _detailRow('Purchase Date', _formatDate(customer['dateOfPurchase'])),
              if (customer['price'] != null)
                _detailRow('Price', '₱${customer['price'].toString()}'),
              if (customer['supplier'] != null && customer['supplier'].toString().isNotEmpty)
                _detailRow('Supplier', customer['supplier']),
              _detailRow('Status', customer['status'] ?? 'N/A'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.white)),
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
    final serialNumberController = TextEditingController(text: customer['serialNumber'] ?? '');
    final ccaNumberController = TextEditingController(text: customer['ccaNumber'] ?? '');
    final boxNumberController = TextEditingController(text: customer['boxNumber'] ?? '');
    final nameController = TextEditingController(text: customer['name'] ?? '');
    final accountNumberController = TextEditingController(text: customer['accountNumber'] ?? '');
    final addressController = TextEditingController(text: customer['address'] ?? '');
    final priceController = TextEditingController(
      text: customer['price'] != null ? customer['price'].toString() : '',
    );

    DateTime? dateOfActivation;
    DateTime? dateOfPurchase;

    // Parse existing dates
    if (customer['dateOfActivation'] != null) {
      try {
        dateOfActivation = DateTime.parse(customer['dateOfActivation']);
      } catch (e) {
        // ignore parsing error
      }
    }
    if (customer['dateOfPurchase'] != null) {
      try {
        dateOfPurchase = DateTime.parse(customer['dateOfPurchase']);
      } catch (e) {
        // ignore parsing error
      }
    }

    String selectedStatus = customer['status'] ?? 'Active';
    String selectedSupplier = customer['supplier'] ?? 'Masbate';

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
            width: MediaQuery.of(context).size.width * 0.8,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Serial Number (editable)
                  _buildTextField(
                    controller: serialNumberController,
                    label: 'Serial No. (S/N)',
                    icon: Icons.qr_code,
                  ),
                  const SizedBox(height: 16),
                  // CCA Number (editable)
                  _buildTextField(
                    controller: ccaNumberController,
                    label: 'CCA No.',
                    icon: Icons.confirmation_number,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  // Box Number
                  _buildTextField(
                    controller: boxNumberController,
                    label: 'Box No.',
                    icon: Icons.inventory_2,
                  ),
                  const SizedBox(height: 16),
                  // Name
                  _buildTextField(
                    controller: nameController,
                    label: 'Name',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 16),
                  // Account Number
                  _buildTextField(
                    controller: accountNumberController,
                    label: 'Account Number',
                    icon: Icons.account_circle,
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
                                primary: satliteGradient[0],
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
                                primary: satliteGradient[0],
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
                  // Supplier
                  // Supplier
                  DropdownButtonFormField<String>(
                    value: selectedSupplier,
                    dropdownColor: const Color(0xFF2A1A1A),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                    decoration: InputDecoration(
                      labelText: 'Supplier',
                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      prefixIcon: Icon(Icons.store, color: satliteGradient[0]),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: satliteGradient[0]),
                      ),
                    ),
                    items: ['Masbate', 'Cebu'].map((supplier) {
                      return DropdownMenuItem(
                        value: supplier,
                        child: Text(
                          supplier,
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedSupplier = value!);
                    },
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
                      prefixIcon: Icon(Icons.flag, color: satliteGradient[0]),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: satliteGradient[0]),
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

                final List<String> missingFields = [];
                if (nameController.text.isEmpty) {
                  missingFields.add('Name');
                }
                if (accountNumberController.text.isEmpty) {
                  missingFields.add('Account Number');
                }
                if (missingFields.isNotEmpty) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Please fill in: ${missingFields.join(', ')}'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                // Close dialog immediately and show saving indicator
                navigator.pop();

                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Row(
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
                    duration: Duration(seconds: 30),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Color(0xFF3498DB),
                  ),
                );

                final success = await FirebaseDatabaseService.updateCustomer(
                  serviceType: FirebaseDatabaseService.satellite,
                  customerId: customer['id'],
                  serialNumber: serialNumberController.text,
                  ccaNumber: ccaNumberController.text,
                  boxNumber: boxNumberController.text,
                  name: nameController.text,
                  accountNumber: accountNumberController.text,
                  address: addressController.text,
                  dateOfActivation: dateOfActivation != null
                      ? DateFormat('yyyy-MM-dd').format(dateOfActivation!)
                      : null,
                  dateOfPurchase: dateOfPurchase != null
                      ? DateFormat('yyyy-MM-dd').format(dateOfPurchase!)
                      : null,
                  price: priceController.text.isNotEmpty
                      ? double.tryParse(priceController.text)
                      : null,
                  supplier: selectedSupplier,
                  status: selectedStatus,
                );

                if (!mounted) return;

                scaffoldMessenger.hideCurrentSnackBar();

                if (success) {
                  // Update customer incrementally instead of reloading all
                  final customerId = customer['id'];
                  final index = _customers.indexWhere((c) => c['id'] == customerId);

                  if (index != -1) {
                    final updatedCustomer = Map<String, dynamic>.from(_customers[index]);
                    updatedCustomer['serialNumber'] = serialNumberController.text;
                    updatedCustomer['ccaNumber'] = ccaNumberController.text;
                    updatedCustomer['boxNumber'] = boxNumberController.text;
                    updatedCustomer['name'] = nameController.text;
                    updatedCustomer['accountNumber'] = accountNumberController.text;
                    updatedCustomer['address'] = addressController.text;
                    updatedCustomer['dateOfActivation'] = dateOfActivation != null
                        ? DateFormat('yyyy-MM-dd').format(dateOfActivation!)
                        : null;
                    updatedCustomer['dateOfPurchase'] = dateOfPurchase != null
                        ? DateFormat('yyyy-MM-dd').format(dateOfPurchase!)
                        : null;
                    updatedCustomer['price'] = priceController.text.isNotEmpty
                        ? double.tryParse(priceController.text)
                        : null;
                    updatedCustomer['supplier'] = selectedSupplier;
                    updatedCustomer['status'] = selectedStatus;
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

                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Customer ${nameController.text} updated successfully!'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  await ErrorDialog.showSaveError(
                    context: context,
                    customMessage: 'Failed to update customer.\n\nPlease check your internet connection and try again.',
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: satliteGradient[0],
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
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final reasonText = reasonController.text.trim();
              Navigator.of(context).pop();

              final currentUser = await AuthService.getCurrentUser();
              final isAdmin = currentUser != null && AuthService.isAdmin(currentUser);

              if (isAdmin) {
                // Admin: Delete directly
                final success = await FirebaseDatabaseService.deleteCustomer(
                  FirebaseDatabaseService.satellite,
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

                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('${customer['name']} deleted'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: const Color(0xFFE74C3C),
                    ),
                  );
                } else {
                  await ErrorDialog.showSaveError(
                    context: context,
                    customMessage: 'Failed to delete customer.\n\nPlease check your internet connection and try again.',
                  );
                }
              } else {
                // Non-admin: Submit delete suggestion with reason
                final customerData = Map<String, dynamic>.from(customer);
                customerData.remove('id');

                final result = await FirebaseDatabaseService.submitSuggestion(
                  serviceType: FirebaseDatabaseService.satellite,
                  type: 'delete',
                  customerId: customer['id'],
                  customerData: customerData,
                  submittedByEmail: currentUser?['email'] ?? '',
                  submittedByName: currentUser?['name'] ?? '',
                  reason: reasonText,
                );

                if (!mounted) return;

                if (result == 'duplicate') {
                  await ErrorDialog.show(
                    context: context,
                    title: 'Duplicate Request',
                    message: 'A pending delete request already exists for this customer.\n\nPlease wait for admin to review the existing request.',
                  );
                } else if (result != null) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Delete request for ${customer['name']} submitted for admin approval!'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.green,
                    ),
                  );
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
                colors: satliteGradient,
              ),
            ),
            child: Row(
              children: [
                // Logo - smaller on mobile, no background
                SizedBox(
                  width: isMobile ? 40 : 80,
                  height: isMobile ? 40 : 80,
                  child: Image.asset(
                    'Photos/SATLITE.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.satellite_alt,
                        size: isMobile ? 28 : 50,
                        color: Colors.white,
                      );
                    },
                  ),
                ),
                SizedBox(width: isMobile ? 10 : 20),
                Expanded(
                  child: Text(
                    'Satellite Services',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isMobile ? 18 : 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Action buttons - compact on mobile
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
                        hintText: 'Search by name, CCA, serial, date...',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                        prefixIcon: Icon(Icons.search, color: satliteGradient[0]),
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
                  Container(
                    decoration: BoxDecoration(
                      color: satliteGradient[0].withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: satliteGradient[0]),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.calendar_month, color: satliteGradient[0]),
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
                                  primary: satliteGradient[0],
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
                      color: Color(0xFFFF6B35),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadCustomers,
                    color: satliteGradient[0],
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
                            crossAxisCount: 4,
                            mainAxisSpacing: isCompact ? 4 : (isMobile ? 4 : 16),
                            crossAxisSpacing: isCompact ? 4 : (isMobile ? 4 : 16),
                            childAspectRatio: isCompact ? 2.0 : (isMobile ? 1.0 : 1.3),
                            children: [
                              _StatCard(
                                title: 'Total',
                                value: '${_customers.length}',
                                icon: Icons.people,
                                gradientColors: satliteGradient,
                                isMobile: isMobile,
                                isCompact: isCompact,
                              ),
                              _StatCard(
                                title: 'Active',
                                value: '$activeCount',
                                icon: Icons.check_circle,
                                gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)],
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
                                gradientColors: const [Color(0xFF3498DB), Color(0xFF2980B9)],
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
                                  backgroundColor: satliteGradient[0],
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
                          else if (_filteredCustomers.isEmpty)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.search_off,
                                      size: 48,
                                      color: Colors.white.withValues(alpha: 0.3),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No customers found',
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
                                    primaryColor: satliteGradient[0],
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
    final borderRadius = isCompact ? 8.0 : (isMobile ? 12.0 : 40.0);
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
            // Rounded rectangle decorative element - hide in compact mode
            if (!isCompact)
              Positioned(
                top: isMobile ? -15 : -30,
                right: isMobile ? -15 : -30,
                child: Container(
                  width: isMobile ? 50 : 120,
                  height: isMobile ? 50 : 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(isMobile ? 12 : 30),
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.all(isCompact ? 4 : (isMobile ? 6 : 16)),
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
                                  fontSize: 12,
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
                        Icon(icon, color: Colors.white, size: isMobile ? 16 : 32),
                        SizedBox(height: isMobile ? 2 : 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            value,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isMobile ? 14 : 32,
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
                              fontSize: isMobile ? 8 : 14,
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
  final bool isAdmin;

  const _CustomerCard({
    required this.customer,
    required this.isMobile,
    required this.onEdit,
    required this.onDelete,
    required this.onTap,
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied: $text'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFFFF6B35),
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
                  ? const Color(0xFFFF6B35).withValues(alpha: 0.5)
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
                            color: const Color(0xFFFF6B35).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(widget.isMobile ? 8 : 10),
                            border: Border.all(
                              color: const Color(0xFFFF6B35).withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            widget.customer['boxNumber'] ?? 'N/A',
                            style: TextStyle(
                              color: const Color(0xFFFF6B35),
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
                              color: const Color(0xFFFF6B35),
                              fontSize: widget.isMobile ? 12 : 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildDetailRow('Serial No. (S/N)', widget.customer['serialNumber'] ?? 'N/A'),
                          _buildDetailRow('CCA No.', widget.customer['ccaNumber'] ?? 'N/A', copiable: true),
                          _buildDetailRow('Box No.', widget.customer['boxNumber'] ?? 'N/A'),
                          _buildDetailRow('Name', widget.customer['name'] ?? 'N/A'),
                          _buildDetailRow('Account No.', widget.customer['accountNumber'] ?? 'N/A', copiable: true),
                          _buildDetailRow('Address', widget.customer['address'] ?? 'N/A'),
                          _buildDetailRow('Activation Date', _formatDate(widget.customer['dateOfActivation'])),
                          _buildDetailRow('Purchase Date', _formatDate(widget.customer['dateOfPurchase'])),
                          _buildDetailRow('Price', widget.customer['price'] != null
                              ? '₱${(widget.customer['price'] as num).toStringAsFixed(2)}'
                              : 'N/A'),
                          _buildDetailRow('Supplier', widget.customer['supplier'] ?? 'N/A'),
                          _buildDetailRow('Status', widget.customer['status'] ?? 'N/A'),

                          const SizedBox(height: 12),
                          Divider(color: Colors.white.withValues(alpha: 0.1)),
                          const SizedBox(height: 8),

                          // Record Tracking Section
                          Text(
                            'Record Tracking',
                            style: TextStyle(
                              color: const Color(0xFFFF6B35),
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
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
                              const SizedBox(width: 8),
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
            Icons.people_outline,
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
            'Scan a serial number to add your first Satellite customer',
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
              backgroundColor: const Color(0xFFFF6B35),
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
