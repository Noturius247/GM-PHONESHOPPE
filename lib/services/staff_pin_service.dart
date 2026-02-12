import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'cache_service.dart';

/// Service for managing staff 4-digit PINs used to identify
/// which staff member is serving during POS transactions.
///
/// PINs are stored in Firebase at `/staff_pins/{pin}` containing
/// {email, name, userId} for O(1) lookup and uniqueness.
///
/// PINs are cached locally via Hive for fast offline lookup.
class StaffPinService {
  static final DatabaseReference _pinsRef =
      FirebaseDatabase.instance.ref('staff_pins');

  /// Validate PIN format: exactly 4 digits.
  static bool isValidPinFormat(String pin) {
    return RegExp(r'^\d{4}$').hasMatch(pin);
  }

  /// Set or update a user's PIN.
  /// Returns an error message string on failure, or null on success.
  static Future<String?> setPin({
    required String userId,
    required String email,
    required String name,
    required String pin,
  }) async {
    if (!isValidPinFormat(pin)) {
      return 'PIN must be exactly 4 digits';
    }

    try {
      // Check if PIN is already taken by another user
      final existing = await _pinsRef.child(pin).get();
      if (existing.exists) {
        final data = Map<String, dynamic>.from(existing.value as Map);
        if (data['userId'] != userId) {
          return 'This PIN is already in use by another staff member';
        }
        // Same user re-setting same PIN — allow
      }

      // Remove old PIN if user had one
      final oldPin = await getUserPin(userId);
      if (oldPin != null && oldPin != pin) {
        await _pinsRef.child(oldPin).remove();
      }

      // Write new PIN
      await _pinsRef.child(pin).set({
        'email': email,
        'name': name,
        'userId': userId,
      });

      // Refresh local cache
      await syncPinsToCache();

      return null; // Success
    } catch (e) {
      debugPrint('StaffPinService.setPin error: $e');
      return 'Failed to set PIN. Please try again.';
    }
  }

  /// Remove a user's PIN.
  static Future<bool> removePin({
    required String userId,
    required String currentPin,
  }) async {
    try {
      await _pinsRef.child(currentPin).remove();
      await syncPinsToCache();
      return true;
    } catch (e) {
      debugPrint('StaffPinService.removePin error: $e');
      return false;
    }
  }

  /// Check if a PIN is already in use (optionally excluding a userId).
  static Future<bool> isPinTaken(String pin, {String? excludeUserId}) async {
    try {
      final snap = await _pinsRef.child(pin).get();
      if (!snap.exists) return false;
      if (excludeUserId != null) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        return data['userId'] != excludeUserId;
      }
      return true;
    } catch (e) {
      debugPrint('StaffPinService.isPinTaken error: $e');
      return false;
    }
  }

  /// Lookup staff by PIN from Firebase.
  /// Returns {email, name, userId} or null.
  static Future<Map<String, dynamic>?> lookupPin(String pin) async {
    try {
      final snap = await _pinsRef.child(pin).get();
      if (snap.exists) {
        return Map<String, dynamic>.from(snap.value as Map);
      }
      return null;
    } catch (e) {
      debugPrint('StaffPinService.lookupPin error: $e');
      return null;
    }
  }

  /// Fetch all PINs from Firebase and cache them locally in Hive.
  static Future<void> syncPinsToCache() async {
    try {
      final snap = await _pinsRef.get();
      final Map<String, Map<String, dynamic>> pins = {};
      if (snap.exists && snap.value != null) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        for (final entry in data.entries) {
          pins[entry.key] =
              Map<String, dynamic>.from(entry.value as Map);
        }
      }
      await CacheService.saveStaffPins(pins);
    } catch (e) {
      debugPrint('StaffPinService.syncPinsToCache error: $e');
    }
  }

  /// Lookup PIN from local Hive cache (fast, offline-capable).
  /// Falls back to Firebase if cache has no data.
  static Future<Map<String, dynamic>?> lookupPinFromCache(String pin) async {
    final cached = await CacheService.getStaffByPin(pin);
    if (cached != null) return cached;

    // Cache miss — try Firebase
    final result = await lookupPin(pin);
    if (result != null) {
      // Refresh cache in background
      syncPinsToCache();
    }
    return result;
  }

  /// Get a user's current PIN by scanning /staff_pins for their userId.
  static Future<String?> getUserPin(String userId) async {
    try {
      final snap = await _pinsRef.orderByChild('userId').equalTo(userId).get();
      if (snap.exists && snap.value != null) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        if (data.isEmpty) return null;
        // The key is the PIN itself
        return data.keys.first;
      }
      return null;
    } catch (e) {
      debugPrint('StaffPinService.getUserPin error: $e');
      return null;
    }
  }

  /// Generate a random 4-digit PIN that is not already in use.
  static Future<String> generateUniquePin() async {
    final rng = Random.secure();
    for (int attempt = 0; attempt < 100; attempt++) {
      final pin = (rng.nextInt(9000) + 1000).toString(); // 1000-9999
      final taken = await isPinTaken(pin);
      if (!taken) return pin;
    }
    // Extremely unlikely fallback
    return (rng.nextInt(9000) + 1000).toString();
  }

  /// Reset a user's PIN to a new randomly generated one.
  /// Returns the new PIN on success, or null on failure.
  static Future<String?> resetPin({
    required String userId,
    required String email,
    required String name,
  }) async {
    try {
      final newPin = await generateUniquePin();
      final error = await setPin(
        userId: userId,
        email: email,
        name: name,
        pin: newPin,
      );
      if (error != null) {
        debugPrint('StaffPinService.resetPin error: $error');
        return null;
      }
      return newPin;
    } catch (e) {
      debugPrint('StaffPinService.resetPin error: $e');
      return null;
    }
  }
}
