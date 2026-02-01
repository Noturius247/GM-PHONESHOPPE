import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

/// Real-time stock alert notification service.
/// Listens to `stock_alerts` in Firebase Realtime Database and notifies
/// all running app instances when new alerts are created.
class NotificationService {
  static final DatabaseReference _alertsRef =
      FirebaseDatabase.instance.ref('stock_alerts');
  static bool _initialized = false;
  static StreamSubscription? _subscription;

  /// Callback that pages can register to receive new alerts.
  static void Function(Map<String, dynamic> alert)? onNewAlert;

  /// Initialize the listener for new stock alerts.
  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    // Listen only for new alerts added after this moment
    _subscription = _alertsRef
        .orderByChild('timestamp')
        .startAt(DateTime.now().millisecondsSinceEpoch)
        .onChildAdded
        .listen((event) {
      final data = event.snapshot.value;
      if (data != null && data is Map) {
        final alert = Map<String, dynamic>.from(data);
        alert['id'] = event.snapshot.key;
        debugPrint('Stock alert received: ${alert['title']}');
        onNewAlert?.call(alert);
      }
    });

    debugPrint('NotificationService initialized - listening for stock alerts');
  }

  /// Write a stock alert to the database so all app instances receive it.
  static Future<void> sendStockAlert({
    required String title,
    required String body,
    required String category,
    required String itemId,
    required String itemName,
    required int quantity,
    required int reorderLevel,
    required String alertType, // 'out_of_stock' or 'low_stock'
  }) async {
    try {
      await _alertsRef.push().set({
        'title': title,
        'body': body,
        'category': category,
        'itemId': itemId,
        'itemName': itemName,
        'quantity': quantity,
        'reorderLevel': reorderLevel,
        'alertType': alertType,
        'timestamp': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Error sending stock alert: $e');
    }
  }

  /// Clean up old alerts (older than 7 days) to keep DB small.
  static Future<void> cleanOldAlerts() async {
    try {
      final cutoff = DateTime.now()
          .subtract(const Duration(days: 7))
          .millisecondsSinceEpoch;
      final snapshot = await _alertsRef
          .orderByChild('timestamp')
          .endAt(cutoff)
          .get();
      if (snapshot.exists) {
        final updates = <String, dynamic>{};
        for (final child in snapshot.children) {
          updates[child.key!] = null; // delete
        }
        if (updates.isNotEmpty) {
          await _alertsRef.update(updates);
          debugPrint('Cleaned ${updates.length} old stock alerts');
        }
      }
    } catch (e) {
      debugPrint('Error cleaning old alerts: $e');
    }
  }

  /// Dispose the listener.
  static void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _initialized = false;
    onNewAlert = null;
  }
}
