import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';

class POSReportsPage extends StatefulWidget {
  const POSReportsPage({super.key});

  @override
  State<POSReportsPage> createState() => _POSReportsPageState();
}

class _POSReportsPageState extends State<POSReportsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _allTransactions = [];
  bool _isLoading = true;
  String _selectedUser = 'all';
  List<String> _users = [];
  DateTime _selectedDate = DateTime.now();

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
    _tabController = TabController(length: 4, vsync: this);
    _loadTransactions();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
          final usersSet = <String>{};
          for (var t in cachedTransactions) {
            if (t['processedBy'] != null) {
              usersSet.add(t['processedBy'] as String);
            }
          }
          cachedTransactions.sort((a, b) {
            final aTime = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime(1970);
            final bTime = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime(1970);
            return bTime.compareTo(aTime);
          });
          setState(() {
            _allTransactions = cachedTransactions;
            _users = usersSet.toList()..sort();
            _isLoading = false;
          });
          return;
        }
      }

      // Fetch from Firebase
      final snapshot = await FirebaseDatabase.instance.ref('pos_transactions').get();
      final transactions = <Map<String, dynamic>>[];
      final usersSet = <String>{};

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          final transaction = Map<String, dynamic>.from(value as Map);
          transaction['id'] = key;
          transactions.add(transaction);
          if (transaction['processedBy'] != null) {
            usersSet.add(transaction['processedBy'] as String);
          }
        });
      }

      // Sort by timestamp descending
      transactions.sort((a, b) {
        final aTime = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime(1970);
        final bTime = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });

      setState(() {
        _allTransactions = transactions;
        _users = usersSet.toList()..sort();
        _isLoading = false;
      });
    } catch (e) {
      // Fallback to cache on error
      final cachedTransactions = await CacheService.getPosTransactions();
      if (cachedTransactions.isNotEmpty) {
        final usersSet = <String>{};
        for (var t in cachedTransactions) {
          if (t['processedBy'] != null) {
            usersSet.add(t['processedBy'] as String);
          }
        }
        cachedTransactions.sort((a, b) {
          final aTime = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime(1970);
          final bTime = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime(1970);
          return bTime.compareTo(aTime);
        });
        setState(() {
          _allTransactions = cachedTransactions;
          _users = usersSet.toList()..sort();
          _isLoading = false;
        });
        return;
      }
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading transactions: $e')),
        );
      }
    }
  }

  List<Map<String, dynamic>> _filterTransactions(String period) {
    final now = _selectedDate;
    DateTime startDate;
    DateTime endDate;

    switch (period) {
      case 'daily':
        startDate = DateTime(now.year, now.month, now.day);
        endDate = startDate.add(const Duration(days: 1));
        break;
      case 'weekly':
        // Start of the week (Monday)
        final weekDay = now.weekday;
        startDate = DateTime(now.year, now.month, now.day - (weekDay - 1));
        endDate = startDate.add(const Duration(days: 7));
        break;
      case 'monthly':
        startDate = DateTime(now.year, now.month, 1);
        endDate = DateTime(now.year, now.month + 1, 1);
        break;
      case 'yearly':
        startDate = DateTime(now.year, 1, 1);
        endDate = DateTime(now.year + 1, 1, 1);
        break;
      default:
        return _allTransactions;
    }

    return _allTransactions.where((t) {
      final timestamp = DateTime.tryParse(t['timestamp'] ?? '');
      if (timestamp == null) return false;
      if (timestamp.isBefore(startDate) || timestamp.isAfter(endDate)) return false;
      if (_selectedUser != 'all' && t['processedBy'] != _selectedUser) return false;
      return true;
    }).toList();
  }

  Map<String, dynamic> _calculateStats(List<Map<String, dynamic>> transactions) {
    double totalSales = 0;
    double totalTax = 0;
    int totalItems = 0;
    double totalCashOutAmount = 0;
    double totalServiceFees = 0;
    final salesByUser = <String, double>{};
    final salesByPaymentMethod = <String, double>{};

    for (var t in transactions) {
      // Use actualRevenue if available, otherwise use total (for backward compatibility)
      final actualRevenue = (t['actualRevenue'] as num?)?.toDouble();
      final total = (t['total'] as num?)?.toDouble() ?? 0;
      final revenue = actualRevenue ?? total;

      final tax = (t['tax'] as num?)?.toDouble() ?? 0;
      final user = t['processedBy'] as String? ?? 'Unknown';
      final method = t['paymentMethod'] as String? ?? 'unknown';
      final items = t['items'] as List?;

      // Track cash-out amounts
      final cashOutAmt = (t['totalCashOutAmount'] as num?)?.toDouble() ?? 0;
      final serviceFee = (t['totalServiceFee'] as num?)?.toDouble() ?? 0;
      totalCashOutAmount += cashOutAmt;
      totalServiceFees += serviceFee;

      totalSales += revenue;
      totalTax += tax;
      totalItems += items?.length ?? 0;

      salesByUser[user] = (salesByUser[user] ?? 0) + revenue;
      salesByPaymentMethod[method] = (salesByPaymentMethod[method] ?? 0) + revenue;
    }

    return {
      'totalSales': totalSales,
      'totalTax': totalTax,
      'totalTransactions': transactions.length,
      'totalItems': totalItems,
      'averageTransaction': transactions.isEmpty ? 0 : totalSales / transactions.length,
      'salesByUser': salesByUser,
      'salesByPaymentMethod': salesByPaymentMethod,
      'totalCashOutAmount': totalCashOutAmount,
      'totalServiceFees': totalServiceFees,
    };
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        foregroundColor: _textPrimary,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_accentColor, _accentDark]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.analytics, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'POS Reports',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadTransactions,
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _accentColor,
          labelColor: _accentColor,
          unselectedLabelColor: _textSecondary,
          isScrollable: isMobile,
          tabs: const [
            Tab(text: 'Daily'),
            Tab(text: 'Weekly'),
            Tab(text: 'Monthly'),
            Tab(text: 'Yearly'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _accentColor))
          : Column(
              children: [
                // Filters
                _buildFilters(isMobile),
                // Tab content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildReportView('daily', isMobile),
                      _buildReportView('weekly', isMobile),
                      _buildReportView('monthly', isMobile),
                      _buildReportView('yearly', isMobile),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilters(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardColor,
        border: Border(bottom: BorderSide(color: _textSecondary.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          // Date picker
          Expanded(
            child: InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.dark(
                          primary: _accentColor,
                          onPrimary: Colors.white,
                          surface: _cardColor,
                          onSurface: _textPrimary,
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (picked != null) {
                  setState(() => _selectedDate = picked);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _bgColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _textSecondary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, color: _accentColor, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        DateFormat('MMM dd, yyyy').format(_selectedDate),
                        style: const TextStyle(color: _textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down, color: _textSecondary),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // User filter
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _bgColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _textSecondary.withValues(alpha: 0.3)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedUser,
                  dropdownColor: _cardColor,
                  style: const TextStyle(color: _textPrimary),
                  icon: const Icon(Icons.arrow_drop_down, color: _textSecondary),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All Users')),
                    ..._users.map((user) => DropdownMenuItem(
                      value: user,
                      child: Text(user, overflow: TextOverflow.ellipsis),
                    )),
                  ],
                  onChanged: (value) => setState(() => _selectedUser = value ?? 'all'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportView(String period, bool isMobile) {
    final transactions = _filterTransactions(period);
    final stats = _calculateStats(transactions);
    final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    return RefreshIndicator(
      color: _accentColor,
      backgroundColor: _cardColor,
      onRefresh: _loadTransactions,
      child: CustomScrollView(
        slivers: [
          // Stats cards
          SliverToBoxAdapter(
            child: _buildStatsSection(stats, currencyFormat, isMobile),
          ),
          // Sales by user chart
          if ((stats['salesByUser'] as Map).isNotEmpty)
            SliverToBoxAdapter(
              child: _buildSalesByUserSection(stats['salesByUser'] as Map<String, double>, currencyFormat, isMobile),
            ),
          // Payment methods breakdown
          if ((stats['salesByPaymentMethod'] as Map).isNotEmpty)
            SliverToBoxAdapter(
              child: _buildPaymentMethodsSection(
                stats['salesByPaymentMethod'] as Map<String, double>,
                currencyFormat,
                isMobile,
              ),
            ),
          // Transactions list header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, color: _accentColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Transactions (${transactions.length})',
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Transactions list
          transactions.isEmpty
              ? SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 64, color: _textSecondary.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'No transactions found',
                          style: TextStyle(color: _textSecondary.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildTransactionCard(transactions[index], currencyFormat),
                      childCount: transactions.length,
                    ),
                  ),
                ),
          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _buildStatsSection(Map<String, dynamic> stats, NumberFormat currencyFormat, bool isMobile) {
    final totalCashOut = (stats['totalCashOutAmount'] as num?)?.toDouble() ?? 0;
    final totalServiceFees = (stats['totalServiceFees'] as num?)?.toDouble() ?? 0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _buildStatCard(
            'Total Revenue',
            currencyFormat.format(stats['totalSales']),
            Icons.attach_money,
            _accentColor,
            isMobile,
          ),
          _buildStatCard(
            'Transactions',
            '${stats['totalTransactions']}',
            Icons.receipt,
            Colors.blue,
            isMobile,
          ),
          _buildStatCard(
            'Items Sold',
            '${stats['totalItems']}',
            Icons.inventory_2,
            Colors.green,
            isMobile,
          ),
          _buildStatCard(
            'Avg. Transaction',
            currencyFormat.format(stats['averageTransaction']),
            Icons.trending_up,
            Colors.purple,
            isMobile,
          ),
          _buildStatCard(
            'Total VAT',
            currencyFormat.format(stats['totalTax']),
            Icons.account_balance,
            Colors.teal,
            isMobile,
          ),
          if (totalCashOut > 0) ...[
            _buildStatCard(
              'Cash-Out Given',
              currencyFormat.format(totalCashOut),
              Icons.output,
              Colors.red,
              isMobile,
            ),
            _buildStatCard(
              'Service Fees',
              currencyFormat.format(totalServiceFees),
              Icons.paid,
              Colors.orange,
              isMobile,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, bool isMobile) {
    return Container(
      width: isMobile ? (MediaQuery.of(context).size.width - 44) / 2 : 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            title,
            style: TextStyle(color: _textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesByUserSection(Map<String, double> salesByUser, NumberFormat currencyFormat, bool isMobile) {
    final sortedUsers = salesByUser.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxSale = sortedUsers.isNotEmpty ? sortedUsers.first.value : 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people, color: _accentColor, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Sales by User',
                style: TextStyle(color: _textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...sortedUsers.map((entry) {
            final percentage = (entry.value / maxSale).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          entry.key,
                          style: const TextStyle(color: _textPrimary, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 0,
                        child: Text(
                          currencyFormat.format(entry.value),
                          style: const TextStyle(color: _accentColor, fontWeight: FontWeight.bold, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percentage,
                      backgroundColor: _bgColor,
                      valueColor: const AlwaysStoppedAnimation<Color>(_accentColor),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodsSection(
      Map<String, double> salesByMethod, NumberFormat currencyFormat, bool isMobile) {
    final total = salesByMethod.values.fold(0.0, (a, b) => a + b);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payment, color: _accentColor, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Payment Methods',
                style: TextStyle(color: _textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: salesByMethod.entries.map((entry) {
              final percentage = total > 0 ? (entry.value / total * 100) : 0;
              IconData icon;
              Color color;
              switch (entry.key) {
                case 'cash':
                  icon = Icons.money;
                  color = Colors.green;
                  break;
                case 'card':
                  icon = Icons.credit_card;
                  color = Colors.blue;
                  break;
                case 'gcash':
                  icon = Icons.phone_android;
                  color = Colors.indigo;
                  break;
                default:
                  icon = Icons.payment;
                  color = Colors.grey;
              }
              return Container(
                width: isMobile ? (MediaQuery.of(context).size.width - 76) / 2 : 140,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Icon(icon, color: color, size: 24),
                    const SizedBox(height: 4),
                    Text(
                      entry.key.toUpperCase(),
                      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      currencyFormat.format(entry.value),
                      style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      '${percentage.toStringAsFixed(1)}%',
                      style: TextStyle(color: _textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> transaction, NumberFormat currencyFormat) {
    final timestamp = DateTime.tryParse(transaction['timestamp'] ?? '') ?? DateTime.now();
    final total = (transaction['total'] as num?)?.toDouble() ?? 0;
    final items = transaction['items'] as List? ?? [];
    final paymentMethod = transaction['paymentMethod'] as String? ?? 'unknown';
    final processedBy = transaction['processedBy'] as String? ?? 'Unknown';
    final customerName = transaction['customerName'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _textSecondary.withValues(alpha: 0.1)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        iconColor: _textSecondary,
        collapsedIconColor: _textSecondary,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.receipt, color: _accentColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${transaction['transactionId']}',
                    style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  Text(
                    DateFormat('MMM dd, yyyy hh:mm a').format(timestamp),
                    style: TextStyle(color: _textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            Flexible(
              flex: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    currencyFormat.format(total),
                    style: const TextStyle(color: _accentColor, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getPaymentColor(paymentMethod).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      paymentMethod.toUpperCase(),
                      style: TextStyle(color: _getPaymentColor(paymentMethod), fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        children: [
          // Transaction details
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _bgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('Processed by', processedBy),
                if (customerName.isNotEmpty) _detailRow('Customer', customerName),
                if (transaction['basketOwner'] != null && (transaction['basketOwner'] as String).isNotEmpty)
                  _detailRow('Basket from', transaction['basketOwner']),
                _detailRow('Items', '${items.length} item(s)'),
                const Divider(color: _textSecondary, height: 16),
                ...items.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${item['quantity']}x ${item['name']}',
                              style: const TextStyle(color: _textPrimary, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            currencyFormat.format((item['subtotal'] as num?)?.toDouble() ?? 0),
                            style: TextStyle(color: _textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    )),
                const Divider(color: _textSecondary, height: 16),
                _detailRow('Subtotal', currencyFormat.format((transaction['subtotal'] as num?)?.toDouble() ?? 0)),
                _detailRow('VAT (12%)', currencyFormat.format((transaction['tax'] as num?)?.toDouble() ?? 0)),
                _detailRow('Total', currencyFormat.format(total), isBold: true),
                _detailRow('Cash Received', currencyFormat.format((transaction['cashReceived'] as num?)?.toDouble() ?? 0)),
                _detailRow('Change', currencyFormat.format((transaction['change'] as num?)?.toDouble() ?? 0)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: _textSecondary, fontSize: 12)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                color: isBold ? _accentColor : _textPrimary,
                fontSize: isBold ? 14 : 12,
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
    switch (method) {
      case 'cash':
        return Colors.green;
      case 'card':
        return Colors.blue;
      case 'gcash':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }
}
