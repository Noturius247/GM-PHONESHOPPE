import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class GsatSubscriptionCheckPage extends StatefulWidget {
  final String serialNumber;
  final String planType; // '99' for GPinoy, 'other' for GSAT subscription

  const GsatSubscriptionCheckPage({
    super.key,
    required this.serialNumber,
    required this.planType,
  });

  @override
  State<GsatSubscriptionCheckPage> createState() => _GsatSubscriptionCheckPageState();
}

class _GsatSubscriptionCheckPageState extends State<GsatSubscriptionCheckPage> {
  late final WebViewController _controller;
  bool _isLoading = true;

  String get _baseUrl {
    if (widget.planType == '99') {
      return 'https://www.gsat.asia/gpinoysubscription.php';
    } else {
      return 'https://www.gsat.asia/gsatsubscription.php';
    }
  }

  String get _planLabel {
    if (widget.planType == '99') {
      return 'Plan 99 (GPinoy)';
    } else {
      return 'Plans 69/200/300/500';
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
            // Auto-populate the box id field with serial number
            _autoPopulateBoxId();
          },
        ),
      )
      ..loadRequest(Uri.parse(_baseUrl));
  }

  void _autoPopulateBoxId() {
    // JavaScript to auto-fill the box id field (avoid captcha field)
    final jsCode = '''
      (function() {
        // Get all text inputs
        var inputs = document.querySelectorAll('input[type="text"]');
        var boxIdInput = null;

        // Find the Box No. field - usually the first text input before captcha
        for (var i = 0; i < inputs.length; i++) {
          var input = inputs[i];
          var name = (input.name || '').toLowerCase();
          var id = (input.id || '').toLowerCase();
          var placeholder = (input.placeholder || '').toLowerCase();

          // Skip captcha fields
          if (name.includes('captcha') || id.includes('captcha') ||
              placeholder.includes('captcha') || placeholder.includes('code') ||
              name.includes('security') || id.includes('security')) {
            continue;
          }

          // Look for box-related fields
          if (name.includes('box') || id.includes('box') ||
              placeholder.includes('box') || name.includes('subscriber') ||
              id.includes('subscriber')) {
            boxIdInput = input;
            break;
          }

          // If no specific match, use first non-captcha text input
          if (!boxIdInput) {
            boxIdInput = input;
          }
        }

        if (boxIdInput) {
          boxIdInput.value = '${widget.serialNumber}';
          boxIdInput.dispatchEvent(new Event('input', { bubbles: true }));
          boxIdInput.dispatchEvent(new Event('change', { bubbles: true }));
          boxIdInput.focus();
        }
      })();
    ''';

    _controller.runJavaScript(jsCode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Check Subscription', style: TextStyle(fontSize: 16)),
            Text(
              '$_planLabel - ${widget.serialNumber}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2ECC71),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _controller.reload();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF2ECC71),
              ),
            ),
        ],
      ),
    );
  }
}
