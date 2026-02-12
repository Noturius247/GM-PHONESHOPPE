import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'cache_service.dart';

class POSSettingsService {
  static final DatabaseReference _settingsRef =
      FirebaseDatabase.instance.ref('pos_settings');
  static final DatabaseReference _balanceHistoryRef =
      FirebaseDatabase.instance.ref('cash_balance_history');
  static final DatabaseReference _cashAdjustmentsRef =
      FirebaseDatabase.instance.ref('cash_adjustments');

  // Default settings
  static const Map<String, dynamic> _defaultSettings = {
    'vatEnabled': true,
    'vatRate': 12.0, // 12% VAT
    'vatInclusive': true, // VAT is included in selling price
    'cashDrawerOpeningBalance': 0.0, // Opening balance for cash drawer
    // Sort settings for services (field_direction format)
    'sortCignal': 'name_asc',
    'sortSky': 'name_asc',
    'sortSatellite': 'name_asc',
    'sortGsat': 'name_asc',
  };

  // Sort options
  static const List<Map<String, String>> sortOptions = [
    {'value': 'name_asc', 'label': 'Name (A-Z)'},
    {'value': 'name_desc', 'label': 'Name (Z-A)'},
    {'value': 'dateOfActivation_desc', 'label': 'Activation Date (Newest)'},
    {'value': 'dateOfActivation_asc', 'label': 'Activation Date (Oldest)'},
    {'value': 'dateOfPurchase_desc', 'label': 'Purchase Date (Newest)'},
    {'value': 'dateOfPurchase_asc', 'label': 'Purchase Date (Oldest)'},
    {'value': 'status_asc', 'label': 'Status (Active First)'},
    {'value': 'status_desc', 'label': 'Status (Inactive First)'},
  ];

  // Get all POS settings (cache-first)
  static Future<Map<String, dynamic>> getSettings() async {
    try {
      // Try cache first
      final cachedSettings = await CacheService.getPosSettings();
      if (cachedSettings != null) {
        return {..._defaultSettings, ...cachedSettings};
      }

      // Fetch from Firebase
      final snapshot = await _settingsRef.get();
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        // Save to cache
        await CacheService.savePosSettings(data);
        // Merge with defaults to ensure all keys exist
        return {..._defaultSettings, ...data};
      }
      return Map<String, dynamic>.from(_defaultSettings);
    } catch (e) {
      // Fallback to cache on error
      final cachedSettings = await CacheService.getPosSettings();
      if (cachedSettings != null) {
        return {..._defaultSettings, ...cachedSettings};
      }
      return Map<String, dynamic>.from(_defaultSettings);
    }
  }

  // Get a specific setting
  static Future<T> getSetting<T>(String key, T defaultValue) async {
    try {
      final snapshot = await _settingsRef.child(key).get();
      if (snapshot.exists) {
        return snapshot.value as T;
      }
      return defaultValue;
    } catch (e) {
      return defaultValue;
    }
  }

  // Check if VAT is enabled
  static Future<bool> isVATEnabled() async {
    return await getSetting<bool>('vatEnabled', true);
  }

  // Get VAT rate
  static Future<double> getVATRate() async {
    final rate = await getSetting<num>('vatRate', 12.0);
    return rate.toDouble();
  }

  // Check if VAT is inclusive (included in price)
  static Future<bool> isVATInclusive() async {
    return await getSetting<bool>('vatInclusive', true);
  }

  // Update a setting
  static Future<bool> updateSetting(String key, dynamic value) async {
    try {
      await _settingsRef.child(key).set(value);
      return true;
    } catch (e) {
      return false;
    }
  }

  // Update multiple settings
  static Future<bool> updateSettings(Map<String, dynamic> settings) async {
    try {
      await _settingsRef.update(settings);
      // Update cache with new settings
      final allSettings = await getSettings();
      await CacheService.savePosSettings(allSettings);
      return true;
    } catch (e) {
      return false;
    }
  }

  // Toggle VAT enabled/disabled
  static Future<bool> toggleVAT(bool enabled) async {
    return await updateSetting('vatEnabled', enabled);
  }

  // Set VAT rate
  static Future<bool> setVATRate(double rate) async {
    return await updateSetting('vatRate', rate);
  }

  // Set VAT inclusive
  static Future<bool> setVATInclusive(bool inclusive) async {
    return await updateSetting('vatInclusive', inclusive);
  }

  // Get cash drawer opening balance
  static Future<double> getCashDrawerOpeningBalance() async {
    final balance = await getSetting<num>('cashDrawerOpeningBalance', 0.0);
    return balance.toDouble();
  }

  // Set cash drawer opening balance
  static Future<bool> setCashDrawerOpeningBalance(double balance) async {
    return await updateSetting('cashDrawerOpeningBalance', balance);
  }

  // Get sort setting for a service
  static Future<String> getSortSetting(String service) async {
    final key = 'sort${service[0].toUpperCase()}${service.substring(1)}';
    return await getSetting<String>(key, 'name_asc');
  }

  // Set sort setting for a service
  static Future<bool> setSortSetting(String service, String sortValue) async {
    final key = 'sort${service[0].toUpperCase()}${service.substring(1)}';
    return await updateSetting(key, sortValue);
  }

  // Sort a list of customers based on sort setting
  static List<Map<String, dynamic>> sortCustomers(
    List<Map<String, dynamic>> customers,
    String sortSetting,
  ) {
    final parts = sortSetting.split('_');
    if (parts.length != 2) return customers;

    final field = parts[0];
    final direction = parts[1];
    final ascending = direction == 'asc';

    final sorted = List<Map<String, dynamic>>.from(customers);
    sorted.sort((a, b) {
      dynamic valA = a[field];
      dynamic valB = b[field];

      // Handle null values
      if (valA == null && valB == null) return 0;
      if (valA == null) return ascending ? 1 : -1;
      if (valB == null) return ascending ? -1 : 1;

      // Handle date fields
      if (field == 'dateOfActivation' || field == 'dateOfPurchase') {
        try {
          final dateA = DateTime.tryParse(valA.toString()) ?? DateTime(1900);
          final dateB = DateTime.tryParse(valB.toString()) ?? DateTime(1900);
          return ascending ? dateA.compareTo(dateB) : dateB.compareTo(dateA);
        } catch (e) {
          return 0;
        }
      }

      // Handle status field (Active should come first when ascending)
      if (field == 'status') {
        final statusOrder = {'Active': 0, 'Inactive': 1, 'Pending': 2};
        final orderA = statusOrder[valA.toString()] ?? 3;
        final orderB = statusOrder[valB.toString()] ?? 3;
        return ascending ? orderA.compareTo(orderB) : orderB.compareTo(orderA);
      }

      // Handle string comparison (case-insensitive)
      final strA = valA.toString().toLowerCase();
      final strB = valB.toString().toLowerCase();
      return ascending ? strA.compareTo(strB) : strB.compareTo(strA);
    });

    return sorted;
  }

  // ============================================
  // CASH BALANCE HISTORY METHODS
  // ============================================

  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  // Get date key for a given DateTime
  static String _getDateKey(DateTime date) {
    return _dateFormat.format(date);
  }

  // Save daily balance record (called when "Close Day" is pressed)
  static Future<bool> saveDailyBalance({
    required DateTime date,
    required double openingBalance,
    required double closingBalance,
    required double cashSales,
    required double cashIn,
    required double cashOut,
    required double adjustments,
    String? notes,
  }) async {
    try {
      final dateKey = _getDateKey(date);
      await _balanceHistoryRef.child(dateKey).set({
        'date': dateKey,
        'openingBalance': openingBalance,
        'closingBalance': closingBalance,
        'cashSales': cashSales,
        'cashIn': cashIn,
        'cashOut': cashOut,
        'adjustments': adjustments,
        'notes': notes ?? '',
        'closedAt': DateTime.now().toIso8601String(),
        'status': 'closed',
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  // Get daily balance for a specific date
  static Future<Map<String, dynamic>?> getDailyBalance(DateTime date) async {
    try {
      final dateKey = _getDateKey(date);
      final snapshot = await _balanceHistoryRef.child(dateKey).get();
      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Check if a day has been started (opening balance locked)
  static Future<bool> isDayStarted(DateTime date) async {
    try {
      final dateKey = _getDateKey(date);
      final snapshot = await _balanceHistoryRef.child(dateKey).child('status').get();
      if (snapshot.exists) {
        final status = snapshot.value as String;
        return status == 'started' || status == 'closed';
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Check if a day has been closed
  static Future<bool> isDayClosed(DateTime date) async {
    try {
      final dateKey = _getDateKey(date);
      final snapshot = await _balanceHistoryRef.child(dateKey).child('status').get();
      if (snapshot.exists) {
        return snapshot.value == 'closed';
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Start the day (lock opening balance)
  static Future<bool> startDay({
    required DateTime date,
    required double openingBalance,
  }) async {
    try {
      final dateKey = _getDateKey(date);
      await _balanceHistoryRef.child(dateKey).set({
        'date': dateKey,
        'openingBalance': openingBalance,
        'status': 'started',
        'startedAt': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  // Get the opening balance (float) for a specific date
  // - For past dates: Use saved history (remembers what float was set that day)
  // - For today/future: Use current Settings value
  static Future<double> getOpeningBalanceForDate(DateTime date) async {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final dateOnly = DateTime(date.year, date.month, date.day);

    // For today or future, use Settings value
    if (!dateOnly.isBefore(todayOnly)) {
      return await getCashDrawerOpeningBalance();
    }

    // For past dates, check history first
    final savedBalance = await getDailyBalance(date);
    if (savedBalance != null && savedBalance['openingBalance'] != null) {
      return (savedBalance['openingBalance'] as num).toDouble();
    }

    // If no history for that day, fall back to Settings (legacy data)
    return await getCashDrawerOpeningBalance();
  }

  // Save daily float to history (called automatically when transactions exist)
  static Future<bool> saveDailyFloat(DateTime date, double openingBalance) async {
    try {
      final dateKey = _getDateKey(date);

      // Check if already saved
      final existing = await _balanceHistoryRef.child(dateKey).get();
      if (existing.exists) {
        // Already has a record, don't overwrite
        return true;
      }

      // Save the float for this day
      await _balanceHistoryRef.child(dateKey).set({
        'date': dateKey,
        'openingBalance': openingBalance,
        'savedAt': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  // Get the opening balance for a period
  // For daily: Get that day's float
  // For weekly/monthly/yearly: Get first day's float (since each day resets)
  static Future<double> getPeriodOpeningBalance({
    required String period,
    required DateTime selectedDate,
  }) async {
    // For all periods, we use the selected date's float
    // (Weekly/monthly/yearly show totals, the float is just for reference)
    return await getOpeningBalanceForDate(selectedDate);
  }

  // Get balance history for a date range
  static Future<List<Map<String, dynamic>>> getBalanceHistory({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startKey = _getDateKey(startDate);
      final endKey = _getDateKey(endDate);

      final snapshot = await _balanceHistoryRef
          .orderByKey()
          .startAt(startKey)
          .endAt(endKey)
          .get();

      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        return data.entries
            .map((e) => Map<String, dynamic>.from(e.value as Map))
            .toList()
          ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // ============================================
  // CASH ADJUSTMENT METHODS
  // ============================================

  // Record a cash adjustment (for mid-day corrections)
  static Future<bool> recordCashAdjustment({
    required DateTime date,
    required double amount, // positive for adding, negative for removing
    required String reason,
    String? recordedBy,
  }) async {
    try {
      final dateKey = _getDateKey(date);
      final adjustmentRef = _cashAdjustmentsRef.child(dateKey).push();

      await adjustmentRef.set({
        'date': dateKey,
        'amount': amount,
        'reason': reason,
        'recordedBy': recordedBy ?? 'Unknown',
        'timestamp': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  // Get all cash adjustments for a specific date
  static Future<List<Map<String, dynamic>>> getCashAdjustments(DateTime date) async {
    try {
      final dateKey = _getDateKey(date);
      final snapshot = await _cashAdjustmentsRef.child(dateKey).get();

      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        return data.entries
            .map((e) => {
                  ...Map<String, dynamic>.from(e.value as Map),
                  'id': e.key,
                })
            .toList()
          ..sort((a, b) => (a['timestamp'] as String).compareTo(b['timestamp'] as String));
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // Get total adjustments for a date
  static Future<double> getTotalAdjustments(DateTime date) async {
    final adjustments = await getCashAdjustments(date);
    return adjustments.fold<double>(
      0.0,
      (sum, adj) => sum + ((adj['amount'] as num?)?.toDouble() ?? 0.0),
    );
  }

  // Get total adjustments for a date range
  static Future<double> getTotalAdjustmentsForRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    double total = 0.0;
    DateTime current = startDate;

    while (!current.isAfter(endDate)) {
      total += await getTotalAdjustments(current);
      current = current.add(const Duration(days: 1));
    }

    return total;
  }

  // Get the last closed day's closing balance (for auto-populating next day's opening)
  static Future<double?> getLastClosingBalance() async {
    try {
      final snapshot = await _balanceHistoryRef
          .orderByKey()
          .limitToLast(1)
          .get();

      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        final lastEntry = data.values.first as Map;
        if (lastEntry['status'] == 'closed' && lastEntry['closingBalance'] != null) {
          return (lastEntry['closingBalance'] as num).toDouble();
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Get day status for a date
  static Future<String> getDayStatus(DateTime date) async {
    try {
      final dateKey = _getDateKey(date);
      final snapshot = await _balanceHistoryRef.child(dateKey).child('status').get();
      if (snapshot.exists) {
        return snapshot.value as String;
      }
      return 'not_started';
    } catch (e) {
      return 'not_started';
    }
  }
}
