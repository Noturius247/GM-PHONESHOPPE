import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class SerialScannerPage extends StatefulWidget {
  final String serviceType;
  final String serviceName;
  final Color primaryColor;

  const SerialScannerPage({
    super.key,
    required this.serviceType,
    required this.serviceName,
    required this.primaryColor,
  });

  @override
  State<SerialScannerPage> createState() => _SerialScannerPageState();
}

class _SerialScannerPageState extends State<SerialScannerPage> {
  MobileScannerController cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _isScanning = true;
  String? _scannedCode;

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
        setState(() {
          _isScanning = false;
          _scannedCode = barcode.rawValue;
        });

        // Return the scanned code to the previous page
        Navigator.pop(context, _scannedCode);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Scan ${widget.serviceName} Serial'),
        backgroundColor: widget.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: cameraController.torchState,
              builder: (context, state, child) {
                return Icon(
                  state == TorchState.on ? Icons.flash_on : Icons.flash_off,
                );
              },
            ),
            onPressed: () => cameraController.toggleTorch(),
          ),
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: cameraController.cameraFacingState,
              builder: (context, state, child) {
                return Icon(
                  state == CameraFacing.front
                      ? Icons.camera_front
                      : Icons.camera_rear,
                );
              },
            ),
            onPressed: () => cameraController.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: cameraController,
            onDetect: _onDetect,
          ),
          // Scanning overlay
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
            ),
            child: Stack(
              children: [
                // Transparent scanning area
                Center(
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: widget.primaryColor,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.transparent,
                    ),
                  ),
                ),
                // Cut out the scanning area from the overlay
                ClipPath(
                  clipper: ScannerOverlayClipper(),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          // Instructions
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: widget.primaryColor.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text(
                    'Point camera at barcode or QR code',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () => _showManualEntryDialog(),
                  icon: const Icon(Icons.keyboard, color: Colors.white),
                  label: const Text(
                    'Enter manually',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showManualEntryDialog() {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Serial Number'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter serial number',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                Navigator.pop(context); // Close dialog
                Navigator.pop(this.context, controller.text); // Return serial
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: widget.primaryColor,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}

// Custom clipper to create the scanning window
class ScannerOverlayClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();

    // Full screen rectangle
    path.addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Scanning window (to be cut out)
    final scanRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: 280,
        height: 280,
      ),
      const Radius.circular(16),
    );

    path.addRRect(scanRect);
    path.fillType = PathFillType.evenOdd;

    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
