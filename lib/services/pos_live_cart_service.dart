import 'dart:async';
import 'package:firebase_database/firebase_database.dart';

/// Service for real-time shared POS cart between multiple devices.
/// Two devices logged into the same POS account share a single cart
/// via Firebase Realtime Database.
class PosLiveCartService {
  static final _database = FirebaseDatabase.instance.ref();

  /// Sanitize email for use as a Firebase key.
  static String _sanitize(String email) {
    return email.replaceAll('.', '_').replaceAll('@', '_');
  }

  static DatabaseReference cartRef(String email) {
    return _database.child('pos_live_cart/${_sanitize(email)}');
  }

  static DatabaseReference _itemsRef(String email) {
    return cartRef(email).child('items');
  }

  /// Listen to cart changes in real-time.
  /// Returns a StreamSubscription that should be cancelled on dispose.
  static StreamSubscription<DatabaseEvent> listenToCart(
    String email,
    void Function(List<Map<String, dynamic>> items, String customerName) onData,
  ) {
    return cartRef(email).onValue.listen((event) {
      if (!event.snapshot.exists) {
        onData([], '');
        return;
      }

      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
      final customerName = data['customerName'] as String? ?? '';

      final List<Map<String, dynamic>> items = [];
      if (data['items'] != null) {
        final rawItems = data['items'];
        if (rawItems is List) {
          for (final item in rawItems) {
            if (item != null && item is Map) {
              items.add(Map<String, dynamic>.from(item));
            }
          }
        } else if (rawItems is Map) {
          // Firebase may convert arrays to maps with numeric keys
          final sorted = rawItems.entries.toList()
            ..sort((a, b) => int.parse(a.key.toString()).compareTo(int.parse(b.key.toString())));
          for (final entry in sorted) {
            if (entry.value != null && entry.value is Map) {
              items.add(Map<String, dynamic>.from(entry.value));
            }
          }
        }
      }

      onData(items, customerName);
    });
  }

  /// Add an item to the shared cart. Increments quantity if already exists.
  static Future<void> addItem(String email, Map<String, dynamic> item) async {
    final snapshot = await _itemsRef(email).get();
    final List<Map<String, dynamic>> items = [];

    if (snapshot.exists) {
      final rawItems = snapshot.value;
      if (rawItems is List) {
        for (final i in rawItems) {
          if (i != null && i is Map) items.add(Map<String, dynamic>.from(i));
        }
      } else if (rawItems is Map) {
        final sorted = rawItems.entries.toList()
          ..sort((a, b) => int.parse(a.key.toString()).compareTo(int.parse(b.key.toString())));
        for (final entry in sorted) {
          if (entry.value != null && entry.value is Map) {
            items.add(Map<String, dynamic>.from(entry.value));
          }
        }
      }
    }

    // Check if item already exists by id
    final itemId = item['id'] ?? item['itemId'];
    final existingIdx = items.indexWhere((c) => (c['id'] ?? c['itemId']) == itemId);

    if (existingIdx >= 0) {
      final currentQty = items[existingIdx]['cartQuantity'] as int? ?? 1;
      final availableQty = item['quantity'] as int? ?? 999;
      if (currentQty < availableQty) {
        items[existingIdx]['cartQuantity'] = currentQty + 1;
      }
    } else {
      final newItem = Map<String, dynamic>.from(item);
      if (newItem['cartQuantity'] == null) newItem['cartQuantity'] = 1;
      items.add(newItem);
    }

    await cartRef(email).update({
      'items': items,
      'updatedAt': ServerValue.timestamp,
    });
  }

  /// Remove an item at a specific index.
  static Future<void> removeItem(String email, int index) async {
    final snapshot = await _itemsRef(email).get();
    if (!snapshot.exists) return;

    final items = _parseItems(snapshot.value);
    if (index >= 0 && index < items.length) {
      items.removeAt(index);
    }

    await cartRef(email).update({
      'items': items.isEmpty ? null : items,
      'updatedAt': ServerValue.timestamp,
    });
  }

  /// Update quantity of an item at index.
  static Future<void> updateItemQty(String email, int index, int newQty) async {
    final snapshot = await _itemsRef(email).get();
    if (!snapshot.exists) return;

    final items = _parseItems(snapshot.value);
    if (index >= 0 && index < items.length) {
      if (newQty <= 0) {
        items.removeAt(index);
      } else {
        items[index]['cartQuantity'] = newQty;
      }
    }

    await cartRef(email).update({
      'items': items.isEmpty ? null : items,
      'updatedAt': ServerValue.timestamp,
    });
  }

  /// Set the customer name on the shared cart.
  static Future<void> setCustomerName(String email, String name) async {
    await cartRef(email).update({
      'customerName': name,
      'updatedAt': ServerValue.timestamp,
    });
  }

  /// Clear the entire shared cart.
  static Future<void> clearCart(String email) async {
    await cartRef(email).remove();
  }

  /// Helper to parse items from Firebase snapshot value.
  static List<Map<String, dynamic>> _parseItems(dynamic rawItems) {
    final List<Map<String, dynamic>> items = [];
    if (rawItems is List) {
      for (final i in rawItems) {
        if (i != null && i is Map) items.add(Map<String, dynamic>.from(i));
      }
    } else if (rawItems is Map) {
      final sorted = rawItems.entries.toList()
        ..sort((a, b) => int.parse(a.key.toString()).compareTo(int.parse(b.key.toString())));
      for (final entry in sorted) {
        if (entry.value != null && entry.value is Map) {
          items.add(Map<String, dynamic>.from(entry.value));
        }
      }
    }
    return items;
  }
}
