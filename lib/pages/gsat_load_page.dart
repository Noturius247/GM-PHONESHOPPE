import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webviewx_plus/webviewx_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'ocr_scanner_page.dart';
import 'gsat_subscription_check_page.dart';

class GsatLoadPage extends StatefulWidget {
  const GsatLoadPage({super.key});

  @override
  State<GsatLoadPage> createState() => _GsatLoadPageState();
}

class _GsatLoadPageState extends State<GsatLoadPage> {
  WebViewXController? _controller;
  bool _isLoading = true;
  String? _scannedBoxId;
  String? _scannedPin;

  static const String gsatUrl = 'https://www.gsat.asia/index.php';
  static const Color primaryColor = Color(0xFF2ECC71);

  // Scan for Security Code/PIN only
  Future<void> _scanSecurityCode() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OCR Scanner is only available on mobile devices'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final result = await Navigator.push<OcrExtractedData>(
      context,
      MaterialPageRoute(
        builder: (context) => const OcrScannerPage(
          serviceName: 'GSAT Security Code',
          primaryColor: primaryColor,
          securityCodeOnly: true,
          serviceType: 'gsat',
        ),
      ),
    );

    if (result != null && mounted) {
      if (result.pin != null && result.pin!.isNotEmpty) {
        setState(() {
          _scannedPin = result.pin;
        });
        _autoPopulatePin(result.pin!);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Security Code detected: ${result.pin}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No security code detected. Try again.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  // Scan for Box ID/Serial Number only
  Future<void> _scanBoxId() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OCR Scanner is only available on mobile devices'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final result = await Navigator.push<OcrExtractedData>(
      context,
      MaterialPageRoute(
        builder: (context) => const OcrScannerPage(
          serviceName: 'GSAT Box ID',
          primaryColor: primaryColor,
          securityCodeOnly: false,
          serviceType: 'gsat_boxid',
        ),
      ),
    );

    if (result != null && mounted) {
      if (result.serialNumber != null && result.serialNumber!.isNotEmpty) {
        setState(() {
          _scannedBoxId = result.serialNumber;
        });
        _autoPopulateBoxId(result.serialNumber!);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Box ID detected: ${result.serialNumber}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No Box ID detected. Try again.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _autoPopulateBoxId(String boxId) {
    if (_controller == null) return;

    // Improved JavaScript to find and fill Box ID field
    // Targets the first text input on the GSAT loading page (Box No. field)
    final jsCode = '''
      (function() {
        // Get ALL inputs
        var inputs = document.querySelectorAll('input');
        var boxIdInput = null;
        var validInputs = [];

        for (var i = 0; i < inputs.length; i++) {
          var input = inputs[i];
          var type = (input.type || 'text').toLowerCase();

          // Skip non-text inputs
          if (type === 'hidden' || type === 'submit' || type === 'button' ||
              type === 'checkbox' || type === 'radio' || type === 'file' ||
              type === 'image' || type === 'reset' || type === 'password') {
            continue;
          }

          var name = (input.name || '').toLowerCase();
          var id = (input.id || '').toLowerCase();
          var placeholder = (input.placeholder || '').toLowerCase();

          // Skip captcha fields (usually has captcha/code in name or comes after box input)
          if (name.includes('captcha') || id.includes('captcha') ||
              placeholder.includes('captcha') || placeholder.includes('enter code') ||
              placeholder.includes('verification')) {
            continue;
          }

          validInputs.push({
            input: input,
            name: name,
            id: id,
            placeholder: placeholder
          });

          // Prefer inputs with box/subscriber/account keywords
          if (!boxIdInput && (name.includes('box') || id.includes('box') ||
              placeholder.includes('box') || name.includes('subscriber') ||
              id.includes('subscriber') || name.includes('subs') ||
              placeholder.includes('subs'))) {
            boxIdInput = input;
          }
        }

        // Use found box input or the FIRST valid input (usually Box No. on GSAT)
        var targetInput = boxIdInput || (validInputs.length > 0 ? validInputs[0].input : null);

        if (targetInput) {
          // Clear and set value
          targetInput.value = '';
          targetInput.value = '$boxId';

          // Trigger multiple events for compatibility
          ['input', 'change', 'keyup', 'keydown', 'blur'].forEach(function(eventType) {
            targetInput.dispatchEvent(new Event(eventType, { bubbles: true }));
          });

          targetInput.focus();

          // Also try setting via native setter for React/Vue compatibility
          var nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
          if (nativeInputValueSetter) {
            nativeInputValueSetter.call(targetInput, '$boxId');
            targetInput.dispatchEvent(new Event('input', { bubbles: true }));
          }
        }
      })();
    ''';

    _controller!.evalRawJavascript(jsCode);
  }

  void _autoPopulatePin(String pin) {
    if (_controller == null) return;

    // Only populate PIN/Security Code fields, NOT captcha
    final jsCode = '''
      (function() {
        var pinInput = document.querySelector('input[name*="pin"]') ||
                      document.querySelector('input[name*="security"]') ||
                      document.querySelector('input[id*="pin"]') ||
                      document.querySelector('input[id*="security"]') ||
                      document.querySelector('input[placeholder*="pin"]') ||
                      document.querySelector('input[placeholder*="security"]') ||
                      document.querySelector('input[type="password"]');

        if (pinInput) {
          pinInput.value = '$pin';
          pinInput.dispatchEvent(new Event('input', { bubbles: true }));
          pinInput.dispatchEvent(new Event('change', { bubbles: true }));
        }
      })();
    ''';

    _controller!.evalRawJavascript(jsCode);
  }

  // Open GSAT Subscription Check (manual entry without scanner)
  void _openSubscriptionCheck() {
    final boxIdController = TextEditingController(text: _scannedBoxId ?? '');
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 360 ? screenWidth * 0.9 : 400.0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        title: const Text(
          'Check GSAT Subscription',
          style: TextStyle(color: Colors.white),
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: dialogWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: boxIdController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Box ID / Serial Number',
                  labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                  hintText: 'Enter Box ID',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: primaryColor),
                  ),
                  prefixIcon: const Icon(Icons.qr_code, color: primaryColor),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select Plan Type:',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
        actions: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceEvenly,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () {
                  if (boxIdController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a Box ID'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GsatSubscriptionCheckPage(
                        serialNumber: boxIdController.text,
                        planType: '99',
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                ),
                child: const Text('Plan 99 (GPinoy)'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (boxIdController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a Box ID'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GsatSubscriptionCheckPage(
                        serialNumber: boxIdController.text,
                        planType: 'other',
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                ),
                child: const Text('Other Plans'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(gsatUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open GSAT website'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showScannedDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Scanned Data',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDataRow('Box ID', _scannedBoxId),
            const SizedBox(height: 8),
            _buildDataRow('PIN', _scannedPin),
            const SizedBox(height: 16),
            const Text(
              'Copy these values to paste into the GSAT website',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _scannedBoxId = null;
                _scannedPin = null;
              });
              Navigator.pop(context);
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
          if (!kIsWeb)
            TextButton(
              onPressed: () {
                if (_scannedBoxId != null) _autoPopulateBoxId(_scannedBoxId!);
                if (_scannedPin != null) _autoPopulatePin(_scannedPin!);
                Navigator.pop(context);
              },
              child: const Text('Re-fill', style: TextStyle(color: primaryColor)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildDataRow(String label, String? value) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.bold,
          ),
        ),
        Expanded(
          child: SelectableText(
            value ?? 'Not scanned',
            style: TextStyle(
              color: value != null ? Colors.white : Colors.white38,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Load GSAT'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          // OCR Scanner for Security Code/PIN (only show on mobile)
          if (!kIsWeb)
            IconButton(
              icon: const Icon(Icons.pin),
              tooltip: 'Scan Security Code/PIN',
              onPressed: _scanSecurityCode,
            ),
          // OCR Scanner for Box ID/Serial Number (only show on mobile)
          if (!kIsWeb)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Scan Box ID/Serial Number',
              onPressed: _scanBoxId,
            ),
          // Show scanned data
          if (_scannedBoxId != null || _scannedPin != null)
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'View Scanned Data',
              onPressed: _showScannedDataDialog,
            ),
          // Check GSAT Subscription (manual entry)
          IconButton(
            icon: const Icon(Icons.fact_check),
            tooltip: 'Check Subscription',
            onPressed: _openSubscriptionCheck,
          ),
          // Open in external browser
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Open in Browser',
            onPressed: _openInBrowser,
          ),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              _controller?.reload();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewX(
            width: size.width,
            height: size.height - kToolbarHeight - MediaQuery.of(context).padding.top,
            initialContent: gsatUrl,
            initialSourceType: SourceType.url,
            javascriptMode: JavascriptMode.unrestricted,
            onWebViewCreated: (controller) {
              _controller = controller;
            },
            onPageStarted: (url) {
              setState(() => _isLoading = true);
            },
            onPageFinished: (url) {
              setState(() => _isLoading = false);
              // Auto-populate fields if we have scanned data
              if (_scannedBoxId != null) {
                _autoPopulateBoxId(_scannedBoxId!);
              }
              if (_scannedPin != null) {
                _autoPopulatePin(_scannedPin!);
              }
            },
          ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(
                  color: primaryColor,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: kIsWeb
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'scanPin',
                  onPressed: _scanSecurityCode,
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  tooltip: 'Scan Security Code/PIN',
                  child: const Icon(Icons.pin),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.extended(
                  heroTag: 'scanBoxId',
                  onPressed: _scanBoxId,
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan Box ID'),
                ),
              ],
            ),
    );
  }
}
