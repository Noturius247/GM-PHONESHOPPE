import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

/// Local Notification Service - Works completely offline
/// Use this for immediate alerts, scheduled reminders, and local notifications
/// that don't require internet connectivity.
class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static Completer<void>? _initCompleter;

  /// Callback when user taps on a notification
  static void Function(String? payload)? onNotificationTapped;

  /// Initialize local notifications
  static Future<void> initialize() async {
    // Already initialized
    if (_initialized) return;

    // Initialization in progress - wait for it
    if (_initCompleter != null) {
      await _initCompleter!.future;
      return;
    }

    // Start initialization
    _initCompleter = Completer<void>();

    // Initialize timezone data for scheduled notifications
    tz_data.initializeTimeZones();

    // Android settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Local notification tapped: ${response.payload}');
        onNotificationTapped?.call(response.payload);
      },
    );

    // Request permissions on Android 13+
    await _requestPermissions();

    _initialized = true;
    _initCompleter?.complete();
    debugPrint('LocalNotificationService initialized');
  }

  /// Request notification permissions
  static Future<bool> _requestPermissions() async {
    bool granted = false;

    // Android 13+ requires runtime permission
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      granted = await androidPlugin.requestNotificationsPermission() ?? false;
      debugPrint('Android notification permission granted: $granted');
    }

    // iOS permissions
    final iosPlugin = _notifications
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (iosPlugin != null) {
      granted = await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      ) ?? false;
    }

    return granted;
  }

  /// Check if notification permissions are granted
  static Future<bool> arePermissionsGranted() async {
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      return await androidPlugin.areNotificationsEnabled() ?? false;
    }
    return true; // Assume granted on iOS after initialization
  }

  /// Request permissions manually (call this from settings if user denied initially)
  static Future<bool> requestPermissions() async {
    return await _requestPermissions();
  }

  /// Show an immediate notification
  static Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
    String channelId = 'default',
    String channelName = 'Default',
    String channelDescription = 'Default notifications',
    Importance importance = Importance.high,
    Priority priority = Priority.high,
  }) async {
    try {
      // Auto-initialize if not already done
      if (!_initialized) {
        await initialize();
      }

      // Create notification channel on Android (required for Android 8+)
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          AndroidNotificationChannel(
            channelId,
            channelName,
            description: channelDescription,
            importance: importance,
            playSound: true,
            enableVibration: true,
          ),
        );
      }

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: importance,
        priority: priority,
        icon: '@drawable/ic_launcher_foreground',
        playSound: true,
        enableVibration: true,
        color: const Color(0xFF8B0000), // Brand burgundy color
        colorized: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(id, title, body, details, payload: payload);
      debugPrint('Local notification shown: $title');
    } catch (e) {
      debugPrint('Error showing notification: $e');
    }
  }

  /// Show a stock alert notification (offline)
  static Future<void> showStockAlert({
    required String itemName,
    required int quantity,
    required bool isOutOfStock,
    String? itemId,
  }) async {
    final title = isOutOfStock ? 'Out of Stock!' : 'Low Stock Alert';
    final body = isOutOfStock
        ? '$itemName is out of stock'
        : '$itemName is low ($quantity remaining)';

    await show(
      id: itemName.hashCode,
      title: title,
      body: body,
      payload: itemId,
      channelId: 'stock_alerts',
      channelName: 'Stock Alerts',
      channelDescription: 'Notifications for low stock and out of stock items',
      importance: Importance.high,
      priority: Priority.high,
    );
  }

  /// Show a cash transaction alert notification (offline)
  static Future<void> showCashTransactionAlert({
    required bool isCashOut,
    required double amount,
    required String provider,
    required String processedBy,
  }) async {
    final title = isCashOut ? '💸 Cash-Out Transaction' : '💵 Cash-In Transaction';
    final body = isCashOut
        ? 'Cash-Out: ₱${amount.toStringAsFixed(2)} via $provider by $processedBy'
        : 'Cash-In: ₱${amount.toStringAsFixed(2)} via $provider by $processedBy';

    await show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      channelId: 'cash_transactions',
      channelName: 'Cash Transactions',
      channelDescription: 'Notifications for cash-in and cash-out transactions',
      importance: Importance.high,
      priority: Priority.high,
    );
  }

  /// Show a transaction notification
  static Future<void> showTransactionAlert({
    required String message,
    required double amount,
    String? transactionId,
  }) async {
    await show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Transaction Complete',
      body: '$message - ₱${amount.toStringAsFixed(2)}',
      payload: transactionId,
      channelId: 'transactions',
      channelName: 'Transactions',
      channelDescription: 'Notifications for completed transactions',
    );
  }

  /// Show a sync notification
  static Future<void> showSyncNotification({
    required String message,
    bool isError = false,
  }) async {
    await show(
      id: 9999,
      title: isError ? 'Sync Error' : 'Sync Complete',
      body: message,
      channelId: 'sync',
      channelName: 'Data Sync',
      channelDescription: 'Notifications for data synchronization',
      importance: isError ? Importance.high : Importance.low,
      priority: isError ? Priority.high : Priority.low,
    );
  }

  /// Schedule a notification for later
  static Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'scheduled',
      'Scheduled',
      channelDescription: 'Scheduled notifications',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Convert DateTime to TZDateTime
    final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      tzScheduledTime,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
    debugPrint('Notification scheduled for: $scheduledTime');
  }

  /// Cancel a specific notification
  static Future<void> cancel(int id) async {
    await _notifications.cancel(id);
  }

  /// Cancel all notifications
  static Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}
