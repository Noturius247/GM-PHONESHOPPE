import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// CacheService provides offline-first local storage using Hive.
/// Data is stored locally and synced with Firebase when online.
/// Optimized: Stores Maps directly without JSON encoding for better performance.
class CacheService {
  static const String _inventoryBoxName = 'inventory_cache_v2';
  static const String _customersBoxName = 'customers_cache_v2';
  static const String _gsatActivationsBoxName = 'gsat_activations_cache';
  static const String _posSettingsBoxName = 'pos_settings_cache';
  static const String _suggestionsBoxName = 'suggestions_cache';
  static const String _inventoryHistoryBoxName = 'inventory_history_cache';
  static const String _posTransactionsBoxName = 'pos_transactions_cache';
  static const String _pendingTransactionsBoxName = 'pending_transactions_queue';
  static const String _posBasketsBoxName = 'pos_baskets_cache';
  static const String _posItemRequestsBoxName = 'pos_item_requests_cache';
  static const String _staffPinsBoxName = 'staff_pins_cache';
  static const String _syncMetadataBoxName = 'sync_metadata';
  static const String _pendingOperationsBoxName = 'pending_operations_queue';

  static Box? _inventoryBox;
  static Box? _customersBox;
  static Box? _gsatActivationsBox;
  static Box? _posSettingsBox;
  static Box? _suggestionsBox;
  static Box? _inventoryHistoryBox;
  static Box? _posTransactionsBox;
  static Box? _pendingTransactionsBox;
  static Box? _posBasketsBox;
  static Box? _posItemRequestsBox;
  static Box? _staffPinsBox;
  static Box? _syncMetadataBox;
  static Box? _pendingOperationsBox;

  static bool _isInitialized = false;

  /// Initialize Hive and open all required boxes
  static Future<void> initialize() async {
    if (_isInitialized) return;

    await Hive.initFlutter();

    _inventoryBox = await Hive.openBox(_inventoryBoxName);
    _customersBox = await Hive.openBox(_customersBoxName);
    _gsatActivationsBox = await Hive.openBox(_gsatActivationsBoxName);
    _posSettingsBox = await Hive.openBox(_posSettingsBoxName);
    _suggestionsBox = await Hive.openBox(_suggestionsBoxName);
    _inventoryHistoryBox = await Hive.openBox(_inventoryHistoryBoxName);
    _posTransactionsBox = await Hive.openBox(_posTransactionsBoxName);
    _pendingTransactionsBox = await Hive.openBox(_pendingTransactionsBoxName);
    _posBasketsBox = await Hive.openBox(_posBasketsBoxName);
    _posItemRequestsBox = await Hive.openBox(_posItemRequestsBoxName);
    _staffPinsBox = await Hive.openBox(_staffPinsBoxName);
    _syncMetadataBox = await Hive.openBox(_syncMetadataBoxName);
    _pendingOperationsBox = await Hive.openBox(_pendingOperationsBoxName);

    _isInitialized = true;
    print('CacheService initialized');
  }

  /// Check if device has internet connectivity
  static Future<bool> hasConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  // ==================== INVENTORY CACHE ====================

  /// Save all inventory items to local cache (batch operation)
  static Future<void> saveInventoryItems(List<Map<String, dynamic>> items) async {
    if (_inventoryBox == null) await initialize();

    // Use putAll for better performance on bulk operations
    final Map<String, Map<String, dynamic>> batch = {};
    for (var item in items) {
      final id = item['id'] as String?;
      if (id != null) {
        batch[id] = item;
      }
    }

    // Clear and save in batch
    await _inventoryBox!.clear();
    await _inventoryBox!.putAll(batch);

    // Update sync timestamp
    await _setSyncTimestamp('inventory', DateTime.now().millisecondsSinceEpoch);
    print('Cached ${items.length} inventory items');
  }

  /// Save a single inventory item to cache
  static Future<void> saveInventoryItem(Map<String, dynamic> item) async {
    if (_inventoryBox == null) await initialize();

    final id = item['id'] as String?;
    if (id != null) {
      // Store Map directly - no JSON encoding needed
      await _inventoryBox!.put(id, Map<String, dynamic>.from(item));
    }
  }

  /// Get all inventory items from local cache
  static Future<List<Map<String, dynamic>>> getInventoryItems() async {
    if (_inventoryBox == null) await initialize();

    final List<Map<String, dynamic>> items = [];

    for (var key in _inventoryBox!.keys) {
      final data = _inventoryBox!.get(key);
      if (data != null) {
        // Convert to Map<String, dynamic> to ensure proper typing
        items.add(Map<String, dynamic>.from(data as Map));
      }
    }

    return items;
  }

  /// Get inventory items by category from cache
  static Future<List<Map<String, dynamic>>> getInventoryItemsByCategory(String category) async {
    final allItems = await getInventoryItems();
    return allItems.where((item) => item['category'] == category).toList();
  }

  /// Delete an inventory item from cache
  static Future<void> deleteInventoryItem(String itemId) async {
    if (_inventoryBox == null) await initialize();
    await _inventoryBox!.delete(itemId);
  }

  /// Check if inventory cache has data
  static Future<bool> hasInventoryCache() async {
    if (_inventoryBox == null) await initialize();
    return _inventoryBox!.isNotEmpty;
  }

  // ==================== CUSTOMERS CACHE ====================

  /// Save all customers for a service type to local cache (batch operation)
  static Future<void> saveCustomers(String serviceType, List<Map<String, dynamic>> customers) async {
    if (_customersBox == null) await initialize();

    // First, remove existing customers for this service type
    final keysToDelete = _customersBox!.keys
        .where((key) => key.toString().startsWith('${serviceType}_'))
        .toList();
    await _customersBox!.deleteAll(keysToDelete);

    // Batch save new customers
    final Map<String, Map<String, dynamic>> batch = {};
    for (var customer in customers) {
      final id = customer['id'] as String?;
      if (id != null) {
        batch['${serviceType}_$id'] = customer;
      }
    }
    await _customersBox!.putAll(batch);

    // Update sync timestamp
    await _setSyncTimestamp('customers_$serviceType', DateTime.now().millisecondsSinceEpoch);
    print('Cached ${customers.length} $serviceType customers');
  }

  /// Save a single customer to cache
  static Future<void> saveCustomer(String serviceType, Map<String, dynamic> customer) async {
    if (_customersBox == null) await initialize();

    final id = customer['id'] as String?;
    if (id != null) {
      // Store Map directly - no JSON encoding needed
      await _customersBox!.put('${serviceType}_$id', Map<String, dynamic>.from(customer));
    }
  }

  /// Get all customers for a service type from local cache
  static Future<List<Map<String, dynamic>>> getCustomers(String serviceType) async {
    if (_customersBox == null) await initialize();

    final List<Map<String, dynamic>> customers = [];
    final prefix = '${serviceType}_';

    for (var key in _customersBox!.keys) {
      if (key.toString().startsWith(prefix)) {
        final data = _customersBox!.get(key);
        if (data != null) {
          customers.add(Map<String, dynamic>.from(data as Map));
        }
      }
    }

    return customers;
  }

  /// Delete a customer from cache
  static Future<void> deleteCustomer(String serviceType, String customerId) async {
    if (_customersBox == null) await initialize();
    await _customersBox!.delete('${serviceType}_$customerId');
  }

  /// Check if customers cache has data for a service type
  static Future<bool> hasCustomersCache(String serviceType) async {
    if (_customersBox == null) await initialize();
    final prefix = '${serviceType}_';
    return _customersBox!.keys.any((key) => key.toString().startsWith(prefix));
  }

  // ==================== GSAT ACTIVATIONS CACHE ====================

  /// Save all GSAT activations to local cache (batch operation)
  static Future<void> saveGsatActivations(List<Map<String, dynamic>> activations) async {
    if (_gsatActivationsBox == null) await initialize();

    final Map<String, Map<String, dynamic>> batch = {};
    for (var activation in activations) {
      final id = activation['id'] as String?;
      if (id != null) {
        batch[id] = activation;
      }
    }

    await _gsatActivationsBox!.clear();
    await _gsatActivationsBox!.putAll(batch);

    await _setSyncTimestamp('gsat_activations', DateTime.now().millisecondsSinceEpoch);
    print('Cached ${activations.length} GSAT activations');
  }

  /// Save a single GSAT activation to cache
  static Future<void> saveGsatActivation(Map<String, dynamic> activation) async {
    if (_gsatActivationsBox == null) await initialize();

    final id = activation['id'] as String?;
    if (id != null) {
      await _gsatActivationsBox!.put(id, Map<String, dynamic>.from(activation));
    }
  }

  /// Get all GSAT activations from local cache
  static Future<List<Map<String, dynamic>>> getGsatActivations() async {
    if (_gsatActivationsBox == null) await initialize();

    final List<Map<String, dynamic>> activations = [];
    for (var key in _gsatActivationsBox!.keys) {
      final data = _gsatActivationsBox!.get(key);
      if (data != null) {
        activations.add(Map<String, dynamic>.from(data as Map));
      }
    }
    return activations;
  }

  /// Delete a GSAT activation from cache
  static Future<void> deleteGsatActivation(String activationId) async {
    if (_gsatActivationsBox == null) await initialize();
    await _gsatActivationsBox!.delete(activationId);
  }

  /// Check if GSAT activations cache has data
  static Future<bool> hasGsatActivationsCache() async {
    if (_gsatActivationsBox == null) await initialize();
    return _gsatActivationsBox!.isNotEmpty;
  }

  // ==================== POS SETTINGS CACHE ====================

  /// Save POS settings to local cache
  static Future<void> savePosSettings(Map<String, dynamic> settings) async {
    if (_posSettingsBox == null) await initialize();
    await _posSettingsBox!.put('settings', Map<String, dynamic>.from(settings));
    await _setSyncTimestamp('pos_settings', DateTime.now().millisecondsSinceEpoch);
  }

  /// Get POS settings from local cache
  static Future<Map<String, dynamic>?> getPosSettings() async {
    if (_posSettingsBox == null) await initialize();
    final data = _posSettingsBox!.get('settings');
    if (data != null) {
      return Map<String, dynamic>.from(data as Map);
    }
    return null;
  }

  /// Check if POS settings cache has data
  static Future<bool> hasPosSettingsCache() async {
    if (_posSettingsBox == null) await initialize();
    return _posSettingsBox!.containsKey('settings');
  }

  // ==================== SUGGESTIONS CACHE ====================

  /// Save all suggestions for a service type to local cache (batch operation)
  static Future<void> saveSuggestions(String serviceType, List<Map<String, dynamic>> suggestions) async {
    if (_suggestionsBox == null) await initialize();

    // Remove existing suggestions for this service type
    final keysToDelete = _suggestionsBox!.keys
        .where((key) => key.toString().startsWith('${serviceType}_'))
        .toList();
    await _suggestionsBox!.deleteAll(keysToDelete);

    // Batch save new suggestions
    final Map<String, Map<String, dynamic>> batch = {};
    for (var suggestion in suggestions) {
      final id = suggestion['id'] as String?;
      if (id != null) {
        batch['${serviceType}_$id'] = suggestion;
      }
    }
    await _suggestionsBox!.putAll(batch);

    await _setSyncTimestamp('suggestions_$serviceType', DateTime.now().millisecondsSinceEpoch);
    print('Cached ${suggestions.length} $serviceType suggestions');
  }

  /// Save a single suggestion to cache
  static Future<void> saveSuggestion(String serviceType, Map<String, dynamic> suggestion) async {
    if (_suggestionsBox == null) await initialize();

    final id = suggestion['id'] as String?;
    if (id != null) {
      await _suggestionsBox!.put('${serviceType}_$id', Map<String, dynamic>.from(suggestion));
    }
  }

  /// Get all suggestions for a service type from local cache
  static Future<List<Map<String, dynamic>>> getSuggestions(String serviceType) async {
    if (_suggestionsBox == null) await initialize();

    final List<Map<String, dynamic>> suggestions = [];
    final prefix = '${serviceType}_';

    for (var key in _suggestionsBox!.keys) {
      if (key.toString().startsWith(prefix)) {
        final data = _suggestionsBox!.get(key);
        if (data != null) {
          suggestions.add(Map<String, dynamic>.from(data as Map));
        }
      }
    }
    return suggestions;
  }

  /// Delete a suggestion from cache
  static Future<void> deleteSuggestion(String serviceType, String suggestionId) async {
    if (_suggestionsBox == null) await initialize();
    await _suggestionsBox!.delete('${serviceType}_$suggestionId');
  }

  /// Check if suggestions cache has data for a service type
  static Future<bool> hasSuggestionsCache(String serviceType) async {
    if (_suggestionsBox == null) await initialize();
    final prefix = '${serviceType}_';
    return _suggestionsBox!.keys.any((key) => key.toString().startsWith(prefix));
  }

  // ==================== INVENTORY HISTORY CACHE ====================

  /// Save all inventory history records to local cache (batch operation)
  static Future<void> saveInventoryHistory(List<Map<String, dynamic>> records) async {
    if (_inventoryHistoryBox == null) await initialize();

    final Map<String, Map<String, dynamic>> batch = {};
    for (var record in records) {
      final id = record['id'] as String?;
      if (id != null) {
        batch[id] = record;
      }
    }

    await _inventoryHistoryBox!.clear();
    await _inventoryHistoryBox!.putAll(batch);

    await _setSyncTimestamp('inventory_history', DateTime.now().millisecondsSinceEpoch);
    print('Cached ${records.length} inventory history records');
  }

  /// Save a single inventory history record to cache
  static Future<void> saveInventoryHistoryRecord(Map<String, dynamic> record) async {
    if (_inventoryHistoryBox == null) await initialize();

    final id = record['id'] as String?;
    if (id != null) {
      await _inventoryHistoryBox!.put(id, Map<String, dynamic>.from(record));
    }
  }

  /// Get all inventory history records from local cache
  static Future<List<Map<String, dynamic>>> getInventoryHistory() async {
    if (_inventoryHistoryBox == null) await initialize();

    final List<Map<String, dynamic>> records = [];
    for (var key in _inventoryHistoryBox!.keys) {
      final data = _inventoryHistoryBox!.get(key);
      if (data != null) {
        records.add(Map<String, dynamic>.from(data as Map));
      }
    }
    return records;
  }

  /// Get inventory history for a specific item
  static Future<List<Map<String, dynamic>>> getInventoryHistoryByItem(String itemId) async {
    final allRecords = await getInventoryHistory();
    return allRecords.where((record) => record['itemId'] == itemId).toList();
  }

  /// Delete an inventory history record from cache
  static Future<void> deleteInventoryHistoryRecord(String recordId) async {
    if (_inventoryHistoryBox == null) await initialize();
    await _inventoryHistoryBox!.delete(recordId);
  }

  /// Check if inventory history cache has data
  static Future<bool> hasInventoryHistoryCache() async {
    if (_inventoryHistoryBox == null) await initialize();
    return _inventoryHistoryBox!.isNotEmpty;
  }

  // ==================== POS TRANSACTIONS CACHE ====================

  /// Save all POS transactions to local cache (batch operation)
  static Future<void> savePosTransactions(List<Map<String, dynamic>> transactions) async {
    if (_posTransactionsBox == null) await initialize();

    final Map<String, Map<String, dynamic>> batch = {};
    for (var transaction in transactions) {
      final id = transaction['transactionId'] as String?;
      if (id != null) {
        batch[id] = transaction;
      }
    }

    await _posTransactionsBox!.clear();
    await _posTransactionsBox!.putAll(batch);

    await _setSyncTimestamp('pos_transactions', DateTime.now().millisecondsSinceEpoch);
    print('Cached ${transactions.length} POS transactions');
  }

  /// Save a single POS transaction to cache
  static Future<void> savePosTransaction(Map<String, dynamic> transaction) async {
    if (_posTransactionsBox == null) await initialize();

    final id = transaction['transactionId'] as String?;
    if (id != null) {
      await _posTransactionsBox!.put(id, Map<String, dynamic>.from(transaction));
    }
  }

  /// Get all POS transactions from local cache
  static Future<List<Map<String, dynamic>>> getPosTransactions() async {
    if (_posTransactionsBox == null) await initialize();

    final List<Map<String, dynamic>> transactions = [];
    for (var key in _posTransactionsBox!.keys) {
      final data = _posTransactionsBox!.get(key);
      if (data != null) {
        transactions.add(Map<String, dynamic>.from(data as Map));
      }
    }
    return transactions;
  }

  /// Get POS transactions by date
  static Future<List<Map<String, dynamic>>> getPosTransactionsByDate(String date) async {
    final allTransactions = await getPosTransactions();
    return allTransactions.where((t) => t['date'] == date).toList();
  }

  /// Delete a POS transaction from cache
  static Future<void> deletePosTransaction(String transactionId) async {
    if (_posTransactionsBox == null) await initialize();
    await _posTransactionsBox!.delete(transactionId);
  }

  /// Check if POS transactions cache has data
  static Future<bool> hasPosTransactionsCache() async {
    if (_posTransactionsBox == null) await initialize();
    return _posTransactionsBox!.isNotEmpty;
  }

  // ==================== PENDING OFFLINE TRANSACTIONS ====================

  /// Save a transaction to the offline pending queue
  static Future<void> savePendingTransaction(Map<String, dynamic> transaction) async {
    if (_pendingTransactionsBox == null) await initialize();

    final id = transaction['transactionId'] as String?;
    if (id != null) {
      // Mark as pending sync
      final pendingTransaction = Map<String, dynamic>.from(transaction);
      pendingTransaction['syncStatus'] = 'pending';
      pendingTransaction['createdOfflineAt'] = DateTime.now().toIso8601String();
      await _pendingTransactionsBox!.put(id, pendingTransaction);
      print('Saved pending transaction: $id');
    }
  }

  /// Get all pending transactions from the offline queue
  static Future<List<Map<String, dynamic>>> getPendingTransactions() async {
    if (_pendingTransactionsBox == null) await initialize();

    final List<Map<String, dynamic>> transactions = [];
    for (var key in _pendingTransactionsBox!.keys) {
      final data = _pendingTransactionsBox!.get(key);
      if (data != null) {
        transactions.add(Map<String, dynamic>.from(data as Map));
      }
    }
    return transactions;
  }

  /// Get count of pending transactions
  static Future<int> getPendingTransactionCount() async {
    if (_pendingTransactionsBox == null) await initialize();
    return _pendingTransactionsBox!.length;
  }

  /// Remove a transaction from the pending queue (after successful sync)
  static Future<void> removePendingTransaction(String transactionId) async {
    if (_pendingTransactionsBox == null) await initialize();
    await _pendingTransactionsBox!.delete(transactionId);
    print('Removed pending transaction: $transactionId');
  }

  /// Check if there are pending transactions to sync
  static Future<bool> hasPendingTransactions() async {
    if (_pendingTransactionsBox == null) await initialize();
    return _pendingTransactionsBox!.isNotEmpty;
  }

  /// Update sync status of a pending transaction
  static Future<void> updatePendingTransactionStatus(String transactionId, String status, {String? error}) async {
    if (_pendingTransactionsBox == null) await initialize();

    final data = _pendingTransactionsBox!.get(transactionId);
    if (data != null) {
      final transaction = Map<String, dynamic>.from(data as Map);
      transaction['syncStatus'] = status;
      if (error != null) {
        transaction['syncError'] = error;
      }
      transaction['lastSyncAttempt'] = DateTime.now().toIso8601String();
      await _pendingTransactionsBox!.put(transactionId, transaction);
    }
  }

  /// Get failed transactions that need retry
  static Future<List<Map<String, dynamic>>> getFailedTransactions() async {
    if (_pendingTransactionsBox == null) await initialize();

    final List<Map<String, dynamic>> failed = [];
    for (var key in _pendingTransactionsBox!.keys) {
      final data = _pendingTransactionsBox!.get(key);
      if (data != null) {
        final transaction = Map<String, dynamic>.from(data as Map);
        if (transaction['syncStatus'] == 'failed') {
          failed.add(transaction);
        }
      }
    }
    return failed;
  }

  /// Reset failed transactions to pending for retry
  static Future<void> resetFailedTransactionsForRetry() async {
    if (_pendingTransactionsBox == null) await initialize();

    for (var key in _pendingTransactionsBox!.keys) {
      final data = _pendingTransactionsBox!.get(key);
      if (data != null) {
        final transaction = Map<String, dynamic>.from(data as Map);
        if (transaction['syncStatus'] == 'failed') {
          transaction['syncStatus'] = 'pending';
          transaction['retryCount'] = (transaction['retryCount'] ?? 0) + 1;
          await _pendingTransactionsBox!.put(key, transaction);
        }
      }
    }
  }

  // ==================== POS BASKETS CACHE ====================

  /// Save all POS baskets to local cache (batch operation)
  static Future<void> savePosBaskets(List<Map<String, dynamic>> baskets) async {
    if (_posBasketsBox == null) await initialize();

    final Map<String, Map<String, dynamic>> batch = {};
    for (var basket in baskets) {
      final key = basket['firebaseKey'] as String? ?? basket['id'] as String?;
      if (key != null) {
        batch[key] = basket;
      }
    }

    await _posBasketsBox!.clear();
    await _posBasketsBox!.putAll(batch);

    await _setSyncTimestamp('pos_baskets', DateTime.now().millisecondsSinceEpoch);
    print('Cached ${baskets.length} POS baskets');
  }

  /// Save a single POS basket to cache
  static Future<void> savePosBasket(Map<String, dynamic> basket) async {
    if (_posBasketsBox == null) await initialize();

    final key = basket['firebaseKey'] as String? ?? basket['id'] as String?;
    if (key != null) {
      await _posBasketsBox!.put(key, Map<String, dynamic>.from(basket));
    }
  }

  /// Save a pending POS basket that needs to sync to Firebase
  static Future<void> savePendingPosBasket(Map<String, dynamic> basket) async {
    if (_posBasketsBox == null) await initialize();

    final key = basket['firebaseKey'] as String? ?? basket['id'] as String?;
    if (key != null) {
      final pendingBasket = Map<String, dynamic>.from(basket);
      pendingBasket['_needsSync'] = true;
      pendingBasket['_createdOfflineAt'] = DateTime.now().toIso8601String();
      await _posBasketsBox!.put(key, pendingBasket);
      print('Saved pending basket: $key');
    }
  }

  /// Get all baskets that need to sync to Firebase
  static Future<List<Map<String, dynamic>>> getPendingPosBaskets() async {
    if (_posBasketsBox == null) await initialize();

    final List<Map<String, dynamic>> pending = [];
    for (var key in _posBasketsBox!.keys) {
      final data = _posBasketsBox!.get(key);
      if (data != null) {
        final basket = Map<String, dynamic>.from(data as Map);
        if (basket['_needsSync'] == true) {
          pending.add(basket);
        }
      }
    }
    return pending;
  }

  /// Mark a basket as synced (remove pending flag)
  static Future<void> markPosBasketSynced(String basketKey) async {
    if (_posBasketsBox == null) await initialize();

    final data = _posBasketsBox!.get(basketKey);
    if (data != null) {
      final basket = Map<String, dynamic>.from(data as Map);
      basket.remove('_needsSync');
      basket.remove('_createdOfflineAt');
      await _posBasketsBox!.put(basketKey, basket);
    }
  }

  /// Get all pending POS baskets from local cache
  static Future<List<Map<String, dynamic>>> getPosBaskets({String? status}) async {
    if (_posBasketsBox == null) await initialize();

    final List<Map<String, dynamic>> baskets = [];
    for (var key in _posBasketsBox!.keys) {
      final data = _posBasketsBox!.get(key);
      if (data != null) {
        final basket = Map<String, dynamic>.from(data as Map);
        if (status == null || basket['status'] == status) {
          baskets.add(basket);
        }
      }
    }
    return baskets;
  }

  /// Delete a POS basket from cache
  static Future<void> deletePosBasket(String basketKey) async {
    if (_posBasketsBox == null) await initialize();
    await _posBasketsBox!.delete(basketKey);
  }

  /// Check if POS baskets cache has data
  static Future<bool> hasPosBasketsCache() async {
    if (_posBasketsBox == null) await initialize();
    return _posBasketsBox!.isNotEmpty;
  }

  // ==================== POS ITEM REQUESTS CACHE ====================

  /// Save all POS item requests to local cache (batch operation)
  static Future<void> savePosItemRequests(List<Map<String, dynamic>> requests) async {
    if (_posItemRequestsBox == null) await initialize();

    final Map<String, Map<String, dynamic>> batch = {};
    for (var request in requests) {
      final id = request['id'] as String?;
      if (id != null) {
        batch[id] = request;
      }
    }

    await _posItemRequestsBox!.clear();
    await _posItemRequestsBox!.putAll(batch);

    await _setSyncTimestamp('pos_item_requests', DateTime.now().millisecondsSinceEpoch);
    print('Cached ${requests.length} POS item requests');
  }

  /// Save a single POS item request to cache
  static Future<void> savePosItemRequest(Map<String, dynamic> request) async {
    if (_posItemRequestsBox == null) await initialize();

    final id = request['id'] as String?;
    if (id != null) {
      await _posItemRequestsBox!.put(id, Map<String, dynamic>.from(request));
    }
  }

  /// Save a pending POS item request that needs to sync to Firebase
  static Future<void> savePendingPosItemRequest(Map<String, dynamic> request) async {
    if (_posItemRequestsBox == null) await initialize();

    final id = request['id'] as String?;
    if (id != null) {
      final pendingRequest = Map<String, dynamic>.from(request);
      pendingRequest['_needsSync'] = true;
      pendingRequest['_createdOfflineAt'] = DateTime.now().toIso8601String();
      await _posItemRequestsBox!.put(id, pendingRequest);
    }
  }

  /// Get all item requests that need to sync to Firebase
  static Future<List<Map<String, dynamic>>> getPendingPosItemRequests() async {
    if (_posItemRequestsBox == null) await initialize();

    final List<Map<String, dynamic>> pending = [];
    for (var key in _posItemRequestsBox!.keys) {
      final data = _posItemRequestsBox!.get(key);
      if (data != null) {
        final request = Map<String, dynamic>.from(data as Map);
        if (request['_needsSync'] == true) {
          pending.add(request);
        }
      }
    }
    return pending;
  }

  /// Mark an item request as synced
  static Future<void> markPosItemRequestSynced(String requestId) async {
    if (_posItemRequestsBox == null) await initialize();

    final data = _posItemRequestsBox!.get(requestId);
    if (data != null) {
      final request = Map<String, dynamic>.from(data as Map);
      request.remove('_needsSync');
      request.remove('_createdOfflineAt');
      await _posItemRequestsBox!.put(requestId, request);
    }
  }

  /// Get all POS item requests from local cache
  static Future<List<Map<String, dynamic>>> getPosItemRequests({String? status}) async {
    if (_posItemRequestsBox == null) await initialize();

    final List<Map<String, dynamic>> requests = [];
    for (var key in _posItemRequestsBox!.keys) {
      final data = _posItemRequestsBox!.get(key);
      if (data != null) {
        final request = Map<String, dynamic>.from(data as Map);
        if (status == null || request['status'] == status) {
          requests.add(request);
        }
      }
    }
    return requests;
  }

  /// Delete a POS item request from cache
  static Future<void> deletePosItemRequest(String requestId) async {
    if (_posItemRequestsBox == null) await initialize();
    await _posItemRequestsBox!.delete(requestId);
  }

  /// Check if POS item requests cache has data
  static Future<bool> hasPosItemRequestsCache() async {
    if (_posItemRequestsBox == null) await initialize();
    return _posItemRequestsBox!.isNotEmpty;
  }

  // ==================== STAFF PINS CACHE ====================

  /// Save all staff PINs to local cache
  static Future<void> saveStaffPins(Map<String, Map<String, dynamic>> pins) async {
    if (_staffPinsBox == null) await initialize();
    await _staffPinsBox!.clear();
    for (final entry in pins.entries) {
      await _staffPinsBox!.put(entry.key, entry.value);
    }
    await _setSyncTimestamp('staff_pins', DateTime.now().millisecondsSinceEpoch);
  }

  /// Lookup a PIN from cache. Returns {email, name, userId} or null.
  static Future<Map<String, dynamic>?> getStaffByPin(String pin) async {
    if (_staffPinsBox == null) await initialize();
    final data = _staffPinsBox!.get(pin);
    if (data != null) {
      return Map<String, dynamic>.from(data as Map);
    }
    return null;
  }

  /// Check if staff PINs cache has data
  static Future<bool> hasStaffPinsCache() async {
    if (_staffPinsBox == null) await initialize();
    return _staffPinsBox!.isNotEmpty;
  }

  // ==================== PENDING OPERATIONS QUEUE ====================
  // Generic queue for all pending Firebase operations (inventory, customers, suggestions, etc.)

  /// Save a pending operation to the queue
  /// operationType: 'inventory_add', 'inventory_update', 'inventory_delete',
  ///                'customer_add', 'customer_update', 'customer_delete',
  ///                'suggestion_submit', 'suggestion_approve', 'suggestion_reject', 'suggestion_delete',
  ///                'gsat_add', 'gsat_update', 'gsat_delete',
  ///                'invitation_add', 'stock_add', 'stock_remove', 'stock_set', etc.
  static Future<String> savePendingOperation({
    required String operationType,
    required Map<String, dynamic> data,
    String? entityId,
  }) async {
    if (_pendingOperationsBox == null) await initialize();

    final id = '${operationType}_${DateTime.now().millisecondsSinceEpoch}';
    final pendingOp = {
      'id': id,
      'operationType': operationType,
      'data': data,
      'entityId': entityId,
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
      'retryCount': 0,
    };

    await _pendingOperationsBox!.put(id, pendingOp);
    print('Saved pending operation: $operationType ($id)');
    return id;
  }

  /// Get all pending operations
  static Future<List<Map<String, dynamic>>> getPendingOperations() async {
    if (_pendingOperationsBox == null) await initialize();

    final List<Map<String, dynamic>> operations = [];
    for (var key in _pendingOperationsBox!.keys) {
      final data = _pendingOperationsBox!.get(key);
      if (data != null) {
        operations.add(Map<String, dynamic>.from(data as Map));
      }
    }
    return operations;
  }

  /// Get pending operations by type
  static Future<List<Map<String, dynamic>>> getPendingOperationsByType(String operationType) async {
    final all = await getPendingOperations();
    return all.where((op) =>
      op['operationType'] == operationType && op['status'] == 'pending'
    ).toList();
  }

  /// Get pending operations by type prefix (e.g., 'inventory_' gets all inventory operations)
  static Future<List<Map<String, dynamic>>> getPendingOperationsByPrefix(String prefix) async {
    final all = await getPendingOperations();
    return all.where((op) =>
      (op['operationType'] as String).startsWith(prefix) && op['status'] == 'pending'
    ).toList();
  }

  /// Get count of all pending operations
  static Future<int> getPendingOperationsCount() async {
    final all = await getPendingOperations();
    return all.where((op) => op['status'] == 'pending').length;
  }

  /// Remove a pending operation (after successful sync)
  static Future<void> removePendingOperation(String operationId) async {
    if (_pendingOperationsBox == null) await initialize();
    await _pendingOperationsBox!.delete(operationId);
    print('Removed pending operation: $operationId');
  }

  /// Update status of a pending operation
  static Future<void> updatePendingOperationStatus(String operationId, String status, {String? error}) async {
    if (_pendingOperationsBox == null) await initialize();

    final data = _pendingOperationsBox!.get(operationId);
    if (data != null) {
      final operation = Map<String, dynamic>.from(data as Map);
      operation['status'] = status;
      if (error != null) {
        operation['error'] = error;
      }
      operation['lastAttempt'] = DateTime.now().toIso8601String();
      if (status == 'failed') {
        operation['retryCount'] = (operation['retryCount'] ?? 0) + 1;
      }
      await _pendingOperationsBox!.put(operationId, operation);
    }
  }

  /// Reset all failed operations to pending for retry
  static Future<void> resetFailedOperationsForRetry() async {
    if (_pendingOperationsBox == null) await initialize();

    for (var key in _pendingOperationsBox!.keys) {
      final data = _pendingOperationsBox!.get(key);
      if (data != null) {
        final operation = Map<String, dynamic>.from(data as Map);
        if (operation['status'] == 'failed') {
          operation['status'] = 'pending';
          await _pendingOperationsBox!.put(key, operation);
        }
      }
    }
  }

  /// Check if there are any pending operations
  static Future<bool> hasPendingOperations() async {
    if (_pendingOperationsBox == null) await initialize();
    final all = await getPendingOperations();
    return all.any((op) => op['status'] == 'pending');
  }

  // ==================== SYNC METADATA ====================

  /// Set last sync timestamp for a data type
  static Future<void> _setSyncTimestamp(String dataType, int timestamp) async {
    if (_syncMetadataBox == null) await initialize();
    await _syncMetadataBox!.put('lastSync_$dataType', timestamp);
  }

  /// Get last sync timestamp for a data type
  static Future<int?> getLastSyncTimestamp(String dataType) async {
    if (_syncMetadataBox == null) await initialize();
    return _syncMetadataBox!.get('lastSync_$dataType') as int?;
  }

  /// Check if data needs to be synced (older than specified duration)
  static Future<bool> needsSync(String dataType, {Duration maxAge = const Duration(minutes: 5)}) async {
    final lastSync = await getLastSyncTimestamp(dataType);
    if (lastSync == null) return true;

    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - lastSync) > maxAge.inMilliseconds;
  }

  /// Mark that initial sync has been completed
  static Future<void> setInitialSyncCompleted(String dataType) async {
    if (_syncMetadataBox == null) await initialize();
    await _syncMetadataBox!.put('initialSync_$dataType', true);
  }

  /// Check if initial sync has been completed
  static Future<bool> isInitialSyncCompleted(String dataType) async {
    if (_syncMetadataBox == null) await initialize();
    return _syncMetadataBox!.get('initialSync_$dataType') ?? false;
  }

  // ==================== UTILITIES ====================

  /// Clear all cached data (excluding pending data to prevent data loss)
  static Future<void> clearAllCache({bool includePendingData = false}) async {
    if (_inventoryBox != null) await _inventoryBox!.clear();
    if (_customersBox != null) await _customersBox!.clear();
    if (_gsatActivationsBox != null) await _gsatActivationsBox!.clear();
    if (_posSettingsBox != null) await _posSettingsBox!.clear();
    if (_suggestionsBox != null) await _suggestionsBox!.clear();
    if (_inventoryHistoryBox != null) await _inventoryHistoryBox!.clear();
    if (_posTransactionsBox != null) await _posTransactionsBox!.clear();
    if (_posBasketsBox != null) await _posBasketsBox!.clear();
    if (_posItemRequestsBox != null) await _posItemRequestsBox!.clear();
    if (_staffPinsBox != null) await _staffPinsBox!.clear();
    if (includePendingData) {
      if (_pendingTransactionsBox != null) await _pendingTransactionsBox!.clear();
      if (_pendingOperationsBox != null) await _pendingOperationsBox!.clear();
    }
    if (_syncMetadataBox != null) await _syncMetadataBox!.clear();
    print('All cache cleared');
  }

  /// Get cache statistics
  static Future<Map<String, dynamic>> getCacheStats() async {
    if (_inventoryBox == null) await initialize();

    return {
      'inventoryItemCount': _inventoryBox?.length ?? 0,
      'customersCount': _customersBox?.length ?? 0,
      'gsatActivationsCount': _gsatActivationsBox?.length ?? 0,
      'suggestionsCount': _suggestionsBox?.length ?? 0,
      'inventoryHistoryCount': _inventoryHistoryBox?.length ?? 0,
      'posTransactionsCount': _posTransactionsBox?.length ?? 0,
      'pendingTransactionsCount': _pendingTransactionsBox?.length ?? 0,
      'pendingOperationsCount': _pendingOperationsBox?.length ?? 0,
      'posBasketsCount': _posBasketsBox?.length ?? 0,
      'posItemRequestsCount': _posItemRequestsBox?.length ?? 0,
      'staffPinsCount': _staffPinsBox?.length ?? 0,
      'hasPosSettings': _posSettingsBox?.containsKey('settings') ?? false,
      'lastInventorySync': await getLastSyncTimestamp('inventory'),
      'isInitialized': _isInitialized,
    };
  }

  /// Close all Hive boxes
  static Future<void> dispose() async {
    await _inventoryBox?.close();
    await _customersBox?.close();
    await _gsatActivationsBox?.close();
    await _posSettingsBox?.close();
    await _suggestionsBox?.close();
    await _inventoryHistoryBox?.close();
    await _posTransactionsBox?.close();
    await _pendingTransactionsBox?.close();
    await _pendingOperationsBox?.close();
    await _posBasketsBox?.close();
    await _posItemRequestsBox?.close();
    await _staffPinsBox?.close();
    await _syncMetadataBox?.close();
    _isInitialized = false;
  }
}
