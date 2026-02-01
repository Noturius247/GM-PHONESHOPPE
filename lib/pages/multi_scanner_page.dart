import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannedItem {
  final String code;
  final String label;
  final DateTime scannedAt;

  ScannedItem({
    required this.code,
    required this.label,
    required this.scannedAt,
  });
}

class MultiScanResult {
  final String? ccaNumber;
  final String? serialNumber;
  final String? stbId;
  final List<ScannedItem> allScannedItems;

  MultiScanResult({
    this.ccaNumber,
    this.serialNumber,
    this.stbId,
    required this.allScannedItems,
  });
}

class MultiScannerPage extends StatefulWidget {
  final String serviceType;
  final String serviceName;
  final Color primaryColor;
  /// Callback for continuous inventory scanning — called each time a code is detected.
  /// When provided, the scanner stays open instead of popping.
  final void Function(String code)? onInventoryScan;

  const MultiScannerPage({
    super.key,
    required this.serviceType,
    required this.serviceName,
    required this.primaryColor,
    this.onInventoryScan,
  });

  @override
  State<MultiScannerPage> createState() => _MultiScannerPageState();
}

class _MultiScannerPageState extends State<MultiScannerPage> {
  MobileScannerController cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
    formats: [
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.codabar,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.itf,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.qrCode,
      BarcodeFormat.dataMatrix,
      BarcodeFormat.aztec,
      BarcodeFormat.pdf417,
    ],
  );

  final List<ScannedItem> _scannedItems = [];
  bool _isScanning = false; // Start with scanning disabled
  bool _scanButtonPressed = false; // Track if scan button is pressed
  String? _lastScannedCode;
  String _selectedLabel = 'CCA No.';
  DateTime? _lastScanTime; // Cooldown for continuous scanning
  int _continuousScanCount = 0; // Track items added in continuous mode

  final List<String> _labelOptions = ['CCA No.', 'Serial No.', 'STB ID', 'Other'];

  bool get _isContinuousMode => widget.onInventoryScan != null;

  @override
  void initState() {
    super.initState();
    // Auto-start scanning in continuous inventory mode
    if (_isContinuousMode) {
      _isScanning = true;
      _scanButtonPressed = true;
    }
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  String _autoDetectLabel(String code) {
    // CCA is typically 11 digits numeric only (e.g., 02761974110)
    if (RegExp(r'^[0-9]{11}$').hasMatch(code)) {
      return 'CCA No.';
    }
    // STB ID is typically 11 digits numeric (e.g., 00851456960)
    if (RegExp(r'^[0-9]{11}$').hasMatch(code)) {
      return 'STB ID';
    }
    // Serial often has letters mixed with numbers (e.g., 8222a73012504037339)
    if (RegExp(r'^[a-zA-Z0-9]+$').hasMatch(code) && RegExp(r'[a-zA-Z]').hasMatch(code)) {
      return 'Serial No.';
    }
    // Default to CCA for pure numeric
    if (RegExp(r'^[0-9]+$').hasMatch(code)) {
      return 'CCA No.';
    }
    return 'Other';
  }

  void _onDetect(BarcodeCapture capture) {
    // Only process if scanning is enabled (button pressed)
    if (!_isScanning || !_scanButtonPressed) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
        // Check if barcode is within the scanning box area
        if (!_isBarcodeInScanArea(barcode, capture.size)) {
          continue;
        }

        final code = barcode.rawValue!;

        // Continuous inventory mode — call callback, stay open, keep scanning
        if (_isContinuousMode) {
          final now = DateTime.now();
          // Cooldown: skip same code within 3s, any code within 1s
          if (_lastScanTime != null && now.difference(_lastScanTime!).inMilliseconds < 1000) {
            continue;
          }
          if (code == _lastScannedCode && _lastScanTime != null && now.difference(_lastScanTime!).inSeconds < 3) {
            continue;
          }

          _lastScanTime = now;
          _lastScannedCode = code;
          setState(() => _continuousScanCount++);

          widget.onInventoryScan!(code);
          continue;
        }

        // Don't add duplicates
        if (_scannedItems.any((item) => item.code == code) || code == _lastScannedCode) {
          continue;
        }

        setState(() {
          _isScanning = false;
          _scanButtonPressed = false;
          _lastScannedCode = code;
          _selectedLabel = _autoDetectLabel(code);
        });

        // Show confirmation dialog
        _showConfirmScanDialog(code);
        break;
      }
    }
  }

  bool _isBarcodeInScanArea(Barcode barcode, Size? imageSize) {
    // Accept barcode if no position info available (don't be too strict)
    if (imageSize == null || imageSize.width == 0 || imageSize.height == 0) {
      return true;
    }

    // Accept barcode if no corner data (don't be too strict)
    if (barcode.corners.isEmpty) {
      return true;
    }

    // Get the barcode center point
    final corners = barcode.corners;
    double centerX = 0;
    double centerY = 0;
    for (final corner in corners) {
      centerX += corner.dx;
      centerY += corner.dy;
    }
    centerX /= corners.length;
    centerY /= corners.length;

    // Normalize to 0-1 range
    final normalizedX = centerX / imageSize.width;
    final normalizedY = centerY / imageSize.height;

    // More lenient bounds - accept barcodes in most of the frame
    const double horizontalMargin = 0.05; // 5% margin on sides
    const double verticalMin = 0.10; // Top 10% excluded
    const double verticalMax = 0.90; // Bottom 10% excluded

    final isInHorizontalBounds = normalizedX >= horizontalMargin && normalizedX <= (1 - horizontalMargin);
    final isInVerticalBounds = normalizedY >= verticalMin && normalizedY <= verticalMax;

    return isInHorizontalBounds && isInVerticalBounds;
  }

  void _startScanning() {
    setState(() {
      _isScanning = true;
      _scanButtonPressed = true;
    });
  }

  void _showConfirmScanDialog(String code) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 28),
              const SizedBox(width: 12),
              const Text(
                'Code Scanned',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Scanned Value:',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.primaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: widget.primaryColor.withValues(alpha: 0.5)),
                ),
                child: SelectableText(
                  code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'What is this code?',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedLabel,
                dropdownColor: const Color(0xFF2A1A1A),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.1),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: widget.primaryColor),
                  ),
                ),
                items: _labelOptions.map((label) {
                  return DropdownMenuItem(
                    value: label,
                    child: Text(label),
                  );
                }).toList(),
                onChanged: (value) {
                  setDialogState(() => _selectedLabel = value!);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _isScanning = false;
                  _scanButtonPressed = false;
                  _lastScannedCode = null;
                });
              },
              child: Text(
                'Discard',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _addScannedItem(code, _selectedLabel);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _addScannedItem(String code, String label) {
    setState(() {
      _scannedItems.add(ScannedItem(
        code: code,
        label: label,
        scannedAt: DateTime.now(),
      ));
      _isScanning = false;
      _scanButtonPressed = false;
      _lastScannedCode = null;
    });
  }

  void _removeScannedItem(int index) {
    setState(() {
      _scannedItems.removeAt(index);
    });
  }

  void _finishScanning() {
    // Organize scanned items by label
    String? ccaNumber;
    String? serialNumber;
    String? stbId;

    for (final item in _scannedItems) {
      switch (item.label) {
        case 'CCA No.':
          ccaNumber = item.code;
          break;
        case 'Serial No.':
          serialNumber = item.code;
          break;
        case 'STB ID':
          stbId = item.code;
          break;
      }
    }

    final result = MultiScanResult(
      ccaNumber: ccaNumber,
      serialNumber: serialNumber,
      stbId: stbId,
      allScannedItems: _scannedItems,
    );

    Navigator.pop(context, result);
  }

  void _showManualEntryDialog() {
    final TextEditingController controller = TextEditingController();
    String manualLabel = 'CCA No.';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Enter Code Manually',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Enter code',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  prefixIcon: Icon(Icons.qr_code, color: widget.primaryColor),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.1),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: widget.primaryColor),
                  ),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: manualLabel,
                dropdownColor: const Color(0xFF2A1A1A),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Code Type',
                  labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.1),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: widget.primaryColor),
                  ),
                ),
                items: _labelOptions.map((label) {
                  return DropdownMenuItem(
                    value: label,
                    child: Text(label),
                  );
                }).toList(),
                onChanged: (value) {
                  setDialogState(() => manualLabel = value!);
                },
              ),
            ],
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
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  Navigator.pop(context);
                  _addScannedItem(controller.text, manualLabel);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isContinuousMode) return _buildContinuousLayout();

    return _buildDefaultLayout();
  }

  Widget _buildContinuousLayout() {
    return Scaffold(
      appBar: AppBar(
        title: Text('Scan ${widget.serviceName}'),
        backgroundColor: widget.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: cameraController.torchState,
              builder: (context, state, child) {
                return Icon(state == TorchState.on ? Icons.flash_on : Icons.flash_off);
              },
            ),
            onPressed: () => cameraController.toggleTorch(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Full camera preview
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  controller: cameraController,
                  onDetect: _onDetect,
                ),
                // Scanning overlay
                Container(
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3)),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.green, width: 2),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                ),
                // Scan count indicator
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _continuousScanCount > 0
                            ? Colors.green.withValues(alpha: 0.9)
                            : Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _continuousScanCount > 0
                            ? '$_continuousScanCount item${_continuousScanCount != 1 ? 's' : ''} scanned'
                            : 'Point at barcode to scan',
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Done button
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF2A1A1A),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check),
                label: Text(_continuousScanCount > 0
                    ? 'Done ($_continuousScanCount scanned)'
                    : 'Close'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultLayout() {
    return Scaffold(
      appBar: AppBar(
        title: Text('Scan ${widget.serviceName} Codes'),
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
      body: Column(
        children: [
          // Camera preview area - 4:3 aspect ratio
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              children: [
                MobileScanner(
                  controller: cameraController,
                  onDetect: _onDetect,
                ),
                // Scanning overlay with horizontal scanning area
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                  ),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _isScanning ? Colors.green : widget.primaryColor,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                ),
                // Scanning indicator
                if (_isScanning)
                  Positioned(
                    top: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Scanning...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Scan button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF2A1A1A),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isScanning ? null : _startScanning,
                icon: Icon(_isScanning ? Icons.hourglass_top : Icons.qr_code_scanner),
                label: Text(_isScanning ? 'Scanning...' : 'Tap to Scan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isScanning ? Colors.green : widget.primaryColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.green,
                  disabledForegroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          // Scanned items list
          Expanded(
            child: Container(
              color: const Color(0xFF1A1A1A),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A1A1A),
                      border: Border(
                        bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Scanned Codes (${_scannedItems.length})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _showManualEntryDialog,
                          icon: const Icon(Icons.keyboard, size: 18),
                          label: const Text('Manual'),
                          style: TextButton.styleFrom(
                            foregroundColor: widget.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // List of scanned items
                  Expanded(
                    child: _scannedItems.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.qr_code_scanner,
                                  size: 48,
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Scan barcodes to add them here',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _scannedItems.length,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemBuilder: (context, index) {
                              final item = _scannedItems[index];
                              return Dismissible(
                                key: Key('${item.code}-${item.scannedAt}'),
                                background: Container(
                                  color: Colors.red,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 16),
                                  child: const Icon(Icons.delete, color: Colors.white),
                                ),
                                direction: DismissDirection.endToStart,
                                onDismissed: (_) => _removeScannedItem(index),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: widget.primaryColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: widget.primaryColor.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: widget.primaryColor,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          item.label,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          item.code,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontFamily: 'monospace',
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.close,
                                          color: Colors.white.withValues(alpha: 0.5),
                                          size: 18,
                                        ),
                                        onPressed: () => _removeScannedItem(index),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  // Bottom buttons
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A1A1A),
                      border: Border(
                        top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                            label: const Text('Cancel'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white.withValues(alpha: 0.7),
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: _scannedItems.isEmpty ? null : _finishScanning,
                            icon: const Icon(Icons.check),
                            label: Text(
                              _scannedItems.isEmpty
                                  ? 'Scan to continue'
                                  : 'Done (${_scannedItems.length})',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.primaryColor,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey.withValues(alpha: 0.3),
                              disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
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
        ],
      ),
    );
  }
}
