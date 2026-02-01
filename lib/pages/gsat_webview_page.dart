import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'ocr_scanner_page.dart';

class GSatWebViewPage extends StatefulWidget {
  final String accountNumber;

  const GSatWebViewPage({
    super.key,
    required this.accountNumber,
  });

  @override
  State<GSatWebViewPage> createState() => _GSatWebViewPageState();
}

class _GSatWebViewPageState extends State<GSatWebViewPage> {
  late final WebViewController _controller;
  bool _isLoading = true;

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
            // Auto-populate the account number field
            _autoPopulateAccountNumber();
          },
        ),
      )
      ..loadRequest(Uri.parse('https://www.gsat.asia/index.php'));
  }

  void _autoPopulateAccountNumber() {
    // JavaScript to auto-fill the account number field
    // This assumes the GSAT website has an input field with id or name attribute
    // You may need to adjust the selector based on the actual website structure
    final jsCode = '''
      (function() {
        // Try common selectors for account number input fields
        var accountInput = document.querySelector('input[name*="account"]') ||
                          document.querySelector('input[id*="account"]') ||
                          document.querySelector('input[placeholder*="account"]') ||
                          document.querySelector('input[type="text"]');

        if (accountInput) {
          accountInput.value = '${widget.accountNumber}';
          accountInput.dispatchEvent(new Event('input', { bubbles: true }));
          accountInput.dispatchEvent(new Event('change', { bubbles: true }));
        }
      })();
    ''';

    _controller.runJavaScript(jsCode);
  }

  Future<void> _scanAndPopulatePin() async {
    final result = await Navigator.push<OcrExtractedData>(
      context,
      MaterialPageRoute(
        builder: (context) => OcrScannerPage(
          serviceName: 'GSAT Security Code',
          primaryColor: Colors.orange.shade600,
          securityCodeOnly: true,
        ),
      ),
    );

    if (result != null && result.pin != null && result.pin!.isNotEmpty) {
      _autoPopulatePin(result.pin!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Security Code detected: ${result.pin}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _autoPopulatePin(String pin) {
    // JavaScript to auto-fill the PIN/security code field
    final jsCode = '''
      (function() {
        // Try common selectors for PIN/security code input fields
        var pinInput = document.querySelector('input[name*="pin"]') ||
                      document.querySelector('input[name*="security"]') ||
                      document.querySelector('input[name*="code"]') ||
                      document.querySelector('input[id*="pin"]') ||
                      document.querySelector('input[id*="security"]') ||
                      document.querySelector('input[id*="code"]') ||
                      document.querySelector('input[placeholder*="pin"]') ||
                      document.querySelector('input[placeholder*="security"]') ||
                      document.querySelector('input[placeholder*="code"]') ||
                      document.querySelector('input[type="password"]');

        if (pinInput) {
          pinInput.value = '$pin';
          pinInput.dispatchEvent(new Event('input', { bubbles: true }));
          pinInput.dispatchEvent(new Event('change', { bubbles: true }));
        }
      })();
    ''';

    _controller.runJavaScript(jsCode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('GSAT - ${widget.accountNumber}'),
        backgroundColor: Colors.orange.shade600,
        actions: [
          IconButton(
            icon: const Icon(Icons.document_scanner),
            tooltip: 'Scan Security Code',
            onPressed: _scanAndPopulatePin,
          ),
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
                color: Colors.orange,
              ),
            ),
        ],
      ),
    );
  }
}
