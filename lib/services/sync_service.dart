import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'cache_service.dart';

/// SyncService handles synchronization between Firebase and local Hive cache.
/// It performs initial sync on first install and sets up real-time listeners
/// for incremental updates.
class SyncService {
  static final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // Stream subscriptions for real-time updates (incremental)
  static final Map<String, StreamSubscription> _inventoryAddedSubs = {};
  static final Map<String, StreamSubscription> _inventoryChangedSubs = {};
  static final Map<String, StreamSubscription> _inventoryRemovedSubs = {};
  static final Map<String, StreamSubscription> _customerAddedSubs = {};
  static final Map<String, StreamSubscription> _customerChangedSubs = {};
  static final Map<String, StreamSubscription> _customerRemovedSubs = {};
  static final Map<String, StreamSubscription> _suggestionAddedSubs = {};
  static final Map<String, StreamSubscription> _suggestionChangedSubs = {};
  static final Map<String, StreamSubscription> _suggestionRemovedSubs = {};
  static StreamSubscription? _gsatActivationAddedSub;
  static StreamSubscription? _gsatActivationChangedSub;
  static StreamSubscription? _gsatActivationRemovedSub;
  static StreamSubscription? _posSettingsSub;
  static StreamSubscription? _inventoryHistoryAddedSub;
  static StreamSubscription? _inventoryHistoryChangedSub;
  static StreamSubscription? _inventoryHistoryRemovedSub;
  static StreamSubscription? _posTransactionAddedSub;
  static StreamSubscription? _posTransactionChangedSub;
  static StreamSubscription? _posTransactionRemovedSub;

  // Service types
  static const List<String> serviceTypes = ['cignal', 'gsat', 'sky', 'satellite'];

  // Sync status
  static bool _isSyncing = false;
  static final _syncStatusController = StreamController<SyncStatus>.broadcast();

  // Track when listeners were set up to ignore initial onChildAdded events
  // ignore: unused_field
  static DateTime? _listenersSetupTime;
  static bool _initialSyncComplete = false;
  static bool _isInitialized = false;

  /// Stream to monitor sync status
  static Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  /// Initialize sync service - call this on app startup
  static Future<void> initialize() async {
    // Prevent duplicate initialization
    if (_isInitialized) {
      print('SyncService already initialized - skipping');
      return;
    }
    _isInitialized = true;

    await CacheService.initialize();

    // Check connectivity and perform initial sync if needed
    final hasConnectivity = await CacheService.hasConnectivity();

    if (hasConnectivity) {
      // Perform initial sync if not completed before
      await _performInitialSyncIfNeeded();

      // Set up real-time listeners for continuous sync
      _setupRealtimeListeners();
    } else {
      print('No connectivity - using cached data');
      _syncStatusController.add(SyncStatus(
        status: SyncState.offline,
        message: 'Using cached data (offline)',
      ));
    }

    // Listen for connectivity changes
    Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        _onConnectivityRestored();
      }
    });
  }

  /// Perform initial sync if this is first run or cache is empty
  static Future<void> _performInitialSyncIfNeeded() async {
    // Check if inventory needs initial sync
    final inventorySyncCompleted = await CacheService.isInitialSyncCompleted('inventory');
    if (!inventorySyncCompleted) {
      await syncInventory();
    }

    // Check if each service type needs initial sync (customers + suggestions)
    for (var serviceType in serviceTypes) {
      final customersSyncCompleted = await CacheService.isInitialSyncCompleted('customers_$serviceType');
      if (!customersSyncCompleted) {
        await syncCustomers(serviceType);
      }

      final suggestionsSyncCompleted = await CacheService.isInitialSyncCompleted('suggestions_$serviceType');
      if (!suggestionsSyncCompleted) {
        await syncSuggestions(serviceType);
      }
    }

    // Check if GSAT activations needs initial sync
    final gsatSyncCompleted = await CacheService.isInitialSyncCompleted('gsat_activations');
    if (!gsatSyncCompleted) {
      await syncGsatActivations();
    }

    // Check if POS settings needs initial sync
    final posSettingsSyncCompleted = await CacheService.isInitialSyncCompleted('pos_settings');
    if (!posSettingsSyncCompleted) {
      await syncPosSettings();
    }

    // Check if inventory history needs initial sync
    final inventoryHistorySyncCompleted = await CacheService.isInitialSyncCompleted('inventory_history');
    if (!inventoryHistorySyncCompleted) {
      await syncInventoryHistory();
    }

    // Check if POS transactions needs initial sync
    final posTransactionsSyncCompleted = await CacheService.isInitialSyncCompleted('pos_transactions');
    if (!posTransactionsSyncCompleted) {
      await syncPosTransactions();
    }
  }

  /// Called when connectivity is restored
  static Future<void> _onConnectivityRestored() async {
    print('Connectivity restored - syncing data');
    _syncStatusController.add(SyncStatus(
      status: SyncState.syncing,
      message: 'Connectivity restored - syncing...',
    ));

    await _performInitialSyncIfNeeded();
    _setupRealtimeListeners();
  }

  // ==================== INVENTORY SYNC ====================

  /// Sync all inventory from Firebase to local cache
  static Future<bool> syncInventory() async {
    if (_isSyncing) return false;
    _isSyncing = true;

    try {
      _syncStatusController.add(SyncStatus(
        status: SyncState.syncing,
        message: 'Syncing inventory...',
      ));

      final snapshot = await _database.child('inventory').get();

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

        await CacheService.saveInventoryItems(allItems);
        await CacheService.setInitialSyncCompleted('inventory');

        _syncStatusController.add(SyncStatus(
          status: SyncState.completed,
          message: 'Inventory synced (${allItems.length} items)',
        ));

        print('Inventory sync completed: ${allItems.length} items');
      } else {
        // No data in Firebase, mark as synced anyway
        await CacheService.setInitialSyncCompleted('inventory');
      }

      _isSyncing = false;
      return true;
    } catch (e) {
      print('Error syncing inventory: $e');
      _syncStatusController.add(SyncStatus(
        status: SyncState.error,
        message: 'Inventory sync failed: $e',
      ));
      _isSyncing = false;
      return false;
    }
  }

  /// Sync customers for a specific service type
  static Future<bool> syncCustomers(String serviceType) async {
    try {
      _syncStatusController.add(SyncStatus(
        status: SyncState.syncing,
        message: 'Syncing $serviceType customers...',
      ));

      final snapshot = await _database
          .child('services')
          .child(serviceType)
          .child('customers')
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final customers = data.entries.map((entry) {
          final customer = Map<String, dynamic>.from(entry.value as Map);
          customer['id'] = entry.key;
          return customer;
        }).toList();

        await CacheService.saveCustomers(serviceType, customers);
        await CacheService.setInitialSyncCompleted('customers_$serviceType');

        _syncStatusController.add(SyncStatus(
          status: SyncState.completed,
          message: '$serviceType customers synced (${customers.length})',
        ));

        print('$serviceType customers sync completed: ${customers.length}');
      } else {
        await CacheService.setInitialSyncCompleted('customers_$serviceType');
      }

      return true;
    } catch (e) {
      print('Error syncing $serviceType customers: $e');
      _syncStatusController.add(SyncStatus(
        status: SyncState.error,
        message: '$serviceType sync failed: $e',
      ));
      return false;
    }
  }

  /// Sync all customers (all service types)
  static Future<void> syncAllCustomers() async {
    for (var serviceType in serviceTypes) {
      await syncCustomers(serviceType);
    }
  }

  // ==================== SUGGESTIONS SYNC ====================

  /// Sync suggestions for a specific service type
  static Future<bool> syncSuggestions(String serviceType) async {
    try {
      final snapshot = await _database
          .child('services')
          .child(serviceType)
          .child('suggestions')
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final suggestions = data.entries.map((entry) {
          final suggestion = Map<String, dynamic>.from(entry.value as Map);
          suggestion['id'] = entry.key;
          return suggestion;
        }).toList();

        await CacheService.saveSuggestions(serviceType, suggestions);
        await CacheService.setInitialSyncCompleted('suggestions_$serviceType');
        print('$serviceType suggestions sync completed: ${suggestions.length}');
      } else {
        await CacheService.setInitialSyncCompleted('suggestions_$serviceType');
      }

      return true;
    } catch (e) {
      print('Error syncing $serviceType suggestions: $e');
      return false;
    }
  }

  // ==================== GSAT ACTIVATIONS SYNC ====================

  /// Sync all GSAT activations
  static Future<bool> syncGsatActivations() async {
    try {
      final snapshot = await _database.child('gsat_activations').get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final activations = data.entries.map((entry) {
          final activation = Map<String, dynamic>.from(entry.value as Map);
          activation['id'] = entry.key;
          return activation;
        }).toList();

        await CacheService.saveGsatActivations(activations);
        await CacheService.setInitialSyncCompleted('gsat_activations');
        print('GSAT activations sync completed: ${activations.length}');
      } else {
        await CacheService.setInitialSyncCompleted('gsat_activations');
      }

      return true;
    } catch (e) {
      print('Error syncing GSAT activations: $e');
      return false;
    }
  }

  // ==================== POS SETTINGS SYNC ====================

  /// Sync POS settings
  static Future<bool> syncPosSettings() async {
    try {
      final snapshot = await _database.child('pos_settings').get();

      if (snapshot.exists) {
        final settings = Map<String, dynamic>.from(snapshot.value as Map);
        await CacheService.savePosSettings(settings);
        await CacheService.setInitialSyncCompleted('pos_settings');
        print('POS settings sync completed');
      } else {
        await CacheService.setInitialSyncCompleted('pos_settings');
      }

      return true;
    } catch (e) {
      print('Error syncing POS settings: $e');
      return false;
    }
  }

  // ==================== INVENTORY HISTORY SYNC ====================

  /// Sync all inventory history records
  static Future<bool> syncInventoryHistory() async {
    try {
      final snapshot = await _database.child('inventory_history').get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final records = data.entries.map((entry) {
          final record = Map<String, dynamic>.from(entry.value as Map);
          record['id'] = entry.key;
          return record;
        }).toList();

        await CacheService.saveInventoryHistory(records);
        await CacheService.setInitialSyncCompleted('inventory_history');
        print('Inventory history sync completed: ${records.length} records');
      } else {
        await CacheService.setInitialSyncCompleted('inventory_history');
      }

      return true;
    } catch (e) {
      print('Error syncing inventory history: $e');
      return false;
    }
  }

  // ==================== POS TRANSACTIONS SYNC ====================

  /// Sync all POS transactions
  static Future<bool> syncPosTransactions() async {
    try {
      final snapshot = await _database.child('pos_transactions').get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final transactions = data.entries.map((entry) {
          final transaction = Map<String, dynamic>.from(entry.value as Map);
          transaction['transactionId'] = entry.key;
          return transaction;
        }).toList();

        await CacheService.savePosTransactions(transactions);
        await CacheService.setInitialSyncCompleted('pos_transactions');
        print('POS transactions sync completed: ${transactions.length} transactions');
      } else {
        await CacheService.setInitialSyncCompleted('pos_transactions');
      }

      return true;
    } catch (e) {
      print('Error syncing POS transactions: $e');
      return false;
    }
  }

  // ==================== REAL-TIME LISTENERS (INCREMENTAL) ====================

  /// Set up real-time listeners for automatic sync using incremental updates
  static void _setupRealtimeListeners() {
    // Mark the time when listeners are set up - events before this are initial load
    _listenersSetupTime = DateTime.now();

    // Small delay to let initial onChildAdded events pass before marking sync complete
    Future.delayed(const Duration(seconds: 3), () {
      _initialSyncComplete = true;
      print('Initial sync complete - now listening for real-time changes only');
    });

    // Set up inventory listeners for each category
    final categories = ['phones', 'tv', 'speaker', 'digital_box', 'accessories',
                        'light_bulb', 'solar_panel', 'battery', 'inverter', 'controller', 'other'];
    for (var category in categories) {
      _setupInventoryListenersForCategory(category);
    }

    // Set up customer and suggestion listeners for each service type
    for (var serviceType in serviceTypes) {
      _setupCustomerListenersForService(serviceType);
      _setupSuggestionListenersForService(serviceType);
    }

    // Set up GSAT activations listeners
    _setupGsatActivationListeners();

    // Set up POS settings listener
    _setupPosSettingsListener();

    // Set up inventory history listeners
    _setupInventoryHistoryListeners();

    // Set up POS transactions listeners
    _setupPosTransactionListeners();
  }

  /// Set up INCREMENTAL listeners for a specific inventory category
  /// Only syncs individual items when they change (not the whole dataset)
  static void _setupInventoryListenersForCategory(String category) {
    final ref = _database.child('inventory').child(category);

    // Cancel existing subscriptions
    _inventoryAddedSubs[category]?.cancel();
    _inventoryChangedSubs[category]?.cancel();
    _inventoryRemovedSubs[category]?.cancel();

    // Listen for NEW items added (skip initial load events)
    _inventoryAddedSubs[category] = ref.onChildAdded.listen(
      (event) async {
        // Skip initial flood of events - only process after initial sync
        if (!_initialSyncComplete) return;

        if (event.snapshot.exists) {
          final item = Map<String, dynamic>.from(event.snapshot.value as Map);
          item['id'] = event.snapshot.key;
          item['category'] = category;
          await CacheService.saveInventoryItem(item);
          print('Inventory item added: ${item['name']} ($category)');
        }
      },
      onError: (error) => print('Inventory onChildAdded error: $error'),
    );

    // Listen for CHANGED items (updates)
    _inventoryChangedSubs[category] = ref.onChildChanged.listen(
      (event) async {
        if (event.snapshot.exists) {
          final item = Map<String, dynamic>.from(event.snapshot.value as Map);
          item['id'] = event.snapshot.key;
          item['category'] = category;
          await CacheService.saveInventoryItem(item);
          print('Inventory item updated: ${item['name']} ($category)');
        }
      },
      onError: (error) => print('Inventory onChildChanged error: $error'),
    );

    // Listen for REMOVED items
    _inventoryRemovedSubs[category] = ref.onChildRemoved.listen(
      (event) async {
        final itemId = event.snapshot.key;
        if (itemId != null) {
          await CacheService.deleteInventoryItem(itemId);
          print('Inventory item removed: $itemId ($category)');
        }
      },
      onError: (error) => print('Inventory onChildRemoved error: $error'),
    );
  }

  /// Set up INCREMENTAL listeners for a specific service type's customers
  /// Only syncs individual customers when they change
  static void _setupCustomerListenersForService(String serviceType) {
    final ref = _database.child('services').child(serviceType).child('customers');

    // Cancel existing subscriptions
    _customerAddedSubs[serviceType]?.cancel();
    _customerChangedSubs[serviceType]?.cancel();
    _customerRemovedSubs[serviceType]?.cancel();

    // Listen for NEW customers added (skip initial load events)
    _customerAddedSubs[serviceType] = ref.onChildAdded.listen(
      (event) async {
        // Skip initial flood of events - only process after initial sync
        if (!_initialSyncComplete) return;

        if (event.snapshot.exists) {
          final customer = Map<String, dynamic>.from(event.snapshot.value as Map);
          customer['id'] = event.snapshot.key;
          await CacheService.saveCustomer(serviceType, customer);
          print('Customer added: ${customer['name']} ($serviceType)');
        }
      },
      onError: (error) => print('$serviceType onChildAdded error: $error'),
    );

    // Listen for CHANGED customers (updates)
    _customerChangedSubs[serviceType] = ref.onChildChanged.listen(
      (event) async {
        if (event.snapshot.exists) {
          final customer = Map<String, dynamic>.from(event.snapshot.value as Map);
          customer['id'] = event.snapshot.key;
          await CacheService.saveCustomer(serviceType, customer);
          print('Customer updated: ${customer['name']} ($serviceType)');
        }
      },
      onError: (error) => print('$serviceType onChildChanged error: $error'),
    );

    // Listen for REMOVED customers
    _customerRemovedSubs[serviceType] = ref.onChildRemoved.listen(
      (event) async {
        final customerId = event.snapshot.key;
        if (customerId != null) {
          await CacheService.deleteCustomer(serviceType, customerId);
          print('Customer removed: $customerId ($serviceType)');
        }
      },
      onError: (error) => print('$serviceType onChildRemoved error: $error'),
    );
  }

  /// Set up INCREMENTAL listeners for suggestions
  static void _setupSuggestionListenersForService(String serviceType) {
    final ref = _database.child('services').child(serviceType).child('suggestions');

    _suggestionAddedSubs[serviceType]?.cancel();
    _suggestionChangedSubs[serviceType]?.cancel();
    _suggestionRemovedSubs[serviceType]?.cancel();

    _suggestionAddedSubs[serviceType] = ref.onChildAdded.listen(
      (event) async {
        if (!_initialSyncComplete) return; // Skip initial load
        if (event.snapshot.exists) {
          final suggestion = Map<String, dynamic>.from(event.snapshot.value as Map);
          suggestion['id'] = event.snapshot.key;
          await CacheService.saveSuggestion(serviceType, suggestion);
        }
      },
      onError: (error) => print('$serviceType suggestion onChildAdded error: $error'),
    );

    _suggestionChangedSubs[serviceType] = ref.onChildChanged.listen(
      (event) async {
        if (event.snapshot.exists) {
          final suggestion = Map<String, dynamic>.from(event.snapshot.value as Map);
          suggestion['id'] = event.snapshot.key;
          await CacheService.saveSuggestion(serviceType, suggestion);
        }
      },
      onError: (error) => print('$serviceType suggestion onChildChanged error: $error'),
    );

    _suggestionRemovedSubs[serviceType] = ref.onChildRemoved.listen(
      (event) async {
        final suggestionId = event.snapshot.key;
        if (suggestionId != null) {
          await CacheService.deleteSuggestion(serviceType, suggestionId);
        }
      },
      onError: (error) => print('$serviceType suggestion onChildRemoved error: $error'),
    );
  }

  /// Set up INCREMENTAL listeners for GSAT activations
  static void _setupGsatActivationListeners() {
    final ref = _database.child('gsat_activations');

    _gsatActivationAddedSub?.cancel();
    _gsatActivationChangedSub?.cancel();
    _gsatActivationRemovedSub?.cancel();

    _gsatActivationAddedSub = ref.onChildAdded.listen(
      (event) async {
        if (!_initialSyncComplete) return; // Skip initial load
        if (event.snapshot.exists) {
          final activation = Map<String, dynamic>.from(event.snapshot.value as Map);
          activation['id'] = event.snapshot.key;
          await CacheService.saveGsatActivation(activation);
        }
      },
      onError: (error) => print('GSAT activation onChildAdded error: $error'),
    );

    _gsatActivationChangedSub = ref.onChildChanged.listen(
      (event) async {
        if (event.snapshot.exists) {
          final activation = Map<String, dynamic>.from(event.snapshot.value as Map);
          activation['id'] = event.snapshot.key;
          await CacheService.saveGsatActivation(activation);
        }
      },
      onError: (error) => print('GSAT activation onChildChanged error: $error'),
    );

    _gsatActivationRemovedSub = ref.onChildRemoved.listen(
      (event) async {
        final activationId = event.snapshot.key;
        if (activationId != null) {
          await CacheService.deleteGsatActivation(activationId);
        }
      },
      onError: (error) => print('GSAT activation onChildRemoved error: $error'),
    );
  }

  /// Set up listener for POS settings (single document, use onValue)
  static void _setupPosSettingsListener() {
    _posSettingsSub?.cancel();

    _posSettingsSub = _database.child('pos_settings').onValue.listen(
      (event) async {
        if (event.snapshot.exists) {
          final settings = Map<String, dynamic>.from(event.snapshot.value as Map);
          await CacheService.savePosSettings(settings);
        }
      },
      onError: (error) => print('POS settings listener error: $error'),
    );
  }

  /// Set up INCREMENTAL listeners for inventory history
  static void _setupInventoryHistoryListeners() {
    final ref = _database.child('inventory_history');

    _inventoryHistoryAddedSub?.cancel();
    _inventoryHistoryChangedSub?.cancel();
    _inventoryHistoryRemovedSub?.cancel();

    _inventoryHistoryAddedSub = ref.onChildAdded.listen(
      (event) async {
        if (!_initialSyncComplete) return; // Skip initial load
        if (event.snapshot.exists) {
          final record = Map<String, dynamic>.from(event.snapshot.value as Map);
          record['id'] = event.snapshot.key;
          await CacheService.saveInventoryHistoryRecord(record);
        }
      },
      onError: (error) => print('Inventory history onChildAdded error: $error'),
    );

    _inventoryHistoryChangedSub = ref.onChildChanged.listen(
      (event) async {
        if (event.snapshot.exists) {
          final record = Map<String, dynamic>.from(event.snapshot.value as Map);
          record['id'] = event.snapshot.key;
          await CacheService.saveInventoryHistoryRecord(record);
        }
      },
      onError: (error) => print('Inventory history onChildChanged error: $error'),
    );

    _inventoryHistoryRemovedSub = ref.onChildRemoved.listen(
      (event) async {
        final recordId = event.snapshot.key;
        if (recordId != null) {
          await CacheService.deleteInventoryHistoryRecord(recordId);
        }
      },
      onError: (error) => print('Inventory history onChildRemoved error: $error'),
    );
  }

  /// Set up INCREMENTAL listeners for POS transactions
  static void _setupPosTransactionListeners() {
    final ref = _database.child('pos_transactions');

    _posTransactionAddedSub?.cancel();
    _posTransactionChangedSub?.cancel();
    _posTransactionRemovedSub?.cancel();

    _posTransactionAddedSub = ref.onChildAdded.listen(
      (event) async {
        if (!_initialSyncComplete) return; // Skip initial load
        if (event.snapshot.exists) {
          final transaction = Map<String, dynamic>.from(event.snapshot.value as Map);
          transaction['transactionId'] = event.snapshot.key;
          await CacheService.savePosTransaction(transaction);
        }
      },
      onError: (error) => print('POS transaction onChildAdded error: $error'),
    );

    _posTransactionChangedSub = ref.onChildChanged.listen(
      (event) async {
        if (event.snapshot.exists) {
          final transaction = Map<String, dynamic>.from(event.snapshot.value as Map);
          transaction['transactionId'] = event.snapshot.key;
          await CacheService.savePosTransaction(transaction);
        }
      },
      onError: (error) => print('POS transaction onChildChanged error: $error'),
    );

    _posTransactionRemovedSub = ref.onChildRemoved.listen(
      (event) async {
        final transactionId = event.snapshot.key;
        if (transactionId != null) {
          await CacheService.deletePosTransaction(transactionId);
        }
      },
      onError: (error) => print('POS transaction onChildRemoved error: $error'),
    );
  }

  // ==================== MANUAL SYNC ====================

  /// Force a full sync of all data
  static Future<void> forceFullSync() async {
    final hasConnectivity = await CacheService.hasConnectivity();
    if (!hasConnectivity) {
      _syncStatusController.add(SyncStatus(
        status: SyncState.offline,
        message: 'Cannot sync - no internet connection',
      ));
      return;
    }

    _syncStatusController.add(SyncStatus(
      status: SyncState.syncing,
      message: 'Performing full sync...',
    ));

    await syncInventory();
    await syncAllCustomers();

    _syncStatusController.add(SyncStatus(
      status: SyncState.completed,
      message: 'Full sync completed',
    ));
  }

  // ==================== UTILITIES ====================

  /// Check if initial sync is complete for all data
  static Future<bool> isFullySynced() async {
    final inventorySynced = await CacheService.isInitialSyncCompleted('inventory');
    if (!inventorySynced) return false;

    for (var serviceType in serviceTypes) {
      final synced = await CacheService.isInitialSyncCompleted('customers_$serviceType');
      if (!synced) return false;
    }

    return true;
  }

  /// Get sync status for all data types
  static Future<Map<String, bool>> getSyncStatus() async {
    final status = <String, bool>{};

    status['inventory'] = await CacheService.isInitialSyncCompleted('inventory');
    for (var serviceType in serviceTypes) {
      status['customers_$serviceType'] =
          await CacheService.isInitialSyncCompleted('customers_$serviceType');
    }

    return status;
  }

  /// Dispose all subscriptions
  static void dispose() {
    // Cancel all inventory subscriptions
    for (var sub in _inventoryAddedSubs.values) {
      sub.cancel();
    }
    for (var sub in _inventoryChangedSubs.values) {
      sub.cancel();
    }
    for (var sub in _inventoryRemovedSubs.values) {
      sub.cancel();
    }
    _inventoryAddedSubs.clear();
    _inventoryChangedSubs.clear();
    _inventoryRemovedSubs.clear();

    // Cancel all customer subscriptions
    for (var sub in _customerAddedSubs.values) {
      sub.cancel();
    }
    for (var sub in _customerChangedSubs.values) {
      sub.cancel();
    }
    for (var sub in _customerRemovedSubs.values) {
      sub.cancel();
    }
    _customerAddedSubs.clear();
    _customerChangedSubs.clear();
    _customerRemovedSubs.clear();

    // Cancel all suggestion subscriptions
    for (var sub in _suggestionAddedSubs.values) {
      sub.cancel();
    }
    for (var sub in _suggestionChangedSubs.values) {
      sub.cancel();
    }
    for (var sub in _suggestionRemovedSubs.values) {
      sub.cancel();
    }
    _suggestionAddedSubs.clear();
    _suggestionChangedSubs.clear();
    _suggestionRemovedSubs.clear();

    // Cancel GSAT activation subscriptions
    _gsatActivationAddedSub?.cancel();
    _gsatActivationChangedSub?.cancel();
    _gsatActivationRemovedSub?.cancel();

    // Cancel POS settings subscription
    _posSettingsSub?.cancel();

    // Cancel inventory history subscriptions
    _inventoryHistoryAddedSub?.cancel();
    _inventoryHistoryChangedSub?.cancel();
    _inventoryHistoryRemovedSub?.cancel();

    // Cancel POS transaction subscriptions
    _posTransactionAddedSub?.cancel();
    _posTransactionChangedSub?.cancel();
    _posTransactionRemovedSub?.cancel();

    _syncStatusController.close();
  }
}

/// Sync status enum
enum SyncState { idle, syncing, completed, error, offline }

/// Sync status class
class SyncStatus {
  final SyncState status;
  final String message;
  final DateTime timestamp;

  SyncStatus({
    required this.status,
    required this.message,
  }) : timestamp = DateTime.now();
}
