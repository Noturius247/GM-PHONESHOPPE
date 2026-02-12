import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/cache_service.dart';
import '../services/pos_settings_service.dart';
import '../utils/snackbar_utils.dart';

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
  String _currentPeriod = 'daily';
  bool _showBarChart = true; // Toggle between bar and line chart
  bool _showItemsBarChart = false; // Toggle between pie chart (payment) and bar chart (items sold)

  // Cash balance tracking (automated)
  double _periodOpeningBalance = 0.0; // Opening balance for the current period (auto-calculated)
  double _totalAdjustments = 0.0; // Total cash adjustments for the period

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
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final newPeriod = ['daily', 'weekly', 'monthly', 'yearly'][_tabController.index];
        if (newPeriod != _currentPeriod) {
          setState(() {
            _currentPeriod = newPeriod;
          });
          _loadPeriodOpeningBalance(); // Reload opening balance for new period
        }
      }
    });
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
      // Load opening balance (float) from Settings
      await _loadPeriodOpeningBalance();

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
        SnackBarUtils.showError(context, 'Error loading transactions: $e');
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
      // Check if timestamp is within the date range (inclusive of start, exclusive of end)
      if (timestamp.isBefore(startDate) || !timestamp.isBefore(endDate)) return false;
      if (_selectedUser != 'all' && t['processedBy'] != _selectedUser) return false;
      return true;
    }).toList();
  }

  void _navigateDate(bool forward) {
    setState(() {
      switch (_currentPeriod) {
        case 'daily':
          _selectedDate = _selectedDate.add(Duration(days: forward ? 1 : -1));
          break;
        case 'weekly':
          _selectedDate = _selectedDate.add(Duration(days: forward ? 7 : -7));
          break;
        case 'monthly':
          _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + (forward ? 1 : -1), 1);
          break;
        case 'yearly':
          _selectedDate = DateTime(_selectedDate.year + (forward ? 1 : -1), 1, 1);
          break;
      }
    });
    // Reload period opening balance for the new date
    _loadPeriodOpeningBalance();
  }

  String _getDateRangeText() {
    switch (_currentPeriod) {
      case 'daily':
        return DateFormat('MMM dd, yyyy').format(_selectedDate);
      case 'weekly':
        final weekDay = _selectedDate.weekday;
        final startOfWeek = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day - (weekDay - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 6));
        return 'Week of ${DateFormat('MMM dd').format(startOfWeek)} - ${DateFormat('MMM dd, yyyy').format(endOfWeek)}';
      case 'monthly':
        return DateFormat('MMMM yyyy').format(_selectedDate);
      case 'yearly':
        return DateFormat('yyyy').format(_selectedDate);
      default:
        return DateFormat('MMM dd, yyyy').format(_selectedDate);
    }
  }

  Future<void> _showContextAwareDatePicker() async {
    switch (_currentPeriod) {
      case 'daily':
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
          _loadPeriodOpeningBalance();
        }
        break;
      case 'weekly':
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          helpText: 'SELECT A DATE IN THE WEEK',
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
          _loadPeriodOpeningBalance();
        }
        break;
      case 'monthly':
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          helpText: 'SELECT ANY DATE IN THE MONTH',
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
          setState(() => _selectedDate = DateTime(picked.year, picked.month, 1));
          _loadPeriodOpeningBalance();
        }
        break;
      case 'yearly':
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          helpText: 'SELECT ANY DATE IN THE YEAR',
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
          setState(() => _selectedDate = DateTime(picked.year, 1, 1));
          _loadPeriodOpeningBalance();
        }
        break;
    }
  }

  Map<String, dynamic> _calculateStats(List<Map<String, dynamic>> transactions) {
    double totalSales = 0;
    double totalTax = 0;
    int totalItems = 0;
    double totalCashOutAmount = 0; // Principal amount
    double totalActualCashGiven = 0; // Actual cash given (after fee deduction for 'deducted' scenarios)
    double totalServiceFees = 0;
    double totalCashIn = 0;
    double cashInServiceFees = 0;
    double cashOutServiceFees = 0;
    double cashInPaidWithCash = 0; // Track cash-in amounts paid with cash (for drawer calculation)
    double cashOutPaidWithCash = 0; // Track cash-out principals received as cash (for drawer calculation)
    final salesByUser = <String, double>{};
    final salesByPaymentMethod = <String, double>{};
    final itemsSoldByName = <String, int>{}; // Track quantity sold by item name
    final itemsRevenueByName = <String, double>{}; // Track revenue by item name

    // Discount tracking
    double totalDiscounts = 0;
    int discountedTransactions = 0;
    final discountsByStaff = <String, double>{}; // Discounts authorized by staff member

    for (var t in transactions) {
      final total = (t['total'] as num?)?.toDouble() ?? 0;
      final tax = (t['tax'] as num?)?.toDouble() ?? 0;
      final user = t['processedBy'] as String? ?? 'Unknown';
      final method = t['paymentMethod'] as String? ?? 'unknown';
      final items = t['items'] as List?;

      // Track cash-out amounts and service fees
      final cashOutAmt = (t['totalCashOutAmount'] as num?)?.toDouble() ?? 0;
      // Use actualCashGiven if available, otherwise fall back to cashOutAmt (for backward compatibility)
      final actualCashGiven = (t['totalActualCashGiven'] as num?)?.toDouble() ?? cashOutAmt;
      final transactionServiceFee = (t['totalServiceFee'] as num?)?.toDouble() ?? 0;

      // Also check item-level for actual cash given (for transactions without totalActualCashGiven)
      double itemLevelActualCashGiven = 0;
      double itemLevelCashInFees = 0;
      double itemLevelCashOutFees = 0;
      double itemLevelCashInAmount = 0; // Track actual cash-in load amounts from items
      // Check transaction-level flags first, then item-level
      bool hasCashInItem = t['hasCashIn'] == true;
      bool hasCashOutItem = t['hasCashOut'] == true;

      double regularItemsRevenue = 0; // Revenue from regular product sales
      double transactionDiscountTotal = 0; // Track total discounts for this transaction

      if (items != null) {
        for (var item in items) {
          final itemMap = item as Map<dynamic, dynamic>;
          final isCashIn = itemMap['isCashIn'] == true;
          final isCashOut = itemMap['isCashOut'] == true;
          final itemServiceFee = (itemMap['serviceFee'] as num?)?.toDouble() ?? 0;
          final itemActualCashGiven = (itemMap['actualCashGiven'] as num?)?.toDouble();
          // cashOutAmount stores the principal amount for BOTH cash-in and cash-out
          final itemCashOutAmount = (itemMap['cashOutAmount'] as num?)?.toDouble() ?? 0;

          // Track discount amounts
          final itemDiscountAmount = (itemMap['discountAmount'] as num?)?.toDouble() ?? 0;
          if (itemDiscountAmount > 0) {
            transactionDiscountTotal += itemDiscountAmount;
          }

          // Track items sold by name (excluding cash-in/cash-out transactions)
          if (!isCashIn && !isCashOut) {
            final itemName = itemMap['name'] as String? ?? 'Unknown Item';
            final itemQty = (itemMap['quantity'] as num?)?.toInt() ?? 1;
            final itemSubtotal = (itemMap['subtotal'] as num?)?.toDouble() ?? 0;

            itemsSoldByName[itemName] = (itemsSoldByName[itemName] ?? 0) + itemQty;
            itemsRevenueByName[itemName] = (itemsRevenueByName[itemName] ?? 0) + itemSubtotal;
            regularItemsRevenue += itemSubtotal;
          }

          if (isCashOut) {
            hasCashOutItem = true;
            // Use actualCashGiven if available, otherwise use cashOutAmount
            itemLevelActualCashGiven += itemActualCashGiven ?? itemCashOutAmount;
            if (itemServiceFee > 0) {
              itemLevelCashOutFees += itemServiceFee;
            }
          } else if (isCashIn) {
            hasCashInItem = true;
            // Use actualCashGiven which represents the actual load customer receives
            // For COUNTER: actualCashGiven = requested amount (fee paid separately)
            // For DEDUCTED: actualCashGiven = requested amount - fee
            // This ensures cash drawer calculation is correct:
            // cashSales (fee) + cashInPaidWithCash (actual load) = total cash received
            final actualLoadGiven = itemActualCashGiven ?? itemCashOutAmount;
            itemLevelCashInAmount += actualLoadGiven;
            if (itemServiceFee > 0) {
              itemLevelCashInFees += itemServiceFee;
            }
          }
        }
      }

      // Calculate correct revenue:
      // Revenue = regular product sales + service fees from cash-in/cash-out
      // This correctly handles both COUNTER and DEDUCTED scenarios
      final storedActualRevenue = (t['actualRevenue'] as num?)?.toDouble();
      final storedCashInAmount = (t['totalCashInAmount'] as num?)?.toDouble();
      double revenue;

      if (hasCashInItem || hasCashOutItem) {
        // Transaction has cash-in/cash-out items
        // Revenue = regular items + service fees (NOT the principal amounts)
        final totalItemServiceFees = itemLevelCashInFees + itemLevelCashOutFees;
        if (storedActualRevenue != null) {
          // Use stored actualRevenue if available
          revenue = storedActualRevenue;
        } else if (totalItemServiceFees > 0 || regularItemsRevenue > 0) {
          // Calculate from items: product sales + service fees
          revenue = regularItemsRevenue + totalItemServiceFees;
        } else {
          // Fallback: use transaction-level service fee only
          revenue = transactionServiceFee;
        }
      } else {
        // Regular transaction without cash-in/cash-out
        revenue = storedActualRevenue ?? total;
      }

      // Use transaction-level service fee if available, otherwise use item-level sum
      final totalTransactionServiceFee = transactionServiceFee > 0
          ? transactionServiceFee
          : (itemLevelCashInFees + itemLevelCashOutFees);

      totalCashOutAmount += cashOutAmt;
      // Use transaction-level actualCashGiven if available, otherwise use item-level sum
      totalActualCashGiven += (t['totalActualCashGiven'] != null) ? actualCashGiven : itemLevelActualCashGiven;
      totalServiceFees += totalTransactionServiceFee;

      // Only count actual cash-in transactions (e-wallet loading)
      // Cash-in is when customer gives cash to load their e-wallet
      if (hasCashInItem) {
        // Use item-level amount if available, otherwise fall back to transaction-level
        final cashInAmount = itemLevelCashInAmount > 0
            ? itemLevelCashInAmount
            : (storedCashInAmount ?? 0);
        totalCashIn += cashInAmount;
        // Track if paid with cash (for drawer calculation)
        if (method == 'cash') {
          cashInPaidWithCash += cashInAmount;
        }
      }

      // Track cash-out transactions paid with cash (for drawer calculation)
      // For cash-out: customer pays principal + fee, we give back principal
      // We need to track the principal received (not just the fee in revenue)
      if (hasCashOutItem && method == 'cash') {
        // Use actualCashGiven which is the amount we give to customer
        final cashOutGiven = (t['totalActualCashGiven'] != null) ? actualCashGiven : itemLevelActualCashGiven;
        cashOutPaidWithCash += cashOutGiven;
      }

      // Separate service fees
      // Always use item-level fees if available for accurate breakdown
      if (itemLevelCashOutFees > 0) {
        cashOutServiceFees += itemLevelCashOutFees;
      }

      if (itemLevelCashInFees > 0) {
        cashInServiceFees += itemLevelCashInFees;
      }

      // Fallback to transaction-level fee only if no item-level fees were found
      // and only one type of cash service exists in the transaction
      if (itemLevelCashOutFees == 0 && itemLevelCashInFees == 0) {
        if (transactionServiceFee > 0) {
          // Use stored transaction-level service fee
          if (hasCashOutItem && !hasCashInItem) {
            // Only cash-out in this transaction
            cashOutServiceFees += transactionServiceFee;
          } else if (hasCashInItem && !hasCashOutItem) {
            // Only cash-in in this transaction
            cashInServiceFees += transactionServiceFee;
          } else if (hasCashInItem && hasCashOutItem) {
            // Both types - split evenly
            final halfFee = transactionServiceFee / 2;
            cashInServiceFees += halfFee;
            cashOutServiceFees += halfFee;
          }
        } else if ((hasCashInItem || hasCashOutItem) && storedActualRevenue != null) {
          // Last resort fallback: For old transactions without serviceFee stored
          // Calculate service fee by subtracting regular items revenue
          // Works for both PURE and MIXED transactions:
          // - PURE: regularItemsRevenue = 0, so fee = actualRevenue
          // - MIXED: fee = actualRevenue - regularItemsRevenue
          final estimatedServiceFee = (storedActualRevenue - regularItemsRevenue).clamp(0.0, double.infinity);

          if (estimatedServiceFee > 0) {
            if (hasCashOutItem && !hasCashInItem) {
              // Only cash-out
              cashOutServiceFees += estimatedServiceFee;
            } else if (hasCashInItem && !hasCashOutItem) {
              // Only cash-in
              cashInServiceFees += estimatedServiceFee;
            } else if (hasCashInItem && hasCashOutItem) {
              // Both types - split evenly
              final halfFee = estimatedServiceFee / 2;
              cashInServiceFees += halfFee;
              cashOutServiceFees += halfFee;
            }
          }
        }
      }

      // Track discount stats
      if (transactionDiscountTotal > 0) {
        totalDiscounts += transactionDiscountTotal;
        discountedTransactions++;

        // Track discounts by staff who authorized them
        final discountAuthorizer = t['discountAuthorizedBy'] as String? ?? 'Unknown';
        discountsByStaff[discountAuthorizer] = (discountsByStaff[discountAuthorizer] ?? 0) + transactionDiscountTotal;
      }

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
      'totalCashOutAmount': totalCashOutAmount, // Principal amount (kept for backward compatibility)
      'totalActualCashGiven': totalActualCashGiven, // Actual cash given after deductions
      'totalServiceFees': totalServiceFees,
      'totalCashIn': totalCashIn,
      'cashInServiceFees': cashInServiceFees,
      'cashOutServiceFees': cashOutServiceFees,
      'cashInPaidWithCash': cashInPaidWithCash, // Cash-in paid with cash (for drawer calculation)
      'cashOutPaidWithCash': cashOutPaidWithCash, // Cash-out principals received as cash (for drawer calculation)
      'itemsSoldByName': itemsSoldByName, // Quantity sold by item name
      'itemsRevenueByName': itemsRevenueByName, // Revenue by item name
      // Discount analytics
      'totalDiscounts': totalDiscounts,
      'discountedTransactions': discountedTransactions,
      'discountsByStaff': discountsByStaff,
      'averageDiscount': discountedTransactions > 0 ? totalDiscounts / discountedTransactions : 0,
    };
  }

  List<Map<String, dynamic>> _getChartData() {
    final chartData = <Map<String, dynamic>>[];

    switch (_currentPeriod) {
      case 'daily':
        // Show data for past 7 days
        for (int i = 6; i >= 0; i--) {
          final date = DateTime.now().subtract(Duration(days: i));
          final dayStart = DateTime(date.year, date.month, date.day);
          final dayEnd = dayStart.add(const Duration(days: 1));

          final dayTransactions = _allTransactions.where((t) {
            final timestamp = DateTime.tryParse(t['timestamp'] ?? '');
            if (timestamp == null) return false;
            return !timestamp.isBefore(dayStart) && timestamp.isBefore(dayEnd);
          }).toList();

          double totalSales = 0;
          for (var t in dayTransactions) {
            final actualRevenue = (t['actualRevenue'] as num?)?.toDouble();
            final total = (t['total'] as num?)?.toDouble() ?? 0;
            totalSales += actualRevenue ?? total;
          }

          chartData.add({
            'label': DateFormat('EEE').format(date),
            'fullLabel': DateFormat('MMM dd').format(date),
            'value': totalSales,
            'date': date,
          });
        }
        break;

      case 'weekly':
        // Show data for past 8 weeks
        for (int i = 7; i >= 0; i--) {
          final date = DateTime.now().subtract(Duration(days: i * 7));
          final weekDay = date.weekday;
          final weekStart = DateTime(date.year, date.month, date.day - (weekDay - 1));
          final weekEnd = weekStart.add(const Duration(days: 7));

          final weekTransactions = _allTransactions.where((t) {
            final timestamp = DateTime.tryParse(t['timestamp'] ?? '');
            if (timestamp == null) return false;
            return !timestamp.isBefore(weekStart) && timestamp.isBefore(weekEnd);
          }).toList();

          double totalSales = 0;
          for (var t in weekTransactions) {
            final actualRevenue = (t['actualRevenue'] as num?)?.toDouble();
            final total = (t['total'] as num?)?.toDouble() ?? 0;
            totalSales += actualRevenue ?? total;
          }

          chartData.add({
            'label': 'W${i == 0 ? 'now' : '-$i'}',
            'fullLabel': 'Week of ${DateFormat('MMM dd').format(weekStart)}',
            'value': totalSales,
            'date': weekStart,
          });
        }
        break;

      case 'monthly':
        // Show data for past 12 months
        for (int i = 11; i >= 0; i--) {
          final date = DateTime(DateTime.now().year, DateTime.now().month - i, 1);
          final monthStart = DateTime(date.year, date.month, 1);
          final monthEnd = DateTime(date.year, date.month + 1, 1);

          final monthTransactions = _allTransactions.where((t) {
            final timestamp = DateTime.tryParse(t['timestamp'] ?? '');
            if (timestamp == null) return false;
            return !timestamp.isBefore(monthStart) && timestamp.isBefore(monthEnd);
          }).toList();

          double totalSales = 0;
          for (var t in monthTransactions) {
            final actualRevenue = (t['actualRevenue'] as num?)?.toDouble();
            final total = (t['total'] as num?)?.toDouble() ?? 0;
            totalSales += actualRevenue ?? total;
          }

          chartData.add({
            'label': DateFormat('MMM').format(date),
            'fullLabel': DateFormat('MMMM yyyy').format(date),
            'value': totalSales,
            'date': date,
          });
        }
        break;

      case 'yearly':
        // Show data for past 5 years
        for (int i = 4; i >= 0; i--) {
          final year = DateTime.now().year - i;
          final yearStart = DateTime(year, 1, 1);
          final yearEnd = DateTime(year + 1, 1, 1);

          final yearTransactions = _allTransactions.where((t) {
            final timestamp = DateTime.tryParse(t['timestamp'] ?? '');
            if (timestamp == null) return false;
            return !timestamp.isBefore(yearStart) && timestamp.isBefore(yearEnd);
          }).toList();

          double totalSales = 0;
          for (var t in yearTransactions) {
            final actualRevenue = (t['actualRevenue'] as num?)?.toDouble();
            final total = (t['total'] as num?)?.toDouble() ?? 0;
            totalSales += actualRevenue ?? total;
          }

          chartData.add({
            'label': year.toString(),
            'fullLabel': year.toString(),
            'value': totalSales,
            'date': yearStart,
          });
        }
        break;
    }

    return chartData;
  }

  Widget _buildSwitchableChart(List<Map<String, dynamic>> chartData, NumberFormat currencyFormat) {
    if (chartData.isEmpty || chartData.every((d) => (d['value'] as double) == 0)) {
      return _buildNoChartData();
    }

    final screenWidth = MediaQuery.of(context).size.width;

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
          // Header with toggle button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(screenWidth < 360 ? 6 : 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _accentColor.withValues(alpha: 0.2),
                            _accentDark.withValues(alpha: 0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _showBarChart ? Icons.bar_chart : Icons.show_chart,
                        color: _accentColor,
                        size: screenWidth < 360 ? 16 : 20,
                      ),
                    ),
                    SizedBox(width: screenWidth < 360 ? 8 : 12),
                    Flexible(
                      child: Text(
                        _showBarChart ? 'SALES TREND' : 'SALES PERFORMANCE',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: screenWidth < 360 ? 10 : 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: screenWidth < 360 ? 0.8 : 1.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
              // Toggle button
              Container(
                decoration: BoxDecoration(
                  color: _bgColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _accentColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => setState(() => _showBarChart = true),
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _showBarChart ? _accentColor.withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.bar_chart,
                              size: 16,
                              color: _showBarChart ? _accentColor : _textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Bar',
                              style: TextStyle(
                                color: _showBarChart ? _accentColor : _textSecondary,
                                fontSize: screenWidth < 360 ? 10 : 12,
                                fontWeight: _showBarChart ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _showBarChart = false),
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: !_showBarChart ? _accentColor.withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.show_chart,
                              size: 16,
                              color: !_showBarChart ? _accentColor : _textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Line',
                              style: TextStyle(
                                color: !_showBarChart ? _accentColor : _textSecondary,
                                fontSize: screenWidth < 360 ? 10 : 12,
                                fontWeight: !_showBarChart ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Chart content
          SizedBox(
            height: screenWidth < 360 ? 160 : 200,
            child: _showBarChart
                ? _buildBarChartContent(chartData, currencyFormat)
                : _buildLineChartContent(chartData, currencyFormat),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChartContent(List<Map<String, dynamic>> chartData, NumberFormat currencyFormat) {
    final maxY = chartData.map((d) => d['value'] as double).reduce((a, b) => a > b ? a : b);
    final interval = maxY > 0 ? (maxY / 5).ceilToDouble() : 1.0;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY * 1.2,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => _cardColor.withValues(alpha: 0.9),
            tooltipPadding: const EdgeInsets.all(8),
            tooltipMargin: 8,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final data = chartData[group.x.toInt()];
              return BarTooltipItem(
                '${data['fullLabel']}\n',
                const TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                children: [
                  TextSpan(
                    text: currencyFormat.format(rod.toY.toDouble()),
                    style: const TextStyle(color: _accentColor, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < chartData.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      chartData[value.toInt()]['label'],
                      style: const TextStyle(color: _textSecondary, fontSize: 10),
                    ),
                  );
                }
                return const Text('');
              },
              reservedSize: 30,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: interval,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const Text('');
                return Text(
                  '₱${(value.toDouble() / 1000).toStringAsFixed(0)}k',
                  style: const TextStyle(color: _textSecondary, fontSize: 10),
                );
              },
              reservedSize: 40,
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: _textSecondary.withValues(alpha: 0.1),
              strokeWidth: 1,
            );
          },
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(
          chartData.length,
          (index) => BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: chartData[index]['value'] as double,
                gradient: const LinearGradient(
                  colors: [_accentColor, _accentDark],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
                width: 16,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLineChartContent(List<Map<String, dynamic>> chartData, NumberFormat currencyFormat) {
    final maxY = chartData.map((d) => d['value'] as double).reduce((a, b) => a > b ? a : b);
    final interval = maxY > 0 ? (maxY / 5).ceilToDouble() : 1.0;

    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => _cardColor.withValues(alpha: 0.9),
            tooltipPadding: const EdgeInsets.all(8),
            tooltipMargin: 8,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final data = chartData[spot.x.toInt()];
                return LineTooltipItem(
                  '${data['fullLabel']}\n',
                  const TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                  children: [
                    TextSpan(
                      text: currencyFormat.format(spot.y.toDouble()),
                      style: const TextStyle(color: _accentColor, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: _textSecondary.withValues(alpha: 0.1),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < chartData.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      chartData[value.toInt()]['label'],
                      style: const TextStyle(color: _textSecondary, fontSize: 10),
                    ),
                  );
                }
                return const Text('');
              },
              reservedSize: 30,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: interval,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const Text('');
                return Text(
                  '₱${(value.toDouble() / 1000).toStringAsFixed(0)}k',
                  style: const TextStyle(color: _textSecondary, fontSize: 10),
                );
              },
              reservedSize: 40,
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (chartData.length - 1).toDouble(),
        minY: 0,
        maxY: maxY * 1.2,
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(
              chartData.length,
              (index) => FlSpot(index.toDouble(), chartData[index]['value'] as double),
            ),
            isCurved: true,
            gradient: const LinearGradient(colors: [_accentColor, _accentDark]),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 4,
                  color: _accentColor,
                  strokeWidth: 2,
                  strokeColor: _cardColor,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  _accentColor.withValues(alpha: 0.3),
                  _accentColor.withValues(alpha: 0.05),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }


  /// Switchable widget between Payment Distribution (Pie) and Items Sold (Bar)
  Widget _buildSwitchableDistributionChart(
    Map<String, double> salesByMethod,
    Map<String, int> itemsSoldByName,
    NumberFormat currencyFormat,
  ) {
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
          // Header with toggle
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _accentColor.withValues(alpha: 0.2),
                      _accentDark.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _showItemsBarChart ? Icons.bar_chart : Icons.pie_chart,
                  color: _accentColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _showItemsBarChart ? 'TOP SELLING ITEMS' : 'PAYMENT DISTRIBUTION',
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              // Toggle button
              Container(
                decoration: BoxDecoration(
                  color: _bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildChartToggleButton(
                      icon: Icons.pie_chart,
                      label: 'Payment',
                      isSelected: !_showItemsBarChart,
                      onTap: () => setState(() => _showItemsBarChart = false),
                    ),
                    _buildChartToggleButton(
                      icon: Icons.bar_chart,
                      label: 'Items',
                      isSelected: _showItemsBarChart,
                      onTap: () => setState(() => _showItemsBarChart = true),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Chart content
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _showItemsBarChart
                ? _buildItemsSoldBarChart(itemsSoldByName, currencyFormat)
                : _buildPieChartContent(salesByMethod, currencyFormat),
          ),
        ],
      ),
    );
  }

  Widget _buildChartToggleButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _accentColor.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? _accentColor : _textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? _accentColor : _textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pie chart content (payment distribution)
  Widget _buildPieChartContent(Map<String, double> salesByMethod, NumberFormat currencyFormat) {
    if (salesByMethod.isEmpty) {
      return _buildNoChartDataContent();
    }

    final total = salesByMethod.values.fold(0.0, (a, b) => a + b);
    if (total == 0) {
      return _buildNoChartDataContent();
    }

    final colors = {
      'cash': Colors.green,
      'card': Colors.blue,
      'gcash': Colors.indigo,
      'gcash/maya': Colors.purple,
    };

    return SizedBox(
      height: 200,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: PieChart(
              PieChartData(
                pieTouchData: PieTouchData(
                  touchCallback: (FlTouchEvent event, pieTouchResponse) {},
                ),
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: List.generate(
                  salesByMethod.length,
                  (index) {
                    final entry = salesByMethod.entries.elementAt(index);
                    final percentage = (entry.value / total * 100);
                    final color = colors[entry.key] ?? Colors.grey;

                    return PieChartSectionData(
                      color: color,
                      value: entry.value,
                      title: '${percentage.toStringAsFixed(1)}%',
                      radius: 50,
                      titleStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: salesByMethod.entries.map((entry) {
                final color = colors[entry.key] ?? Colors.grey;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.key.toUpperCase(),
                              style: const TextStyle(
                                color: _textPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              currencyFormat.format(entry.value),
                              style: TextStyle(
                                color: _textSecondary,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// Bar chart showing top selling items
  Widget _buildItemsSoldBarChart(Map<String, int> itemsSoldByName, NumberFormat currencyFormat) {
    if (itemsSoldByName.isEmpty) {
      return _buildNoChartDataContent();
    }

    // Sort items by quantity sold (descending) and take top 10
    final sortedItems = itemsSoldByName.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topItems = sortedItems.take(10).toList();

    if (topItems.isEmpty) {
      return _buildNoChartDataContent();
    }

    final maxValue = topItems.first.value.toDouble();

    // Generate colors for bars
    final barColors = [
      _accentColor,
      Colors.blue,
      Colors.green,
      Colors.purple,
      Colors.teal,
      Colors.orange,
      Colors.pink,
      Colors.cyan,
      Colors.amber,
      Colors.indigo,
    ];

    return SizedBox(
      height: topItems.length * 45.0 + 20,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxValue * 1.2,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => _cardColor,
              tooltipPadding: const EdgeInsets.all(8),
              tooltipMargin: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final item = topItems[group.x.toInt()];
                return BarTooltipItem(
                  '${item.key}\n${item.value} sold',
                  const TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < topItems.length) {
                    // Truncate long names
                    String name = topItems[index].key;
                    if (name.length > 8) {
                      name = '${name.substring(0, 6)}..';
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: _textSecondary,
                          fontSize: 9,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
                reservedSize: 32,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 35,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxValue / 4,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: _textSecondary.withValues(alpha: 0.1),
                strokeWidth: 1,
              );
            },
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(
            topItems.length,
            (index) {
              final item = topItems[index];
              return BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: item.value.toDouble(),
                    color: barColors[index % barColors.length],
                    width: 20,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildNoChartDataContent() {
    return SizedBox(
      height: 150,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, color: _textSecondary.withValues(alpha: 0.5), size: 48),
            const SizedBox(height: 8),
            Text(
              'No data available',
              style: TextStyle(color: _textSecondary.withValues(alpha: 0.7), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoChartData() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.bar_chart_outlined, size: 48, color: _textSecondary.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(
              'No data available',
              style: TextStyle(color: _textSecondary.withValues(alpha: 0.5), fontSize: 14),
            ),
          ],
        ),
      ),
    );
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
              padding: EdgeInsets.all(screenWidth < 360 ? 6 : 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_accentColor, _accentDark]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.analytics, color: Colors.white, size: screenWidth < 360 ? 16 : 20),
            ),
            SizedBox(width: screenWidth < 360 ? 8 : 12),
            Flexible(
              child: Text(
                'POS Reports',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: screenWidth < 360 ? 16 : 20,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
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
          : TabBarView(
              controller: _tabController,
              children: [
                _buildReportView('daily', isMobile),
                _buildReportView('weekly', isMobile),
                _buildReportView('monthly', isMobile),
                _buildReportView('yearly', isMobile),
              ],
            ),
    );
  }

  Widget _buildFilters(bool isMobile) {
    // Compact filter bar with user and date on one line
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _textSecondary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          // User Filter (compact dropdown)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _bgColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _accentColor.withValues(alpha: 0.2)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedUser,
                dropdownColor: _cardColor,
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                icon: Icon(
                  Icons.arrow_drop_down,
                  color: _accentColor.withValues(alpha: 0.7),
                  size: 18,
                ),
                isDense: true,
                items: [
                  DropdownMenuItem(
                    value: 'all',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people, size: 14, color: _accentColor.withValues(alpha: 0.7)),
                        const SizedBox(width: 6),
                        const Text('All', style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                  ..._users.map((user) => DropdownMenuItem(
                    value: user,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person, size: 14, color: _textSecondary.withValues(alpha: 0.6)),
                        const SizedBox(width: 6),
                        Text(
                          user.length > 10 ? '${user.substring(0, 10)}...' : user,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  )),
                ],
                onChanged: (value) => setState(() => _selectedUser = value ?? 'all'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Previous button
          InkWell(
            onTap: () => _navigateDate(false),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _bgColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _accentColor.withValues(alpha: 0.2)),
              ),
              child: const Icon(Icons.chevron_left, color: _accentColor, size: 18),
            ),
          ),
          const SizedBox(width: 6),
          // Date picker (expanded)
          Expanded(
            child: InkWell(
              onTap: _showContextAwareDatePicker,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _accentColor.withValues(alpha: 0.12),
                      _accentDark.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _accentColor.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_today, color: _accentColor, size: 14),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _getDateRangeText(),
                        style: const TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down, color: _accentColor.withValues(alpha: 0.7), size: 16),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Next button
          InkWell(
            onTap: _canNavigateForward() ? () => _navigateDate(true) : null,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _bgColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _canNavigateForward()
                      ? _accentColor.withValues(alpha: 0.2)
                      : _textSecondary.withValues(alpha: 0.1),
                ),
              ),
              child: Icon(
                Icons.chevron_right,
                color: _canNavigateForward() ? _accentColor : _textSecondary.withValues(alpha: 0.3),
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _canNavigateForward() {
    final now = DateTime.now();
    switch (_currentPeriod) {
      case 'daily':
        final tomorrow = _selectedDate.add(const Duration(days: 1));
        return tomorrow.isBefore(now) ||
               (tomorrow.year == now.year && tomorrow.month == now.month && tomorrow.day == now.day);
      case 'weekly':
        final nextWeek = _selectedDate.add(const Duration(days: 7));
        return nextWeek.isBefore(now);
      case 'monthly':
        final nextMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
        return nextMonth.isBefore(now) ||
               (nextMonth.year == now.year && nextMonth.month == now.month);
      case 'yearly':
        final nextYear = DateTime(_selectedDate.year + 1, 1, 1);
        return nextYear.year <= now.year;
      default:
        return false;
    }
  }

  Widget _buildReportView(String period, bool isMobile) {
    final transactions = _filterTransactions(period);
    final stats = _calculateStats(transactions);
    final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final chartData = _getChartData();

    return RefreshIndicator(
      color: _accentColor,
      backgroundColor: _cardColor,
      onRefresh: _loadTransactions,
      child: CustomScrollView(
        slivers: [
          // Filters at the very top (compact bar with user + date picker)
          SliverToBoxAdapter(
            child: _buildFilters(isMobile),
          ),
          // Switchable Chart (Bar/Line) - Sales Trend
          SliverToBoxAdapter(
            child: _buildSwitchableChart(chartData, currencyFormat),
          ),
          // Switchable Distribution Chart (Pie/Bar) - Always show
          SliverToBoxAdapter(
            child: _buildSwitchableDistributionChart(
              stats['salesByPaymentMethod'] as Map<String, double>,
              stats['itemsSoldByName'] as Map<String, int>,
              currencyFormat,
            ),
          ),
          // Stats cards
          SliverToBoxAdapter(
            child: _buildStatsSection(stats, currencyFormat, isMobile),
          ),
          // Discount Analytics Section
          if (stats['totalDiscounts'] > 0)
            SliverToBoxAdapter(
              child: _buildDiscountAnalyticsSection(stats, currencyFormat, isMobile),
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
          // Discounts by staff breakdown
          if ((stats['discountsByStaff'] as Map).isNotEmpty)
            SliverToBoxAdapter(
              child: _buildDiscountsByStaffSection(
                stats['discountsByStaff'] as Map<String, double>,
                currencyFormat,
                isMobile,
              ),
            ),
          // Cash Drawer Summary
          SliverToBoxAdapter(
            child: _buildCashDrawerSummary(stats, currencyFormat),
          ),
          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _buildStatsSection(Map<String, dynamic> stats, NumberFormat currencyFormat, bool isMobile) {
    // Use actualCashGiven for display (shows actual cash given after fee deduction)
    // Fall back to totalCashOutAmount for backward compatibility with old transactions
    final totalActualCashGiven = (stats['totalActualCashGiven'] as num?)?.toDouble() ?? 0;
    final totalCashOutAmount = (stats['totalCashOutAmount'] as num?)?.toDouble() ?? 0;
    final totalCashOut = totalActualCashGiven > 0 ? totalActualCashGiven : totalCashOutAmount;
    final totalServiceFees = (stats['totalServiceFees'] as num?)?.toDouble() ?? 0;
    final totalCashIn = (stats['totalCashIn'] as num?)?.toDouble() ?? 0;
    final cashInFees = (stats['cashInServiceFees'] as num?)?.toDouble() ?? 0;
    final cashOutFees = (stats['cashOutServiceFees'] as num?)?.toDouble() ?? 0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _accentColor.withValues(alpha: 0.2),
                      _accentDark.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.assessment, color: _accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'STATISTICS',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Stats Cards
          Wrap(
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
          // Payment Method Cards
          ..._buildPaymentMethodCards(stats['salesByPaymentMethod'] as Map<String, double>, currencyFormat, isMobile),
          if (totalCashIn > 0)
            _buildStatCard(
              'Cash In',
              currencyFormat.format(totalCashIn),
              Icons.input,
              Colors.greenAccent,
              isMobile,
            ),
          if (totalCashOut > 0)
            _buildStatCard(
              'Cash Out',
              currencyFormat.format(totalCashOut),
              Icons.output,
              Colors.red,
              isMobile,
            ),
          if (cashInFees > 0 || cashOutFees > 0)
            _buildServiceFeesCard(
              cashInFees: cashInFees,
              cashOutFees: cashOutFees,
              totalFees: totalServiceFees,
              currencyFormat: currencyFormat,
              isMobile: isMobile,
            ),
        ],
      ),
        ],
      ),
    );
  }

  Widget _buildDiscountAnalyticsSection(Map<String, dynamic> stats, NumberFormat currencyFormat, bool isMobile) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.orange.withValues(alpha: 0.2),
                      Colors.deepOrange.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.discount, color: Colors.orange, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'DISCOUNT ANALYTICS',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Discount Stats Cards
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildStatCard(
                'Total Discounts',
                currencyFormat.format(stats['totalDiscounts']),
                Icons.discount,
                Colors.orange,
                isMobile,
              ),
              _buildStatCard(
                'Discounted Sales',
                '${stats['discountedTransactions']}',
                Icons.local_offer,
                Colors.amber,
                isMobile,
              ),
              _buildStatCard(
                'Avg. Discount',
                currencyFormat.format(stats['averageDiscount']),
                Icons.percent,
                Colors.deepOrange,
                isMobile,
              ),
            ],
          ),
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
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPaymentMethodCards(Map<String, double> salesByMethod, NumberFormat currencyFormat, bool isMobile) {
    final cards = <Widget>[];

    // Cash payments
    final cashTotal = salesByMethod['cash'] ?? 0;
    if (cashTotal > 0) {
      cards.add(_buildStatCard(
        'Cash Sales',
        currencyFormat.format(cashTotal),
        Icons.money,
        Colors.green,
        isMobile,
      ));
    }

    // Card payments
    final cardTotal = salesByMethod['card'] ?? 0;
    if (cardTotal > 0) {
      cards.add(_buildStatCard(
        'Card Sales',
        currencyFormat.format(cardTotal),
        Icons.credit_card,
        Colors.indigo,
        isMobile,
      ));
    }

    // GCash/Maya payments
    final gcashMayaTotal = salesByMethod['gcash/maya'] ?? 0;
    if (gcashMayaTotal > 0) {
      cards.add(_buildStatCard(
        'GCash/Maya',
        currencyFormat.format(gcashMayaTotal),
        Icons.phone_android,
        Colors.cyan,
        isMobile,
      ));
    }

    return cards;
  }

  Widget _buildServiceFeesCard({
    required double cashInFees,
    required double cashOutFees,
    required double totalFees,
    required NumberFormat currencyFormat,
    required bool isMobile,
  }) {
    return Container(
      width: isMobile ? (MediaQuery.of(context).size.width - 44) : 340,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.paid, color: Colors.orange, size: 24),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Service Fees',
                  style: TextStyle(color: _textSecondary, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (cashInFees > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.input, color: Colors.greenAccent.withValues(alpha: 0.7), size: 16),
                      const SizedBox(width: 4),
                      const Text(
                        'Cash In Fee',
                        style: TextStyle(color: _textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                  Text(
                    currencyFormat.format(cashInFees),
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          if (cashOutFees > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.output, color: Colors.red.withValues(alpha: 0.7), size: 16),
                      const SizedBox(width: 4),
                      const Text(
                        'Cash Out Fee',
                        style: TextStyle(color: _textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                  Text(
                    currencyFormat.format(cashOutFees),
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(color: Colors.orange, height: 12, thickness: 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Fees',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                currencyFormat.format(totalFees),
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _accentColor.withValues(alpha: 0.2),
                      _accentDark.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.people, color: _accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'SALES BY USER',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _accentColor.withValues(alpha: 0.2),
                      _accentDark.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.payment, color: _accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'PAYMENT METHODS',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
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

  Widget _buildDiscountsByStaffSection(Map<String, double> discountsByStaff, NumberFormat currencyFormat, bool isMobile) {
    if (discountsByStaff.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedStaff = discountsByStaff.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxDiscount = sortedStaff.isNotEmpty ? sortedStaff.first.value : 1;

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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.orange.withValues(alpha: 0.2),
                      Colors.deepOrange.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.discount, color: Colors.orange, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'DISCOUNTS BY STAFF',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...sortedStaff.map((entry) {
            final percentage = (entry.value / maxDiscount).clamp(0.0, 1.0);
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
                          style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13),
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
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
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

  Widget _buildCashDrawerSummary(Map<String, dynamic> stats, NumberFormat currencyFormat) {
    // Opening balance is always the "float" from Settings (since sales are collected daily)
    final openingBalance = _periodOpeningBalance;

    // Total Revenue from stats (all payment methods)
    final totalRevenue = (stats['totalSales'] as num?)?.toDouble() ?? 0;

    // Cash sales ONLY (for drawer calculation)
    final salesByPaymentMethod = stats['salesByPaymentMethod'] as Map<String, double>? ?? {};
    final cashSalesOnly = salesByPaymentMethod['cash'] ?? 0;

    // Cash In for display (all e-wallet loading)
    final totalCashIn = (stats['totalCashIn'] as num?)?.toDouble() ?? 0;

    // Cash In paid with CASH only (for drawer calculation)
    final cashInPaidWithCash = (stats['cashInPaidWithCash'] as num?)?.toDouble() ?? 0;

    // Cash Out principals received as CASH (for drawer calculation)
    final cashOutPaidWithCash = (stats['cashOutPaidWithCash'] as num?)?.toDouble() ?? 0;

    // Cash Out (money given to customers - use actualCashGiven for deducted scenario)
    final totalActualCashGiven = (stats['totalActualCashGiven'] as num?)?.toDouble() ?? 0;
    final totalCashOutAmount = (stats['totalCashOutAmount'] as num?)?.toDouble() ?? 0;
    final cashOut = totalActualCashGiven > 0 ? totalActualCashGiven : totalCashOutAmount;

    // For DAILY: Closing = Opening + Cash Sales + Cash In/Out principals (cash) - Cash Out (all)
    // For WEEKLY/MONTHLY/YEARLY: Show net cash flow (total collected over period)
    final bool isDaily = _currentPeriod == 'daily';

    // Daily closing balance (what's in drawer before collection)
    // Formula: Opening + Cash Sales + Cash In principals (cash) + Cash Out principals (cash) - ALL Cash Out given
    // For cash-out paid with cash: receive principal + fee, give principal → net = fee ✓
    // For cash-out paid with GCash: receive 0, give principal → net = -principal ✓
    final dailyClosing = openingBalance + cashSalesOnly + cashInPaidWithCash + cashOutPaidWithCash - cashOut + _totalAdjustments;

    // Net cash collected (what you take out at end of day = closing - opening)
    final netCashFlow = cashSalesOnly + cashInPaidWithCash + cashOutPaidWithCash - cashOut + _totalAdjustments;

    // Get period label for display
    String periodLabel;
    switch (_currentPeriod) {
      case 'daily':
        periodLabel = DateFormat('MMM d, yyyy').format(_selectedDate);
        break;
      case 'weekly':
        final weekday = _selectedDate.weekday;
        final startOfWeek = _selectedDate.subtract(Duration(days: weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 6));
        periodLabel = '${DateFormat('MMM d').format(startOfWeek)} - ${DateFormat('MMM d, yyyy').format(endOfWeek)}';
        break;
      case 'monthly':
        periodLabel = DateFormat('MMMM yyyy').format(_selectedDate);
        break;
      case 'yearly':
        periodLabel = 'Year ${_selectedDate.year}';
        break;
      default:
        periodLabel = '';
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF27AE60).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CASH DRAWER SUMMARY',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      periodLabel,
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // For Daily: Show drawer flow
          if (isDaily) ...[
            _buildCashDrawerRow('Opening Balance (Float)', openingBalance, currencyFormat, Colors.blue),
            const Divider(color: _textSecondary, height: 24),

            // Additions (money coming in)
            const Text(
              'ADDITIONS (+)',
              style: TextStyle(color: _textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildCashDrawerRow('Total Revenue', totalRevenue, currencyFormat, Colors.green),
            if (totalCashIn > 0)
              _buildCashDrawerRow('Cash In (E-wallet)', totalCashIn, currencyFormat, Colors.green),
            if (_totalAdjustments > 0)
              _buildCashDrawerRow('Cash Adjustments (+)', _totalAdjustments, currencyFormat, Colors.cyan),

            const SizedBox(height: 12),
            // Deductions (money going out)
            const Text(
              'DEDUCTIONS (-)',
              style: TextStyle(color: _textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildCashDrawerRow('Cash Out Given', cashOut, currencyFormat, Colors.red, isNegative: true),
            if (_totalAdjustments < 0)
              _buildCashDrawerRow('Cash Adjustments (-)', _totalAdjustments.abs(), currencyFormat, Colors.orange, isNegative: true),

            const Divider(color: _textSecondary, height: 24),

            // Closing balance (what's in drawer)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF27AE60).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF27AE60).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.account_balance_wallet, color: Color(0xFF27AE60), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Closing Balance',
                          style: TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    currencyFormat.format(dailyClosing),
                    style: const TextStyle(
                      color: Color(0xFF27AE60),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Amount to collect
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _accentColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.savings, color: _accentColor, size: 20),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'To Collect (Closing - Float)',
                            style: TextStyle(
                              color: _textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    currencyFormat.format(netCashFlow),
                    style: const TextStyle(
                      color: _accentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Collect ${currencyFormat.format(netCashFlow)} at end of day. Leave ${currencyFormat.format(openingBalance)} as float for tomorrow.',
              style: TextStyle(
                color: _textSecondary.withValues(alpha: 0.7),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ] else ...[
            // For Weekly/Monthly/Yearly: Show totals and net collected
            _buildCashDrawerRow('Daily Float (from Settings)', openingBalance, currencyFormat, Colors.blue),
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: Text(
                'Same float used each day',
                style: TextStyle(
                  color: _textSecondary.withValues(alpha: 0.6),
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const Divider(color: _textSecondary, height: 24),

            // Period totals
            const Text(
              'PERIOD TOTALS',
              style: TextStyle(color: _textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildCashDrawerRow('Total Revenue', totalRevenue, currencyFormat, Colors.green),
            if (totalCashIn > 0)
              _buildCashDrawerRow('Total Cash In', totalCashIn, currencyFormat, Colors.green),
            _buildCashDrawerRow('Total Cash Out', cashOut, currencyFormat, Colors.red, isNegative: true),
            if (_totalAdjustments != 0)
              _buildCashDrawerRow(
                'Total Adjustments',
                _totalAdjustments.abs(),
                currencyFormat,
                _totalAdjustments > 0 ? Colors.cyan : Colors.orange,
                isNegative: _totalAdjustments < 0,
              ),

            const Divider(color: _textSecondary, height: 24),

            // Total collected over period
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _accentColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.savings, color: _accentColor, size: 20),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Total Collected',
                            style: TextStyle(
                              color: _textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    currencyFormat.format(netCashFlow),
                    style: const TextStyle(
                      color: _accentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Total cash collected over this ${_currentPeriod == 'weekly' ? 'week' : _currentPeriod == 'monthly' ? 'month' : 'year'} (after leaving float each day).',
              style: TextStyle(
                color: _textSecondary.withValues(alpha: 0.7),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCashDrawerRow(String label, double amount, NumberFormat currencyFormat, Color color, {bool isNegative = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: _textPrimary, fontSize: 13),
          ),
          Text(
            '${isNegative ? "- " : ""}${currencyFormat.format(amount)}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // CASH BALANCE METHODS
  // ============================================

  Future<void> _loadPeriodOpeningBalance() async {
    // Get opening balance for the selected date
    // - Past dates: Uses saved history (remembers what float was that day)
    // - Today/future: Uses current Settings value
    final balance = await POSSettingsService.getOpeningBalanceForDate(_selectedDate);

    // Get adjustments for the period (if any)
    final adjustments = await _getTotalAdjustmentsForPeriod();

    if (mounted) {
      setState(() {
        _periodOpeningBalance = balance;
        _totalAdjustments = adjustments;
      });
    }

    // Auto-save today's float if there are transactions (so it's remembered)
    await _autoSaveTodaysFloat();
  }

  // Save today's float to history so it's remembered for future reports
  Future<void> _autoSaveTodaysFloat() async {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    // Check if today has any transactions
    final todayTransactions = _allTransactions.where((t) {
      final timestamp = DateTime.tryParse(t['timestamp'] ?? '');
      if (timestamp == null) return false;
      return timestamp.year == todayOnly.year &&
          timestamp.month == todayOnly.month &&
          timestamp.day == todayOnly.day;
    }).toList();

    // If there are transactions today, save the float
    if (todayTransactions.isNotEmpty) {
      final currentFloat = await POSSettingsService.getCashDrawerOpeningBalance();
      await POSSettingsService.saveDailyFloat(todayOnly, currentFloat);
    }
  }

  Future<double> _getTotalAdjustmentsForPeriod() async {
    DateTime startDate;
    DateTime endDate;

    switch (_currentPeriod) {
      case 'daily':
        startDate = _selectedDate;
        endDate = _selectedDate;
        break;
      case 'weekly':
        final weekday = _selectedDate.weekday;
        startDate = _selectedDate.subtract(Duration(days: weekday - 1));
        endDate = startDate.add(const Duration(days: 6));
        break;
      case 'monthly':
        startDate = DateTime(_selectedDate.year, _selectedDate.month, 1);
        endDate = DateTime(_selectedDate.year, _selectedDate.month + 1, 0);
        break;
      case 'yearly':
        startDate = DateTime(_selectedDate.year, 1, 1);
        endDate = DateTime(_selectedDate.year, 12, 31);
        break;
      default:
        return 0.0;
    }

    return await POSSettingsService.getTotalAdjustmentsForRange(
      startDate: startDate,
      endDate: endDate,
    );
  }
}
