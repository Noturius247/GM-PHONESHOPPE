import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'cache_service.dart';
import 'inventory_service.dart';

/// OfflineSyncService handles syncing ALL pending offline data
/// (transactions, baskets, item requests) when connectivity is restored.
class OfflineSyncService {
  static StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  static bool _isSyncing = false;
  static bool _isInitialized = false;
  static final _syncStatusController = StreamController<SyncStatus>.broadcast();

  /// Stream of sync status updates
  static Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  /// Initialize the sync service and start listening for connectivity changes
  static Future<void> initialize() async {
    if (_isInitialized) {
      print('OfflineSyncService already initialized - skipping');
      return;
    }
    _isInitialized = true;

    // Cancel any existing subscription
    await _connectivitySubscription?.cancel();

    // One-time migration: mark existing cached data for sync
    await _migrateExistingCacheForSync();

    // Listen to connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) async {
      final hasConnection = result != ConnectivityResult.none;
      if (hasConnection) {
        // Connectivity restored, attempt to sync ALL pending data
        await syncAllPendingData();
      }
    });

    // Check if there are pending items on startup
    final pendingCount = await _getTotalPendingCount();
    if (pendingCount > 0) {
      _syncStatusController.add(SyncStatus(
        hasPending: true,
        pendingCount: pendingCount,
        message: '$pendingCount items pending sync',
      ));

      // Try to sync immediately if online
      final hasConnection = await CacheService.hasConnectivity();
      if (hasConnection) {
        await syncAllPendingData();
      }
    }

    print('OfflineSyncService initialized');
  }

  /// One-time migration to mark existing cached data for sync
  /// This ensures data created before the sync flag feature will be synced
  static Future<void> _migrateExistingCacheForSync() async {
    try {
      // Check if migration already done (v2 includes all data types)
      final migrationDone = await CacheService.isInitialSyncCompleted('offline_sync_migration_v2');
      if (migrationDone) return;

      print('Running one-time cache migration for offline sync (v2 - all data types)...');

      int totalMarked = 0;

      // 1. Mark all existing baskets that don't have sync metadata
      final baskets = await CacheService.getPosBaskets();
      int basketsMarked = 0;
      for (var basket in baskets) {
        if (basket.containsKey('_needsSync')) continue;
        await CacheService.savePendingPosBasket(basket);
        basketsMarked++;
      }
      totalMarked += basketsMarked;

      // 2. Mark all existing item requests that don't have sync metadata
      final itemRequests = await CacheService.getPosItemRequests();
      int requestsMarked = 0;
      for (var request in itemRequests) {
        if (request.containsKey('_needsSync')) continue;
        await CacheService.savePendingPosItemRequest(request);
        requestsMarked++;
      }
      totalMarked += requestsMarked;

      // 3. Mark all existing inventory items with temp_ IDs for sync
      final inventoryItems = await CacheService.getInventoryItems();
      int inventoryMarked = 0;
      for (var item in inventoryItems) {
        final id = item['id'] as String? ?? '';
        // Only queue items with temp_ IDs (created offline but never synced)
        if (id.startsWith('temp_')) {
          await CacheService.savePendingOperation(
            operationType: 'inventory_add',
            data: {
              'category': item['category'] ?? 'other',
              'itemData': item,
            },
            entityId: id,
          );
          inventoryMarked++;
        }
      }
      totalMarked += inventoryMarked;

      // 4. Mark all existing customers with temp_ IDs for sync
      for (var serviceType in ['cignal', 'gsat', 'sky', 'satellite']) {
        final customers = await CacheService.getCustomers(serviceType);
        int customersMarked = 0;
        for (var customer in customers) {
          final id = customer['id'] as String? ?? '';
          if (id.startsWith('temp_')) {
            await CacheService.savePendingOperation(
              operationType: 'customer_add',
              data: {
                'serviceType': serviceType,
                'customerData': customer,
              },
              entityId: id,
            );
            customersMarked++;
          }
        }
        totalMarked += customersMarked;
      }

      // 5. Mark all existing GSAT activations with temp_ IDs for sync
      final gsatActivations = await CacheService.getGsatActivations();
      int gsatMarked = 0;
      for (var activation in gsatActivations) {
        final id = activation['id'] as String? ?? '';
        if (id.startsWith('temp_')) {
          await CacheService.savePendingOperation(
            operationType: 'gsat_add',
            data: {
              'serialNumber': activation['serialNumber'],
              'name': activation['name'],
              'address': activation['address'],
              'contactNumber': activation['contactNumber'],
              'dealer': activation['dealer'],
              'createdAt': activation['createdAt'],
            },
            entityId: id,
          );
          gsatMarked++;
        }
      }
      totalMarked += gsatMarked;

      // 6. Mark all existing suggestions with temp_ IDs for sync
      for (var serviceType in ['cignal', 'gsat', 'sky', 'satellite']) {
        final suggestions = await CacheService.getSuggestions(serviceType);
        int suggestionsMarked = 0;
        for (var suggestion in suggestions) {
          final id = suggestion['id'] as String? ?? '';
          if (id.startsWith('temp_')) {
            final submittedBy = suggestion['submittedBy'] as Map<dynamic, dynamic>?;
            await CacheService.savePendingOperation(
              operationType: 'suggestion_submit',
              data: {
                'serviceType': serviceType,
                'type': suggestion['type'],
                'customerId': suggestion['customerId'],
                'customerData': suggestion['customerData'],
                'submittedByEmail': submittedBy?['email'] ?? '',
                'submittedByName': submittedBy?['name'] ?? '',
                'reason': suggestion['reason'],
              },
              entityId: id,
            );
            suggestionsMarked++;
          }
        }
        totalMarked += suggestionsMarked;
      }

      // Mark migration as complete
      await CacheService.setInitialSyncCompleted('offline_sync_migration_v2');

      print('Migration v2 complete: $totalMarked total items marked for sync');
      print('  - Baskets: $basketsMarked');
      print('  - Item requests: $requestsMarked');
      print('  - Inventory: $inventoryMarked');
      print('  - GSAT: $gsatMarked');
    } catch (e) {
      print('Migration error (non-fatal): $e');
    }
  }

  /// Get total count of all pending items
  static Future<int> _getTotalPendingCount() async {
    final transactions = await CacheService.getPendingTransactionCount();
    final baskets = (await CacheService.getPendingPosBaskets()).length;
    final itemRequests = (await CacheService.getPendingPosItemRequests()).length;
    final failedTransactions = (await CacheService.getFailedTransactions()).length;
    final pendingOperations = await CacheService.getPendingOperationsCount();
    return transactions + baskets + itemRequests + failedTransactions + pendingOperations;
  }

  /// Sync ALL pending data when connectivity is restored
  static Future<FullSyncResult> syncAllPendingData() async {
    if (_isSyncing) {
      return FullSyncResult(
        success: false,
        message: 'Sync already in progress',
      );
    }

    _isSyncing = true;
    final results = <String, SyncResult>{};

    try {
      final hasConnection = await CacheService.hasConnectivity();
      if (!hasConnection) {
        _isSyncing = false;
        return FullSyncResult(
          success: false,
          message: 'No internet connection',
        );
      }

      _syncStatusController.add(SyncStatus(
        hasPending: true,
        pendingCount: await _getTotalPendingCount(),
        isSyncing: true,
        message: 'Syncing all pending data...',
      ));

      // 1. Reset failed transactions and operations for retry
      await CacheService.resetFailedTransactionsForRetry();
      await CacheService.resetFailedOperationsForRetry();

      // 2. Sync pending transactions
      results['transactions'] = await syncPendingTransactions();

      // 3. Sync pending baskets
      results['baskets'] = await syncPendingBaskets();

      // 4. Sync pending item requests
      results['itemRequests'] = await syncPendingItemRequests();

      // 5. Sync all pending operations (inventory, customers, suggestions, GSAT, etc.)
      results['operations'] = await syncPendingOperations();

      final totalSynced = results.values.fold<int>(0, (sum, r) => sum + r.syncedCount);
      final totalFailed = results.values.fold<int>(0, (sum, r) => sum + r.failedCount);
      final remainingCount = await _getTotalPendingCount();

      _syncStatusController.add(SyncStatus(
        hasPending: remainingCount > 0,
        pendingCount: remainingCount,
        isSyncing: false,
        message: 'Synced $totalSynced items${totalFailed > 0 ? ', $totalFailed failed' : ''}',
      ));

      return FullSyncResult(
        success: totalFailed == 0,
        message: 'Synced $totalSynced items',
        results: results,
      );
    } catch (e) {
      print('Error in syncAllPendingData: $e');
      return FullSyncResult(
        success: false,
        message: 'Sync error: $e',
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// Sync all pending offline transactions to Firebase
  static Future<SyncResult> syncPendingTransactions() async {
    int syncedCount = 0;
    int failedCount = 0;
    final errors = <String>[];

    try {
      // Get all pending transactions (status = 'pending')
      final pendingTransactions = await CacheService.getPendingTransactions();
      // Filter to only pending status (not failed or syncing)
      final toSync = pendingTransactions.where((t) =>
        t['syncStatus'] == 'pending' || t['syncStatus'] == null
      ).toList();

      if (toSync.isEmpty) {
        return SyncResult(
          success: true,
          syncedCount: 0,
          failedCount: 0,
          message: 'No pending transactions to sync',
        );
      }

      for (var transaction in toSync) {
        final transactionId = transaction['transactionId'] as String?;
        if (transactionId == null) continue;

        try {
          // Update status to syncing
          await CacheService.updatePendingTransactionStatus(transactionId, 'syncing');

          // Remove offline-specific fields before saving to Firebase
          final firebaseTransaction = Map<String, dynamic>.from(transaction);
          firebaseTransaction.remove('syncStatus');
          firebaseTransaction.remove('createdOfflineAt');
          firebaseTransaction.remove('syncError');
          firebaseTransaction.remove('lastSyncAttempt');
          firebaseTransaction.remove('retryCount');

          // Save to Firebase
          await FirebaseDatabase.instance
              .ref('pos_transactions/$transactionId')
              .set(firebaseTransaction);

          // Also save to local cache (completed transactions)
          await CacheService.savePosTransaction(firebaseTransaction);

          // Deduct inventory for each item
          final items = transaction['items'] as List<dynamic>?;
          if (items != null) {
            for (var item in items) {
              if (item is! Map) continue;
              final itemMap = Map<String, dynamic>.from(item);
              final qty = (itemMap['quantity'] as num?)?.toInt() ?? 1;
              final itemId = itemMap['itemId'] as String?;
              final category = itemMap['category'] as String?;

              if (itemId != null && category != null) {
                try {
                  await InventoryService.removeStock(
                    category: category,
                    itemId: itemId,
                    quantityToRemove: qty,
                    reason: 'POS Sale (Offline Sync) - Transaction #$transactionId',
                    removedByEmail: transaction['processedByEmail'] ?? '',
                    removedByName: transaction['processedBy'] ?? '',
                  );
                } catch (inventoryError) {
                  print('Warning: Failed to deduct inventory for item $itemId: $inventoryError');
                  // Continue - transaction is already saved, inventory will reconcile
                }
              }
            }
          }

          // Remove from pending queue only after all operations complete
          await CacheService.removePendingTransaction(transactionId);
          syncedCount++;
        } catch (e) {
          failedCount++;
          errors.add('Transaction $transactionId: $e');
          await CacheService.updatePendingTransactionStatus(
            transactionId,
            'failed',
            error: e.toString(),
          );
        }
      }

      return SyncResult(
        success: failedCount == 0,
        syncedCount: syncedCount,
        failedCount: failedCount,
        message: failedCount == 0
            ? 'Successfully synced $syncedCount transactions'
            : 'Synced $syncedCount, failed $failedCount',
        errors: errors,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        syncedCount: syncedCount,
        failedCount: failedCount,
        message: 'Sync error: $e',
        errors: [e.toString()],
      );
    }
  }

  /// Sync all pending POS baskets to Firebase
  static Future<SyncResult> syncPendingBaskets() async {
    int syncedCount = 0;
    int failedCount = 0;
    final errors = <String>[];

    try {
      final pendingBaskets = await CacheService.getPendingPosBaskets();
      if (pendingBaskets.isEmpty) {
        return SyncResult(
          success: true,
          syncedCount: 0,
          failedCount: 0,
          message: 'No pending baskets to sync',
        );
      }

      for (var basket in pendingBaskets) {
        final basketKey = basket['firebaseKey'] as String? ?? basket['id'] as String?;
        if (basketKey == null) continue;

        try {
          // Remove sync metadata before saving to Firebase
          final firebaseBasket = Map<String, dynamic>.from(basket);
          firebaseBasket.remove('_needsSync');
          firebaseBasket.remove('_createdOfflineAt');

          // Save to Firebase
          await FirebaseDatabase.instance
              .ref('pos_baskets/$basketKey')
              .set(firebaseBasket);

          // Mark as synced in local cache
          await CacheService.markPosBasketSynced(basketKey);
          syncedCount++;
        } catch (e) {
          failedCount++;
          errors.add('Basket $basketKey: $e');
        }
      }

      return SyncResult(
        success: failedCount == 0,
        syncedCount: syncedCount,
        failedCount: failedCount,
        message: failedCount == 0
            ? 'Successfully synced $syncedCount baskets'
            : 'Synced $syncedCount baskets, failed $failedCount',
        errors: errors,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        syncedCount: syncedCount,
        failedCount: failedCount,
        message: 'Basket sync error: $e',
        errors: [e.toString()],
      );
    }
  }

  /// Sync all pending POS item requests to Firebase
  static Future<SyncResult> syncPendingItemRequests() async {
    int syncedCount = 0;
    int failedCount = 0;
    final errors = <String>[];

    try {
      final pendingRequests = await CacheService.getPendingPosItemRequests();
      if (pendingRequests.isEmpty) {
        return SyncResult(
          success: true,
          syncedCount: 0,
          failedCount: 0,
          message: 'No pending item requests to sync',
        );
      }

      for (var request in pendingRequests) {
        final requestId = request['id'] as String?;
        if (requestId == null) continue;

        try {
          // Remove sync metadata before saving to Firebase
          final firebaseRequest = Map<String, dynamic>.from(request);
          firebaseRequest.remove('_needsSync');
          firebaseRequest.remove('_createdOfflineAt');

          // Save to Firebase
          await FirebaseDatabase.instance
              .ref('pos_item_requests/$requestId')
              .set(firebaseRequest);

          // Mark as synced in local cache
          await CacheService.markPosItemRequestSynced(requestId);
          syncedCount++;
        } catch (e) {
          failedCount++;
          errors.add('Item request $requestId: $e');
        }
      }

      return SyncResult(
        success: failedCount == 0,
        syncedCount: syncedCount,
        failedCount: failedCount,
        message: failedCount == 0
            ? 'Successfully synced $syncedCount item requests'
            : 'Synced $syncedCount item requests, failed $failedCount',
        errors: errors,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        syncedCount: syncedCount,
        failedCount: failedCount,
        message: 'Item request sync error: $e',
        errors: [e.toString()],
      );
    }
  }

  /// OPTIMIZED: Sync all pending operations using batched multi-path updates
  /// This reduces network requests by grouping operations together
  static Future<SyncResult> syncPendingOperations() async {
    int syncedCount = 0;
    int failedCount = 0;
    final errors = <String>[];

    try {
      final pendingOps = await CacheService.getPendingOperations();
      final toSync = pendingOps.where((op) => op['status'] == 'pending').toList();

      // Sort by createdAt to preserve operation order (add before update/delete)
      toSync.sort((a, b) {
        final aTime = (a['createdAt'] as num?)?.toInt() ?? 0;
        final bTime = (b['createdAt'] as num?)?.toInt() ?? 0;
        return aTime.compareTo(bTime);
      });

      if (toSync.isEmpty) {
        return SyncResult(
          success: true,
          syncedCount: 0,
          failedCount: 0,
          message: 'No pending operations to sync',
        );
      }

      // OPTIMIZED: Group operations by type for batching
      final inventoryUpdates = <String, dynamic>{};
      final customerUpdates = <String, dynamic>{};

      // Operations that need individual processing (adds that generate new IDs)
      final individualOps = <Map<String, dynamic>>[];

      // Mark all as syncing first
      for (var op in toSync) {
        await CacheService.updatePendingOperationStatus(op['id'] as String, 'syncing');
      }

      // Group operations for batch processing
      for (var op in toSync) {
        final opType = op['operationType'] as String;
        final data = Map<String, dynamic>.from(op['data'] as Map);
        final opId = op['id'] as String;

        try {
          switch (opType) {
            // These can be batched as updates
            case 'inventory_update':
              final category = data['category'] as String;
              final itemId = data['itemId'] as String;
              if (!itemId.startsWith('temp_')) {
                final updates = Map<String, dynamic>.from(data['updates'] as Map);
                updates['updatedAt'] = ServerValue.timestamp;
                inventoryUpdates['inventory/$category/$itemId'] = updates;
                await CacheService.removePendingOperation(opId);
                syncedCount++;
              }
              break;

            case 'inventory_delete':
              final category = data['category'] as String;
              final itemId = data['itemId'] as String;
              if (!itemId.startsWith('temp_')) {
                inventoryUpdates['inventory/$category/$itemId'] = null;
                await CacheService.removePendingOperation(opId);
                syncedCount++;
              }
              break;

            case 'customer_update':
              final serviceType = data['serviceType'] as String;
              final customerId = data['customerId'] as String;
              if (!customerId.startsWith('temp_')) {
                final updates = Map<String, dynamic>.from(data['updates'] as Map);
                updates['updatedAt'] = ServerValue.timestamp;
                customerUpdates['services/$serviceType/customers/$customerId'] = updates;
                await CacheService.removePendingOperation(opId);
                syncedCount++;
              }
              break;

            case 'customer_delete':
              final serviceType = data['serviceType'] as String;
              final customerId = data['customerId'] as String;
              if (!customerId.startsWith('temp_')) {
                customerUpdates['services/$serviceType/customers/$customerId'] = null;
                await CacheService.removePendingOperation(opId);
                syncedCount++;
              }
              break;

            // These need individual processing (generate new Firebase IDs)
            case 'inventory_add':
            case 'customer_add':
            case 'suggestion_submit':
            case 'gsat_add':
            case 'stock_add':
            case 'stock_remove':
            case 'stock_set':
              individualOps.add(op);
              break;

            default:
              print('Unknown operation type: $opType');
              failedCount++;
              await CacheService.updatePendingOperationStatus(opId, 'failed', error: 'Unknown operation type');
          }
        } catch (e) {
          failedCount++;
          errors.add('Operation $opId ($opType): $e');
          await CacheService.updatePendingOperationStatus(opId, 'failed', error: e.toString());
        }
      }

      // OPTIMIZED: Execute batched updates in single network calls
      try {
        if (inventoryUpdates.isNotEmpty) {
          await FirebaseDatabase.instance.ref().update(inventoryUpdates);
          print('Batched ${inventoryUpdates.length} inventory updates');
        }
      } catch (e) {
        print('Batch inventory update error: $e');
        // Individual items already marked as synced, this is a partial failure
        errors.add('Batch inventory update: $e');
      }

      try {
        if (customerUpdates.isNotEmpty) {
          await FirebaseDatabase.instance.ref().update(customerUpdates);
          print('Batched ${customerUpdates.length} customer updates');
        }
      } catch (e) {
        print('Batch customer update error: $e');
        errors.add('Batch customer update: $e');
      }

      // Process individual operations that can't be batched
      for (var op in individualOps) {
        final opId = op['id'] as String;
        final opType = op['operationType'] as String;
        final data = Map<String, dynamic>.from(op['data'] as Map);

        try {
          bool success = false;
          switch (opType) {
            case 'inventory_add':
              success = await _syncInventoryAdd(data);
              break;
            case 'stock_add':
              success = await _syncStockAdd(data);
              break;
            case 'stock_remove':
              success = await _syncStockRemove(data);
              break;
            case 'stock_set':
              success = await _syncStockSet(data);
              break;
            case 'customer_add':
              success = await _syncCustomerAdd(data);
              break;
            case 'suggestion_submit':
              success = await _syncSuggestionSubmit(data);
              break;
            case 'gsat_add':
              success = await _syncGsatAdd(data);
              break;
          }

          if (success) {
            await CacheService.removePendingOperation(opId);
            syncedCount++;
          } else {
            failedCount++;
            await CacheService.updatePendingOperationStatus(opId, 'failed', error: 'Sync failed');
          }
        } catch (e) {
          failedCount++;
          errors.add('Operation $opId ($opType): $e');
          await CacheService.updatePendingOperationStatus(opId, 'failed', error: e.toString());
        }
      }

      return SyncResult(
        success: failedCount == 0,
        syncedCount: syncedCount,
        failedCount: failedCount,
        message: failedCount == 0
            ? 'Successfully synced $syncedCount operations'
            : 'Synced $syncedCount operations, failed $failedCount',
        errors: errors,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        syncedCount: syncedCount,
        failedCount: failedCount,
        message: 'Operations sync error: $e',
        errors: [e.toString()],
      );
    }
  }

  // ==================== SYNC HELPERS ====================

  static Future<bool> _syncInventoryAdd(Map<String, dynamic> data) async {
    final category = data['category'] as String;
    final itemData = Map<String, dynamic>.from(data['itemData'] as Map);

    final ref = FirebaseDatabase.instance.ref('inventory/$category').push();
    final firebaseData = Map<String, dynamic>.from(itemData);
    firebaseData['createdAt'] = ServerValue.timestamp;
    firebaseData['updatedAt'] = ServerValue.timestamp;
    if (firebaseData['addedBy'] != null) {
      firebaseData['addedBy']['timestamp'] = ServerValue.timestamp;
    }

    await ref.set(firebaseData);

    // Update cache with real Firebase ID
    final newItem = Map<String, dynamic>.from(itemData);
    newItem['id'] = ref.key;
    newItem['category'] = category;
    await CacheService.saveInventoryItem(newItem);

    return true;
  }

  static Future<bool> _syncInventoryUpdate(Map<String, dynamic> data) async {
    final category = data['category'] as String;
    final itemId = data['itemId'] as String;
    final updates = Map<String, dynamic>.from(data['updates'] as Map);

    // Skip temp items that were created offline and already synced
    if (itemId.startsWith('temp_')) return true;

    final firebaseUpdates = Map<String, dynamic>.from(updates);
    firebaseUpdates['updatedAt'] = ServerValue.timestamp;
    if (firebaseUpdates['lastUpdatedBy'] != null) {
      firebaseUpdates['lastUpdatedBy']['timestamp'] = ServerValue.timestamp;
    }

    await FirebaseDatabase.instance
        .ref('inventory/$category/$itemId')
        .update(firebaseUpdates);
    return true;
  }

  static Future<bool> _syncInventoryDelete(Map<String, dynamic> data) async {
    final category = data['category'] as String;
    final itemId = data['itemId'] as String;

    // Skip temp items
    if (itemId.startsWith('temp_')) return true;

    await FirebaseDatabase.instance
        .ref('inventory/$category/$itemId')
        .remove();
    return true;
  }

  static Future<bool> _syncStockAdd(Map<String, dynamic> data) async {
    final category = data['category'] as String;
    final itemId = data['itemId'] as String;

    if (itemId.startsWith('temp_')) return true;

    // Get current quantity from Firebase and add
    final snapshot = await FirebaseDatabase.instance
        .ref('inventory/$category/$itemId/quantity')
        .get();

    final currentQty = (snapshot.value as int?) ?? 0;
    final quantityToAdd = data['quantityToAdd'] as int;
    final newQty = currentQty + quantityToAdd;

    await FirebaseDatabase.instance
        .ref('inventory/$category/$itemId')
        .update({
          'quantity': newQty,
          'updatedAt': ServerValue.timestamp,
        });

    // Log stock change
    await _logStockChangeToFirebase(
      category: category,
      itemId: itemId,
      itemName: data['itemName'] as String? ?? '',
      changeType: 'add',
      quantityChange: quantityToAdd,
      previousQty: currentQty,
      newQty: newQty,
      reason: data['reason'] as String?,
      changedByEmail: data['addedByEmail'] as String?,
      changedByName: data['addedByName'] as String?,
    );

    return true;
  }

  static Future<bool> _syncStockRemove(Map<String, dynamic> data) async {
    final category = data['category'] as String;
    final itemId = data['itemId'] as String;

    if (itemId.startsWith('temp_')) return true;

    final snapshot = await FirebaseDatabase.instance
        .ref('inventory/$category/$itemId/quantity')
        .get();

    final currentQty = (snapshot.value as int?) ?? 0;
    final quantityToRemove = data['quantityToRemove'] as int;
    final newQty = (currentQty - quantityToRemove).clamp(0, double.infinity).toInt();

    await FirebaseDatabase.instance
        .ref('inventory/$category/$itemId')
        .update({
          'quantity': newQty,
          'updatedAt': ServerValue.timestamp,
        });

    await _logStockChangeToFirebase(
      category: category,
      itemId: itemId,
      itemName: data['itemName'] as String? ?? '',
      changeType: 'remove',
      quantityChange: quantityToRemove,
      previousQty: currentQty,
      newQty: newQty,
      reason: data['reason'] as String?,
      changedByEmail: data['removedByEmail'] as String?,
      changedByName: data['removedByName'] as String?,
    );

    return true;
  }

  static Future<bool> _syncStockSet(Map<String, dynamic> data) async {
    final category = data['category'] as String;
    final itemId = data['itemId'] as String;

    if (itemId.startsWith('temp_')) return true;

    final newQuantity = data['newQuantity'] as int;
    final previousQty = data['previousQty'] as int;

    await FirebaseDatabase.instance
        .ref('inventory/$category/$itemId')
        .update({
          'quantity': newQuantity,
          'updatedAt': ServerValue.timestamp,
        });

    await _logStockChangeToFirebase(
      category: category,
      itemId: itemId,
      itemName: data['itemName'] as String? ?? '',
      changeType: 'set',
      quantityChange: newQuantity - previousQty,
      previousQty: previousQty,
      newQty: newQuantity,
      reason: data['reason'] as String?,
      changedByEmail: data['setByEmail'] as String?,
      changedByName: data['setByName'] as String?,
    );

    return true;
  }

  static Future<void> _logStockChangeToFirebase({
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
    final ref = FirebaseDatabase.instance.ref('inventory_history').push();
    await ref.set({
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
      'timestamp': ServerValue.timestamp,
    });
  }

  static Future<bool> _syncCustomerAdd(Map<String, dynamic> data) async {
    final serviceType = data['serviceType'] as String;
    final customerData = Map<String, dynamic>.from(data['customerData'] as Map);

    final ref = FirebaseDatabase.instance
        .ref('services/$serviceType/customers')
        .push();

    final firebaseData = Map<String, dynamic>.from(customerData);
    firebaseData['createdAt'] = ServerValue.timestamp;
    firebaseData['updatedAt'] = ServerValue.timestamp;
    if (firebaseData['addedBy'] != null) {
      firebaseData['addedBy']['timestamp'] = ServerValue.timestamp;
    }

    await ref.set(firebaseData);

    // Update cache with real Firebase ID
    final newCustomer = Map<String, dynamic>.from(customerData);
    newCustomer['id'] = ref.key;
    await CacheService.saveCustomer(serviceType, newCustomer);

    return true;
  }

  static Future<bool> _syncCustomerUpdate(Map<String, dynamic> data) async {
    final serviceType = data['serviceType'] as String;
    final customerId = data['customerId'] as String;
    final updates = Map<String, dynamic>.from(data['updates'] as Map);

    if (customerId.startsWith('temp_')) return true;

    final firebaseUpdates = Map<String, dynamic>.from(updates);
    firebaseUpdates['updatedAt'] = ServerValue.timestamp;
    if (firebaseUpdates['lastUpdatedBy'] != null) {
      firebaseUpdates['lastUpdatedBy']['timestamp'] = ServerValue.timestamp;
    }

    await FirebaseDatabase.instance
        .ref('services/$serviceType/customers/$customerId')
        .update(firebaseUpdates);
    return true;
  }

  static Future<bool> _syncCustomerDelete(Map<String, dynamic> data) async {
    final serviceType = data['serviceType'] as String;
    final customerId = data['customerId'] as String;

    if (customerId.startsWith('temp_')) return true;

    await FirebaseDatabase.instance
        .ref('services/$serviceType/customers/$customerId')
        .remove();
    return true;
  }

  static Future<bool> _syncSuggestionSubmit(Map<String, dynamic> data) async {
    final serviceType = data['serviceType'] as String;
    final type = data['type'] as String;
    final customerId = data['customerId'] as String?;
    final customerData = Map<String, dynamic>.from(data['customerData'] as Map);
    final submittedByEmail = data['submittedByEmail'] as String;
    final submittedByName = data['submittedByName'] as String;
    final reason = data['reason'] as String?;

    final ref = FirebaseDatabase.instance
        .ref('services/$serviceType/suggestions')
        .push();

    final suggestionData = <String, dynamic>{
      'type': type,
      'status': 'pending',
      'customerData': customerData,
      'submittedBy': {
        'email': submittedByEmail,
        'name': submittedByName,
        'timestamp': ServerValue.timestamp,
      },
      'createdAt': ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
    };

    if (customerId != null) {
      suggestionData['customerId'] = customerId;
    }
    if (reason != null && reason.isNotEmpty) {
      suggestionData['reason'] = reason;
    }

    await ref.set(suggestionData);

    // Update cache
    final newSuggestion = Map<String, dynamic>.from(suggestionData);
    newSuggestion['id'] = ref.key;
    newSuggestion['submittedBy']['timestamp'] = DateTime.now().millisecondsSinceEpoch;
    newSuggestion['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    newSuggestion['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    await CacheService.saveSuggestion(serviceType, newSuggestion);

    return true;
  }

  static Future<bool> _syncGsatAdd(Map<String, dynamic> data) async {
    final ref = FirebaseDatabase.instance.ref('gsat_activations').push();

    final firebaseData = {
      'serialNumber': data['serialNumber'],
      'name': data['name'],
      'address': data['address'],
      'contactNumber': data['contactNumber'],
      'dealer': data['dealer'],
      'createdAt': data['createdAt'],
      'timestamp': ServerValue.timestamp,
    };

    await ref.set(firebaseData);

    // Update cache with real Firebase ID
    final newActivation = Map<String, dynamic>.from(data);
    newActivation['id'] = ref.key;
    newActivation['timestamp'] = DateTime.now().millisecondsSinceEpoch;
    await CacheService.saveGsatActivation(newActivation);

    return true;
  }

  /// Check if currently syncing
  static bool get isSyncing => _isSyncing;

  /// Force upload ALL local data to Firebase.
  /// This queues every cached item for sync, not just those with temp_ IDs.
  /// Use this to ensure all local data is pushed to Firebase.
  static Future<ForceUploadResult> forceFullUpload({
    void Function(String message, int current, int total)? onProgress,
  }) async {
    if (_isSyncing) {
      return ForceUploadResult(
        success: false,
        message: 'Sync already in progress',
        queuedCount: 0,
      );
    }

    _isSyncing = true;
    int queuedCount = 0;
    int totalItems = 0;
    int processedItems = 0;

    try {
      final hasConnection = await CacheService.hasConnectivity();
      if (!hasConnection) {
        _isSyncing = false;
        return ForceUploadResult(
          success: false,
          message: 'No internet connection',
          queuedCount: 0,
        );
      }

      onProgress?.call('Counting items...', 0, 0);

      // Count total items first
      final inventoryItems = await CacheService.getInventoryItems();
      final gsatActivations = await CacheService.getGsatActivations();
      final posBaskets = await CacheService.getPosBaskets();
      final posItemRequests = await CacheService.getPosItemRequests();
      final posTransactions = await CacheService.getPosTransactions();
      final pendingTransactions = await CacheService.getPendingTransactions();

      List<List<Map<String, dynamic>>> allCustomers = [];
      List<List<Map<String, dynamic>>> allSuggestions = [];
      for (var serviceType in ['cignal', 'gsat', 'sky', 'satellite']) {
        allCustomers.add(await CacheService.getCustomers(serviceType));
        allSuggestions.add(await CacheService.getSuggestions(serviceType));
      }

      totalItems = inventoryItems.length +
          gsatActivations.length +
          posBaskets.length +
          posItemRequests.length +
          posTransactions.length +
          pendingTransactions.length +
          allCustomers.fold<int>(0, (sum, list) => sum + list.length) +
          allSuggestions.fold<int>(0, (sum, list) => sum + list.length);

      if (totalItems == 0) {
        _isSyncing = false;
        return ForceUploadResult(
          success: true,
          message: 'No local data to sync',
          queuedCount: 0,
        );
      }

      onProgress?.call('Queueing inventory items...', processedItems, totalItems);

      // 1. Queue ALL inventory items
      for (var item in inventoryItems) {
        final id = item['id'] as String? ?? '';
        final category = item['category'] as String? ?? 'other';

        // Queue for add (will create new or update existing in Firebase)
        await CacheService.savePendingOperation(
          operationType: 'inventory_add',
          data: {
            'category': category,
            'itemData': item,
          },
          entityId: id.isNotEmpty ? id : _generateTempIdForForceSync(),
        );
        queuedCount++;
        processedItems++;
        if (processedItems % 10 == 0) {
          onProgress?.call('Queueing inventory items...', processedItems, totalItems);
        }
      }

      onProgress?.call('Queueing customers...', processedItems, totalItems);

      // 2. Queue ALL customers
      final serviceTypes = ['cignal', 'gsat', 'sky', 'satellite'];
      for (var i = 0; i < serviceTypes.length; i++) {
        final serviceType = serviceTypes[i];
        final customers = allCustomers[i];

        for (var customer in customers) {
          final id = customer['id'] as String? ?? '';
          await CacheService.savePendingOperation(
            operationType: 'customer_add',
            data: {
              'serviceType': serviceType,
              'customerData': customer,
            },
            entityId: id.isNotEmpty ? id : _generateTempIdForForceSync(),
          );
          queuedCount++;
          processedItems++;
        }
      }

      onProgress?.call('Queueing suggestions...', processedItems, totalItems);

      // 3. Queue ALL suggestions (only pending ones make sense to re-sync)
      for (var i = 0; i < serviceTypes.length; i++) {
        final serviceType = serviceTypes[i];
        final suggestions = allSuggestions[i];

        for (var suggestion in suggestions) {
          if (suggestion['status'] != 'pending') continue; // Skip non-pending

          final id = suggestion['id'] as String? ?? '';
          final submittedBy = suggestion['submittedBy'] as Map<dynamic, dynamic>?;

          await CacheService.savePendingOperation(
            operationType: 'suggestion_submit',
            data: {
              'serviceType': serviceType,
              'type': suggestion['type'],
              'customerId': suggestion['customerId'],
              'customerData': suggestion['customerData'] ?? {},
              'submittedByEmail': submittedBy?['email'] ?? '',
              'submittedByName': submittedBy?['name'] ?? '',
              'reason': suggestion['reason'],
            },
            entityId: id.isNotEmpty ? id : _generateTempIdForForceSync(),
          );
          queuedCount++;
          processedItems++;
        }
      }

      onProgress?.call('Queueing GSAT activations...', processedItems, totalItems);

      // 4. Queue ALL GSAT activations
      for (var activation in gsatActivations) {
        final id = activation['id'] as String? ?? '';
        await CacheService.savePendingOperation(
          operationType: 'gsat_add',
          data: {
            'serialNumber': activation['serialNumber'],
            'name': activation['name'],
            'address': activation['address'],
            'contactNumber': activation['contactNumber'],
            'dealer': activation['dealer'],
            'createdAt': activation['createdAt'],
          },
          entityId: id.isNotEmpty ? id : _generateTempIdForForceSync(),
        );
        queuedCount++;
        processedItems++;
      }

      onProgress?.call('Queueing POS baskets...', processedItems, totalItems);

      // 5. Queue ALL POS baskets
      for (var basket in posBaskets) {
        if (basket['status'] != 'pending') continue; // Only pending baskets
        await CacheService.savePendingPosBasket(basket);
        queuedCount++;
        processedItems++;
      }

      // 6. Queue ALL POS item requests
      for (var request in posItemRequests) {
        if (request['status'] != 'pending') continue; // Only pending
        await CacheService.savePendingPosItemRequest(request);
        queuedCount++;
        processedItems++;
      }

      onProgress?.call('Queueing POS transactions...', processedItems, totalItems);

      // 7. Upload completed POS transactions directly to Firebase
      for (var transaction in posTransactions) {
        final transactionId = transaction['transactionId'] as String?;
        if (transactionId == null || transactionId.isEmpty) continue;

        try {
          // Remove any offline-specific fields
          final firebaseTransaction = Map<String, dynamic>.from(transaction);
          firebaseTransaction.remove('syncStatus');
          firebaseTransaction.remove('createdOfflineAt');
          firebaseTransaction.remove('syncError');
          firebaseTransaction.remove('lastSyncAttempt');
          firebaseTransaction.remove('retryCount');

          await FirebaseDatabase.instance
              .ref('pos_transactions/$transactionId')
              .set(firebaseTransaction);
          queuedCount++;
        } catch (e) {
          print('Warning: Failed to sync transaction $transactionId: $e');
        }
        processedItems++;
        if (processedItems % 10 == 0) {
          onProgress?.call('Queueing POS transactions...', processedItems, totalItems);
        }
      }

      // 8. Re-queue pending transactions for sync
      for (var transaction in pendingTransactions) {
        final transactionId = transaction['transactionId'] as String?;
        if (transactionId == null) continue;

        // Reset status to pending so it will be picked up by syncAllPendingData
        await CacheService.updatePendingTransactionStatus(transactionId, 'pending');
        queuedCount++;
        processedItems++;
      }

      onProgress?.call('Syncing to Firebase...', processedItems, totalItems);

      // Now trigger the actual sync
      final syncResult = await syncAllPendingData();

      final message = syncResult.success
          ? 'Synced $queuedCount items to Firebase'
          : 'Sync completed with errors: ${syncResult.message}';

      return ForceUploadResult(
        success: syncResult.success,
        message: message,
        queuedCount: queuedCount,
        syncResult: syncResult,
      );
    } catch (e) {
      print('Error in forceFullUpload: $e');
      return ForceUploadResult(
        success: false,
        message: 'Force sync error: $e',
        queuedCount: queuedCount,
      );
    } finally {
      _isSyncing = false;
    }
  }

  static String _generateTempIdForForceSync() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp % 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'force_${timestamp}_$random';
  }

  /// Dispose of resources
  static Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    await _syncStatusController.close();
  }
}

/// Represents the current sync status
class SyncStatus {
  final bool hasPending;
  final int pendingCount;
  final bool isSyncing;
  final String message;

  SyncStatus({
    required this.hasPending,
    required this.pendingCount,
    this.isSyncing = false,
    required this.message,
  });
}

/// Represents the result of a sync operation
class SyncResult {
  final bool success;
  final int syncedCount;
  final int failedCount;
  final String message;
  final List<String> errors;

  SyncResult({
    required this.success,
    required this.syncedCount,
    required this.failedCount,
    required this.message,
    this.errors = const [],
  });
}

/// Represents the result of syncing all pending data
class FullSyncResult {
  final bool success;
  final String message;
  final Map<String, SyncResult>? results;

  FullSyncResult({
    required this.success,
    required this.message,
    this.results,
  });
}

/// Represents the result of a force full upload operation
class ForceUploadResult {
  final bool success;
  final String message;
  final int queuedCount;
  final FullSyncResult? syncResult;

  ForceUploadResult({
    required this.success,
    required this.message,
    required this.queuedCount,
    this.syncResult,
  });
}
