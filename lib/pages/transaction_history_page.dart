import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/cache_service.dart';
import 'ocr_scanner_page.dart';

/// Transaction History Page - Read-only view of all POS transactions
/// Accessible by both users and admins
class TransactionHistoryPage extends StatefulWidget {
  const TransactionHistoryPage({super.key});

  @override
  State<TransactionHistoryPage> createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  // Dark theme colors matching the app
  static const Color _bgColor = Color(0xFF1A0A0A);
  static const Color _cardColor = Color(0xFF252525);
  static const Color _accentColor = Color(0xFFE67E22);
  static const Color _textPrimary = Colors.white;
  static const Color _textSecondary = Color(0xFFB0B0B0);

  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedDateFilter = 'all';
  final Set<String> _expandedTransactions = {};
  final _searchController = TextEditingController();

  final _currencyFormat = NumberFormat.currency(symbol: '\u20B1', decimalDigits: 2);
  final _dateFormat = DateFormat('MMM dd, yyyy');
  final _timeFormat = DateFormat('hh:mm a');

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTransactions() async {
    setState(() => _isLoading = true);

    try {
      // Try cache first
      final hasCache = await CacheService.hasPosTransactionsCache();
      if (hasCache) {
        final cachedTransactions = await CacheService.getPosTransactions();
        if (cachedTransactions.isNotEmpty) {
          setState(() {
            _transactions = cachedTransactions;
            _sortTransactions();
            _isLoading = false;
          });
          return;
        }
      }

      // Fetch from Firebase if no cache
      final snapshot = await FirebaseDatabase.instance.ref('pos_transactions').get();
      if (snapshot.exists && snapshot.value != null) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final List<Map<String, dynamic>> transactions = [];

        data.forEach((key, value) {
          if (value is Map) {
            final transaction = Map<String, dynamic>.from(value);
            transaction['id'] = key;
            transactions.add(transaction);
          }
        });

        // Cache the transactions
        await CacheService.savePosTransactions(transactions);

        setState(() {
          _transactions = transactions;
          _sortTransactions();
        });
      }
    } catch (e) {
      // Try cache as fallback on error
      final cachedTransactions = await CacheService.getPosTransactions();
      setState(() {
        _transactions = cachedTransactions;
        _sortTransactions();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Using cached data. Error: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _sortTransactions() {
    _transactions.sort((a, b) {
      final timestampA = a['timestamp'] as String? ?? '';
      final timestampB = b['timestamp'] as String? ?? '';
      return timestampB.compareTo(timestampA); // Newest first
    });
  }

  List<Map<String, dynamic>> get _filteredTransactions {
    var filtered = _transactions;

    // Apply date filter
    if (_selectedDateFilter != 'all') {
      final now = DateTime.now();
      DateTime startDate;

      switch (_selectedDateFilter) {
        case 'today':
          startDate = DateTime(now.year, now.month, now.day);
          break;
        case 'week':
          startDate = now.subtract(const Duration(days: 7));
          break;
        case 'month':
          startDate = DateTime(now.year, now.month, 1);
          break;
        default:
          startDate = DateTime(1970);
      }

      filtered = filtered.where((t) {
        final timestamp = DateTime.tryParse(t['timestamp'] ?? '');
        if (timestamp == null) return false;
        return timestamp.isAfter(startDate);
      }).toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((t) {
        final processedBy = (t['processedBy'] as String? ?? '').toLowerCase();
        final transactionId = (t['transactionId'] as String? ?? '').toLowerCase();
        final customerName = (t['customerName'] as String? ?? '').toLowerCase();
        return processedBy.contains(query) ||
            transactionId.contains(query) ||
            customerName.contains(query);
      }).toList();
    }

    return filtered;
  }

  Future<void> _openOcrScannerForTransactionId() async {
    final result = await Navigator.push<OcrExtractedData>(
      context,
      MaterialPageRoute(
        builder: (context) => const OcrScannerPage(
          serviceName: 'Transaction',
          primaryColor: _accentColor,
          serviceType: 'transaction_id',
        ),
      ),
    );

    if (result != null && result.serialNumber != null && result.serialNumber!.isNotEmpty) {
      setState(() {
        _searchController.text = result.serialNumber!;
        _searchQuery = result.serialNumber!;
      });
    }
  }

  void _toggleExpanded(String transactionId) {
    setState(() {
      if (_expandedTransactions.contains(transactionId)) {
        _expandedTransactions.remove(transactionId);
      } else {
        _expandedTransactions.add(transactionId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bgColor, Color(0xFF2D1515), _bgColor],
        ),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(isMobile),
          // Filters
          _buildFilters(isMobile),
          // Transaction List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: _accentColor),
                  )
                : _filteredTransactions.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadTransactions,
                        color: _accentColor,
                        child: ListView.builder(
                          padding: EdgeInsets.all(isMobile ? 12 : 16),
                          itemCount: _filteredTransactions.length,
                          itemBuilder: (context, index) {
                            return _buildTransactionCard(
                              _filteredTransactions[index],
                              isMobile,
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_accentColor, Color(0xFFD35400)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.history, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Transaction History',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: isMobile ? 20 : 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_filteredTransactions.length} transaction${_filteredTransactions.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: isMobile ? 12 : 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16),
      child: Column(
        children: [
          // Search bar
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: _textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search by staff, transaction ID, or customer...',
                    hintStyle: TextStyle(color: _textSecondary.withValues(alpha: 0.6)),
                    prefixIcon: const Icon(Icons.search, color: _textSecondary),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: _textSecondary),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: _cardColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: _accentColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.document_scanner, color: Colors.white),
                  onPressed: _openOcrScannerForTransactionId,
                  tooltip: 'Scan Transaction ID',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Date filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All Time', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('Today', 'today'),
                const SizedBox(width: 8),
                _buildFilterChip('This Week', 'week'),
                const SizedBox(width: 8),
                _buildFilterChip('This Month', 'month'),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedDateFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedDateFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _accentColor : _cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _accentColor : _textSecondary.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : _textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _cardColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: _textSecondary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Transactions Found',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try adjusting your search or filters'
                : 'Transactions will appear here once completed',
            style: TextStyle(
              color: _textSecondary,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> transaction, bool isMobile) {
    final transactionId = transaction['transactionId'] as String? ?? 'N/A';
    final isExpanded = _expandedTransactions.contains(transactionId);
    final timestamp = DateTime.tryParse(transaction['timestamp'] ?? '');
    final processedBy = transaction['processedBy'] as String? ?? 'Unknown';
    final total = (transaction['total'] as num?)?.toDouble() ?? 0.0;
    final paymentMethod = transaction['paymentMethod'] as String? ?? 'cash';
    final items = (transaction['items'] as List<dynamic>?) ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded
              ? _accentColor.withValues(alpha: 0.5)
              : _textSecondary.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          // Main row (always visible)
          InkWell(
            onTap: () => _toggleExpanded(transactionId),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Transaction icon
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _getPaymentColor(paymentMethod).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _getPaymentIcon(paymentMethod),
                      color: _getPaymentColor(paymentMethod),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Transaction info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          transactionId,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 14,
                              color: _textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                processedBy,
                                style: const TextStyle(
                                  color: _textSecondary,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (timestamp != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 14,
                                color: _textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${_dateFormat.format(timestamp)} at ${_timeFormat.format(timestamp)}',
                                  style: const TextStyle(
                                    color: _textSecondary,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Total and expand icon
                  Flexible(
                    flex: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _currencyFormat.format(total),
                          style: const TextStyle(
                            color: _accentColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getPaymentColor(paymentMethod).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            paymentMethod.toUpperCase(),
                            style: TextStyle(
                              color: _getPaymentColor(paymentMethod),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
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
          // Expanded details
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildExpandedDetails(transaction, items, isMobile),
            crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedDetails(
    Map<String, dynamic> transaction,
    List<dynamic> items,
    bool isMobile,
  ) {
    final subtotal = (transaction['subtotal'] as num?)?.toDouble() ?? 0.0;
    final vatAmount = (transaction['vatAmount'] as num?)?.toDouble() ?? 0.0;
    final total = (transaction['total'] as num?)?.toDouble() ?? 0.0;
    final cashReceived = (transaction['cashReceived'] as num?)?.toDouble();
    final change = (transaction['change'] as num?)?.toDouble();
    final referenceNumber = transaction['referenceNumber'] as String?;
    final customerName = transaction['customerName'] as String?;
    final paymentMethod = transaction['paymentMethod'] as String? ?? 'cash';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: _textSecondary.withValues(alpha: 0.2)),
          const SizedBox(height: 8),

          // Customer name if available
          if (customerName != null && customerName.isNotEmpty) ...[
            _buildDetailRow('Customer', customerName),
            const SizedBox(height: 8),
          ],

          // Items section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shopping_bag_outlined, color: _accentColor, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Items (${items.length})',
                      style: const TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...items.map((item) {
                  final itemMap = item as Map<dynamic, dynamic>;
                  final name = itemMap['name'] as String? ?? 'Unknown Item';
                  final quantity = (itemMap['quantity'] as num?)?.toInt() ?? 1;
                  final unitPrice = (itemMap['unitPrice'] as num?)?.toDouble() ?? 0.0;
                  final itemSubtotal = (itemMap['subtotal'] as num?)?.toDouble() ?? (unitPrice * quantity);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$name x$quantity',
                            style: const TextStyle(color: _textSecondary, fontSize: 12),
                          ),
                        ),
                        Text(
                          _currencyFormat.format(itemSubtotal),
                          style: const TextStyle(color: _textPrimary, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Totals section
          _buildDetailRow('Subtotal', _currencyFormat.format(subtotal)),
          if (vatAmount > 0)
            _buildDetailRow('VAT', _currencyFormat.format(vatAmount)),
          _buildDetailRow('Total', _currencyFormat.format(total), isBold: true, isAccent: true),

          // Payment details
          if (paymentMethod == 'cash' && cashReceived != null) ...[
            const SizedBox(height: 8),
            Divider(color: _textSecondary.withValues(alpha: 0.2)),
            const SizedBox(height: 8),
            _buildDetailRow('Cash Received', _currencyFormat.format(cashReceived)),
            if (change != null)
              _buildDetailRow('Change', _currencyFormat.format(change)),
          ],

          // Reference number for card/gcash
          if (referenceNumber != null && referenceNumber.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(color: _textSecondary.withValues(alpha: 0.2)),
            const SizedBox(height: 8),
            _buildDetailRow('Reference #', referenceNumber),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false, bool isAccent = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: _textSecondary,
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                color: isAccent ? _accentColor : _textPrimary,
                fontSize: 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Color _getPaymentColor(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return const Color(0xFF2ECC71);
      case 'card':
        return const Color(0xFF3498DB);
      case 'gcash/maya':
      case 'gcash':
      case 'maya':
        return const Color(0xFF9B59B6);
      default:
        return _accentColor;
    }
  }

  IconData _getPaymentIcon(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return Icons.payments_outlined;
      case 'card':
        return Icons.credit_card;
      case 'gcash/maya':
      case 'gcash':
      case 'maya':
        return Icons.phone_android;
      default:
        return Icons.receipt_long;
    }
  }
}
