import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'cignal_page.dart';
import 'satlite_page.dart';
import 'gsat_page.dart';
import 'gsat_activation_page.dart';
import 'sky_page.dart';
import 'inventory_page.dart';
import 'transaction_history_page.dart';
import 'landing_page.dart';
import 'admin_profile_page.dart';
import 'settings_page.dart';
import 'label_printing_page.dart';
import '../services/auth_service.dart';
import '../services/firebase_database_service.dart';
import '../services/inventory_service.dart';
import '../services/email_service.dart';
import '../services/cache_service.dart';
import '../services/staff_pin_service.dart';
import '../services/notification_service.dart';

class MainAdminPage extends StatefulWidget {
  const MainAdminPage({super.key});

  @override
  State<MainAdminPage> createState() => _MainAdminPageState();
}

class _MainAdminPageState extends State<MainAdminPage> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  late AnimationController _scaleAnimationController;
  late Animation<double> _scaleAnimation;
  bool _showScrollToTop = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _userFirstName = 'Admin';

  // Low stock notification state
  List<Map<String, dynamic>> _lowStockItems = [];

  // Pre-built pages kept alive via IndexedStack
  late final List<Widget> _pages;

  // Service color themes matching landing page
  static const cignalGradient = [Color(0xFF8B1A1A), Color(0xFF5C0F0F)];
  static const satliteGradient = [Color(0xFFFF6B35), Color(0xFFCC5528)];
  static const gsatGradient = [Color(0xFF2ECC71), Color(0xFF27AE60)];
  static const skyGradient = [Color(0xFF3498DB), Color(0xFFFF6B35)];
  static const allUsersGradient = [Color(0xFF1ABC9C), Color(0xFF16A085)];
  static const reportsGradient = [Color(0xFF9B59B6), Color(0xFF8E44AD)];
  static const settingsGradient = [Color(0xFF95A5A6), Color(0xFF7F8C8D)];
  static const dashboardGradient = [Color(0xFF8B1A1A), Color(0xFF5C0F0F)];
  static const inventoryGradient = [Color(0xFFE67E22), Color(0xFFD35400)];
  static const profileGradient = [Color(0xFF6C5CE7), Color(0xFF4834D4)];

  final List<_MenuItem> _menuItems = [
    _MenuItem(
      icon: Icons.dashboard,
      title: 'Dashboard',
      gradientColors: dashboardGradient,
    ),
    _MenuItem(
      icon: Icons.tv,
      title: 'Cignal',
      gradientColors: cignalGradient,
      logoPath: 'Photos/CIGNAL.png',
    ),
    _MenuItem(
      icon: Icons.satellite_alt,
      title: 'Satlite',
      gradientColors: satliteGradient,
      logoPath: 'Photos/SATLITE.png',
    ),
    _MenuItem(
      icon: Icons.public,
      title: 'GSAT',
      gradientColors: gsatGradient,
      logoPath: 'Photos/GSAT.png',
    ),
    _MenuItem(
      icon: Icons.rocket_launch,
      title: 'GSAT Activation',
      gradientColors: gsatGradient,
      logoPath: 'Photos/GSAT.png',
    ),
    _MenuItem(
      icon: Icons.cloud,
      title: 'Sky',
      gradientColors: skyGradient,
      logoPath: 'Photos/SKY.png',
    ),
    _MenuItem(
      icon: Icons.inventory_2,
      title: 'Inventory',
      gradientColors: inventoryGradient,
    ),
    _MenuItem(
      icon: Icons.history,
      title: 'Transactions',
      gradientColors: inventoryGradient,
    ),
    _MenuItem(
      icon: Icons.qr_code_2,
      title: 'Label Printing',
      gradientColors: inventoryGradient,
    ),
    _MenuItem(
      icon: Icons.people,
      title: 'All Users',
      gradientColors: allUsersGradient,
    ),
    _MenuItem(
      icon: Icons.bar_chart,
      title: 'Reports',
      gradientColors: reportsGradient,
    ),
    _MenuItem(
      icon: Icons.settings,
      title: 'Settings',
      gradientColors: settingsGradient,
    ),
    _MenuItem(
      icon: Icons.person,
      title: 'Profile',
      gradientColors: profileGradient,
    ),
  ];

  @override
  void initState() {
    super.initState();

    // Load user's first name and stock alerts
    _loadUserName();
    _loadLowStockItems();

    // Listen for real-time stock alerts from other devices
    NotificationService.onNewAlert = _onStockAlert;

    // Scale animation for logos (triggered on touch)
    _scaleAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(
        parent: _scaleAnimationController,
        curve: Curves.easeOut,
      ),
    );

    _scrollController.addListener(_onScroll);

    _pages = [
      _AdminDashboardPage(
        scaleAnimation: _scaleAnimation,
        onLogoTouchStart: _onLogoTouchStart,
        onLogoTouchEnd: _onLogoTouchEnd,
        onNavigateToService: _navigateToService,
      ),
      const CignalPage(),
      const SatlitePage(),
      const GSatPage(),
      const GsatActivationPage(),
      const SkyPage(),
      const InventoryPage(),
      const TransactionHistoryPage(),
      const LabelPrintingPage(),
      const _AllUsersPage(),
      const _ReportsPage(),
      const SettingsPage(isAdmin: true),
      const AdminProfilePage(),
    ];
  }

  Future<void> _loadLowStockItems() async {
    try {
      final items = await InventoryService.getLowStockItems();
      if (mounted) {
        setState(() => _lowStockItems = items);
      }
    } catch (_) {}
  }

  void _showNotificationsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        final outOfStock = _lowStockItems.where((i) => (i['quantity'] as int? ?? 0) == 0).toList();
        final lowStock = _lowStockItems.where((i) => (i['quantity'] as int? ?? 0) > 0).toList();

        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (ctx, scrollController) => Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.notifications_active, color: Colors.redAccent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Stock Alerts',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_lowStockItems.length}',
                        style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              // List
              Expanded(
                child: _lowStockItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline, color: Colors.green.withValues(alpha: 0.5), size: 48),
                            const SizedBox(height: 12),
                            Text('All stock levels are healthy', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14)),
                          ],
                        ),
                      )
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        children: [
                          if (outOfStock.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 6),
                              child: Text('OUT OF STOCK', style: TextStyle(color: Colors.red.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                            ),
                            ...outOfStock.map((item) => _buildStockAlertTile(item, isOutOfStock: true)),
                          ],
                          if (lowStock.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 12, bottom: 6),
                              child: Text('LOW STOCK', style: TextStyle(color: Colors.orange.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                            ),
                            ...lowStock.map((item) => _buildStockAlertTile(item, isOutOfStock: false)),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStockAlertTile(Map<String, dynamic> item, {required bool isOutOfStock}) {
    final name = item['name'] as String? ?? 'Unknown';
    final sku = item['sku'] as String? ?? item['serialNo'] as String? ?? '-';
    final qty = item['quantity'] as int? ?? 0;
    final reorderLevel = item['reorderLevel'] as int? ?? 5;
    final alertColor = isOutOfStock ? Colors.red : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: alertColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: alertColor.withValues(alpha: 0.15)),
      ),
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          setState(() => _selectedIndex = 6); // Navigate to Inventory
        },
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: alertColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  isOutOfStock ? Icons.error_outline : Icons.warning_amber_rounded,
                  color: alertColor,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('SKU: $sku', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isOutOfStock ? 'Empty' : '$qty left',
                  style: TextStyle(color: alertColor, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  'Reorder: $reorderLevel',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadUserName() async {
    final user = await AuthService.getCurrentUser();
    if (user != null && mounted) {
      final fullName = user['name'] as String? ?? 'Admin';
      final firstName = fullName.split(' ').first;
      setState(() {
        _userFirstName = firstName;
      });
    }
  }

  void _onLogoTouchStart() {
    _scaleAnimationController.forward();
  }

  void _onLogoTouchEnd() {
    _scaleAnimationController.reverse();
  }

  void _onScroll() {
    final showButton = _scrollController.offset > 200;
    if (showButton != _showScrollToTop) {
      setState(() {
        _showScrollToTop = showButton;
      });
    }
  }

  void _onStockAlert(Map<String, dynamic> alert) {
    if (!mounted) return;
    _loadLowStockItems(); // Refresh bell icon badge
    final title = alert['title'] ?? 'Stock Alert';
    final body = alert['body'] ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              alert['alertType'] == 'out_of_stock'
                  ? Icons.error_outline
                  : Icons.warning_amber_rounded,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (body.isNotEmpty) Text(body, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: alert['alertType'] == 'out_of_stock'
            ? const Color(0xFFD32F2F)
            : const Color(0xFFF57C00),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void dispose() {
    NotificationService.onNewAlert = null;
    _scrollController.dispose();
    _scaleAnimationController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
    );
  }

  void _navigateToService(int serviceIndex) {
    setState(() {
      _selectedIndex = serviceIndex;
    });
  }


  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF1A0A0A),
      drawer: isMobile ? _buildMobileDrawer(context, isMobile, isLandscape) : null,
      appBar: _buildAppBar(context, isMobile),
      body: Stack(
        children: [
          Row(
            children: [
              if (!isMobile) _buildSidebar(isMobile),
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: _pages,
                ),
              ),
            ],
          ),
          if (_showScrollToTop)
            Positioned(
              bottom: 20,
              right: 20,
              child: _buildScrollToTopButton(isMobile),
            ),
        ],
      ),
      bottomNavigationBar: isMobile && !isLandscape ? _buildBottomNav() : null,
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, bool isMobile) {
    return AppBar(
      toolbarHeight: isMobile ? 70 : 80,
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF1A0A0A).withValues(alpha: 0.98),
              const Color(0xFF1A0A0A).withValues(alpha: 0.95),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
      leading: isMobile
          ? IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () {
                _scaffoldKey.currentState?.openDrawer();
              },
            )
          : null,
      title: GestureDetector(
        onTap: () {
          setState(() {
            _selectedIndex = 0;
          });
        },
        child: Row(
          children: [
            Container(
              width: isMobile ? 32 : 40,
              height: isMobile ? 32 : 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(isMobile ? 8 : 10),
              ),
              padding: EdgeInsets.all(isMobile ? 4 : 6),
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(Icons.phone_android, color: const Color(0xFF8B1A1A), size: isMobile ? 16 : 20);
                },
              ),
            ),
            SizedBox(width: isMobile ? 8 : 12),
            Flexible(
              child: Text(
                isMobile ? 'GM Admin' : 'GM PhoneShoppe Admin',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isMobile ? 14 : 20,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      actions: [
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications, color: Colors.white),
              onPressed: _showNotificationsSheet,
            ),
            if (_lowStockItems.isNotEmpty)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFE74C3C), Color(0xFFC0392B)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    '${_lowStockItems.length > 99 ? '99+' : _lowStockItems.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white),
          tooltip: 'Logout',
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF252525),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text('Sign Out', style: TextStyle(color: Colors.white)),
                content: const Text(
                  'Are you sure you want to sign out of your account?',
                  style: TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      navigator.pop();
                      await AuthService.logout();
                      navigator.pushAndRemoveUntil(
                        MaterialPageRoute(builder: (context) => const LandingPage()),
                        (route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildDrawerItem(int index, BuildContext ctx) {
    final item = _menuItems[index];
    final isSelected = _selectedIndex == index;
    final gradColor = item.gradientColors.first;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          splashColor: gradColor.withValues(alpha: 0.1),
          highlightColor: gradColor.withValues(alpha: 0.05),
          onTap: () {
            setState(() => _selectedIndex = index);
            Navigator.pop(ctx);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: isSelected ? gradColor.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // Icon with subtle background
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? gradColor.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: item.logoPath != null
                        ? Image.asset(
                            item.logoPath!,
                            width: 20,
                            height: 20,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(item.icon, color: isSelected ? gradColor : Colors.white38, size: 20);
                            },
                          )
                        : Icon(
                            item.icon,
                            color: isSelected ? gradColor : Colors.white38,
                            size: 20,
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.6),
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 14,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: gradColor,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 26, right: 20, top: 20, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.3),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.8,
        ),
      ),
    );
  }

  Widget _buildMobileDrawer(BuildContext context, bool isMobile, bool isLandscape) {
    return Drawer(
      backgroundColor: const Color(0xFF0D0D0D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Modern profile header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
              child: Row(
                children: [
                  // User avatar with initials
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF8B1A1A), Color(0xFFB22222)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        _userFirstName.isNotEmpty ? _userFirstName[0].toUpperCase() : 'A',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _userFirstName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE67E22).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE67E22),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Text(
                                'Admin',
                                style: TextStyle(
                                  color: Color(0xFFE67E22),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Close button
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.3), size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
            // Subtle divider
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(height: 1, color: Colors.white.withValues(alpha: 0.06)),
            ),
            // Menu items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 4, bottom: 16),
                children: [
                  _buildDrawerSectionLabel('Services'),
                  _buildDrawerItem(0, context),
                  if (isLandscape) ...[
                    _buildDrawerItem(1, context),
                    _buildDrawerItem(2, context),
                    _buildDrawerItem(3, context),
                  ],
                  _buildDrawerItem(4, context),
                  if (isLandscape) _buildDrawerItem(5, context),
                  _buildDrawerSectionLabel('Management'),
                  _buildDrawerItem(6, context),
                  _buildDrawerItem(7, context),
                  _buildDrawerItem(8, context),
                  _buildDrawerItem(9, context),
                  _buildDrawerItem(10, context),
                  _buildDrawerSectionLabel('Account'),
                  _buildDrawerItem(11, context),
                  _buildDrawerItem(12, context),
                ],
              ),
            ),
            // Modern footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(Icons.storefront, color: Colors.white.withValues(alpha: 0.2), size: 14);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'GM PhoneShoppe',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.2),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'v1.0',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.12),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(int index) {
    final item = _menuItems[index];
    final isSelected = _selectedIndex == index;
    final gradColor = item.gradientColors.first;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: Colors.white.withValues(alpha: 0.04),
          onTap: () {
            setState(() {
              _selectedIndex = index;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: isSelected ? gradColor.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // Icon with background
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? gradColor.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: item.logoPath != null
                        ? Image.asset(
                            item.logoPath!,
                            width: 20,
                            height: 20,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(item.icon, color: isSelected ? gradColor : Colors.white38, size: 20);
                            },
                          )
                        : Icon(
                            item.icon,
                            color: isSelected ? gradColor : Colors.white38,
                            size: 20,
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.6),
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 14,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: gradColor,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, top: 20, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.3),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.8,
        ),
      ),
    );
  }

  Widget _buildSidebar(bool isMobile) {
    return Container(
      width: 270,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        border: Border(
          right: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Modern compact header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Row(
              children: [
                // Avatar with initials
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF8B1A1A), Color(0xFFB22222)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      _userFirstName.isNotEmpty ? _userFirstName[0].toUpperCase() : 'A',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _userFirstName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE67E22).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE67E22),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'Admin',
                              style: TextStyle(
                                color: Color(0xFFE67E22),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          ),
          // Menu items grouped by section
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              children: [
                _buildSectionLabel('Services'),
                for (final i in [0, 1, 2, 3, 4, 5]) _buildSidebarItem(i),
                _buildSectionLabel('Management'),
                for (final i in [6, 7, 8, 9, 10]) _buildSidebarItem(i),
                _buildSectionLabel('Account'),
                for (final i in [11, 12]) _buildSidebarItem(i),
              ],
            ),
          ),
          // Modern footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(Icons.storefront, color: Colors.white.withValues(alpha: 0.2), size: 14);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'GM PhoneShoppe',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                Text(
                  'v1.0',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.12),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Bottom navigation for services only (mobile)
  Widget _buildBottomNav() {
    // Services: Cignal (1), Satlite (2), GSAT (3), Sky (5)
    final serviceIndices = [1, 2, 3, 5];
    final serviceItems = serviceIndices.map((i) => _menuItems[i]).toList();
    final serviceIndex = serviceIndices.indexOf(_selectedIndex);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(serviceItems.length, (index) {
              final item = serviceItems[index];
              final isSelected = serviceIndex == index;
              final gradColor = item.gradientColors.first;

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedIndex = serviceIndices[index];
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: isSelected ? gradColor.withValues(alpha: 0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? gradColor.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: item.logoPath != null
                                ? Image.asset(
                                    item.logoPath!,
                                    width: 22,
                                    height: 22,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(item.icon, color: isSelected ? gradColor : Colors.white38, size: 22);
                                    },
                                  )
                                : Icon(item.icon, color: isSelected ? gradColor : Colors.white38, size: 22),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.title,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.4),
                            fontSize: 10,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            letterSpacing: 0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollToTopButton(bool isMobile) {
    return AnimatedOpacity(
      opacity: _showScrollToTop ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: FloatingActionButton(
        onPressed: _scrollToTop,
        backgroundColor: const Color(0xFF8B1A1A),
        foregroundColor: Colors.white,
        elevation: 6,
        shape: isMobile
            ? const CircleBorder()
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
        child: const Icon(Icons.arrow_upward),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String title;
  final List<Color> gradientColors;
  final String? logoPath;

  _MenuItem({
    required this.icon,
    required this.title,
    required this.gradientColors,
    this.logoPath,
  });
}

// Admin Dashboard Page
class _AdminDashboardPage extends StatefulWidget {
  final Animation<double> scaleAnimation;
  final VoidCallback onLogoTouchStart;
  final VoidCallback onLogoTouchEnd;
  final void Function(int) onNavigateToService;

  const _AdminDashboardPage({
    required this.scaleAnimation,
    required this.onLogoTouchStart,
    required this.onLogoTouchEnd,
    required this.onNavigateToService,
  });

  @override
  State<_AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<_AdminDashboardPage> {
  int _totalCustomers = 0;
  final int _activeServices = 4; // Cignal, Satlite, GSAT, Sky
  int _thisMonthCustomers = 0;
  bool _isLoading = true;

  // Location filter dropdown
  String _selectedLocation = 'All Locations';
  final List<String> _locationOptions = ['All Locations', 'Cebu', 'Masbate'];

  // Per-service customer counts
  Map<String, int> _serviceCustomerCounts = {
    'cignal': 0,
    'satellite': 0,
    'gsat': 0,
    'sky': 0,
  };

  // Per-service location counts (Cebu vs Masbate based on supplier field)
  Map<String, Map<String, int>> _serviceLocationCounts = {
    'cignal': {'cebu': 0, 'masbate': 0},
    'satellite': {'cebu': 0, 'masbate': 0},
    'gsat': {'cebu': 0, 'masbate': 0},
    'sky': {'cebu': 0, 'masbate': 0},
  };

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _onRefresh() async {
    setState(() => _isLoading = true);

    final services = [
      FirebaseDatabaseService.cignal,
      FirebaseDatabaseService.satellite,
      FirebaseDatabaseService.gsat,
      FirebaseDatabaseService.sky,
    ];

    int refreshedCount = 0;

    // Only refresh services that don't have cache or have stale cache (older than 5 minutes)
    for (final service in services) {
      final hasCache = await CacheService.hasCustomersCache(service);
      final needsSync = await CacheService.needsSync('customers_$service');

      if (!hasCache || needsSync) {
        FirebaseDatabaseService.forceRefresh(service);
        refreshedCount++;
      }
    }

    // Reload dashboard data
    await _loadDashboardData();

    // Show feedback about what was refreshed
    if (mounted && refreshedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            refreshedCount == services.length
                ? 'All services refreshed from Firebase'
                : 'Refreshed $refreshedCount service${refreshedCount > 1 ? 's' : ''} from Firebase',
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF2ECC71),
        ),
      );
    } else if (mounted && refreshedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All data is up to date from cache'),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF3498DB),
        ),
      );
    }
  }

  // Get filtered customer count based on selected location
  int _getFilteredTotalCustomers() {
    if (_selectedLocation == 'All Locations') {
      return _totalCustomers;
    }

    int total = 0;
    final locationKey = _selectedLocation.toLowerCase();
    for (final service in _serviceLocationCounts.keys) {
      total += _serviceLocationCounts[service]?[locationKey] ?? 0;
    }
    return total;
  }

  // Get filtered service count based on selected location
  int _getFilteredServiceCount(String service) {
    if (_selectedLocation == 'All Locations') {
      return _serviceCustomerCounts[service] ?? 0;
    }

    final locationKey = _selectedLocation.toLowerCase();
    return _serviceLocationCounts[service]?[locationKey] ?? 0;
  }

  Future<void> _loadDashboardData() async {
    try {
      // Get customers from all services
      final services = [
        FirebaseDatabaseService.cignal,
        FirebaseDatabaseService.satellite,
        FirebaseDatabaseService.gsat,
        FirebaseDatabaseService.sky,
      ];

      int totalCount = 0;
      int thisMonthCount = 0;
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;

      final Map<String, int> serviceCounts = {};
      final Map<String, Map<String, int>> locationCounts = {};

      // Fetch customers from each service
      for (final service in services) {
        final customers = await FirebaseDatabaseService.getCustomers(service);
        serviceCounts[service] = customers.length;
        totalCount += customers.length;

        int cebuCount = 0;
        int masbateCount = 0;

        // Count customers added this month and location counts
        for (final customer in customers) {
          final createdAt = customer['createdAt'] as int?;
          if (createdAt != null && createdAt >= startOfMonth) {
            thisMonthCount++;
          }

          // Count by supplier (location)
          final supplier = (customer['supplier'] as String?)?.toLowerCase() ?? '';
          if (supplier.contains('cebu')) {
            cebuCount++;
          } else if (supplier.contains('masbate')) {
            masbateCount++;
          }
        }

        locationCounts[service] = {
          'cebu': cebuCount,
          'masbate': masbateCount,
        };
      }

      if (mounted) {
        setState(() {
          _totalCustomers = totalCount;
          _thisMonthCustomers = thisMonthCount;
          _serviceCustomerCounts = serviceCounts;
          _serviceLocationCounts = locationCounts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final isCompact = isMobile && isLandscape;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF1A0A0A),
            const Color(0xFF2A1A1A),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fixed header at the top - hide in compact mode
          if (!isCompact)
            Padding(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 16 : 24,
                isMobile ? 16 : 24,
                isMobile ? 16 : 24,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome, Admin',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isMobile ? 32 : 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Manage your services and users',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: isMobile ? 16 : 20,
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(height: isCompact ? 8 : 24),
          // Scrollable content with pull-to-refresh
          Expanded(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              color: const Color(0xFF8B1A1A),
              backgroundColor: Colors.white,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  isCompact ? 8 : (isMobile ? 16 : 24),
                  0,
                  isCompact ? 8 : (isMobile ? 16 : 24),
                  isCompact ? 8 : (isMobile ? 16 : 24),
                ),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // In compact mode, show welcome inline
                  if (isCompact)
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Welcome, Admin',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Text(
                          'Quick Stats',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Quick Stats',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isMobile ? 24 : 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        // Location Filter Dropdown
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedLocation,
                              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                              dropdownColor: const Color(0xFF2A1A1A),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isMobile ? 14 : 16,
                                fontWeight: FontWeight.w500,
                              ),
                              items: _locationOptions.map((String location) {
                                return DropdownMenuItem<String>(
                                  value: location,
                                  child: Row(
                                    children: [
                                      Icon(
                                        location == 'All Locations'
                                            ? Icons.public
                                            : Icons.location_on,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(location),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  setState(() {
                                    _selectedLocation = newValue;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  SizedBox(height: isCompact ? 8 : 16),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    mainAxisSpacing: isCompact ? 6 : 16,
                    crossAxisSpacing: isCompact ? 6 : 16,
                    childAspectRatio: isCompact ? 2.5 : (isMobile ? 1.0 : 1.8),
                    children: [
                      _StatCard(
                        title: 'Total Customers',
                        value: _isLoading ? '...' : _getFilteredTotalCustomers().toString(),
                        icon: Icons.people,
                        gradientColors: const [Color(0xFF1ABC9C), Color(0xFF16A085)],
                        isMobile: isMobile,
                        isCompact: isCompact,
                      ),
                      _StatCard(
                        title: 'Active Services',
                        value: _activeServices.toString(),
                        icon: Icons.check_circle,
                        gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)],
                        isMobile: isMobile,
                        isCompact: isCompact,
                      ),
                      _StatCard(
                        title: 'New This Month',
                        value: _isLoading ? '...' : _thisMonthCustomers.toString(),
                        icon: Icons.trending_up,
                        gradientColors: const [Color(0xFFFF6B35), Color(0xFFCC5528)],
                        isMobile: isMobile,
                        isCompact: isCompact,
                      ),
                    ],
                  ),
                  SizedBox(height: isCompact ? 12 : 32),
                  Text(
                    'Services Overview',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isCompact ? 14 : (isMobile ? 24 : 32),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: isCompact ? 8 : 16),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: isCompact ? 4 : (isMobile ? 2 : 4),
                    mainAxisSpacing: isCompact ? 6 : 16,
                    crossAxisSpacing: isCompact ? 6 : 16,
                    childAspectRatio: isCompact ? 1.5 : (isMobile ? 1.0 : 1.2),
                    children: [
                      _ServiceOverviewCard(
                        logoPath: 'Photos/CIGNAL.png',
                        customers: _isLoading ? '...' : _getFilteredServiceCount('cignal').toString(),
                        cebuBoxes: _isLoading ? null : _serviceLocationCounts['cignal']?['cebu']?.toString(),
                        masbateBoxes: _isLoading ? null : _serviceLocationCounts['cignal']?['masbate']?.toString(),
                        gradientColors: const [Color(0xFF8B1A1A), Color(0xFF5C0F0F)],
                        scaleAnimation: widget.scaleAnimation,
                        onTouchStart: widget.onLogoTouchStart,
                        onTouchEnd: widget.onLogoTouchEnd,
                        onTap: () => widget.onNavigateToService(1),
                        isMobile: isMobile,
                        isLoading: _isLoading,
                        showLocationCounts: _selectedLocation == 'All Locations',
                      ),
                      _ServiceOverviewCard(
                        logoPath: 'Photos/SATLITE.png',
                        customers: _isLoading ? '...' : _getFilteredServiceCount('satellite').toString(),
                        cebuBoxes: _isLoading ? null : _serviceLocationCounts['satellite']?['cebu']?.toString(),
                        masbateBoxes: _isLoading ? null : _serviceLocationCounts['satellite']?['masbate']?.toString(),
                        gradientColors: const [Color(0xFFFF6B35), Color(0xFFCC5528)],
                        scaleAnimation: widget.scaleAnimation,
                        onTouchStart: widget.onLogoTouchStart,
                        onTouchEnd: widget.onLogoTouchEnd,
                        onTap: () => widget.onNavigateToService(2),
                        isMobile: isMobile,
                        isLoading: _isLoading,
                        showLocationCounts: _selectedLocation == 'All Locations',
                      ),
                      _ServiceOverviewCard(
                        logoPath: 'Photos/GSAT.png',
                        customers: _isLoading ? '...' : _getFilteredServiceCount('gsat').toString(),
                        cebuBoxes: _isLoading ? null : _serviceLocationCounts['gsat']?['cebu']?.toString(),
                        masbateBoxes: _isLoading ? null : _serviceLocationCounts['gsat']?['masbate']?.toString(),
                        gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)],
                        scaleAnimation: widget.scaleAnimation,
                        onTouchStart: widget.onLogoTouchStart,
                        onTouchEnd: widget.onLogoTouchEnd,
                        onTap: () => widget.onNavigateToService(3),
                        isMobile: isMobile,
                        isLoading: _isLoading,
                        showLocationCounts: _selectedLocation == 'All Locations',
                      ),
                      _ServiceOverviewCard(
                        logoPath: 'Photos/SKY.png',
                        customers: _isLoading ? '...' : _getFilteredServiceCount('sky').toString(),
                        cebuBoxes: _isLoading ? null : _serviceLocationCounts['sky']?['cebu']?.toString(),
                        masbateBoxes: _isLoading ? null : _serviceLocationCounts['sky']?['masbate']?.toString(),
                        gradientColors: const [Color(0xFF3498DB), Color(0xFFFF6B35)],
                        scaleAnimation: widget.scaleAnimation,
                        onTouchStart: widget.onLogoTouchStart,
                        onTouchEnd: widget.onLogoTouchEnd,
                        onTap: () => widget.onNavigateToService(4),
                        isMobile: isMobile,
                        isLoading: _isLoading,
                        showLocationCounts: _selectedLocation == 'All Locations',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }
}

// All Users Page
class _AllUsersPage extends StatefulWidget {
  const _AllUsersPage();

  @override
  State<_AllUsersPage> createState() => _AllUsersPageState();
}

class _AllUsersPageState extends State<_AllUsersPage> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _pendingInvitations = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  bool _currentUserIsSuperAdmin = false;
  String? _expandedUserId; // Track which user is expanded on mobile

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCurrentUserStatus();
    _loadData();
  }

  Future<void> _loadCurrentUserStatus() async {
    final currentUser = await AuthService.getCurrentUser();
    if (currentUser != null && mounted) {
      setState(() {
        _currentUserIsSuperAdmin = AuthService.isSuperAdminEmail(currentUser['email'] ?? '');
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final users = await FirebaseDatabaseService.getAllUsers();
      final invitations = await FirebaseDatabaseService.getPendingInvitations();
      setState(() {
        _users = users;
        _filteredUsers = users;
        _pendingInvitations = invitations;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _filterUsers(String query) {
    setState(() {
      _searchQuery = query.toLowerCase().trim();
      if (_searchQuery.isEmpty) {
        _filteredUsers = _users;
      } else {
        _filteredUsers = _users.where((user) {
          final name = (user['name'] ?? '').toString().toLowerCase();
          final email = (user['email'] ?? '').toString().toLowerCase();
          return name.contains(_searchQuery) || email.contains(_searchQuery);
        }).toList();
      }
    });
  }

  Future<void> _showInviteUserDialog() async {
    final emailController = TextEditingController();
    final nameController = TextEditingController();
    String selectedRole = 'user';
    bool isSending = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final screenWidth = MediaQuery.of(context).size.width;
          final isMobileDialog = screenWidth < 400;

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.symmetric(
              horizontal: isMobileDialog ? 16 : 40,
              vertical: 24,
            ),
            child: Container(
              width: screenWidth * 0.9,
              constraints: BoxConstraints(
                maxWidth: 480,
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: EdgeInsets.all(isMobileDialog ? 16 : 24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF1ABC9C).withValues(alpha: 0.2),
                          const Color(0xFF16A085).withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(28),
                        topRight: Radius.circular(28),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(isMobileDialog ? 8 : 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1ABC9C), Color(0xFF16A085)],
                            ),
                            borderRadius: BorderRadius.circular(isMobileDialog ? 10 : 14),
                          ),
                          child: Icon(Icons.person_add, color: Colors.white, size: isMobileDialog ? 20 : 24),
                        ),
                        SizedBox(width: isMobileDialog ? 12 : 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Invite New User',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isMobileDialog ? 16 : 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (!isMobileDialog) ...[
                                const SizedBox(height: 4),
                                const Text(
                                  'Send an invitation to join your team',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: isSending ? null : () => Navigator.of(context).pop(),
                          icon: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.5)),
                          iconSize: isMobileDialog ? 20 : 24,
                          padding: EdgeInsets.all(isMobileDialog ? 4 : 8),
                          constraints: BoxConstraints(
                            minWidth: isMobileDialog ? 32 : 40,
                            minHeight: isMobileDialog ? 32 : 40,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(isMobileDialog ? 16 : 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Email field
                        Text(
                          'Email Address',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: emailController,
                        style: const TextStyle(color: Colors.black87, fontSize: 16),
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: 'user@example.com',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                          prefixIcon: Icon(Icons.email_outlined, color: Colors.grey.shade600),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Name field
                      Text(
                        'Name (Optional)',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameController,
                        style: const TextStyle(color: Colors.black87, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'John Doe',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                          prefixIcon: Icon(Icons.person_outline, color: Colors.grey.shade600),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Role field - only show for super admins
                      if (_currentUserIsSuperAdmin) ...[
                        Text(
                          'Role',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: selectedRole,
                          dropdownColor: Colors.white,
                          style: const TextStyle(color: Colors.black87, fontSize: 16),
                          icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.badge_outlined, color: Colors.grey.shade600),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'user', child: Text('User', style: TextStyle(color: Colors.black87))),
                            DropdownMenuItem(value: 'pos', child: Text('POS', style: TextStyle(color: Colors.black87))),
                            DropdownMenuItem(value: 'admin', child: Text('Admin', style: TextStyle(color: Colors.black87))),
                          ],
                          onChanged: (value) {
                            setDialogState(() => selectedRole = value!);
                          },
                        ),
                      ],
                      const SizedBox(height: 24),
                      // Info box
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3498DB).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF3498DB).withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3498DB).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.info_outline, color: Color(0xFF5DADE2), size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'An invitation email will be sent with the GM Phoneshoppe branding.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ],
                    ),
                  ),
                ),
                // Actions
                Container(
                  padding: EdgeInsets.fromLTRB(isMobileDialog ? 16 : 24, 0, isMobileDialog ? 16 : 24, isMobileDialog ? 16 : 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: isSending ? null : () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: isSending
                              ? null
                              : () async {
                                  final email = emailController.text.trim();
                                  if (email.isEmpty || !email.contains('@')) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text('Please enter a valid email address'),
                                        backgroundColor: Colors.orange.shade700,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    );
                                    return;
                                  }

                                  // Check if POS role is already assigned (only 1 POS user allowed)
                                  if (selectedRole == 'pos') {
                                    final existingPOSUser = _users.any((u) => u['role'] == 'pos');
                                    final pendingPOSInvitation = _pendingInvitations.any((i) => i['role'] == 'pos');
                                    if (existingPOSUser || pendingPOSInvitation) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: const Text('Only one POS user is allowed. Please remove the existing POS user first.'),
                                          backgroundColor: Colors.orange.shade700,
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      );
                                      return;
                                    }
                                  }

                                  setDialogState(() => isSending = true);

                                  // Get current admin info
                                  final currentUser = await AuthService.getCurrentUser();

                                  // Create invitation in Firebase
                                  final token = await FirebaseDatabaseService.addUserInvitation(
                                    email: email,
                                    name: nameController.text.trim(),
                                    role: selectedRole,
                                    invitedByEmail: currentUser?['email'] ?? '',
                                    invitedByName: currentUser?['name'] ?? '',
                                  );

                                  if (token == null) {
                                    setDialogState(() => isSending = false);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text('User already exists or invitation already sent'),
                                        backgroundColor: Colors.orange.shade700,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    );
                                    return;
                                  }

                                  // Send invitation email
                                  final emailSent = await EmailService.sendInvitationEmail(
                                    recipientEmail: email,
                                    recipientName: nameController.text.trim(),
                                    invitedByName: currentUser?['name'] ?? 'Admin',
                                    invitedByEmail: currentUser?['email'] ?? '',
                                    invitationToken: token,
                                  );

                                  setDialogState(() => isSending = false);

                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        emailSent
                                            ? 'Invitation sent to $email!'
                                            : 'Invitation created! (Email service not configured)',
                                      ),
                                      backgroundColor: emailSent ? const Color(0xFF1ABC9C) : Colors.orange.shade700,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  );

                                  _loadData();
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1ABC9C),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: isSending
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.send, size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'Send Invitation',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
        },
      ),
    );
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete User', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete ${user['name'] ?? user['email']}?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B1A1A)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseDatabaseService.deleteUser(user['id']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User deleted'), backgroundColor: Colors.green),
      );
      _loadData();
    }
  }

  Future<void> _promoteUser(Map<String, dynamic> user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Promote to Admin', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to promote ${user['name'] ?? user['email']} to Admin?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1ABC9C)),
            child: const Text('Promote'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await FirebaseDatabaseService.updateUser(user['id'], {'role': 'admin'});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'User promoted to Admin' : 'Failed to promote user'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
      if (success) _loadData();
    }
  }

  Future<void> _demoteUser(Map<String, dynamic> user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Demote to User', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to demote ${user['name'] ?? user['email']} to regular User?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE67E22)),
            child: const Text('Demote'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await FirebaseDatabaseService.updateUser(user['id'], {'role': 'user'});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Admin demoted to User' : 'Failed to demote user'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
      if (success) _loadData();
    }
  }

  Future<void> _resetUserPin(Map<String, dynamic> user) async {
    final userName = user['name'] ?? '';
    final userEmail = user['email'] ?? '';
    final userId = user['id'] ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.pin, color: Color(0xFFE67E22)),
            SizedBox(width: 8),
            Text('Reset Staff PIN', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'This will generate a new random PIN for $userName and send it to $userEmail via email.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE67E22)),
            child: const Text('Reset & Send Email', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Check connectivity before resetting PIN
    final hasConnection = await CacheService.hasConnectivity();
    if (!hasConnection) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No internet connection. Cannot reset PIN offline.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show loading
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Resetting PIN...'), backgroundColor: Colors.blue),
    );

    final newPin = await StaffPinService.resetPin(
      userId: userId,
      email: userEmail,
      name: userName,
    );

    if (!mounted) return;

    if (newPin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to reset PIN'), backgroundColor: Colors.red),
      );
      return;
    }

    // Get current admin name for the email
    final currentUser = await AuthService.getCurrentUser();
    final adminName = currentUser?['name'] ?? 'Admin';

    final emailSent = await EmailService.sendPinResetEmail(
      recipientEmail: userEmail,
      recipientName: userName,
      newPin: newPin,
      resetByName: adminName,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          emailSent
              ? 'PIN reset successfully. New PIN sent to $userEmail'
              : 'PIN reset but failed to send email. New PIN: $newPin',
        ),
        backgroundColor: emailSent ? Colors.green : Colors.orange,
        duration: Duration(seconds: emailSent ? 3 : 8),
      ),
    );
  }

  Future<void> _deleteInvitation(Map<String, dynamic> invitation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Invitation', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to cancel the invitation for ${invitation['email']}?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('No', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B1A1A)),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseDatabaseService.deleteInvitation(invitation['id']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invitation cancelled'), backgroundColor: Colors.green),
      );
      _loadData();
    }
  }

  Future<void> _resendInvitation(Map<String, dynamic> invitation) async {
    final currentUser = await AuthService.getCurrentUser();

    final emailSent = await EmailService.sendInvitationEmail(
      recipientEmail: invitation['email'],
      recipientName: invitation['name'] ?? '',
      invitedByName: currentUser?['name'] ?? 'Admin',
      invitedByEmail: currentUser?['email'] ?? '',
      invitationToken: invitation['token'] ?? '',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          emailSent ? 'Invitation resent!' : 'Resend queued (Email service not configured)',
        ),
        backgroundColor: emailSent ? Colors.green : Colors.orange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A0A0A), Color(0xFF2A1A1A)],
        ),
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1ABC9C)))
          : SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'User Management',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isMobile ? 28 : 48,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (!isMobile)
                        ElevatedButton.icon(
                          onPressed: _showInviteUserDialog,
                          icon: const Icon(Icons.person_add),
                          label: const Text('Invite User'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            backgroundColor: const Color(0xFF1ABC9C),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                          ),
                        ),
                    ],
                  ),
                  if (isMobile) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _showInviteUserDialog,
                        icon: const Icon(Icons.person_add),
                        label: const Text('Invite User'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          backgroundColor: const Color(0xFF1ABC9C),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Stats Cards
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Total Users',
                          _users.length.toString(),
                          Icons.people,
                          const Color(0xFF1ABC9C),
                          isMobile,
                        ),
                      ),
                      SizedBox(width: isMobile ? 12 : 16),
                      Expanded(
                        child: _buildStatCard(
                          'Pending Invites',
                          _pendingInvitations.length.toString(),
                          Icons.mail_outline,
                          const Color(0xFFE67E22),
                          isMobile,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Tab Bar
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1ABC9C), Color(0xFF16A085)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1ABC9C).withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor: Colors.white,
                      labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: isMobile ? 13 : 15),
                      unselectedLabelColor: Colors.white.withValues(alpha: 0.5),
                      unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: isMobile ? 13 : 15),
                      tabs: [
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people, size: isMobile ? 16 : 18),
                              SizedBox(width: isMobile ? 4 : 8),
                              Text('Users (${_users.length})'),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.schedule, size: isMobile ? 16 : 18),
                              SizedBox(width: isMobile ? 4 : 8),
                              Text('Pending (${_pendingInvitations.length})'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Content
                  SizedBox(
                    height: 500,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildUsersTab(isMobile),
                        _buildPendingTab(isMobile),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(isMobile ? 16 : 24),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: isMobile ? 10 : 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: isMobile
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildUsersTab(bool isMobile) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          children: [
            // Search bar with better styling
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _filterUsers,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search users...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 16),
                  prefixIcon: Icon(Icons.search, color: Colors.white.withValues(alpha: 0.5)),
                  filled: false,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _filteredUsers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(Icons.people_outline, size: 48, color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _searchQuery.isEmpty ? 'No users yet' : 'No users found',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Invite users using the button above',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredUsers.length,
                      itemBuilder: (context, index) {
                        final user = _filteredUsers[index];
                        final isAdmin = user['role'] == 'admin';
                        final isPOS = user['role'] == 'pos';
                        final isSuperAdmin = AuthService.isSuperAdminEmail(user['email'] ?? '');
                        final userId = user['id'] as String?;
                        final isExpanded = _expandedUserId == userId;

                        // Get invited by info
                        final invitedByRaw = user['invitedBy'];
                        final invitedBy = invitedByRaw != null ? Map<String, dynamic>.from(invitedByRaw as Map) : null;

                        // Get joined date
                        final createdAt = user['createdAt'] as int?;
                        final joinedDateStr = createdAt != null
                            ? DateFormat('MMM dd, yyyy').format(DateTime.fromMillisecondsSinceEpoch(createdAt))
                            : '';

                        final hasExtraInfo = invitedBy != null || joinedDateStr.isNotEmpty;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                          ),
                          child: Column(
                            children: [
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                onTap: isMobile && hasExtraInfo
                                    ? () {
                                        setState(() {
                                          _expandedUserId = isExpanded ? null : userId;
                                        });
                                      }
                                    : null,
                                leading: Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: isAdmin
                                          ? [const Color(0xFF8B1A1A), const Color(0xFF5C0F0F)]
                                          : isPOS
                                              ? [const Color(0xFF9B59B6), const Color(0xFF8E44AD)]
                                              : [const Color(0xFF1ABC9C), const Color(0xFF16A085)],
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    isAdmin ? Icons.admin_panel_settings : isPOS ? Icons.point_of_sale : Icons.person,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        user['name'] ?? 'Unknown',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isSuperAdmin) ...[
                                      const SizedBox(width: 10),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [Color(0xFF8B1A1A), Color(0xFF5C0F0F)],
                                          ),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'Super Admin',
                                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ] else if (isAdmin) ...[
                                      const SizedBox(width: 10),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE67E22),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'Admin',
                                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ] else if (isPOS) ...[
                                      const SizedBox(width: 10),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF9B59B6),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'POS',
                                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user['email'] ?? '',
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
                                      ),
                                      // Show extra info inline on desktop, or hint to expand on mobile
                                      if (!isMobile && hasExtraInfo) ...[
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            if (invitedBy != null) ...[
                                              Icon(Icons.person_outline, size: 12, color: Colors.white.withValues(alpha: 0.4)),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  'Invited by ${invitedBy['name'] ?? invitedBy['email'] ?? 'Admin'}',
                                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                            if (invitedBy != null && joinedDateStr.isNotEmpty)
                                              const SizedBox(width: 12),
                                            if (joinedDateStr.isNotEmpty) ...[
                                              Icon(Icons.calendar_today_outlined, size: 12, color: Colors.white.withValues(alpha: 0.4)),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Joined $joinedDateStr',
                                                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                      // Show "tap to expand" hint on mobile
                                      if (isMobile && hasExtraInfo && !isExpanded) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(Icons.expand_more, size: 14, color: Colors.white.withValues(alpha: 0.3)),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Tap for details',
                                              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                trailing: isSuperAdmin
                                    ? (isMobile && hasExtraInfo
                                        ? Icon(
                                            isExpanded ? Icons.expand_less : Icons.expand_more,
                                            color: Colors.white.withValues(alpha: 0.5),
                                          )
                                        : null)
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Promote/Demote button - only visible to super admins
                                          if (_currentUserIsSuperAdmin && !isMobile) ...[
                                            Container(
                                              decoration: BoxDecoration(
                                                color: isAdmin
                                                    ? const Color(0xFFE67E22).withValues(alpha: 0.15)
                                                    : const Color(0xFF1ABC9C).withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: IconButton(
                                                icon: Icon(
                                                  isAdmin ? Icons.arrow_downward : Icons.arrow_upward,
                                                  size: 22,
                                                  color: isAdmin ? const Color(0xFFE67E22) : const Color(0xFF1ABC9C),
                                                ),
                                                tooltip: isAdmin ? 'Demote to User' : 'Promote to Admin',
                                                onPressed: () => isAdmin ? _demoteUser(user) : _promoteUser(user),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                          // Reset PIN button (desktop)
                                          if (!isMobile)
                                            Container(
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF9B59B6).withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: IconButton(
                                                icon: const Icon(Icons.pin, size: 22, color: Color(0xFF9B59B6)),
                                                tooltip: 'Reset PIN',
                                                onPressed: () => _resetUserPin(user),
                                              ),
                                            ),
                                          // Delete button - only visible to super admins (desktop)
                                          if (_currentUserIsSuperAdmin && !isMobile)
                                            Container(
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF8B1A1A).withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: IconButton(
                                                icon: const Icon(Icons.delete_outline, size: 22, color: Color(0xFFE57373)),
                                                tooltip: 'Delete User',
                                                onPressed: () => _deleteUser(user),
                                              ),
                                            ),
                                          // Expand icon for mobile
                                          if (isMobile && hasExtraInfo)
                                            Icon(
                                              isExpanded ? Icons.expand_less : Icons.expand_more,
                                              color: Colors.white.withValues(alpha: 0.5),
                                            ),
                                        ],
                                      ),
                              ),
                              // Expanded section for mobile
                              if (isMobile && isExpanded) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.03),
                                    borderRadius: const BorderRadius.only(
                                      bottomLeft: Radius.circular(16),
                                      bottomRight: Radius.circular(16),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
                                      const SizedBox(height: 12),
                                      // Invited by info
                                      if (invitedBy != null)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: Row(
                                            children: [
                                              Icon(Icons.person_outline, size: 16, color: Colors.white.withValues(alpha: 0.5)),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Invited by ${invitedBy['name'] ?? invitedBy['email'] ?? 'Admin'}',
                                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      // Joined date
                                      if (joinedDateStr.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: Row(
                                            children: [
                                              Icon(Icons.calendar_today_outlined, size: 16, color: Colors.white.withValues(alpha: 0.5)),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Joined $joinedDateStr',
                                                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                                              ),
                                            ],
                                          ),
                                        ),
                                      // Reset PIN button for mobile (any admin)
                                      if (!isSuperAdmin) ...[
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton.icon(
                                            onPressed: () => _resetUserPin(user),
                                            icon: const Icon(Icons.pin, size: 18),
                                            label: const Text('Reset PIN'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF8E44AD),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            ),
                                          ),
                                        ),
                                      ],
                                      // Action buttons for super admin on mobile
                                      if (_currentUserIsSuperAdmin && !isSuperAdmin) ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                onPressed: () => isAdmin ? _demoteUser(user) : _promoteUser(user),
                                                icon: Icon(
                                                  isAdmin ? Icons.arrow_downward : Icons.arrow_upward,
                                                  size: 18,
                                                ),
                                                label: Text(isAdmin ? 'Demote' : 'Promote'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: isAdmin ? const Color(0xFFE67E22) : const Color(0xFF1ABC9C),
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                onPressed: () => _deleteUser(user),
                                                icon: const Icon(Icons.delete_outline, size: 18),
                                                label: const Text('Delete'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF8B1A1A),
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingTab(bool isMobile) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: _pendingInvitations.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(Icons.mark_email_read_outlined, size: 48, color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No pending invitations',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Invite users using the button above',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: _pendingInvitations.length,
                itemBuilder: (context, index) {
                  final invitation = _pendingInvitations[index];
                  final invitedByRaw = invitation['invitedBy'];
                  final invitedBy = invitedByRaw != null ? Map<String, dynamic>.from(invitedByRaw as Map) : null;
                  final createdAt = invitation['createdAt'] as int?;
                  final dateStr = createdAt != null
                      ? DateFormat('MMM dd, yyyy').format(DateTime.fromMillisecondsSinceEpoch(createdAt))
                      : '';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE67E22).withValues(alpha: 0.2)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFE67E22), Color(0xFFD35400)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.hourglass_empty, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  invitation['name']?.isNotEmpty == true ? invitation['name'] : 'Pending User',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  invitation['email'] ?? '',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.person_outline, size: 14, color: Colors.white.withValues(alpha: 0.4)),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        'Invited by ${invitedBy?['name'] ?? 'Admin'}',
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Icon(Icons.calendar_today_outlined, size: 14, color: Colors.white.withValues(alpha: 0.4)),
                                    const SizedBox(width: 4),
                                    Text(
                                      dateStr,
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3498DB).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.send_outlined, size: 20, color: Color(0xFF5DADE2)),
                                  onPressed: () => _resendInvitation(invitation),
                                  tooltip: 'Resend',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B1A1A).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.close, size: 20, color: Color(0xFFE57373)),
                                  onPressed: () => _deleteInvitation(invitation),
                                  tooltip: 'Cancel',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// Reports Page
class _ReportsPage extends StatefulWidget {
  const _ReportsPage();

  @override
  State<_ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<_ReportsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Suggestions tab state
  List<Map<String, dynamic>> _allSuggestions = [];
  bool _isLoading = true;
  String _selectedService = 'all';
  String _selectedType = 'all';

  // Low Stock Alerts tab state
  List<Map<String, dynamic>> _lowStockItems = [];
  bool _isLoadingLowStock = true;

  // Suggestion counts per service
  Map<String, int> _suggestionCounts = {
    'cignal': 0,
    'satellite': 0,
    'gsat': 0,
    'sky': 0,
    'pos_requests': 0,
  };

  // User Performance tab state
  Map<String, Map<String, dynamic>> _userPerformanceData = {};
  bool _isLoadingPerformance = true;
  String _performanceFilter = 'all'; // 'all', 'today', 'month', 'date', 'custom_month'
  DateTime _selectedDate = DateTime.now();
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  final Map<String, String> _serviceNames = {
    'cignal': 'Cignal',
    'satellite': 'Satlite',
    'gsat': 'GSAT',
    'sky': 'Sky',
    'pos_requests': 'POS Requests',
  };

  // Service gradients
  static const _serviceGradients = {
    'cignal': [Color(0xFF8B1A1A), Color(0xFF5C0F0F)],
    'satellite': [Color(0xFFFF6B35), Color(0xFFCC5528)],
    'gsat': [Color(0xFF2ECC71), Color(0xFF27AE60)],
    'sky': [Color(0xFF3498DB), Color(0xFF2980B9)],
  };

  // Service logos
  static const _serviceLogos = {
    'cignal': 'Photos/CIGNAL.png',
    'satellite': 'Photos/SATLITE.png',
    'gsat': 'Photos/GSAT.png',
    'sky': 'Photos/SKY.png',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadSuggestions();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.index == 1 && _userPerformanceData.isEmpty) {
      _loadUserPerformance();
    }
    if (_tabController.index == 2 && _lowStockItems.isEmpty) {
      _loadLowStockItems();
    }
  }

  Future<void> _loadLowStockItems() async {
    setState(() => _isLoadingLowStock = true);
    try {
      final items = await InventoryService.getItemsBelowThreshold(threshold: 10);
      if (mounted) {
        setState(() {
          _lowStockItems = items;
          _isLoadingLowStock = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLowStock = false);
      }
    }
  }

  Future<void> _loadUserPerformance() async {
    setState(() => _isLoadingPerformance = true);
    try {
      Map<String, Map<String, dynamic>> data;

      switch (_performanceFilter) {
        case 'today':
          data = await FirebaseDatabaseService.getCustomerAdditionsForDate(DateTime.now());
          break;
        case 'month':
          final now = DateTime.now();
          data = await FirebaseDatabaseService.getCustomerAdditionsForMonth(now.year, now.month);
          break;
        case 'date':
          data = await FirebaseDatabaseService.getCustomerAdditionsForDate(_selectedDate);
          break;
        case 'custom_month':
          data = await FirebaseDatabaseService.getCustomerAdditionsForMonth(_selectedYear, _selectedMonth);
          break;
        default:
          data = await FirebaseDatabaseService.getCustomerAdditionsByUser();
      }

      if (mounted) {
        setState(() {
          _userPerformanceData = data;
          _isLoadingPerformance = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingPerformance = false);
      }
    }
  }

  Future<void> _loadSuggestions() async {
    setState(() => _isLoading = true);
    try {
      final services = [
        FirebaseDatabaseService.cignal,
        FirebaseDatabaseService.satellite,
        FirebaseDatabaseService.gsat,
        FirebaseDatabaseService.sky,
      ];

      List<Map<String, dynamic>> allSuggestions = [];
      Map<String, int> counts = {
        'cignal': 0,
        'satellite': 0,
        'gsat': 0,
        'sky': 0,
      };

      for (final service in services) {
        final suggestions = await FirebaseDatabaseService.getPendingSuggestions(service);
        counts[service] = suggestions.length;
        for (final suggestion in suggestions) {
          suggestion['serviceType'] = service;
          allSuggestions.add(suggestion);
        }
      }

      // Also load POS item requests
      final posRequests = await FirebaseDatabaseService.getPosItemRequests(status: 'pending');
      counts['pos_requests'] = posRequests.length;
      for (final req in posRequests) {
        req['serviceType'] = 'pos_requests';
        req['type'] = 'custom_item';
        allSuggestions.add(req);
      }

      // Sort by createdAt descending
      allSuggestions.sort((a, b) {
        final aTime = a['createdAt'] as int? ?? 0;
        final bTime = b['createdAt'] as int? ?? 0;
        return bTime.compareTo(aTime);
      });

      if (mounted) {
        setState(() {
          _allSuggestions = allSuggestions;
          _suggestionCounts = counts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> get _filteredSuggestions {
    return _allSuggestions.where((s) {
      if (_selectedService != 'all' && s['serviceType'] != _selectedService) {
        return false;
      }
      if (_selectedType != 'all' && s['type'] != _selectedType) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _approveSuggestion(Map<String, dynamic> suggestion) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Approve Suggestion?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to approve this ${suggestion['type']} request?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2ECC71)),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final currentUser = await AuthService.getCurrentUser();
      bool success;

      if (suggestion['serviceType'] == 'pos_requests') {
        success = await FirebaseDatabaseService.approvePosItemRequest(
          requestId: suggestion['id'],
          approvedByEmail: currentUser?['email'] ?? '',
          approvedByName: currentUser?['name'] ?? '',
        );
      } else {
        success = await FirebaseDatabaseService.approveSuggestion(
          serviceType: suggestion['serviceType'],
          suggestionId: suggestion['id'],
          suggestion: suggestion,
          approvedByEmail: currentUser?['email'] ?? '',
          approvedByName: currentUser?['name'] ?? '',
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Request approved!' : 'Failed to approve request'),
          backgroundColor: success ? const Color(0xFF2ECC71) : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );

      if (success) _loadSuggestions();
    }
  }

  Future<void> _rejectSuggestion(Map<String, dynamic> suggestion) async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reject Suggestion?', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to reject this ${suggestion['type']} request?',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 16),
            Text(
              'Rejection reason (optional)',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              maxLines: 2,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter reason for rejection...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE74C3C)),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final currentUser = await AuthService.getCurrentUser();
      bool success;

      if (suggestion['serviceType'] == 'pos_requests') {
        success = await FirebaseDatabaseService.rejectPosItemRequest(
          requestId: suggestion['id'],
          rejectedByEmail: currentUser?['email'] ?? '',
          rejectedByName: currentUser?['name'] ?? '',
          rejectionReason: reasonController.text.trim().isNotEmpty ? reasonController.text.trim() : null,
        );
      } else {
        success = await FirebaseDatabaseService.rejectSuggestion(
          serviceType: suggestion['serviceType'],
          suggestionId: suggestion['id'],
          rejectedByEmail: currentUser?['email'] ?? '',
          rejectedByName: currentUser?['name'] ?? '',
          rejectionReason: reasonController.text.trim().isNotEmpty ? reasonController.text.trim() : null,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Request rejected' : 'Failed to reject request'),
          backgroundColor: success ? const Color(0xFFE74C3C) : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );

      if (success) _loadSuggestions();
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'add':
        return 'Add';
      case 'edit':
        return 'Edit';
      case 'delete':
        return 'Delete';
      case 'custom_item':
        return 'Custom Item';
      default:
        return type;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'add':
        return const Color(0xFF2ECC71);
      case 'edit':
        return const Color(0xFF3498DB);
      case 'delete':
        return const Color(0xFFE74C3C);
      case 'custom_item':
        return const Color(0xFFE67E22);
      default:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'add':
        return Icons.add_circle_outline;
      case 'edit':
        return Icons.edit_outlined;
      case 'delete':
        return Icons.delete_outline;
      case 'custom_item':
        return Icons.shopping_cart_outlined;
      default:
        return Icons.help_outline;
    }
  }

  Widget _buildServiceSuggestionCard(String serviceKey, bool isMobile) {
    final count = _suggestionCounts[serviceKey] ?? 0;
    final name = _serviceNames[serviceKey] ?? serviceKey;
    final gradients = _serviceGradients[serviceKey] ?? [Colors.grey, Colors.grey];
    final logoPath = _serviceLogos[serviceKey] ?? '';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradients,
        ),
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
      ),
      child: Stack(
        children: [
          // Decorative rounded rectangle
          Positioned(
            top: isMobile ? -15 : -25,
            right: isMobile ? -15 : -25,
            child: Container(
              width: isMobile ? 50 : 80,
              height: isMobile ? 50 : 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(isMobile ? 12 : 20),
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
              onTap: () {
                setState(() {
                  _selectedService = serviceKey;
                });
              },
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 8 : 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo in top-left - bigger, no white background
                    Image.asset(
                      logoPath,
                      width: isMobile ? 32 : 48,
                      height: isMobile ? 32 : 48,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.image_not_supported,
                          size: isMobile ? 24 : 40,
                          color: Colors.white,
                        );
                      },
                    ),
                    const Spacer(),
                    // Count
                    Text(
                      '$count',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isMobile ? 16 : 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // Service name
                    Text(
                      name,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: isMobile ? 9 : 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF1A0A0A),
            const Color(0xFF2A1A1A),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: EdgeInsets.fromLTRB(
              isMobile ? 16 : 24,
              isMobile ? 16 : 24,
              isMobile ? 16 : 24,
              0,
            ),
            child: Text(
              'Reports & Analytics',
              style: TextStyle(
                color: Colors.white,
                fontSize: isMobile ? 28 : 48,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Tab Bar
          Container(
            margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B1A1A), Color(0xFF5C0F0F)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Suggestions'),
                Tab(text: 'Performance'),
                Tab(text: 'Low Stock'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSuggestionsTab(isMobile),
                _buildUserPerformanceTab(isMobile),
                _buildLowStockAlertsTab(isMobile),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsTab(bool isMobile) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Analytics Cards - Suggestion counts per service
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: isMobile ? 0.7 : 1.8,
            children: [
              _buildServiceSuggestionCard('cignal', isMobile),
              _buildServiceSuggestionCard('satellite', isMobile),
              _buildServiceSuggestionCard('gsat', isMobile),
              _buildServiceSuggestionCard('sky', isMobile),
            ],
          ),
          const SizedBox(height: 24),

          // Pending Suggestions Section
          Container(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              decoration: BoxDecoration(
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE67E22), Color(0xFFD35400)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.pending_actions, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Pending Suggestions',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_allSuggestions.length} pending review',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _loadSuggestions,
                        icon: Icon(Icons.refresh, color: Colors.white.withValues(alpha: 0.7)),
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Filters
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      // Service filter
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedService,
                            dropdownColor: const Color(0xFF2A1A1A),
                            style: const TextStyle(color: Colors.white),
                            icon: Icon(Icons.arrow_drop_down, color: Colors.white.withValues(alpha: 0.7)),
                            items: [
                              const DropdownMenuItem(value: 'all', child: Text('All Services')),
                              ...['cignal', 'satellite', 'gsat', 'sky', 'pos_requests'].map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(_serviceNames[s] ?? s),
                                  )),
                            ],
                            onChanged: (value) {
                              setState(() => _selectedService = value ?? 'all');
                            },
                          ),
                        ),
                      ),
                      // Type filter
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedType,
                            dropdownColor: const Color(0xFF2A1A1A),
                            style: const TextStyle(color: Colors.white),
                            icon: Icon(Icons.arrow_drop_down, color: Colors.white.withValues(alpha: 0.7)),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All Types')),
                              DropdownMenuItem(value: 'add', child: Text('Add')),
                              DropdownMenuItem(value: 'edit', child: Text('Edit')),
                              DropdownMenuItem(value: 'delete', child: Text('Delete')),
                              DropdownMenuItem(value: 'custom_item', child: Text('Custom Item')),
                            ],
                            onChanged: (value) {
                              setState(() => _selectedType = value ?? 'all');
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Suggestions list
                  if (_isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(color: Color(0xFFE67E22)),
                      ),
                    )
                  else if (_filteredSuggestions.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          children: [
                            Icon(Icons.check_circle_outline, size: 48, color: Colors.white.withValues(alpha: 0.3)),
                            const SizedBox(height: 16),
                            Text(
                              'No pending suggestions',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _filteredSuggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = _filteredSuggestions[index];
                        final type = suggestion['type'] as String? ?? 'unknown';
                        final serviceType = suggestion['serviceType'] as String? ?? '';
                        final customerData = suggestion['customerData'] as Map<dynamic, dynamic>?;
                        final submittedBy = suggestion['submittedBy'] as Map<dynamic, dynamic>?;
                        final reason = suggestion['reason'] as String?;
                        final createdAt = suggestion['createdAt'] as int?;
                        final dateStr = createdAt != null
                            ? DateFormat('MMM dd, yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(createdAt))
                            : '';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _getTypeColor(type).withValues(alpha: 0.3)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header row
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: _getTypeColor(type).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(_getTypeIcon(type), color: _getTypeColor(type), size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: _getTypeColor(type),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  _getTypeLabel(type),
                                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  _serviceNames[serviceType] ?? serviceType,
                                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            serviceType == 'pos_requests'
                                                ? suggestion['itemName'] ?? 'Unknown Item'
                                                : customerData?['name'] ?? 'Unknown Customer',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                // POS request details
                                if (serviceType == 'pos_requests') ...[
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 8,
                                    children: [
                                      _buildDetailChip('Quantity', '${suggestion['quantity'] ?? 1}'),
                                      _buildDetailChip('Est. Price', '₱${(suggestion['estimatedPrice'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
                                    ],
                                  ),
                                ],

                                // Customer details
                                if (customerData != null && serviceType != 'pos_requests') ...[
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 8,
                                    children: [
                                      if (customerData['serialNumber'] != null)
                                        _buildDetailChip('Serial', customerData['serialNumber'].toString()),
                                      if (customerData['boxId'] != null)
                                        _buildDetailChip('Box ID', customerData['boxId'].toString()),
                                      if (customerData['plan'] != null)
                                        _buildDetailChip('Plan', customerData['plan'].toString()),
                                      if (customerData['status'] != null)
                                        _buildDetailChip('Status', customerData['status'].toString()),
                                    ],
                                  ),
                                ],

                                // Reason for deletion
                                if (reason != null && reason.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE74C3C).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFE74C3C).withValues(alpha: 0.2)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Reason:',
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.7),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          reason,
                                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                // Submitted by info
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Icon(Icons.person_outline, size: 14, color: Colors.white.withValues(alpha: 0.4)),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Submitted by ${submittedBy?['name'] ?? submittedBy?['email'] ?? 'Unknown'}',
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Icon(Icons.access_time, size: 14, color: Colors.white.withValues(alpha: 0.4)),
                                    const SizedBox(width: 4),
                                    Text(
                                      dateStr,
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                                    ),
                                  ],
                                ),

                                // Action buttons
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => _approveSuggestion(suggestion),
                                        icon: const Icon(Icons.check, size: 18),
                                        label: const Text('Approve'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF2ECC71),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => _rejectSuggestion(suggestion),
                                        icon: const Icon(Icons.close, size: 18),
                                        label: const Text('Reject'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFFE74C3C),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildUserPerformanceTab(bool isMobile) {
    // Sort users by total (descending)
    final sortedUsers = _userPerformanceData.entries.toList()
      ..sort((a, b) => (b.value['total'] as int).compareTo(a.value['total'] as int));

    final totalCustomers = sortedUsers.fold<int>(0, (sum, e) => sum + (e.value['total'] as int));
    final activeUsers = sortedUsers.length;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFilterChip('All Time', 'all', isMobile),
              _buildFilterChip('Today', 'today', isMobile),
              _buildFilterChip('This Month', 'month', isMobile),
            ],
          ),
          const SizedBox(height: 12),

          // Date picker and Month selector
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Date picker
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.dark(
                            primary: Color(0xFF8B1A1A),
                            surface: Color(0xFF2A1A1A),
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedDate = picked;
                      _performanceFilter = 'date';
                    });
                    _loadUserPerformance();
                  }
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _performanceFilter == 'date'
                        ? const Color(0xFF8B1A1A).withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: _performanceFilter == 'date'
                        ? Border.all(color: const Color(0xFF8B1A1A))
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: Colors.white.withValues(alpha: 0.7)),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('MMM dd, yyyy').format(_selectedDate),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),

              // Month dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _performanceFilter == 'custom_month'
                      ? const Color(0xFF8B1A1A).withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: _performanceFilter == 'custom_month'
                      ? Border.all(color: const Color(0xFF8B1A1A))
                      : null,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedMonth,
                    dropdownColor: const Color(0xFF2A1A1A),
                    style: const TextStyle(color: Colors.white),
                    icon: Icon(Icons.arrow_drop_down, color: Colors.white.withValues(alpha: 0.7)),
                    items: List.generate(12, (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text(DateFormat('MMMM').format(DateTime(2024, i + 1))),
                    )),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedMonth = value;
                          _performanceFilter = 'custom_month';
                        });
                        _loadUserPerformance();
                      }
                    },
                  ),
                ),
              ),

              // Year dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _performanceFilter == 'custom_month'
                      ? const Color(0xFF8B1A1A).withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: _performanceFilter == 'custom_month'
                      ? Border.all(color: const Color(0xFF8B1A1A))
                      : null,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedYear,
                    dropdownColor: const Color(0xFF2A1A1A),
                    style: const TextStyle(color: Colors.white),
                    icon: Icon(Icons.arrow_drop_down, color: Colors.white.withValues(alpha: 0.7)),
                    items: List.generate(7, (i) => DropdownMenuItem(
                      value: DateTime.now().year - i,
                      child: Text('${DateTime.now().year - i}'),
                    )),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedYear = value;
                          _performanceFilter = 'custom_month';
                        });
                        _loadUserPerformance();
                      }
                    },
                  ),
                ),
              ),

              // Refresh button
              IconButton(
                onPressed: _loadUserPerformance,
                icon: Icon(Icons.refresh, color: Colors.white.withValues(alpha: 0.7)),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Summary stats
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF8B1A1A).withValues(alpha: 0.3),
                  const Color(0xFF5C0F0F).withValues(alpha: 0.3),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF8B1A1A).withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(
                      '$totalCustomers',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Customers Added',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                Column(
                  children: [
                    Text(
                      '$activeUsers',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Active Users',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // User Performance Cards
          if (_isLoadingPerformance)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: Color(0xFF8B1A1A)),
              ),
            )
          else if (sortedUsers.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(Icons.people_outline, size: 48, color: Colors.white.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    Text(
                      'No customer additions found',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try adjusting the date filter',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sortedUsers.length,
              itemBuilder: (context, index) {
                final entry = sortedUsers[index];
                final email = entry.key;
                final data = entry.value;
                final name = data['name'] as String? ?? '';
                final total = data['total'] as int;
                final services = data['services'] as Map<String, int>;
                final lastAddition = data['lastAddition'] as int?;
                final lastAdditionStr = lastAddition != null
                    ? DateFormat('MMM dd, yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(lastAddition))
                    : 'N/A';

                // Get initials for avatar
                final initials = name.isNotEmpty
                    ? name.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase()
                    : email.isNotEmpty ? email[0].toUpperCase() : '?';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252525),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // User info row
                        Row(
                          children: [
                            // Avatar
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF8B1A1A), Color(0xFF5C0F0F)],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  initials,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Name and email
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name.isNotEmpty ? name : email,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (name.isNotEmpty)
                                    Text(
                                      email,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.5),
                                        fontSize: 13,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Total badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '$total',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Service breakdown
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildServiceCountChip('Cignal', services['cignal'] ?? 0, const Color(0xFF8B1A1A)),
                            _buildServiceCountChip('Satlite', services['satellite'] ?? 0, const Color(0xFFFF6B35)),
                            _buildServiceCountChip('GSAT', services['gsat'] ?? 0, const Color(0xFF2ECC71)),
                            _buildServiceCountChip('Sky', services['sky'] ?? 0, const Color(0xFF3498DB)),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Last addition
                        Row(
                          children: [
                            Icon(Icons.access_time, size: 14, color: Colors.white.withValues(alpha: 0.4)),
                            const SizedBox(width: 6),
                            Text(
                              'Last: $lastAdditionStr',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String filterValue, bool isMobile) {
    final isSelected = _performanceFilter == filterValue;
    return InkWell(
      onTap: () {
        setState(() => _performanceFilter = filterValue);
        _loadUserPerformance();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 14 : 18,
          vertical: isMobile ? 8 : 10,
        ),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(colors: [Color(0xFF8B1A1A), Color(0xFF5C0F0F)])
              : null,
          color: isSelected ? null : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: isSelected ? 1.0 : 0.7),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: isMobile ? 13 : 14,
          ),
        ),
      ),
    );
  }

  Widget _buildServiceCountChip(String service, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$service: ',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
          ),
          Text(
            '$count',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildLowStockAlertsTab(bool isMobile) {
    final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final outOfStockItems = _lowStockItems.where((item) => (item['quantity'] as int? ?? 0) == 0).toList();
    final lowStockItems = _lowStockItems.where((item) => (item['quantity'] as int? ?? 0) > 0).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary stats
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.red.withValues(alpha: 0.3),
                        Colors.red.withValues(alpha: 0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: isMobile ? 28 : 36),
                      const SizedBox(height: 8),
                      Text(
                        '${outOfStockItems.length}',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: isMobile ? 24 : 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Out of Stock',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: isMobile ? 12 : 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.orange.withValues(alpha: 0.3),
                        Colors.orange.withValues(alpha: 0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange, size: isMobile ? 28 : 36),
                      const SizedBox(height: 8),
                      Text(
                        '${lowStockItems.length}',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: isMobile ? 24 : 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Low Stock (<10)',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: isMobile ? 12 : 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Refresh button
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _lowStockItems = [];
                  });
                  _loadLowStockItems();
                },
                icon: Icon(Icons.refresh, color: Colors.white.withValues(alpha: 0.7)),
                label: Text('Refresh', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Low Stock Items List
          if (_isLoadingLowStock)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: Color(0xFFE67E22)),
              ),
            )
          else if (_lowStockItems.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline, size: 64, color: Colors.green.withValues(alpha: 0.5)),
                    const SizedBox(height: 16),
                    Text(
                      'All items are well stocked!',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No items below 10 pieces',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              padding: EdgeInsets.all(isMobile ? 12 : 20),
              decoration: BoxDecoration(
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE67E22), Color(0xFFD35400)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.inventory_2, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Low Stock Alerts',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_lowStockItems.length} items need attention',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _lowStockItems.length,
                    itemBuilder: (context, index) {
                      final item = _lowStockItems[index];
                      final quantity = item['quantity'] as int? ?? 0;
                      final name = item['name'] as String? ?? 'Unknown Item';
                      final serialNo = item['serialNo'] as String? ?? '-';
                      final price = (item['sellingPrice'] as num?)?.toDouble() ?? 0;
                      final category = InventoryService.categoryLabels[item['category']] ?? item['category'] ?? '';
                      final isOutOfStock = quantity == 0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: EdgeInsets.all(isMobile ? 12 : 16),
                        decoration: BoxDecoration(
                          color: isOutOfStock
                              ? Colors.red.withValues(alpha: 0.1)
                              : Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isOutOfStock
                                ? Colors.red.withValues(alpha: 0.3)
                                : Colors.orange.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Item number
                            Container(
                              width: isMobile ? 36 : 44,
                              height: isMobile ? 36 : 44,
                              decoration: BoxDecoration(
                                color: isOutOfStock
                                    ? Colors.red.withValues(alpha: 0.2)
                                    : Colors.orange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  '#${index + 1}',
                                  style: TextStyle(
                                    color: isOutOfStock ? Colors.red : Colors.orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: isMobile ? 12 : 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Item details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: isMobile ? 14 : 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      Text(
                                        'Serial No.: $serialNo',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.5),
                                          fontSize: isMobile ? 11 : 12,
                                        ),
                                      ),
                                      Text(
                                        '• $category',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.5),
                                          fontSize: isMobile ? 11 : 12,
                                        ),
                                      ),
                                      Text(
                                        '• ${currencyFormat.format(price)}',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.5),
                                          fontSize: isMobile ? 11 : 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Quantity badge
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isMobile ? 10 : 14,
                                vertical: isMobile ? 6 : 8,
                              ),
                              decoration: BoxDecoration(
                                color: isOutOfStock ? Colors.red : Colors.orange,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '$quantity',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: isMobile ? 14 : 16,
                                    ),
                                  ),
                                  Text(
                                    'pcs',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.8),
                                      fontSize: isMobile ? 9 : 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDetailChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
          ),
          Text(
            value,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final List<Color> gradientColors;
  final bool isMobile;
  final bool isCompact;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.gradientColors,
    required this.isMobile,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = isCompact ? 12.0 : (isMobile ? 24.0 : 40.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Rounded rectangle decorative element - hide in compact mode
            if (!isCompact)
              Positioned(
                top: isMobile ? -20 : -30,
                right: isMobile ? -20 : -30,
                child: Container(
                  width: isMobile ? 80 : 120,
                  height: isMobile ? 80 : 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(isMobile ? 20 : 30),
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(isCompact ? 8 : (isMobile ? 10 : 16)),
                child: isCompact
                    ? Row(
                        children: [
                          Icon(icon, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  value,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  title,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 8,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, color: Colors.white, size: isMobile ? 20 : 32),
                          const Spacer(),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              value,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isMobile ? 18 : 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          SizedBox(height: isMobile ? 2 : 4),
                          Text(
                            title,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: isMobile ? 9 : 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceOverviewCard extends StatelessWidget {
  final String logoPath;
  final String customers;
  final String? cebuBoxes;
  final String? masbateBoxes;
  final List<Color> gradientColors;
  final Animation<double> scaleAnimation;
  final VoidCallback onTouchStart;
  final VoidCallback onTouchEnd;
  final VoidCallback onTap;
  final bool isMobile;
  final bool isLoading;
  final bool showLocationCounts;

  const _ServiceOverviewCard({
    required this.logoPath,
    required this.customers,
    this.cebuBoxes,
    this.masbateBoxes,
    required this.gradientColors,
    required this.scaleAnimation,
    required this.onTouchStart,
    required this.onTouchEnd,
    required this.onTap,
    required this.isMobile,
    this.isLoading = false,
    this.showLocationCounts = true,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = isMobile ? 24.0 : 40.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Rounded rectangle decorative element instead of circle
            Positioned(
              bottom: isMobile ? -20 : -40,
              left: isMobile ? -20 : -40,
              child: Container(
                width: isMobile ? 80 : 140,
                height: isMobile ? 80 : 140,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(isMobile ? 20 : 35),
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 8 : 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTapDown: (_) => onTouchStart(),
                        onTapUp: (_) {
                          onTouchEnd();
                          onTap();
                        },
                        onTapCancel: () => onTouchEnd(),
                        child: AnimatedBuilder(
                          animation: scaleAnimation,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: scaleAnimation.value,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final size = constraints.maxWidth * 0.8;
                                  return Image.asset(
                                    logoPath,
                                    width: size,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(
                                        Icons.image_not_supported,
                                        size: size * 0.5,
                                        color: Colors.white,
                                      );
                                    },
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$customers users',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isMobile ? 11 : 14,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (showLocationCounts && (cebuBoxes != null || masbateBoxes != null)) ...[
                      const SizedBox(height: 2),
                      if (cebuBoxes != null)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Cebu: $cebuBoxes boxes',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: isMobile ? 9 : 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (masbateBoxes != null)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Masbate: $masbateBoxes boxes',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: isMobile ? 9 : 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

