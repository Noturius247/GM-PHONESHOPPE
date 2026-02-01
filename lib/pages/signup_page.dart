import 'package:flutter/material.dart';
import 'login_page.dart';
import 'main_admin_page.dart';
import 'main_user_page.dart';
import '../services/auth_service.dart';
import '../services/firebase_database_service.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  bool _isLoading = false;
  bool _isVerifyingCode = false;
  final TextEditingController _codeController = TextEditingController();
  Map<String, dynamic>? _verifiedInvitation;
  String? _codeError;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verifyInvitationCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _codeError = 'Please enter your invitation code';
      });
      return;
    }

    setState(() {
      _isVerifyingCode = true;
      _codeError = null;
    });

    final invitation = await FirebaseDatabaseService.validateInvitationCode(code);

    if (mounted) {
      setState(() {
        _isVerifyingCode = false;
        if (invitation != null) {
          _verifiedInvitation = invitation;
          _codeError = null;
        } else {
          _codeError = 'Invalid or expired invitation code';
          _verifiedInvitation = null;
        }
      });
    }
  }

  void _resetVerification() {
    setState(() {
      _verifiedInvitation = null;
      _codeController.clear();
      _codeError = null;
    });
  }

  void _showEmailMismatchDialog(String signedInEmail, String invitedEmail) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.error_outline, color: Colors.red, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Email Mismatch',
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The Google account you signed in with does not match the invitation.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Signed in as:',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    signedInEmail,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Invitation sent to:',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    invitedEmail,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Please sign in with the correct Google account.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _resetVerification();
            },
            child: const Text(
              'Try Again',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleGoogleSignUp() async {
    // If we have a verified invitation, check that email matches
    if (_verifiedInvitation == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please verify your invitation code first'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Sign in with Google (only authenticate, don't check access yet)
    final googleUser = await AuthService.signInWithGoogleForSignup();

    if (googleUser == null) {
      // Sign up failed or cancelled
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sign up cancelled or failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Verify email matches the invitation
    final signedInEmail = (googleUser['email'] as String?)?.toLowerCase().trim() ?? '';
    final invitedEmail = (_verifiedInvitation!['email'] as String?)?.toLowerCase().trim() ?? '';

    if (signedInEmail != invitedEmail) {
      // Email mismatch - sign out and show error
      await AuthService.logout();
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showEmailMismatchDialog(signedInEmail, invitedEmail);
      }
      return;
    }

    // Accept the invitation and create user in database
    // Use the ID from the verified invitation for reliability
    final invitationId = _verifiedInvitation!['id'] as String;
    final acceptedUser = await FirebaseDatabaseService.acceptInvitationWithId(invitationId, signedInEmail);

    if (acceptedUser == null) {
      // Failed to accept invitation
      await AuthService.logout();
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to complete signup. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Get the role from the accepted user (more reliable than invitation)
    final role = acceptedUser['role'] as String? ?? _verifiedInvitation!['role'] as String? ?? 'user';
    final name = googleUser['name'] as String? ?? '';

    // Complete signup - save login state
    await AuthService.completeSignup(signedInEmail, name, role);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }

    // Sign up successful - navigate based on role
    if (mounted) {
      if (role == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const MainAdminPage(),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => MainUserPage(userName: name),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Logo colors - deep red/burgundy
    const logoRed = Color(0xFF8B1A1A);
    const logoLightRed = Color(0xFFCC3333);
    const darkBg = Color(0xFF1A0A0A);

    return Scaffold(
      body: Container(
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo with glow effect
                    Container(
                      width: 180,
                      height: 180,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.3),
                            blurRadius: 40,
                            spreadRadius: 5,
                            offset: const Offset(0, 0),
                          ),
                          BoxShadow(
                            color: logoLightRed.withValues(alpha: 0.2),
                            blurRadius: 50,
                            spreadRadius: 3,
                            offset: const Offset(0, 0),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 40),
                    // Title
                    Text(
                      'Join Us Today',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 36,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Create your account and start e-loading',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 16,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    // Invitation Code Section
                    if (_verifiedInvitation == null) ...[
                      // Code Input Field
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _codeError != null
                                ? Colors.red.withValues(alpha: 0.5)
                                : Colors.white.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: TextField(
                          controller: _codeController,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 18,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: 'Enter invitation code',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 16,
                            ),
                            prefixIcon: Icon(
                              Icons.vpn_key,
                              color: logoRed.withValues(alpha: 0.7),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 18,
                            ),
                          ),
                          onChanged: (_) {
                            if (_codeError != null) {
                              setState(() {
                                _codeError = null;
                              });
                            }
                          },
                        ),
                      ),
                      if (_codeError != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              _codeError!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),
                      // Verify Code Button
                      _isVerifyingCode
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Container(
                              width: double.infinity,
                              height: 56,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Colors.white, Color(0xFFF5F5F5)],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.3),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: ElevatedButton.icon(
                                onPressed: _verifyInvitationCode,
                                icon: const Icon(Icons.verified, color: logoRed),
                                label: const Text(
                                  'Verify Code',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: logoRed,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                    ] else ...[
                      // Verified Invitation Display
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Code Verified!',
                                        style: TextStyle(
                                          color: Colors.green,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Invitation for: ${_verifiedInvitation!['email']}',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.9),
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: _resetVerification,
                                  icon: Icon(
                                    Icons.close,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                  tooltip: 'Use different code',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Sign Up Button (only shown after code verification)
                      _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Container(
                              width: double.infinity,
                              height: 60,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Colors.white, Color(0xFFF5F5F5)],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.3),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: ElevatedButton.icon(
                                onPressed: _handleGoogleSignUp,
                                icon: const Icon(Icons.person_add, color: logoRed),
                                label: const Text(
                                  'Sign up with Google',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: logoRed,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                      const SizedBox(height: 12),
                      Text(
                        'Sign in with the Google account: ${_verifiedInvitation!['email']}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 32),
                    // Already have account section
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Already have an account?',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const LoginPage(),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              backgroundColor: logoRed,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Sign In',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    // Info Box
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.mail_outline,
                            size: 32,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Invitation Required',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white.withValues(alpha: 0.95),
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Enter the invitation code from your email to sign up. Make sure to use the same Google account that received the invitation.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}