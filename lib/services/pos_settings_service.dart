import 'package:firebase_database/firebase_database.dart';
import 'cache_service.dart';

class POSSettingsService {
  static final DatabaseReference _settingsRef =
      FirebaseDatabase.instance.ref('pos_settings');

  // Default settings
  static const Map<String, dynamic> _defaultSettings = {
    'vatEnabled': true,
    'vatRate': 12.0, // 12% VAT
    'vatInclusive': true, // VAT is included in selling price
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
}
