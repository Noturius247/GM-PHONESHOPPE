import 'dart:convert';
import 'package:http/http.dart' as http;

class EmailService {
  // EmailJS Configuration
  // Sign up at https://www.emailjs.com/ and get these values:
  // 1. Create an account and add an Email Service (Gmail, Outlook, etc.)
  // 2. Create an Email Template with variables: {{to_email}}, {{to_name}}, {{from_name}}, {{message}}, {{subject}}
  // 3. Get your Service ID, Template ID, and Public Key from the dashboard

  static const String _serviceId = 'service_zazghys';
  static const String _templateId = 'template_cdp1ebq';
  static const String _publicKey = 'n27SPVnFkwAH1ESJZ';

  static const String _emailJsUrl = 'https://api.emailjs.com/api/v1.0/email/send';

  /// Check if EmailJS is configured
  static bool get isConfigured =>
      _serviceId != 'YOUR_SERVICE_ID' &&
      _templateId != 'YOUR_TEMPLATE_ID' &&
      _publicKey != 'YOUR_PUBLIC_KEY';

  /// Send email via EmailJS API
  static Future<bool> _sendEmail({
    required String toEmail,
    required String toName,
    required String subject,
    required String message,
  }) async {
    if (!isConfigured) {
      print('EmailJS not configured. Please set your Service ID, Template ID, and Public Key.');
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse(_emailJsUrl),
        headers: {
          'Content-Type': 'application/json',
          'origin': 'http://localhost', // Required for EmailJS
        },
        body: jsonEncode({
          'service_id': _serviceId,
          'template_id': _templateId,
          'user_id': _publicKey,
          'template_params': {
            'to_email': toEmail,
            'to_name': toName.isNotEmpty ? toName : 'User',
            'subject': subject,
            'message': message,
            'from_name': 'GM Phoneshoppe',
          },
        }),
      );

      if (response.statusCode == 200) {
        print('Email sent successfully to $toEmail');
        return true;
      } else {
        print('EmailJS Error: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error sending email: $e');
      return false;
    }
  }

  /// Send invitation email to a new user
  static Future<bool> sendInvitationEmail({
    required String recipientEmail,
    required String recipientName,
    required String invitedByName,
    required String invitedByEmail,
    required String invitationToken,
  }) async {
    final message = '''
Hello ${recipientName.isNotEmpty ? recipientName : 'there'},

$invitedByName has invited you to join the GM Phoneshoppe team!

To accept this invitation:
1. Download the GM Phoneshoppe app
2. Sign in with your Google account using this email address ($recipientEmail)
3. Your account will be automatically activated!

Your Invitation Code: $invitationToken

This invitation is valid for 7 days.

---
GM Phoneshoppe
Your Trusted Partner in Connectivity
Cignal • GSAT • Sky • Satellite Services
''';

    return await _sendEmail(
      toEmail: recipientEmail,
      toName: recipientName,
      subject: "You're Invited to Join GM Phoneshoppe!",
      message: message,
    );
  }

  /// Send approval email when user is approved
  static Future<bool> sendApprovalEmail({
    required String recipientEmail,
    required String recipientName,
  }) async {
    final message = '''
Hello ${recipientName.isNotEmpty ? recipientName : 'there'},

Great news! Your account has been APPROVED and you now have full access to the GM Phoneshoppe app.

You can now:
• View and manage customer records
• Access Cignal, GSAT, Sky, and Satellite services
• Use barcode and OCR scanning features
• Submit suggestions for admin review

Open the app and sign in to get started!

---
GM Phoneshoppe
Your Trusted Partner in Connectivity
Cignal • GSAT • Sky • Satellite Services
''';

    return await _sendEmail(
      toEmail: recipientEmail,
      toName: recipientName,
      subject: 'Welcome to GM Phoneshoppe - Account Approved!',
      message: message,
    );
  }

  /// Send PIN reset email with new generated PIN
  static Future<bool> sendPinResetEmail({
    required String recipientEmail,
    required String recipientName,
    required String newPin,
    required String resetByName,
  }) async {
    final message = '''
Hello ${recipientName.isNotEmpty ? recipientName : 'there'},

Your POS Staff PIN has been reset by $resetByName.

Your new PIN is: $newPin

Please sign in to the app and change your PIN in Settings as soon as possible.

---
GM Phoneshoppe
Your Trusted Partner in Connectivity
''';

    return await _sendEmail(
      toEmail: recipientEmail,
      toName: recipientName,
      subject: 'GM Phoneshoppe - Your Staff PIN Has Been Reset',
      message: message,
    );
  }
}
