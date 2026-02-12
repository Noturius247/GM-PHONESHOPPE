import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// OneSignal Push Notification Service
/// Handles push notifications that work even when the app is closed.
///
/// Setup Instructions:
/// 1. Go to https://onesignal.com and create a free account
/// 2. Create a new app and get your App ID
/// 3. Replace 'YOUR_ONESIGNAL_APP_ID' below with your actual App ID
/// 4. For Android: Add your Firebase Server Key in OneSignal dashboard
///    (Settings > Platforms > Google Android > Firebase Server Key)
/// 5. Get your REST API Key from OneSignal Dashboard > Settings > Keys & IDs
class OneSignalService {
  // OneSignal App ID from https://onesignal.com
  static const String _appId = 'fb80fb3e-bf78-45bf-8594-f4fbe8813449';

  // OneSignal REST API Key (get from OneSignal Dashboard > Settings > Keys & IDs)
  // Note: For production apps, this should be stored securely on a backend server
  static const String _restApiKey = 'os_v2_app_hp3bhlp6hbb6jgmpk6bmdvxvucvvxgfmbsiqo2whpq55dcvqbfdzcn7p4ptijypbdqhtbxwgvlblgwqmahyglvaqvl66phdcyldm7hq';

  static bool _initialized = false;

  /// Callback when a notification is received while app is open
  static void Function(String title, String body, Map<String, dynamic> data)? onNotificationReceived;

  /// Callback when user taps on a notification
  static void Function(String title, String body, Map<String, dynamic> data)? onNotificationOpened;

  /// Initialize OneSignal push notifications
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Enable verbose logging for debugging (remove in production)
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);

      // Initialize OneSignal with your App ID
      OneSignal.initialize(_appId);

      // Request permission to send notifications
      await OneSignal.Notifications.requestPermission(true);

      // Handle notification received while app is in foreground
      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        final notification = event.notification;
        debugPrint('OneSignal: Notification received in foreground');
        debugPrint('  Title: ${notification.title}');
        debugPrint('  Body: ${notification.body}');

        // Call the callback if set
        onNotificationReceived?.call(
          notification.title ?? '',
          notification.body ?? '',
          notification.additionalData ?? {},
        );

        // Display the notification (you can also prevent it with event.preventDefault())
        event.preventDefault();
        event.notification.display();
      });

      // Handle notification opened (user tapped on notification)
      OneSignal.Notifications.addClickListener((event) {
        final notification = event.notification;
        debugPrint('OneSignal: Notification opened');
        debugPrint('  Title: ${notification.title}');
        debugPrint('  Body: ${notification.body}');
        debugPrint('  Data: ${notification.additionalData}');

        // Call the callback if set
        onNotificationOpened?.call(
          notification.title ?? '',
          notification.body ?? '',
          notification.additionalData ?? {},
        );
      });

      _initialized = true;
      debugPrint('OneSignal initialized successfully');

      // Get the player ID (device ID) for testing
      final playerId = await OneSignal.User.getOnesignalId();
      debugPrint('OneSignal Player ID: $playerId');

    } catch (e) {
      debugPrint('OneSignal initialization error: $e');
    }
  }

  /// Send a push notification to all users
  /// This sends to all subscribed devices using OneSignal REST API
  static Future<bool> sendNotificationToAll({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (_restApiKey.isEmpty || _restApiKey.contains('YOUR_')) {
      debugPrint('OneSignal: REST API Key not configured');
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Basic $_restApiKey',
        },
        body: jsonEncode({
          'app_id': _appId,
          'included_segments': ['All'], // Send to all subscribed users
          'headings': {'en': title},
          'contents': {'en': body},
          'data': data ?? {},
          'android_channel_id': 'stock_alerts',
          'small_icon': 'ic_launcher_foreground',
          'android_accent_color': 'FF8B0000', // Brand burgundy
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('OneSignal: Push notification sent successfully');
        debugPrint('  Title: $title');
        return true;
      } else {
        debugPrint('OneSignal: Failed to send notification');
        debugPrint('  Status: ${response.statusCode}');
        debugPrint('  Body: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('OneSignal: Error sending notification: $e');
      return false;
    }
  }

  /// Set external user ID (useful for targeting specific users)
  static Future<void> setExternalUserId(String userId) async {
    try {
      await OneSignal.login(userId);
      debugPrint('OneSignal: Set external user ID: $userId');
    } catch (e) {
      debugPrint('OneSignal: Error setting external user ID: $e');
    }
  }

  /// Remove external user ID (on logout)
  static Future<void> removeExternalUserId() async {
    try {
      await OneSignal.logout();
      debugPrint('OneSignal: Removed external user ID');
    } catch (e) {
      debugPrint('OneSignal: Error removing external user ID: $e');
    }
  }

  /// Add a tag to the user (for segmentation)
  static Future<void> addTag(String key, String value) async {
    try {
      OneSignal.User.addTagWithKey(key, value);
      debugPrint('OneSignal: Added tag $key=$value');
    } catch (e) {
      debugPrint('OneSignal: Error adding tag: $e');
    }
  }

  /// Add multiple tags
  static Future<void> addTags(Map<String, String> tags) async {
    try {
      OneSignal.User.addTags(tags);
      debugPrint('OneSignal: Added tags $tags');
    } catch (e) {
      debugPrint('OneSignal: Error adding tags: $e');
    }
  }

  /// Check if notifications are enabled
  static Future<bool> areNotificationsEnabled() async {
    return OneSignal.Notifications.permission;
  }

  /// Get OneSignal Player ID (device ID)
  static Future<String?> getPlayerId() async {
    return await OneSignal.User.getOnesignalId();
  }
}
