import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/inventory_service.dart';
import '../services/auth_service.dart';
import 'ocr_scanner_page.dart';
import '../services/beep_service.dart';
import '../utils/snackbar_utils.dart';

class BasketPage extends StatefulWidget {
  const BasketPage({super.key});

  @override
  State<BasketPage> createState() => _BasketPageState();
}

class _BasketPageState extends State<BasketPage> {
  List<Map<String, dynamic>> _userBaskets = []; // User's baskets from Firebase
  List<Map<String, dynamic>> _currentBasketItems = []; // Items in current basket being edited
  List<Map<String, dynamic>> _inventoryItems = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String _currentUserEmail = '';
  String _currentUserName = '';
  int? _editingBasketNumber; // null = creating new basket, number = editing existing
  final TextEditingController _customerNameController = TextEditingController();

  // Dark theme colors (matching inventory page)
  static const Color _bgColor = Color(0xFF1A0A0A);
  static const Color _cardColor = Color(0xFF252525);
  static const Color _accentColor = Color(0xFFE67E22);
  static const Color _accentDark = Color(0xFFD35400);
  static const Color _textPrimary = Colors.white;
  static const Color _textSecondary = Color(0xFFB0B0B0);

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final user = await AuthService.getCurrentUser();
    if (user != null) {
      setState(() {
        _currentUserEmail = user['email'] ?? '';
        _currentUserName = user['name'] ?? '';
      });
      _loadInventory();
      _loadUserBaskets();
    }
  }

  Future<void> _loadInventory() async {
    setState(() => _isLoading = true);
    try {
      final items = await InventoryService.getAllItems();
      setState(() {
        _inventoryItems = items.where((item) {
          final quantity = item['quantity'] as int? ?? 0;
          return quantity > 0; // Only show items in stock
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        SnackBarUtils.showError(context, 'Error loading inventory: $e');
      }
    }
  }

  Future<void> _loadUserBaskets() async {
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('pos_baskets')
          .orderByChild('userEmail')
          .equalTo(_currentUserEmail)
          .get();

      final baskets = <Map<String, dynamic>>[];
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          final basket = Map<String, dynamic>.from(value as Map);
          basket['firebaseKey'] = key;
          // Only show pending baskets (not processed)
          if (basket['status'] == 'pending') {
            baskets.add(basket);
          }
        });
      }

      // Sort by basket number
      baskets.sort((a, b) => ((a['basketNumber'] as num?)?.toInt() ?? 0).compareTo((b['basketNumber'] as num?)?.toInt() ?? 0));

      setState(() {
        _userBaskets = baskets;
      });
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showError(context, 'Error loading baskets: $e');
      }
    }
  }

  Future<int> _getNextBasketNumber() async {
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('pos_baskets')
          .orderByChild('userEmail')
          .equalTo(_currentUserEmail)
          .get();

      int maxNumber = 0;
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          final basket = value as Map;
          final num = basket['basketNumber'] as int? ?? 0;
          if (num > maxNumber) maxNumber = num;
        });
      }
      return maxNumber + 1;
    } catch (e) {
      return 1;
    }
  }

  List<Map<String, dynamic>> get _filteredInventory {
    if (_searchQuery.isEmpty) return _inventoryItems;
    final query = _searchQuery.toLowerCase();
    return _inventoryItems.where((item) {
      final name = (item['name'] as String? ?? '').toLowerCase();
      final serialNo = (item['sku'] as String? ?? item['serialNo'] as String? ?? '').toLowerCase();
      final brand = (item['brand'] as String? ?? '').toLowerCase();
      return name.contains(query) || serialNo.contains(query) || brand.contains(query);
    }).toList();
  }

  double get _totalAmount {
    double total = 0;
    for (var item in _currentBasketItems) {
      final price = (item['sellingPrice'] as num?)?.toDouble() ?? 0;
      final qty = item['basketQuantity'] as int? ?? 1;
      total += price * qty;
    }
    return total;
  }

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
    // Keep the raw value as-is so alphanumeric SKUs match
    return raw.trim().toLowerCase();
  }

  void _matchAndAddScannedItem(String scannedSerial) {
    final matchingItem = _inventoryItems.cast<Map<String, dynamic>>().firstWhere(
      (item) {
        final serialNo = (item['serialNo'] as String? ?? '').toLowerCase();
        final sku = (item['sku'] as String? ?? '').toLowerCase();
        final barcode = (item['barcode'] as String? ?? '').toLowerCase();
        final name = (item['name'] as String? ?? '').toLowerCase();
        return (serialNo.isNotEmpty && serialNo == scannedSerial) ||
               (sku.isNotEmpty && sku == scannedSerial) ||
               (barcode.isNotEmpty && barcode == scannedSerial) ||
               (name.isNotEmpty && name == scannedSerial);
      },
      orElse: () => <String, dynamic>{},
    );

    if (matchingItem.isNotEmpty) {
      BeepService.playBeep();
      _addToBasket(matchingItem);
    } else {
      // Fallback: try contains matching
      final partialMatch = _inventoryItems.cast<Map<String, dynamic>>().firstWhere(
        (item) {
          final sku = (item['sku'] as String? ?? '').toLowerCase();
          final serialNo = (item['serialNo'] as String? ?? '').toLowerCase();
          final barcode = (item['barcode'] as String? ?? '').toLowerCase();
          return (sku.isNotEmpty && sku.contains(scannedSerial)) ||
                 (serialNo.isNotEmpty && serialNo.contains(scannedSerial)) ||
                 (barcode.isNotEmpty && barcode.contains(scannedSerial));
        },
        orElse: () => <String, dynamic>{},
      );

      if (partialMatch.isNotEmpty) {
        BeepService.playBeep();
        _addToBasket(partialMatch);
      }
    }
  }

  void _addToBasket(Map<String, dynamic> item) {
    setState(() {
      final existingIndex = _currentBasketItems.indexWhere((b) => b['id'] == item['id']);
      if (existingIndex >= 0) {
        final currentQty = _currentBasketItems[existingIndex]['basketQuantity'] as int? ?? 1;
        final availableQty = item['quantity'] as int? ?? 0;
        if (currentQty < availableQty) {
          _currentBasketItems[existingIndex]['basketQuantity'] = currentQty + 1;
        } else {
          SnackBarUtils.showWarning(context, 'Maximum stock reached');
        }
      } else {
        final newItem = Map<String, dynamic>.from(item);
        newItem['basketQuantity'] = 1;
        _currentBasketItems.add(newItem);
      }
    });
  }

  void _removeFromBasket(int index) {
    setState(() {
      _currentBasketItems.removeAt(index);
    });
  }

  void _updateBasketQuantity(int index, int newQty) {
    if (newQty <= 0) {
      _removeFromBasket(index);
      return;
    }
    final availableQty = _currentBasketItems[index]['quantity'] as int? ?? 0;
    if (newQty > availableQty) {
      SnackBarUtils.showWarning(context, 'Only $availableQty available in stock');
      return;
    }
    setState(() {
      _currentBasketItems[index]['basketQuantity'] = newQty;
    });
  }

  void _clearCurrentBasket() {
    setState(() {
      _currentBasketItems.clear();
      _editingBasketNumber = null;
      _customerNameController.clear();
    });
  }

  void _startNewBasket() {
    setState(() {
      _currentBasketItems.clear();
      _editingBasketNumber = null;
      _customerNameController.clear();
    });
  }

  void _editBasket(Map<String, dynamic> basket) {
    final items = (basket['items'] as List?)?.map((item) {
      return Map<String, dynamic>.from(item as Map);
    }).toList() ?? [];

    setState(() {
      _currentBasketItems = items;
      _editingBasketNumber = basket['basketNumber'] as int?;
      _customerNameController.text = basket['customerName'] as String? ?? '';
    });
  }

  Future<void> _saveBasket() async {
    if (_currentBasketItems.isEmpty) {
      SnackBarUtils.showWarning(context, 'Basket is empty');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final items = _currentBasketItems.map((item) => {
        'itemId': item['id'],
        'name': item['name'],
        'brand': item['brand'],
        'category': item['category'],
        'serialNo': item['sku'] ?? item['serialNo'],
        'quantity': item['basketQuantity'],
        'unitPrice': item['sellingPrice'],
        'subtotal': (item['sellingPrice'] as num? ?? 0) * (item['basketQuantity'] as int? ?? 1),
        'availableStock': item['quantity'],
      }).toList();

      if (_editingBasketNumber != null) {
        // Update existing basket
        final existingBasket = _userBaskets.firstWhere(
          (b) => b['basketNumber'] == _editingBasketNumber,
          orElse: () => {},
        );

        if (existingBasket.isNotEmpty) {
          await FirebaseDatabase.instance
              .ref('pos_baskets/${existingBasket['firebaseKey']}')
              .update({
            'items': items,
            'total': _totalAmount,
            'itemCount': _currentBasketItems.length,
            'customerName': _customerNameController.text.trim(),
            'updatedAt': ServerValue.timestamp,
          });
        }
      } else {
        // Create new basket
        final basketNumber = await _getNextBasketNumber();
        final basketData = {
          'basketNumber': basketNumber,
          'userEmail': _currentUserEmail,
          'userName': _currentUserName,
          'customerName': _customerNameController.text.trim(),
          'items': items,
          'total': _totalAmount,
          'itemCount': _currentBasketItems.length,
          'status': 'pending',
          'createdAt': ServerValue.timestamp,
          'updatedAt': ServerValue.timestamp,
        };

        await FirebaseDatabase.instance.ref('pos_baskets').push().set(basketData);
      }

      _clearCurrentBasket();
      await _loadUserBaskets();

      if (mounted) {
        SnackBarUtils.showSuccess(
          context,
          _editingBasketNumber != null
              ? 'Basket updated successfully!'
              : 'Basket saved successfully!',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showError(context, 'Error saving basket: $e');
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteBasket(Map<String, dynamic> basket) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final screenWidth = MediaQuery.of(context).size.width;
        return AlertDialog(
          backgroundColor: _cardColor,
          title: const Text('Delete Basket?', style: TextStyle(color: _textPrimary)),
          content: SizedBox(
            width: screenWidth < 360 ? screenWidth * 0.9 : (screenWidth < 500 ? screenWidth * 0.85 : 400),
            child: Text(
              'Are you sure you want to delete Basket #${basket['basketNumber']}?',
              style: TextStyle(color: _textSecondary),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: _textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await FirebaseDatabase.instance
          .ref('pos_baskets/${basket['firebaseKey']}')
          .remove();
      await _loadUserBaskets();

      // Clear current basket if it was the one being edited
      if (_editingBasketNumber == basket['basketNumber']) {
        _clearCurrentBasket();
      }

      if (mounted) {
        SnackBarUtils.showSuccess(context, 'Basket deleted');
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showError(context, 'Error deleting basket: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isSmallScreen = screenWidth < 360;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        foregroundColor: _textPrimary,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isSmallScreen ? 5 : 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_accentColor, _accentDark],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.shopping_basket, color: Colors.white, size: isSmallScreen ? 16 : 20),
            ),
            SizedBox(width: isSmallScreen ? 8 : 12),
            Expanded(
              child: Text(
                _editingBasketNumber != null
                    ? '$_currentUserName - Basket #$_editingBasketNumber'
                    : '$_currentUserName - New Basket',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: isSmallScreen ? 16 : 20,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (_currentBasketItems.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    final screenWidth = MediaQuery.of(context).size.width;
                    return AlertDialog(
                      backgroundColor: _cardColor,
                      title: const Text('Clear Basket?', style: TextStyle(color: _textPrimary)),
                      content: SizedBox(
                        width: screenWidth < 360 ? screenWidth * 0.9 : (screenWidth < 500 ? screenWidth * 0.85 : 400),
                        child: Text(
                          'Remove all items from current basket?',
                          style: TextStyle(color: _textSecondary),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('Cancel', style: TextStyle(color: _textSecondary)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: () {
                            Navigator.pop(context);
                            _clearCurrentBasket();
                          },
                          child: const Text('Clear', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    );
                  },
                );
              },
              tooltip: 'Clear Basket',
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              _loadInventory();
              _loadUserBaskets();
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _accentColor))
          : Column(
              children: [
                // User's pending baskets bar
                if (_userBaskets.isNotEmpty)
                  _buildPendingBasketsBar(currencyFormat),
                // Main content
                Expanded(
                  child: isMobile
                      ? _buildMobileLayout(currencyFormat)
                      : _buildDesktopLayout(currencyFormat),
                ),
              ],
            ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.all(isSmallScreen ? 10 : 16),
        decoration: BoxDecoration(
          color: _cardColor,
          border: Border(top: BorderSide(color: _textSecondary.withValues(alpha: 0.2))),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Customer name field
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _customerNameController,
                  style: const TextStyle(color: _textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Customer name (optional)',
                    hintStyle: TextStyle(color: _textSecondary.withValues(alpha: 0.5)),
                    prefixIcon: Icon(Icons.person, color: _textSecondary, size: 20),
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
                    fillColor: _bgColor,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                ),
              ),
              Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total (${_currentBasketItems.length} items)',
                      style: TextStyle(color: _textSecondary, fontSize: 12),
                    ),
                    Text(
                      currencyFormat.format(_totalAmount),
                      style: TextStyle(
                        color: _accentColor,
                        fontSize: screenWidth < 360 ? 16 : (isSmallScreen ? 18 : 24),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (_editingBasketNumber != null) ...[
                OutlinedButton.icon(
                  onPressed: _startNewBasket,
                  icon: const Icon(Icons.add),
                  label: const Text('New'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _textSecondary,
                    side: BorderSide(color: _textSecondary.withValues(alpha: 0.5)),
                    padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 10 : 16, vertical: isSmallScreen ? 8 : 12),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              ElevatedButton.icon(
                onPressed: _isSaving || _currentBasketItems.isEmpty ? null : _saveBasket,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: Text(_editingBasketNumber != null ? 'Update' : (screenWidth < 340 ? 'Save' : (isSmallScreen ? 'Save' : 'Save Basket'))),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _currentBasketItems.isEmpty ? _cardColor : _accentColor,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 14 : 24, vertical: isSmallScreen ? 10 : 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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

  Widget _buildPendingBasketsBar(NumberFormat currencyFormat) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _cardColor,
        border: Border(bottom: BorderSide(color: _textSecondary.withValues(alpha: 0.2))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pending_actions, color: _accentColor, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'My Pending Baskets (${_userBaskets.length})',
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: _startNewBasket,
                icon: const Icon(Icons.add, size: 16),
                label: Text(MediaQuery.of(context).size.width < 360 ? 'New' : 'New Basket'),
                style: TextButton.styleFrom(
                  foregroundColor: _accentColor,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _userBaskets.length,
              itemBuilder: (context, index) {
                final basket = _userBaskets[index];
                final isEditing = _editingBasketNumber == basket['basketNumber'];
                return GestureDetector(
                  onTap: () => _editBasket(basket),
                  child: Container(
                    width: MediaQuery.of(context).size.width < 360 ? 120 : 140,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isEditing ? _accentColor.withValues(alpha: 0.2) : _bgColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isEditing ? _accentColor : _textSecondary.withValues(alpha: 0.3),
                        width: isEditing ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Basket #${basket['basketNumber']}',
                              style: TextStyle(
                                color: isEditing ? _accentColor : _textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _deleteBasket(basket),
                              child: const Icon(Icons.close, color: Colors.red, size: 16),
                            ),
                          ],
                        ),
                        Text(
                          (basket['customerName'] as String? ?? '').isNotEmpty
                              ? '${basket['customerName']}'
                              : '${basket['itemCount']} items',
                          style: TextStyle(color: _textSecondary, fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          currencyFormat.format(basket['total'] ?? 0),
                          style: TextStyle(
                            color: isEditing ? _accentColor : _textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
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
    );
  }

  Widget _buildMobileLayout(NumberFormat currencyFormat) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: _cardColor,
            child: TabBar(
              indicatorColor: _accentColor,
              labelColor: _accentColor,
              unselectedLabelColor: _textSecondary,
              tabs: [
                Tab(
                  icon: const Icon(Icons.inventory_2),
                  text: MediaQuery.of(context).size.width < 360
                      ? 'Items (${_filteredInventory.length})'
                      : 'Products (${_filteredInventory.length})',
                ),
                Tab(
                  icon: Badge(
                    label: Text('${_currentBasketItems.length}'),
                    isLabelVisible: _currentBasketItems.isNotEmpty,
                    child: const Icon(Icons.shopping_basket),
                  ),
                  text: MediaQuery.of(context).size.width < 360 ? 'Basket' : 'Current Basket',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildProductsList(currencyFormat),
                _buildBasketList(currencyFormat),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(NumberFormat currencyFormat) {
    return Row(
      children: [
        // Products section
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.all(MediaQuery.of(context).size.width < 360 ? 12 : 16),
                child: Text(
                  'Products',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: MediaQuery.of(context).size.width < 360 ? 16 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(child: _buildProductsList(currencyFormat)),
            ],
          ),
        ),
        // Divider
        Container(
          width: 1,
          color: _textSecondary.withValues(alpha: 0.2),
        ),
        // Basket section
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.all(MediaQuery.of(context).size.width < 360 ? 12 : 16),
                child: Row(
                  children: [
                    Icon(Icons.shopping_basket, color: _accentColor, size: MediaQuery.of(context).size.width < 360 ? 20 : 24),
                    SizedBox(width: MediaQuery.of(context).size.width < 360 ? 6 : 8),
                    Expanded(
                      child: Text(
                        'Current Basket (${_currentBasketItems.length})',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: MediaQuery.of(context).size.width < 360 ? 16 : 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildBasketList(currencyFormat)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductsList(NumberFormat currencyFormat) {
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
                  IconButton(
                    icon: const Icon(Icons.document_scanner, color: _accentColor),
                    onPressed: _openOcrScanner,
                    tooltip: 'Scan Product (OCR)',
                  ),
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        // Products list
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _loadInventory();
              await _loadUserBaskets();
            },
            color: _accentColor,
            child: _filteredInventory.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 64, color: _textSecondary.withValues(alpha: 0.5)),
                              const SizedBox(height: 16),
                              Text(
                                'No products found',
                                style: TextStyle(color: _textSecondary.withValues(alpha: 0.7)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _filteredInventory.length,
                    itemBuilder: (context, index) {
                      final item = _filteredInventory[index];
                      return _buildProductCard(item, currencyFormat);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductCard(Map<String, dynamic> item, NumberFormat currencyFormat) {
    final name = item['name'] as String? ?? 'Unnamed';
    final brand = item['brand'] as String? ?? '';
    final price = (item['sellingPrice'] as num?)?.toDouble() ?? 0;
    final quantity = item['quantity'] as int? ?? 0;
    final basketQty = _currentBasketItems
        .where((b) => b['id'] == item['id'])
        .map((b) => b['basketQuantity'] as int? ?? 0)
        .fold(0, (a, b) => a + b);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _textSecondary.withValues(alpha: 0.1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        title: Text(
          name,
          style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (brand.isNotEmpty)
              Text(brand, style: TextStyle(color: _textSecondary, fontSize: 12)),
            const SizedBox(height: 4),
            Row(
              children: [
                Flexible(
                  child: Text(
                    currencyFormat.format(price),
                    style: const TextStyle(color: _accentColor, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Stock: $quantity',
                  style: TextStyle(
                    color: quantity < 10 ? Colors.orange : _textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (basketQty > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _accentColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'x$basketQty',
                  style: const TextStyle(color: _accentColor, fontWeight: FontWeight.bold),
                ),
              ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_shopping_cart, color: _accentColor),
              onPressed: () => _addToBasket(item),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasketList(NumberFormat currencyFormat) {
    if (_currentBasketItems.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          await _loadInventory();
          await _loadUserBaskets();
        },
        color: _accentColor,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shopping_basket_outlined, size: 64, color: _textSecondary.withValues(alpha: 0.5)),
                    const SizedBox(height: 16),
                    Text(
                      'Basket is empty',
                      style: TextStyle(color: _textSecondary.withValues(alpha: 0.7)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add products to get started',
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
      onRefresh: () async {
        await _loadInventory();
        await _loadUserBaskets();
      },
      color: _accentColor,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _currentBasketItems.length,
        itemBuilder: (context, index) {
          final item = _currentBasketItems[index];
          return _buildBasketItemCard(item, index, currencyFormat);
        },
      ),
    );
  }

  Widget _buildBasketItemCard(Map<String, dynamic> item, int index, NumberFormat currencyFormat) {
    final name = item['name'] as String? ?? 'Unnamed';
    final price = (item['sellingPrice'] as num?)?.toDouble() ?? 0;
    final basketQty = item['basketQuantity'] as int? ?? 1;
    final availableQty = item['quantity'] as int? ?? item['availableStock'] as int? ?? 0;
    final subtotal = price * basketQty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _textSecondary.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red, size: 20),
                  onPressed: () => _removeFromBasket(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  currencyFormat.format(price),
                  style: TextStyle(color: _textSecondary, fontSize: 12),
                ),
                const Spacer(),
                // Quantity controls
                Container(
                  decoration: BoxDecoration(
                    color: _bgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove, size: 16),
                        color: _textSecondary,
                        onPressed: () => _updateBasketQuantity(index, basketQty - 1),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).size.width < 360 ? 8 : 12),
                        child: Text(
                          '$basketQty',
                          style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 16),
                        color: basketQty < availableQty ? _accentColor : _textSecondary,
                        onPressed: basketQty < availableQty
                            ? () => _updateBasketQuantity(index, basketQty + 1)
                            : null,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Subtotal:',
                  style: TextStyle(color: _textSecondary, fontSize: 12),
                ),
                Text(
                  currencyFormat.format(subtotal),
                  style: const TextStyle(color: _accentColor, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customerNameController.dispose();
    super.dispose();
  }
}
