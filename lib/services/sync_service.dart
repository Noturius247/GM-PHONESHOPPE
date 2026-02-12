import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'cache_service.dart';

/// SyncService handles synchronization between Firebase and local Hive cache.
/// OPTIMIZED: Uses single onValue listeners instead of 3 separate streams per data type.
/// This reduces ~68 active streams to ~20, significantly lowering data usage.
class SyncService {
  static final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // OPTIMIZED: Single stream subscription per data type (was 3 per type before)
  static final Map<String, StreamSubscription> _inventorySubs = {};
  static final Map<String, StreamSubscription> _customerSubs = {};
  static final Map<String, StreamSubscription> _suggestionSubs = {};
  static StreamSubscription? _gsatActivationSub;
  static StreamSubscription? _posSettingsSub;
  static StreamSubscription? _inventoryHistorySub;
  static StreamSubscription? _posTransactionSub;
  static StreamSubscription? _connectivitySub;

  // Service types
  static const List<String> serviceTypes = ['cignal', 'gsat', 'sky', 'satellite'];

  // Inventory categories
  static const List<String> _inventoryCategories = [
    'phones', 'tv', 'speaker', 'digital_box', 'accessories',
    'light_bulb', 'solar_panel', 'battery', 'inverter', 'controller', 'other'
  ];

  // Sync status
  static bool _isSyncing = false;
  static final _syncStatusController = StreamController<SyncStatus>.broadcast();

  // Track initialization and sync state
  static bool _initialSyncComplete = false;
  static bool _isInitialized = false;

  // OPTIMIZED: Track if listeners are active (for lifecycle management)
  static bool _listenersActive = false;

  // OPTIMIZED: Query limits for large collections
  static const int _historyQueryLimit = 500;  // Last 500 history records
  static const int _transactionQueryLimit = 200;  // Last 200 transactions

  // Local cache of last known data for change detection
  static final Map<String, Map<String, dynamic>> _lastKnownInventory = {};
  static final Map<String, Map<String, dynamic>> _lastKnownCustomers = {};
  static final Map<String, Map<String, dynamic>> _lastKnownSuggestions = {};
  static Map<String, dynamic>? _lastKnownGsatActivations;

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
    await _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        _onConnectivityRestored();
      }
    });
  }

  /// OPTIMIZED: Pause all listeners when app goes to background
  /// Call this from your app's lifecycle observer
  static void pauseListeners() {
    if (!_listenersActive) return;

    print('SyncService: Pausing listeners to save data');
    _cancelAllSubscriptions();
    _listenersActive = false;

    _syncStatusController.add(SyncStatus(
      status: SyncState.idle,
      message: 'Sync paused (app backgrounded)',
    ));
  }

  /// OPTIMIZED: Resume listeners when app comes to foreground
  /// Call this from your app's lifecycle observer
  static void resumeListeners() async {
    if (_listenersActive || !_isInitialized) return;

    final hasConnectivity = await CacheService.hasConnectivity();
    if (!hasConnectivity) {
      print('SyncService: Cannot resume - no connectivity');
      return;
    }

    print('SyncService: Resuming listeners');
    _setupRealtimeListeners();
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

    // OPTIMIZED: Sync only recent history and transactions
    final inventoryHistorySyncCompleted = await CacheService.isInitialSyncCompleted('inventory_history');
    if (!inventoryHistorySyncCompleted) {
      await syncInventoryHistory();
    }

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

  /// OPTIMIZED: Sync only recent inventory history records (limited query)
  static Future<bool> syncInventoryHistory() async {
    try {
      // OPTIMIZED: Only fetch last N records instead of all history
      final snapshot = await _database
          .child('inventory_history')
          .orderByChild('timestamp')
          .limitToLast(_historyQueryLimit)
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final records = data.entries.map((entry) {
          final record = Map<String, dynamic>.from(entry.value as Map);
          record['id'] = entry.key;
          return record;
        }).toList();

        await CacheService.saveInventoryHistory(records);
        await CacheService.setInitialSyncCompleted('inventory_history');
        print('Inventory history sync completed: ${records.length} records (limited to $_historyQueryLimit)');
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

  /// OPTIMIZED: Sync only recent POS transactions (limited query)
  static Future<bool> syncPosTransactions() async {
    try {
      // OPTIMIZED: Only fetch last N transactions instead of all
      final snapshot = await _database
          .child('pos_transactions')
          .orderByChild('timestamp')
          .limitToLast(_transactionQueryLimit)
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final transactions = data.entries.map((entry) {
          final transaction = Map<String, dynamic>.from(entry.value as Map);
          transaction['transactionId'] = entry.key;
          return transaction;
        }).toList();

        await CacheService.savePosTransactions(transactions);
        await CacheService.setInitialSyncCompleted('pos_transactions');
        print('POS transactions sync completed: ${transactions.length} transactions (limited to $_transactionQueryLimit)');
      } else {
        await CacheService.setInitialSyncCompleted('pos_transactions');
      }

      return true;
    } catch (e) {
      print('Error syncing POS transactions: $e');
      return false;
    }
  }

  // ==================== REAL-TIME LISTENERS (OPTIMIZED) ====================

  /// OPTIMIZED: Set up real-time listeners using single onValue per data type
  /// This reduces ~68 streams to ~20 streams
  static void _setupRealtimeListeners() {
    if (_listenersActive) {
      print('Listeners already active - skipping setup');
      return;
    }

    // Mark initial sync as complete after a delay (to skip initial data load)
    Future.delayed(const Duration(seconds: 2), () {
      _initialSyncComplete = true;
      print('Initial sync complete - now listening for real-time changes only');
    });

    // OPTIMIZED: Single listener per inventory category
    for (var category in _inventoryCategories) {
      _setupInventoryListener(category);
    }

    // OPTIMIZED: Single listener per service type for customers and suggestions
    for (var serviceType in serviceTypes) {
      _setupCustomerListener(serviceType);
      _setupSuggestionListener(serviceType);
    }

    // OPTIMIZED: Single listeners for other data types
    _setupGsatActivationListener();
    _setupPosSettingsListener();
    _setupInventoryHistoryListener();
    _setupPosTransactionListener();

    _listenersActive = true;

    _syncStatusController.add(SyncStatus(
      status: SyncState.completed,
      message: 'Real-time sync active',
    ));

    // Log the number of active streams for monitoring
    final streamCount = _inventoryCategories.length +
                        (serviceTypes.length * 2) + // customers + suggestions
                        4; // gsat, pos_settings, history, transactions
    print('SyncService: Started $streamCount optimized listeners (was ~68 before)');
  }

  /// OPTIMIZED: Single onValue listener for inventory category with diff detection
  static void _setupInventoryListener(String category) {
    final ref = _database.child('inventory').child(category);

    _inventorySubs[category]?.cancel();

    _inventorySubs[category] = ref.onValue.listen(
      (event) async {
        if (!_initialSyncComplete) return;

        final newData = event.snapshot.value as Map<dynamic, dynamic>?;
        final lastKnown = _lastKnownInventory[category];

        if (newData == null) {
          // All items in category were deleted
          if (lastKnown != null) {
            for (var id in lastKnown.keys) {
              await CacheService.deleteInventoryItem(id);
              print('Inventory item removed: $id ($category)');
            }
          }
          _lastKnownInventory[category] = {};
          return;
        }

        final newDataMap = Map<String, dynamic>.from(newData);

        // Detect changes by comparing with last known state
        final newIds = newDataMap.keys.toSet();
        final oldIds = lastKnown?.keys.toSet() ?? <String>{};

        // Added items
        for (var id in newIds.difference(oldIds)) {
          final item = Map<String, dynamic>.from(newDataMap[id] as Map);
          item['id'] = id;
          item['category'] = category;
          await CacheService.saveInventoryItem(item);
          print('Inventory item added: ${item['name']} ($category)');
        }

        // Removed items
        for (var id in oldIds.difference(newIds)) {
          await CacheService.deleteInventoryItem(id);
          print('Inventory item removed: $id ($category)');
        }

        // Changed items (check by comparing JSON or specific fields)
        for (var id in newIds.intersection(oldIds)) {
          final newItem = newDataMap[id];
          final oldItem = lastKnown?[id];

          // Simple change detection: compare updatedAt timestamp
          final newUpdated = (newItem as Map?)?['updatedAt'];
          final oldUpdated = (oldItem as Map?)?['updatedAt'];

          if (newUpdated != oldUpdated) {
            final item = Map<String, dynamic>.from(newItem as Map);
            item['id'] = id;
            item['category'] = category;
            await CacheService.saveInventoryItem(item);
            print('Inventory item updated: ${item['name']} ($category)');
          }
        }

        // Update last known state
        _lastKnownInventory[category] = newDataMap;
      },
      onError: (error) => print('Inventory $category listener error: $error'),
    );
  }

  /// OPTIMIZED: Single onValue listener for customers with diff detection
  static void _setupCustomerListener(String serviceType) {
    final ref = _database.child('services').child(serviceType).child('customers');

    _customerSubs[serviceType]?.cancel();

    _customerSubs[serviceType] = ref.onValue.listen(
      (event) async {
        if (!_initialSyncComplete) return;

        final newData = event.snapshot.value as Map<dynamic, dynamic>?;
        final lastKnown = _lastKnownCustomers[serviceType];

        if (newData == null) {
          if (lastKnown != null) {
            for (var id in lastKnown.keys) {
              await CacheService.deleteCustomer(serviceType, id);
              print('Customer removed: $id ($serviceType)');
            }
          }
          _lastKnownCustomers[serviceType] = {};
          return;
        }

        final newDataMap = Map<String, dynamic>.from(newData);
        final newIds = newDataMap.keys.toSet();
        final oldIds = lastKnown?.keys.toSet() ?? <String>{};

        // Added
        for (var id in newIds.difference(oldIds)) {
          final customer = Map<String, dynamic>.from(newDataMap[id] as Map);
          customer['id'] = id;
          await CacheService.saveCustomer(serviceType, customer);
          print('Customer added: ${customer['name']} ($serviceType)');
        }

        // Removed
        for (var id in oldIds.difference(newIds)) {
          await CacheService.deleteCustomer(serviceType, id);
          print('Customer removed: $id ($serviceType)');
        }

        // Changed
        for (var id in newIds.intersection(oldIds)) {
          final newItem = newDataMap[id];
          final oldItem = lastKnown?[id];
          final newUpdated = (newItem as Map?)?['updatedAt'];
          final oldUpdated = (oldItem as Map?)?['updatedAt'];

          if (newUpdated != oldUpdated) {
            final customer = Map<String, dynamic>.from(newItem as Map);
            customer['id'] = id;
            await CacheService.saveCustomer(serviceType, customer);
            print('Customer updated: ${customer['name']} ($serviceType)');
          }
        }

        _lastKnownCustomers[serviceType] = newDataMap;
      },
      onError: (error) => print('$serviceType customers listener error: $error'),
    );
  }

  /// OPTIMIZED: Single onValue listener for suggestions with diff detection
  static void _setupSuggestionListener(String serviceType) {
    final ref = _database.child('services').child(serviceType).child('suggestions');

    _suggestionSubs[serviceType]?.cancel();

    _suggestionSubs[serviceType] = ref.onValue.listen(
      (event) async {
        if (!_initialSyncComplete) return;

        final newData = event.snapshot.value as Map<dynamic, dynamic>?;
        final lastKnown = _lastKnownSuggestions[serviceType];

        if (newData == null) {
          if (lastKnown != null) {
            for (var id in lastKnown.keys) {
              await CacheService.deleteSuggestion(serviceType, id);
            }
          }
          _lastKnownSuggestions[serviceType] = {};
          return;
        }

        final newDataMap = Map<String, dynamic>.from(newData);
        final newIds = newDataMap.keys.toSet();
        final oldIds = lastKnown?.keys.toSet() ?? <String>{};

        for (var id in newIds.difference(oldIds)) {
          final suggestion = Map<String, dynamic>.from(newDataMap[id] as Map);
          suggestion['id'] = id;
          await CacheService.saveSuggestion(serviceType, suggestion);
        }

        for (var id in oldIds.difference(newIds)) {
          await CacheService.deleteSuggestion(serviceType, id);
        }

        for (var id in newIds.intersection(oldIds)) {
          final newItem = newDataMap[id];
          final oldItem = lastKnown?[id];
          final newUpdated = (newItem as Map?)?['updatedAt'];
          final oldUpdated = (oldItem as Map?)?['updatedAt'];

          if (newUpdated != oldUpdated) {
            final suggestion = Map<String, dynamic>.from(newItem as Map);
            suggestion['id'] = id;
            await CacheService.saveSuggestion(serviceType, suggestion);
          }
        }

        _lastKnownSuggestions[serviceType] = newDataMap;
      },
      onError: (error) => print('$serviceType suggestions listener error: $error'),
    );
  }

  /// OPTIMIZED: Single onValue listener for GSAT activations
  static void _setupGsatActivationListener() {
    final ref = _database.child('gsat_activations');

    _gsatActivationSub?.cancel();

    _gsatActivationSub = ref.onValue.listen(
      (event) async {
        if (!_initialSyncComplete) return;

        final newData = event.snapshot.value as Map<dynamic, dynamic>?;

        if (newData == null) {
          if (_lastKnownGsatActivations != null) {
            for (var id in _lastKnownGsatActivations!.keys) {
              await CacheService.deleteGsatActivation(id);
            }
          }
          _lastKnownGsatActivations = {};
          return;
        }

        final newDataMap = Map<String, dynamic>.from(newData);
        final newIds = newDataMap.keys.toSet();
        final oldIds = _lastKnownGsatActivations?.keys.toSet() ?? <String>{};

        for (var id in newIds.difference(oldIds)) {
          final activation = Map<String, dynamic>.from(newDataMap[id] as Map);
          activation['id'] = id;
          await CacheService.saveGsatActivation(activation);
        }

        for (var id in oldIds.difference(newIds)) {
          await CacheService.deleteGsatActivation(id);
        }

        for (var id in newIds.intersection(oldIds)) {
          final newItem = newDataMap[id];
          final oldItem = _lastKnownGsatActivations?[id];
          final newUpdated = (newItem as Map?)?['timestamp'];
          final oldUpdated = (oldItem as Map?)?['timestamp'];

          if (newUpdated != oldUpdated) {
            final activation = Map<String, dynamic>.from(newItem as Map);
            activation['id'] = id;
            await CacheService.saveGsatActivation(activation);
          }
        }

        _lastKnownGsatActivations = newDataMap;
      },
      onError: (error) => print('GSAT activation listener error: $error'),
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

  /// OPTIMIZED: Single onValue listener for inventory history (with query limit)
  static void _setupInventoryHistoryListener() {
    // OPTIMIZED: Only listen to recent records
    final ref = _database
        .child('inventory_history')
        .orderByChild('timestamp')
        .limitToLast(_historyQueryLimit);

    _inventoryHistorySub?.cancel();

    _inventoryHistorySub = ref.onValue.listen(
      (event) async {
        if (!_initialSyncComplete) return;

        if (event.snapshot.exists) {
          final data = event.snapshot.value as Map<dynamic, dynamic>;
          final records = data.entries.map((entry) {
            final record = Map<String, dynamic>.from(entry.value as Map);
            record['id'] = entry.key;
            return record;
          }).toList();

          // Replace all cached history with latest (limited) records
          await CacheService.saveInventoryHistory(records);
        }
      },
      onError: (error) => print('Inventory history listener error: $error'),
    );
  }

  /// OPTIMIZED: Single onValue listener for POS transactions (with query limit)
  static void _setupPosTransactionListener() {
    // OPTIMIZED: Only listen to recent transactions
    final ref = _database
        .child('pos_transactions')
        .orderByChild('timestamp')
        .limitToLast(_transactionQueryLimit);

    _posTransactionSub?.cancel();

    _posTransactionSub = ref.onValue.listen(
      (event) async {
        if (!_initialSyncComplete) return;

        if (event.snapshot.exists) {
          final data = event.snapshot.value as Map<dynamic, dynamic>;
          final transactions = data.entries.map((entry) {
            final transaction = Map<String, dynamic>.from(entry.value as Map);
            transaction['transactionId'] = entry.key;
            return transaction;
          }).toList();

          // Update cache with latest transactions
          await CacheService.savePosTransactions(transactions);
        }
      },
      onError: (error) => print('POS transaction listener error: $error'),
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

  /// Cancel all active subscriptions
  static void _cancelAllSubscriptions() {
    // Cancel inventory subscriptions
    for (var sub in _inventorySubs.values) {
      sub.cancel();
    }
    _inventorySubs.clear();

    // Cancel customer subscriptions
    for (var sub in _customerSubs.values) {
      sub.cancel();
    }
    _customerSubs.clear();

    // Cancel suggestion subscriptions
    for (var sub in _suggestionSubs.values) {
      sub.cancel();
    }
    _suggestionSubs.clear();

    // Cancel single subscriptions
    _gsatActivationSub?.cancel();
    _gsatActivationSub = null;

    _posSettingsSub?.cancel();
    _posSettingsSub = null;

    _inventoryHistorySub?.cancel();
    _inventoryHistorySub = null;

    _posTransactionSub?.cancel();
    _posTransactionSub = null;
  }

  /// Dispose all subscriptions and reset state for clean re-initialization
  static void dispose() {
    // Cancel connectivity subscription
    _connectivitySub?.cancel();
    _connectivitySub = null;

    // Cancel all data subscriptions
    _cancelAllSubscriptions();

    // Clear last known state
    _lastKnownInventory.clear();
    _lastKnownCustomers.clear();
    _lastKnownSuggestions.clear();
    _lastKnownGsatActivations = null;

    _syncStatusController.close();

    // Reset state so service can be re-initialized
    _isInitialized = false;
    _initialSyncComplete = false;
    _listenersActive = false;
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
