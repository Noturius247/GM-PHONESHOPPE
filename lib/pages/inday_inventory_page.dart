import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/inventory_service.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';

class IndayInventoryPage extends StatefulWidget {
  const IndayInventoryPage({super.key});

  @override
  State<IndayInventoryPage> createState() => _IndayInventoryPageState();
}

class _IndayInventoryPageState extends State<IndayInventoryPage> {
  List<Map<String, dynamic>> _allItems = [];
  List<Map<String, dynamic>> _filteredItems = [];
  bool _isLoading = true;
  String _selectedCategory = 'all';
  String _selectedStockFilter = 'all'; // all, low, empty
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String _currentUserEmail = '';
  String _currentUserName = '';
  Timer? _debounceTimer;
  final Set<String> _expandedItems = {}; // Track which items are expanded

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
    _loadUserInfo();
    _loadInventory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    final user = await AuthService.getCurrentUser();
    if (user != null) {
      setState(() {
        _currentUserEmail = user['email'] ?? '';
        _currentUserName = user['name'] ?? '';
      });
    }
  }

  Future<void> _loadInventory() async {
    setState(() => _isLoading = true);
    try {
      final items = await InventoryService.getAllItems();
      setState(() {
        _allItems = items;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        SnackBarUtils.showError(context, 'Failed to load inventory: $e');
      }
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> filtered = List.from(_allItems);

    // Show items that have been transferred to Inday (including 0 qty as Out of Stock)
    filtered = filtered.where((item) {
      return item.containsKey('indayQuantity');
    }).toList();

    // Filter by category
    if (_selectedCategory != 'all') {
      filtered = filtered.where((item) => item['category'] == _selectedCategory).toList();
    }

    // Filter by stock status based on indayQuantity
    if (_selectedStockFilter == 'low') {
      filtered = filtered.where((item) {
        final indayQty = item['indayQuantity'] as int? ?? 0;
        return _getIndayStockStatus(indayQty) == 'Low Stock';
      }).toList();
    } else if (_selectedStockFilter == 'empty') {
      filtered = filtered.where((item) {
        final indayQty = item['indayQuantity'] as int? ?? 0;
        return _getIndayStockStatus(indayQty) == 'Out of Stock';
      }).toList();
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((item) {
        final name = (item['name'] as String? ?? '').toLowerCase();
        final sku = (item['sku'] as String? ?? item['serialNo'] as String? ?? '').toLowerCase();
        final brand = (item['brand'] as String? ?? '').toLowerCase();
        return name.contains(query) || sku.contains(query) || brand.contains(query);
      }).toList();
    }

    // Sort by name
    filtered.sort((a, b) {
      final nameA = (a['name'] as String? ?? '').toLowerCase();
      final nameB = (b['name'] as String? ?? '').toLowerCase();
      return nameA.compareTo(nameB);
    });

    setState(() {
      _filteredItems = filtered;
    });
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = query;
        _applyFilters();
      });
    });
  }

  Future<void> _showStockDialog(Map<String, dynamic> item, String action) async {
    final quantityController = TextEditingController();
    final reasonController = TextEditingController();
    final mainQty = item['quantity'] as int? ?? 0;
    final indayQty = item['indayQuantity'] as int? ?? 0;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: Text(
          action == 'add' ? 'Transfer from Main' : 'Return to Main',
          style: const TextStyle(color: _textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item['name'] as String? ?? 'Unknown',
              style: const TextStyle(color: _accentColor, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Main Stock:', style: TextStyle(color: _textSecondary, fontSize: 12)),
                      Text('$mainQty', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Inday Stock:', style: TextStyle(color: _textSecondary, fontSize: 12)),
                      Text('$indayQty', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: quantityController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: _textPrimary),
              decoration: InputDecoration(
                labelText: action == 'set' ? 'New Quantity' : 'Quantity',
                labelStyle: const TextStyle(color: _textSecondary),
                filled: true,
                fillColor: _bgColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              style: const TextStyle(color: _textPrimary),
              decoration: InputDecoration(
                labelText: 'Reason',
                labelStyle: const TextStyle(color: _textSecondary),
                filled: true,
                fillColor: _bgColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final qtyText = quantityController.text.trim();
              if (qtyText.isEmpty) {
                SnackBarUtils.showError(context, 'Please enter quantity');
                return;
              }

              final qty = int.tryParse(qtyText);
              if (qty == null || qty <= 0) {
                SnackBarUtils.showError(context, 'Invalid quantity');
                return;
              }

              Navigator.pop(context);

              final category = item['category'] as String?;
              final itemId = item['id'] as String?;
              final reason = reasonController.text.trim().isEmpty
                  ? 'Stock adjustment'
                  : reasonController.text.trim();

              if (category == null || itemId == null) {
                SnackBarUtils.showError(context, 'Invalid item data');
                return;
              }

              bool success = false;
              try {
                if (action == 'add') {
                  // Transfer from main inventory to Inday
                  success = await InventoryService.transferToInday(
                    category: category,
                    itemId: itemId,
                    quantity: qty,
                    reason: reason,
                    transferredByEmail: _currentUserEmail,
                    transferredByName: _currentUserName,
                  );
                } else if (action == 'remove') {
                  // Return from Inday to main inventory
                  success = await InventoryService.returnFromInday(
                    category: category,
                    itemId: itemId,
                    quantity: qty,
                    reason: reason,
                    returnedByEmail: _currentUserEmail,
                    returnedByName: _currentUserName,
                  );
                }

                if (success && mounted) {
                  SnackBarUtils.showSuccess(
                    context,
                    action == 'add' ? 'Transferred to Inday successfully' : 'Returned to Main successfully',
                  );
                  _loadInventory();
                } else if (mounted) {
                  SnackBarUtils.showError(
                    context,
                    action == 'add'
                        ? 'Transfer failed - check main stock'
                        : 'Return failed - check Inday stock',
                  );
                }
              } catch (e) {
                if (mounted) {
                  SnackBarUtils.showError(context, 'Error: $e');
                }
              }
            },
            child: Text(action == 'add' ? 'Transfer' : 'Return'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddItemFromInventoryDialog() async {
    // Load all inventory items (not just those with indayQuantity)
    List<Map<String, dynamic>> allInventoryItems = [];

    try {
      final snapshot = await FirebaseDatabase.instance.ref('inventory').get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        data.forEach((category, categoryData) {
          if (categoryData is Map) {
            categoryData.forEach((itemId, itemData) {
              if (itemData is Map) {
                final item = Map<String, dynamic>.from(itemData);
                item['id'] = itemId;
                item['category'] = category;
                final mainQty = item['quantity'] as int? ?? 0;
                // Only show items that have stock in main inventory
                if (mainQty > 0) {
                  allInventoryItems.add(item);
                }
              }
            });
          }
        });
      }

      // Sort by name
      allInventoryItems.sort((a, b) =>
        (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));

      if (!mounted) return;

      if (allInventoryItems.isEmpty) {
        SnackBarUtils.showError(context, 'No items available in main inventory');
        return;
      }

      // Show selection dialog
      Map<String, dynamic>? selectedItem;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _cardColor,
          title: const Text('Select Item to Transfer', style: TextStyle(color: _textPrimary)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: allInventoryItems.length,
              itemBuilder: (context, index) {
                final item = allInventoryItems[index];
                final name = item['name'] as String? ?? 'Unknown';
                final mainQty = item['quantity'] as int? ?? 0;
                final indayQty = item['indayQuantity'] as int? ?? 0;
                final category = item['category'] as String? ?? '';

                return ListTile(
                  title: Text(name, style: const TextStyle(color: _textPrimary)),
                  subtitle: Text(
                    '$category • Main: $mainQty | Inday: $indayQty',
                    style: TextStyle(color: _textSecondary.withValues(alpha: 0.7), fontSize: 12),
                  ),
                  onTap: () {
                    selectedItem = item;
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      // If an item was selected, show the transfer dialog
      if (selectedItem != null) {
        _showStockDialog(selectedItem!, 'add');
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showError(context, 'Error loading inventory: $e');
      }
    }
  }

  Future<void> _confirmDeleteIndayItem(Map<String, dynamic> item) async {
    final name = item['name'] as String? ?? 'Unknown';
    final indayQty = item['indayQuantity'] as int? ?? 0;
    final category = item['category'] as String?;
    final itemId = item['id'] as String?;

    if (category == null || itemId == null) {
      SnackBarUtils.showError(context, 'Invalid item data');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: const Text('Remove from Inday', style: TextStyle(color: _textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(color: _accentColor, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (indayQty > 0)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This item still has $indayQty Inday stock. Removing will return them to main inventory.',
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Remove this item from Inday tracking?',
              style: TextStyle(color: _textSecondary.withValues(alpha: 0.9), fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: _textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final ref = FirebaseDatabase.instance.ref('inventory/$category/$itemId');

      if (indayQty > 0) {
        // Return remaining Inday stock to main inventory before removing
        final snapshot = await ref.get();
        if (snapshot.exists) {
          final data = Map<String, dynamic>.from(snapshot.value as Map);
          final mainQty = data['quantity'] as int? ?? 0;
          await ref.update({
            'quantity': mainQty + indayQty,
            'indayQuantity': null,
            'lastIndayUpdatedBy': null,
          });
        }
      } else {
        // Just remove Inday tracking fields
        await ref.update({
          'indayQuantity': null,
          'lastIndayUpdatedBy': null,
        });
      }

      if (mounted) {
        SnackBarUtils.showSuccess(context, '$name removed from Inday inventory');
        _loadInventory();
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showError(context, 'Failed to remove: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ['all', 'Phone', 'TV', 'Accessories', 'Other'];
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        foregroundColor: _textPrimary,
        elevation: 0,
        toolbarHeight: 48,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_accentColor, _accentDark]),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.inventory_2, color: Colors.white, size: 14),
            ),
            const SizedBox(width: 6),
            Text(
              'Inday Inventory',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: screenWidth < 360 ? 12 : 14,
                color: _textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box, size: 18, color: _accentColor),
            onPressed: _showAddItemFromInventoryDialog,
            tooltip: 'Add from Inventory',
            padding: const EdgeInsets.all(6),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18, color: _textPrimary),
            onPressed: _loadInventory,
            tooltip: 'Refresh',
            padding: const EdgeInsets.all(6),
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats section
          _buildStatsSection(isMobile),
          // Search and filters
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Column(
              children: [
                // Search bar
                SizedBox(
                  height: screenWidth < 360 ? 36 : 40,
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(color: _textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: TextStyle(color: _textSecondary.withValues(alpha: 0.5), fontSize: 13),
                      prefixIcon: const Icon(Icons.search, color: _accentColor, size: 18),
                      filled: true,
                      fillColor: _cardColor,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Category and Stock filter dropdowns
                Row(
                  children: [
                    // Category dropdown
                    Expanded(
                      child: Container(
                        height: screenWidth < 360 ? 36 : 40,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: _cardColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _accentColor.withValues(alpha: 0.3)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedCategory,
                            isExpanded: true,
                            dropdownColor: _cardColor,
                            icon: const Icon(Icons.arrow_drop_down, color: _accentColor, size: 20),
                            style: const TextStyle(color: _textPrimary, fontSize: 13),
                            items: categories.map((category) {
                              return DropdownMenuItem(
                                value: category,
                                child: Text(
                                  category == 'all' ? 'All Categories' : category,
                                  style: const TextStyle(color: _textPrimary, fontSize: 13),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedCategory = value;
                                  _applyFilters();
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Stock filter dropdown
                    Expanded(
                      child: Container(
                        height: screenWidth < 360 ? 36 : 40,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: _cardColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _accentColor.withValues(alpha: 0.3)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedStockFilter,
                            isExpanded: true,
                            dropdownColor: _cardColor,
                            icon: const Icon(Icons.arrow_drop_down, color: _accentColor, size: 20),
                            style: const TextStyle(color: _textPrimary, fontSize: 13),
                            items: const [
                              DropdownMenuItem(
                                value: 'all',
                                child: Text('All Stock', style: TextStyle(color: _textPrimary, fontSize: 13)),
                              ),
                              DropdownMenuItem(
                                value: 'low',
                                child: Text('Low Stock', style: TextStyle(color: _textPrimary, fontSize: 13)),
                              ),
                              DropdownMenuItem(
                                value: 'empty',
                                child: Text('Out of Stock', style: TextStyle(color: _textPrimary, fontSize: 13)),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedStockFilter = value;
                                  _applyFilters();
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Items list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _accentColor))
                : RefreshIndicator(
                    color: _accentColor,
                    backgroundColor: _cardColor,
                    onRefresh: _loadInventory,
                    child: _filteredItems.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: MediaQuery.of(context).size.height * 0.4,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.inventory_2_outlined, size: 64, color: _textSecondary.withValues(alpha: 0.5)),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No items found',
                                        style: TextStyle(color: _textSecondary.withValues(alpha: 0.7), fontSize: 16),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Pull down to refresh',
                                        style: TextStyle(color: _textSecondary.withValues(alpha: 0.4), fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredItems.length,
                            itemBuilder: (context, index) {
                              final item = _filteredItems[index];
                              return _buildItemCard(item, isMobile, screenWidth);
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item, bool isMobile, double screenWidth) {
    final name = item['name'] as String? ?? 'Unknown';
    final sku = item['sku'] as String? ?? item['serialNo'] as String? ?? 'N/A';
    final quantity = item['quantity'] as int? ?? 0;
    final indayQuantity = item['indayQuantity'] as int? ?? 0;
    final brand = item['brand'] as String? ?? '';
    final sellingPrice = (item['sellingPrice'] as num?)?.toDouble() ?? 0;
    final indayStatus = _getIndayStockStatus(indayQuantity);
    final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final itemId = item['id'] as String? ?? '';
    final isExpanded = _expandedItems.contains(itemId);

    // Get last Inday update info - safe casting
    Map<String, dynamic>? lastIndayUpdate;
    try {
      final updateData = item['lastIndayUpdatedBy'];
      if (updateData != null && updateData is Map) {
        lastIndayUpdate = Map<String, dynamic>.from(updateData);
      }
    } catch (e) {
      lastIndayUpdate = null;
    }
    final lastUpdateName = lastIndayUpdate?['name'] as String?;
    final lastUpdateTimestamp = lastIndayUpdate?['timestamp'] as int?;
    final lastUpdateAction = lastIndayUpdate?['action'] as String?;

    Color statusColor;
    switch (indayStatus) {
      case 'In Stock':
        statusColor = Colors.green;
        break;
      case 'Low Stock':
        statusColor = Colors.orange;
        break;
      case 'Out of Stock':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _textSecondary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Item header - Always visible
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedItems.remove(itemId);
                } else {
                  _expandedItems.add(itemId);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: screenWidth < 360 ? 12 : 14,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (brand.isNotEmpty)
                          Text(
                            brand,
                            style: TextStyle(color: _textSecondary.withValues(alpha: 0.7), fontSize: 11),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          'Inday: $indayQuantity',
                          style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor),
                    ),
                    child: Text(
                      indayStatus,
                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: _textSecondary,
                  ),
                ],
              ),
            ),
          ),
          // Expandable details
          if (isExpanded) ...[
            const Divider(height: 1, color: _textSecondary),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoChip(Icons.qr_code, 'SKU: $sku'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildInfoChip(Icons.inventory_2, 'Main: $quantity'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildInfoChip(Icons.monetization_on, currencyFormat.format(sellingPrice)),
                  // Show last Inday update info if available
                  if (lastUpdateName != null && lastUpdateTimestamp != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A085).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF16A085).withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            lastUpdateAction == 'transfer_to_inday' ? Icons.arrow_forward : Icons.arrow_back,
                            size: 14,
                            color: const Color(0xFF16A085),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Last ${lastUpdateAction == 'transfer_to_inday' ? 'transfer' : 'return'} by $lastUpdateName • ${_formatTimestamp(lastUpdateTimestamp)}',
                              style: TextStyle(
                                color: _textSecondary.withValues(alpha: 0.9),
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Action buttons
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: _textSecondary.withValues(alpha: 0.2))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _showStockDialog(item, 'add'),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Transfer', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 36, color: _textSecondary.withValues(alpha: 0.2)),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _showStockDialog(item, 'remove'),
                      icon: const Icon(Icons.remove, size: 16),
                      label: const Text('Return', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 36, color: _textSecondary.withValues(alpha: 0.2)),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _confirmDeleteIndayItem(item),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Remove', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _textSecondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(color: _textSecondary, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _getIndayStockStatus(int indayQty) {
    if (indayQty <= 0) return 'Out of Stock';
    if (indayQty <= 5) return 'Low Stock';
    return 'In Stock';
  }

  Map<String, int> _calculateStats() {
    int totalItems = 0;
    int inStockItems = 0;
    int lowStockItems = 0;
    int outOfStockItems = 0;

    for (var item in _allItems) {
      final indayQty = item['indayQuantity'] as int? ?? 0;
      // Only count items that have been transferred to Inday at some point
      if (indayQty > 0 || item.containsKey('indayQuantity')) {
        totalItems++;
        final status = _getIndayStockStatus(indayQty);
        if (status == 'In Stock') {
          inStockItems++;
        } else if (status == 'Low Stock') {
          lowStockItems++;
        } else if (status == 'Out of Stock') {
          outOfStockItems++;
        }
      }
    }

    return {
      'total': totalItems,
      'inStock': inStockItems,
      'lowStock': lowStockItems,
      'outOfStock': outOfStockItems,
    };
  }

  Widget _buildStatsSection(bool isMobile) {
    final stats = _calculateStats();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Stats',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          isMobile
              ? Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            'Total Items',
                            stats['total']!,
                            Icons.inventory_2,
                            const Color(0xFF16A085),
                            null,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _buildStatCard(
                            'In Stock',
                            stats['inStock']!,
                            Icons.check_circle,
                            Colors.green,
                            null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            'Low Stock',
                            stats['lowStock']!,
                            Icons.warning,
                            Colors.orange,
                            () {
                              setState(() {
                                _selectedStockFilter = 'low';
                                _applyFilters();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _buildStatCard(
                            'Out of Stock',
                            stats['outOfStock']!,
                            Icons.error,
                            Colors.red,
                            () {
                              setState(() {
                                _selectedStockFilter = 'empty';
                                _applyFilters();
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Total Items',
                        stats['total']!,
                        Icons.inventory_2,
                        const Color(0xFF16A085),
                        null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildStatCard(
                        'In Stock',
                        stats['inStock']!,
                        Icons.check_circle,
                        Colors.green,
                        null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildStatCard(
                        'Low Stock',
                        stats['lowStock']!,
                        Icons.warning,
                        Colors.orange,
                        () {
                          setState(() {
                            _selectedStockFilter = 'low';
                            _applyFilters();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildStatCard(
                        'Out of Stock',
                        stats['outOfStock']!,
                        Icons.error,
                        Colors.red,
                        () {
                          setState(() {
                            _selectedStockFilter = 'empty';
                            _applyFilters();
                          });
                        },
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, int value, IconData icon, Color color, VoidCallback? onTap) {
    // Reduced sizes to match reports page style
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 14),
                if (onTap != null)
                  Icon(Icons.touch_app, color: _textSecondary.withValues(alpha: 0.5), size: 8),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              value.toString(),
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                color: _textSecondary.withValues(alpha: 0.8),
                fontSize: 8,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
