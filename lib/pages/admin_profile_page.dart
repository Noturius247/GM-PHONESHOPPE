import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/firebase_database_service.dart';
import 'landing_page.dart';

class AdminProfilePage extends StatefulWidget {
  const AdminProfilePage({super.key});

  @override
  State<AdminProfilePage> createState() => _AdminProfilePageState();
}

class _AdminProfilePageState extends State<AdminProfilePage> {
  User? _firebaseUser;
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _dbUserData;
  bool _isLoading = true;
  bool _isSuperAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);

    try {
      // Get Firebase Auth user (has Google account info)
      _firebaseUser = AuthService.getFirebaseUser();

      // Get current user data from auth service
      _userData = await AuthService.getCurrentUser();

      // Check if super admin
      if (_userData != null && _userData!['email'] != null) {
        _isSuperAdmin = AuthService.isSuperAdminEmail(_userData!['email']);

        // Get additional data from database
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
                color: Color(0xFF8B1A1A),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadUserData,
              color: const Color(0xFF8B1A1A),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
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
            ),
    );
  }

  Widget _buildProfileHeader(bool isMobile) {
    final photoUrl = _firebaseUser?.photoURL;
    final displayName = _firebaseUser?.displayName ?? _userData?['name'] ?? 'Admin';
    final email = _firebaseUser?.email ?? _userData?['email'] ?? '';

    return Container(
      padding: EdgeInsets.all(isMobile ? 24 : 32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8B1A1A), Color(0xFF5C0F0F)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B1A1A).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Profile Picture
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
                      color: const Color(0xFF8B1A1A),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),

          // Name
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

          // Email
          Text(
            email,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: isMobile ? 14 : 16,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // Role Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _isSuperAdmin
                  ? Colors.amber.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isSuperAdmin ? Colors.amber : Colors.white,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isSuperAdmin ? Icons.shield : Icons.admin_panel_settings,
                  color: _isSuperAdmin ? Colors.amber : Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _isSuperAdmin ? 'Super Admin' : 'Administrator',
                  style: TextStyle(
                    color: _isSuperAdmin ? Colors.amber : Colors.white,
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
      isMobile: isMobile,
      children: [
        _buildInfoRow(
          'User ID',
          _firebaseUser?.uid ?? 'N/A',
          Icons.fingerprint,
          isMobile,
        ),
        _buildDivider(),
        _buildInfoRow(
          'Email Verified',
          _firebaseUser?.emailVerified == true ? 'Yes' : 'No',
          _firebaseUser?.emailVerified == true ? Icons.verified : Icons.warning,
          isMobile,
          valueColor: _firebaseUser?.emailVerified == true
              ? Colors.green
              : Colors.orange,
        ),
        _buildDivider(),
        _buildInfoRow(
          'Account Created',
          _formatDateTime(_firebaseUser?.metadata.creationTime),
          Icons.calendar_today,
          isMobile,
        ),
        _buildDivider(),
        _buildInfoRow(
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
      isMobile: isMobile,
      children: [
        _buildInfoRow(
          'Display Name',
          _firebaseUser?.displayName ?? 'N/A',
          Icons.person,
          isMobile,
        ),
        _buildDivider(),
        _buildInfoRow(
          'Email',
          _firebaseUser?.email ?? 'N/A',
          Icons.email,
          isMobile,
        ),
        _buildDivider(),
        _buildInfoRow(
          'Phone Number',
          _firebaseUser?.phoneNumber ?? 'Not linked',
          Icons.phone,
          isMobile,
        ),
        _buildDivider(),
        _buildInfoRow(
          'Photo URL',
          _firebaseUser?.photoURL != null ? 'Available' : 'Not set',
          Icons.photo,
          isMobile,
          valueColor: _firebaseUser?.photoURL != null ? Colors.green : null,
        ),
        _buildDivider(),
        _buildInfoRow(
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
      isMobile: isMobile,
      children: [
        _buildInfoRow(
          'Status',
          _dbUserData?['status']?.toString().toUpperCase() ?? 'N/A',
          Icons.check_circle,
          isMobile,
          valueColor: _dbUserData?['status'] == 'active' ? Colors.green : null,
        ),
        _buildDivider(),
        _buildInfoRow(
          'Role in Database',
          _dbUserData?['role']?.toString().toUpperCase() ?? 'N/A',
          Icons.badge,
          isMobile,
        ),
        if (addedBy != null) ...[
          _buildDivider(),
          _buildInfoRow(
            'Added By',
            addedBy['name']?.toString() ?? addedBy['email']?.toString() ?? 'N/A',
            Icons.person_add,
            isMobile,
          ),
        ],
        if (createdAt != null) ...[
          _buildDivider(),
          _buildInfoRow(
            'Record Created',
            _formatTimestamp(createdAt),
            Icons.create,
            isMobile,
          ),
        ],
        if (lastLogin != null) ...[
          _buildDivider(),
          _buildInfoRow(
            'Last Login (DB)',
            _formatTimestamp(lastLogin),
            Icons.login,
            isMobile,
          ),
        ],
      ],
    );
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

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required bool isMobile,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
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
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B1A1A), Color(0xFF5C0F0F)],
                    ),
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
          Divider(
            color: Colors.white.withValues(alpha: 0.1),
            height: 1,
          ),
          Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 20),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    IconData icon,
    bool isMobile, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.6),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: isMobile ? 13 : 14,
              ),
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
    return Divider(
      color: Colors.white.withValues(alpha: 0.1),
      height: 1,
    );
  }

  Widget _buildActionButtons(bool isMobile) {
    return Column(
      children: [
        // Refresh Button
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
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Sign Out Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _showSignOutDialog(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B1A1A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Sign Out',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to sign out of your account?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B1A1A),
            ),
            child: const Text(
              'Sign Out',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
