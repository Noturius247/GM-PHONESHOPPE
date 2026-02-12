import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'login_page.dart';
import 'signup_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _scaleAnimationController;
  late Animation<double> _scaleAnimation;
  bool _showScrollToTop = false;
  int _currentSection = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();

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

    // Listen to scroll position for scroll-to-top button and section tracking
    _scrollController.addListener(_onScroll);
  }

  void _onLogoTouchStart() {
    _scaleAnimationController.forward();
  }

  void _onLogoTouchEnd() {
    _scaleAnimationController.reverse();
  }

  void _onScroll() {
    final showButton = _scrollController.offset > 400;
    if (showButton != _showScrollToTop) {
      setState(() {
        _showScrollToTop = showButton;
      });
    }

    // Update current section based on scroll position
    final screenHeight = MediaQuery.of(context).size.height;
    final currentPosition = _scrollController.offset;
    final newSection = (currentPosition / screenHeight).round().clamp(0, 4);

    if (newSection != _currentSection) {
      setState(() {
        _currentSection = newSection;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _scaleAnimationController.dispose();
    super.dispose();
  }

  void _scrollToSection(int sectionIndex) {
    // Close drawer if open
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }

    final screenHeight = MediaQuery.of(context).size.height;
    // Account for the fixed header height (80px)
    final headerHeight = 80.0;
    _scrollController.animateTo(
      (screenHeight * sectionIndex) - (sectionIndex > 0 ? headerHeight : 0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
    );
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _onRefresh() async {
    // Simulate a refresh delay
    await Future.delayed(const Duration(seconds: 1));
    // Scroll to top after refresh
    _scrollToTop();
    // You can add actual data refresh logic here if needed
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // CIGNAL - Red colors
    const cignalDark = Color(0xFF8B1A1A);
    const cignalMain = Color(0xFFCC3333);
    const cignalBg = Color(0xFF1A0A0A);

    // GSAT - Green colors
    const gsatDark = Color(0xFF0A4A1A);
    const gsatMain = Color(0xFF2E7D32);
    const gsatLight = Color(0xFF4CAF50);

    // SATLITE - Orange colors
    const satliteDark = Color(0xFF663300);
    const satliteMain = Color(0xFFFF9800);
    const satliteLight = Color(0xFFFFB74D);

    // SKY DIRECT - Blue & Orange gradient
    const skyBlue = Color(0xFF0D47A1);
    const skyOrange = Color(0xFFFF6F00);
    const skyBlueDark = Color(0xFF0A2E5C);

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;

    return Scaffold(
      key: _scaffoldKey,
      drawer: isMobile ? _buildMobileDrawer(context) : null,
      body: Stack(
        children: [
          // Scrollable content with pull-to-refresh
          RefreshIndicator(
            onRefresh: _onRefresh,
            color: const Color(0xFF8B1A1A),
            backgroundColor: Colors.white,
            displacement: 100,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
              children: [
                // First Section - GM PhoneShoppe Hero
                _buildHeroSection(context, isMobile),

                // Second Section - RED (CIGNAL)
                _buildSection(
              context,
              isMobile: isMobile,
              colors: [cignalBg, cignalDark, const Color(0xFF4A0E0E)],
              logoPath: 'Photos/CIGNAL.png',
              title: 'CIGNAL',
              subtitle: 'TV Services',
              description: 'Experience premium digital TV with Cignal. Enjoy HD channels, sports, movies, and entertainment packages for the whole family.',
              mainColor: cignalMain,
              showHeader: false,
            ),

            // Third Section - GREEN (GSAT)
            _buildSection(
              context,
              isMobile: isMobile,
              colors: [gsatDark, gsatMain, const Color(0xFF1B5E20)],
              logoPath: 'Photos/GSAT.png',
              title: 'GSAT',
              subtitle: 'Global Satellite',
              description: 'Connect to the world with GSAT satellite services. Reliable, fast, and secure connectivity for all your communication needs.',
              mainColor: gsatLight,
              customButton: _buildLoadHereButton(context, gsatLight),
              chips: [
                {'label': 'Fast Speed', 'icon': Icons.speed},
                {'label': 'Global Coverage', 'icon': Icons.public},
                {'label': 'HD Quality', 'icon': Icons.hd},
                {'label': '24/7 Support', 'icon': Icons.support_agent},
              ],
            ),

            // Fourth Section - ORANGE (SATLITE)
            _buildSection(
              context,
              isMobile: isMobile,
              colors: [satliteDark, satliteMain, const Color(0xFFE65100)],
              logoPath: 'Photos/SATLITE.png',
              title: 'SATLITE',
              subtitle: 'Satellite Solutions',
              description: 'Premium satellite services for entertainment and connectivity. Enjoy crystal-clear quality and uninterrupted service.',
              mainColor: satliteLight,
              chips: [
                {'label': 'Prepaid', 'icon': Icons.payment},
                {'label': 'Postpaid', 'icon': Icons.card_membership},
                {'label': 'HD Channels', 'icon': Icons.live_tv},
                {'label': 'Movies', 'icon': Icons.movie},
              ],
            ),

            // Fifth Section - BLUE & ORANGE (SKY DIRECT)
                _buildSection(
                  context,
                  isMobile: isMobile,
                  colors: [skyBlueDark, skyBlue, skyOrange],
                  logoPath: 'Photos/SKY.png',
                  title: 'SKY DIRECT',
                  subtitle: 'Cable Services',
                  description: 'Watch your favorite shows with SKY Direct. Premium cable TV with the best channels, exclusive content, and sports.',
                  mainColor: skyOrange,
                  chips: [
                    {'label': 'Sports', 'icon': Icons.sports_soccer},
                    {'label': 'Movies', 'icon': Icons.movie_creation},
                    {'label': 'News', 'icon': Icons.newspaper},
                    {'label': 'Kids', 'icon': Icons.child_care},
                  ],
                ),
              ],
            ),
          ),
        ),
          // Fixed header at the top
          _buildFixedHeader(context, isMobile),

          // Section navigation dots
          if (!isMobile) _buildSectionDots(context),

          // Scroll to top button
          if (_showScrollToTop)
            Positioned(
              bottom: 20,
              right: 20,
              child: _buildScrollToTopButton(),
            ),
        ],
      ),
    );
  }

  // Mobile drawer menu
  Widget _buildMobileDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF1A0A0A),
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF8B1A1A),
                    const Color(0xFF1A0A0A),
                  ],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.phone_android, color: Colors.red);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Builder(
                      builder: (context) {
                        final screenWidth = MediaQuery.of(context).size.width;
                        return Text(
                          'GM PhoneShoppe',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: screenWidth < 360 ? 16 : 20,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Navigation Items
            _buildDrawerItem(
              context,
              icon: Icons.home,
              title: 'Home',
              onTap: () => _scrollToSection(0),
            ),
            _buildDrawerItem(
              context,
              icon: Icons.tv,
              title: 'Cignal',
              onTap: () => _scrollToSection(1),
            ),
            _buildDrawerItem(
              context,
              icon: Icons.router,
              title: 'GSAT',
              onTap: () => _scrollToSection(2),
            ),
            _buildDrawerItem(
              context,
              icon: Icons.satellite_alt,
              title: 'Satlite',
              onTap: () => _scrollToSection(3),
            ),
            _buildDrawerItem(
              context,
              icon: Icons.cloud,
              title: 'Sky Direct',
              onTap: () => _scrollToSection(4),
            ),
            const Divider(color: Colors.white24, height: 40),
            _buildDrawerItem(
              context,
              icon: Icons.login,
              title: 'Sign In',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LoginPage(),
                  ),
                );
              },
            ),
            _buildDrawerItem(
              context,
              icon: Icons.person_add,
              title: 'Sign Up',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SignUpPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(
        title,
        style: TextStyle(
          color: Colors.white,
          fontSize: screenWidth < 360 ? 14 : 16,
        ),
      ),
      onTap: onTap,
      hoverColor: Colors.white.withValues(alpha: 0.1),
    );
  }

  // Section navigation dots
  Widget _buildSectionDots(BuildContext context) {
    return Positioned(
      right: 20,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(5, (index) {
              final isActive = _currentSection == index;
              return GestureDetector(
                onTap: () => _scrollToSection(index),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 10,
                    height: isActive ? 30 : 10,
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(5),
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

  // Scroll to top button
  Widget _buildScrollToTopButton() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;

    return AnimatedOpacity(
      opacity: _showScrollToTop ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: FloatingActionButton(
        heroTag: 'landingScrollTop',
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

  Widget _buildFixedHeader(BuildContext context, bool isMobile) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: isMobile ? 112 : 80,
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
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16.0 : 20.0,
              vertical: isMobile ? 8.0 : 12.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _scrollToTop,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Row(
                        children: [
                          Container(
                            width: isMobile ? 36 : 50,
                            height: isMobile ? 36 : 50,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(isMobile ? 12 : 10),
                            ),
                            padding: const EdgeInsets.all(5),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(Icons.phone_android, color: Colors.red, size: 18);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'GM PhoneShoppe',
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
                  ),
                ),
                if (isMobile)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    child: IconButton(
                      icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                      onPressed: () {
                        _scaffoldKey.currentState?.openDrawer();
                      },
                    ),
                  )
                else
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => _scrollToSection(1),
                        icon: const Icon(Icons.tv, size: 18, color: Colors.white),
                        label: const Text(
                          'Cignal',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _scrollToSection(3),
                        icon: const Icon(Icons.satellite_alt, size: 18, color: Colors.white),
                        label: const Text(
                          'Satellite',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _scrollToSection(2),
                        icon: const Icon(Icons.router, size: 18, color: Colors.white),
                        label: const Text(
                          'GSAT',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _scrollToSection(4),
                        icon: const Icon(Icons.cloud, size: 18, color: Colors.white),
                        label: const Text(
                          'Sky',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LoginPage(),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: const Text('Sign in'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context, bool isMobile) {
    const darkBg = Color(0xFF1A0A0A);
    const logoRed = Color(0xFF8B1A1A);
    const logoLightRed = Color(0xFFCC3333);

    return Container(
      height: MediaQuery.of(context).size.height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            darkBg,
            logoRed,
            Color(0xFF4A0E0E),
          ],
          stops: [0.0, 0.6, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Add spacing for the fixed header
            SizedBox(height: isMobile ? 112 : 80),
            // Main Content
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 16.0 : 24.0,
                  vertical: isMobile ? 10 : 20,
                ),
                child: isMobile
                    ? _buildHeroMobileContent(context, logoRed, logoLightRed)
                    : _buildHeroDesktopContent(context, logoRed, logoLightRed),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroMobileContent(BuildContext context, Color logoRed, Color logoLightRed) {
    return Column(
      children: [
        const SizedBox(height: 20),
        SizedBox(
          height: 160,
          child: _buildHeroIllustration(context, true),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: _buildHeroText(context),
          ),
        ),
        const SizedBox(height: 20),
        _buildHeroButtons(context, logoRed),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildHeroDesktopContent(BuildContext context, Color logoRed, Color logoLightRed) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildHeroText(context),
                const SizedBox(height: 30),
                _buildHeroButtons(context, logoRed),
              ],
            ),
          ),
        ),
        const SizedBox(width: 40),
        Expanded(
          flex: 5,
          child: _buildHeroIllustration(context, false),
        ),
      ],
    );
  }

  Widget _buildHeroText(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSlimPhone = screenWidth < 360;
    final isMobile = screenWidth < 900;
    final titleFontSize = isSlimPhone ? 24.0 : (isMobile ? 32.0 : 64.0);
    final subtitleFontSize = isSlimPhone ? 15.0 : (isMobile ? 18.0 : 32.0);
    final descriptionFontSize = isMobile ? 13.0 : 16.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fast & Reliable',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w300,
                fontSize: subtitleFontSize,
              ),
        ),
        const SizedBox(height: 12),
        Text(
          'E-Loading',
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: titleFontSize,
                height: 1.1,
              ),
        ),
        Text(
          'Services',
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: titleFontSize,
                height: 1.1,
              ),
        ),
        const SizedBox(height: 24),
        Container(
          height: 4,
          width: 120,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.white, Colors.transparent],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Load your favorite services instantly. From Cignal to Sky, Satellite to GSAT - we\'ve got you covered with fast, secure, and efficient e-loading solutions for all your needs.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: descriptionFontSize,
                height: 1.6,
              ),
        ),
        const SizedBox(height: 32),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildServiceChipButton('Cignal', Icons.tv, 1),
            _buildServiceChipButton('Satlite', Icons.satellite_alt, 3),
            _buildServiceChipButton('GSAT', Icons.router, 2),
            _buildServiceChipButton('Sky Direct', Icons.cloud, 4),
          ],
        ),
      ],
    );
  }

  Widget _buildHeroIllustration(BuildContext context, bool isMobile) {
    const heroColor = Color(0xFFCC3333); // Red color for GM PhoneShoppe
    final containerBorderRadius = isMobile ? 60.0 : 40.0;

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(containerBorderRadius),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.hardEdge,
          children: [
            // Full background with red color
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: heroColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(containerBorderRadius),
                  border: Border.all(
                    color: heroColor.withValues(alpha: 0.2),
                    width: 3,
                  ),
                ),
              ),
            ),
            // Decorative circles with red color
            if (!isMobile) ...[
              Positioned(
                top: -50,
                right: 20,
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: heroColor.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Positioned(
                bottom: -30,
                left: 0,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: heroColor.withValues(alpha: 0.06),
                  ),
                ),
              ),
              Positioned(
                top: 100,
                left: -40,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),
            ] else ...[
              // Mobile: smaller circles that stay inside
              Positioned(
                top: 20,
                right: 20,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: heroColor.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Positioned(
                bottom: 20,
                left: 20,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: heroColor.withValues(alpha: 0.06),
                  ),
                ),
              ),
            ],
            // Logo filling 80% with scale animation on touch
            Center(
              child: GestureDetector(
                onTapDown: (_) => _onLogoTouchStart(),
                onTapUp: (_) => _onLogoTouchEnd(),
                onTapCancel: () => _onLogoTouchEnd(),
                child: AnimatedBuilder(
                  animation: _scaleAnimationController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _scaleAnimation.value,
                      child: FractionallySizedBox(
                        widthFactor: 0.8,
                        heightFactor: 0.8,
                        child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              // Dramatic glow effect
                              BoxShadow(
                                color: heroColor.withValues(alpha: 0.6),
                                blurRadius: 100,
                                spreadRadius: 20,
                                offset: const Offset(0, 0),
                              ),
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.3),
                                blurRadius: 50,
                                spreadRadius: 10,
                                offset: const Offset(0, 0),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.phone_android,
                                size: 150,
                                color: Colors.white,
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroButtons(BuildContext context, Color logoRed) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;
    final buttonFontSize = isMobile ? 14.0 : 18.0;
    final buttonPadding = isMobile
        ? const EdgeInsets.symmetric(vertical: 14, horizontal: 24)
        : const EdgeInsets.symmetric(vertical: 18, horizontal: 32);
    final borderRadius = isMobile ? 30.0 : 12.0;

    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LoginPage(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: logoRed,
              padding: buttonPadding,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(borderRadius),
              ),
              elevation: 8,
            ),
            child: Text(
              'Get Started',
              style: TextStyle(
                fontSize: buttonFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SignUpPage(),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white, width: 2),
              padding: buttonPadding,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(borderRadius),
              ),
            ),
            child: Text(
              'Sign Up',
              style: TextStyle(
                fontSize: buttonFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required bool isMobile,
    required List<Color> colors,
    required String logoPath,
    required String title,
    required String subtitle,
    required String description,
    required Color mainColor,
    bool showHeader = false,
    bool transparentBackground = false,
    Widget? customButton,
    List<Map<String, dynamic>>? chips,
  }) {
    return Container(
      height: MediaQuery.of(context).size.height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
          stops: const [0.0, 0.6, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Header/Navigation (only on first section)
            if (showHeader)
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(Icons.phone_android, color: Colors.red);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'GM PhoneShoppe',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (!isMobile)
                      Row(
                        children: [
                          TextButton(
                            onPressed: () {},
                            child: const Text(
                              'Services',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          TextButton(
                            onPressed: () {},
                            child: const Text(
                              'About Us',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const LoginPage(),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Sign in'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            // Main Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
                child: isMobile
                    ? _buildMobileContent(
                        context,
                        logoPath: logoPath,
                        title: title,
                        subtitle: subtitle,
                        description: description,
                        mainColor: mainColor,
                        transparentBackground: transparentBackground,
                        customButton: customButton,
                        chips: chips,
                      )
                    : _buildDesktopContent(
                        context,
                        logoPath: logoPath,
                        title: title,
                        subtitle: subtitle,
                        description: description,
                        mainColor: mainColor,
                        transparentBackground: transparentBackground,
                        customButton: customButton,
                        chips: chips,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileContent(
    BuildContext context, {
    required String logoPath,
    required String title,
    required String subtitle,
    required String description,
    required Color mainColor,
    bool transparentBackground = false,
    Widget? customButton,
    List<Map<String, dynamic>>? chips,
  }) {
    return Column(
      children: [
        const SizedBox(height: 40),
        SizedBox(
          height: 160,
          child: _buildLogoIllustration(context, logoPath, mainColor, true, transparentBackground),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: _buildTextContent(context, title, subtitle, description, chips),
          ),
        ),
        const SizedBox(height: 20),
        customButton ?? _buildActionButtons(context, mainColor),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildDesktopContent(
    BuildContext context, {
    required String logoPath,
    required String title,
    required String subtitle,
    required String description,
    required Color mainColor,
    bool transparentBackground = false,
    Widget? customButton,
    List<Map<String, dynamic>>? chips,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildTextContent(context, title, subtitle, description, chips),
                const SizedBox(height: 30),
                customButton ?? _buildActionButtons(context, mainColor),
              ],
            ),
          ),
        ),
        const SizedBox(width: 40),
        Expanded(
          flex: 5,
          child: _buildLogoIllustration(context, logoPath, mainColor, false, transparentBackground),
        ),
      ],
    );
  }

  Widget _buildTextContent(
    BuildContext context,
    String title,
    String subtitle,
    String description,
    List<Map<String, dynamic>>? chips,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSlimPhone = screenWidth < 360;
    final isMobile = screenWidth < 900;
    final titleFontSize = isSlimPhone ? 24.0 : (isMobile ? 32.0 : 64.0);
    final subtitleFontSize = isSlimPhone ? 15.0 : (isMobile ? 18.0 : 32.0);
    final descriptionFontSize = isMobile ? 13.0 : 16.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          subtitle,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w300,
                fontSize: subtitleFontSize,
              ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: titleFontSize,
                height: 1.1,
              ),
        ),
        const SizedBox(height: 24),
        Container(
          height: 4,
          width: 120,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.white, Colors.transparent],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: descriptionFontSize,
                height: 1.6,
              ),
        ),
        if (chips != null) ...[
          const SizedBox(height: 32),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: chips.map((chip) {
              return _buildServiceChip(
                chip['label'] as String,
                chip['icon'] as IconData,
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildServiceChip(String label, IconData icon) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(isMobile ? 30 : 20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceChipButton(String label, IconData icon, int sectionIndex) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;
    final chipBorderRadius = isMobile ? 30.0 : 20.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: () => _scrollToSection(sectionIndex),
        borderRadius: BorderRadius.circular(chipBorderRadius),
        hoverColor: Colors.white.withValues(alpha: 0.2),
        splashColor: Colors.white.withValues(alpha: 0.3),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(chipBorderRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoIllustration(
    BuildContext context,
    String logoPath,
    Color glowColor,
    bool isMobile,
    bool transparentBackground,
  ) {
    final containerBorderRadius = isMobile ? 60.0 : 40.0;

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(containerBorderRadius),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.hardEdge,
          children: [
            // Only show background and decorative circles if NOT transparent
            if (!transparentBackground) ...[
              // Full background with service color
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: glowColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(containerBorderRadius),
                    border: Border.all(
                      color: glowColor.withValues(alpha: 0.2),
                      width: 3,
                    ),
                  ),
                ),
              ),
              // Decorative circles
              if (!isMobile) ...[
                Positioned(
                  top: -50,
                  right: 20,
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: glowColor.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -30,
                  left: 0,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: glowColor.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                Positioned(
                  top: 100,
                  left: -40,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
              ] else ...[
                // Mobile: smaller circles that stay inside
                Positioned(
                  top: 20,
                  right: 20,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: glowColor.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: glowColor.withValues(alpha: 0.06),
                    ),
                  ),
                ),
              ],
            ],
            // Logo filling 80% of the container with scale animation on touch
            Center(
              child: GestureDetector(
                onTapDown: (_) => _onLogoTouchStart(),
                onTapUp: (_) => _onLogoTouchEnd(),
                onTapCancel: () => _onLogoTouchEnd(),
                child: AnimatedBuilder(
                  animation: _scaleAnimationController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _scaleAnimation.value,
                      child: FractionallySizedBox(
                        widthFactor: 0.8,
                        heightFactor: 0.8,
                        child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              // Dramatic glow effect
                              BoxShadow(
                                color: glowColor.withValues(alpha: 0.6),
                                blurRadius: 100,
                                spreadRadius: 20,
                                offset: const Offset(0, 0),
                              ),
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.3),
                                blurRadius: 50,
                                spreadRadius: 10,
                                offset: const Offset(0, 0),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            logoPath,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.image_not_supported,
                                size: 150,
                                color: Colors.white,
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, Color mainColor) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;
    final buttonBorderRadius = isMobile ? 30.0 : 12.0;
    final buttonFontSize = isMobile ? 14.0 : 18.0;
    final buttonPadding = isMobile
        ? const EdgeInsets.symmetric(vertical: 14, horizontal: 24)
        : const EdgeInsets.symmetric(vertical: 18, horizontal: 32);

    return Row(
      children: [
        Expanded(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LoginPage(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: mainColor,
                  padding: buttonPadding,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(buttonBorderRadius),
                  ),
                  elevation: 8,
                ).copyWith(
                  overlayColor: WidgetStateProperty.resolveWith<Color?>(
                    (Set<WidgetState> states) {
                      if (states.contains(WidgetState.hovered)) {
                        return mainColor.withValues(alpha: 0.1);
                      }
                      return null;
                    },
                  ),
                ),
                child: Text(
                  'Get Started',
                  style: TextStyle(
                    fontSize: buttonFontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SignUpPage(),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white, width: 2),
                  padding: buttonPadding,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(buttonBorderRadius),
                  ),
                ).copyWith(
                  overlayColor: WidgetStateProperty.resolveWith<Color?>(
                    (Set<WidgetState> states) {
                      if (states.contains(WidgetState.hovered)) {
                        return Colors.white.withValues(alpha: 0.1);
                      }
                      return null;
                    },
                  ),
                ),
                child: Text(
                  'Learn More',
                  style: TextStyle(
                    fontSize: buttonFontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadHereButton(BuildContext context, Color mainColor) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;
    final buttonBorderRadius = isMobile ? 30.0 : 12.0;
    final buttonFontSize = isMobile ? 14.0 : 18.0;
    final buttonPadding = isMobile
        ? const EdgeInsets.symmetric(vertical: 14, horizontal: 24)
        : const EdgeInsets.symmetric(vertical: 18, horizontal: 32);

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          final url = Uri.parse('https://www.gsat.asia/index.php');
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
          } else {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Could not open GSAT website'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
        icon: const Icon(Icons.language, size: 24),
        label: Text(
          'Load Here',
          style: TextStyle(
            fontSize: buttonFontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: mainColor,
          foregroundColor: Colors.white,
          padding: buttonPadding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonBorderRadius),
          ),
          elevation: 8,
        ),
      ),
    );
  }
}
