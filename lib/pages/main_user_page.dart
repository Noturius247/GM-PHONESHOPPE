import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'cignal_page.dart';
import 'satlite_page.dart';
import 'gsat_page.dart';
import 'gsat_activation_page.dart';
import 'sky_page.dart';
import 'inventory_page.dart';
import 'transaction_history_page.dart';
import 'landing_page.dart';
import 'settings_page.dart';
import 'label_printing_page.dart';
import 'pos_page.dart';
import '../services/auth_service.dart';
import '../services/firebase_database_service.dart';
import '../services/inventory_service.dart';
import '../services/sync_service.dart';
import '../services/cache_service.dart';
import '../services/notification_service.dart';

class MainUserPage extends StatefulWidget {
  final String userName;

  const MainUserPage({super.key, required this.userName});

  @override
  State<MainUserPage> createState() => _MainUserPageState();
}

class _MainUserPageState extends State<MainUserPage> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _userFirstName = 'User';
  String _userEmail = '';
  bool _isPosAccount = false;

  // Low stock notification state
  List<Map<String, dynamic>> _lowStockItems = [];

  // Pre-built pages kept alive via IndexedStack
  late final List<Widget> _pages;

  // Service color themes matching admin page
  static const dashboardGradient = [Color(0xFF8B1A1A), Color(0xFF5C0F0F)];
  static const cignalGradient = [Color(0xFF8B1A1A), Color(0xFF5C0F0F)];
  static const satliteGradient = [Color(0xFFFF6B35), Color(0xFFCC5528)];
  static const gsatGradient = [Color(0xFF2ECC71), Color(0xFF27AE60)];
  static const skyGradient = [Color(0xFF3498DB), Color(0xFF2980B9)];
  static const inventoryGradient = [Color(0xFFE67E22), Color(0xFFD35400)];
  static const profileGradient = [Color(0xFF9B59B6), Color(0xFF8E44AD)];
  static const posGradient = [Color(0xFF1ABC9C), Color(0xFF16A085)];

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
      gradientColors: [Color(0xFFE67E22), Color(0xFFD35400)],
    ),
    _MenuItem(
      icon: Icons.qr_code_2,
      title: 'Label Printing',
      gradientColors: [Color(0xFFE67E22), Color(0xFFD35400)],
    ),
    _MenuItem(
      icon: Icons.settings,
      title: 'Settings',
      gradientColors: [Color(0xFFE67E22), Color(0xFFD35400)],
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
    _loadUserInfo();
    _loadLowStockItems();

    // Listen for real-time stock alerts from other devices
    NotificationService.onNewAlert = _onStockAlert;

    _pages = [
      _DashboardPage(
        userName: _userFirstName,
        onNavigateToService: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
      const CignalPage(),
      const SatlitePage(),
      const GSatPage(),
      const GsatActivationPage(),
      const SkyPage(),
      const InventoryPage(),
      const TransactionHistoryPage(),
      const LabelPrintingPage(),
      const SettingsPage(),
      _ProfilePage(userName: widget.userName, email: _userEmail),
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
    super.dispose();
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
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
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
                    const Text(
                      'Stock Alerts',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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

  Future<void> _loadUserInfo() async {
    final user = await AuthService.getCurrentUser();
    if (user != null && mounted) {
      final fullName = user['name'] as String? ?? widget.userName;
      final firstName = fullName.split(' ').first;
      final isPOS = user['role'] == 'pos';
      setState(() {
        _userFirstName = firstName;
        _userEmail = user['email'] as String? ?? '';
        if (isPOS && !_isPosAccount) {
          _isPosAccount = true;
          // Append POS menu item and page at the end
          _menuItems.add(_MenuItem(
            icon: Icons.point_of_sale,
            title: 'POS',
            gradientColors: posGradient,
          ));
          _pages.add(const POSPage());
        }
        _rebuildDynamicPages();
      });
    } else {
      setState(() {
        _userFirstName = widget.userName.split(' ').first;
        _rebuildDynamicPages();
      });
    }
  }

  /// Index of the Profile page (always 10 for non-POS, stays at 10 for POS since POS is appended after)
  int get _profileIndex => 10;

  /// Index of the POS page (appended after Profile, only exists for POS accounts)
  int get _posIndex => _isPosAccount ? _menuItems.length - 1 : -1;

  /// Rebuild only the pages that depend on dynamic user data.
  void _rebuildDynamicPages() {
    _pages[0] = _DashboardPage(
      userName: _userFirstName,
      onNavigateToService: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
    );
    _pages[_profileIndex] = _ProfilePage(userName: widget.userName, email: _userEmail);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF1A0A0A),
      drawer: isMobile ? _buildMobileDrawer(context) : null,
      appBar: _buildAppBar(context, isMobile),
      body: Row(
        children: [
          if (!isMobile) _buildSidebar(),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _pages,
            ),
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
                isMobile ? 'GM PhoneShoppe' : 'GM PhoneShoppe - User Portal',
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
        if (!isMobile)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                'Welcome, $_userFirstName',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                ),
              ),
            ),
          ),
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined, color: Colors.white),
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
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF2D1515),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text('Sign Out', style: TextStyle(color: Colors.white)),
                content: const Text(
                  'Are you sure you want to sign out of your account?',
                  style: TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final navigator = Navigator.of(ctx);
                      navigator.pop();
                      await AuthService.logout();
                      navigator.pushAndRemoveUntil(
                        MaterialPageRoute(builder: (context) => const LandingPage()),
                        (route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9B59B6)),
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

  Widget _buildMobileDrawer(BuildContext context) {
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
                        colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        _userFirstName.isNotEmpty ? _userFirstName[0].toUpperCase() : 'U',
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
                            color: const Color(0xFF2ECC71).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF2ECC71),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Text(
                                'User',
                                style: TextStyle(
                                  color: Color(0xFF2ECC71),
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
                  if (_isPosAccount) ...[
                    _buildDrawerSectionLabel('POS'),
                    _buildDrawerItem(_posIndex, context),
                  ],
                  _buildDrawerSectionLabel('Services'),
                  for (final i in [0, 1, 2, 3, 4, 5]) _buildDrawerItem(i, context),
                  _buildDrawerSectionLabel('Management'),
                  for (final i in [6, 7, 8]) _buildDrawerItem(i, context),
                  _buildDrawerSectionLabel('Account'),
                  for (final i in [9, 10]) _buildDrawerItem(i, context),
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

  Widget _buildSidebar() {
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
                      colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      _userFirstName.isNotEmpty ? _userFirstName[0].toUpperCase() : 'U',
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
                          color: const Color(0xFF2ECC71).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: Color(0xFF2ECC71),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'User',
                              style: TextStyle(
                                color: Color(0xFF2ECC71),
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
                if (_isPosAccount) ...[
                  _buildSectionLabel('POS'),
                  _buildSidebarItem(_posIndex),
                ],
                _buildSectionLabel('Services'),
                for (final i in [0, 1, 2, 3, 4, 5]) _buildSidebarItem(i),
                _buildSectionLabel('Management'),
                for (final i in [6, 7, 8]) _buildSidebarItem(i),
                _buildSectionLabel('Account'),
                for (final i in [9, 10]) _buildSidebarItem(i),
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

  Widget _buildBottomNav() {
    // Show Dashboard, Cignal, Satlite, GSAT, Sky (skip GSAT Activation at index 4)
    final bottomNavIndices = [0, 1, 2, 3, 5];
    final bottomNavItems = bottomNavIndices.map((i) => _menuItems[i]).toList();
    final currentIndex = bottomNavIndices.indexOf(_selectedIndex);

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
            children: List.generate(bottomNavItems.length, (index) {
              final item = bottomNavItems[index];
              final isSelected = currentIndex == index;
              final gradColor = item.gradientColors.first;

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedIndex = bottomNavIndices[index];
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

// Dashboard Page
class _DashboardPage extends StatefulWidget {
  final String userName;
  final Function(int) onNavigateToService;

  const _DashboardPage({
    required this.userName,
    required this.onNavigateToService,
  });

  @override
  State<_DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<_DashboardPage> {
  bool _isLoading = true;
  int _totalCustomers = 0;
  int _thisMonthCustomers = 0;
  final int _activeServices = 4; // Cignal, Satlite, GSAT, Sky

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

    // Trigger full sync in background only if we refreshed any service
    if (refreshedCount > 0) {
      SyncService.forceFullSync();
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

  Future<void> _loadDashboardData() async {
    try {
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

      for (final service in services) {
        final customers = await FirebaseDatabaseService.getCustomers(service);
        serviceCounts[service] = customers.length;
        totalCount += customers.length;

        int cebuCount = 0;
        int masbateCount = 0;

        for (final customer in customers) {
          // Count customers added this month
          final createdAt = customer['createdAt'] as int?;
          if (createdAt != null && createdAt >= startOfMonth) {
            thisMonthCount++;
          }

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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final isCompact = isMobile && isLandscape; // Compact mode for mobile landscape

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A0A0A),
            Color(0xFF2D1515),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome section - minimal in landscape
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
                    'Welcome, ${widget.userName}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isMobile ? 32 : 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Browse our available services',
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
                  // In landscape, show welcome inline with Quick Stats
                  if (isCompact)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Welcome, ${widget.userName}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          'Quick Stats',
                          style: const TextStyle(
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
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isSlimPhone = constraints.maxWidth < 340;
                      final cardAspectRatio = isCompact
                          ? 2.5
                          : (isSlimPhone ? 0.85 : (isMobile ? 1.0 : 1.8));
                      final spacing = isCompact ? 6.0 : (isSlimPhone ? 8.0 : 16.0);

                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 3,
                        mainAxisSpacing: spacing,
                        crossAxisSpacing: spacing,
                        childAspectRatio: cardAspectRatio,
                        children: [
                          _UserStatCard(
                            title: 'Customers',
                            value: _isLoading ? '...' : _getFilteredTotalCustomers().toString(),
                            icon: Icons.people,
                            gradientColors: const [Color(0xFF1ABC9C), Color(0xFF16A085)],
                            isMobile: isMobile,
                            isCompact: isCompact,
                            isSlimPhone: isSlimPhone,
                          ),
                          _UserStatCard(
                            title: 'Active',
                            value: _activeServices.toString(),
                            icon: Icons.check_circle,
                            gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)],
                            isMobile: isMobile,
                            isCompact: isCompact,
                            isSlimPhone: isSlimPhone,
                          ),
                          _UserStatCard(
                            title: 'This Month',
                            value: _isLoading ? '...' : _thisMonthCustomers.toString(),
                            icon: Icons.trending_up,
                            gradientColors: const [Color(0xFFFF6B35), Color(0xFFCC5528)],
                            isMobile: isMobile,
                            isCompact: isCompact,
                            isSlimPhone: isSlimPhone,
                          ),
                        ],
                      );
                    },
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
                  // Service cards grid with dynamic data
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: isCompact ? 4 : (isMobile ? 2 : 4),
                    mainAxisSpacing: isCompact ? 6 : 16,
                    crossAxisSpacing: isCompact ? 6 : 16,
                    childAspectRatio: isCompact ? 1.5 : (isMobile ? 1.0 : 1.2),
                    children: [
                      _ServiceCard(
                        icon: Icons.tv,
                        title: 'Cignal',
                        description: _isLoading
                            ? 'Loading...'
                            : '${_getFilteredServiceCount('cignal')} customers',
                        gradientColors: const [Color(0xFF8B1A1A), Color(0xFF5C0F0F)],
                        logoPath: 'Photos/CIGNAL.png',
                        onTap: () => widget.onNavigateToService(1),
                        cebuCount: _serviceLocationCounts['cignal']?['cebu'],
                        masbateCount: _serviceLocationCounts['cignal']?['masbate'],
                        isLoading: _isLoading,
                        showLocationCounts: _selectedLocation == 'All Locations',
                      ),
                      _ServiceCard(
                        icon: Icons.satellite_alt,
                        title: 'Satlite',
                        description: _isLoading
                            ? 'Loading...'
                            : '${_getFilteredServiceCount('satellite')} customers',
                        gradientColors: const [Color(0xFFFF6B35), Color(0xFFCC5528)],
                        logoPath: 'Photos/SATLITE.png',
                        onTap: () => widget.onNavigateToService(2),
                        cebuCount: _serviceLocationCounts['satellite']?['cebu'],
                        masbateCount: _serviceLocationCounts['satellite']?['masbate'],
                        isLoading: _isLoading,
                        showLocationCounts: _selectedLocation == 'All Locations',
                      ),
                      _ServiceCard(
                        icon: Icons.public,
                        title: 'GSAT',
                        description: _isLoading
                            ? 'Loading...'
                            : '${_getFilteredServiceCount('gsat')} customers',
                        gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)],
                        logoPath: 'Photos/GSAT.png',
                        onTap: () => widget.onNavigateToService(3),
                        cebuCount: _serviceLocationCounts['gsat']?['cebu'],
                        masbateCount: _serviceLocationCounts['gsat']?['masbate'],
                        isLoading: _isLoading,
                        showLocationCounts: _selectedLocation == 'All Locations',
                      ),
                      _ServiceCard(
                        icon: Icons.cloud,
                        title: 'Sky',
                        description: _isLoading
                            ? 'Loading...'
                            : '${_getFilteredServiceCount('sky')} customers',
                        gradientColors: const [Color(0xFF3498DB), Color(0xFF2980B9)],
                        logoPath: 'Photos/SKY.png',
                        onTap: () => widget.onNavigateToService(5),
                        cebuCount: _serviceLocationCounts['sky']?['cebu'],
                        masbateCount: _serviceLocationCounts['sky']?['masbate'],
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

// Profile Page
class _ProfilePage extends StatefulWidget {
  final String userName;
  final String email;

  const _ProfilePage({required this.userName, required this.email});

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  User? _firebaseUser;
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _dbUserData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);

    try {
      _firebaseUser = AuthService.getFirebaseUser();
      _userData = await AuthService.getCurrentUser();

      if (_userData != null && _userData!['email'] != null) {
        _dbUserData = await FirebaseDatabaseService.getUserByEmail(_userData!['email']);
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return 'N/A';
    return DateFormat('MMM dd, yyyy \'at\' hh:mm a').format(dateTime);
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      if (timestamp is int) {
        return _formatDateTime(DateTime.fromMillisecondsSinceEpoch(timestamp));
      }
      return timestamp.toString();
    } catch (e) {
      return 'N/A';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A0A0A),
            Color(0xFF2D1515),
            Color(0xFF1A0A0A),
          ],
        ),
      ),
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF9B59B6),
              ),
            )
          : SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    children: [
                      _buildProfileHeader(isMobile),
                      const SizedBox(height: 24),
                      _buildAccountInfoCard(isMobile),
                      const SizedBox(height: 16),
                      _buildGoogleAccountCard(isMobile),
                      if (_dbUserData != null) ...[
                        const SizedBox(height: 16),
                        _buildDatabaseInfoCard(isMobile),
                      ],
                      const SizedBox(height: 24),
                      _buildActionButtons(isMobile),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildProfileHeader(bool isMobile) {
    final photoUrl = _firebaseUser?.photoURL;
    final displayName = _firebaseUser?.displayName ?? _userData?['name'] ?? widget.userName;
    final email = _firebaseUser?.email ?? _userData?['email'] ?? widget.email;

    return Container(
      padding: EdgeInsets.all(isMobile ? 24 : 32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF9B59B6), Color(0xFF8E44AD)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9B59B6).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: isMobile ? 50 : 60,
              backgroundColor: Colors.white,
              backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
              child: photoUrl == null
                  ? Icon(
                      Icons.person,
                      size: isMobile ? 50 : 60,
                      color: const Color(0xFF9B59B6),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            displayName,
            style: TextStyle(
              color: Colors.white,
              fontSize: isMobile ? 22 : 26,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            email,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: isMobile ? 14 : 16,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white, width: 1),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_outline, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  'User',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountInfoCard(bool isMobile) {
    return _buildInfoCard(
      title: 'Account Information',
      icon: Icons.account_circle,
      color: const Color(0xFF9B59B6),
      isMobile: isMobile,
      children: [
        _buildInfoRowItem('User ID', _firebaseUser?.uid ?? 'N/A', Icons.fingerprint, isMobile),
        _buildDivider(),
        _buildInfoRowItem(
          'Email Verified',
          _firebaseUser?.emailVerified == true ? 'Yes' : 'No',
          _firebaseUser?.emailVerified == true ? Icons.verified : Icons.warning,
          isMobile,
          valueColor: _firebaseUser?.emailVerified == true ? Colors.green : Colors.orange,
        ),
        _buildDivider(),
        _buildInfoRowItem(
          'Account Created',
          _formatDateTime(_firebaseUser?.metadata.creationTime),
          Icons.calendar_today,
          isMobile,
        ),
        _buildDivider(),
        _buildInfoRowItem(
          'Last Sign In',
          _formatDateTime(_firebaseUser?.metadata.lastSignInTime),
          Icons.access_time,
          isMobile,
        ),
      ],
    );
  }

  Widget _buildGoogleAccountCard(bool isMobile) {
    return _buildInfoCard(
      title: 'Google Account',
      icon: Icons.g_mobiledata,
      color: const Color(0xFF9B59B6),
      isMobile: isMobile,
      children: [
        _buildInfoRowItem('Display Name', _firebaseUser?.displayName ?? 'N/A', Icons.person, isMobile),
        _buildDivider(),
        _buildInfoRowItem('Email', _firebaseUser?.email ?? 'N/A', Icons.email, isMobile),
        _buildDivider(),
        _buildInfoRowItem('Phone Number', _firebaseUser?.phoneNumber ?? 'Not linked', Icons.phone, isMobile),
        _buildDivider(),
        _buildInfoRowItem(
          'Photo URL',
          _firebaseUser?.photoURL != null ? 'Available' : 'Not set',
          Icons.photo,
          isMobile,
          valueColor: _firebaseUser?.photoURL != null ? Colors.green : null,
        ),
        _buildDivider(),
        _buildInfoRowItem(
          'Provider',
          _firebaseUser?.providerData.isNotEmpty == true
              ? _firebaseUser!.providerData.first.providerId
              : 'N/A',
          Icons.security,
          isMobile,
        ),
      ],
    );
  }

  Widget _buildDatabaseInfoCard(bool isMobile) {
    final addedBy = _dbUserData?['addedBy'] as Map<dynamic, dynamic>?;
    final createdAt = _dbUserData?['createdAt'];
    final lastLogin = _dbUserData?['lastLogin'];

    return _buildInfoCard(
      title: 'Database Record',
      icon: Icons.storage,
      color: const Color(0xFF9B59B6),
      isMobile: isMobile,
      children: [
        _buildInfoRowItem(
          'Status',
          _dbUserData?['status']?.toString().toUpperCase() ?? 'N/A',
          Icons.check_circle,
          isMobile,
          valueColor: _dbUserData?['status'] == 'active' ? Colors.green : null,
        ),
        _buildDivider(),
        _buildInfoRowItem(
          'Role in Database',
          _dbUserData?['role']?.toString().toUpperCase() ?? 'N/A',
          Icons.badge,
          isMobile,
        ),
        if (addedBy != null) ...[
          _buildDivider(),
          _buildInfoRowItem(
            'Added By',
            addedBy['name']?.toString() ?? addedBy['email']?.toString() ?? 'N/A',
            Icons.person_add,
            isMobile,
          ),
        ],
        if (createdAt != null) ...[
          _buildDivider(),
          _buildInfoRowItem('Record Created', _formatTimestamp(createdAt), Icons.create, isMobile),
        ],
        if (lastLogin != null) ...[
          _buildDivider(),
          _buildInfoRowItem('Last Login (DB)', _formatTimestamp(lastLogin), Icons.login, isMobile),
        ],
      ],
    );
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required Color color,
    required bool isMobile,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.7)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
          Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 20),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRowItem(String label, String value, IconData icon, bool isMobile, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.6), size: 20),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: isMobile ? 13 : 14),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: isMobile ? 13 : 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(color: Colors.white.withValues(alpha: 0.1), height: 1);
  }

  Widget _buildActionButtons(bool isMobile) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
            icon: const Icon(Icons.settings),
            label: const Text('Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE67E22),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _loadUserData,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Profile'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _showSignOutDialog(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9B59B6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D1515),
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9B59B6)),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}


class _ServiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final List<Color> gradientColors;
  final VoidCallback onTap;
  final String? logoPath;
  final int? cebuCount;
  final int? masbateCount;
  final bool isLoading;
  final bool showLocationCounts;

  const _ServiceCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.gradientColors,
    required this.onTap,
    this.logoPath,
    this.cebuCount,
    this.masbateCount,
    this.isLoading = false,
    this.showLocationCounts = true,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;
    final borderRadius = isMobile ? 24.0 : 40.0;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
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
              // Decorative rounded rectangle element
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
              // Main content
              Center(
                child: Padding(
                  padding: EdgeInsets.all(isMobile ? 12 : 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final size = constraints.maxWidth * 0.7;
                            return logoPath != null
                                ? Image.asset(
                                    logoPath!,
                                    width: size,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(icon, size: size * 0.5, color: Colors.white);
                                    },
                                  )
                                : Icon(icon, size: size * 0.5, color: Colors.white);
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: isMobile ? 14 : 18,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: isMobile ? 11 : 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      // Show Cebu and Masbate counts if available and showLocationCounts is true
                      if (showLocationCounts && !isLoading && (cebuCount != null || masbateCount != null)) ...[
                        const SizedBox(height: 4),
                        if (cebuCount != null)
                          Text(
                            'Cebu: $cebuCount',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: isMobile ? 9 : 11,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        if (masbateCount != null)
                          Text(
                            'Masbate: $masbateCount',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: isMobile ? 9 : 11,
                            ),
                            textAlign: TextAlign.center,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// User Stat Card for dashboard overview
class _UserStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final List<Color> gradientColors;
  final bool isMobile;
  final bool isCompact;
  final bool isSlimPhone;

  const _UserStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.gradientColors,
    required this.isMobile,
    this.isCompact = false,
    this.isSlimPhone = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = isCompact ? 12.0 : (isSlimPhone ? 16.0 : (isMobile ? 24.0 : 40.0));
    final iconSize = isCompact ? 16.0 : (isSlimPhone ? 18.0 : (isMobile ? 24.0 : 32.0));
    final valueSize = isCompact ? 14.0 : (isSlimPhone ? 16.0 : (isMobile ? 20.0 : 32.0));
    final titleSize = isCompact ? 8.0 : (isSlimPhone ? 8.0 : (isMobile ? 10.0 : 14.0));
    final padding = isCompact ? 8.0 : (isSlimPhone ? 8.0 : (isMobile ? 12.0 : 16.0));

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
            // Rounded rectangle decorative element - hide on slim phones
            if (!isCompact && !isSlimPhone)
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
            Padding(
              padding: EdgeInsets.all(padding),
              child: isCompact
                  ? Row(
                      children: [
                        Icon(icon, color: Colors.white, size: iconSize),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                value,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: valueSize,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                title,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: titleSize,
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
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: Colors.white, size: iconSize),
                        SizedBox(height: isSlimPhone ? 2 : (isMobile ? 4 : 8)),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            value,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: valueSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            title,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: titleSize,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
}

