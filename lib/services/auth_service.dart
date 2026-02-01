import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'firebase_database_service.dart';

class AuthService {
  // Firebase Auth instance
  static final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  // Google Sign In instance
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: '71583971266-ie3gpkatrmbacon13gfqon0oh24fljgj.apps.googleusercontent.com',
    scopes: [
      'email',
      'profile',
    ],
  );

  // Predefined admin emails (these are always admins regardless of database)
  static const List<String> _superAdmins = [
    'luzaresbenzgerald@gmail.com',
    'gmphoneshoppe24@gmail.com',
  ];

  // SharedPreferences keys
  static const String _keyIsLoggedIn = 'isLoggedIn';
  static const String _keyEmail = 'email';
  static const String _keyRole = 'role';
  static const String _keyName = 'name';

  // Check if email is a super admin
  static bool _isSuperAdmin(String email) {
    return _superAdmins.contains(email.toLowerCase().trim());
  }

  // Google Sign In method with Firebase Authentication
  static Future<Map<String, dynamic>?> signInWithGoogle() async {
    try {
      GoogleSignInAccount? googleUser;

      if (kIsWeb) {
        // For web, use Firebase Auth's signInWithPopup directly
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');

        final UserCredential userCredential = await _firebaseAuth.signInWithPopup(googleProvider);
        final User? firebaseUser = userCredential.user;

        if (firebaseUser == null) {
          return null;
        }

        final String email = firebaseUser.email ?? '';
        final String name = firebaseUser.displayName ?? 'User';

        // Continue with role check and user creation
        return await _processSignedInUser(email, name);
      }

      // For mobile platforms, use GoogleSignIn package
      googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return null; // The user canceled the sign-in
      }

      // Get authentication details from Google
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create a credential for Firebase
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      final UserCredential userCredential = await _firebaseAuth.signInWithCredential(credential);
      final User? firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        return null;
      }

      final String email = firebaseUser.email ?? googleUser.email;
      final String name = firebaseUser.displayName ?? googleUser.displayName ?? 'User';

      return await _processSignedInUser(email, name);
    } catch (error) {
      print('Google Sign In Error: $error');
      return null;
    }
  }

  // Google Sign In for signup - only authenticates, does not check access
  // Returns email and name without creating user or checking database
  static Future<Map<String, dynamic>?> signInWithGoogleForSignup() async {
    try {
      GoogleSignInAccount? googleUser;

      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');

        final UserCredential userCredential = await _firebaseAuth.signInWithPopup(googleProvider);
        final User? firebaseUser = userCredential.user;

        if (firebaseUser == null) {
          return null;
        }

        return {
          'email': firebaseUser.email ?? '',
          'name': firebaseUser.displayName ?? 'User',
        };
      }

      // For mobile platforms
      googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return null;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _firebaseAuth.signInWithCredential(credential);
      final User? firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        return null;
      }

      return {
        'email': firebaseUser.email ?? googleUser.email,
        'name': firebaseUser.displayName ?? googleUser.displayName ?? 'User',
      };
    } catch (error) {
      print('Google Sign In For Signup Error: $error');
      return null;
    }
  }

  // Complete signup after invitation is accepted - saves login state
  static Future<Map<String, dynamic>?> completeSignup(String email, String name, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, true);
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyRole, role);
    await prefs.setString(_keyName, name);

    return {
      'email': email,
      'role': role,
      'name': name,
    };
  }

  // Helper method to process signed in user (shared between web and mobile)
  static Future<Map<String, dynamic>?> _processSignedInUser(String email, String name) async {
    // Determine role
    String role = 'user';

    // Check if super admin first
    if (_isSuperAdmin(email)) {
      role = 'admin';
    } else {
      // Check Firebase database for approved users
      final dbUser = await FirebaseDatabaseService.checkUserAccess(email);
      if (dbUser != null) {
        role = dbUser['role'] ?? 'user';
        // Update last login
        await FirebaseDatabaseService.updateUserLastLogin(email);
      } else {
        // User not approved - sign out and return error
        await _firebaseAuth.signOut();
        if (!kIsWeb) {
          await _googleSignIn.signOut();
        }
        return {
          'error': 'not_approved',
          'email': email,
          'name': name,
        };
      }
    }

    // Save login state to SharedPreferences for app state persistence
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, true);
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyRole, role);
    await prefs.setString(_keyName, name);

    return {
      'email': email,
      'role': role,
      'name': name,
    };
  }

  // Logout method - signs out from both Firebase and Google
  static Future<void> logout() async {
    try {
      // Sign out from Firebase
      await _firebaseAuth.signOut();
      // Sign out from Google
      await _googleSignIn.signOut();
      // Clear local preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (error) {
      print('Logout error: $error');
    }
  }

  // Check if user is logged in (checks both Firebase and SharedPreferences)
  static Future<bool> isLoggedIn() async {
    // First check Firebase Auth state
    final User? firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser != null) {
      return true;
    }

    // Fallback to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsLoggedIn) ?? false;
  }

  // Get current user (with offline support)
  static Future<Map<String, dynamic>?> getCurrentUser() async {
    // First check SharedPreferences for cached user (works offline)
    final prefs = await SharedPreferences.getInstance();
    final cachedEmail = prefs.getString(_keyEmail);
    final cachedRole = prefs.getString(_keyRole);
    final cachedName = prefs.getString(_keyName);
    final isLoggedIn = prefs.getBool(_keyIsLoggedIn) ?? false;

    // Try to get from Firebase
    final User? firebaseUser = _firebaseAuth.currentUser;

    if (firebaseUser != null) {
      final String email = firebaseUser.email ?? '';
      final String name = firebaseUser.displayName ?? '';

      // Get role: check super admin first, then try database with timeout
      String role = 'user';
      if (_isSuperAdmin(email)) {
        role = 'admin';
      } else {
        // Try database with short timeout, fallback to cached role
        try {
          final dbUser = await FirebaseDatabaseService.getUserByEmail(email)
              .timeout(const Duration(seconds: 3), onTimeout: () => null);
          if (dbUser != null) {
            role = dbUser['role'] ?? 'user';
            // Update cache with fresh role
            await prefs.setString(_keyRole, role);
          } else if (cachedEmail == email && cachedRole != null) {
            // Use cached role if database unavailable
            role = cachedRole;
          }
        } catch (e) {
          // On error, use cached role if available
          if (cachedEmail == email && cachedRole != null) {
            role = cachedRole;
          }
        }
      }

      return {
        'email': email,
        'role': role,
        'name': name,
      };
    }

    // Fallback to SharedPreferences (fully offline)
    if (!isLoggedIn || cachedEmail == null || cachedEmail.isEmpty) {
      return null;
    }

    return {
      'email': cachedEmail,
      'role': cachedRole ?? 'user',
      'name': cachedName ?? '',
    };
  }

  // Get Firebase Auth current user directly
  static User? getFirebaseUser() {
    return _firebaseAuth.currentUser;
  }

  // Check if user is admin
  static bool isAdmin(Map<String, dynamic> user) {
    return user['role'] == 'admin';
  }

  // Check if user is POS account
  static bool isPOS(Map<String, dynamic> user) {
    return user['role'] == 'pos';
  }

  // Check if email is super admin (public method)
  static bool isSuperAdminEmail(String email) {
    return _isSuperAdmin(email);
  }

  // Listen to auth state changes (useful for reactive UI)
  static Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();
}
