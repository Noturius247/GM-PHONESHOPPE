import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // Add a new inventory item (offline-first)
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
    // Generate a temporary ID for offline use
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final data = <String, dynamic>{
      'name': name,
      'quantity': quantity,
      'status': _getStockStatus(quantity, reorderLevel ?? 5),
      'createdAt': timestamp,
      'updatedAt': timestamp,
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
        'timestamp': timestamp,
      };
    }

    // Check connectivity
    final hasConnection = await CacheService.hasConnectivity();

    if (hasConnection) {
      try {
        final ref = _getCategoryRef(category).push();
        // Use ServerValue.timestamp for Firebase
        final firebaseData = Map<String, dynamic>.from(data);
        firebaseData['createdAt'] = ServerValue.timestamp;
        firebaseData['updatedAt'] = ServerValue.timestamp;
        if (firebaseData['addedBy'] != null) {
          firebaseData['addedBy']['timestamp'] = ServerValue.timestamp;
        }

        await ref.set(firebaseData);

        // Update cache with new item
        final newItem = Map<String, dynamic>.from(data);
        newItem['id'] = ref.key;
        newItem['category'] = category;
        await CacheService.saveInventoryItem(newItem);

        return ref.key;
      } catch (e) {
        print('Error adding inventory item online, saving offline: $e');
        // Fall through to offline save
      }
    }

    // Offline: Save to cache and queue for sync
    final newItem = Map<String, dynamic>.from(data);
    newItem['id'] = tempId;
    newItem['category'] = category;
    await CacheService.saveInventoryItem(newItem);

    // Queue for sync
    await CacheService.savePendingOperation(
      operationType: 'inventory_add',
      data: {
        'category': category,
        'itemData': data,
      },
      entityId: tempId,
    );

    print('Inventory item saved offline: $tempId');
    return tempId;
  }

  // Get reorder level for an item (cache-first)
  static Future<int> _getItemReorderLevel(String category, String itemId) async {
    try {
      // OPTIMIZED: Check cache first to avoid network call
      final item = await getItemById(category, itemId);
      if (item != null && item['reorderLevel'] != null) {
        return item['reorderLevel'] as int? ?? 5;
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

  /// Stream items for real-time updates.
  /// @deprecated Use SyncService for real-time sync instead to avoid duplicate listeners.
  /// SyncService already maintains optimized listeners - using this creates redundant data usage.
  static Stream<DatabaseEvent> streamInventory() {
    return _getInventoryRef().onValue;
  }

  /// Stream items in a specific category.
  /// @deprecated Use SyncService for real-time sync instead to avoid duplicate listeners.
  static Stream<DatabaseEvent> streamCategory(String category) {
    return _getCategoryRef(category).onValue;
  }

  // Get item by ID (cache-first for efficiency)
  static Future<Map<String, dynamic>?> getItemById(String category, String itemId) async {
    try {
      // OPTIMIZED: Check cache first to avoid network call
      final cachedItems = await CacheService.getInventoryItems();
      final cachedItem = cachedItems.firstWhere(
        (item) => item['id'] == itemId,
        orElse: () => <String, dynamic>{},
      );
      if (cachedItem.isNotEmpty) {
        return cachedItem;
      }

      // If not in cache, try Firebase
      final hasConnection = await CacheService.hasConnectivity();
      if (!hasConnection) return null;

      final snapshot = await _getCategoryRef(category).child(itemId).get();
      if (snapshot.exists) {
        final item = Map<String, dynamic>.from(snapshot.value as Map);
        item['id'] = itemId;
        item['category'] = category;
        // Save to cache for next time
        await CacheService.saveInventoryItem(item);
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

  // Update item (offline-first)
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
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final updates = <String, dynamic>{
      'updatedAt': timestamp,
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
        'timestamp': timestamp,
      };
    }

    // Check connectivity
    final hasConnection = await CacheService.hasConnectivity();

    if (hasConnection) {
      try {
        // Use ServerValue.timestamp for Firebase
        final firebaseUpdates = Map<String, dynamic>.from(updates);
        firebaseUpdates['updatedAt'] = ServerValue.timestamp;
        if (firebaseUpdates['lastUpdatedBy'] != null) {
          firebaseUpdates['lastUpdatedBy']['timestamp'] = ServerValue.timestamp;
        }

        await _getCategoryRef(category).child(itemId).update(firebaseUpdates);

        // Update cache - fetch updated item and save
        final updatedItem = await getItemById(category, itemId);
        if (updatedItem != null) {
          await CacheService.saveInventoryItem(updatedItem);
        }

        return true;
      } catch (e) {
        print('Error updating item online, saving offline: $e');
        // Fall through to offline save
      }
    }

    // Offline: Update cache and queue for sync
    // Get current item from cache and merge updates
    final cachedItems = await CacheService.getInventoryItems();
    final existingItem = cachedItems.firstWhere(
      (item) => item['id'] == itemId,
      orElse: () => <String, dynamic>{},
    );

    if (existingItem.isNotEmpty) {
      final mergedItem = Map<String, dynamic>.from(existingItem);
      mergedItem.addAll(updates);
      await CacheService.saveInventoryItem(mergedItem);
    }

    // Queue for sync
    await CacheService.savePendingOperation(
      operationType: 'inventory_update',
      data: {
        'category': category,
        'itemId': itemId,
        'updates': updates,
      },
      entityId: itemId,
    );

    print('Inventory update saved offline: $itemId');
    return true;
  }

  // Delete item (offline-first)
  static Future<bool> deleteItem(String category, String itemId) async {
    // Check connectivity
    final hasConnection = await CacheService.hasConnectivity();

    if (hasConnection) {
      try {
        await _getCategoryRef(category).child(itemId).remove();

        // Remove from cache
        await CacheService.deleteInventoryItem(itemId);

        return true;
      } catch (e) {
        print('Error deleting item online, saving offline: $e');
        // Fall through to offline save
      }
    }

    // Offline: Remove from cache and queue for sync
    await CacheService.deleteInventoryItem(itemId);

    // Queue for sync
    await CacheService.savePendingOperation(
      operationType: 'inventory_delete',
      data: {
        'category': category,
        'itemId': itemId,
      },
      entityId: itemId,
    );

    print('Inventory delete saved offline: $itemId');
    return true;
  }

  // ==================== STOCK MANAGEMENT ====================

  // Add stock (increase quantity) - offline-first
  static Future<bool> addStock({
    required String category,
    required String itemId,
    required int quantityToAdd,
    String? reason,
    String? addedByEmail,
    String? addedByName,
  }) async {
    // Get current item (from cache if offline)
    final item = await getItemById(category, itemId);
    if (item == null) return false;

    final currentQty = item['quantity'] as int? ?? 0;
    final newQty = currentQty + quantityToAdd;
    final reorderLevel = item['reorderLevel'] as int? ?? 5;

    // Check connectivity
    final hasConnection = await CacheService.hasConnectivity();

    if (hasConnection) {
      try {
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
        print('Error adding stock online, saving offline: $e');
        // Fall through to offline save
      }
    }

    // Offline: Update cache and queue for sync
    final updatedItem = Map<String, dynamic>.from(item);
    updatedItem['quantity'] = newQty;
    updatedItem['status'] = _getStockStatus(newQty, reorderLevel);
    updatedItem['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    await CacheService.saveInventoryItem(updatedItem);

    // Queue for sync
    await CacheService.savePendingOperation(
      operationType: 'stock_add',
      data: {
        'category': category,
        'itemId': itemId,
        'itemName': item['name'] ?? '',
        'quantityToAdd': quantityToAdd,
        'previousQty': currentQty,
        'newQty': newQty,
        'reason': reason,
        'addedByEmail': addedByEmail,
        'addedByName': addedByName,
      },
      entityId: itemId,
    );

    print('Stock add saved offline: $itemId (+$quantityToAdd)');
    return true;
  }

  // Remove stock (decrease quantity) - offline-first
  static Future<bool> removeStock({
    required String category,
    required String itemId,
    required int quantityToRemove,
    String? reason,
    String? removedByEmail,
    String? removedByName,
  }) async {
    // Get current item (from cache if offline)
    final item = await getItemById(category, itemId);
    if (item == null) return false;

    final currentQty = item['quantity'] as int? ?? 0;
    final newQty = (currentQty - quantityToRemove).clamp(0, double.infinity).toInt();
    final reorderLevel = item['reorderLevel'] as int? ?? 5;

    // Check connectivity
    final hasConnection = await CacheService.hasConnectivity();

    if (hasConnection) {
      try {
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
        print('Error removing stock online, saving offline: $e');
        // Fall through to offline save
      }
    }

    // Offline: Update cache and queue for sync
    final updatedItem = Map<String, dynamic>.from(item);
    updatedItem['quantity'] = newQty;
    updatedItem['status'] = _getStockStatus(newQty, reorderLevel);
    updatedItem['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    await CacheService.saveInventoryItem(updatedItem);

    // Queue for sync
    await CacheService.savePendingOperation(
      operationType: 'stock_remove',
      data: {
        'category': category,
        'itemId': itemId,
        'itemName': item['name'] ?? '',
        'quantityToRemove': quantityToRemove,
        'previousQty': currentQty,
        'newQty': newQty,
        'reason': reason,
        'removedByEmail': removedByEmail,
        'removedByName': removedByName,
      },
      entityId: itemId,
    );

    print('Stock remove saved offline: $itemId (-$quantityToRemove)');
    return true;
  }

  // Set exact stock level - offline-first
  static Future<bool> setStock({
    required String category,
    required String itemId,
    required int newQuantity,
    String? reason,
    String? setByEmail,
    String? setByName,
  }) async {
    // Get current item (from cache if offline)
    final item = await getItemById(category, itemId);
    if (item == null) return false;

    final currentQty = item['quantity'] as int? ?? 0;
    final reorderLevel = item['reorderLevel'] as int? ?? 5;

    // Check connectivity
    final hasConnection = await CacheService.hasConnectivity();

    if (hasConnection) {
      try {
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
        print('Error setting stock online, saving offline: $e');
        // Fall through to offline save
      }
    }

    // Offline: Update cache and queue for sync
    final updatedItem = Map<String, dynamic>.from(item);
    updatedItem['quantity'] = newQuantity;
    updatedItem['status'] = _getStockStatus(newQuantity, reorderLevel);
    updatedItem['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    await CacheService.saveInventoryItem(updatedItem);

    // Queue for sync
    await CacheService.savePendingOperation(
      operationType: 'stock_set',
      data: {
        'category': category,
        'itemId': itemId,
        'itemName': item['name'] ?? '',
        'newQuantity': newQuantity,
        'previousQty': currentQty,
        'reason': reason ?? 'Stock adjustment',
        'setByEmail': setByEmail,
        'setByName': setByName,
      },
      entityId: itemId,
    );

    print('Stock set saved offline: $itemId (=$newQuantity)');
    return true;
  }

  // ==================== INDAY INVENTORY TRANSFERS ====================

  /// Transfer stock from main inventory to Inday inventory
  static Future<bool> transferToInday({
    required String category,
    required String itemId,
    required int quantity,
    String? reason,
    String? transferredByEmail,
    String? transferredByName,
  }) async {
    // Get current item
    final item = await getItemById(category, itemId);
    if (item == null) return false;

    final currentMainQty = item['quantity'] as int? ?? 0;
    final currentIndayQty = item['indayQuantity'] as int? ?? 0;

    // Check if enough stock in main inventory
    if (currentMainQty < quantity) {
      print('Transfer failed: Not enough stock in main inventory');
      return false;
    }

    final newMainQty = currentMainQty - quantity;
    final newIndayQty = currentIndayQty + quantity;

    // Check connectivity
    final hasConnection = await CacheService.hasConnectivity();

    if (hasConnection) {
      try {
        // Update both quantities in Firebase
        final updates = <String, dynamic>{
          'quantity': newMainQty,
          'indayQuantity': newIndayQty,
          'updatedAt': ServerValue.timestamp,
        };

        // Add tracking info for who updated Inday inventory
        if (transferredByEmail != null && transferredByName != null) {
          updates['lastIndayUpdatedBy'] = {
            'email': transferredByEmail,
            'name': transferredByName,
            'timestamp': ServerValue.timestamp,
            'action': 'transfer_to_inday',
          };
        }

        await _database.child('inventory/$category/$itemId').update(updates);

        // Log the transfer
        await _logStockChange(
          category: category,
          itemId: itemId,
          itemName: item['name'] as String? ?? 'Unknown',
          changeType: 'transfer_to_inday',
          quantityChange: quantity,
          previousQty: currentMainQty,
          newQty: newMainQty,
          reason: reason ?? 'Transferred to Inday Inventory',
          changedByEmail: transferredByEmail,
          changedByName: transferredByName,
        );

        // Clear cache to force refresh
        await CacheService.clearAllCache();

        print('Transferred $quantity items to Inday Inventory: $itemId');
        return true;
      } catch (e) {
        print('Error transferring to Inday online: $e');
        return false;
      }
    }

    print('Transfer failed: Device is offline');
    return false;
  }

  /// Return stock from Inday inventory to main inventory
  static Future<bool> returnFromInday({
    required String category,
    required String itemId,
    required int quantity,
    String? reason,
    String? returnedByEmail,
    String? returnedByName,
  }) async {
    // Get current item
    final item = await getItemById(category, itemId);
    if (item == null) return false;

    final currentMainQty = item['quantity'] as int? ?? 0;
    final currentIndayQty = item['indayQuantity'] as int? ?? 0;

    // Check if enough stock in Inday inventory
    if (currentIndayQty < quantity) {
      print('Return failed: Not enough stock in Inday inventory');
      return false;
    }

    final newMainQty = currentMainQty + quantity;
    final newIndayQty = currentIndayQty - quantity;

    // Check connectivity
    final hasConnection = await CacheService.hasConnectivity();

    if (hasConnection) {
      try {
        // Update both quantities in Firebase
        final updates = <String, dynamic>{
          'quantity': newMainQty,
          'indayQuantity': newIndayQty,
          'updatedAt': ServerValue.timestamp,
        };

        // Add tracking info for who updated Inday inventory
        if (returnedByEmail != null && returnedByName != null) {
          updates['lastIndayUpdatedBy'] = {
            'email': returnedByEmail,
            'name': returnedByName,
            'timestamp': ServerValue.timestamp,
            'action': 'return_from_inday',
          };
        }

        await _database.child('inventory/$category/$itemId').update(updates);

        // Log the return
        await _logStockChange(
          category: category,
          itemId: itemId,
          itemName: item['name'] as String? ?? 'Unknown',
          changeType: 'return_from_inday',
          quantityChange: quantity,
          previousQty: currentMainQty,
          newQty: newMainQty,
          reason: reason ?? 'Returned from Inday Inventory',
          changedByEmail: returnedByEmail,
          changedByName: returnedByName,
        );

        // Clear cache to force refresh
        await CacheService.clearAllCache();

        print('Returned $quantity items from Inday Inventory: $itemId');
        return true;
      } catch (e) {
        print('Error returning from Inday online: $e');
        return false;
      }
    }

    print('Return failed: Device is offline');
    return false;
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
      final isOutOfStock = newQty <= 0;
      final isLowStock = newQty > 0 && newQty <= reorderLevel;
      final stockDecreased = newQty < previousQty;

      // Debug logging for stock alerts
      debugPrint('🔔 Stock Alert Check: $itemName');
      debugPrint('  Previous: $previousQty → New: $newQty');
      debugPrint('  Reorder Level: $reorderLevel');
      debugPrint('  isOutOfStock: $isOutOfStock');
      debugPrint('  isLowStock: $isLowStock');
      debugPrint('  stockDecreased: $stockDecreased');

      if (isOutOfStock && previousQty > 0) {
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
      } else if (isLowStock && stockDecreased) {
        // Notify on EVERY decrease while in low stock zone
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

  static const String _excludedPrefixesKey = 'excluded_sku_prefixes';
  static const int _skuRangeStart = 7000000;
  static const int _skuRangeEnd = 7999999;

  /// Get list of excluded SKU prefixes from SharedPreferences
  static Future<List<String>> getExcludedPrefixes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_excludedPrefixesKey) ?? [];
    } catch (e) {
      debugPrint('Error loading excluded prefixes: $e');
      return [];
    }
  }

  /// Save excluded SKU prefixes to SharedPreferences
  static Future<void> saveExcludedPrefixes(List<String> prefixes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_excludedPrefixesKey, prefixes);
    } catch (e) {
      debugPrint('Error saving excluded prefixes: $e');
    }
  }

  /// Add a prefix to the excluded list
  static Future<void> addExcludedPrefix(String prefix) async {
    final prefixes = await getExcludedPrefixes();
    if (!prefixes.contains(prefix)) {
      prefixes.add(prefix);
      await saveExcludedPrefixes(prefixes);
    }
  }

  /// Remove a prefix from the excluded list
  static Future<void> removeExcludedPrefix(String prefix) async {
    final prefixes = await getExcludedPrefixes();
    prefixes.remove(prefix);
    await saveExcludedPrefixes(prefixes);
  }

  /// Check if a SKU starts with any excluded prefix
  static Future<bool> _startsWithExcludedPrefix(String sku) async {
    final excludedPrefixes = await getExcludedPrefixes();
    for (final prefix in excludedPrefixes) {
      if (sku.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }

  /// Check if a SKU already exists in the inventory
  static Future<bool> _skuExists(String sku, List<Map<String, dynamic>> allItems) async {
    final normalizedSku = sku.toLowerCase().trim();
    for (final item in allItems) {
      final itemSku = (item['sku'] as String? ?? item['serialNo'] as String? ?? '').toLowerCase().trim();
      if (itemSku == normalizedSku) {
        return true;
      }
    }
    return false;
  }

  /// Generate a unique random SKU in the 7000000-7999999 series.
  /// - Generates random numbers instead of incremental to prevent duplicates on multiple offline devices
  /// - Checks for uniqueness against all existing SKUs
  /// - Avoids SKUs that start with excluded prefixes
  /// - Retries up to maxAttempts times to find a unique number
  static Future<String> generateNextSku({int maxAttempts = 1000}) async {
    try {
      final allItems = await getAllItems();
      final random = Random();
      final range = _skuRangeEnd - _skuRangeStart + 1;

      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        // Generate random number in the 7000000-7999999 range
        final randomNumber = _skuRangeStart + random.nextInt(range);
        final candidateSku = randomNumber.toString();

        // Check if it starts with an excluded prefix
        if (await _startsWithExcludedPrefix(candidateSku)) {
          continue; // Try another number
        }

        // Check if it already exists
        if (await _skuExists(candidateSku, allItems)) {
          continue; // Try another number
        }

        // Found a unique SKU that doesn't start with excluded prefixes
        debugPrint('Generated unique SKU: $candidateSku (attempt ${attempt + 1})');
        return candidateSku;
      }

      // Fallback: If we couldn't find a unique number after maxAttempts,
      // use timestamp-based SKU to ensure uniqueness
      final fallbackSku = '7${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';
      debugPrint('Using fallback timestamp-based SKU: $fallbackSku');
      return fallbackSku;
    } catch (e) {
      debugPrint('Error generating random SKU: $e');
      // Emergency fallback with timestamp
      return '7${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';
    }
  }

  // ==================== DUPLICATE SKU MIGRATION ====================

  static const String _migrationVersionKey = 'sku_migration_version';
  static const int _currentMigrationVersion = 1;
  // ignore: prefer_final_fields
  static bool _migrationInProgress = false;

  /// Check if SKU migration has already been performed (checks both local and Firebase)
  static Future<bool> _hasMigrationRun() async {
    try {
      // First check local SharedPreferences (fast)
      final prefs = await SharedPreferences.getInstance();
      final localVersion = prefs.getInt(_migrationVersionKey) ?? 0;
      if (localVersion >= _currentMigrationVersion) {
        return true;
      }

      // Then check Firebase (for cross-device sync)
      try {
        final snapshot = await _database.child('system/sku_migration_version').get();
        if (snapshot.exists) {
          final firebaseVersion = snapshot.value as int? ?? 0;
          if (firebaseVersion >= _currentMigrationVersion) {
            // Sync local with Firebase
            await prefs.setInt(_migrationVersionKey, firebaseVersion);
            return true;
          }
        }
      } catch (e) {
        debugPrint('Error checking Firebase migration status: $e');
        // Continue with local check only
      }

      return false;
    } catch (e) {
      debugPrint('Error checking migration status: $e');
      return false;
    }
  }

  /// Mark migration as completed (both local and Firebase)
  static Future<void> _markMigrationComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_migrationVersionKey, _currentMigrationVersion);

      // Also mark in Firebase so other devices know
      try {
        await _database.child('system/sku_migration_version').set(_currentMigrationVersion);
      } catch (e) {
        debugPrint('Error marking Firebase migration complete: $e');
      }
    } catch (e) {
      debugPrint('Error marking migration complete: $e');
    }
  }

  static String? _currentLockDeviceId;
  static const int _lockTimeoutMs = 1800000; // 30 minutes for large inventories

  /// Acquire migration lock in Firebase to prevent multiple devices running at once
  static Future<bool> _acquireMigrationLock() async {
    try {
      _currentLockDeviceId = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}';
      final lockRef = _database.child('system/sku_migration_lock');

      // Check if lock exists and is recent (within 30 minutes)
      final snapshot = await lockRef.get();
      if (snapshot.exists) {
        final lockData = Map<String, dynamic>.from(snapshot.value as Map);
        final lockedAt = lockData['lockedAt'] as int? ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;

        // If lock is less than 30 minutes old, another device is running migration
        if (now - lockedAt < _lockTimeoutMs) {
          debugPrint('Migration lock held by another device. Skipping.');
          return false;
        }
      }

      // Acquire lock
      await lockRef.set({
        'deviceId': _currentLockDeviceId,
        'lockedAt': ServerValue.timestamp,
      });

      // Verify we got the lock (race condition protection)
      await Future.delayed(const Duration(milliseconds: 500));
      final verifySnapshot = await lockRef.get();
      if (verifySnapshot.exists) {
        final lockData = Map<String, dynamic>.from(verifySnapshot.value as Map);
        if (lockData['deviceId'] != _currentLockDeviceId) {
          debugPrint('Lost lock race to another device. Skipping.');
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error acquiring migration lock: $e');
      return false;
    }
  }

  /// Refresh the lock timestamp to prevent timeout during long migrations
  static Future<void> _refreshMigrationLock() async {
    if (_currentLockDeviceId == null) return;
    try {
      await _database.child('system/sku_migration_lock').update({
        'lockedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Error refreshing migration lock: $e');
    }
  }

  /// Release migration lock
  static Future<void> _releaseMigrationLock() async {
    try {
      await _database.child('system/sku_migration_lock').remove();
      _currentLockDeviceId = null;
    } catch (e) {
      debugPrint('Error releasing migration lock: $e');
    }
  }

  /// Find all duplicate SKUs in the inventory
  /// Returns a map of SKU -> list of items with that SKU
  static Future<Map<String, List<Map<String, dynamic>>>> _findDuplicateSkus() async {
    final allItems = await getAllItems();
    final skuMap = <String, List<Map<String, dynamic>>>{};

    for (final item in allItems) {
      final sku = (item['sku'] as String? ?? item['serialNo'] as String? ?? '').trim();
      if (sku.isEmpty) continue;

      final normalizedSku = sku.toLowerCase();
      if (!skuMap.containsKey(normalizedSku)) {
        skuMap[normalizedSku] = [];
      }
      skuMap[normalizedSku]!.add(item);
    }

    // Filter to only keep SKUs that have duplicates (more than 1 item)
    final duplicates = <String, List<Map<String, dynamic>>>{};
    for (final entry in skuMap.entries) {
      if (entry.value.length > 1) {
        duplicates[entry.key] = entry.value;
      }
    }

    return duplicates;
  }

  /// Generate a unique SKU that doesn't exist in the provided list
  static Future<String> _generateUniqueSkuExcluding(Set<String> existingSkus) async {
    final random = Random();
    const range = _skuRangeEnd - _skuRangeStart + 1;
    const maxAttempts = 1000;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final randomNumber = _skuRangeStart + random.nextInt(range);
      final candidateSku = randomNumber.toString();

      // Check excluded prefixes
      if (await _startsWithExcludedPrefix(candidateSku)) {
        continue;
      }

      // Check against provided existing SKUs
      if (existingSkus.contains(candidateSku.toLowerCase())) {
        continue;
      }

      return candidateSku;
    }

    // Fallback with timestamp
    return '7${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';
  }

  /// Check if device is online by trying to reach Firebase
  static Future<bool> _isOnline() async {
    try {
      // Use the same connectivity check as the rest of the app
      return await CacheService.hasConnectivity();
    } catch (e) {
      return false;
    }
  }

  /// Get list of already migrated item IDs (for resume functionality)
  static Future<Set<String>> _getAlreadyMigratedItemIds() async {
    try {
      final snapshot = await _database.child('system/sku_migration_log').get();
      if (!snapshot.exists) return {};

      final log = Map<String, dynamic>.from(snapshot.value as Map);
      final migratedIds = <String>{};
      for (final entry in log.values) {
        if (entry is Map && entry['itemId'] != null) {
          migratedIds.add(entry['itemId'].toString());
        }
      }
      return migratedIds;
    } catch (e) {
      debugPrint('Error loading migration log: $e');
      return {};
    }
  }

  /// Save a migration fix to Firebase log (for label reprinting reference)
  static Future<void> _logMigrationFix(Map<String, dynamic> fix) async {
    try {
      await _database.child('system/sku_migration_log').push().set({
        ...fix,
        'migratedAt': ServerValue.timestamp,
        'needsReprint': true, // Flag for label reprinting
      });
    } catch (e) {
      debugPrint('Error logging migration fix: $e');
    }
  }

  /// Get all items that need label reprinting after migration
  static Future<List<Map<String, dynamic>>> getItemsNeedingReprint() async {
    try {
      final snapshot = await _database.child('system/sku_migration_log')
          .orderByChild('needsReprint')
          .equalTo(true)
          .get();

      if (!snapshot.exists) return [];

      final items = <Map<String, dynamic>>[];
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      for (final entry in data.entries) {
        final item = Map<String, dynamic>.from(entry.value as Map);
        item['logKey'] = entry.key;
        items.add(item);
      }
      return items;
    } catch (e) {
      debugPrint('Error getting items needing reprint: $e');
      return [];
    }
  }

  /// Mark an item as reprinted (clear the needsReprint flag)
  static Future<void> markAsReprinted(String logKey) async {
    try {
      await _database.child('system/sku_migration_log/$logKey/needsReprint').set(false);
    } catch (e) {
      debugPrint('Error marking as reprinted: $e');
    }
  }

  /// Mark all items as reprinted (with batching for large logs)
  static Future<void> markAllAsReprinted() async {
    try {
      final snapshot = await _database.child('system/sku_migration_log').get();
      if (!snapshot.exists) return;

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final keys = data.keys.toList();

      // Process in batches of 20 with small delays to prevent rate limiting
      for (int i = 0; i < keys.length; i++) {
        await _database.child('system/sku_migration_log/${keys[i]}/needsReprint').set(false);

        // Small delay every 20 items
        if ((i + 1) % 20 == 0) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    } catch (e) {
      debugPrint('Error marking all as reprinted: $e');
    }
  }

  /// Clean up old migration logs (older than specified days)
  /// Call this periodically or after confirming all labels are reprinted
  static Future<int> cleanupOldMigrationLogs({int olderThanDays = 30}) async {
    try {
      final snapshot = await _database.child('system/sku_migration_log').get();
      if (!snapshot.exists) return 0;

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final cutoffTime = DateTime.now().subtract(Duration(days: olderThanDays)).millisecondsSinceEpoch;
      int deletedCount = 0;

      for (final entry in data.entries) {
        final logData = entry.value as Map?;
        if (logData == null) continue;

        final migratedAt = logData['migratedAt'] as int? ?? 0;
        final needsReprint = logData['needsReprint'] as bool? ?? false;

        // Only delete if older than cutoff AND already reprinted
        if (migratedAt < cutoffTime && !needsReprint) {
          await _database.child('system/sku_migration_log/${entry.key}').remove();
          deletedCount++;

          // Small delay every 10 deletions
          if (deletedCount % 10 == 0) {
            await Future.delayed(const Duration(milliseconds: 50));
          }
        }
      }

      if (deletedCount > 0) {
        debugPrint('Cleaned up $deletedCount old migration log entries');
      }
      return deletedCount;
    } catch (e) {
      debugPrint('Error cleaning up migration logs: $e');
      return 0;
    }
  }

  /// Get migration log statistics
  static Future<Map<String, dynamic>> getMigrationLogStats() async {
    try {
      final snapshot = await _database.child('system/sku_migration_log').get();
      if (!snapshot.exists) {
        return {
          'totalEntries': 0,
          'needsReprint': 0,
          'alreadyReprinted': 0,
        };
      }

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      int needsReprint = 0;
      int alreadyReprinted = 0;

      for (final entry in data.values) {
        final logData = entry as Map?;
        if (logData == null) continue;

        if (logData['needsReprint'] == true) {
          needsReprint++;
        } else {
          alreadyReprinted++;
        }
      }

      return {
        'totalEntries': data.length,
        'needsReprint': needsReprint,
        'alreadyReprinted': alreadyReprinted,
      };
    } catch (e) {
      debugPrint('Error getting migration log stats: $e');
      return {
        'totalEntries': 0,
        'needsReprint': 0,
        'alreadyReprinted': 0,
        'error': e.toString(),
      };
    }
  }

  /// Run the duplicate SKU migration
  /// - Finds all duplicate SKUs
  /// - Keeps the first item with the original SKU
  /// - Generates new unique SKUs for all other duplicates
  /// - Updates Firebase database
  /// - Logs changes for label reprinting
  /// - Supports resume if interrupted
  /// Returns a report of what was fixed
  static Future<Map<String, dynamic>> runDuplicateSkuMigration({bool force = false}) async {
    final report = <String, dynamic>{
      'success': false,
      'alreadyRun': false,
      'lockedByOther': false,
      'offline': false,
      'duplicatesFound': 0,
      'itemsFixed': 0,
      'itemsSkipped': 0, // Already migrated in previous partial run
      'errors': <String>[],
      'fixes': <Map<String, dynamic>>[],
    };

    // Prevent concurrent runs on same device
    if (_migrationInProgress) {
      report['errors'].add('Migration already in progress on this device');
      return report;
    }

    try {
      // Check if migration already ran (unless forced)
      if (!force && await _hasMigrationRun()) {
        report['alreadyRun'] = true;
        report['success'] = true;
        debugPrint('SKU migration already completed. Skipping.');
        return report;
      }

      // Check if device is online
      if (!await _isOnline()) {
        report['offline'] = true;
        report['errors'].add('Device is offline. Migration requires internet connection.');
        debugPrint('SKU migration skipped: Device is offline.');
        return report;
      }

      // Try to acquire lock to prevent multiple devices running simultaneously
      if (!await _acquireMigrationLock()) {
        report['lockedByOther'] = true;
        report['errors'].add('Migration is being run by another device. Try again later.');
        debugPrint('SKU migration locked by another device. Skipping.');
        return report;
      }

      _migrationInProgress = true;
      debugPrint('🔄 Starting duplicate SKU migration...');

      // Force refresh to get latest data from Firebase (not cache)
      forceRefresh();
      debugPrint('Fetching fresh data from Firebase...');

      // Get already migrated items (for resume functionality)
      final alreadyMigrated = await _getAlreadyMigratedItemIds();
      if (alreadyMigrated.isNotEmpty) {
        debugPrint('Resuming migration: ${alreadyMigrated.length} items already processed');
      }

      // Find all duplicates (using fresh data)
      final duplicates = await _findDuplicateSkus();
      report['duplicatesFound'] = duplicates.length;

      if (duplicates.isEmpty) {
        debugPrint('✅ No duplicate SKUs found. Migration complete.');
        await _markMigrationComplete();
        report['success'] = true;
        return report;
      }

      debugPrint('Found ${duplicates.length} duplicate SKU groups');

      // Collect all existing SKUs for uniqueness checking
      final allItems = await getAllItems();
      final allExistingSkus = <String>{};
      for (final item in allItems) {
        final sku = (item['sku'] as String? ?? item['serialNo'] as String? ?? '').toLowerCase().trim();
        if (sku.isNotEmpty) {
          allExistingSkus.add(sku);
        }
      }

      int processedCount = 0;
      final totalToProcess = duplicates.values.fold<int>(0, (sum, items) => sum + items.length - 1);

      // Process each duplicate group
      for (final entry in duplicates.entries) {
        final originalSku = entry.key;
        final items = entry.value;

        debugPrint('Processing duplicate SKU: $originalSku (${items.length} items)');

        // Keep the first item with original SKU, fix the rest
        for (int i = 1; i < items.length; i++) {
          final item = items[i];
          final itemId = item['id'] as String?;
          final category = item['category'] as String?;
          final itemName = item['name'] as String? ?? 'Unknown';

          if (itemId == null || category == null) {
            final error = 'Cannot fix item "$itemName" - missing id or category';
            report['errors'].add(error);
            debugPrint('⚠️ $error');
            continue;
          }

          // Skip if already migrated (resume functionality)
          if (alreadyMigrated.contains(itemId)) {
            report['itemsSkipped'] = (report['itemsSkipped'] as int) + 1;
            debugPrint('⏭️ Skipping already migrated: "$itemName"');
            continue;
          }

          try {
            // Generate new unique SKU
            final newSku = await _generateUniqueSkuExcluding(allExistingSkus);
            allExistingSkus.add(newSku.toLowerCase()); // Add to set to prevent reuse

            // Update in Firebase
            await _database.child('inventory/$category/$itemId/sku').set(newSku);

            // Also update serialNo field if it exists
            final hasSerialNo = item['serialNo'] != null;
            if (hasSerialNo) {
              await _database.child('inventory/$category/$itemId/serialNo').set(newSku);
            }

            final fix = {
              'itemId': itemId,
              'itemName': itemName,
              'category': category,
              'oldSku': originalSku,
              'newSku': newSku,
            };

            // Log to Firebase for label reprinting reference
            await _logMigrationFix(fix);

            report['fixes'].add(fix);
            report['itemsFixed'] = (report['itemsFixed'] as int) + 1;

            debugPrint('✅ Fixed: "$itemName" - $originalSku → $newSku');

            // Progress update
            processedCount++;
            if (processedCount % 10 == 0) {
              debugPrint('Progress: $processedCount / $totalToProcess items processed');
            }

            // Small delay and lock refresh to prevent rate limiting and lock timeout on large batches
            if (processedCount % 50 == 0) {
              await Future.delayed(const Duration(milliseconds: 100));
              await _refreshMigrationLock(); // Keep lock alive for large inventories
            }
          } catch (e) {
            final error = 'Failed to fix item "$itemName": $e';
            report['errors'].add(error);
            debugPrint('❌ $error');
            // Continue with next item instead of failing entire migration
          }
        }
      }

      // Clear cache to force refresh
      await CacheService.clearAllCache();
      forceRefresh();

      // Mark migration complete
      await _markMigrationComplete();

      report['success'] = true;
      debugPrint('🎉 SKU migration completed. Fixed ${report['itemsFixed']} items, skipped ${report['itemsSkipped']} already migrated.');

      return report;
    } catch (e) {
      final error = 'Migration failed: $e';
      report['errors'].add(error);
      debugPrint('❌ $error');
      return report;
    } finally {
      // Always release lock and reset flag
      _migrationInProgress = false;
      await _releaseMigrationLock();
    }
  }

  /// Check for duplicates without fixing (preview mode)
  static Future<Map<String, dynamic>> previewDuplicateSkus() async {
    final duplicates = await _findDuplicateSkus();

    final preview = <String, dynamic>{
      'totalDuplicateGroups': duplicates.length,
      'totalItemsAffected': 0,
      'duplicates': <Map<String, dynamic>>[],
    };

    for (final entry in duplicates.entries) {
      final items = entry.value;
      preview['totalItemsAffected'] = (preview['totalItemsAffected'] as int) + items.length - 1;

      preview['duplicates'].add({
        'sku': entry.key,
        'count': items.length,
        'items': items.map((item) => {
          'id': item['id'],
          'name': item['name'],
          'category': item['category'],
        }).toList(),
      });
    }

    return preview;
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
