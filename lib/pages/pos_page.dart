import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/inventory_service.dart';
import '../services/auth_service.dart';
import '../services/pos_settings_service.dart';
import '../services/cache_service.dart';
import '../services/offline_sync_service.dart';
import '../services/pos_live_cart_service.dart';
import '../services/printer_service.dart';
import '../widgets/printer_settings_dialog.dart';
import '../widgets/pin_entry_dialog.dart';
import '../services/staff_pin_service.dart';
import 'settings_page.dart';
import 'ocr_scanner_page.dart';
import 'multi_scanner_page.dart';
import '../services/beep_service.dart';
import '../utils/snackbar_utils.dart';

class POSPage extends StatefulWidget {
  const POSPage({super.key});

  @override
  State<POSPage> createState() => _POSPageState();
}

class _POSPageState extends State<POSPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<Map<String, dynamic>> _cartItems = [];
  List<Map<String, dynamic>> _inventoryItems = [];
  List<Map<String, dynamic>> _pendingBaskets = []; // Baskets from users
  bool _isLoading = true;
  bool _isProcessing = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _cashReceivedController = TextEditingController();
  final TextEditingController _referenceNumberController = TextEditingController();
  String _currentUserEmail = '';
  String _currentUserName = '';
  String _paymentMethod = 'cash';
  String _feeHandling = 'customer_pays'; // customer_pays, business_absorbs
  Map<String, dynamic>? _selectedBasket; // Currently selected basket for processing
  String? _expandedProductId; // Track which product tile is expanded in mobile view

  // VAT Settings
  bool _vatEnabled = true;
  double _vatRate = 12.0;
  bool _vatInclusive = true;

  // Offline sync state
  bool _isOffline = false;
  int _pendingSyncCount = 0;
  StreamSubscription<SyncStatus>? _syncStatusSubscription;

  // Live cart sync
  StreamSubscription? _liveCartSubscription;
  bool _isSyncingFromRemote = false; // prevents echo writes
  bool _isSyncingToFirebase = false; // prevents re-entrant writes
  Timer? _syncDebounce;

  // Discount mode state
  bool _discountModeEnabled = false;
  Map<String, dynamic>? _discountAuthorizedBy; // Staff who enabled discount mode
  Map<int, double> _discountedPrices = {}; // cartItemIndex → discounted price
  Map<int, double> _originalPrices = {}; // cartItemIndex → original price

  // Dark theme colors
  static const Color _bgColor = Color(0xFF1A0A0A);
  static const Color _cardColor = Color(0xFF252525);
  static const Color _accentColor = Color(0xFFE67E22);
  static const Color _accentDark = Color(0xFFD35400);
  static const Color _textPrimary = Colors.white;
  static const Color _textSecondary = Color(0xFFB0B0B0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initApp();
  }

  /// Stagger initialization to avoid blocking the UI thread.
  /// Critical loads first, then secondary in parallel after a frame.
  Future<void> _initApp() async {
    // Phase 1: Load user info + settings (lightweight, needed for UI)
    _loadUserInfo();
    _loadPOSSettings();

    // Phase 2: After first frame, load heavier data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInventory();
      _loadPendingBaskets();
    });

    // Phase 3: Defer non-UI-blocking background tasks
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _syncStaffPins();
      _initOfflineSync();
      _initPrinter();
    });
  }

  Future<void> _initPrinter() async {
    await PrinterService.initialize();
  }

  Future<void> _initOfflineSync() async {
    // Initialize offline sync service
    await OfflineSyncService.initialize();

    // Check initial connectivity
    final hasConnection = await CacheService.hasConnectivity();
    final pendingCount = await CacheService.getPendingTransactionCount();

    if (mounted) {
      setState(() {
        _isOffline = !hasConnection;
        _pendingSyncCount = pendingCount;
      });
    }

    // Listen for sync status updates
    _syncStatusSubscription = OfflineSyncService.syncStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _pendingSyncCount = status.pendingCount;
        });

        // Show snackbar when sync completes
        if (!status.isSyncing && status.pendingCount == 0 && _pendingSyncCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All pending transactions synced successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    });
  }

  Future<void> _syncStaffPins() async {
    await StaffPinService.syncPinsToCache();
  }

  Future<void> _loadPOSSettings() async {
    final settings = await POSSettingsService.getSettings();
    if (mounted) {
      setState(() {
        _vatEnabled = settings['vatEnabled'] ?? true;
        _vatRate = (settings['vatRate'] as num?)?.toDouble() ?? 12.0;
        _vatInclusive = settings['vatInclusive'] ?? true;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _customerNameController.dispose();
    _cashReceivedController.dispose();
    _referenceNumberController.dispose();
    _syncDebounce?.cancel();
    _syncStatusSubscription?.cancel();
    _liveCartSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    final user = await AuthService.getCurrentUser();
    if (user != null) {
      setState(() {
        _currentUserEmail = user['email'] ?? '';
        _currentUserName = user['name'] ?? '';
      });
      _startLiveCartListener();
    }
  }

  void _startLiveCartListener() {
    if (_currentUserEmail.isEmpty) return;
    _liveCartSubscription?.cancel();
    _liveCartSubscription = PosLiveCartService.listenToCart(
      _currentUserEmail,
      (items, customerName) {
        if (!mounted || _isSyncingToFirebase) return;
        _isSyncingFromRemote = true;
        setState(() {
          _cartItems.clear();
          _cartItems.addAll(items);
          if (customerName.isNotEmpty && _customerNameController.text != customerName) {
            _customerNameController.text = customerName;
          }
        });
        // Use microtask to ensure flag stays true until after any sync calls triggered by setState
        Future.microtask(() => _isSyncingFromRemote = false);
      },
    );
  }

  Future<void> _loadInventory() async {
    setState(() => _isLoading = true);
    try {
      final items = await InventoryService.getAllItems();
      setState(() {
        _inventoryItems = items.where((item) {
          final quantity = item['quantity'] as int? ?? 0;
          return quantity > 0;
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading inventory: $e')),
        );
      }
    }
  }

  Future<void> _loadPendingBaskets() async {
    try {
      // Try cache first if offline
      final hasConnection = await CacheService.hasConnectivity();

      if (!hasConnection) {
        // Load from cache when offline
        final cachedBaskets = await CacheService.getPosBaskets(status: 'pending');
        if (cachedBaskets.isNotEmpty) {
          cachedBaskets.sort((a, b) {
            final aTime = a['createdAt'] as int? ?? 0;
            final bTime = b['createdAt'] as int? ?? 0;
            return aTime.compareTo(bTime);
          });
          setState(() {
            _pendingBaskets = cachedBaskets;
          });
          return;
        }
      }

      final snapshot = await FirebaseDatabase.instance
          .ref('pos_baskets')
          .orderByChild('status')
          .equalTo('pending')
          .get();

      final baskets = <Map<String, dynamic>>[];
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          final basket = Map<String, dynamic>.from(value as Map);
          basket['firebaseKey'] = key;
          baskets.add(basket);
        });
      }

      // Sort by createdAt ascending (oldest first)
      baskets.sort((a, b) {
        final aTime = a['createdAt'] as int? ?? 0;
        final bTime = b['createdAt'] as int? ?? 0;
        return aTime.compareTo(bTime);
      });

      // Cache for offline use
      await CacheService.savePosBaskets(baskets);

      setState(() {
        _pendingBaskets = baskets;
      });
    } catch (e) {
      // Fallback to cache on error
      final cachedBaskets = await CacheService.getPosBaskets(status: 'pending');
      if (cachedBaskets.isNotEmpty) {
        cachedBaskets.sort((a, b) {
          final aTime = a['createdAt'] as int? ?? 0;
          final bTime = b['createdAt'] as int? ?? 0;
          return aTime.compareTo(bTime);
        });
        setState(() {
          _pendingBaskets = cachedBaskets;
        });
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading baskets: $e')),
        );
      }
    }
  }

  void _selectBasket(Map<String, dynamic> basket) {
    setState(() {
      _selectedBasket = basket;
      _cartItems.clear();

      // Load basket items into cart
      final items = basket['items'] as List? ?? [];
      for (var item in items) {
        final cartItem = Map<String, dynamic>.from(item as Map);
        cartItem['cartQuantity'] = cartItem['quantity'];
        cartItem['quantity'] = cartItem['availableStock'] ?? cartItem['quantity'];
        cartItem['id'] = cartItem['itemId'];
        cartItem['sellingPrice'] = cartItem['unitPrice'];
        _cartItems.add(cartItem);
      }

      final customerName = basket['customerName'] as String? ?? '';
      _customerNameController.text = customerName;
    });
  }

  void _deselectBasket() {
    setState(() {
      _selectedBasket = null;
      _cartItems.clear();
      _customerNameController.clear();
    });
  }

  void _showAddManualItemDialog() {
    final nameController = TextEditingController();
    final qtyController = TextEditingController(text: '1');
    final priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final screenWidth = size.width;
        final screenHeight = size.height;
        final isLandscape = screenWidth > screenHeight;

        final dialog = AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.add_shopping_cart, color: _accentColor, size: 22),
            SizedBox(width: 8),
            Text('Add Item', style: TextStyle(color: _textPrimary, fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Add an item that is not in the inventory.',
                style: TextStyle(color: _textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                style: const TextStyle(color: _textPrimary),
                decoration: InputDecoration(
                  labelText: 'Item Name *',
                  labelStyle: const TextStyle(color: _textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _accentColor),
                  ),
                  filled: true,
                  fillColor: _bgColor,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: qtyController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: _textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Qty *',
                        labelStyle: const TextStyle(color: _textSecondary),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _accentColor),
                        ),
                        filled: true,
                        fillColor: _bgColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: _textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Price *',
                        labelStyle: const TextStyle(color: _textSecondary),
                        prefixText: '₱ ',
                        prefixStyle: const TextStyle(color: _textPrimary),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _accentColor),
                        ),
                        filled: true,
                        fillColor: _bgColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _textSecondary)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final name = nameController.text.trim();
              final qty = int.tryParse(qtyController.text.trim()) ?? 0;
              final price = double.tryParse(priceController.text.trim()) ?? 0;

              if (name.isEmpty || qty <= 0 || price <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill in all required fields')),
                );
                return;
              }

              Navigator.pop(ctx);

              setState(() {
                _cartItems.add({
                  'name': name,
                  'sellingPrice': price,
                  'cartQuantity': qty,
                  '_isCustomItem': true,
                });
              });
              _syncCartToFirebase();

              SnackBarUtils.showSuccess(context, 'Added: $name');
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add to Cart'),
          ),
        ],
      );

      if (isLandscape) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: screenWidth * 0.5,
                  maxHeight: screenHeight * 0.9,
                ),
                child: dialog,
              ),
            ),
          ),
        );
      }
      return dialog;
      },
    );
  }

  void _showCashInDialog() {
    String selectedProvider = 'GCash';
    String selectedType = 'Cash-In';
    String feeHandlingScenario = 'fee_included'; // fee_included, fee_separate, auto_deduct
    final amountController = TextEditingController();
    final feeController = TextEditingController();
    final refController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final screenWidth = size.width;
        final screenHeight = size.height;
        final isLandscape = screenWidth > screenHeight;

        final dialog = StatefulBuilder(
        builder: (ctx, setDialogState) {
          final providerColor = selectedProvider == 'GCash' ? const Color(0xFF007BFF) : const Color(0xFF2ECC71);
          return AlertDialog(
            backgroundColor: _cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: providerColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.account_balance_wallet, color: providerColor, size: 20),
                ),
                const SizedBox(width: 10),
                Text('$selectedProvider $selectedType', style: const TextStyle(color: _textPrimary, fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Provider selector
                  Row(
                    children: [
                      _buildProviderChip('GCash', const Color(0xFF007BFF), selectedProvider, (val) {
                        setDialogState(() => selectedProvider = val);
                      }),
                      const SizedBox(width: 8),
                      _buildProviderChip('Maya', const Color(0xFF2ECC71), selectedProvider, (val) {
                        setDialogState(() => selectedProvider = val);
                      }),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Cash-In / Cash-Out selector
                  Row(
                    children: [
                      _buildProviderChip('Cash-In', providerColor, selectedType, (val) {
                        setDialogState(() => selectedType = val);
                      }),
                      const SizedBox(width: 8),
                      _buildProviderChip('Cash-Out', const Color(0xFFE67E22), selectedType, (val) {
                        setDialogState(() => selectedType = val);
                      }),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: _textPrimary),
                    onChanged: (value) {
                      // Auto-calculate 2% fee when amount is entered
                      final amount = double.tryParse(value) ?? 0;
                      if (amount > 0) {
                        setDialogState(() {
                          feeController.text = (amount * 0.02).toStringAsFixed(2);
                        });
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Amount *',
                      labelStyle: const TextStyle(color: _textSecondary),
                      prefixText: '\u20B1 ',
                      prefixStyle: const TextStyle(color: _textPrimary),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: providerColor),
                      ),
                      filled: true,
                      fillColor: _bgColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Fee Handling Scenario
                  Text(
                    'Fee Handling:',
                    style: TextStyle(color: _textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  ...['fee_included', 'fee_separate', 'auto_deduct'].map((scenario) {
                    final labels = {
                      'fee_included': 'Fee Included in Amount',
                      'fee_separate': 'Fee Given to Cashier',
                      'auto_deduct': 'Auto Deduct 2%',
                    };
                    return InkWell(
                      onTap: () {
                        setDialogState(() {
                          feeHandlingScenario = scenario;
                          if (scenario == 'auto_deduct') {
                            final amount = double.tryParse(amountController.text) ?? 0;
                            if (amount > 0) {
                              feeController.text = (amount * 0.02).toStringAsFixed(2);
                            }
                          }
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: feeHandlingScenario == scenario ? providerColor.withValues(alpha: 0.15) : _bgColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: feeHandlingScenario == scenario ? providerColor : _textSecondary.withValues(alpha: 0.3),
                            width: feeHandlingScenario == scenario ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              feeHandlingScenario == scenario ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                              color: feeHandlingScenario == scenario ? providerColor : _textSecondary,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                labels[scenario]!,
                                style: TextStyle(
                                  color: feeHandlingScenario == scenario ? providerColor : _textPrimary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  TextField(
                    controller: feeController,
                    readOnly: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: _textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Service Fee (auto-calculated)',
                      labelStyle: const TextStyle(color: _textSecondary),
                      prefixText: '\u20B1 ',
                      prefixStyle: const TextStyle(color: _textPrimary),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: providerColor),
                      ),
                      filled: true,
                      fillColor: _bgColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: refController,
                    style: const TextStyle(color: _textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Reference No. (optional)',
                      labelStyle: const TextStyle(color: _textSecondary),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: providerColor),
                      ),
                      filled: true,
                      fillColor: _bgColor,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: _textSecondary)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: selectedType == 'Cash-Out' ? const Color(0xFFE67E22) : providerColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final amount = double.tryParse(amountController.text.trim()) ?? 0;
                  // Always calculate fee as 2% of amount, regardless of text field value
                  final fee = amount * 0.02;
                  final ref = refController.text.trim();

                  if (amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a valid amount')),
                    );
                    return;
                  }

                  Navigator.pop(ctx);

                  // Calculate selling price based on fee handling scenario
                  double sellingPrice;
                  double actualCashGiven;

                  switch (feeHandlingScenario) {
                    case 'fee_included':
                      // Fee included in system/e-wallet transaction
                      // System charges: amount + fee (e.g., ₱5,100 in e-wallet)
                      // Actual cash given/received: amount (e.g., ₱5,000)
                      // Business keeps: fee (e.g., ₱100)
                      sellingPrice = amount + fee;
                      actualCashGiven = amount;
                      break;
                    case 'fee_separate':
                      // Fee collected as physical cash to cashier (not in e-wallet, but still business revenue)
                      // System records: amount + fee (total customer pays)
                      // Physical cash: fee goes to cashier to deposit
                      // Cash-Out: System ₱5,000 + Cashier ₱100 = ₱5,100 total, send ₱5,000
                      // Cash-In: System ₱5,000 + Cashier ₱100 = ₱5,100 total, customer gets ₱5,000
                      sellingPrice = amount + fee;
                      actualCashGiven = amount;
                      break;
                    case 'auto_deduct':
                      // Auto deduct fee from amount (for both Cash-Out and Cash-In)
                      sellingPrice = amount;
                      actualCashGiven = amount - fee;
                      break;
                    default:
                      sellingPrice = amount + fee;
                      actualCashGiven = selectedType == 'Cash-Out' ? amount : 0;
                  }

                  final itemName = '$selectedProvider $selectedType${ref.isNotEmpty ? ' (Ref: $ref)' : ''}';
                  setState(() {
                    _cartItems.add({
                      'name': itemName,
                      'sellingPrice': sellingPrice,
                      'cartQuantity': 1,
                      '_isCustomItem': true,
                      '_cashInProvider': selectedProvider,
                      '_cashInType': selectedType,
                      '_cashInAmount': amount,
                      '_cashInFee': fee,
                      '_cashInRef': ref,
                      '_cashInFeeHandling': feeHandlingScenario,
                      '_actualCashGiven': actualCashGiven,
                    });
                  });
                  _syncCartToFirebase();

                  SnackBarUtils.showEWalletAdded(
                    context,
                    provider: selectedProvider,
                    type: selectedType,
                    sellingPrice: sellingPrice,
                    fee: fee,
                    actualCashGiven: actualCashGiven,
                    feeHandling: feeHandlingScenario,
                  );
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add to Cart'),
              ),
            ],
          );
        },
      );

      if (isLandscape) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: screenWidth * 0.5,
                  maxHeight: screenHeight * 0.9,
                ),
                child: dialog,
              ),
            ),
          ),
        );
      }
      return dialog;
      },
    );
  }

  Widget _buildProviderChip(String label, Color color, String selected, Function(String) onTap) {
    final isSelected = selected == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.2) : _bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : _textSecondary.withValues(alpha: 0.2),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? color : _textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== SCANNERS ====================

  Future<void> _openOcrScanner() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OcrScannerPage(
          serviceName: 'Product',
          primaryColor: _accentColor,
          serviceType: 'inventory_serial',
          onInventoryScan: (serial) {
            final cleaned = _extractScanCode(serial);
            if (cleaned.isNotEmpty) {
              _matchAndAddScannedItem(cleaned);
            }
          },
        ),
      ),
    );
  }

  /// Extract SKU/serial from scanned data.
  /// Handles QR label format "SKU|Name|Price" by extracting just the SKU.
  /// Falls back to numbers-only extraction for plain barcodes.
  String _extractScanCode(String raw) {
    if (raw.contains('|')) {
      return raw.split('|').first.trim().toLowerCase();
    }
    return raw.replaceAll(RegExp(r'[^0-9]'), '').trim().toLowerCase();
  }

  Future<void> _openBarcodeScanner() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MultiScannerPage(
          serviceType: 'inventory',
          serviceName: 'Product',
          primaryColor: _accentColor,
          onInventoryScan: (code) {
            final cleaned = _extractScanCode(code);
            if (cleaned.isNotEmpty) {
              _matchAndAddScannedItem(cleaned);
            }
          },
        ),
      ),
    );
  }

  void _matchAndAddScannedItem(String scannedValue) {
    // Match against inventory items
    final match = _inventoryItems.cast<Map<String, dynamic>?>().firstWhere(
      (item) {
        final serialNo = (item?['serialNo'] as String? ?? '').toLowerCase();
        final sku = (item?['sku'] as String? ?? '').toLowerCase();
        final barcode = (item?['barcode'] as String? ?? '').toLowerCase();
        final name = (item?['name'] as String? ?? '').toLowerCase();
        return serialNo == scannedValue ||
            sku == scannedValue ||
            barcode == scannedValue ||
            name == scannedValue;
      },
      orElse: () => null,
    );

    if (match != null) {
      BeepService.playBeep();
      _addToCart(match);
      SnackBarUtils.showSuccess(context, 'Added: ${match['name']}');
    } else {
      SnackBarUtils.showError(context, 'Product not found for: $scannedValue');
    }
  }

  List<Map<String, dynamic>> get _filteredInventory {
    if (_searchQuery.isEmpty) return _inventoryItems;
    final query = _searchQuery.toLowerCase();
    return _inventoryItems.where((item) {
      final name = (item['name'] as String? ?? '').toLowerCase();
      final serialNo = (item['sku'] as String? ?? item['serialNo'] as String? ?? '').toLowerCase();
      final brand = (item['brand'] as String? ?? '').toLowerCase();
      final modelNumber = (item['modelNumber'] as String? ?? '').toLowerCase();
      return name.contains(query) || serialNo.contains(query) || brand.contains(query) || modelNumber.contains(query);
    }).toList();
  }

  double get _total {
    double total = 0;
    for (int i = 0; i < _cartItems.length; i++) {
      final item = _cartItems[i];

      // Use discounted price if available, otherwise use selling price
      final price = (item['_discountedPrice'] as double?) ??
                    (item['sellingPrice'] as num?)?.toDouble() ??
                    (item['unitPrice'] as num?)?.toDouble() ?? 0;
      final qty = item['cartQuantity'] as int? ?? 1;
      total += price * qty;
    }
    return total;
  }

  // VAT calculation based on settings
  // If VAT is inclusive: VAT = Total - (Total / (1 + rate/100))
  // If VAT is exclusive: VAT = Total * (rate/100)
  double get _vatAmount {
    if (!_vatEnabled) return 0;
    if (_vatInclusive) {
      // VAT is included in price
      return _total - (_total / (1 + _vatRate / 100));
    } else {
      // VAT is added on top
      return _total * (_vatRate / 100);
    }
  }

  double get _netAmount => _vatInclusive ? _total - _vatAmount : _total;

  // No transaction fee - all payment methods treated equally
  double get _transactionFee {
    return 0;
  }

  double get _grandTotal {
    final baseTotal = _vatInclusive ? _total : _total + _vatAmount;
    return baseTotal;
  }

  // Net amount business receives (same as grand total)
  double get _netReceived {
    return _grandTotal;
  }

  void _addToCart(Map<String, dynamic> item) {
    // Don't allow adding items if processing a basket
    if (_selectedBasket != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clear basket first to add items manually')),
      );
      return;
    }

    setState(() {
      final existingIndex = _cartItems.indexWhere((c) => c['id'] == item['id']);
      if (existingIndex >= 0) {
        final currentQty = _cartItems[existingIndex]['cartQuantity'] as int? ?? 1;
        final availableQty = item['quantity'] as int? ?? 0;
        if (currentQty < availableQty) {
          _cartItems[existingIndex]['cartQuantity'] = currentQty + 1;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maximum stock reached')),
          );
        }
      } else {
        final newItem = Map<String, dynamic>.from(item);
        newItem['cartQuantity'] = 1;
        _cartItems.add(newItem);
      }
    });
    _syncCartToFirebase();
  }

  void _removeFromCart(int index) {
    setState(() {
      _cartItems.removeAt(index);
    });
    _syncCartToFirebase();
  }

  void _updateCartQuantity(int index, int newQty) {
    if (newQty <= 0) {
      _removeFromCart(index);
      return;
    }
    final availableQty = _cartItems[index]['quantity'] as int? ??
                        _cartItems[index]['availableStock'] as int? ?? 0;
    if (newQty > availableQty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Only $availableQty available in stock')),
      );
      return;
    }
    setState(() {
      _cartItems[index]['cartQuantity'] = newQty;
    });
    _syncCartToFirebase();
  }

  void _clearCart() {
    setState(() {
      _cartItems.clear();
      _selectedBasket = null;
      _customerNameController.clear();
      _cashReceivedController.clear();

      // Clear discount state
      _discountModeEnabled = false;
      _discountAuthorizedBy = null;
      _discountedPrices.clear();
      _originalPrices.clear();
    });
    if (_currentUserEmail.isNotEmpty) {
      PosLiveCartService.clearCart(_currentUserEmail);
    }
  }

  // ==================== DISCOUNT MODE ====================

  Future<void> _toggleDiscountMode() async {
    if (_discountModeEnabled) {
      // Turning OFF discount mode - no PIN needed
      setState(() {
        _discountModeEnabled = false;
        _discountAuthorizedBy = null;
      });
      SnackBarUtils.showWarning(context, 'Discount mode disabled');
    } else {
      // Turning ON discount mode - require PIN verification
      final staffInfo = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const PinEntryDialog(),
      );

      if (staffInfo != null) {
        setState(() {
          _discountModeEnabled = true;
          _discountAuthorizedBy = staffInfo;
        });
        SnackBarUtils.showSuccess(context, 'Discount mode enabled by ${staffInfo['name']}');
      }
    }
  }

  void _updateDiscountedPrice(int itemIndex, String value, double originalPrice) {
    final newPrice = double.tryParse(value);
    if (newPrice != null && newPrice >= 0) {
      setState(() {
        if (!_originalPrices.containsKey(itemIndex)) {
          _originalPrices[itemIndex] = originalPrice;
        }
        _discountedPrices[itemIndex] = newPrice;

        // Update the cart item with new price
        _cartItems[itemIndex]['_discountedPrice'] = newPrice;
        _cartItems[itemIndex]['_originalPrice'] = originalPrice;
      });
    }
  }

  void _resetItemPrice(int itemIndex) {
    setState(() {
      _discountedPrices.remove(itemIndex);
      _cartItems[itemIndex].remove('_discountedPrice');
      _cartItems[itemIndex].remove('_originalPrice');
    });
    SnackBarUtils.showInfo(context, 'Price reset to original', duration: const Duration(seconds: 1));
  }

  // ==================== FIREBASE SYNC ====================

  /// Push the entire local cart state to Firebase for cross-device sync.
  void _syncCartToFirebase() {
    if (_currentUserEmail.isEmpty || _isSyncingFromRemote) return;
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 300), () {
      if (_currentUserEmail.isEmpty || _isSyncingFromRemote) return;
      _isSyncingToFirebase = true;
      final ref = PosLiveCartService.cartRef(_currentUserEmail);
      ref.update({
        'items': _cartItems.isEmpty ? null : _cartItems,
        'customerName': _customerNameController.text.trim(),
        'updatedAt': ServerValue.timestamp,
      }).whenComplete(() {
        Future.delayed(const Duration(milliseconds: 500), () {
          _isSyncingToFirebase = false;
        });
      });
    });
  }

  Future<void> _processTransaction() async {
    // Block transaction if cash drawer is still open
    if (PrinterService.isCashDrawerOpen) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF2D1515),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Text('Cash Drawer Open', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: const Text(
            'Please close the cash drawer before starting a new transaction.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2ECC71)),
              onPressed: () {
                PrinterService.markCashDrawerClosed();
                Navigator.pop(context);
              },
              child: const Text('Drawer is Closed', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      return;
    }

    // Block transaction if printer is not connected
    if (!PrinterService.isConnected) {
      await PrinterService.updateConnectionStatus();
      if (!PrinterService.isConnected) {
        if (!mounted) return;
        final reconnected = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => _PrinterReconnectDialog(primaryColor: _accentColor),
        );
        if (reconnected != true) return;
      }
    }

    if (_cartItems.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart is empty')),
      );
      return;
    }

    // Validate stock availability before showing payment dialog
    final stockErrors = <String>[];
    for (var item in _cartItems) {
      // Skip stock check for custom items (admin-approved requests)
      if (item['_isCustomItem'] == true) continue;

      final itemId = item['id'] ?? item['itemId'];
      final category = item['category'];
      final requestedQty = item['cartQuantity'] as int? ?? 1;
      final itemName = item['name'] as String? ?? 'Unknown item';

      if (itemId != null && category != null) {
        final currentStock = await InventoryService.getItemStock(category: category, itemId: itemId);
        if (currentStock < requestedQty) {
          stockErrors.add('$itemName: only $currentStock available (requested $requestedQty)');
        }
      }
    }

    if (stockErrors.isNotEmpty) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: _cardColor,
            title: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange, size: 24),
                SizedBox(width: 8),
                Text('Insufficient Stock', style: TextStyle(color: _textPrimary)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('The following items have insufficient stock:', style: TextStyle(color: _textSecondary)),
                const SizedBox(height: 12),
                ...stockErrors.map((error) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(error, style: const TextStyle(color: Colors.red, fontSize: 12))),
                    ],
                  ),
                )),
                const SizedBox(height: 12),
                Text('Please update cart quantities or refresh inventory.', style: TextStyle(color: _textSecondary, fontSize: 12)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _loadInventory();
                },
                child: const Text('Refresh Inventory', style: TextStyle(color: _accentColor)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _accentColor),
                onPressed: () => Navigator.pop(context),
                child: const Text('OK', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      }
      return;
    }

    // Staff PIN verification
    if (!mounted) return;
    final staffInfo = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PinEntryDialog(),
    );
    if (staffInfo == null) return; // User cancelled

    final String servedByName = staffInfo['name'] as String;
    final String servedByEmail = staffInfo['email'] as String;

    // Show payment dialog
    final result = await _showPaymentDialog();
    if (result != true) return;

    setState(() => _isProcessing = true);

    try {
      // Create transaction record
      final transactionId = DateTime.now().millisecondsSinceEpoch.toString();
      final items = _cartItems.map((item) {
        final isCashOut = item['_cashInType'] == 'Cash-Out';
        final isCashIn = item['_cashInType'] == 'Cash-In';
        final hasDiscount = item['_discountedPrice'] != null;
        final finalPrice = (item['_discountedPrice'] as double?) ??
                          (item['sellingPrice'] as num?)?.toDouble() ??
                          (item['unitPrice'] as num?)?.toDouble() ?? 0;

        return {
          'itemId': item['id'] ?? item['itemId'],
          'name': item['name'],
          'brand': item['brand'],
          'category': item['category'],
          'serialNo': item['sku'] ?? item['serialNo'],
          'quantity': item['cartQuantity'],
          'unitPrice': finalPrice,
          'subtotal': finalPrice * (item['cartQuantity'] as int? ?? 1),
          // Discount fields (if this item was discounted)
          if (hasDiscount) ...{
            'originalPrice': item['_originalPrice'],
            'discountedPrice': item['_discountedPrice'],
            'discountAmount': (item['_originalPrice'] as double? ?? 0) - (item['_discountedPrice'] as double? ?? 0),
          },
          // Cash-out/Cash-in specific fields
          if (isCashOut || isCashIn) ...{
            'isCashOut': isCashOut,
            'isCashIn': isCashIn,
            // cashOutAmount represents the principal (actual money that goes out/in)
            // For fee_included/fee_separate: principal = full amount
            // For auto_deduct: principal = amount after deduction (actualCashGiven)
            'cashOutAmount': item['_actualCashGiven'] ?? (item['_cashInAmount'] ?? 0),
            'serviceFee': item['_cashInFee'] ?? 0,
            'feeHandling': item['_cashInFeeHandling'] ?? 'fee_included',
            'actualCashGiven': item['_actualCashGiven'] ?? (item['_cashInAmount'] ?? 0),
            'provider': item['_cashInProvider'],
            'referenceNo': item['_cashInRef'],
          },
        };
      }).toList();

      // Calculate cash-out and cash-in summary for this transaction
      double totalCashOutAmount = 0;
      double totalCashInAmount = 0;
      double totalServiceFee = 0;
      bool hasCashOut = false;
      bool hasCashIn = false;
      for (var item in items) {
        if (item['isCashOut'] == true) {
          hasCashOut = true;
          totalCashOutAmount += (item['cashOutAmount'] as num?)?.toDouble() ?? 0;
          totalServiceFee += (item['serviceFee'] as num?)?.toDouble() ?? 0;
        }
        if (item['isCashIn'] == true) {
          hasCashIn = true;
          totalCashInAmount += (item['cashOutAmount'] as num?)?.toDouble() ?? 0;
          totalServiceFee += (item['serviceFee'] as num?)?.toDouble() ?? 0;
        }
      }

      final transaction = {
        'transactionId': transactionId,
        'items': items,
        'subtotal': _netAmount,
        'vatEnabled': _vatEnabled,
        'vatRate': _vatRate,
        'vatInclusive': _vatInclusive,
        'vatAmount': _vatAmount,
        'transactionFee': _transactionFee,
        'feeHandling': _feeHandling,
        'netReceived': _netReceived,
        'total': _grandTotal,
        // For reporting: actual revenue excludes cash-out and cash-in principal amounts
        // Revenue = total sales - cash-out principal - cash-in principal (only service fees count as revenue)
        'actualRevenue': _grandTotal - totalCashOutAmount - totalCashInAmount,
        'totalCashOutAmount': totalCashOutAmount,
        'totalCashInAmount': totalCashInAmount,
        'totalServiceFee': totalServiceFee,
        'hasCashOut': hasCashOut,
        'hasCashIn': hasCashIn,
        // Discount tracking fields
        'hasDiscounts': _discountedPrices.isNotEmpty,
        if (_discountedPrices.isNotEmpty && _discountAuthorizedBy != null) ...{
          'discountAuthorizedBy': _discountAuthorizedBy!['name'],
          'discountAuthorizedByEmail': _discountAuthorizedBy!['email'],
          'discountAuthorizedByUserId': _discountAuthorizedBy!['userId'],
        },
        'paymentMethod': _paymentMethod,
        'customerName': _customerNameController.text.trim(),
        'cashReceived': _paymentMethod == 'cash'
            ? double.tryParse(_cashReceivedController.text) ?? _grandTotal
            : _grandTotal,
        'change': _paymentMethod == 'cash'
            ? (double.tryParse(_cashReceivedController.text) ?? _grandTotal) - _grandTotal
            : 0,
        if (_paymentMethod == 'card' || _paymentMethod == 'gcash/maya')
          'referenceNumber': _referenceNumberController.text.trim(),
        'processedBy': servedByName,
        'processedByEmail': servedByEmail,
        'deviceUser': _currentUserEmail,
        'timestamp': DateTime.now().toIso8601String(),
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'basketId': _selectedBasket?['firebaseKey'],
        'basketOwner': _selectedBasket?['userName'],
      };

      // Keep a copy of cart items before clearing for inventory deduction later
      final cartItemsCopy = List<Map<String, dynamic>>.from(_cartItems);
      final selectedBasketCopy = _selectedBasket != null ? Map<String, dynamic>.from(_selectedBasket!) : null;

      // Show receipt first — transaction is saved only after confirmation
      final confirmed = await _showReceiptDialog(transaction);
      if (confirmed != true) {
        return;
      }

      // Print receipt and open cash drawer if printer is connected
      if (PrinterService.isConnected) {
        bool printConfirmed = false;

        while (!printConfirmed && mounted) {
          // Attempt to print
          await PrinterService.printReceiptAndOpenDrawer(transaction);

          // Show receipt and ask cashier if it printed successfully
          final action = await _showPrintConfirmationDialog(transaction);

          if (action == 'yes') {
            // Print confirmed, exit loop
            printConfirmed = true;
          } else if (action == 'retry') {
            // Update connection status and retry
            await PrinterService.updateConnectionStatus();
            // Loop will continue and attempt print again
            if (!mounted) break;
          } else {
            // User chose to skip printing
            // Still try to open drawer for cash payments or cash-out transactions
            final needsDrawer = transaction['paymentMethod'] == 'cash' ||
                                transaction['hasCashOut'] == true;
            if (needsDrawer) {
              await PrinterService.openCashDrawer();
            }
            printConfirmed = true; // Exit loop even though we skipped
            break;
          }
        }
      }

      // Now save the transaction
      final hasConnection = await CacheService.hasConnectivity();
      bool isOfflineTransaction = false;

      if (hasConnection) {
        try {
          await FirebaseDatabase.instance.ref('pos_transactions/$transactionId').set(transaction);
          await CacheService.savePosTransaction({...transaction, 'transactionId': transactionId});

          // Deduct inventory (online) and mark custom item requests as used
          bool allSuccess = true;
          for (var item in cartItemsCopy) {
            if (item['_isCustomItem'] == true) continue;

            final qty = item['cartQuantity'] as int? ?? 1;
            final itemId = item['id'] ?? item['itemId'];
            final category = item['category'];

            if (itemId != null && category != null) {
              final success = await InventoryService.removeStock(
                category: category,
                itemId: itemId,
                quantityToRemove: qty,
                reason: 'POS Sale - Transaction #$transactionId',
                removedByEmail: _currentUserEmail,
                removedByName: _currentUserName,
              );
              if (!success) allSuccess = false;
            }
          }

          // If processing a basket, remove it from pos_baskets
          if (selectedBasketCopy != null) {
            await FirebaseDatabase.instance
                .ref('pos_baskets/${selectedBasketCopy['firebaseKey']}')
                .remove();
          }

          if (!allSuccess && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Transaction completed but some inventory updates failed'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } catch (e) {
          isOfflineTransaction = true;
          await CacheService.savePendingTransaction(transaction);

          for (var item in cartItemsCopy) {
            final qty = item['cartQuantity'] as int? ?? 1;
            final itemId = item['id'] ?? item['itemId'];
            if (itemId != null) {
              final cachedItem = _inventoryItems.firstWhere(
                (inv) => (inv['id'] ?? inv['itemId']) == itemId,
                orElse: () => <String, dynamic>{},
              );
              if (cachedItem.isNotEmpty) {
                final currentQty = cachedItem['quantity'] as int? ?? 0;
                cachedItem['quantity'] = currentQty - qty;
              }
            }
          }

          if (mounted) {
            setState(() {
              _pendingSyncCount++;
              _isOffline = true;
            });
          }
        }
      } else {
        isOfflineTransaction = true;
        await CacheService.savePendingTransaction(transaction);

        for (var item in cartItemsCopy) {
          final qty = item['cartQuantity'] as int? ?? 1;
          final itemId = item['id'] ?? item['itemId'];
          if (itemId != null) {
            final cachedItem = _inventoryItems.firstWhere(
              (inv) => (inv['id'] ?? inv['itemId']) == itemId,
              orElse: () => <String, dynamic>{},
            );
            if (cachedItem.isNotEmpty) {
              final currentQty = cachedItem['quantity'] as int? ?? 0;
              cachedItem['quantity'] = currentQty - qty;
            }
          }
        }

        if (mounted) {
          setState(() {
            _pendingSyncCount++;
            _isOffline = true;
          });
        }
      }

      _clearCart();

      // Update local inventory for sold items instead of full reload
      if (mounted) {
        setState(() {
          for (var item in cartItemsCopy) {
            if (item['_isCustomItem'] == true) continue;
            final itemId = item['id'] ?? item['itemId'];
            if (itemId == null) continue;
            final qty = item['cartQuantity'] as int? ?? 1;
            final idx = _inventoryItems.indexWhere((inv) => (inv['id'] ?? inv['itemId']) == itemId);
            if (idx >= 0) {
              final currentQty = _inventoryItems[idx]['quantity'] as int? ?? 0;
              final newQty = (currentQty - qty).clamp(0, double.infinity).toInt();
              if (newQty <= 0) {
                _inventoryItems.removeAt(idx);
              } else {
                _inventoryItems[idx]['quantity'] = newQty;
              }
            }
          }
        });
      }

      if (!isOfflineTransaction) {
        _loadPendingBaskets();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing transaction: $e')),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// Open cash drawer for making change (non-sale transaction).
  /// Flow: enter amount → PIN verification → open drawer → log transaction.
  Future<void> _openCashDrawerForChange() async {
    // Block if drawer is already open
    if (PrinterService.isCashDrawerOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cash drawer is already open'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!PrinterService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Printer not connected. Cannot open cash drawer.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Step 1: Show amount entry dialog
    final amountController = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.money, color: _accentColor, size: 24),
              SizedBox(width: 8),
              Text('Cash Drawer - Change', style: TextStyle(color: _textPrimary, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the amount for change:',
                style: TextStyle(color: _textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                style: const TextStyle(color: _textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  prefixText: '₱ ',
                  prefixStyle: const TextStyle(color: _accentColor, fontSize: 20, fontWeight: FontWeight.bold),
                  hintText: '0.00',
                  hintStyle: TextStyle(color: _textSecondary.withValues(alpha: 0.5)),
                  filled: true,
                  fillColor: _bgColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _accentColor),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This will open the cash drawer for making change.\nNo sale will be recorded.',
                style: TextStyle(color: _textSecondary, fontSize: 11),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text('Cancel', style: TextStyle(color: _textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _accentColor),
              onPressed: () {
                final value = double.tryParse(amountController.text);
                if (value == null || value <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid amount'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, value);
              },
              child: const Text('Continue', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (amount == null || !mounted) return;

    // Step 2: PIN verification
    final staffInfo = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PinEntryDialog(),
    );
    if (staffInfo == null || !mounted) return;

    // Step 3: Open cash drawer
    final success = await PrinterService.openCashDrawer();

    if (!mounted) return;

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to open cash drawer'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Step 4: Log as non-sale transaction
    final transactionId = DateTime.now().millisecondsSinceEpoch.toString();
    final currentUser = await AuthService.getCurrentUser();

    final drawerTransaction = {
      'transactionId': transactionId,
      'type': 'cash_drawer_change',
      'amount': amount,
      'processedBy': staffInfo['name'] as String? ?? 'Unknown',
      'processedByEmail': staffInfo['email'] as String? ?? '',
      'processedByUserId': staffInfo['userId'] as String? ?? '',
      'deviceUser': _currentUserEmail,
      'deviceUserName': _currentUserName,
      'deviceUserRole': currentUser?['role'] ?? 'unknown',
      'timestamp': DateTime.now().toIso8601String(),
      'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'note': 'Cash drawer opened for change',
    };

    try {
      final hasConnection = await CacheService.hasConnectivity();
      if (hasConnection) {
        await FirebaseDatabase.instance
            .ref('pos_transactions/$transactionId')
            .set(drawerTransaction);
      }
      // Also save to local cache
      await CacheService.savePosTransaction({...drawerTransaction, 'transactionId': transactionId});
    } catch (e) {
      debugPrint('Failed to log cash drawer change transaction: $e');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cash drawer opened - ₱${amount.toStringAsFixed(2)} change'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<bool?> _showPaymentDialog() {
    final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    _cashReceivedController.text = '';
    _referenceNumberController.text = '';
    String displayAmount = '0';

    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final cashReceived = double.tryParse(displayAmount) ?? 0;
          final change = cashReceived - _grandTotal;
          final screenSize = MediaQuery.of(context).size;
          final isLandscape = screenSize.width > screenSize.height;
          final isWideScreen = screenSize.width > 700;
          final useLandscapeLayout = isLandscape || isWideScreen;

          void onKeyPress(String key) {
            setDialogState(() {
              if (_paymentMethod == 'cash') {
                // Cash: update displayAmount for cash received
                if (key == 'C') {
                  displayAmount = '0';
                } else if (key == '⌫') {
                  if (displayAmount.length > 1) {
                    displayAmount = displayAmount.substring(0, displayAmount.length - 1);
                  } else {
                    displayAmount = '0';
                  }
                } else if (key == '.') {
                  if (!displayAmount.contains('.')) {
                    displayAmount += '.';
                  }
                } else {
                  if (displayAmount == '0') {
                    displayAmount = key;
                  } else {
                    displayAmount += key;
                  }
                }
                _cashReceivedController.text = displayAmount;
              } else {
                // Card / GCash: update reference number
                final current = _referenceNumberController.text;
                if (key == 'C') {
                  _referenceNumberController.text = '';
                } else if (key == '⌫') {
                  if (current.isNotEmpty) {
                    _referenceNumberController.text = current.substring(0, current.length - 1);
                  }
                } else {
                  _referenceNumberController.text = current + key;
                }
              }
            });
          }

          Widget buildKeypadButton(String label, {Color? color, IconData? icon}) {
            final isSpecial = color != null;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: _KeypadButton(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onKeyPress(label);
                  },
                  isSpecial: isSpecial,
                  color: color,
                  height: useLandscapeLayout ? 48 : 60,
                  child: icon != null
                      ? Icon(icon, color: color ?? _textPrimary, size: 22)
                      : Text(
                          label,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: isSpecial ? color : _textPrimary,
                          ),
                        ),
                ),
              ),
            );
          }

          // --- Payment info panel (left side in landscape) ---
          Widget paymentInfoPanel() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Basket info
                if (_selectedBasket != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.shopping_basket, color: Colors.blue, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Basket #${_selectedBasket!['basketNumber']} by ${_selectedBasket!['userName']}'
                            '${(_selectedBasket!['customerName'] as String?)?.isNotEmpty == true ? ' — ${_selectedBasket!['customerName']}' : ''}',
                            style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Order Summary
                if (_cartItems.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        initiallyExpanded: useLandscapeLayout,
                        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        iconColor: _textSecondary,
                        collapsedIconColor: _textSecondary,
                        title: Row(
                          children: [
                            const Icon(Icons.receipt_long, color: _accentColor, size: 16),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Order Summary (${_cartItems.length})',
                                style: const TextStyle(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        children: [
                          ..._cartItems.map((item) {
                            final name = item['name'] as String? ?? 'Unnamed';
                            final price = (item['sellingPrice'] as num?)?.toDouble() ??
                                (item['unitPrice'] as num?)?.toDouble() ?? 0;
                            final qty = item['cartQuantity'] as int? ?? 1;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: const TextStyle(color: _textPrimary, fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$qty × ${currencyFormat.format(price)}',
                                    style: TextStyle(color: _textSecondary, fontSize: 10),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    currencyFormat.format(price * qty),
                                    style: const TextStyle(color: _textPrimary, fontSize: 11, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),

                // Total Amount
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(
                    color: _accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _accentColor.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    children: [
                      Text('TOTAL AMOUNT', style: TextStyle(color: _textSecondary, fontSize: useLandscapeLayout ? 10 : 11, letterSpacing: 1.2)),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          currencyFormat.format(_grandTotal),
                          style: TextStyle(color: _accentColor, fontSize: useLandscapeLayout ? 22 : 30, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (_vatEnabled)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _vatInclusive
                                ? 'VAT Included (${_vatRate.toStringAsFixed(0)}%): ${currencyFormat.format(_vatAmount)}'
                                : 'VAT (${_vatRate.toStringAsFixed(0)}%): ${currencyFormat.format(_vatAmount)}',
                            style: const TextStyle(color: _textSecondary, fontSize: 10),
                          ),
                        ),
                      if (_transactionFee > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _feeHandling == 'customer_pays'
                                ? 'Transaction Fee (2%): +${currencyFormat.format(_transactionFee)}'
                                : 'Fee Deducted (2%): -${currencyFormat.format(_transactionFee)}',
                            style: TextStyle(
                              color: _feeHandling == 'customer_pays' ? _textSecondary : Colors.orange,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Payment Method
                Builder(
                  builder: (context) {
                    // Check if cart has Cash-In/Cash-Out with auto_deduct scenario
                    final hasAutoDeductEWallet = _cartItems.any((item) {
                      final isCashInOut = item['_cashInType'] == 'Cash-In' || item['_cashInType'] == 'Cash-Out';
                      final isAutoDeduct = item['_cashInFeeHandling'] == 'auto_deduct';
                      return isCashInOut && isAutoDeduct;
                    });

                    // Auto-switch from cash if disabled
                    if (hasAutoDeductEWallet && _paymentMethod == 'cash') {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        setDialogState(() => _paymentMethod = 'card');
                        setState(() {});
                      });
                    }

                    return Row(
                      children: [
                        Expanded(child: _buildPaymentMethodButton('cash', Icons.money, 'Cash', setDialogState, disabled: hasAutoDeductEWallet)),
                        const SizedBox(width: 6),
                        Expanded(child: _buildPaymentMethodButton('card', Icons.credit_card, 'Card', setDialogState)),
                        const SizedBox(width: 6),
                        Expanded(child: _buildPaymentMethodButton('gcash/maya', Icons.phone_android, 'GCash/Maya', setDialogState)),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),

                // Change Display (cash only)
                if (_paymentMethod == 'cash')
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: change >= 0 ? Colors.green.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: change >= 0 ? Colors.green.withValues(alpha: 0.25) : Colors.red.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          change >= 0 ? 'Change' : 'Insufficient',
                          style: TextStyle(
                            color: change >= 0 ? Colors.green : Colors.red,
                            fontSize: useLandscapeLayout ? 12 : 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            currencyFormat.format(change.abs()),
                            style: TextStyle(
                              color: change >= 0 ? Colors.green : Colors.red,
                              fontSize: useLandscapeLayout ? 18 : 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 10),

                // Customer Name
                TextField(
                  controller: _customerNameController,
                  style: const TextStyle(color: _textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Customer Name (optional)',
                    labelStyle: TextStyle(color: _textSecondary, fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _accentColor),
                    ),
                    filled: true,
                    fillColor: _bgColor,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),

                // Reference Number (card/gcash only)
                if (_paymentMethod == 'card' || _paymentMethod == 'gcash/maya') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _referenceNumberController,
                    style: const TextStyle(color: _textPrimary, fontSize: 14),
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Reference Number',
                      labelStyle: TextStyle(color: _textSecondary, fontSize: 13),
                      prefixIcon: Icon(
                        _paymentMethod == 'gcash/maya' ? Icons.phone_android : Icons.credit_card,
                        color: _accentColor,
                        size: 18,
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _accentColor.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _accentColor),
                      ),
                      filled: true,
                      fillColor: _bgColor,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ],
            );
          }

          // --- Amount / Reference display (sticky) ---
          Widget amountDisplay() {
            final isCash = _paymentMethod == 'cash';
            final refDisplay = _referenceNumberController.text;

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _accentColor.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isCash ? 'CASH RECEIVED' : 'REFERENCE NUMBER',
                    style: const TextStyle(color: _textSecondary, fontSize: 10, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      isCash ? '₱ $displayAmount' : (refDisplay.isEmpty ? '—' : refDisplay),
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // --- Keypad buttons (scrollable area) ---
          Widget keypadButtons() {
            final isCash = _paymentMethod == 'cash';

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Quick denomination buttons (cash only)
                if (isCash) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [20, 50, 100, 200, 500, 1000].map((amount) {
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            setDialogState(() {
                              final current = double.tryParse(displayAmount) ?? 0;
                              final newAmount = current + amount;
                              displayAmount = newAmount.toStringAsFixed(0);
                              _cashReceivedController.text = displayAmount;
                            });
                          },
                          borderRadius: BorderRadius.circular(10),
                          splashColor: Colors.green.withValues(alpha: 0.3),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: useLandscapeLayout ? 10 : 14,
                              vertical: useLandscapeLayout ? 6 : 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
                            ),
                            child: Text(
                              '+₱$amount',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: useLandscapeLayout ? 12 : 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                ],

                // Numeric keypad (all payment methods)
                Row(children: [buildKeypadButton('1'), buildKeypadButton('2'), buildKeypadButton('3')]),
                Row(children: [buildKeypadButton('4'), buildKeypadButton('5'), buildKeypadButton('6')]),
                Row(children: [buildKeypadButton('7'), buildKeypadButton('8'), buildKeypadButton('9')]),
                Row(children: [
                  buildKeypadButton('.'),
                  buildKeypadButton('0'),
                  buildKeypadButton('⌫', color: const Color(0xFFE67E22), icon: Icons.backspace_outlined),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => onKeyPress('C'),
                          borderRadius: BorderRadius.circular(16),
                          splashColor: Colors.red.withValues(alpha: 0.3),
                          child: Container(
                            height: useLandscapeLayout ? 38 : 48,
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'CLEAR',
                              style: TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (isCash)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              setDialogState(() {
                                displayAmount = _grandTotal.toStringAsFixed(0);
                                _cashReceivedController.text = displayAmount;
                              });
                            },
                            borderRadius: BorderRadius.circular(16),
                            splashColor: Colors.blue.withValues(alpha: 0.3),
                            child: Container(
                              height: useLandscapeLayout ? 38 : 48,
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'EXACT',
                                style: TextStyle(color: Colors.blue, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
              ],
            );
          }

          return Dialog(
            backgroundColor: const Color(0xFF1E1E1E),
            insetPadding: EdgeInsets.symmetric(
              horizontal: useLandscapeLayout ? 24 : 16,
              vertical: useLandscapeLayout ? 16 : 24,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: useLandscapeLayout ? 780 : 420,
                maxHeight: useLandscapeLayout ? screenSize.height * 0.85 : 700,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.payment, color: _accentColor, size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Process Payment',
                            style: TextStyle(color: _textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: _textSecondary, size: 20),
                          onPressed: () => Navigator.pop(context, false),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),

                  // Body: landscape (side-by-side) or portrait (stacked)
                  Flexible(
                    child: useLandscapeLayout
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left: payment info (30%)
                                Expanded(
                                  flex: 3,
                                  child: SingleChildScrollView(
                                    child: paymentInfoPanel(),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Divider
                                Container(
                                  width: 1,
                                  height: double.infinity,
                                  color: Colors.white.withValues(alpha: 0.06),
                                ),
                                const SizedBox(width: 16),
                                // Right: display (sticky) + keypad (scrollable) (70%)
                                Expanded(
                                  flex: 7,
                                  child: Column(
                                    children: [
                                      amountDisplay(),
                                      const SizedBox(height: 10),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          child: keypadButtons(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                // Sticky amount/reference display
                                amountDisplay(),
                                const SizedBox(height: 10),
                                // Scrollable: payment info + keypad buttons
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        paymentInfoPanel(),
                                        const SizedBox(height: 14),
                                        keypadButtons(),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),

                  // Complete Sale button
                  Builder(builder: (context) {
                    final isReady = (_paymentMethod == 'cash' && change >= 0) ||
                        ((_paymentMethod == 'card' || _paymentMethod == 'gcash/maya') && _referenceNumberController.text.trim().isNotEmpty);

                    String hintText = 'Complete Sale';
                    if (!isReady) {
                      if (_paymentMethod == 'cash') {
                        hintText = 'Enter cash amount';
                      } else {
                        hintText = 'Enter reference number';
                      }
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          decoration: BoxDecoration(
                            gradient: isReady
                                ? const LinearGradient(colors: [Color(0xFF27AE60), Color(0xFF2ECC71)])
                                : null,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: isReady
                                ? [BoxShadow(color: const Color(0xFF27AE60).withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))]
                                : null,
                          ),
                          child: ElevatedButton.icon(
                            onPressed: isReady ? () => Navigator.pop(context, true) : null,
                            icon: Icon(isReady ? Icons.check_circle : Icons.info_outline, size: 20),
                            label: Text(
                              isReady ? 'Complete Sale' : hintText,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isReady ? Colors.transparent : Colors.transparent,
                              foregroundColor: isReady ? Colors.white : _textSecondary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              disabledBackgroundColor: _textSecondary.withValues(alpha: 0.15),
                              disabledForegroundColor: _textSecondary.withValues(alpha: 0.6),
                              elevation: 0,
                              shadowColor: Colors.transparent,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPaymentMethodButton(String method, IconData icon, String label, StateSetter setDialogState, {bool disabled = false}) {
    final isSelected = _paymentMethod == method;
    return InkWell(
      onTap: disabled ? null : () {
        setDialogState(() => _paymentMethod = method);
        setState(() {});
      },
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: disabled ? 0.4 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          decoration: BoxDecoration(
            gradient: isSelected && !disabled
                ? const LinearGradient(colors: [Color(0xFFE67E22), Color(0xFFD35400)])
                : null,
            color: isSelected && !disabled ? null : _bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: disabled
                  ? _textSecondary.withValues(alpha: 0.1)
                  : (isSelected ? _accentColor : _textSecondary.withValues(alpha: 0.2)),
              width: isSelected && !disabled ? 1.5 : 1,
            ),
            boxShadow: isSelected && !disabled
                ? [BoxShadow(color: _accentColor.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))]
                : null,
          ),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.topRight,
                children: [
                  Icon(icon, color: disabled ? _textSecondary.withValues(alpha: 0.5) : (isSelected ? Colors.white : _textSecondary), size: 24),
                  if (isSelected && !disabled)
                    Container(
                      padding: const EdgeInsets.all(1),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle, color: Color(0xFFE67E22), size: 10),
                    ),
                  if (disabled)
                    Container(
                      padding: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.block, color: Colors.red.withValues(alpha: 0.7), size: 12),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    color: disabled ? _textSecondary.withValues(alpha: 0.5) : (isSelected ? Colors.white : _textSecondary),
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettingsDialog() {
    bool tempVatEnabled = _vatEnabled;
    double tempVatRate = _vatRate;
    bool tempVatInclusive = _vatInclusive;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _cardColor,
          title: const Row(
            children: [
              Icon(Icons.settings, color: _accentColor),
              SizedBox(width: 8),
              Text('POS Settings', style: TextStyle(color: _textPrimary)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // VAT Enabled Toggle
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _bgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Enable VAT',
                              style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Show VAT calculation on receipts',
                              style: TextStyle(color: _textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: tempVatEnabled,
                        onChanged: (value) {
                          setDialogState(() => tempVatEnabled = value);
                        },
                        activeColor: _accentColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // VAT Rate
                if (tempVatEnabled) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _bgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'VAT Rate',
                          style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: tempVatRate,
                                min: 0,
                                max: 25,
                                divisions: 25,
                                label: '${tempVatRate.toStringAsFixed(0)}%',
                                activeColor: _accentColor,
                                inactiveColor: _textSecondary.withValues(alpha: 0.3),
                                onChanged: (value) {
                                  setDialogState(() => tempVatRate = value);
                                },
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: _accentColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${tempVatRate.toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  color: _accentColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // VAT Inclusive Toggle
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _bgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'VAT Inclusive Pricing',
                                style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                tempVatInclusive
                                    ? 'VAT is included in selling price'
                                    : 'VAT is added on top of price',
                                style: TextStyle(color: _textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: tempVatInclusive,
                          onChanged: (value) {
                            setDialogState(() => tempVatInclusive = value);
                          },
                          activeColor: _accentColor,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: _textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                // Save settings
                await POSSettingsService.updateSettings({
                  'vatEnabled': tempVatEnabled,
                  'vatRate': tempVatRate,
                  'vatInclusive': tempVatInclusive,
                });

                // Update local state
                setState(() {
                  _vatEnabled = tempVatEnabled;
                  _vatRate = tempVatRate;
                  _vatInclusive = tempVatInclusive;
                });

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Settings saved'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPendingSyncDialog() async {
    final pendingTransactions = await CacheService.getPendingTransactions();
    final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _cardColor,
          title: Row(
            children: [
              const Icon(Icons.cloud_off, color: Colors.orange, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Pending Transactions', style: TextStyle(color: _textPrimary, fontSize: 16)),
                    Text(
                      '${pendingTransactions.length} waiting to sync',
                      style: TextStyle(color: _textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'These transactions will be automatically synced when internet connection is restored.',
                          style: TextStyle(color: _textSecondary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: pendingTransactions.length,
                    itemBuilder: (context, index) {
                      final transaction = pendingTransactions[index];
                      final total = transaction['total'] as num? ?? 0;
                      final timestamp = transaction['timestamp'] as String?;
                      final date = timestamp != null
                          ? DateFormat('MMM dd, hh:mm a').format(DateTime.parse(timestamp))
                          : 'Unknown';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _bgColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _accentColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.receipt_long, color: _accentColor, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currencyFormat.format(total),
                                    style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    date,
                                    style: TextStyle(color: _textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Pending',
                                style: TextStyle(color: Colors.orange, fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close', style: TextStyle(color: _textSecondary)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(context);
                // Attempt manual sync
                final result = await OfflineSyncService.syncPendingTransactions();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result.message),
                      backgroundColor: result.success ? Colors.green : Colors.orange,
                    ),
                  );
                  // Refresh pending count
                  final newCount = await CacheService.getPendingTransactionCount();
                  setState(() {
                    _pendingSyncCount = newCount;
                  });
                  if (result.success && result.syncedCount > 0) {
                    _loadInventory();
                  }
                }
              },
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('Sync Now'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashedDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: List.generate(
          40,
          (index) => Expanded(
            child: Container(
              height: 1,
              color: index.isEven ? _textSecondary.withValues(alpha: 0.3) : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }

  Future<bool?> _showReceiptDialog(Map<String, dynamic> transaction, {bool isOffline = false}) {
    final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final items = transaction['items'] as List<dynamic>;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final size = MediaQuery.of(context).size;
        final screenWidth = size.width;
        final isSlimPhone = screenWidth < 360;
        final horizontalPadding = isSlimPhone ? 12.0 : 24.0;

        return Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        insetPadding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isOffline
                        ? [Colors.orange.withValues(alpha: 0.2), Colors.orange.withValues(alpha: 0.05)]
                        : [Colors.green.withValues(alpha: 0.2), Colors.green.withValues(alpha: 0.05)],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    Icon(
                      isOffline ? Icons.cloud_off_rounded : Icons.check_circle_rounded,
                      color: isOffline ? Colors.orange : Colors.green,
                      size: isSlimPhone ? 40 : 48,
                    ),
                    SizedBox(height: isSlimPhone ? 8 : 10),
                    Text(
                      isOffline ? 'Saved Offline' : 'Sale Complete!',
                      style: TextStyle(
                        color: isOffline ? Colors.orange : Colors.green,
                        fontSize: isSlimPhone ? 16 : 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (isOffline)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Will sync when online',
                          style: TextStyle(color: Colors.orange.withValues(alpha: 0.8), fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),

              // Receipt body
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(isSlimPhone ? 12 : 20, 16, isSlimPhone ? 12 : 20, 0),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(isSlimPhone ? 12 : 16),
                    decoration: BoxDecoration(
                      color: _bgColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Store header with logo
                        Center(
                          child: Column(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.all(5),
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(Icons.phone_android, color: Color(0xFF8B1A1A), size: 20);
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'GM PHONESHOPPE',
                                style: TextStyle(
                                  color: _accentColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Transaction #${transaction['transactionId']}',
                                style: TextStyle(color: _textSecondary, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              Text(
                                DateFormat('MMM dd, yyyy hh:mm a').format(DateTime.parse(transaction['timestamp'])),
                                style: TextStyle(color: _textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        _dashedDivider(),
                        // Items
                        ...items.map((item) {
                          final isCashOut = item['isCashOut'] == true;
                          final isCashIn = item['isCashIn'] == true;
                          final hasDiscount = item['discountAmount'] != null && (item['discountAmount'] as num) > 0;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['name'],
                                        style: TextStyle(
                                          color: hasDiscount ? Colors.green : (isCashOut ? const Color(0xFFE67E22) : _textPrimary),
                                          fontSize: 12,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (hasDiscount) ...[
                                        Text(
                                          'Before: ${currencyFormat.format(item['originalPrice'])} → After: ${currencyFormat.format(item['discountedPrice'])}',
                                          style: TextStyle(
                                            color: Colors.green.withValues(alpha: 0.7),
                                            fontSize: 10,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                        Text(
                                          'Saved: ${currencyFormat.format(item['discountAmount'])}',
                                          style: TextStyle(
                                            color: Colors.green.withValues(alpha: 0.9),
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                      if (isCashOut || isCashIn) ...[
                                        Text(
                                          isCashOut
                                              ? 'Cash Given: ${currencyFormat.format(item['actualCashGiven'] ?? item['cashOutAmount'])}'
                                              : 'Cash Received: ${currencyFormat.format(item['actualCashGiven'] ?? item['cashOutAmount'])}',
                                          style: TextStyle(color: isCashOut ? Colors.red : Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                        if (item['feeHandling'] == 'fee_included')
                                          Text(
                                            'Service Fee: ${currencyFormat.format(item['serviceFee'])} (included)',
                                            style: TextStyle(color: _textSecondary, fontSize: 9, fontStyle: FontStyle.italic),
                                          )
                                        else if (item['feeHandling'] == 'fee_separate')
                                          Text(
                                            'Service Fee: ${currencyFormat.format(item['serviceFee'])} (to cashier)',
                                            style: TextStyle(color: Colors.orange, fontSize: 9, fontStyle: FontStyle.italic),
                                          )
                                        else if (item['feeHandling'] == 'auto_deduct')
                                          Text(
                                            'Service Fee: ${currencyFormat.format(item['serviceFee'])} (deducted)',
                                            style: TextStyle(color: Colors.orange, fontSize: 9, fontStyle: FontStyle.italic),
                                          )
                                        else
                                          Text(
                                            'Service Fee: ${currencyFormat.format(item['serviceFee'])}',
                                            style: TextStyle(color: _textSecondary, fontSize: 10),
                                          ),
                                      ] else if (!hasDiscount)
                                        Text(
                                          '${item['quantity']} x ${currencyFormat.format(item['unitPrice'])}',
                                          style: TextStyle(color: _textSecondary, fontSize: 10),
                                        ),
                                      if (hasDiscount && !isCashOut && !isCashIn)
                                        Text(
                                          '${item['quantity']} x ${currencyFormat.format(item['unitPrice'])}',
                                          style: TextStyle(color: Colors.green.withValues(alpha: 0.8), fontSize: 10),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  currencyFormat.format(item['subtotal']),
                                  style: const TextStyle(color: _textPrimary, fontSize: 12),
                                ),
                              ],
                            ),
                          );
                        }),
                        _dashedDivider(),
                        // Total — prominent
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: _accentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'TOTAL',
                                style: TextStyle(color: _accentColor, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                currencyFormat.format(transaction['total']),
                                style: const TextStyle(color: _accentColor, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        if (transaction['vatEnabled'] == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: _receiptRow(
                              transaction['vatInclusive'] == true
                                  ? 'VAT Included (${(transaction['vatRate'] as num?)?.toStringAsFixed(0) ?? '12'}%)'
                                  : 'VAT (${(transaction['vatRate'] as num?)?.toStringAsFixed(0) ?? '12'}%)',
                              currencyFormat.format(transaction['vatAmount'] ?? 0),
                            ),
                          ),
                        if (((transaction['transactionFee'] as num?)?.toDouble() ?? 0) > 0) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: _receiptRow(
                              transaction['feeHandling'] == 'customer_pays'
                                  ? 'Transaction Fee (2%)'
                                  : 'Fee Absorbed (2%)',
                              transaction['feeHandling'] == 'customer_pays'
                                  ? '+${currencyFormat.format(transaction['transactionFee'] ?? 0)}'
                                  : '-${currencyFormat.format(transaction['transactionFee'] ?? 0)}',
                            ),
                          ),
                          if (transaction['feeHandling'] == 'business_absorbs')
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: _receiptRow(
                                'Net Received',
                                currencyFormat.format(transaction['netReceived'] ?? transaction['total']),
                                isBold: true,
                              ),
                            ),
                        ],
                        const SizedBox(height: 8),
                        _receiptRow('Payment', transaction['paymentMethod'].toString().toUpperCase()),
                        if (transaction['paymentMethod'] == 'cash') ...[
                          _receiptRow('Cash', currencyFormat.format(transaction['cashReceived'])),
                          _receiptRow('Change', currencyFormat.format(transaction['change'])),
                        ],
                        if (transaction['referenceNumber']?.isNotEmpty == true)
                          _receiptRow('Ref #', transaction['referenceNumber']),
                        if (transaction['customerName']?.isNotEmpty == true)
                          _receiptRow('Customer', transaction['customerName']),
                        // Cash-out summary
                        if (transaction['hasCashOut'] == true) ...[
                          _dashedDivider(),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'CASH-OUT SUMMARY',
                                  style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Cash Given:', style: TextStyle(color: Colors.red, fontSize: 12)),
                                    Text(
                                      currencyFormat.format(transaction['totalCashOutAmount']),
                                      style: const TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Service Fee:', style: TextStyle(color: _textSecondary, fontSize: 11)),
                                    Text(
                                      currencyFormat.format(transaction['totalServiceFee']),
                                      style: TextStyle(color: _textSecondary, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                        // Discount summary (if discounts were applied)
                        if (transaction['hasDiscounts'] == true) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.discount, color: Colors.green, size: 14),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'DISCOUNTS APPLIED',
                                      style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Authorized by: ${transaction['discountAuthorizedBy'] ?? 'Unknown'}',
                                  style: TextStyle(color: _textSecondary, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                        _dashedDivider(),
                        Center(
                          child: Text(
                            'Served by: ${transaction['processedBy']?.toString().split(' ').first ?? 'Staff'}',
                            style: TextStyle(color: _textSecondary, fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Action buttons
              Padding(
                padding: EdgeInsets.all(isSlimPhone ? 12 : 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _textSecondary,
                          side: BorderSide(color: _textSecondary.withValues(alpha: 0.3)),
                          padding: EdgeInsets.symmetric(vertical: isSlimPhone ? 12 : 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          'Skip',
                          style: TextStyle(fontSize: isSlimPhone ? 13 : 14),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentColor,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: isSlimPhone ? 12 : 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        icon: Icon(Icons.print, size: isSlimPhone ? 16 : 18),
                        label: Text(
                          isSlimPhone ? 'Print' : 'Print & Save',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isSlimPhone ? 13 : 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
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
      },
    );
  }

  Widget _receiptRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: _textSecondary,
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isBold ? _accentColor : _textPrimary,
              fontSize: isBold ? 14 : 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _showPrintConfirmationDialog(Map<String, dynamic> transaction) {
    final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final items = transaction['items'] as List<dynamic>;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final size = MediaQuery.of(context).size;
        final screenWidth = size.width;
        final screenHeight = size.height;
        final isLandscape = screenWidth > screenHeight;
        final isSlimPhone = screenWidth < 360;
        final isSmallLandscape = isLandscape && screenWidth < 600;
        final horizontalPadding = isSlimPhone ? 12.0 : (isLandscape ? (isSmallLandscape ? 16.0 : 40.0) : 24.0);

        return Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        insetPadding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: isLandscape ? 16 : 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isLandscape ? (isSmallLandscape ? 500 : 650) : 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status header
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: isSmallLandscape ? 12 : (isSlimPhone ? 16 : 20)),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_accentColor.withValues(alpha: 0.2), _accentColor.withValues(alpha: 0.05)],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.print,
                      color: _accentColor,
                      size: isSmallLandscape ? 36 : (isSlimPhone ? 40 : 48),
                    ),
                    SizedBox(height: isSmallLandscape ? 6 : 10),
                    Text(
                      'Did it print?',
                      style: TextStyle(
                        color: _accentColor,
                        fontSize: isSmallLandscape ? 15 : (isSlimPhone ? 16 : 18),
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Verify the receipt printed correctly',
                        style: TextStyle(
                          color: _textSecondary,
                          fontSize: isSmallLandscape ? 10 : 12,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        maxLines: isSmallLandscape ? 1 : 2,
                      ),
                    ),
                  ],
                ),
              ),

              // Receipt body
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    isSlimPhone || isSmallLandscape ? 12 : 20,
                    isSmallLandscape ? 12 : 16,
                    isSlimPhone || isSmallLandscape ? 12 : 20,
                    0
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(isSlimPhone || isSmallLandscape ? 12 : 16),
                    decoration: BoxDecoration(
                      color: _bgColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Store header with logo
                        Center(
                          child: Column(
                            children: [
                              Container(
                                width: isSmallLandscape ? 32 : 40,
                                height: isSmallLandscape ? 32 : 40,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(isSmallLandscape ? 8 : 10),
                                ),
                                padding: EdgeInsets.all(isSmallLandscape ? 4 : 5),
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Icon(Icons.phone_android, color: const Color(0xFF8B1A1A), size: isSmallLandscape ? 16 : 20);
                                  },
                                ),
                              ),
                              SizedBox(height: isSmallLandscape ? 6 : 8),
                              Text(
                                'GM PHONESHOPPE',
                                style: TextStyle(
                                  color: _accentColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: isSmallLandscape ? 14 : 16,
                                  letterSpacing: isSmallLandscape ? 0.8 : 1,
                                ),
                              ),
                              SizedBox(height: isSmallLandscape ? 3 : 4),
                              Text(
                                'Transaction #${transaction['transactionId']}',
                                style: TextStyle(color: _textSecondary, fontSize: isSmallLandscape ? 10 : 12),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              Text(
                                DateFormat('MMM dd, yyyy hh:mm a').format(DateTime.parse(transaction['timestamp'])),
                                style: TextStyle(color: _textSecondary, fontSize: isSmallLandscape ? 10 : 12),
                              ),
                            ],
                          ),
                        ),
                        _dashedDivider(),
                        // Items summary
                        ...items.take(isSmallLandscape ? 2 : 3).map((item) {
                          final isCashOut = item['isCashOut'] == true;
                          final isCashIn = item['isCashIn'] == true;
                          final hasDiscount = item['discountAmount'] != null && (item['discountAmount'] as num) > 0;

                          return Padding(
                            padding: EdgeInsets.symmetric(vertical: isSmallLandscape ? 3 : 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['name'],
                                        style: TextStyle(
                                          color: hasDiscount ? Colors.green : (isCashOut ? const Color(0xFFE67E22) : _textPrimary),
                                          fontSize: isSmallLandscape ? 11 : 12,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (hasDiscount) ...[
                                        Text(
                                          'Before: ${currencyFormat.format(item['originalPrice'])} → After: ${currencyFormat.format(item['discountedPrice'])}',
                                          style: TextStyle(
                                            color: Colors.green.withValues(alpha: 0.7),
                                            fontSize: isSmallLandscape ? 9 : 10,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                        Text(
                                          'Saved: ${currencyFormat.format(item['discountAmount'])}',
                                          style: TextStyle(
                                            color: Colors.green.withValues(alpha: 0.9),
                                            fontSize: isSmallLandscape ? 8 : 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                      if (isCashOut || isCashIn) ...[
                                        Text(
                                          isCashOut
                                              ? 'Cash Given: ${currencyFormat.format(item['actualCashGiven'] ?? item['cashOutAmount'])}'
                                              : 'Cash Received: ${currencyFormat.format(item['actualCashGiven'] ?? item['cashOutAmount'])}',
                                          style: TextStyle(
                                            color: isCashOut ? Colors.red : Colors.green,
                                            fontSize: isSmallLandscape ? 9 : 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (item['feeHandling'] == 'fee_included')
                                          Text(
                                            'Service Fee: ${currencyFormat.format(item['serviceFee'])} (included)',
                                            style: TextStyle(
                                              color: _textSecondary,
                                              fontSize: isSmallLandscape ? 8 : 9,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          )
                                        else if (item['feeHandling'] == 'fee_separate')
                                          Text(
                                            'Service Fee: ${currencyFormat.format(item['serviceFee'])} (to cashier)',
                                            style: TextStyle(
                                              color: Colors.orange,
                                              fontSize: isSmallLandscape ? 8 : 9,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          )
                                        else if (item['feeHandling'] == 'auto_deduct')
                                          Text(
                                            'Service Fee: ${currencyFormat.format(item['serviceFee'])} (deducted)',
                                            style: TextStyle(
                                              color: Colors.orange,
                                              fontSize: isSmallLandscape ? 8 : 9,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          )
                                        else
                                          Text(
                                            'Service Fee: ${currencyFormat.format(item['serviceFee'])}',
                                            style: TextStyle(
                                              color: _textSecondary,
                                              fontSize: isSmallLandscape ? 9 : 10,
                                            ),
                                          ),
                                      ] else if (!hasDiscount)
                                        Text(
                                          '${item['quantity']} x ${currencyFormat.format(item['unitPrice'])}',
                                          style: TextStyle(
                                            color: _textSecondary,
                                            fontSize: isSmallLandscape ? 9 : 10,
                                          ),
                                        ),
                                      if (hasDiscount && !isCashOut && !isCashIn)
                                        Text(
                                          '${item['quantity']} x ${currencyFormat.format(item['unitPrice'])}',
                                          style: TextStyle(
                                            color: Colors.green.withValues(alpha: 0.8),
                                            fontSize: isSmallLandscape ? 9 : 10,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  currencyFormat.format(item['subtotal']),
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontSize: isSmallLandscape ? 11 : 12,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        if (items.length > (isSmallLandscape ? 2 : 3))
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: isSmallLandscape ? 3 : 4),
                            child: Text(
                              '... and ${items.length - (isSmallLandscape ? 2 : 3)} more items',
                              style: TextStyle(color: _textSecondary, fontSize: isSmallLandscape ? 10 : 11, fontStyle: FontStyle.italic),
                            ),
                          ),
                        _dashedDivider(),
                        // Total
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: _accentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'TOTAL',
                                style: TextStyle(color: _accentColor, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                currencyFormat.format(transaction['total']),
                                style: const TextStyle(color: _accentColor, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _receiptRow('Payment', transaction['paymentMethod'].toString().toUpperCase()),
                      ],
                    ),
                  ),
                ),
              ),

              // Action buttons
              Padding(
                padding: EdgeInsets.all(isSlimPhone ? 12 : 20),
                child: isLandscape
                    ? Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context, 'skip'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _textSecondary,
                                side: BorderSide(color: _textSecondary.withValues(alpha: 0.3)),
                                padding: EdgeInsets.symmetric(vertical: isSmallLandscape ? 10 : 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text(
                                isSmallLandscape ? 'Skip' : 'Skip Print',
                                style: TextStyle(fontSize: isSmallLandscape ? 12 : 14),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                          SizedBox(width: isSmallLandscape ? 6 : 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: isSmallLandscape ? 10 : 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              onPressed: () => Navigator.pop(context, 'retry'),
                              icon: Icon(Icons.refresh, size: isSmallLandscape ? 16 : 18),
                              label: Text(
                                'Retry',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: isSmallLandscape ? 12 : 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                          SizedBox(width: isSmallLandscape ? 6 : 12),
                          Expanded(
                            flex: isSmallLandscape ? 2 : 2,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: isSmallLandscape ? 10 : 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              onPressed: () => Navigator.pop(context, 'yes'),
                              icon: Icon(Icons.check_circle, size: isSmallLandscape ? 18 : 20),
                              label: Text(
                                isSmallLandscape ? 'Printed' : 'Yes, Printed',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: isSmallLandscape ? 13 : 15,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: isSlimPhone ? 12 : 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    elevation: 0,
                                  ),
                                  onPressed: () => Navigator.pop(context, 'yes'),
                                  icon: const Icon(Icons.check_circle, size: 18),
                                  label: Text(
                                    'Yes, Printed',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: isSlimPhone ? 13 : 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(context, 'skip'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _textSecondary,
                                    side: BorderSide(color: _textSecondary.withValues(alpha: 0.3)),
                                    padding: EdgeInsets.symmetric(vertical: isSlimPhone ? 10 : 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: Text(
                                    'Skip Print',
                                    style: TextStyle(fontSize: isSlimPhone ? 12 : 13),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: isSlimPhone ? 10 : 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    elevation: 0,
                                  ),
                                  onPressed: () => Navigator.pop(context, 'retry'),
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: Text(
                                    'Retry',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: isSlimPhone ? 12 : 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        foregroundColor: _textPrimary,
        elevation: 0,
        toolbarHeight: 44,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_accentColor, _accentDark]),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.point_of_sale, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
            const Text('POS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
          ],
        ),
        actions: [
          // Pending sync indicator
          if (_pendingSyncCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                onTap: () => _showPendingSyncDialog(),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, color: Colors.orange, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '$_pendingSyncCount',
                        style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.point_of_sale, color: Colors.white, size: 20),
            onPressed: _openCashDrawerForChange,
            tooltip: 'Open Drawer for Change',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          IconButton(
            icon: Icon(
              _discountModeEnabled ? Icons.discount : Icons.discount_outlined,
              color: _discountModeEnabled ? Colors.green : Colors.white,
              size: 20,
            ),
            onPressed: _toggleDiscountMode,
            tooltip: 'Discount Mode',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white, size: 20),
            onPressed: _showSettingsDialog,
            tooltip: 'POS Settings',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          IconButton(
            icon: const Icon(Icons.pin, color: Colors.white, size: 20),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
            tooltip: 'Staff PIN & Account Settings',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          const PrinterStatusButton(),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
            onPressed: () {
              _loadInventory();
              _loadPendingBaskets();
            },
            tooltip: 'Refresh',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          if (_cartItems.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: _cardColor,
                    title: const Text('Clear Cart?', style: TextStyle(color: _textPrimary)),
                    content: Text('Remove all items from cart?', style: TextStyle(color: _textSecondary)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Cancel', style: TextStyle(color: _textSecondary)),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () {
                          Navigator.pop(context);
                          _clearCart();
                        },
                        child: const Text('Clear', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
              },
              tooltip: 'Clear Cart',
            ),
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back to Inventory',
          ),
        ],
        bottom: isMobile ? TabBar(
          controller: _tabController,
          indicatorColor: _accentColor,
          labelColor: _accentColor,
          unselectedLabelColor: _textSecondary,
          tabs: [
            Tab(
              icon: Badge(
                label: Text('${_cartItems.length}'),
                isLabelVisible: _cartItems.isNotEmpty,
                child: const Icon(Icons.shopping_cart),
              ),
              text: 'Cart',
            ),
            Tab(
              icon: Badge(
                label: Text('${_pendingBaskets.length}'),
                isLabelVisible: _pendingBaskets.isNotEmpty,
                child: const Icon(Icons.shopping_basket),
              ),
              text: 'Baskets',
            ),
            const Tab(icon: Icon(Icons.inventory_2), text: 'Products'),
          ],
        ) : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _accentColor))
          : isMobile
              ? _buildMobileLayout(currencyFormat)
              : _buildDesktopLayout(currencyFormat),
    );
  }

  Widget _buildMobileLayout(NumberFormat currencyFormat) {
    return Column(
      children: [
        // Selected basket indicator
        if (_selectedBasket != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.blue.withValues(alpha: 0.15),
            child: Row(
              children: [
                const Icon(Icons.shopping_basket, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Processing Basket #${_selectedBasket!['basketNumber']} by ${_selectedBasket!['userName']}',
                    style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.blue, size: 20),
                  onPressed: _deselectBasket,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildMobileCartTab(currencyFormat),
              _buildPendingBasketsTab(currencyFormat),
              _buildProductsTab(currencyFormat),
            ],
          ),
        ),
        // Cart summary bar
        if (_cartItems.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _cardColor,
              border: Border(top: BorderSide(color: _textSecondary.withValues(alpha: 0.2))),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Badge(
                    label: Text('${_cartItems.length}'),
                    child: const Icon(Icons.shopping_cart, color: _accentColor, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total', style: const TextStyle(color: _textSecondary, fontSize: 12)),
                        Text(
                          currencyFormat.format(_grandTotal),
                          style: const TextStyle(
                            color: _accentColor,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _processTransaction,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.payment),
                    label: const Text('Pay'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadInventory(),
      _loadPendingBaskets(),
    ]);
  }

  Widget _buildMobileCartTab(NumberFormat currencyFormat) {
    if (_cartItems.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshAll,
        color: _accentColor,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 64, color: _textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'Cart is empty',
              style: TextStyle(color: _textSecondary.withValues(alpha: 0.7), fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Add products or select a basket to get started',
              style: TextStyle(color: _textSecondary.withValues(alpha: 0.5), fontSize: 12),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _openOcrScanner,
              icon: const Icon(Icons.document_scanner, size: 20),
              label: const Text('Scan QR / OCR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Scan button bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_cartItems.length} item${_cartItems.length != 1 ? 's' : ''} in cart',
                  style: const TextStyle(color: _textSecondary, fontSize: 13),
                ),
              ),
              TextButton.icon(
                onPressed: _openOcrScanner,
                icon: const Icon(Icons.document_scanner, size: 16),
                label: const Text('Scan QR'),
                style: TextButton.styleFrom(foregroundColor: _accentColor),
              ),
            ],
          ),
        ),
        // Cart items list
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshAll,
            color: _accentColor,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: _cartItems.length,
            itemBuilder: (context, index) {
              final item = _cartItems[index];
              final price = (item['sellingPrice'] ?? item['unitPrice']) as num? ?? 0;
              final cartQty = item['cartQuantity'] as int? ?? 1;
              final subtotal = price * cartQty;
              final availableQty = item['quantity'] as int? ?? item['availableStock'] as int? ?? 0;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: _cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // Item info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['name'] ?? 'Unknown',
                              style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              currencyFormat.format(price),
                              style: TextStyle(color: _textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      // Quantity controls
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () => _updateCartQuantity(index, cartQty - 1),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: _textSecondary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(Icons.remove, size: 16, color: _textSecondary),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              '$cartQty',
                              style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.bold),
                            ),
                          ),
                          InkWell(
                            onTap: cartQty < availableQty ? () => _updateCartQuantity(index, cartQty + 1) : null,
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: cartQty < availableQty ? _accentColor.withValues(alpha: 0.1) : _textSecondary.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(Icons.add, size: 16, color: cartQty < availableQty ? _accentColor : _textSecondary.withValues(alpha: 0.3)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      // Subtotal and delete
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            currencyFormat.format(subtotal),
                            style: const TextStyle(color: _accentColor, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () => _removeFromCart(index),
                            child: Icon(Icons.delete_outline, size: 18, color: Colors.red.withValues(alpha: 0.7)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
            ),
          ),
        ),
        // Clear cart button
        if (_cartItems.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: _clearCart,
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear Cart'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPendingBasketsTab(NumberFormat currencyFormat) {
    if (_pendingBaskets.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadPendingBaskets,
        color: _accentColor,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shopping_basket_outlined, size: 64, color: _textSecondary.withValues(alpha: 0.5)),
                    const SizedBox(height: 16),
                    Text(
                      'No pending baskets',
                      style: TextStyle(color: _textSecondary.withValues(alpha: 0.7), fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Baskets created by users will appear here',
                      style: TextStyle(color: _textSecondary.withValues(alpha: 0.5), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPendingBaskets,
      color: _accentColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _pendingBaskets.length,
        itemBuilder: (context, index) {
          final basket = _pendingBaskets[index];
          return _buildBasketCard(basket, currencyFormat);
        },
      ),
    );
  }

  Widget _buildBasketCard(Map<String, dynamic> basket, NumberFormat currencyFormat) {
    final isSelected = _selectedBasket?['firebaseKey'] == basket['firebaseKey'];
    final items = basket['items'] as List? ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? _accentColor.withValues(alpha: 0.15) : _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? _accentColor : _textSecondary.withValues(alpha: 0.1),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => _selectBasket(basket),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.shopping_basket, color: Colors.blue, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Basket #${basket['basketNumber']}',
                          style: const TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'by ${basket['userName']}',
                          style: TextStyle(color: _textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        currencyFormat.format(basket['total'] ?? 0),
                        style: const TextStyle(
                          color: _accentColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        '${basket['itemCount']} items',
                        style: TextStyle(color: _textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Items preview
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    ...items.take(3).map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item['quantity']}x ${item['name']}',
                              style: TextStyle(color: _textSecondary, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            currencyFormat.format(item['subtotal']),
                            style: const TextStyle(color: _textPrimary, fontSize: 12),
                          ),
                        ],
                      ),
                    )),
                    if (items.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '+${items.length - 3} more items',
                          style: TextStyle(color: _textSecondary.withValues(alpha: 0.7), fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Action button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    _selectBasket(basket);
                    _processTransaction();
                  },
                  icon: const Icon(Icons.payment, size: 18),
                  label: const Text('Process Payment'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSelected ? _accentColor : _accentColor.withValues(alpha: 0.8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductsTab(NumberFormat currencyFormat) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: _textPrimary),
            decoration: InputDecoration(
              hintText: 'Search products...',
              hintStyle: TextStyle(color: _textSecondary.withValues(alpha: 0.5)),
              prefixIcon: Icon(Icons.search, color: _textSecondary),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchQuery.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.clear, color: _textSecondary),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
                  if (!isLandscape) ...[
                    IconButton(
                      icon: const Icon(Icons.document_scanner, color: _accentColor),
                      onPressed: _openOcrScanner,
                      tooltip: 'OCR Scanner',
                    ),
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner, color: _accentColor),
                      onPressed: _openBarcodeScanner,
                      tooltip: 'Barcode Scanner',
                    ),
                  ],
                ],
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _accentColor),
              ),
              filled: true,
              fillColor: _cardColor,
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        // Add manual item & Cash-In buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showAddManualItemDialog,
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Add Item'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accentColor,
                    side: BorderSide(color: _accentColor.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showCashInDialog,
                  icon: const Icon(Icons.account_balance_wallet, size: 18),
                  label: const Text('E-wallet'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF007BFF),
                    side: BorderSide(color: const Color(0xFF007BFF).withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Products list (collapsed by default, expandable)
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshAll,
            color: _accentColor,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: _filteredInventory.length,
              itemBuilder: (context, index) {
                return _buildProductTile(_filteredInventory[index], currencyFormat);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(NumberFormat currencyFormat) {
    return Row(
      children: [
        // LEFT - BASKETS (20%)
        Expanded(
          flex: 2,
          child: Container(
            decoration: BoxDecoration(
              color: _cardColor,
              border: Border(right: BorderSide(color: _textSecondary.withValues(alpha: 0.2))),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    border: Border(bottom: BorderSide(color: _textSecondary.withValues(alpha: 0.2))),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shopping_basket, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Baskets (${_pendingBaskets.length})',
                        style: const TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                // Baskets list
                Expanded(
                  child: _pendingBaskets.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.shopping_basket_outlined, size: 48, color: _textSecondary.withValues(alpha: 0.3)),
                              const SizedBox(height: 8),
                              Text('No pending baskets', style: TextStyle(color: _textSecondary.withValues(alpha: 0.5), fontSize: 12)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _pendingBaskets.length,
                          itemBuilder: (context, index) {
                            final basket = _pendingBaskets[index];
                            final isSelected = _selectedBasket?['firebaseKey'] == basket['firebaseKey'];
                            final total = (basket['total'] as num?)?.toDouble() ?? 0;
                            final userName = basket['userName'] as String? ?? 'Unknown';
                            return GestureDetector(
                              onTap: () => _selectBasket(basket),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isSelected ? _accentColor.withValues(alpha: 0.2) : _bgColor,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected ? _accentColor : _textSecondary.withValues(alpha: 0.2),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Basket #${basket['basketNumber']}',
                                          style: TextStyle(
                                            color: isSelected ? _accentColor : _textPrimary,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (isSelected)
                                          const Icon(Icons.check_circle, color: _accentColor, size: 18),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(userName, style: TextStyle(color: _textSecondary, fontSize: 11)),
                                    const SizedBox(height: 4),
                                    Text(
                                      currencyFormat.format(total),
                                      style: TextStyle(
                                        color: isSelected ? _accentColor : Colors.green,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        // MIDDLE - PRODUCTS (40%)
        Expanded(
          flex: 4,
          child: Container(
            color: _bgColor,
            child: Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: _textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search by name or barcode...',
                      hintStyle: TextStyle(color: _textSecondary.withValues(alpha: 0.5), fontSize: 14),
                      prefixIcon: const Icon(Icons.search, color: _textSecondary),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: _cardColor,
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                // Add manual item & Cash-In buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _showAddManualItemDialog,
                          icon: const Icon(Icons.add_circle_outline, size: 16),
                          label: const Text('Add Item', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _accentColor,
                            side: BorderSide(color: _accentColor.withValues(alpha: 0.5)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _showCashInDialog,
                          icon: const Icon(Icons.account_balance_wallet, size: 16),
                          label: const Text('E-wallet', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF007BFF),
                            side: BorderSide(color: const Color(0xFF007BFF).withValues(alpha: 0.5)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Products list with expand/collapse
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refreshAll,
                    color: _accentColor,
                    child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _filteredInventory.length,
                    itemBuilder: (context, index) {
                      final item = _filteredInventory[index];
                      final name = item['name'] as String? ?? 'Unnamed';
                      final brand = item['brand'] as String? ?? '';
                      final sku = item['sku'] as String? ?? item['serialNo'] as String? ?? '';
                      final category = item['category'] as String? ?? '';
                      final price = (item['sellingPrice'] as num?)?.toDouble() ?? 0;
                      final stock = item['quantity'] as int? ?? 0;
                      final itemId = item['id'] as String? ?? '';
                      final isExpanded = _expandedProductId == itemId;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: _cardColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isExpanded ? _accentColor.withValues(alpha: 0.4) : _textSecondary.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Column(
                          children: [
                            // Collapsed header — always visible, tap to expand
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _expandedProductId = isExpanded ? null : itemId;
                                });
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: _bgColor,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(_getCategoryIcon(item['category']), color: _accentColor, size: 22),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: const TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                                            maxLines: isExpanded ? 3 : 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (brand.isNotEmpty)
                                            Text(brand, style: TextStyle(color: _textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(currencyFormat.format(price), style: const TextStyle(color: _accentColor, fontWeight: FontWeight.bold, fontSize: 14)),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: stock < 10 ? Colors.orange.withValues(alpha: 0.15) : _bgColor,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Stock: $stock',
                                            style: TextStyle(color: stock < 10 ? Colors.orange : _textSecondary, fontSize: 10, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      isExpanded ? Icons.expand_less : Icons.expand_more,
                                      color: _textSecondary,
                                      size: 22,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Expanded details + Add to Cart
                            if (isExpanded)
                              Container(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Divider(color: _textSecondary.withValues(alpha: 0.12), height: 1),
                                    const SizedBox(height: 10),
                                    // Detail rows in a wrap for desktop width
                                    Wrap(
                                      spacing: 24,
                                      runSpacing: 6,
                                      children: [
                                        if (sku.isNotEmpty)
                                          _buildDesktopDetailChip('SKU / S.N.', sku),
                                        if (category.isNotEmpty)
                                          _buildDesktopDetailChip('Category', category),
                                        _buildDesktopDetailChip('Full Name', name),
                                        if (brand.isNotEmpty)
                                          _buildDesktopDetailChip('Brand', brand),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    // Add to Cart button
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: stock > 0 ? () => _addToCart(item) : null,
                                        icon: const Icon(Icons.add_shopping_cart, size: 18),
                                        label: Text(stock > 0 ? 'Add to Cart' : 'Out of Stock'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _accentColor,
                                          foregroundColor: Colors.white,
                                          disabledBackgroundColor: _textSecondary.withValues(alpha: 0.2),
                                          disabledForegroundColor: _textSecondary,
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // RIGHT - RECEIPT (40%) - DARK MODE
        Expanded(
          flex: 4,
          child: Container(
            decoration: BoxDecoration(
              color: _cardColor,
              border: Border(left: BorderSide(color: _textSecondary.withValues(alpha: 0.2))),
            ),
            child: Column(
              children: [
                // Receipt header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _accentColor.withValues(alpha: 0.15),
                    border: Border(bottom: BorderSide(color: _textSecondary.withValues(alpha: 0.2))),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long, color: _accentColor, size: 18),
                      const SizedBox(width: 8),
                      const Text('Cart', style: TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: _accentColor, borderRadius: BorderRadius.circular(10)),
                        child: Text('${_cartItems.length}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      if (_selectedBasket != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                          child: Text('#${_selectedBasket!['basketNumber']}', style: const TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                      const Spacer(),
                      if (_cartItems.isNotEmpty)
                        GestureDetector(
                          onTap: _clearCart,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.delete_outline, color: Colors.red, size: 14),
                                SizedBox(width: 4),
                                Text('Clear', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Cart items - SCROLLABLE
                Expanded(
                  child: _cartItems.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.shopping_cart_outlined, size: 40, color: _textSecondary.withValues(alpha: 0.3)),
                              const SizedBox(height: 6),
                              Text('Select a basket or add items', style: TextStyle(color: _textSecondary.withValues(alpha: 0.5), fontSize: 11)),
                            ],
                          ),
                        )
                      : ListView.builder(
                                      padding: const EdgeInsets.all(8),
                                      itemCount: _cartItems.length,
                                      itemBuilder: (context, index) {
                                        final item = _cartItems[index];
                                        final name = item['name'] as String? ?? '';
                                        final qty = item['cartQuantity'] as int? ?? 1;
                                        final originalPrice = (item['sellingPrice'] as num?)?.toDouble() ?? 0;
                                        final currentPrice = (item['_discountedPrice'] as double?) ?? originalPrice;
                                        final lineTotal = currentPrice * qty;
                                        final hasDiscount = item['_discountedPrice'] != null;

                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 6),
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: _bgColor,
                                            borderRadius: BorderRadius.circular(6),
                                            border: hasDiscount ? Border.all(color: Colors.green.withValues(alpha: 0.3), width: 1) : null,
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                            children: [
                                              // Quantity controls
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  GestureDetector(
                                                    onTap: () => _updateCartQuantity(index, qty - 1),
                                                    child: Container(
                                                      width: 24,
                                                      height: 24,
                                                      decoration: BoxDecoration(
                                                        color: _textSecondary.withValues(alpha: 0.1),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      alignment: Alignment.center,
                                                      child: Icon(Icons.remove, size: 14, color: _textSecondary),
                                                    ),
                                                  ),
                                                  Container(
                                                    width: 28,
                                                    height: 28,
                                                    alignment: Alignment.center,
                                                    child: Text('$qty', style: const TextStyle(color: _accentColor, fontSize: 12, fontWeight: FontWeight.bold)),
                                                  ),
                                                  GestureDetector(
                                                    onTap: () {
                                                      final availableQty = item['quantity'] as int? ?? item['availableStock'] as int? ?? 0;
                                                      if (qty < availableQty) _updateCartQuantity(index, qty + 1);
                                                    },
                                                    child: Container(
                                                      width: 24,
                                                      height: 24,
                                                      decoration: BoxDecoration(
                                                        color: _accentColor.withValues(alpha: 0.1),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      alignment: Alignment.center,
                                                      child: Icon(Icons.add, size: 14, color: _accentColor),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(width: 8),
                                              // Item name and price
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(name, style: const TextStyle(color: _textPrimary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                    if (hasDiscount) ...[
                                                      Text('@${currencyFormat.format(originalPrice)}', style: TextStyle(color: _textSecondary, fontSize: 10, decoration: TextDecoration.lineThrough)),
                                                      Text('@${currencyFormat.format(currentPrice)}', style: const TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                                                    ] else
                                                      Text('@${currencyFormat.format(currentPrice)}', style: TextStyle(color: _textSecondary, fontSize: 10)),
                                                  ],
                                                ),
                                              ),
                                              // Line total
                                              Text(currencyFormat.format(lineTotal), style: const TextStyle(color: _accentColor, fontSize: 12, fontWeight: FontWeight.bold)),
                                              const SizedBox(width: 8),
                                              // Delete button
                                              GestureDetector(
                                                onTap: () => _removeFromCart(index),
                                                child: Container(
                                                  padding: const EdgeInsets.all(4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red.withValues(alpha: 0.2),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Icon(Icons.close, color: Colors.red, size: 16),
                                                ),
                                              ),
                                            ],
                                          ),
                                          // Discount adjustment UI (only shown when discount mode is enabled)
                                          if (_discountModeEnabled)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 8),
                                              child: Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.edit, color: Colors.green, size: 14),
                                                    const SizedBox(width: 6),
                                                    const Text(
                                                      'Adjust Price:',
                                                      style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: SizedBox(
                                                        height: 32,
                                                        child: TextField(
                                                          key: ValueKey('discount_$index'),
                                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                          style: const TextStyle(color: _textPrimary, fontSize: 12),
                                                          decoration: InputDecoration(
                                                            prefixText: '₱ ',
                                                            hintText: currencyFormat.format(originalPrice),
                                                            hintStyle: TextStyle(color: _textSecondary.withValues(alpha: 0.5)),
                                                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                            border: OutlineInputBorder(
                                                              borderRadius: BorderRadius.circular(4),
                                                              borderSide: const BorderSide(color: Colors.green),
                                                            ),
                                                            enabledBorder: OutlineInputBorder(
                                                              borderRadius: BorderRadius.circular(4),
                                                              borderSide: BorderSide(color: Colors.green.withValues(alpha: 0.5)),
                                                            ),
                                                            focusedBorder: OutlineInputBorder(
                                                              borderRadius: BorderRadius.circular(4),
                                                              borderSide: const BorderSide(color: Colors.green, width: 2),
                                                            ),
                                                            filled: true,
                                                            fillColor: _bgColor,
                                                          ),
                                                          onChanged: (value) => _updateDiscountedPrice(index, value, originalPrice),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    IconButton(
                                                      icon: const Icon(Icons.refresh, color: _textSecondary, size: 16),
                                                      tooltip: 'Reset to original price',
                                                      padding: EdgeInsets.zero,
                                                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                      onPressed: () => _resetItemPrice(index),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        );
                          },
                        ),
                ),
                // Payment section - DARK MODE
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _bgColor,
                    border: Border(top: BorderSide(color: _textSecondary.withValues(alpha: 0.2))),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // TOTAL row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('TOTAL', style: TextStyle(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                          Text(currencyFormat.format(_grandTotal), style: const TextStyle(color: _accentColor, fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // PAY button
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _cartItems.isEmpty || _isProcessing ? null : _processTransaction,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: _textSecondary.withValues(alpha: 0.3),
                            disabledForegroundColor: _textSecondary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: _isProcessing
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('PROCESS PAYMENT', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactBasketCard(Map<String, dynamic> basket, NumberFormat currencyFormat) {
    final isSelected = _selectedBasket?['firebaseKey'] == basket['firebaseKey'];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? _accentColor.withValues(alpha: 0.15) : _bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? _accentColor : _textSecondary.withValues(alpha: 0.2),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => _selectBasket(basket),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.shopping_basket, color: Colors.blue, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Basket #${basket['basketNumber']}',
                      style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      '${basket['userName']} • ${basket['itemCount']} items',
                      style: TextStyle(color: _textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Text(
                currencyFormat.format(basket['total'] ?? 0),
                style: const TextStyle(color: _accentColor, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductTile(Map<String, dynamic> item, NumberFormat currencyFormat) {
    final name = item['name'] as String? ?? 'Unnamed';
    final brand = item['brand'] as String? ?? '';
    final sku = item['sku'] as String? ?? item['serialNo'] as String? ?? '';
    final category = item['category'] as String? ?? '';
    final price = (item['sellingPrice'] as num?)?.toDouble() ?? 0;
    final quantity = item['quantity'] as int? ?? 0;
    final itemId = item['id'] as String? ?? '';
    final isExpanded = _expandedProductId == itemId;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isExpanded ? _accentColor.withValues(alpha: 0.4) : _textSecondary.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          // Collapsed header — always visible
          InkWell(
            onTap: () {
              setState(() {
                _expandedProductId = isExpanded ? null : itemId;
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _bgColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(_getCategoryIcon(item['category']), color: _accentColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (brand.isNotEmpty)
                          Text(brand, style: TextStyle(color: _textSecondary, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        currencyFormat.format(price),
                        style: const TextStyle(color: _accentColor, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: quantity < 10 ? Colors.orange.withValues(alpha: 0.2) : _bgColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Stk: $quantity',
                          style: TextStyle(
                            color: quantity < 10 ? Colors.orange : _textSecondary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: _textSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          // Expanded details
          if (isExpanded)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: _textSecondary.withValues(alpha: 0.15), height: 1),
                  const SizedBox(height: 8),
                  // Detail rows
                  if (sku.isNotEmpty)
                    _buildDetailRow('SKU / S.N.', sku),
                  if (category.isNotEmpty)
                    _buildDetailRow('Category', category),
                  _buildDetailRow('Name', name),
                  if (brand.isNotEmpty)
                    _buildDetailRow('Brand', brand),
                  const SizedBox(height: 8),
                  // Add to Cart button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: quantity > 0 ? () => _addToCart(item) : null,
                      icon: const Icon(Icons.add_shopping_cart, size: 18),
                      label: Text(quantity > 0 ? 'Add to Cart' : 'Out of Stock'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _textSecondary.withValues(alpha: 0.2),
                        disabledForegroundColor: _textSecondary,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: TextStyle(color: _textSecondary, fontSize: 11)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: _textPrimary, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopDetailChip(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: TextStyle(color: _textSecondary, fontSize: 11)),
        Flexible(
          child: Text(value, style: const TextStyle(color: _textPrimary, fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _buildCartItem(Map<String, dynamic> item, int index, NumberFormat currencyFormat) {
    final name = item['name'] as String? ?? 'Unnamed';
    final price = (item['sellingPrice'] as num?)?.toDouble() ??
                 (item['unitPrice'] as num?)?.toDouble() ?? 0;
    final cartQty = item['cartQuantity'] as int? ?? 1;
    final availableQty = item['quantity'] as int? ?? item['availableStock'] as int? ?? 0;
    final subtotal = price * cartQty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              InkWell(
                onTap: () => _removeFromCart(index),
                child: const Icon(Icons.close, color: Colors.red, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                currencyFormat.format(price),
                style: TextStyle(color: _textSecondary, fontSize: 11),
              ),
              const Spacer(),
              // Quantity controls
              Container(
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => _updateCartQuantity(index, cartQty - 1),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.remove, size: 14, color: _textSecondary),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '$cartQty',
                        style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    InkWell(
                      onTap: cartQty < availableQty ? () => _updateCartQuantity(index, cartQty + 1) : null,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.add,
                          size: 14,
                          color: cartQty < availableQty ? _accentColor : _textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              currencyFormat.format(subtotal),
              style: const TextStyle(color: _accentColor, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String? category) {
    switch (category) {
      case 'phones':
        return Icons.phone_android;
      case 'tv':
        return Icons.tv;
      case 'speaker':
        return Icons.speaker;
      case 'accessories':
        return Icons.headphones;
      default:
        return Icons.inventory_2;
    }
  }
}

class _KeypadButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isSpecial;
  final Color? color;
  final double height;
  final Widget child;

  const _KeypadButton({
    required this.onTap,
    required this.isSpecial,
    required this.height,
    required this.child,
    this.color,
  });

  @override
  State<_KeypadButton> createState() => _KeypadButtonState();
}

class _KeypadButtonState extends State<_KeypadButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 80),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalColor = widget.isSpecial
        ? widget.color!.withValues(alpha: 0.15)
        : const Color(0xFF2A2A2A);
    final pressedColor = widget.isSpecial
        ? widget.color!.withValues(alpha: 0.35)
        : const Color(0xFF3A3A3A);
    final normalBorder = widget.isSpecial
        ? widget.color!.withValues(alpha: 0.3)
        : Colors.white.withValues(alpha: 0.06);
    final pressedBorder = widget.isSpecial
        ? widget.color!.withValues(alpha: 0.6)
        : const Color(0xFFE67E22).withValues(alpha: 0.4);

    return GestureDetector(
      onTapDown: (_) {
        _controller.forward();
        setState(() => _isPressed = true);
      },
      onTapUp: (_) {
        _controller.reverse();
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () {
        _controller.reverse();
        setState(() => _isPressed = false);
      },
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) {
          return Transform.scale(
            scale: _scale.value,
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: widget.height,
          decoration: BoxDecoration(
            color: _isPressed ? pressedColor : normalColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isPressed ? pressedBorder : normalBorder,
              width: _isPressed ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Dialog that lets the cashier quickly reconnect to the saved printer
/// without leaving the POS page.
class _PrinterReconnectDialog extends StatefulWidget {
  final Color primaryColor;
  const _PrinterReconnectDialog({required this.primaryColor});

  @override
  State<_PrinterReconnectDialog> createState() => _PrinterReconnectDialogState();
}

class _PrinterReconnectDialogState extends State<_PrinterReconnectDialog> {
  bool _isConnecting = false;
  bool _reconnectFailed = false;

  Future<void> _tryReconnect() async {
    setState(() {
      _isConnecting = true;
      _reconnectFailed = false;
    });

    // First try auto-reconnect to saved printer
    await PrinterService.updateConnectionStatus();

    if (PrinterService.isConnected) {
      if (mounted) Navigator.pop(context, true);
      return;
    }

    // Not connected yet — wait a moment and retry once more
    await Future.delayed(const Duration(seconds: 2));
    await PrinterService.updateConnectionStatus();

    if (PrinterService.isConnected) {
      if (mounted) Navigator.pop(context, true);
      return;
    }

    if (mounted) {
      setState(() {
        _isConnecting = false;
        _reconnectFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2D1515),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            _isConnecting ? Icons.bluetooth_searching : Icons.print_disabled,
            color: _isConnecting ? Colors.blue : Colors.red,
            size: 28,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isConnecting ? 'Connecting...' : 'Printer Not Connected',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isConnecting) ...[
            const Text('Trying to reconnect to printer...', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            LinearProgressIndicator(color: widget.primaryColor),
          ] else if (_reconnectFailed) ...[
            const Text(
              'Failed to reconnect.',
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Please close the app, make sure the printer is turned on, then re-open the app and connect the printer in Settings.',
              style: TextStyle(color: Colors.white70),
            ),
          ] else ...[
            const Text(
              'Cannot process transaction without a receipt printer.',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isConnecting ? null : () => Navigator.pop(context, false),
          child: Text(
            _reconnectFailed ? 'OK' : 'Cancel',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        if (!_isConnecting && !_reconnectFailed)
          ElevatedButton.icon(
            onPressed: _tryReconnect,
            icon: const Icon(Icons.bluetooth_connected, size: 18),
            label: const Text('Reconnect'),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.primaryColor,
              foregroundColor: Colors.white,
            ),
          ),
        if (_reconnectFailed)
          ElevatedButton.icon(
            onPressed: _tryReconnect,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.primaryColor,
              foregroundColor: Colors.white,
            ),
          ),
      ],
    );
  }
}
