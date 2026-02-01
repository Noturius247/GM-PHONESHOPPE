import 'package:firebase_database/firebase_database.dart';
import 'cache_service.dart';
import 'notification_service.dart';

class InventoryService {
  static final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // Flag to track if we should force refresh from Firebase
  static bool _forceRefresh = false;

  /// Set to force next fetch to get fresh data from Firebase
  static void forceRefresh() {
    _forceRefresh = true;
  }

  // Inventory categories
  static const String phones = 'phones';
  static const String tv = 'tv';
  static const String speaker = 'speaker';
  static const String digitalBox = 'digital_box';
  static const String accessories = 'accessories';
  static const String lightBulb = 'light_bulb';
  static const String solarPanel = 'solar_panel';
  static const String battery = 'battery';
  static const String inverter = 'inverter';
  static const String controller = 'controller';
  static const String other = 'other';

  // Get all category names with display labels
  static Map<String, String> get categoryLabels => {
    phones: 'Phone',
    tv: 'TV',
    speaker: 'Speaker',
    digitalBox: 'Digital Box',
    accessories: 'Accessories',
    lightBulb: 'Light Bulb',
    solarPanel: 'Solar Panel',
    battery: 'Battery',
    inverter: 'Inverter',
    controller: 'Controller',
    other: 'Others',
  };

  // Get reference for inventory
  static DatabaseReference _getInventoryRef() {
    return _database.child('inventory');
  }

  // Get reference for a specific category
  static DatabaseReference _getCategoryRef(String category) {
    return _getInventoryRef().child(category);
  }

  // ==================== INVENTORY ITEMS ====================

  // Add a new inventory item
  static Future<String?> addItem({
    required String category,
    required String name,
    String? sku,
    String? modelNumber,
    String? brand,
    String? description,
    required int quantity,
    double? unitCost,
    double? sellingPrice,
    int? reorderLevel,
    String? supplier,
    String? location,
    String? notes,
    String? addedByEmail,
    String? addedByName,
  }) async {
    try {
      final ref = _getCategoryRef(category).push();
      final data = <String, dynamic>{
        'name': name,
        'quantity': quantity,
        'status': _getStockStatus(quantity, reorderLevel ?? 5),
        'createdAt': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
      };

      if (sku != null && sku.isNotEmpty) data['sku'] = sku;
      if (modelNumber != null && modelNumber.isNotEmpty) data['modelNumber'] = modelNumber;
      if (brand != null && brand.isNotEmpty) data['brand'] = brand;
      if (description != null && description.isNotEmpty) data['description'] = description;
      if (unitCost != null) data['unitCost'] = unitCost;
      if (sellingPrice != null) data['sellingPrice'] = sellingPrice;
      if (reorderLevel != null) data['reorderLevel'] = reorderLevel;
      if (supplier != null && supplier.isNotEmpty) data['supplier'] = supplier;
      if (location != null && location.isNotEmpty) data['location'] = location;
      if (notes != null && notes.isNotEmpty) data['notes'] = notes;

      // Track who added the item
      if (addedByEmail != null && addedByEmail.isNotEmpty) {
        data['addedBy'] = {
          'email': addedByEmail,
          'name': addedByName ?? '',
          'timestamp': ServerValue.timestamp,
        };
      }

      await ref.set(data);

      // Update cache with new item
      final newItem = Map<String, dynamic>.from(data);
      newItem['id'] = ref.key;
      newItem['category'] = category;
      await CacheService.saveInventoryItem(newItem);

      return ref.key;
    } catch (e) {
      print('Error adding inventory item: $e');
      return null;
    }
  }

  // Get reorder level for an item
  static Future<int> _getItemReorderLevel(String category, String itemId) async {
    try {
      final snapshot = await _getCategoryRef(category).child(itemId).child('reorderLevel').get();
      if (snapshot.exists && snapshot.value != null) {
        return int.tryParse(snapshot.value.toString()) ?? 5;
      }
    } catch (_) {}
    return 5;
  }

  // Get stock status based on quantity and reorder level
  static String _getStockStatus(int quantity, int reorderLevel) {
    if (quantity <= 0) return 'Out of Stock';
    if (quantity <= reorderLevel) return 'Low Stock';
    return 'In Stock';
  }

  // Get all items in a category (cache-first)
  static Future<List<Map<String, dynamic>>> getItemsByCategory(String category) async {
    try {
      // Try cache first if not forcing refresh
      if (!_forceRefresh) {
        final cachedItems = await CacheService.getInventoryItemsByCategory(category);
        if (cachedItems.isNotEmpty) {
          print('Loaded ${cachedItems.length} $category items from cache');
          return cachedItems;
        }
      }

      // Fetch from Firebase
      final snapshot = await _getCategoryRef(category).get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final items = data.entries.map((entry) {
          final item = Map<String, dynamic>.from(entry.value as Map);
          item['id'] = entry.key;
          item['category'] = category;
          return item;
        }).toList();

        // Save to cache
        for (var item in items) {
          await CacheService.saveInventoryItem(item);
        }

        return items;
      }
      return [];
    } catch (e) {
      print('Error getting items by category: $e');
      // Fallback to cache on error
      return await CacheService.getInventoryItemsByCategory(category);
    }
  }

  // Get all inventory items across all categories (cache-first)
  static Future<List<Map<String, dynamic>>> getAllItems() async {
    try {
      // Try cache first if not forcing refresh
      if (!_forceRefresh) {
        final hasCache = await CacheService.hasInventoryCache();
        if (hasCache) {
          final cachedItems = await CacheService.getInventoryItems();
          if (cachedItems.isNotEmpty) {
            print('Loaded ${cachedItems.length} inventory items from cache (instant)');
            return cachedItems;
          }
        }
      }

      // Reset force refresh flag
      _forceRefresh = false;

      // Fetch from Firebase
      final snapshot = await _getInventoryRef().get();
      if (snapshot.exists) {
        final List<Map<String, dynamic>> allItems = [];
        final data = snapshot.value as Map<dynamic, dynamic>;

        data.forEach((category, items) {
          if (items is Map) {
            items.forEach((id, itemData) {
              final item = Map<String, dynamic>.from(itemData as Map);
              item['id'] = id;
              item['category'] = category;
              allItems.add(item);
            });
          }
        });

        // Save all items to cache
        await CacheService.saveInventoryItems(allItems);
        print('Fetched ${allItems.length} items from Firebase and cached');

        return allItems;
      }
      return [];
    } catch (e) {
      print('Error getting all items from Firebase: $e');
      // Fallback to cache on network error
      final cachedItems = await CacheService.getInventoryItems();
      if (cachedItems.isNotEmpty) {
        print('Using ${cachedItems.length} cached items (offline fallback)');
        return cachedItems;
      }
      return [];
    }
  }

  /// Fetch fresh data from Firebase and update cache
  static Future<List<Map<String, dynamic>>> refreshFromFirebase() async {
    _forceRefresh = true;
    return await getAllItems();
  }

  // Stream items for real-time updates
  static Stream<DatabaseEvent> streamInventory() {
    return _getInventoryRef().onValue;
  }

  // Stream items in a specific category
  static Stream<DatabaseEvent> streamCategory(String category) {
    return _getCategoryRef(category).onValue;
  }

  // Get item by ID
  static Future<Map<String, dynamic>?> getItemById(String category, String itemId) async {
    try {
      final snapshot = await _getCategoryRef(category).child(itemId).get();
      if (snapshot.exists) {
        final item = Map<String, dynamic>.from(snapshot.value as Map);
        item['id'] = itemId;
        item['category'] = category;
        return item;
      }
      return null;
    } catch (e) {
      print('Error getting item by ID: $e');
      return null;
    }
  }

  // Get current stock quantity for an item
  static Future<int> getItemStock({required String category, required String itemId}) async {
    try {
      final item = await getItemById(category, itemId);
      if (item != null) {
        return item['quantity'] as int? ?? 0;
      }
      return 0;
    } catch (e) {
      print('Error getting item stock: $e');
      return 0;
    }
  }

  // Check if barcode already exists
  static Future<bool> barcodeExists(String barcode) async {
    try {
      final allItems = await getAllItems();
      return allItems.any((item) => item['barcode'] == barcode);
    } catch (e) {
      print('Error checking barcode: $e');
      return false;
    }
  }

  // Get item by barcode
  static Future<Map<String, dynamic>?> getItemByBarcode(String barcode) async {
    try {
      final allItems = await getAllItems();
      for (var item in allItems) {
        if (item['barcode'] == barcode) {
          return item;
        }
      }
      return null;
    } catch (e) {
      print('Error getting item by barcode: $e');
      return null;
    }
  }

  // Get item by SKU/Serial Number (checks both fields for compatibility)
  static Future<Map<String, dynamic>?> getItemBySku(String sku) async {
    try {
      final allItems = await getAllItems();
      for (var item in allItems) {
        final itemSku = item['sku'] ?? item['serialNo'] ?? '';
        if (itemSku == sku) {
          return item;
        }
      }
      return null;
    } catch (e) {
      print('Error getting item by SKU/Serial: $e');
      return null;
    }
  }

  // Update item
  static Future<bool> updateItem({
    required String category,
    required String itemId,
    String? name,
    String? sku,
    String? modelNumber,
    String? brand,
    String? description,
    int? quantity,
    double? unitCost,
    double? sellingPrice,
    int? reorderLevel,
    String? supplier,
    String? location,
    String? notes,
    String? updatedByEmail,
    String? updatedByName,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updatedAt': ServerValue.timestamp,
      };

      if (name != null) updates['name'] = name;
      if (sku != null) updates['sku'] = sku;
      if (modelNumber != null) updates['modelNumber'] = modelNumber;
      if (brand != null) updates['brand'] = brand;
      if (description != null) updates['description'] = description;
      if (unitCost != null) updates['unitCost'] = unitCost;
      if (sellingPrice != null) updates['sellingPrice'] = sellingPrice;
      if (reorderLevel != null) updates['reorderLevel'] = reorderLevel;
      if (supplier != null) updates['supplier'] = supplier;
      if (location != null) updates['location'] = location;
      if (notes != null) updates['notes'] = notes;

      // Update quantity and status together
      if (quantity != null) {
        updates['quantity'] = quantity;
        final currentReorderLevel = reorderLevel ?? 5;
        updates['status'] = _getStockStatus(quantity, currentReorderLevel);
      }

      // Track who updated the item
      if (updatedByEmail != null && updatedByEmail.isNotEmpty) {
        updates['lastUpdatedBy'] = {
          'email': updatedByEmail,
          'name': updatedByName ?? '',
          'timestamp': ServerValue.timestamp,
        };
      }

      await _getCategoryRef(category).child(itemId).update(updates);

      // Update cache - fetch updated item and save
      final updatedItem = await getItemById(category, itemId);
      if (updatedItem != null) {
        await CacheService.saveInventoryItem(updatedItem);
      }

      return true;
    } catch (e) {
      print('Error updating item: $e');
      return false;
    }
  }

  // Delete item
  static Future<bool> deleteItem(String category, String itemId) async {
    try {
      await _getCategoryRef(category).child(itemId).remove();

      // Remove from cache
      await CacheService.deleteInventoryItem(itemId);

      return true;
    } catch (e) {
      print('Error deleting item: $e');
      return false;
    }
  }

  // ==================== STOCK MANAGEMENT ====================

  // Add stock (increase quantity)
  static Future<bool> addStock({
    required String category,
    required String itemId,
    required int quantityToAdd,
    String? reason,
    String? addedByEmail,
    String? addedByName,
  }) async {
    try {
      final item = await getItemById(category, itemId);
      if (item == null) return false;

      final currentQty = item['quantity'] as int? ?? 0;
      final newQty = currentQty + quantityToAdd;
      final reorderLevel = item['reorderLevel'] as int? ?? 5;

      final updates = <String, dynamic>{
        'quantity': newQty,
        'status': _getStockStatus(newQty, reorderLevel),
        'updatedAt': ServerValue.timestamp,
      };

      await _getCategoryRef(category).child(itemId).update(updates);

      // Log the stock change
      await _logStockChange(
        category: category,
        itemId: itemId,
        itemName: item['name'] ?? '',
        changeType: 'add',
        quantityChange: quantityToAdd,
        previousQty: currentQty,
        newQty: newQty,
        reason: reason,
        changedByEmail: addedByEmail,
        changedByName: addedByName,
      );

      return true;
    } catch (e) {
      print('Error adding stock: $e');
      return false;
    }
  }

  // Remove stock (decrease quantity)
  static Future<bool> removeStock({
    required String category,
    required String itemId,
    required int quantityToRemove,
    String? reason,
    String? removedByEmail,
    String? removedByName,
  }) async {
    try {
      final item = await getItemById(category, itemId);
      if (item == null) return false;

      final currentQty = item['quantity'] as int? ?? 0;
      final newQty = (currentQty - quantityToRemove).clamp(0, double.infinity).toInt();
      final reorderLevel = item['reorderLevel'] as int? ?? 5;

      final updates = <String, dynamic>{
        'quantity': newQty,
        'status': _getStockStatus(newQty, reorderLevel),
        'updatedAt': ServerValue.timestamp,
      };

      await _getCategoryRef(category).child(itemId).update(updates);

      // Update local cache
      final updatedItem = Map<String, dynamic>.from(item);
      updatedItem['quantity'] = newQty;
      updatedItem['status'] = _getStockStatus(newQty, reorderLevel);
      await CacheService.saveInventoryItem(updatedItem);

      // Log the stock change
      await _logStockChange(
        category: category,
        itemId: itemId,
        itemName: item['name'] ?? '',
        changeType: 'remove',
        quantityChange: quantityToRemove,
        previousQty: currentQty,
        newQty: newQty,
        reason: reason,
        changedByEmail: removedByEmail,
        changedByName: removedByName,
      );

      return true;
    } catch (e) {
      print('Error removing stock: $e');
      return false;
    }
  }

  // Set exact stock level
  static Future<bool> setStock({
    required String category,
    required String itemId,
    required int newQuantity,
    String? reason,
    String? setByEmail,
    String? setByName,
  }) async {
    try {
      final item = await getItemById(category, itemId);
      if (item == null) return false;

      final currentQty = item['quantity'] as int? ?? 0;
      final reorderLevel = item['reorderLevel'] as int? ?? 5;

      final updates = <String, dynamic>{
        'quantity': newQuantity,
        'status': _getStockStatus(newQuantity, reorderLevel),
        'updatedAt': ServerValue.timestamp,
      };

      await _getCategoryRef(category).child(itemId).update(updates);

      // Log the stock change
      await _logStockChange(
        category: category,
        itemId: itemId,
        itemName: item['name'] ?? '',
        changeType: 'set',
        quantityChange: newQuantity - currentQty,
        previousQty: currentQty,
        newQty: newQuantity,
        reason: reason ?? 'Stock adjustment',
        changedByEmail: setByEmail,
        changedByName: setByName,
      );

      return true;
    } catch (e) {
      print('Error setting stock: $e');
      return false;
    }
  }

  // ==================== STOCK HISTORY ====================

  // Get reference for stock history
  static DatabaseReference _getStockHistoryRef() {
    return _database.child('inventory_history');
  }

  // Log stock change
  static Future<void> _logStockChange({
    required String category,
    required String itemId,
    required String itemName,
    required String changeType,
    required int quantityChange,
    required int previousQty,
    required int newQty,
    String? reason,
    String? changedByEmail,
    String? changedByName,
  }) async {
    try {
      final ref = _getStockHistoryRef().push();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final record = {
        'id': ref.key,
        'category': category,
        'itemId': itemId,
        'itemName': itemName,
        'changeType': changeType,
        'quantityChange': quantityChange,
        'previousQty': previousQty,
        'newQty': newQty,
        'reason': reason ?? '',
        'changedBy': {
          'email': changedByEmail ?? '',
          'name': changedByName ?? '',
        },
        'timestamp': timestamp,
      };

      // Save to Firebase
      await ref.set({
        ...record,
        'timestamp': ServerValue.timestamp,
      });

      // Also save to local cache
      await CacheService.saveInventoryHistoryRecord(record);

      // Check for stock transition and send alert to all devices
      final reorderLevel = await _getItemReorderLevel(category, itemId);
      final wasOk = previousQty > reorderLevel;
      final wasLow = previousQty > 0 && previousQty <= reorderLevel;
      final isOutOfStock = newQty <= 0;
      final isLowStock = newQty > 0 && newQty <= reorderLevel;

      if (isOutOfStock && (wasOk || wasLow || previousQty > 0)) {
        await NotificationService.sendStockAlert(
          title: 'Out of Stock!',
          body: '$itemName ($category) is now out of stock.',
          category: category,
          itemId: itemId,
          itemName: itemName,
          quantity: newQty,
          reorderLevel: reorderLevel,
          alertType: 'out_of_stock',
        );
      } else if (isLowStock && wasOk) {
        await NotificationService.sendStockAlert(
          title: 'Low Stock Alert',
          body: '$itemName ($category) is low — only $newQty left (reorder at $reorderLevel).',
          category: category,
          itemId: itemId,
          itemName: itemName,
          quantity: newQty,
          reorderLevel: reorderLevel,
          alertType: 'low_stock',
        );
      }
    } catch (e) {
      print('Error logging stock change: $e');
    }
  }

  // Get stock history for an item (cache-first)
  static Future<List<Map<String, dynamic>>> getItemStockHistory(String itemId) async {
    try {
      // Try cache first
      final hasCache = await CacheService.hasInventoryHistoryCache();
      if (hasCache) {
        final cachedHistory = await CacheService.getInventoryHistoryByItem(itemId);
        if (cachedHistory.isNotEmpty) {
          // Sort by timestamp descending
          cachedHistory.sort((a, b) {
            final aTime = a['timestamp'] as int? ?? 0;
            final bTime = b['timestamp'] as int? ?? 0;
            return bTime.compareTo(aTime);
          });
          return cachedHistory.take(50).toList();
        }
      }

      // Fetch from Firebase
      final snapshot = await _getStockHistoryRef()
          .orderByChild('itemId')
          .equalTo(itemId)
          .limitToLast(50)
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final history = data.entries.map((entry) {
          final record = Map<String, dynamic>.from(entry.value as Map);
          record['id'] = entry.key;
          return record;
        }).toList();

        // Sort by timestamp descending
        history.sort((a, b) {
          final aTime = a['timestamp'] as int? ?? 0;
          final bTime = b['timestamp'] as int? ?? 0;
          return bTime.compareTo(aTime);
        });

        return history;
      }
      return [];
    } catch (e) {
      print('Error getting item stock history: $e');
      // Fallback to cache on error
      final cachedHistory = await CacheService.getInventoryHistoryByItem(itemId);
      cachedHistory.sort((a, b) {
        final aTime = a['timestamp'] as int? ?? 0;
        final bTime = b['timestamp'] as int? ?? 0;
        return bTime.compareTo(aTime);
      });
      return cachedHistory.take(50).toList();
    }
  }

  // Get recent stock history (cache-first)
  static Future<List<Map<String, dynamic>>> getRecentStockHistory({int limit = 50}) async {
    try {
      // Try cache first
      final hasCache = await CacheService.hasInventoryHistoryCache();
      if (hasCache) {
        final cachedHistory = await CacheService.getInventoryHistory();
        if (cachedHistory.isNotEmpty) {
          cachedHistory.sort((a, b) {
            final aTime = a['timestamp'] as int? ?? 0;
            final bTime = b['timestamp'] as int? ?? 0;
            return bTime.compareTo(aTime);
          });
          return cachedHistory.take(limit).toList();
        }
      }

      // Fetch from Firebase
      final snapshot = await _getStockHistoryRef()
          .limitToLast(limit)
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final history = data.entries.map((entry) {
          final record = Map<String, dynamic>.from(entry.value as Map);
          record['id'] = entry.key;
          return record;
        }).toList();

        // Sort by timestamp descending
        history.sort((a, b) {
          final aTime = a['timestamp'] as int? ?? 0;
          final bTime = b['timestamp'] as int? ?? 0;
          return bTime.compareTo(aTime);
        });

        return history;
      }
      return [];
    } catch (e) {
      print('Error getting recent stock history: $e');
      // Fallback to cache on error
      final cachedHistory = await CacheService.getInventoryHistory();
      cachedHistory.sort((a, b) {
        final aTime = a['timestamp'] as int? ?? 0;
        final bTime = b['timestamp'] as int? ?? 0;
        return bTime.compareTo(aTime);
      });
      return cachedHistory.take(limit).toList();
    }
  }

  // ==================== SKU GENERATION ====================

  /// Generate the next unique SKU in the 9000000+ series.
  /// Scans all existing items, finds the highest 9XXXXXX SKU, and returns the next one.
  static Future<String> generateNextSku() async {
    try {
      final allItems = await getAllItems();
      int maxSku = 9000000;

      for (final item in allItems) {
        final sku = item['sku'] as String? ?? item['serialNo'] as String? ?? '';
        final parsed = int.tryParse(sku);
        if (parsed != null && parsed >= 9000000 && parsed > maxSku) {
          maxSku = parsed;
        }
      }

      return (maxSku + 1).toString();
    } catch (e) {
      print('Error generating next SKU: $e');
      return '9000001';
    }
  }

  // ==================== INVENTORY STATISTICS ====================

  // Get inventory statistics
  static Future<Map<String, dynamic>> getInventoryStats() async {
    try {
      final allItems = await getAllItems();

      int totalItems = allItems.length;
      int totalQuantity = 0;
      int lowStockCount = 0;
      int outOfStockCount = 0;
      double totalValue = 0;
      double totalCost = 0;
      Map<String, int> categoryCount = {};

      for (var item in allItems) {
        final qty = item['quantity'] as int? ?? 0;
        final status = item['status'] as String? ?? '';
        final sellingPrice = (item['sellingPrice'] as num?)?.toDouble() ?? 0;
        final unitCost = (item['unitCost'] as num?)?.toDouble() ?? 0;
        final category = item['category'] as String? ?? other;

        totalQuantity += qty;
        totalValue += qty * sellingPrice;
        totalCost += qty * unitCost;
        categoryCount[category] = (categoryCount[category] ?? 0) + 1;

        if (status == 'Low Stock') lowStockCount++;
        if (status == 'Out of Stock') outOfStockCount++;
      }

      return {
        'totalItems': totalItems,
        'totalQuantity': totalQuantity,
        'lowStockCount': lowStockCount,
        'outOfStockCount': outOfStockCount,
        'totalValue': totalValue,
        'totalCost': totalCost,
        'potentialProfit': totalValue - totalCost,
        'categoryCount': categoryCount,
      };
    } catch (e) {
      print('Error getting inventory stats: $e');
      return {
        'totalItems': 0,
        'totalQuantity': 0,
        'lowStockCount': 0,
        'outOfStockCount': 0,
        'totalValue': 0.0,
        'totalCost': 0.0,
        'potentialProfit': 0.0,
        'categoryCount': <String, int>{},
      };
    }
  }

  // Get low stock items
  static Future<List<Map<String, dynamic>>> getLowStockItems() async {
    try {
      final allItems = await getAllItems();
      return allItems.where((item) =>
        item['status'] == 'Low Stock' || item['status'] == 'Out of Stock'
      ).toList();
    } catch (e) {
      print('Error getting low stock items: $e');
      return [];
    }
  }

  // Get items below specified quantity threshold (default 10)
  static Future<List<Map<String, dynamic>>> getItemsBelowThreshold({int threshold = 10}) async {
    try {
      final allItems = await getAllItems();
      return allItems.where((item) {
        final quantity = item['quantity'] as int? ?? 0;
        return quantity < threshold;
      }).toList()
        ..sort((a, b) {
          final aQty = a['quantity'] as int? ?? 0;
          final bQty = b['quantity'] as int? ?? 0;
          return aQty.compareTo(bQty); // Sort by quantity ascending (lowest first)
        });
    } catch (e) {
      print('Error getting items below threshold: $e');
      return [];
    }
  }

  // Search items by name
  static Future<List<Map<String, dynamic>>> searchItems(String query) async {
    try {
      final allItems = await getAllItems();
      final searchLower = query.toLowerCase();
      return allItems.where((item) {
        final name = (item['name'] as String? ?? '').toLowerCase();
        final sku = (item['sku'] as String? ?? item['serialNo'] as String? ?? '').toLowerCase();
        final barcode = (item['barcode'] as String? ?? '').toLowerCase();
        final description = (item['description'] as String? ?? '').toLowerCase();
        return name.contains(searchLower) ||
               sku.contains(searchLower) ||
               barcode.contains(searchLower) ||
               description.contains(searchLower);
      }).toList();
    } catch (e) {
      print('Error searching items: $e');
      return [];
    }
  }
}
