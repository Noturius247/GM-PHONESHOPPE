import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/inventory_service.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import 'ocr_scanner_page.dart';
import 'basket_page.dart';
import 'pos_page.dart';
import 'pos_reports_page.dart';
import 'label_printing_page.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _allItems = [];
  List<Map<String, dynamic>> _filteredItems = [];
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  String _selectedStockStatus = 'all';
  String _selectedCategory = 'all'; // Filter by category (Phone, TV, etc.)
  String _selectedBrand = 'all'; // Filter by brand (Samsung, Apple, etc.)
  List<String> _availableBrands = []; // Brands from database for filtering
  String _searchQuery = '';
  String _sortBy = 'name';
  bool _sortAscending = true;
  final TextEditingController _searchController = TextEditingController();
  String _currentUserEmail = '';
  String _currentUserName = '';
  String _currentUserRole = '';
  Timer? _debounceTimer;
  int _currentPage = 0;
  int _itemsPerPage = 10;

  // Collapse/expand state
  final Set<String> _expandedItems = {};
  bool _allExpanded = true; // Start with all items expanded

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

  Future<void> _loadUserInfo() async {
    final user = await AuthService.getCurrentUser();
    if (user != null) {
      setState(() {
        _currentUserEmail = user['email'] ?? '';
        _currentUserName = user['name'] ?? '';
        _currentUserRole = user['role'] ?? '';
      });
    }
  }

  bool get _isAdminOrSuperAdmin => _currentUserRole == 'admin' || _currentUserRole == 'superadmin';

  Future<void> _navigateToPOS() async {
    // Ensure user role is loaded before routing
    if (_currentUserRole.isEmpty) {
      await _loadUserInfo();
    }
    if (!mounted) return;
    Widget page;
    if (_currentUserRole == 'admin' || _currentUserRole == 'superadmin') {
      page = const POSReportsPage();
    } else if (_currentUserRole == 'pos') {
      page = const POSPage();
    } else {
      page = const BasketPage();
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
  }

  Future<void> _loadInventory() async {
    setState(() => _isLoading = true);
    try {
      final items = await InventoryService.getAllItems();
      final stats = await InventoryService.getInventoryStats();

      // Extract unique brands from items
      final brands = <String>{};
      for (var item in items) {
        final brand = item['brand'] as String?;
        if (brand != null && brand.isNotEmpty) {
          brands.add(brand);
        }
      }

      setState(() {
        _allItems = items;
        _stats = stats;
        _availableBrands = brands.toList()..sort();
        // Reset brand filter if selected brand no longer exists
        if (_selectedBrand != 'all' && !_availableBrands.contains(_selectedBrand)) {
          _selectedBrand = 'all';
        }
        _filterAndSortItems();
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

  void _filterAndSortItems() {
    // Optimize: use single where clause instead of multiple intermediate lists
    final query = _searchQuery.toLowerCase();

    final filtered = _allItems.where((item) {
      // Filter by category
      if (_selectedCategory != 'all' && item['category'] != _selectedCategory) {
        return false;
      }

      // Filter by brand
      if (_selectedBrand != 'all' && item['brand'] != _selectedBrand) {
        return false;
      }

      // Filter by stock status
      if (_selectedStockStatus != 'all') {
        final quantity = item['quantity'] as int? ?? 0;
        switch (_selectedStockStatus) {
          case 'in_stock':
            if (quantity < 10) return false;
            break;
          case 'low_stock':
            if (quantity == 0 || quantity >= 10) return false;
            break;
          case 'out_of_stock':
            if (quantity != 0) return false;
            break;
        }
      }

      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        final name = (item['name'] as String? ?? '').toLowerCase();
        final serialNo = (item['sku'] as String? ?? item['serialNo'] as String? ?? '').toLowerCase();
        final modelNumber = (item['modelNumber'] as String? ?? '').toLowerCase();
        if (!name.contains(query) && !serialNo.contains(query) && !modelNumber.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();

    // Sort items
    filtered.sort((a, b) {
      dynamic aValue, bValue;
      switch (_sortBy) {
        case 'name':
          aValue = a['name'] ?? '';
          bValue = b['name'] ?? '';
          break;
        case 'quantity':
          aValue = a['quantity'] ?? 0;
          bValue = b['quantity'] ?? 0;
          break;
        case 'price':
          aValue = a['sellingPrice'] ?? 0;
          bValue = b['sellingPrice'] ?? 0;
          break;
        case 'status':
          aValue = a['status'] ?? '';
          bValue = b['status'] ?? '';
          break;
        default:
          aValue = a['name'] ?? '';
          bValue = b['name'] ?? '';
      }
      int comparison = Comparable.compare(aValue, bValue);
      return _sortAscending ? comparison : -comparison;
    });

    _filteredItems = filtered;
    _currentPage = 0; // Reset to first page when filters change
  }

  List<Map<String, dynamic>> get _paginatedItems {
    final start = _currentPage * _itemsPerPage;
    final end = (start + _itemsPerPage).clamp(0, _filteredItems.length);
    if (start >= _filteredItems.length) return [];
    return _filteredItems.sublist(start, end);
  }

  int get _totalPages => (_filteredItems.length / _itemsPerPage).ceil();

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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    // In landscape, use height to determine if mobile (height < 600 means phone in landscape)
    final isMobile = isLandscape ? screenHeight < 600 : screenWidth < 600;
    final isCompact = isMobile && isLandscape;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        foregroundColor: _textPrimary,
        elevation: 0,
        toolbarHeight: isCompact ? 44 : kToolbarHeight,
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isCompact ? 6 : 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_accentColor, _accentDark],
                ),
                borderRadius: BorderRadius.circular(isCompact ? 8 : 10),
              ),
              child: Icon(Icons.inventory_2, color: Colors.white, size: isCompact ? 16 : 20),
            ),
            SizedBox(width: isCompact ? 8 : 12),
            Text(
              'Inventory',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: isCompact ? 16 : 20,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          // Expand/Collapse All Button
          IconButton(
            icon: Icon(
              _allExpanded ? Icons.unfold_less : Icons.unfold_more,
              size: isCompact ? 20 : 24,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _allExpanded = !_allExpanded;
                if (_allExpanded) {
                  // Expand all items
                  _expandedItems.addAll(_filteredItems.map((item) => item['id'] as String));
                } else {
                  // Collapse all items
                  _expandedItems.clear();
                }
              });
            },
            tooltip: _allExpanded ? 'Collapse All' : 'Expand All',
          ),
          // Label Printing Button
          IconButton(
            icon: Icon(Icons.qr_code_2, size: isCompact ? 20 : 24, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => LabelPrintingPage(inventoryItems: _allItems),
                ),
              );
            },
            tooltip: 'Print Labels',
          ),
          // POS Button - navigates based on user role
          IconButton(
            icon: Icon(Icons.point_of_sale, size: isCompact ? 20 : 24, color: Colors.white),
            onPressed: _navigateToPOS,
            tooltip: 'POS',
          ),
          IconButton(
            icon: Icon(Icons.refresh, size: isCompact ? 20 : 24, color: Colors.white),
            onPressed: _loadInventory,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _accentColor))
          : RefreshIndicator(
              color: _accentColor,
              backgroundColor: _cardColor,
              onRefresh: _loadInventory,
              child: CustomScrollView(
                slivers: [
                  // Stats Cards
                  SliverToBoxAdapter(
                    child: _buildStatsSection(isMobile, isCompact),
                  ),
                  // Search and Filters
                  SliverToBoxAdapter(
                    child: _buildSearchAndFilters(isMobile, isCompact),
                  ),
                  // Items List
                  _filteredItems.isEmpty
                      ? SliverFillRemaining(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inventory_2_outlined,
                                    size: 64, color: _textSecondary.withValues(alpha: 0.5)),
                                const SizedBox(height: 16),
                                Text(
                                  'No items found',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: _textSecondary.withValues(alpha: 0.7),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () => _showAddItemDialog(),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add First Item'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _accentColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : SliverPadding(
                          padding: EdgeInsets.only(
                            left: isCompact ? 8 : (isMobile ? 12 : 16),
                            right: isCompact ? 8 : (isMobile ? 12 : 16),
                            top: isCompact ? 8 : (isMobile ? 12 : 16),
                            bottom: isCompact ? 60 : 80, // Extra padding for FAB
                          ),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                if (index < _paginatedItems.length) {
                                  final actualIndex = _currentPage * _itemsPerPage + index;
                                  return _buildItemCard(_paginatedItems[index], actualIndex + 1, isMobile, isCompact);
                                } else if (index == _paginatedItems.length && _filteredItems.length > _itemsPerPage) {
                                  // Add pagination controls after the list
                                  return _buildPaginationControls(isMobile);
                                }
                                return null;
                              },
                              childCount: _paginatedItems.length + (_filteredItems.length > _itemsPerPage ? 1 : 0),
                            ),
                          ),
                        ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddItemDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Item'),
        backgroundColor: _accentColor,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildPaginationControls(bool isMobile) {
    final startItem = _currentPage * _itemsPerPage + 1;
    final endItem = ((_currentPage + 1) * _itemsPerPage).clamp(0, _filteredItems.length);

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      margin: EdgeInsets.only(top: isMobile ? 12 : 16, bottom: isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Page info
          Text(
            'Showing $startItem-$endItem of ${_filteredItems.length}',
            style: TextStyle(
              color: _textSecondary,
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
                onPressed: _currentPage > 0 ? _previousPage : null,
                icon: const Icon(Icons.chevron_left),
                color: _accentColor,
                disabledColor: _textSecondary.withValues(alpha: 0.3),
                iconSize: isMobile ? 24 : 28,
              ),
              SizedBox(width: isMobile ? 8 : 16),
              // Page numbers
              ...List.generate(
                _totalPages > 5 ? 5 : _totalPages,
                (index) {
                  int pageNumber;
                  if (_totalPages <= 5) {
                    pageNumber = index;
                  } else if (_currentPage < 3) {
                    pageNumber = index;
                  } else if (_currentPage > _totalPages - 4) {
                    pageNumber = _totalPages - 5 + index;
                  } else {
                    pageNumber = _currentPage - 2 + index;
                  }

                  if (pageNumber >= _totalPages) return const SizedBox.shrink();

                  final isCurrentPage = pageNumber == _currentPage;
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 2 : 4),
                    child: InkWell(
                      onTap: () => _goToPage(pageNumber),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: isMobile ? 32 : 40,
                        height: isMobile ? 32 : 40,
                        decoration: BoxDecoration(
                          color: isCurrentPage
                              ? _accentColor
                              : _cardColor.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isCurrentPage
                                ? _accentColor
                                : _textSecondary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '${pageNumber + 1}',
                            style: TextStyle(
                              color: isCurrentPage
                                  ? Colors.white
                                  : _textSecondary,
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
                onPressed: _currentPage < _totalPages - 1 ? _nextPage : null,
                icon: const Icon(Icons.chevron_right),
                color: _accentColor,
                disabledColor: _textSecondary.withValues(alpha: 0.3),
                iconSize: isMobile ? 24 : 28,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(bool isMobile, bool isCompact) {
    final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    return Padding(
      padding: EdgeInsets.all(isCompact ? 8 : (isMobile ? 12 : 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isCompact)
            const Text(
              'Overview',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: _textPrimary,
              ),
            ),
          if (!isCompact) const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatCard(
                  'Total Items',
                  '${_stats['totalItems'] ?? 0}',
                  Icons.inventory_2,
                  Colors.blue,
                  isMobile,
                  isCompact,
                ),
                _buildStatCard(
                  'Total Quantity',
                  '${_stats['totalQuantity'] ?? 0}',
                  Icons.numbers,
                  Colors.green,
                  isMobile,
                  isCompact,
                ),
                _buildStatCard(
                  'Low Stock',
                  '${_stats['lowStockCount'] ?? 0}',
                  Icons.warning_amber,
                  Colors.orange,
                  isMobile,
                  isCompact,
                ),
                _buildStatCard(
                  'Out of Stock',
                  '${_stats['outOfStockCount'] ?? 0}',
                  Icons.error_outline,
                  Colors.red,
                  isMobile,
                  isCompact,
                ),
                // Total Value - only visible to admin/super admin
                if (_isAdminOrSuperAdmin)
                  _buildStatCard(
                    'Total Value',
                    currencyFormat.format(_stats['totalValue'] ?? 0),
                    Icons.attach_money,
                    Colors.teal,
                    isMobile,
                    isCompact,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, bool isMobile, bool isCompact) {
    if (isCompact) {
      return Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 9,
                color: _textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: isMobile ? 110 : 140,
      margin: const EdgeInsets.only(right: 12),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: isMobile ? 20 : 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: isMobile ? 14 : 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: isMobile ? 10 : 12,
              color: _textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters(bool isMobile, bool isCompact) {
    // Compact landscape: single row with search + filters
    if (isCompact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          children: [
            Row(
              children: [
                // Compact search field
                Expanded(
                  flex: 5,
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: _textPrimary, fontSize: 11),
                      cursorColor: _accentColor,
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        hintStyle: TextStyle(color: _textSecondary.withValues(alpha: 0.5), fontSize: 11),
                        prefixIcon: Icon(Icons.search, color: _textSecondary.withValues(alpha: 0.7), size: 16),
                        prefixIconConstraints: const BoxConstraints(minWidth: 32),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                    _filterAndSortItems();
                                  });
                                },
                                child: Icon(Icons.clear, color: _textSecondary.withValues(alpha: 0.7), size: 14),
                              )
                            : null,
                        suffixIconConstraints: const BoxConstraints(minWidth: 28),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.2)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.2)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: _accentColor),
                        ),
                        filled: true,
                        fillColor: _cardColor,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        _debounceTimer?.cancel();
                        _debounceTimer = Timer(const Duration(milliseconds: 300), () {
                          setState(() {
                            _searchQuery = value;
                            _filterAndSortItems();
                          });
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // OCR Scan button for search
                Container(
                  height: 32,
                  width: 32,
                  decoration: BoxDecoration(
                    color: _cardColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _textSecondary.withValues(alpha: 0.2)),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.document_scanner, color: Colors.white, size: 16),
                    onPressed: _openOcrScannerForSearch,
                    tooltip: 'Scan Serial',
                  ),
                ),
                const SizedBox(width: 4),
                // Category
                Expanded(
                  flex: 2,
                  child: _buildCompactLabeledDropdown(
                    label: 'Cat',
                    value: _selectedCategory,
                    displayValue: _selectedCategory == 'all'
                        ? 'All'
                        : (InventoryService.categoryLabels[_selectedCategory] ?? _selectedCategory),
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All')),
                      ...InventoryService.categoryLabels.entries.map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedCategory = value ?? 'all';
                        _filterAndSortItems();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 3),
                // Brand
                Expanded(
                  flex: 2,
                  child: _buildCompactLabeledDropdown(
                    label: 'Brand',
                    value: _selectedBrand,
                    displayValue: _selectedBrand == 'all' ? 'All' : _selectedBrand,
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All')),
                      ..._availableBrands.map((brand) =>
                        DropdownMenuItem(value: brand, child: Text(brand)),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedBrand = value ?? 'all';
                        _filterAndSortItems();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 3),
                // Stock Status
                Expanded(
                  flex: 2,
                  child: _buildCompactLabeledDropdown(
                    label: 'Status',
                    value: _selectedStockStatus,
                    displayValue: _selectedStockStatus == 'all' ? 'All' :
                        _selectedStockStatus == 'in_stock' ? 'In' :
                        _selectedStockStatus == 'low_stock' ? 'Low' : 'Out',
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All')),
                      DropdownMenuItem(value: 'in_stock', child: Text('In Stock')),
                      DropdownMenuItem(value: 'low_stock', child: Text('Low Stock')),
                      DropdownMenuItem(value: 'out_of_stock', child: Text('Out of Stock')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedStockStatus = value ?? 'all';
                        _filterAndSortItems();
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            // Results count - smaller
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_filteredItems.length} items',
                style: TextStyle(color: _textSecondary.withValues(alpha: 0.6), fontSize: 10),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 16),
      child: Column(
        children: [
          // Search bar - more compact on mobile
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: _textPrimary, fontSize: isMobile ? 13 : 14),
                  decoration: InputDecoration(
                    hintText: 'Search name or serial...',
                    hintStyle: TextStyle(color: _textSecondary.withValues(alpha: 0.5), fontSize: isMobile ? 13 : 14),
                    prefixIcon: Icon(Icons.search, color: _textSecondary.withValues(alpha: 0.7), size: isMobile ? 20 : 24),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: _textSecondary.withValues(alpha: 0.7), size: isMobile ? 18 : 22),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _filterAndSortItems();
                              });
                            },
                          )
                        : null,
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
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: isMobile ? 8 : 12,
                    ),
                    isDense: isMobile,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                      _filterAndSortItems();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              // OCR Scan button for search
              Container(
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _textSecondary.withValues(alpha: 0.2)),
                ),
                child: IconButton(
                  icon: Icon(Icons.document_scanner, color: Colors.white, size: isMobile ? 20 : 24),
                  onPressed: _openOcrScannerForSearch,
                  tooltip: 'Scan Serial Number',
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 8 : 12),
          // Filters - all in ONE row for mobile
          if (isMobile)
            Row(
              children: [
                // Category (Phone, TV, etc.)
                Expanded(
                  flex: 3,
                  child: _buildMiniDropdown(
                    value: _selectedCategory,
                    hint: 'Category',
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All Cat.')),
                      ...InventoryService.categoryLabels.entries.map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedCategory = value ?? 'all';
                        _filterAndSortItems();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 3),
                // Brand (Samsung, Apple, etc.)
                Expanded(
                  flex: 3,
                  child: _buildMiniDropdown(
                    value: _selectedBrand,
                    hint: 'Brand',
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All Brand')),
                      ..._availableBrands.map((brand) =>
                        DropdownMenuItem(value: brand, child: Text(brand)),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedBrand = value ?? 'all';
                        _filterAndSortItems();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 3),
                // Stock Status
                Expanded(
                  flex: 2,
                  child: _buildMiniDropdown(
                    value: _selectedStockStatus,
                    hint: 'Status',
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All')),
                      DropdownMenuItem(value: 'in_stock', child: Text('In')),
                      DropdownMenuItem(value: 'low_stock', child: Text('Low')),
                      DropdownMenuItem(value: 'out_of_stock', child: Text('Out')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedStockStatus = value ?? 'all';
                        _filterAndSortItems();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 3),
                // Sort direction button
                Container(
                  height: 32,
                  width: 28,
                  decoration: BoxDecoration(
                    color: _cardColor,
                    border: Border.all(color: _textSecondary.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
                    icon: Icon(
                      _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                      color: _accentColor,
                      size: 16,
                    ),
                    onPressed: () {
                      setState(() {
                        _sortAscending = !_sortAscending;
                        _filterAndSortItems();
                      });
                    },
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                // Category dropdown (Phone, TV, etc.)
                Expanded(
                  child: _buildDropdown(
                    value: _selectedCategory,
                    label: 'Category',
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All Categories')),
                      ...InventoryService.categoryLabels.entries.map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedCategory = value ?? 'all';
                        _filterAndSortItems();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Brand dropdown (Samsung, Apple, etc.)
                Expanded(
                  child: _buildDropdown(
                    value: _selectedBrand,
                    label: 'Brand',
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All Brands')),
                      ..._availableBrands.map((brand) =>
                        DropdownMenuItem(value: brand, child: Text(brand)),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedBrand = value ?? 'all';
                        _filterAndSortItems();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Stock Status dropdown
                Expanded(
                  child: _buildDropdown(
                    value: _selectedStockStatus,
                    label: 'Stock Status',
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Status')),
                      DropdownMenuItem(value: 'in_stock', child: Text('In Stock')),
                      DropdownMenuItem(value: 'low_stock', child: Text('Low Stock')),
                      DropdownMenuItem(value: 'out_of_stock', child: Text('Out of Stock')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedStockStatus = value ?? 'all';
                        _filterAndSortItems();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: _cardColor,
                    border: Border.all(color: _textSecondary.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: Icon(
                      _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                      color: _accentColor,
                    ),
                    onPressed: () {
                      setState(() {
                        _sortAscending = !_sortAscending;
                        _filterAndSortItems();
                      });
                    },
                    tooltip: _sortAscending ? 'Ascending' : 'Descending',
                  ),
                ),
              ],
            ),
          const SizedBox(height: 4),
          // Results count
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_filteredItems.length} items',
              style: TextStyle(color: _textSecondary.withValues(alpha: 0.6), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniDropdown({
    required String value,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
    String? hint,
  }) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _textSecondary.withValues(alpha: 0.2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: _cardColor,
          style: const TextStyle(color: _textPrimary, fontSize: 11),
          icon: Icon(Icons.arrow_drop_down, color: _textSecondary, size: 16),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildCompactLabeledDropdown({
    required String label,
    required String value,
    required String displayValue,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
  }) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _textSecondary.withValues(alpha: 0.2)),
      ),
      child: PopupMenuButton<String>(
        initialValue: value,
        onSelected: onChanged,
        offset: const Offset(0, 32),
        color: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        itemBuilder: (context) => items.map((item) {
          return PopupMenuItem<String>(
            value: item.value,
            height: 36,
            child: DefaultTextStyle(
              style: const TextStyle(color: _textPrimary, fontSize: 12),
              child: item.child,
            ),
          );
        }).toList(),
        child: Row(
          children: [
            Expanded(
              child: RichText(
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$label: ',
                      style: const TextStyle(color: _textSecondary, fontSize: 9),
                    ),
                    TextSpan(
                      text: displayValue,
                      style: const TextStyle(color: _textPrimary, fontSize: 10, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: _textSecondary, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required String label,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      dropdownColor: _cardColor,
      style: const TextStyle(color: _textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: _textSecondary.withValues(alpha: 0.7)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accentColor),
        ),
        filled: true,
        fillColor: _cardColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item, int itemNumber, bool isMobile, bool isCompact) {
    final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final status = item['status'] as String? ?? 'Unknown';
    final quantity = item['quantity'] as int? ?? 0;
    final sellingPrice = (item['sellingPrice'] as num?)?.toDouble() ?? 0;
    final serialNo = item['sku'] as String? ?? item['serialNo'] as String? ?? '-';
    final name = item['name'] as String? ?? 'Unnamed Item';
    final itemId = item['id'] as String? ?? '';
    final isExpanded = _allExpanded || _expandedItems.contains(itemId);

    Color statusColor;
    switch (status) {
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

    // Show low stock warning if quantity is below 10
    final bool isLowStock = quantity < 10 && quantity > 0;
    final bool isOutOfStock = quantity == 0;

    return Container(
      margin: EdgeInsets.only(bottom: isCompact ? 8 : 12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(isCompact ? 12 : 16),
        border: Border.all(color: _textSecondary.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          // Header row - always visible (tappable to expand/collapse)
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedItems.remove(itemId);
                  // If manually collapsing, turn off "all expanded" mode
                  if (_allExpanded) _allExpanded = false;
                } else {
                  _expandedItems.add(itemId);
                }
              });
            },
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(isCompact ? 12 : 16),
              bottom: isExpanded ? Radius.zero : Radius.circular(isCompact ? 12 : 16),
            ),
            child: Padding(
              padding: EdgeInsets.all(isCompact ? 8 : (isMobile ? 12 : 16)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Item number badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_accentColor, _accentDark],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '#$itemNumber',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 12 : 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isMobile ? 14 : 16,
                            color: _textPrimary,
                          ),
                          maxLines: isExpanded ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (!isExpanded) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Qty: $quantity  •  ${currencyFormat.format(sellingPrice)}',
                            style: TextStyle(
                              color: _textSecondary.withValues(alpha: 0.7),
                              fontSize: isMobile ? 11 : 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    flex: 0,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 8 : 12,
                        vertical: isMobile ? 4 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: isMobile ? 10 : 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Expand/Collapse icon
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: _textSecondary,
                    size: isMobile ? 20 : 24,
                  ),
                ],
              ),
            ),
          ),
          // Expandable details section
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: EdgeInsets.only(
                left: isCompact ? 8 : (isMobile ? 12 : 16),
                right: isCompact ? 8 : (isMobile ? 12 : 16),
                bottom: isCompact ? 8 : (isMobile ? 12 : 16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Divider
                  Divider(color: _textSecondary.withValues(alpha: 0.1), height: 1),
                  const SizedBox(height: 12),
                  // SKU/Serial number
                  Text(
                    'SKU/Serial No.: $serialNo',
                    style: TextStyle(
                      color: _textSecondary.withValues(alpha: 0.7),
                      fontSize: isMobile ? 11 : 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  // Item details row - Quantity and Price
                  Row(
                    children: [
                      Expanded(
                        child: _buildItemStat(
                          'Quantity',
                          '$quantity',
                          Icons.inventory,
                          isLowStock || isOutOfStock ? Colors.orange : _textSecondary,
                          isMobile,
                        ),
                      ),
                      Expanded(
                        child: _buildItemStat(
                          'Price',
                          currencyFormat.format(sellingPrice),
                          Icons.sell,
                          _textSecondary,
                          isMobile,
                        ),
                      ),
                    ],
                  ),
                  // Low stock warning
                  if (isLowStock || isOutOfStock) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isOutOfStock ? Colors.red.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isOutOfStock ? Colors.red.withValues(alpha: 0.3) : Colors.orange.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isOutOfStock ? Icons.error_outline : Icons.warning_amber,
                            size: 16,
                            color: isOutOfStock ? Colors.red : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isOutOfStock ? 'Out of Stock!' : 'Low Stock! Only $quantity left',
                              style: TextStyle(
                                color: isOutOfStock ? Colors.red : Colors.orange,
                                fontSize: isMobile ? 11 : 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Action buttons - responsive
                  if (isMobile)
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildActionButton(
                                onPressed: () => _showStockAdjustDialog(item),
                                icon: Icons.add_circle_outline,
                                label: 'Stock',
                                color: _accentColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildActionButton(
                                onPressed: () => _showEditItemDialog(item),
                                icon: Icons.edit,
                                label: 'Edit',
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildActionButton(
                                onPressed: () => _showItemDetailsDialog(item),
                                icon: Icons.visibility,
                                label: 'View',
                                color: Colors.teal,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildActionButton(
                                onPressed: () => _confirmDeleteItem(item),
                                icon: Icons.delete_outline,
                                label: 'Delete',
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  else
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: () => _showItemDetailsDialog(item),
                          icon: const Icon(Icons.visibility, size: 18),
                          label: const Text('View'),
                          style: TextButton.styleFrom(foregroundColor: Colors.teal),
                        ),
                        TextButton.icon(
                          onPressed: () => _showStockAdjustDialog(item),
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          label: const Text('Adjust Stock'),
                          style: TextButton.styleFrom(foregroundColor: _accentColor),
                        ),
                        TextButton.icon(
                          onPressed: () => _showEditItemDialog(item),
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('Edit'),
                          style: TextButton.styleFrom(foregroundColor: Colors.blue),
                        ),
                        TextButton.icon(
                          onPressed: () => _confirmDeleteItem(item),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Delete'),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(color: color)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 8),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildItemStat(String label, String value, IconData icon, Color color, bool isMobile) {
    return Row(
      children: [
        Icon(icon, size: isMobile ? 14 : 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: isMobile ? 12 : 13,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                label,
                style: TextStyle(
                  color: _textSecondary.withValues(alpha: 0.5),
                  fontSize: isMobile ? 9 : 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<bool> _checkDuplicateSerialNo(String serialNo, {String? excludeId}) async {
    if (serialNo.isEmpty) return false;
    final normalizedSerialNo = serialNo.toLowerCase().trim();
    for (var item in _allItems) {
      if (excludeId != null && item['id'] == excludeId) continue;
      final itemSerialNo = (item['sku'] as String? ?? item['serialNo'] as String? ?? '').toLowerCase().trim();
      if (itemSerialNo == normalizedSerialNo) return true;
    }
    return false;
  }

  Map<String, dynamic>? _findItemBySerialNo(String serialNo) {
    if (serialNo.isEmpty) return null;
    final normalized = serialNo.toLowerCase().trim();
    for (var item in _allItems) {
      final itemSerialNo = (item['sku'] as String? ?? item['serialNo'] as String? ?? '').toLowerCase().trim();
      if (itemSerialNo == normalized) return item;
    }
    return null;
  }

  /// Show error dialog that appears on top of everything
  Future<void> _showErrorDialog(BuildContext context, String title, String message) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.error_outline, color: Colors.red, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.black87, fontSize: 15),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _openOcrScannerForSearch() async {
    final result = await Navigator.push<OcrExtractedData>(
      context,
      MaterialPageRoute(
        builder: (context) => const OcrScannerPage(
          serviceName: 'Inventory',
          primaryColor: _accentColor,
          serviceType: 'inventory_serial',
        ),
      ),
    );

    if (result != null && result.serialNumber != null && result.serialNumber!.isNotEmpty) {
      setState(() {
        _searchController.text = result.serialNumber!;
        _searchQuery = result.serialNumber!;
        _filterAndSortItems();
      });
    }
  }

  Future<String?> _openOcrScannerForSerial() async {
    final result = await Navigator.push<OcrExtractedData>(
      context,
      MaterialPageRoute(
        builder: (context) => const OcrScannerPage(
          serviceName: 'Inventory',
          primaryColor: _accentColor,
          serviceType: 'inventory_serial',
        ),
      ),
    );

    if (result != null && result.serialNumber != null && result.serialNumber!.isNotEmpty) {
      return result.serialNumber;
    }
    return null;
  }

  void _showAddItemDialog() {
    final nameController = TextEditingController();
    final brandController = TextEditingController();
    final serialNoController = TextEditingController();
    final modelNumberController = TextEditingController();
    final quantityController = TextEditingController(text: '0');
    final sellingPriceController = TextEditingController();
    final unitCostController = TextEditingController();
    final descriptionController = TextEditingController();
    final reorderLevelController = TextEditingController(text: '10');
    final supplierController = TextEditingController();
    final locationController = TextEditingController();
    final notesController = TextEditingController();
    String selectedCategory = InventoryService.phones;
    String? selectedBrand;
    final bool isAdmin = _currentUserRole.toLowerCase() == 'admin';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _cardColor,
          title: const Text('Add New Item', style: TextStyle(color: _textPrimary)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Category dropdown
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    isExpanded: true,
                    dropdownColor: _cardColor,
                    style: const TextStyle(color: _textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Category *',
                      labelStyle: TextStyle(color: _textSecondary),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: _accentColor),
                      ),
                      filled: true,
                      fillColor: _bgColor,
                    ),
                    items: InventoryService.categoryLabels.entries.map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ).toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedCategory = value ?? InventoryService.phones);
                    },
                  ),
                  const SizedBox(height: 12),
                  // Brand field - autocomplete with existing brands or enter new
                  Autocomplete<String>(
                    optionsBuilder: (textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return _availableBrands;
                      }
                      return _availableBrands.where((brand) =>
                        brand.toLowerCase().contains(textEditingValue.text.toLowerCase())
                      );
                    },
                    onSelected: (selection) {
                      selectedBrand = selection;
                      brandController.text = selection;
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      // Sync with our controller
                      controller.text = brandController.text;
                      controller.addListener(() {
                        brandController.text = controller.text;
                        selectedBrand = controller.text;
                      });
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        style: const TextStyle(color: _textPrimary),
                        decoration: InputDecoration(
                          labelText: 'Brand *',
                          labelStyle: TextStyle(color: _textSecondary),
                          hintText: 'Enter or select brand',
                          hintStyle: TextStyle(color: _textSecondary.withValues(alpha: 0.5)),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.3)),
                          ),
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
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          color: _cardColor,
                          elevation: 4,
                          borderRadius: BorderRadius.circular(10),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 200, maxWidth: 280),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return ListTile(
                                  dense: true,
                                  title: Text(option, style: const TextStyle(color: _textPrimary)),
                                  onTap: () => onSelected(option),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildDialogTextField(
                    controller: nameController,
                    label: 'Name of Item *',
                    hint: 'Enter item name',
                  ),
                  const SizedBox(height: 12),
                  _buildDialogTextField(
                    controller: modelNumberController,
                    label: 'Model Number',
                    hint: 'Enter model number',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDialogTextField(
                          controller: serialNoController,
                          label: 'SKU/Serial No. *',
                          hint: 'Enter unique SKU or serial number',
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF9B59B6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.auto_awesome, color: Colors.white),
                          onPressed: () async {
                            final nextSku = await InventoryService.generateNextSku();
                            serialNoController.text = nextSku;
                          },
                          tooltip: 'Auto-generate SKU (9000000+ series)',
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        decoration: BoxDecoration(
                          color: _accentColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.document_scanner, color: Colors.white),
                          onPressed: () async {
                            final scannedSerial = await _openOcrScannerForSerial();
                            if (scannedSerial != null) {
                              serialNoController.text = scannedSerial;
                            }
                          },
                          tooltip: 'Scan SKU/Serial Number',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDialogTextField(
                          controller: quantityController,
                          label: 'Quantity *',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildDialogTextField(
                          controller: reorderLevelController,
                          label: 'Reorder Level',
                          hint: 'Low stock alert',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDialogTextField(
                          controller: sellingPriceController,
                          label: 'Selling Price (₱) *',
                          prefix: '₱ ',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      if (isAdmin) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDialogTextField(
                            controller: unitCostController,
                            label: 'Unit Cost (₱)',
                            prefix: '₱ ',
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildDialogTextField(
                    controller: descriptionController,
                    label: 'Description',
                    hint: 'Enter item description',
                  ),
                  const SizedBox(height: 12),
                  _buildDialogTextField(
                    controller: supplierController,
                    label: 'Supplier',
                    hint: 'Enter supplier name',
                  ),
                  const SizedBox(height: 12),
                  _buildDialogTextField(
                    controller: locationController,
                    label: 'Location',
                    hint: 'Storage location',
                  ),
                  const SizedBox(height: 12),
                  _buildDialogTextField(
                    controller: notesController,
                    label: 'Notes',
                    hint: 'Additional notes',
                  ),
                ],
              ),
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
                // Store context-dependent objects at the start before any async operations
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                final pageContext = this.context; // Use page context for dialogs after pop

                final name = nameController.text.trim();
                final serialNo = serialNoController.text.trim();
                final brand = brandController.text.trim();
                final modelNumber = modelNumberController.text.trim();
                final quantity = int.tryParse(quantityController.text) ?? 0;
                final sellingPrice = double.tryParse(sellingPriceController.text);
                final unitCost = double.tryParse(unitCostController.text);
                final description = descriptionController.text.trim();
                final reorderLevel = int.tryParse(reorderLevelController.text) ?? 10;
                final supplier = supplierController.text.trim();
                final location = locationController.text.trim();
                final notes = notesController.text.trim();
                final category = selectedCategory;

                if (brand.isEmpty) {
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(content: Text('Please enter brand')),
                  );
                  return;
                }

                if (name.isEmpty) {
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(content: Text('Please enter item name')),
                  );
                  return;
                }

                if (serialNo.isEmpty) {
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(content: Text('Please enter serial number')),
                  );
                  return;
                }

                // Check connectivity before adding
                final hasConnection = await CacheService.hasConnectivity();
                if (!hasConnection) {
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('No internet connection. Cannot add item offline.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Check for duplicate serial number — offer choices
                final existingItem = _findItemBySerialNo(serialNo);
                if (existingItem != null) {
                  if (!context.mounted) return;
                  final choice = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: _cardColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: const Row(
                        children: [
                          Icon(Icons.info_outline, color: _accentColor, size: 24),
                          SizedBox(width: 8),
                          Expanded(child: Text('Item Already Exists', style: TextStyle(color: _textPrimary, fontSize: 16))),
                        ],
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('An item with this SKU/Serial No. already exists:', style: TextStyle(color: _textSecondary, fontSize: 13)),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: _bgColor, borderRadius: BorderRadius.circular(10)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(existingItem['name'] ?? '', style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                                const SizedBox(height: 4),
                                Text('Brand: ${existingItem['brand'] ?? 'N/A'}  •  Qty: ${existingItem['quantity'] ?? 0}', style: const TextStyle(color: _textSecondary, fontSize: 12)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text('What would you like to do?', style: TextStyle(color: _textPrimary, fontSize: 13)),
                        ],
                      ),
                      actionsAlignment: MainAxisAlignment.spaceBetween,
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel', style: TextStyle(color: _textSecondary)),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3498DB), foregroundColor: Colors.white),
                              onPressed: () => Navigator.pop(ctx, 'edit'),
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text('Edit Info'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2ECC71), foregroundColor: Colors.white),
                              onPressed: () => Navigator.pop(ctx, 'add_stock'),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add Stock'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                  if (choice == null) return;
                  navigator.pop();
                  if (choice == 'edit') {
                    _showEditItemDialog(existingItem);
                  } else if (choice == 'add_stock') {
                    _showStockAdjustDialog(existingItem);
                  }
                  return;
                }

                if (!mounted) return;

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
                        Text('Adding item...'),
                      ],
                    ),
                    duration: Duration(seconds: 30),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Color(0xFF3498DB),
                  ),
                );

                // Add item in background
                final result = await InventoryService.addItem(
                  category: category,
                  name: name,
                  sku: serialNo,
                  modelNumber: modelNumber.isNotEmpty ? modelNumber : null,
                  brand: brand,
                  description: description.isNotEmpty ? description : null,
                  quantity: quantity,
                  unitCost: unitCost,
                  sellingPrice: sellingPrice,
                  reorderLevel: reorderLevel,
                  supplier: supplier.isNotEmpty ? supplier : null,
                  location: location.isNotEmpty ? location : null,
                  notes: notes.isNotEmpty ? notes : null,
                  addedByEmail: _currentUserEmail,
                  addedByName: _currentUserName,
                );

                if (result != null) {
                  await InventoryService.updateItem(
                    category: category,
                    itemId: result,
                    sku: serialNo,
                  );

                  if (!mounted) return;

                  // Add the new item to the list incrementally
                  setState(() {
                    _allItems.add({
                      'id': result,
                      'category': category,
                      'name': name,
                      'brand': brand,
                      'sku': serialNo,
                      'modelNumber': modelNumber,
                      'description': description,
                      'quantity': quantity,
                      'unitCost': unitCost,
                      'sellingPrice': sellingPrice,
                      'reorderLevel': reorderLevel,
                      'supplier': supplier,
                      'location': location,
                      'notes': notes,
                    });
                    _filterAndSortItems();
                  });

                  scaffoldMessenger.hideCurrentSnackBar();
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Item added successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  if (!mounted) return;
                  scaffoldMessenger.hideCurrentSnackBar();
                  await _showErrorDialog(
                    pageContext,
                    'Failed to Add Item',
                    'Unable to save the item to the database.\n\nPlease check your internet connection and try again.',
                  );
                }
              },
              child: const Text('Add Item'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditItemDialog(Map<String, dynamic> item) {
    final nameController = TextEditingController(text: item['name'] ?? '');
    final brandController = TextEditingController(text: item['brand'] ?? '');
    final serialNoController = TextEditingController(text: item['sku'] ?? item['serialNo'] ?? '');
    final modelNumberController = TextEditingController(text: item['modelNumber'] ?? '');
    final quantityController = TextEditingController(text: '${item['quantity'] ?? 0}');
    final sellingPriceController = TextEditingController(text: '${item['sellingPrice'] ?? ''}');
    final unitCostController = TextEditingController(text: '${item['unitCost'] ?? ''}');
    final descriptionController = TextEditingController(text: item['description'] ?? '');
    final reorderLevelController = TextEditingController(text: '${item['reorderLevel'] ?? 10}');
    final supplierController = TextEditingController(text: item['supplier'] ?? '');
    final locationController = TextEditingController(text: item['location'] ?? '');
    final notesController = TextEditingController(text: item['notes'] ?? '');
    final bool isAdmin = _currentUserRole.toLowerCase() == 'admin';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: const Text('Edit Item', style: TextStyle(color: _textPrimary)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Brand field with autocomplete
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: item['brand'] ?? ''),
                  optionsBuilder: (textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return _availableBrands;
                    }
                    return _availableBrands.where((brand) =>
                      brand.toLowerCase().contains(textEditingValue.text.toLowerCase())
                    );
                  },
                  onSelected: (selection) {
                    brandController.text = selection;
                  },
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    controller.addListener(() {
                      brandController.text = controller.text;
                    });
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      style: const TextStyle(color: _textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Brand *',
                        labelStyle: TextStyle(color: _textSecondary),
                        hintText: 'Enter or select brand',
                        hintStyle: TextStyle(color: _textSecondary.withValues(alpha: 0.5)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.3)),
                        ),
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
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        color: _cardColor,
                        elevation: 4,
                        borderRadius: BorderRadius.circular(10),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 280),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (context, index) {
                              final option = options.elementAt(index);
                              return ListTile(
                                dense: true,
                                title: Text(option, style: const TextStyle(color: _textPrimary)),
                                onTap: () => onSelected(option),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _buildDialogTextField(
                  controller: nameController,
                  label: 'Name of Item *',
                ),
                const SizedBox(height: 12),
                _buildDialogTextField(
                  controller: modelNumberController,
                  label: 'Model Number',
                  hint: 'Enter model number',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildDialogTextField(
                        controller: serialNoController,
                        label: 'SKU/Serial No. *',
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF9B59B6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.auto_awesome, color: Colors.white),
                        onPressed: () async {
                          final nextSku = await InventoryService.generateNextSku();
                          serialNoController.text = nextSku;
                        },
                        tooltip: 'Auto-generate SKU (9000000+ series)',
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      decoration: BoxDecoration(
                        color: _accentColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.document_scanner, color: Colors.white),
                        onPressed: () async {
                          final scannedSerial = await _openOcrScannerForSerial();
                          if (scannedSerial != null) {
                            serialNoController.text = scannedSerial;
                          }
                        },
                        tooltip: 'Scan SKU/Serial Number',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildDialogTextField(
                        controller: quantityController,
                        label: 'Quantity *',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDialogTextField(
                        controller: reorderLevelController,
                        label: 'Reorder Level',
                        hint: 'Low stock alert',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildDialogTextField(
                        controller: sellingPriceController,
                        label: 'Selling Price (₱) *',
                        prefix: '₱ ',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildDialogTextField(
                          controller: unitCostController,
                          label: 'Unit Cost (₱)',
                          prefix: '₱ ',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                _buildDialogTextField(
                  controller: descriptionController,
                  label: 'Description',
                  hint: 'Enter item description',
                ),
                const SizedBox(height: 12),
                _buildDialogTextField(
                  controller: supplierController,
                  label: 'Supplier',
                  hint: 'Enter supplier name',
                ),
                const SizedBox(height: 12),
                _buildDialogTextField(
                  controller: locationController,
                  label: 'Location',
                  hint: 'Storage location',
                ),
                const SizedBox(height: 12),
                _buildDialogTextField(
                  controller: notesController,
                  label: 'Notes',
                  hint: 'Additional notes',
                ),
              ],
            ),
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
              // Store context-dependent objects at the start before any async operations
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final pageContext = this.context; // Use page context for dialogs after pop

              final name = nameController.text.trim();
              final brand = brandController.text.trim();
              final serialNo = serialNoController.text.trim();
              final modelNumber = modelNumberController.text.trim();
              final quantity = int.tryParse(quantityController.text);
              final sellingPrice = double.tryParse(sellingPriceController.text);
              final unitCost = double.tryParse(unitCostController.text);
              final description = descriptionController.text.trim();
              final reorderLevel = int.tryParse(reorderLevelController.text) ?? 10;
              final supplier = supplierController.text.trim();
              final location = locationController.text.trim();
              final notes = notesController.text.trim();

              if (brand.isEmpty) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('Please enter brand')),
                );
                return;
              }

              if (name.isEmpty) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('Please enter item name')),
                );
                return;
              }

              if (serialNo.isEmpty) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('Please enter serial number')),
                );
                return;
              }


              // Check for duplicate serial number (excluding current item)
              if (await _checkDuplicateSerialNo(serialNo, excludeId: item['id'])) {
                if (context.mounted) {
                  await _showErrorDialog(
                    context,
                    'Duplicate SKU/Serial No.',
                    'An item with this SKU/Serial Number already exists!\n\nEach item must have a unique SKU/Serial Number.',
                  );
                }
                return;
              }

              if (!mounted) return;

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

              // Update item in background
              final success = await InventoryService.updateItem(
                category: item['category'],
                itemId: item['id'],
                name: name,
                brand: brand,
                sku: serialNo,
                modelNumber: modelNumber.isNotEmpty ? modelNumber : null,
                description: description.isNotEmpty ? description : null,
                quantity: quantity,
                unitCost: unitCost,
                sellingPrice: sellingPrice,
                reorderLevel: reorderLevel,
                supplier: supplier.isNotEmpty ? supplier : null,
                location: location.isNotEmpty ? location : null,
                notes: notes.isNotEmpty ? notes : null,
                updatedByEmail: _currentUserEmail,
                updatedByName: _currentUserName,
              );

              if (!mounted) return;

              scaffoldMessenger.hideCurrentSnackBar();

              if (success) {
                // Update the item in the list incrementally
                final index = _allItems.indexWhere((i) => i['id'] == item['id']);
                if (index != -1) {
                  setState(() {
                    _allItems[index] = {
                      ..._allItems[index],
                      'name': name,
                      'brand': brand,
                      'sku': serialNo,
                      'modelNumber': modelNumber,
                      'description': description,
                      'quantity': quantity,
                      'unitCost': unitCost,
                      'sellingPrice': sellingPrice,
                      'reorderLevel': reorderLevel,
                      'supplier': supplier,
                      'location': location,
                      'notes': notes,
                    };
                    _filterAndSortItems();
                  });
                }
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Item updated successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                await _showErrorDialog(
                  pageContext,
                  'Failed to Update Item',
                  'Unable to save changes to the database.\n\nPlease check your internet connection and try again.',
                );
              }
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? prefix,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: _textPrimary),
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: _textSecondary),
        hintText: hint,
        hintStyle: TextStyle(color: _textSecondary.withValues(alpha: 0.5)),
        prefixText: prefix,
        prefixStyle: const TextStyle(color: _textPrimary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _textSecondary.withValues(alpha: 0.3)),
        ),
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
    );
  }

  void _showStockAdjustDialog(Map<String, dynamic> item) {
    final quantityController = TextEditingController();
    final reasonController = TextEditingController();
    String adjustType = 'add';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _cardColor,
          title: Text('Adjust Stock: ${item['name']}', style: const TextStyle(color: _textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Current Quantity: ${item['quantity'] ?? 0}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: _accentColor),
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'add', label: Text('Add'), icon: Icon(Icons.add)),
                    ButtonSegment(value: 'remove', label: Text('Remove'), icon: Icon(Icons.remove)),
                    ButtonSegment(value: 'set', label: Text('Set'), icon: Icon(Icons.edit)),
                  ],
                  selected: {adjustType},
                  onSelectionChanged: (value) {
                    setDialogState(() => adjustType = value.first);
                  },
                  style: ButtonStyle(
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) return Colors.white;
                      return _textSecondary;
                    }),
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) return _accentColor;
                      return _bgColor;
                    }),
                  ),
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: quantityController,
                  label: adjustType == 'set' ? 'New Quantity' : 'Quantity',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                _buildDialogTextField(
                  controller: reasonController,
                  label: 'Reason (optional)',
                ),
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
                final qty = int.tryParse(quantityController.text);
                if (qty == null || qty < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid quantity')),
                  );
                  return;
                }

                bool success = false;
                switch (adjustType) {
                  case 'add':
                    success = await InventoryService.addStock(
                      category: item['category'],
                      itemId: item['id'],
                      quantityToAdd: qty,
                      reason: reasonController.text,
                      addedByEmail: _currentUserEmail,
                      addedByName: _currentUserName,
                    );
                    break;
                  case 'remove':
                    success = await InventoryService.removeStock(
                      category: item['category'],
                      itemId: item['id'],
                      quantityToRemove: qty,
                      reason: reasonController.text,
                      removedByEmail: _currentUserEmail,
                      removedByName: _currentUserName,
                    );
                    break;
                  case 'set':
                    success = await InventoryService.setStock(
                      category: item['category'],
                      itemId: item['id'],
                      newQuantity: qty,
                      reason: reasonController.text,
                      setByEmail: _currentUserEmail,
                      setByName: _currentUserName,
                    );
                    break;
                }

                if (success) {
                  Navigator.pop(context);
                  _loadInventory();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Stock adjusted successfully')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to adjust stock')),
                  );
                }
              },
              child: const Text('Adjust'),
            ),
          ],
        ),
      ),
    );
  }

  void _showItemDetailsDialog(Map<String, dynamic> item) {
    final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final categoryLabel = InventoryService.categoryLabels[item['category']] ?? item['category'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: Text(item['name'] ?? 'Item Details', style: const TextStyle(color: _textPrimary)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Category', categoryLabel),
              if (item['brand'] != null && item['brand'].toString().isNotEmpty)
                _buildDetailRow('Brand', item['brand']),
              if (item['modelNumber'] != null && item['modelNumber'].toString().isNotEmpty)
                _buildDetailRow('Model No.', item['modelNumber']),
              _buildDetailRow('SKU/Serial No.', item['sku'] ?? item['serialNo'] ?? '-'),
              _buildDetailRow('Status', item['status'] ?? 'Unknown'),
              _buildDetailRow('Quantity', '${item['quantity'] ?? 0}'),
              if (item['reorderLevel'] != null)
                _buildDetailRow('Reorder Level', '${item['reorderLevel']}'),
              if (item['unitCost'] != null)
                _buildDetailRow('Unit Cost', currencyFormat.format(item['unitCost'])),
              if (item['sellingPrice'] != null)
                _buildDetailRow('Selling Price', currencyFormat.format(item['sellingPrice'])),
              if (item['description'] != null && item['description'].toString().isNotEmpty)
                _buildDetailRow('Description', item['description']),
              if (item['supplier'] != null && item['supplier'].toString().isNotEmpty)
                _buildDetailRow('Supplier', item['supplier']),
              if (item['location'] != null && item['location'].toString().isNotEmpty)
                _buildDetailRow('Location', item['location']),
              if (item['notes'] != null && item['notes'].toString().isNotEmpty)
                _buildDetailRow('Notes', item['notes']),
              if (item['addedBy'] != null && item['addedBy'] is Map)
                _buildDetailRow('Added By', item['addedBy']['name'] ?? item['addedBy']['email'] ?? '-'),
              if (item['createdAt'] != null || item['timestamp'] != null)
                _buildDetailRow('Date Added', DateFormat('MMM dd, yyyy hh:mm a').format(
                  DateTime.fromMillisecondsSinceEpoch(
                    item['createdAt'] as int? ?? item['timestamp'] as int? ?? 0,
                  ),
                )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: _textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              _showEditItemDialog(item);
            },
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: _textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: _textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteItem(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: const Text('Delete Item', style: TextStyle(color: _textPrimary)),
        content: Text(
          'Are you sure you want to delete "${item['name']}"? This action cannot be undone.',
          style: TextStyle(color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: _textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final success = await InventoryService.deleteItem(
                item['category'],
                item['id'],
              );

              Navigator.pop(context);

              if (success) {
                _loadInventory();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Item deleted successfully')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to delete item')),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
