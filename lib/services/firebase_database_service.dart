import 'package:firebase_database/firebase_database.dart';
import 'cache_service.dart';

class FirebaseDatabaseService {
  static final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // Flag to track if we should force refresh from Firebase
  static final Map<String, bool> _forceRefresh = {};

  /// Set to force next fetch to get fresh data from Firebase for a service type
  static void forceRefresh(String serviceType) {
    _forceRefresh[serviceType] = true;
  }

  // Service types
  static const String cignal = 'cignal';
  static const String gsat = 'gsat';
  static const String sky = 'sky';
  static const String satellite = 'satellite';

  // Get reference for a specific service
  static DatabaseReference _getServiceRef(String serviceType) {
    return _database.child('services').child(serviceType).child('customers');
  }

  // Add a new customer with serial number
  static Future<String?> addCustomer({
    required String serviceType,
    String? serialNumber,
    String? ccaNumber,
    required String name,
    String? plan,
    String status = 'Active',
    String? boxNumber,
    String? boxId,
    String? accountNumber,
    String? address,
    String? dateOfActivation,
    String? dateOfPurchase,
    double? price,
    String? supplier,
    String? addedByEmail,
    String? addedByName,
  }) async {
    try {
      final ref = _getServiceRef(serviceType).push();
      final data = <String, dynamic>{
        'name': name,
        'status': status,
        'createdAt': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
      };
      if (serialNumber != null && serialNumber.isNotEmpty) data['serialNumber'] = serialNumber;
      if (ccaNumber != null && ccaNumber.isNotEmpty) data['ccaNumber'] = ccaNumber;
      if (plan != null) data['plan'] = plan;
      if (boxNumber != null) data['boxNumber'] = boxNumber;
      if (boxId != null) data['boxId'] = boxId;
      if (accountNumber != null) data['accountNumber'] = accountNumber;
      if (address != null) data['address'] = address;
      if (dateOfActivation != null) data['dateOfActivation'] = dateOfActivation;
      if (dateOfPurchase != null) data['dateOfPurchase'] = dateOfPurchase;
      if (price != null) data['price'] = price;
      if (supplier != null) data['supplier'] = supplier;

      // Track who added the record
      if (addedByEmail != null && addedByEmail.isNotEmpty) {
        data['addedBy'] = {
          'email': addedByEmail,
          'name': addedByName ?? '',
          'timestamp': ServerValue.timestamp,
        };
      }

      await ref.set(data);

      // Update cache with new customer
      final newCustomer = Map<String, dynamic>.from(data);
      newCustomer['id'] = ref.key;
      await CacheService.saveCustomer(serviceType, newCustomer);

      return ref.key;
    } catch (e) {
      print('Error adding customer: $e');
      return null;
    }
  }

  // Get all customers for a service (cache-first)
  static Future<List<Map<String, dynamic>>> getCustomers(String serviceType) async {
    try {
      // Try cache first if not forcing refresh
      final shouldForceRefresh = _forceRefresh[serviceType] ?? false;
      if (!shouldForceRefresh) {
        final hasCache = await CacheService.hasCustomersCache(serviceType);
        if (hasCache) {
          final cachedCustomers = await CacheService.getCustomers(serviceType);
          if (cachedCustomers.isNotEmpty) {
            print('Loaded ${cachedCustomers.length} $serviceType customers from cache (instant)');
            return cachedCustomers;
          }
        }
      }

      // Reset force refresh flag
      _forceRefresh[serviceType] = false;

      // Fetch from Firebase
      final snapshot = await _getServiceRef(serviceType).get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final customers = data.entries.map((entry) {
          final customer = Map<String, dynamic>.from(entry.value as Map);
          customer['id'] = entry.key;
          return customer;
        }).toList();

        // Save to cache
        await CacheService.saveCustomers(serviceType, customers);
        print('Fetched ${customers.length} $serviceType customers from Firebase and cached');

        return customers;
      }
      return [];
    } catch (e) {
      print('Error getting customers from Firebase: $e');
      // Fallback to cache on network error
      final cachedCustomers = await CacheService.getCustomers(serviceType);
      if (cachedCustomers.isNotEmpty) {
        print('Using ${cachedCustomers.length} cached $serviceType customers (offline fallback)');
        return cachedCustomers;
      }
      return [];
    }
  }

  /// Fetch fresh data from Firebase and update cache
  static Future<List<Map<String, dynamic>>> refreshCustomersFromFirebase(String serviceType) async {
    _forceRefresh[serviceType] = true;
    return await getCustomers(serviceType);
  }

  // Stream customers for real-time updates
  static Stream<DatabaseEvent> streamCustomers(String serviceType) {
    return _getServiceRef(serviceType).onValue;
  }

  // Check if serial number already exists
  static Future<bool> serialNumberExists(String serviceType, String serialNumber) async {
    try {
      final snapshot = await _getServiceRef(serviceType)
          .orderByChild('serialNumber')
          .equalTo(serialNumber)
          .get();
      return snapshot.exists;
    } catch (e) {
      print('Error checking serial number: $e');
      return false;
    }
  }

  // Get customer by serial number
  static Future<Map<String, dynamic>?> getCustomerBySerialNumber(
      String serviceType, String serialNumber) async {
    try {
      final snapshot = await _getServiceRef(serviceType)
          .orderByChild('serialNumber')
          .equalTo(serialNumber)
          .get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final entry = data.entries.first;
        final customer = Map<String, dynamic>.from(entry.value as Map);
        customer['id'] = entry.key;
        return customer;
      }
      return null;
    } catch (e) {
      print('Error getting customer by serial: $e');
      return null;
    }
  }

  // Check if CCA number already exists (must be unique)
  static Future<bool> ccaNumberExists(String serviceType, String ccaNumber) async {
    try {
      final snapshot = await _getServiceRef(serviceType)
          .orderByChild('ccaNumber')
          .equalTo(ccaNumber)
          .get();
      return snapshot.exists;
    } catch (e) {
      print('Error checking CCA number: $e');
      return false;
    }
  }

  // Check if account number already exists (must be unique)
  static Future<bool> accountNumberExists(String serviceType, String accountNumber) async {
    try {
      final snapshot = await _getServiceRef(serviceType)
          .orderByChild('accountNumber')
          .equalTo(accountNumber)
          .get();
      return snapshot.exists;
    } catch (e) {
      print('Error checking account number: $e');
      return false;
    }
  }

  // Get customer by CCA number
  static Future<Map<String, dynamic>?> getCustomerByCcaNumber(
      String serviceType, String ccaNumber) async {
    try {
      final snapshot = await _getServiceRef(serviceType)
          .orderByChild('ccaNumber')
          .equalTo(ccaNumber)
          .get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final entry = data.entries.first;
        final customer = Map<String, dynamic>.from(entry.value as Map);
        customer['id'] = entry.key;
        return customer;
      }
      return null;
    } catch (e) {
      print('Error getting customer by CCA: $e');
      return null;
    }
  }

  // Get customer by account number
  static Future<Map<String, dynamic>?> getCustomerByAccountNumber(
      String serviceType, String accountNumber) async {
    try {
      final snapshot = await _getServiceRef(serviceType)
          .orderByChild('accountNumber')
          .equalTo(accountNumber)
          .get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final entry = data.entries.first;
        final customer = Map<String, dynamic>.from(entry.value as Map);
        customer['id'] = entry.key;
        return customer;
      }
      return null;
    } catch (e) {
      print('Error getting customer by account number: $e');
      return null;
    }
  }

  // Check if Box ID already exists (must be unique for Sky)
  static Future<bool> boxIdExists(String serviceType, String boxId) async {
    try {
      final snapshot = await _getServiceRef(serviceType)
          .orderByChild('boxId')
          .equalTo(boxId)
          .get();
      return snapshot.exists;
    } catch (e) {
      print('Error checking Box ID: $e');
      return false;
    }
  }

  // Get customer by Box ID
  static Future<Map<String, dynamic>?> getCustomerByBoxId(
      String serviceType, String boxId) async {
    try {
      final snapshot = await _getServiceRef(serviceType)
          .orderByChild('boxId')
          .equalTo(boxId)
          .get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final entry = data.entries.first;
        final customer = Map<String, dynamic>.from(entry.value as Map);
        customer['id'] = entry.key;
        return customer;
      }
      return null;
    } catch (e) {
      print('Error getting customer by Box ID: $e');
      return null;
    }
  }

  // Check if Box Number already exists (must be unique)
  static Future<bool> boxNumberExists(String serviceType, String boxNumber) async {
    try {
      final snapshot = await _getServiceRef(serviceType)
          .orderByChild('boxNumber')
          .equalTo(boxNumber)
          .get();
      return snapshot.exists;
    } catch (e) {
      print('Error checking Box Number: $e');
      return false;
    }
  }

  // Get customer by Box Number
  static Future<Map<String, dynamic>?> getCustomerByBoxNumber(
      String serviceType, String boxNumber) async {
    try {
      final snapshot = await _getServiceRef(serviceType)
          .orderByChild('boxNumber')
          .equalTo(boxNumber)
          .get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final entry = data.entries.first;
        final customer = Map<String, dynamic>.from(entry.value as Map);
        customer['id'] = entry.key;
        return customer;
      }
      return null;
    } catch (e) {
      print('Error getting customer by Box Number: $e');
      return null;
    }
  }

  // Update customer
  static Future<bool> updateCustomer({
    required String serviceType,
    required String customerId,
    String? serialNumber,
    String? ccaNumber,
    String? name,
    String? plan,
    String? status,
    String? boxNumber,
    String? boxId,
    String? accountNumber,
    String? address,
    String? dateOfActivation,
    String? dateOfPurchase,
    double? price,
    String? supplier,
    String? updatedByEmail,
    String? updatedByName,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updatedAt': ServerValue.timestamp,
      };
      if (serialNumber != null) updates['serialNumber'] = serialNumber;
      if (ccaNumber != null) updates['ccaNumber'] = ccaNumber;
      if (name != null) updates['name'] = name;
      if (plan != null) updates['plan'] = plan;
      if (status != null) updates['status'] = status;
      if (boxNumber != null) updates['boxNumber'] = boxNumber;
      if (boxId != null) updates['boxId'] = boxId;
      if (accountNumber != null) updates['accountNumber'] = accountNumber;
      if (address != null) updates['address'] = address;
      if (dateOfActivation != null) updates['dateOfActivation'] = dateOfActivation;
      if (dateOfPurchase != null) updates['dateOfPurchase'] = dateOfPurchase;
      if (price != null) updates['price'] = price;
      if (supplier != null) updates['supplier'] = supplier;

      // Track who updated the record
      if (updatedByEmail != null && updatedByEmail.isNotEmpty) {
        updates['lastUpdatedBy'] = {
          'email': updatedByEmail,
          'name': updatedByName ?? '',
          'timestamp': ServerValue.timestamp,
        };
      }

      await _getServiceRef(serviceType).child(customerId).update(updates);

      // Update cache - fetch updated customer and save
      final snapshot = await _getServiceRef(serviceType).child(customerId).get();
      if (snapshot.exists) {
        final updatedCustomer = Map<String, dynamic>.from(snapshot.value as Map);
        updatedCustomer['id'] = customerId;
        await CacheService.saveCustomer(serviceType, updatedCustomer);
      }

      return true;
    } catch (e) {
      print('Error updating customer: $e');
      return false;
    }
  }

  // Delete customer
  static Future<bool> deleteCustomer(String serviceType, String customerId) async {
    try {
      await _getServiceRef(serviceType).child(customerId).remove();

      // Remove from cache
      await CacheService.deleteCustomer(serviceType, customerId);

      return true;
    } catch (e) {
      print('Error deleting customer: $e');
      return false;
    }
  }

  // Get customer count by status
  static Future<Map<String, int>> getCustomerStats(String serviceType) async {
    try {
      final customers = await getCustomers(serviceType);
      int total = customers.length;
      int active = customers.where((c) => c['status'] == 'Active').length;
      int inactive = customers.where((c) => c['status'] == 'Inactive').length;
      int pending = customers.where((c) => c['status'] == 'Pending').length;

      return {
        'total': total,
        'active': active,
        'inactive': inactive,
        'pending': pending,
      };
    } catch (e) {
      print('Error getting stats: $e');
      return {'total': 0, 'active': 0, 'inactive': 0, 'pending': 0};
    }
  }

  // ==================== SUGGESTIONS ====================

  // Get reference for suggestions
  static DatabaseReference _getSuggestionsRef(String serviceType) {
    return _database.child('services').child(serviceType).child('suggestions');
  }

  // Check if a pending suggestion already exists for the same customer and type
  static Future<bool> hasPendingSuggestion({
    required String serviceType,
    required String type,
    String? customerId,
    String? customerName, // For 'add' type where customerId doesn't exist yet
  }) async {
    try {
      final pendingSuggestions = await getPendingSuggestions(serviceType);

      for (final suggestion in pendingSuggestions) {
        if (suggestion['type'] != type) continue;

        // For edit/delete, check by customerId
        if (customerId != null && suggestion['customerId'] == customerId) {
          return true;
        }

        // For add, check by customer name in customerData
        if (type == 'add' && customerName != null) {
          final suggestionCustomerData = suggestion['customerData'] as Map<dynamic, dynamic>?;
          if (suggestionCustomerData != null &&
              suggestionCustomerData['name']?.toString().toLowerCase() == customerName.toLowerCase()) {
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      print('Error checking pending suggestion: $e');
      return false;
    }
  }

  // Submit a suggestion (for non-admin users)
  static Future<String?> submitSuggestion({
    required String serviceType,
    required String type, // 'add', 'edit', 'delete'
    String? customerId, // Required for edit/delete
    required Map<String, dynamic> customerData,
    required String submittedByEmail,
    required String submittedByName,
    String? reason,
  }) async {
    try {
      // Check for duplicate pending suggestion
      final hasDuplicate = await hasPendingSuggestion(
        serviceType: serviceType,
        type: type,
        customerId: customerId,
        customerName: customerData['name']?.toString(),
      );

      if (hasDuplicate) {
        print('Duplicate pending suggestion exists');
        return 'duplicate'; // Return special value to indicate duplicate
      }

      final ref = _getSuggestionsRef(serviceType).push();
      final data = <String, dynamic>{
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
        data['customerId'] = customerId;
      }

      if (reason != null && reason.isNotEmpty) {
        data['reason'] = reason;
      }

      await ref.set(data);
      return ref.key;
    } catch (e) {
      print('Error submitting suggestion: $e');
      return null;
    }
  }

  // Get all pending suggestions (for admin review)
  static Future<List<Map<String, dynamic>>> getPendingSuggestions(String serviceType) async {
    try {
      final snapshot = await _getSuggestionsRef(serviceType)
          .orderByChild('status')
          .equalTo('pending')
          .get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        return data.entries.map((entry) {
          final suggestion = Map<String, dynamic>.from(entry.value as Map);
          suggestion['id'] = entry.key;
          return suggestion;
        }).toList();
      }
      return [];
    } catch (e) {
      print('Error getting pending suggestions: $e');
      return [];
    }
  }

  // Get all suggestions for a service
  static Future<List<Map<String, dynamic>>> getAllSuggestions(String serviceType) async {
    try {
      final snapshot = await _getSuggestionsRef(serviceType).get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        return data.entries.map((entry) {
          final suggestion = Map<String, dynamic>.from(entry.value as Map);
          suggestion['id'] = entry.key;
          return suggestion;
        }).toList();
      }
      return [];
    } catch (e) {
      print('Error getting all suggestions: $e');
      return [];
    }
  }

  // Stream suggestions for real-time updates
  static Stream<DatabaseEvent> streamSuggestions(String serviceType) {
    return _getSuggestionsRef(serviceType).onValue;
  }

  // Stream only pending suggestions
  static Stream<DatabaseEvent> streamPendingSuggestions(String serviceType) {
    return _getSuggestionsRef(serviceType)
        .orderByChild('status')
        .equalTo('pending')
        .onValue;
  }

  // Get pending suggestions count
  static Future<int> getPendingSuggestionsCount(String serviceType) async {
    try {
      final suggestions = await getPendingSuggestions(serviceType);
      return suggestions.length;
    } catch (e) {
      print('Error getting pending count: $e');
      return 0;
    }
  }

  // Approve suggestion (admin only - applies the change)
  static Future<bool> approveSuggestion({
    required String serviceType,
    required String suggestionId,
    required Map<String, dynamic> suggestion,
    required String approvedByEmail,
    required String approvedByName,
  }) async {
    try {
      final type = suggestion['type'] as String;
      final customerData = Map<String, dynamic>.from(suggestion['customerData'] as Map);

      bool success = false;

      // Apply the suggestion based on type
      if (type == 'add') {
        final result = await addCustomer(
          serviceType: serviceType,
          serialNumber: customerData['serialNumber'],
          ccaNumber: customerData['ccaNumber'],
          name: customerData['name'] ?? '',
          plan: customerData['plan'],
          status: customerData['status'] ?? 'Active',
          boxNumber: customerData['boxNumber'],
          accountNumber: customerData['accountNumber'],
          address: customerData['address'],
          dateOfActivation: customerData['dateOfActivation'],
          dateOfPurchase: customerData['dateOfPurchase'],
          price: customerData['price'] != null ? (customerData['price'] as num).toDouble() : null,
          supplier: customerData['supplier'],
          addedByEmail: approvedByEmail,
          addedByName: approvedByName,
        );
        success = result != null;
      } else if (type == 'edit') {
        final customerId = suggestion['customerId'] as String?;
        if (customerId != null) {
          success = await updateCustomer(
            serviceType: serviceType,
            customerId: customerId,
            serialNumber: customerData['serialNumber'],
            ccaNumber: customerData['ccaNumber'],
            name: customerData['name'],
            plan: customerData['plan'],
            status: customerData['status'],
            boxNumber: customerData['boxNumber'],
            accountNumber: customerData['accountNumber'],
            address: customerData['address'],
            dateOfActivation: customerData['dateOfActivation'],
            dateOfPurchase: customerData['dateOfPurchase'],
            price: customerData['price'] != null ? (customerData['price'] as num).toDouble() : null,
            supplier: customerData['supplier'],
            updatedByEmail: approvedByEmail,
            updatedByName: approvedByName,
          );
        }
      } else if (type == 'delete') {
        final customerId = suggestion['customerId'] as String?;
        if (customerId != null) {
          success = await deleteCustomer(serviceType, customerId);
        }
      }

      if (success) {
        // Update suggestion status to approved
        await _getSuggestionsRef(serviceType).child(suggestionId).update({
          'status': 'approved',
          'updatedAt': ServerValue.timestamp,
          'reviewedBy': {
            'email': approvedByEmail,
            'name': approvedByName,
            'timestamp': ServerValue.timestamp,
            'action': 'approved',
          },
        });
      }

      return success;
    } catch (e) {
      print('Error approving suggestion: $e');
      return false;
    }
  }

  // Reject suggestion (admin only)
  static Future<bool> rejectSuggestion({
    required String serviceType,
    required String suggestionId,
    required String rejectedByEmail,
    required String rejectedByName,
    String? rejectionReason,
  }) async {
    try {
      final updates = <String, dynamic>{
        'status': 'rejected',
        'updatedAt': ServerValue.timestamp,
        'reviewedBy': {
          'email': rejectedByEmail,
          'name': rejectedByName,
          'timestamp': ServerValue.timestamp,
          'action': 'rejected',
        },
      };

      if (rejectionReason != null && rejectionReason.isNotEmpty) {
        updates['rejectionReason'] = rejectionReason;
      }

      await _getSuggestionsRef(serviceType).child(suggestionId).update(updates);
      return true;
    } catch (e) {
      print('Error rejecting suggestion: $e');
      return false;
    }
  }

  // Delete a suggestion (user can delete their own pending suggestion)
  static Future<bool> deleteSuggestion(String serviceType, String suggestionId) async {
    try {
      await _getSuggestionsRef(serviceType).child(suggestionId).remove();
      return true;
    } catch (e) {
      print('Error deleting suggestion: $e');
      return false;
    }
  }

  // Get suggestions by user email
  static Future<List<Map<String, dynamic>>> getSuggestionsByUser(
      String serviceType, String email) async {
    try {
      final allSuggestions = await getAllSuggestions(serviceType);
      return allSuggestions.where((s) {
        final submittedBy = s['submittedBy'] as Map<String, dynamic>?;
        return submittedBy?['email'] == email;
      }).toList();
    } catch (e) {
      print('Error getting user suggestions: $e');
      return [];
    }
  }

  // ==================== POS ITEM REQUESTS ====================

  static DatabaseReference _getPosItemRequestsRef() {
    return _database.child('pos_item_requests');
  }

  static Future<String> submitPosItemRequest({
    required String itemName,
    required int quantity,
    required double estimatedPrice,
    String? reason,
    required String requestedByEmail,
    required String requestedByName,
  }) async {
    try {
      final ref = _getPosItemRequestsRef().push();
      await ref.set({
        'itemName': itemName,
        'quantity': quantity,
        'estimatedPrice': estimatedPrice,
        'reason': reason ?? '',
        'status': 'pending',
        'requestedBy': {
          'email': requestedByEmail,
          'name': requestedByName,
          'timestamp': ServerValue.timestamp,
        },
        'createdAt': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
      });
      return 'success';
    } catch (e) {
      print('Error submitting POS item request: $e');
      return 'error';
    }
  }

  static Future<List<Map<String, dynamic>>> getPosItemRequests({String? status}) async {
    try {
      Query query = _getPosItemRequestsRef();
      if (status != null) {
        query = query.orderByChild('status').equalTo(status);
      }
      final snapshot = await query.get();
      if (!snapshot.exists) return [];

      final List<Map<String, dynamic>> requests = [];
      final data = snapshot.value as Map<dynamic, dynamic>;
      data.forEach((key, value) {
        if (value is Map) {
          final request = Map<String, dynamic>.from(value);
          request['id'] = key;
          requests.add(request);
        }
      });
      requests.sort((a, b) => ((b['createdAt'] ?? 0) as num).compareTo((a['createdAt'] ?? 0) as num));
      return requests;
    } catch (e) {
      print('Error loading POS item requests: $e');
      return [];
    }
  }

  static Future<bool> approvePosItemRequest({
    required String requestId,
    required String approvedByEmail,
    required String approvedByName,
    double? approvedPrice,
  }) async {
    try {
      final updates = <String, dynamic>{
        'status': 'approved',
        'updatedAt': ServerValue.timestamp,
        'reviewedBy': {
          'email': approvedByEmail,
          'name': approvedByName,
          'timestamp': ServerValue.timestamp,
          'action': 'approved',
        },
      };
      if (approvedPrice != null) {
        updates['approvedPrice'] = approvedPrice;
      }
      await _getPosItemRequestsRef().child(requestId).update(updates);
      return true;
    } catch (e) {
      print('Error approving POS item request: $e');
      return false;
    }
  }

  static Future<bool> rejectPosItemRequest({
    required String requestId,
    required String rejectedByEmail,
    required String rejectedByName,
    String? rejectionReason,
  }) async {
    try {
      final updates = <String, dynamic>{
        'status': 'rejected',
        'updatedAt': ServerValue.timestamp,
        'reviewedBy': {
          'email': rejectedByEmail,
          'name': rejectedByName,
          'timestamp': ServerValue.timestamp,
          'action': 'rejected',
        },
      };
      if (rejectionReason != null && rejectionReason.isNotEmpty) {
        updates['rejectionReason'] = rejectionReason;
      }
      await _getPosItemRequestsRef().child(requestId).update(updates);
      return true;
    } catch (e) {
      print('Error rejecting POS item request: $e');
      return false;
    }
  }

  static Future<bool> markPosItemRequestUsed(String requestId) async {
    try {
      await _getPosItemRequestsRef().child(requestId).update({
        'status': 'used',
        'updatedAt': ServerValue.timestamp,
      });
      return true;
    } catch (e) {
      print('Error marking POS item request used: $e');
      return false;
    }
  }

  // ==================== USER MANAGEMENT ====================

  // Get reference for users
  static DatabaseReference _getUsersRef() {
    return _database.child('users');
  }

  // Get reference for pending invitations
  static DatabaseReference _getInvitationsRef() {
    return _database.child('invitations');
  }

  // Add a new user invitation
  static Future<String?> addUserInvitation({
    required String email,
    String? name,
    String role = 'user',
    required String invitedByEmail,
    required String invitedByName,
  }) async {
    try {
      // Check if user already exists
      final existingUser = await getUserByEmail(email);
      if (existingUser != null) {
        return null; // User already exists
      }

      // Check if invitation already exists
      final existingInvitation = await getInvitationByEmail(email);
      if (existingInvitation != null) {
        return null; // Invitation already sent
      }

      // Generate a simple token
      final token = DateTime.now().millisecondsSinceEpoch.toString();

      final ref = _getInvitationsRef().push();
      await ref.set({
        'email': email.toLowerCase().trim(),
        'name': name ?? '',
        'role': role,
        'token': token,
        'status': 'pending', // pending, accepted, expired
        'invitedBy': {
          'email': invitedByEmail,
          'name': invitedByName,
          'timestamp': ServerValue.timestamp,
        },
        'createdAt': ServerValue.timestamp,
        'expiresAt': DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch,
      });

      return token;
    } catch (e) {
      print('Error adding user invitation: $e');
      return null;
    }
  }

  // Get invitation by email
  static Future<Map<String, dynamic>?> getInvitationByEmail(String email) async {
    try {
      final snapshot = await _getInvitationsRef()
          .orderByChild('email')
          .equalTo(email.toLowerCase().trim())
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final entry = data.entries.first;
        final invitation = Map<String, dynamic>.from(entry.value as Map);
        invitation['id'] = entry.key;
        return invitation;
      }
      return null;
    } catch (e) {
      print('Error getting invitation: $e');
      return null;
    }
  }

  // Get invitation by token (invitation code)
  static Future<Map<String, dynamic>?> getInvitationByToken(String token) async {
    try {
      final snapshot = await _getInvitationsRef()
          .orderByChild('token')
          .equalTo(token.trim())
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final entry = data.entries.first;
        final invitation = Map<String, dynamic>.from(entry.value as Map);
        invitation['id'] = entry.key;
        return invitation;
      }
      return null;
    } catch (e) {
      print('Error getting invitation by token: $e');
      return null;
    }
  }

  // Validate invitation code and return invitation if valid
  static Future<Map<String, dynamic>?> validateInvitationCode(String code) async {
    try {
      final invitation = await getInvitationByToken(code);
      if (invitation == null) {
        return null; // Code not found
      }

      // Check if already accepted or expired
      if (invitation['status'] != 'pending') {
        return null; // Already used or expired
      }

      // Check if expired by date
      final expiresAt = invitation['expiresAt'] as int?;
      if (expiresAt != null && DateTime.now().millisecondsSinceEpoch > expiresAt) {
        // Mark as expired
        await _getInvitationsRef().child(invitation['id']).update({
          'status': 'expired',
        });
        return null; // Expired
      }

      return invitation; // Valid invitation
    } catch (e) {
      print('Error validating invitation code: $e');
      return null;
    }
  }

  // Get all pending invitations
  static Future<List<Map<String, dynamic>>> getPendingInvitations() async {
    try {
      final snapshot = await _getInvitationsRef()
          .orderByChild('status')
          .equalTo('pending')
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        return data.entries.map((entry) {
          final invitation = Map<String, dynamic>.from(entry.value as Map);
          invitation['id'] = entry.key;
          return invitation;
        }).toList();
      }
      return [];
    } catch (e) {
      print('Error getting pending invitations: $e');
      return [];
    }
  }

  // Accept invitation and create user - returns the created user data to avoid race conditions
  static Future<Map<String, dynamic>?> acceptInvitation(String email) async {
    try {
      final invitation = await getInvitationByEmail(email);
      if (invitation == null || invitation['status'] != 'pending') {
        return null;
      }

      // Check if expired
      final expiresAt = invitation['expiresAt'] as int?;
      if (expiresAt != null && DateTime.now().millisecondsSinceEpoch > expiresAt) {
        // Mark as expired
        await _getInvitationsRef().child(invitation['id']).update({
          'status': 'expired',
        });
        return null;
      }

      // Prepare user data
      final userData = {
        'email': email.toLowerCase().trim(),
        'name': invitation['name'] ?? '',
        'role': invitation['role'] ?? 'user',
        'status': 'active',
        'invitedBy': invitation['invitedBy'],
        'createdAt': ServerValue.timestamp,
        'lastLogin': ServerValue.timestamp,
      };

      // Create the user
      final userRef = _getUsersRef().push();
      await userRef.set(userData);

      // Mark invitation as accepted
      await _getInvitationsRef().child(invitation['id']).update({
        'status': 'accepted',
        'acceptedAt': ServerValue.timestamp,
      });

      // Return the user data directly (avoid race condition with getUserByEmail)
      return {
        'id': userRef.key,
        'email': email.toLowerCase().trim(),
        'name': invitation['name'] ?? '',
        'role': invitation['role'] ?? 'user',
        'status': 'active',
      };
    } catch (e) {
      print('Error accepting invitation: $e');
      return null;
    }
  }

  // Accept invitation by ID (more robust than by email)
  static Future<Map<String, dynamic>?> acceptInvitationWithId(String invitationId, String email) async {
    try {
      final snapshot = await _getInvitationsRef().child(invitationId).get();
      if (!snapshot.exists) {
        return null;
      }

      final invitation = Map<String, dynamic>.from(snapshot.value as Map);
      invitation['id'] = snapshot.key;

      if (invitation['status'] != 'pending') {
        return null;
      }

      // Check if expired
      final expiresAt = invitation['expiresAt'] as int?;
      if (expiresAt != null && DateTime.now().millisecondsSinceEpoch > expiresAt) {
        // Mark as expired
        await _getInvitationsRef().child(invitationId).update({
          'status': 'expired',
        });
        return null;
      }

      // Verify email matches (case-insensitive)
      final invitationEmail = (invitation['email'] as String?)?.toLowerCase().trim();
      final providedEmail = email.toLowerCase().trim();

      if (invitationEmail != providedEmail) {
        return null;
      }

      // Prepare user data
      final userData = {
        'email': providedEmail,
        'name': invitation['name'] ?? '',
        'role': invitation['role'] ?? 'user',
        'status': 'active',
        'invitedBy': invitation['invitedBy'],
        'createdAt': ServerValue.timestamp,
        'lastLogin': ServerValue.timestamp,
      };

      // Create the user
      final userRef = _getUsersRef().push();
      await userRef.set(userData);

      // Mark invitation as accepted
      await _getInvitationsRef().child(invitationId).update({
        'status': 'accepted',
        'acceptedAt': ServerValue.timestamp,
      });

      // Return the user data directly
      return {
        'id': userRef.key,
        'email': providedEmail,
        'name': invitation['name'] ?? '',
        'role': invitation['role'] ?? 'user',
        'status': 'active',
      };
    } catch (e) {
      print('Error accepting invitation with ID: $e');
      return null;
    }
  }

  // Get user by email
  static Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    try {
      final snapshot = await _getUsersRef()
          .orderByChild('email')
          .equalTo(email.toLowerCase().trim())
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final entry = data.entries.first;
        final user = Map<String, dynamic>.from(entry.value as Map);
        user['id'] = entry.key;
        return user;
      }
      return null;
    } catch (e) {
      print('Error getting user: $e');
      return null;
    }
  }

  // Get all users
  static Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      final snapshot = await _getUsersRef().get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        return data.entries.map((entry) {
          final user = Map<String, dynamic>.from(entry.value as Map);
          user['id'] = entry.key;
          return user;
        }).toList();
      }
      return [];
    } catch (e) {
      print('Error getting all users: $e');
      return [];
    }
  }

  // Update user
  static Future<bool> updateUser(String userId, Map<String, dynamic> data) async {
    try {
      data['updatedAt'] = ServerValue.timestamp;
      await _getUsersRef().child(userId).update(data);
      return true;
    } catch (e) {
      print('Error updating user: $e');
      return false;
    }
  }

  // Delete user
  static Future<bool> deleteUser(String userId) async {
    try {
      await _getUsersRef().child(userId).remove();
      return true;
    } catch (e) {
      print('Error deleting user: $e');
      return false;
    }
  }

  // Delete invitation
  static Future<bool> deleteInvitation(String invitationId) async {
    try {
      await _getInvitationsRef().child(invitationId).remove();
      return true;
    } catch (e) {
      print('Error deleting invitation: $e');
      return false;
    }
  }

  // Update user last login
  static Future<void> updateUserLastLogin(String email) async {
    try {
      final user = await getUserByEmail(email);
      if (user != null) {
        await _getUsersRef().child(user['id']).update({
          'lastLogin': ServerValue.timestamp,
        });
      }
    } catch (e) {
      print('Error updating last login: $e');
    }
  }

  // Check if email is approved (checks users table first, then invitations)
  static Future<Map<String, dynamic>?> checkUserAccess(String email) async {
    try {
      // First check if user exists in users table
      final user = await getUserByEmail(email);
      if (user != null && user['status'] == 'active') {
        return user;
      }

      // If not in users table, check invitation status
      final invitation = await getInvitationByEmail(email);

      if (invitation != null) {
        // User has an accepted invitation - they are approved
        if (invitation['status'] == 'accepted') {
          return {
            'email': email.toLowerCase().trim(),
            'name': invitation['name'] ?? '',
            'role': invitation['role'] ?? 'user',
            'status': 'active',
          };
        }

        // User has a pending invitation - auto-accept it
        if (invitation['status'] == 'pending') {
          final expiresAt = invitation['expiresAt'] as int?;
          if (expiresAt != null && DateTime.now().millisecondsSinceEpoch <= expiresAt) {
            // Auto-accept the invitation and return the created user directly
            final newUser = await acceptInvitationWithId(invitation['id'], email);
            return newUser;
          }
        }
      }

      return null;
    } catch (e) {
      print('Error checking user access: $e');
      return null;
    }
  }

  // ==================== USER PERFORMANCE TRACKING ====================

  /// Get customer additions grouped by user email with optional date filtering
  /// Returns: { email: { name, total, services: {cignal, satellite, gsat, sky}, lastAddition } }
  static Future<Map<String, Map<String, dynamic>>> getCustomerAdditionsByUser({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final services = [cignal, satellite, gsat, sky];
      final Map<String, Map<String, dynamic>> userStats = {};

      for (final service in services) {
        final customers = await getCustomers(service);

        for (final customer in customers) {
          final addedBy = customer['addedBy'] as Map<dynamic, dynamic>?;
          if (addedBy == null) continue;

          final email = addedBy['email'] as String?;
          if (email == null || email.isEmpty) continue;

          final timestamp = addedBy['timestamp'] as int?;
          if (timestamp == null) continue;

          final addedDate = DateTime.fromMillisecondsSinceEpoch(timestamp);

          // Apply date filter
          if (startDate != null && addedDate.isBefore(startDate)) continue;
          if (endDate != null && addedDate.isAfter(endDate)) continue;

          // Initialize user entry if not exists
          if (!userStats.containsKey(email)) {
            userStats[email] = {
              'name': addedBy['name'] ?? '',
              'email': email,
              'total': 0,
              'services': {
                'cignal': 0,
                'satellite': 0,
                'gsat': 0,
                'sky': 0,
              },
              'lastAddition': null,
            };
          }

          // Update counts
          userStats[email]!['total'] = (userStats[email]!['total'] as int) + 1;
          final servicesMap = userStats[email]!['services'] as Map<String, int>;
          servicesMap[service] = (servicesMap[service] ?? 0) + 1;

          // Track last addition
          final currentLast = userStats[email]!['lastAddition'] as int?;
          if (currentLast == null || timestamp > currentLast) {
            userStats[email]!['lastAddition'] = timestamp;
          }
        }
      }

      return userStats;
    } catch (e) {
      print('Error getting customer additions by user: $e');
      return {};
    }
  }

  /// Get customer additions for a specific month
  static Future<Map<String, Map<String, dynamic>>> getCustomerAdditionsForMonth(
    int year,
    int month,
  ) async {
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 0, 23, 59, 59, 999);
    return getCustomerAdditionsByUser(startDate: startDate, endDate: endDate);
  }

  /// Get customer additions for a specific date
  static Future<Map<String, Map<String, dynamic>>> getCustomerAdditionsForDate(
    DateTime date,
  ) async {
    final startDate = DateTime(date.year, date.month, date.day);
    final endDate = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
    return getCustomerAdditionsByUser(startDate: startDate, endDate: endDate);
  }

  // ============ GSAT Activations ============

  static DatabaseReference _getGsatActivationsRef() {
    return _database.child('gsat_activations');
  }

  /// Add a new GSAT activation record
  static Future<String?> addGsatActivation({
    required String serialNumber,
    required String name,
    required String address,
    required String contactNumber,
    required String dealer,
  }) async {
    try {
      final ref = _getGsatActivationsRef().push();
      final now = DateTime.now();
      final data = <String, dynamic>{
        'serialNumber': serialNumber,
        'name': name,
        'address': address,
        'contactNumber': contactNumber,
        'dealer': dealer,
        'createdAt': now.toIso8601String(),
        'timestamp': ServerValue.timestamp,
      };

      await ref.set(data);

      // Update cache with new activation
      final newActivation = Map<String, dynamic>.from(data);
      newActivation['id'] = ref.key;
      await CacheService.saveGsatActivation(newActivation);

      return ref.key;
    } catch (e) {
      print('Error adding GSAT activation: $e');
      rethrow;
    }
  }

  /// Get all GSAT activations (cache-first)
  static Future<List<Map<String, dynamic>>> getGsatActivations() async {
    try {
      // Try cache first
      final hasCache = await CacheService.hasGsatActivationsCache();
      if (hasCache) {
        final cachedActivations = await CacheService.getGsatActivations();
        if (cachedActivations.isNotEmpty) {
          // Sort by createdAt descending (newest first)
          cachedActivations.sort((a, b) {
            final aDate = a['createdAt'] as String? ?? '';
            final bDate = b['createdAt'] as String? ?? '';
            return bDate.compareTo(aDate);
          });
          print('Loaded ${cachedActivations.length} GSAT activations from cache');
          return cachedActivations;
        }
      }

      // Fetch from Firebase
      final snapshot = await _getGsatActivationsRef()
          .orderByChild('timestamp')
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final activations = data.entries.map((entry) {
          final activation = Map<String, dynamic>.from(entry.value as Map);
          activation['id'] = entry.key;
          return activation;
        }).toList();

        // Sort by createdAt descending (newest first)
        activations.sort((a, b) {
          final aDate = a['createdAt'] as String? ?? '';
          final bDate = b['createdAt'] as String? ?? '';
          return bDate.compareTo(aDate);
        });

        // Save to cache
        await CacheService.saveGsatActivations(activations);

        return activations;
      }
      return [];
    } catch (e) {
      print('Error getting GSAT activations: $e');
      // Fallback to cache
      final cachedActivations = await CacheService.getGsatActivations();
      if (cachedActivations.isNotEmpty) {
        cachedActivations.sort((a, b) {
          final aDate = a['createdAt'] as String? ?? '';
          final bDate = b['createdAt'] as String? ?? '';
          return bDate.compareTo(aDate);
        });
        return cachedActivations;
      }
      return [];
    }
  }

  /// Update a GSAT activation
  static Future<bool> updateGsatActivation({
    required String activationId,
    required String serialNumber,
    required String name,
    required String address,
    required String contactNumber,
    required String dealer,
  }) async {
    try {
      await _getGsatActivationsRef().child(activationId).update({
        'serialNumber': serialNumber,
        'name': name,
        'address': address,
        'contactNumber': contactNumber,
        'dealer': dealer,
      });
      return true;
    } catch (e) {
      print('Error updating GSAT activation: $e');
      return false;
    }
  }

  /// Delete a GSAT activation
  static Future<bool> deleteGsatActivation(String activationId) async {
    try {
      await _getGsatActivationsRef().child(activationId).remove();
      return true;
    } catch (e) {
      print('Error deleting GSAT activation: $e');
      return false;
    }
  }
}
