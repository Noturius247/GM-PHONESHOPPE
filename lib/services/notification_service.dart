import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'local_notification_service.dart';
import 'onesignal_service.dart';

/// Real-time stock alert notification service.
/// Listens to `stock_alerts` in Firebase Realtime Database and notifies
/// all running app instances when new alerts are created.
class NotificationService {
  static final DatabaseReference _alertsRef =
      FirebaseDatabase.instance.ref('stock_alerts');
  static bool _initialized = false;
  static bool _isListening = false;
  static StreamSubscription? _subscription;

  /// Track recently shown alerts to prevent duplicates
  static final Set<String> _recentAlerts = {};

  /// Callback that pages can register to receive new alerts.
  static void Function(Map<String, dynamic> alert)? onNewAlert;

  /// Initialize the listener for new stock alerts.
  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    _startListening();
  }

  /// Start listening for stock alerts
  static void _startListening() {
    if (_isListening) return;
    _isListening = true;

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

        // Create unique key to prevent duplicate notifications
        final alertKey = '${alert['itemId']}_${alert['alertType']}';

        // Skip if we already showed this alert recently (within 5 seconds)
        if (_recentAlerts.contains(alertKey)) {
          debugPrint('Skipping duplicate alert: ${alert['title']}');
          return;
        }

        debugPrint('Stock alert received: ${alert['title']}');
        onNewAlert?.call(alert);

        // Show local notification for alerts from OTHER devices
        LocalNotificationService.showStockAlert(
          itemName: alert['itemName'] ?? 'Unknown Item',
          quantity: alert['quantity'] ?? 0,
          isOutOfStock: alert['alertType'] == 'out_of_stock',
          itemId: alert['itemId'],
        );

        // Mark as shown and auto-remove after 5 seconds
        _recentAlerts.add(alertKey);
        Future.delayed(const Duration(seconds: 5), () {
          _recentAlerts.remove(alertKey);
        });
      }
    });

    debugPrint('NotificationService initialized - listening for stock alerts');
  }

  /// OPTIMIZED: Pause listening when app goes to background to save data
  static void pause() {
    if (!_isListening) return;
    _subscription?.cancel();
    _subscription = null;
    _isListening = false;
    debugPrint('NotificationService paused - stopped listening for alerts');
  }

  /// OPTIMIZED: Resume listening when app comes back to foreground
  static void resume() {
    if (!_initialized || _isListening) return;
    _startListening();
    debugPrint('NotificationService resumed - listening for alerts');
  }

  /// Write a stock alert to the database so all app instances receive it.
  /// Also shows local notification immediately on the triggering device.
  /// Sends push notification to ALL devices (even when app is closed).
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
      // Show local notification immediately on THIS device
      await LocalNotificationService.showStockAlert(
        itemName: itemName,
        quantity: quantity,
        isOutOfStock: alertType == 'out_of_stock',
        itemId: itemId,
      );

      // Send push notification to ALL devices (works even when app is closed)
      await OneSignalService.sendNotificationToAll(
        title: title,
        body: body,
        data: {
          'type': 'stock_alert',
          'alertType': alertType,
          'itemId': itemId,
          'itemName': itemName,
          'quantity': quantity,
          'category': category,
        },
      );

      // Write to Firebase so OTHER devices with app OPEN also receive it
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

      debugPrint('Stock alert sent: $title');
    } catch (e) {
      debugPrint('Error sending stock alert: $e');
    }
  }

  /// Send cash in/out transaction notification to all devices.
  static Future<void> sendCashTransactionAlert({
    required String transactionType, // 'cash_in' or 'cash_out'
    required double amount,
    required String provider,
    required String referenceNo,
    required String processedBy,
  }) async {
    try {
      debugPrint('🔔 NotificationService.sendCashTransactionAlert called');
      debugPrint('  transactionType: $transactionType');
      debugPrint('  amount: $amount');
      debugPrint('  provider: $provider');
      debugPrint('  referenceNo: $referenceNo');
      debugPrint('  processedBy: $processedBy');

      final isCashOut = transactionType == 'cash_out';
      final title = isCashOut ? 'Cash-Out Transaction' : 'Cash-In Transaction';
      final body = isCashOut
          ? 'Cash-Out: ₱${amount.toStringAsFixed(2)} via $provider | Ref: $referenceNo | By: $processedBy'
          : 'Cash-In: ₱${amount.toStringAsFixed(2)} via $provider | Ref: $referenceNo | By: $processedBy';

      debugPrint('  title: $title');
      debugPrint('  body: $body');

      // Show local notification immediately on THIS device
      debugPrint('  Showing local notification...');
      await LocalNotificationService.showCashTransactionAlert(
        isCashOut: isCashOut,
        amount: amount,
        provider: provider,
        processedBy: processedBy,
      );
      debugPrint('  ✅ Local notification shown');

      // Send push notification to ALL devices (works even when app is closed)
      debugPrint('  Sending OneSignal push notification...');
      await OneSignalService.sendNotificationToAll(
        title: title,
        body: body,
        data: {
          'type': 'cash_transaction',
          'transactionType': transactionType,
          'amount': amount,
          'provider': provider,
          'referenceNo': referenceNo,
          'processedBy': processedBy,
        },
      );
      debugPrint('  ✅ OneSignal push notification sent');

      // Write to Firebase so OTHER devices with app OPEN also receive it
      debugPrint('  Writing to Firebase...');
      await _alertsRef.push().set({
        'title': title,
        'body': body,
        'transactionType': transactionType,
        'amount': amount,
        'provider': provider,
        'referenceNo': referenceNo,
        'processedBy': processedBy,
        'alertType': 'cash_transaction',
        'timestamp': ServerValue.timestamp,
      });
      debugPrint('  ✅ Written to Firebase');

      debugPrint('✅ Cash transaction alert sent successfully: $title');
    } catch (e, stackTrace) {
      debugPrint('❌ Error sending cash transaction alert: $e');
      debugPrint('Stack trace: $stackTrace');
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
