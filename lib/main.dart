import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'firebase_options.dart';
import 'design/app_theme.dart';
import 'design/app_colors.dart';
import 'pages/landing_page.dart';
import 'pages/main_admin_page.dart';
import 'pages/main_user_page.dart';
import 'services/auth_service.dart';
import 'services/sync_service.dart';
import 'services/offline_sync_service.dart';
import 'services/notification_service.dart';
import 'services/onesignal_service.dart';
import 'services/local_notification_service.dart';
import 'services/inventory_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Run app IMMEDIATELY - Firebase will initialize in the splash screen
  // This prevents "app not responding" by showing UI instantly
  runApp(const GMPhoneShoppeApp());
}

/// Lifecycle observer to pause/resume Firebase listeners when app is backgrounded
/// This significantly reduces data usage when the app is not in use
class AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App is going to background - pause all listeners to save data
        SyncService.pauseListeners();
        NotificationService.pause();
        debugPrint('App backgrounded - pausing all listeners to save data');
        break;
      case AppLifecycleState.resumed:
        // App is back to foreground - resume all listeners
        SyncService.resumeListeners();
        NotificationService.resume();
        debugPrint('App resumed - resuming all listeners');
        break;
    }
  }
}

class GMPhoneShoppeApp extends StatelessWidget {
  const GMPhoneShoppeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GM PhoneShoppe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const AuthCheck(),
    );
  }
}

class AuthCheck extends StatefulWidget {
  const AuthCheck({super.key});

  @override
  State<AuthCheck> createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> with TickerProviderStateMixin {
  bool _navigated = false;
  String _statusText = 'Initializing...';
  double _progress = 0.0;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _shimmerController;

  // Lifecycle observer for pausing/resuming sync when app is backgrounded
  late final AppLifecycleObserver _lifecycleObserver;

  @override
  void initState() {
    super.initState();

    // Register lifecycle observer to pause sync when app is backgrounded
    // This significantly reduces data usage
    _lifecycleObserver = AppLifecycleObserver();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);

    // Fade in animation
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );

    // Logo pulse animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    // Shimmer animation for loading text
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _fadeController.forward();
    _checkAuth();

    // Fallback: if still on loading screen after 12 seconds, go to landing page
    Future.delayed(const Duration(seconds: 12), () {
      if (mounted && !_navigated) {
        _navigateToDestination(const LandingPage());
      }
    });
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _fadeController.dispose();
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  void _updateStatus(String text, double progress) {
    if (mounted) {
      setState(() {
        _statusText = text;
        _progress = progress;
      });
    }
  }

  void _navigateToDestination(Widget destination) {
    if (_navigated) return;
    _navigated = true;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  Future<void> _applyWakelockSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keepScreenOn = prefs.getBool('keep_screen_on') ?? false;
      if (keepScreenOn) {
        await WakelockPlus.enable();
        debugPrint('Wakelock enabled - screen will stay on');
      }
    } catch (e) {
      debugPrint('Error applying wakelock setting: $e');
    }
  }

  Future<void> _checkAuth() async {
    try {
      _updateStatus('Initializing...', 0.1);

      // Initialize Firebase here (after UI is visible) to prevent "app not responding"
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ).timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            throw Exception('Firebase initialization timed out');
          },
        );
      } catch (e) {
        debugPrint('Firebase initialization error: $e');
        // Continue anyway - offline mode will work
      }

      if (!mounted || _navigated) return;
      _updateStatus('Setting up services...', 0.2);

      // Apply Keep Screen On setting if enabled
      _applyWakelockSetting();

      // Initialize SyncService in background (non-blocking)
      // Don't await - let it run while we check auth
      SyncService.initialize().then((_) {
        debugPrint('SyncService initialized - offline-first caching enabled');
      }).catchError((e) {
        debugPrint('SyncService initialization error: $e');
      });

      // Initialize OfflineSyncService globally to sync pending data when online
      OfflineSyncService.initialize().then((_) {
        debugPrint('OfflineSyncService initialized - will sync pending data when online');
      }).catchError((e) {
        debugPrint('OfflineSyncService initialization error: $e');
      });

      // Run duplicate SKU migration in background (non-blocking)
      // This fixes any duplicate serial numbers from offline device conflicts
      InventoryService.runDuplicateSkuMigration().then((report) {
        if (report['alreadyRun'] == true) {
          debugPrint('SKU migration: Already completed previously');
        } else if (report['success'] == true) {
          final fixed = report['itemsFixed'] as int;
          if (fixed > 0) {
            debugPrint('SKU migration: Fixed $fixed duplicate serial numbers');
          } else {
            debugPrint('SKU migration: No duplicates found');
          }
        } else {
          debugPrint('SKU migration: Failed - ${report['errors']}');
        }
      }).catchError((e) {
        debugPrint('SKU migration error: $e');
      });

      // Initialize local notifications FIRST (works offline) - await to ensure permissions are granted
      await LocalNotificationService.initialize();

      // Initialize real-time stock alert listener
      NotificationService.initialize();

      // Initialize OneSignal push notifications (works when app is closed)
      OneSignalService.initialize();

      // Small delay to let UI render smoothly
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted || _navigated) return;

      _updateStatus('Checking authentication...', 0.3);
      final user = await AuthService.getCurrentUser().timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );

      if (!mounted || _navigated) return;

      _updateStatus('Loading your data...', 0.6);
      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted || _navigated) return;
      _updateStatus('Almost ready...', 0.85);
      await Future.delayed(const Duration(milliseconds: 200));

      if (!mounted || _navigated) return;
      _updateStatus('Welcome!', 1.0);
      await Future.delayed(const Duration(milliseconds: 200));

      if (!mounted || _navigated) return;

      Widget destination;
      if (user != null && user['email'] != null && user['email'].toString().isNotEmpty) {
        if (AuthService.isAdmin(user)) {
          destination = const MainAdminPage();
        } else {
          destination = MainUserPage(userName: user['name']);
        }
      } else {
        destination = const LandingPage();
      }

      _navigateToDestination(destination);
    } catch (e) {
      debugPrint('Auth check error: $e');
      if (!mounted || _navigated) return;
      _navigateToDestination(const LandingPage());
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.height < 700;
    final logoSize = isSmallScreen ? 100.0 : 130.0;
    final titleSize = isSmallScreen ? 24.0 : 30.0;
    final horizontalPadding = screenSize.width * 0.12; // 12% of screen width

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0D0505),
              Color(0xFF1A0A0A),
              Color(0xFF2D1010),
              Color(0xFF1A0A0A),
            ],
            stops: [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                Spacer(flex: isSmallScreen ? 2 : 3),
                // Animated logo with pulse and glow
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brandBurgundy.withValues(alpha: 0.4),
                          blurRadius: isSmallScreen ? 60 : 80,
                          spreadRadius: isSmallScreen ? 15 : 25,
                        ),
                        BoxShadow(
                          color: AppColors.brandRed.withValues(alpha: 0.2),
                          blurRadius: isSmallScreen ? 80 : 120,
                          spreadRadius: isSmallScreen ? 25 : 40,
                        ),
                      ],
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.brandBurgundy.withValues(alpha: 0.5),
                          width: 3,
                        ),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: logoSize,
                          height: logoSize,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: isSmallScreen ? 24 : 40),
                // App name with gradient
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.white, Color(0xFFE0E0E0)],
                  ).createShader(bounds),
                  child: Text(
                    'GM PhoneShoppe',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                SizedBox(height: isSmallScreen ? 6 : 10),
                // Tagline with shimmer
                AnimatedBuilder(
                  animation: _shimmerController,
                  builder: (context, child) {
                    return ShaderMask(
                      shaderCallback: (bounds) {
                        return LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.4),
                            Colors.white.withValues(alpha: 0.8),
                            Colors.white.withValues(alpha: 0.4),
                          ],
                          stops: [
                            (_shimmerController.value - 0.3).clamp(0.0, 1.0),
                            _shimmerController.value,
                            (_shimmerController.value + 0.3).clamp(0.0, 1.0),
                          ],
                        ).createShader(bounds);
                      },
                      child: const Text(
                        'E-Loading & POS Services',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 2.0,
                        ),
                      ),
                    );
                  },
                ),
                Spacer(flex: isSmallScreen ? 1 : 2),
                // Modern progress section
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Column(
                    children: [
                      // Custom progress bar with smooth animation
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: _progress),
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Container(
                            height: 4,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: value.clamp(0.0, 1.0),
                                child: Container(
                                  height: 4,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(2),
                                    gradient: const LinearGradient(
                                      colors: [
                                        AppColors.brandBurgundy,
                                        AppColors.brandRed,
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.brandRed.withValues(alpha: 0.5),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      SizedBox(height: isSmallScreen ? 14 : 20),
                      // Status text with fade animation
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          _statusText,
                          key: ValueKey(_statusText),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: isSmallScreen ? 12 : 13,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.5,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 1),
                // Footer
                Padding(
                  padding: EdgeInsets.only(bottom: isSmallScreen ? 16 : 24),
                  child: Text(
                    'Powered by GM PhoneShoppe',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: isSmallScreen ? 10 : 11,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
