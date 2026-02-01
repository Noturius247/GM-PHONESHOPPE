import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'cache_service.dart';
import 'inventory_service.dart';

/// OfflineSyncService handles syncing pending offline transactions
/// when connectivity is restored.
class OfflineSyncService {
  static StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  static bool _isSyncing = false;
  static final _syncStatusController = StreamController<SyncStatus>.broadcast();

  /// Stream of sync status updates
  static Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  /// Initialize the sync service and start listening for connectivity changes
  static Future<void> initialize() async {
    // Cancel any existing subscription
    await _connectivitySubscription?.cancel();

    // Listen to connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) async {
      final hasConnection = result != ConnectivityResult.none;
      if (hasConnection) {
        // Connectivity restored, attempt to sync pending transactions
        await syncPendingTransactions();
      }
    });

    // Check if there are pending transactions on startup
    final pendingCount = await CacheService.getPendingTransactionCount();
    if (pendingCount > 0) {
      _syncStatusController.add(SyncStatus(
        hasPending: true,
        pendingCount: pendingCount,
        message: '$pendingCount transactions pending sync',
      ));

      // Try to sync immediately if online
      final hasConnection = await CacheService.hasConnectivity();
      if (hasConnection) {
        await syncPendingTransactions();
      }
    }

    print('OfflineSyncService initialized');
  }

  /// Sync all pending offline transactions to Firebase
  static Future<SyncResult> syncPendingTransactions() async {
    if (_isSyncing) {
      return SyncResult(
        success: false,
        syncedCount: 0,
        failedCount: 0,
        message: 'Sync already in progress',
      );
    }

    _isSyncing = true;
    int syncedCount = 0;
    int failedCount = 0;
    final errors = <String>[];

    try {
      // Check connectivity first
      final hasConnection = await CacheService.hasConnectivity();
      if (!hasConnection) {
        _isSyncing = false;
        return SyncResult(
          success: false,
          syncedCount: 0,
          failedCount: 0,
          message: 'No internet connection',
        );
      }

      // Get all pending transactions
      final pendingTransactions = await CacheService.getPendingTransactions();
      if (pendingTransactions.isEmpty) {
        _isSyncing = false;
        _syncStatusController.add(SyncStatus(
          hasPending: false,
          pendingCount: 0,
          message: 'No pending transactions',
        ));
        return SyncResult(
          success: true,
          syncedCount: 0,
          failedCount: 0,
          message: 'No pending transactions to sync',
        );
      }

      _syncStatusController.add(SyncStatus(
        hasPending: true,
        pendingCount: pendingTransactions.length,
        isSyncing: true,
        message: 'Syncing ${pendingTransactions.length} transactions...',
      ));

      for (var transaction in pendingTransactions) {
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
              final itemMap = item as Map<String, dynamic>;
              final qty = itemMap['quantity'] as int? ?? 1;
              final itemId = itemMap['itemId'];
              final category = itemMap['category'];

              if (itemId != null && category != null) {
                await InventoryService.removeStock(
                  category: category,
                  itemId: itemId,
                  quantityToRemove: qty,
                  reason: 'POS Sale (Offline Sync) - Transaction #$transactionId',
                  removedByEmail: transaction['processedByEmail'] ?? '',
                  removedByName: transaction['processedBy'] ?? '',
                );
              }
            }
          }

          // Remove from pending queue
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

      final remainingCount = await CacheService.getPendingTransactionCount();
      _syncStatusController.add(SyncStatus(
        hasPending: remainingCount > 0,
        pendingCount: remainingCount,
        isSyncing: false,
        message: syncedCount > 0
            ? 'Synced $syncedCount transactions'
            : 'Sync completed',
      ));

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
    } finally {
      _isSyncing = false;
    }
  }

  /// Check if currently syncing
  static bool get isSyncing => _isSyncing;

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
