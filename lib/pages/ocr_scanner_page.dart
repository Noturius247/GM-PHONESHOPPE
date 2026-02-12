import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';

/// Data class to hold all extracted OCR fields
class OcrExtractedData {
  String? serialNumber;
  String? ccaNumber;
  String? boxNumber;
  String? name;
  String? accountNumber;
  String? address;
  String? pin;

  OcrExtractedData({
    this.serialNumber,
    this.ccaNumber,
    this.boxNumber,
    this.name,
    this.accountNumber,
    this.address,
    this.pin,
  });

  bool get hasAnyData =>
      serialNumber != null ||
      ccaNumber != null ||
      boxNumber != null ||
      name != null ||
      accountNumber != null ||
      address != null ||
      pin != null;

  Map<String, String?> toMap() => {
        'serialNumber': serialNumber,
        'ccaNumber': ccaNumber,
        'boxNumber': boxNumber,
        'name': name,
        'accountNumber': accountNumber,
        'address': address,
        'pin': pin,
      };
}

class OcrScannerPage extends StatefulWidget {
  final String serviceName;
  final Color primaryColor;
  final bool securityCodeOnly;
  final String? serviceType; // 'gsat', 'sky', 'cignal', etc.
  /// Callback for continuous inventory scanning — called each time a serial is detected.
  /// When provided, the scanner stays open and auto-retakes after a successful scan.
  final void Function(String serial)? onInventoryScan;

  const OcrScannerPage({
    super.key,
    required this.serviceName,
    required this.primaryColor,
    this.securityCodeOnly = false,
    this.serviceType,
    this.onInventoryScan,
  });

  @override
  State<OcrScannerPage> createState() => _OcrScannerPageState();
}

class _OcrScannerPageState extends State<OcrScannerPage> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  final TextRecognizer _textRecognizer = TextRecognizer();
  final BarcodeScanner _barcodeScanner = BarcodeScanner(formats: [
    BarcodeFormat.qrCode,
    BarcodeFormat.code128,
    BarcodeFormat.code39,
    BarcodeFormat.code93,
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upca,
    BarcodeFormat.upce,
    BarcodeFormat.itf,
    BarcodeFormat.codabar,
    BarcodeFormat.dataMatrix,
  ]);
  final ImagePicker _picker = ImagePicker();

  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  bool _showResults = false;
  File? _capturedImage;
  String? _recognizedText;
  OcrExtractedData _extractedData = OcrExtractedData();
  List<String> _detectedSerials = [];

  // Controllers for editable fields
  final _serialController = TextEditingController();
  final _ccaController = TextEditingController();
  final _boxNumberController = TextEditingController();
  final _nameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _addressController = TextEditingController();
  final _pinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _textRecognizer.close();
    _barcodeScanner.close();
    _serialController.dispose();
    _ccaController.dispose();
    _boxNumberController.dispose();
    _nameController.dispose();
    _accountNumberController.dispose();
    _addressController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No camera available'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      _cameraController = CameraController(
        _cameras![0],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initializing camera: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _captureAndProcess() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final XFile imageFile = await _cameraController!.takePicture();
      final File file = File(imageFile.path);

      setState(() {
        _capturedImage = file;
      });

      await _processImage(file);
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error capturing image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _capturedImage = File(pickedFile.path);
          _isProcessing = true;
        });
        await _processImage(File(pickedFile.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _processImage(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);

      // Run OCR text recognition and QR/barcode scanning in parallel
      final results = await Future.wait([
        _textRecognizer.processImage(inputImage),
        _barcodeScanner.processImage(inputImage),
      ]);

      final recognizedText = results[0] as RecognizedText;
      final barcodes = results[1] as List<Barcode>;

      // Extract QR code serial numbers (from label format: SKU|Name|Price)
      final qrSerials = <String>[];
      for (final barcode in barcodes) {
        if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
          final qrValue = barcode.rawValue!;
          // Check if it's our label format: SKU|Name|Price
          if (qrValue.contains('|')) {
            final parts = qrValue.split('|');
            final serial = parts[0].trim();
            if (serial.isNotEmpty) {
              qrSerials.add(serial);
            }
          } else {
            // Plain QR code — use the raw value as serial
            qrSerials.add(qrValue.trim());
          }
        }
      }

      final extractedData = _extractAllFields(recognizedText.text);
      final serials = _extractSerialNumbers(recognizedText.text);

      // Merge QR-detected serials (prioritize QR over OCR)
      final allSerials = <String>[...qrSerials];
      for (final s in serials) {
        if (!allSerials.contains(s)) {
          allSerials.add(s);
        }
      }

      // If QR found a serial and OCR didn't, use QR serial
      if (qrSerials.isNotEmpty && extractedData.serialNumber == null) {
        extractedData.serialNumber = qrSerials.first;
      }

      setState(() {
        _recognizedText = recognizedText.text;
        if (qrSerials.isNotEmpty) {
          _recognizedText = '[QR Detected: ${qrSerials.join(", ")}]\n\n$_recognizedText';
        }
        _extractedData = extractedData;
        _detectedSerials = allSerials;
        _isProcessing = false;
        _showResults = true;

        // Update controllers with extracted data
        // In securityCodeOnly mode, put security code in serial number field
        if (widget.securityCodeOnly) {
          _serialController.text = extractedData.pin ?? '';
        } else {
          _serialController.text = extractedData.serialNumber ?? '';
        }
        _ccaController.text = extractedData.ccaNumber ?? '';
        _boxNumberController.text = extractedData.boxNumber ?? '';
        _nameController.text = extractedData.name ?? '';
        _accountNumberController.text = extractedData.accountNumber ?? '';
        _addressController.text = extractedData.address ?? '';
        _pinController.text = extractedData.pin ?? '';
      });

      // For inventory_serial mode: prioritize QR value as serial when available
      if (widget.serviceType == 'inventory_serial' && qrSerials.isNotEmpty) {
        extractedData.serialNumber = qrSerials.first;
        _serialController.text = qrSerials.first;
      }

      // Auto-return/callback for inventory_serial mode if a serial was found
      final autoReturnSerial = extractedData.serialNumber ?? (allSerials.isNotEmpty ? allSerials.first : null);
      if (widget.serviceType == 'inventory_serial' && autoReturnSerial != null && autoReturnSerial.isNotEmpty) {
        if (widget.onInventoryScan != null) {
          // Continuous mode — call callback and reset for next scan
          widget.onInventoryScan!(autoReturnSerial);
          if (mounted) _retake();
          return;
        } else if (mounted) {
          Navigator.pop(context, OcrExtractedData(serialNumber: autoReturnSerial));
          return;
        }
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _retake() {
    setState(() {
      _showResults = false;
      _capturedImage = null;
      _recognizedText = null;
      _extractedData = OcrExtractedData();
      _detectedSerials = [];
      _serialController.clear();
      _ccaController.clear();
      _boxNumberController.clear();
      _nameController.clear();
      _accountNumberController.clear();
      _addressController.clear();
      _pinController.clear();
    });
  }

  OcrExtractedData _extractAllFields(String text) {
    final data = OcrExtractedData();
    final lines = text.split(RegExp(r'[\n\r]+'));

    // First, try label-based extraction
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final upperLine = line.toUpperCase();

      // Extract Serial Number (S/N)
      if (data.serialNumber == null) {
        if (upperLine.contains('S/N') ||
            upperLine.contains('SERIAL') ||
            upperLine.contains('SN:') ||
            upperLine.contains('SN ')) {
          data.serialNumber = _extractValueAfterLabel(line, [
            'S/N',
            'SN:',
            'SN',
            'SERIAL NO',
            'SERIAL NUMBER',
            'SERIAL:',
            'SERIAL'
          ]);
        }
      }

      // Extract CCA Number (separate from Serial)
      if (data.ccaNumber == null) {
        if (upperLine.contains('CCA')) {
          data.ccaNumber = _extractValueAfterLabel(line, [
            'CCA NO.',
            'CCA NO',
            'CCA:',
            'CCA #',
            'CCA'
          ]);
        }
      }

      // Extract Box Number
      if (data.boxNumber == null) {
        if (upperLine.contains('BOX NO') ||
            upperLine.contains('BOX #') ||
            upperLine.contains('BOX:') ||
            upperLine.contains('BOX NUMBER')) {
          data.boxNumber = _extractValueAfterLabel(
              line, ['BOX NO.', 'BOX NO', 'BOX #', 'BOX:', 'BOX NUMBER', 'BOX']);
        }
      }

      // Extract Name
      if (data.name == null) {
        if (upperLine.contains('NAME:') ||
            upperLine.contains('CUSTOMER:') ||
            upperLine.contains('CUSTOMER NAME') ||
            upperLine.contains('SUBSCRIBER:') ||
            upperLine.contains('SUBSCRIBER NAME') ||
            upperLine.startsWith('NAME')) {
          data.name = _extractValueAfterLabel(line, [
            'CUSTOMER NAME:',
            'CUSTOMER NAME',
            'SUBSCRIBER NAME:',
            'SUBSCRIBER NAME',
            'CUSTOMER:',
            'SUBSCRIBER:',
            'NAME:'
          ]);
        }
      }

      // Extract Account Number
      if (data.accountNumber == null) {
        if (upperLine.contains('ACCOUNT') ||
            upperLine.contains('ACCT') ||
            upperLine.contains('ACC NO') ||
            upperLine.contains('ACC #')) {
          data.accountNumber = _extractValueAfterLabel(line, [
            'ACCOUNT NUMBER:',
            'ACCOUNT NUMBER',
            'ACCOUNT NO.:',
            'ACCOUNT NO:',
            'ACCOUNT NO.',
            'ACCOUNT NO',
            'ACCOUNT:',
            'ACCT NO.:',
            'ACCT NO:',
            'ACCT NO.',
            'ACCT NO',
            'ACCT:',
            'ACCT #:',
            'ACCT #',
            'ACC NO:',
            'ACC NO',
            'ACC #'
          ]);
        }
      }

      // Extract Address
      if (data.address == null) {
        if (upperLine.contains('ADDRESS:') ||
            upperLine.contains('ADDR:') ||
            upperLine.contains('LOCATION:') ||
            upperLine.startsWith('ADDRESS')) {
          String? addr = _extractValueAfterLabel(
              line, ['ADDRESS:', 'ADDR:', 'LOCATION:', 'ADDRESS']);

          if (addr != null &&
              addr.length < 15 &&
              i + 1 < lines.length &&
              !_isLabelLine(lines[i + 1])) {
            addr = '$addr ${lines[i + 1].trim()}';
          }
          data.address = addr;
        }
      }

      // Extract Security Code / PIN (label on one line, numbers on next line)
      if (data.pin == null) {
        if (upperLine.contains('SECURITY CODE') ||
            upperLine.contains('SECURITY') ||
            upperLine.contains('SEC CODE') ||
            upperLine.contains('SEC. CODE')) {
          // Check next line for the numbers
          if (i + 1 < lines.length) {
            final nextLine = lines[i + 1].trim();
            // Extract only digits from next line
            final digits = nextLine.replaceAll(RegExp(r'[^0-9]'), '');
            if (digits.isNotEmpty) {
              data.pin = digits;
            }
          }
        }
      }
    }

    // If no labeled data found, try label-less extraction for handwritten receipts
    if (!data.hasAnyData) {
      _extractLabellessData(text, data);
    }

    if (data.serialNumber == null) {
      final serials = _extractSerialNumbers(text);
      if (serials.isNotEmpty) {
        data.serialNumber = serials.first;
      }
    }

    // For inventory_serial mode: if still no serial, use any detected number as serial
    if (widget.serviceType == 'inventory_serial' && data.serialNumber == null) {
      final numberPattern = RegExp(r'\d{3,}');
      final match = numberPattern.firstMatch(text);
      if (match != null) {
        data.serialNumber = match.group(0);
      }
    }

    return data;
  }

  /// Extract data from handwritten receipts without labels
  /// Expected format (based on receipt image):
  /// Line 1: CCA number / phone number (e.g., 02780795236)
  /// Line 2: Box number, Name, Date (e.g., 7.07 Ruel M. Mendiog 12/5/20)
  /// Line 3: Box number, "Acct." Account Number, Address, Date (e.g., 113 Acct. 117807798 Podacion Cawayan 29/020)
  void _extractLabellessData(String text, OcrExtractedData data) {
    final lines = text.split(RegExp(r'[\n\r]+'));
    final List<String> cleanLines = [];

    // Clean and filter lines
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        cleanLines.add(trimmed);
      }
    }

    // Phone number pattern: 10-11 digits, possibly starting with 0
    final phonePattern = RegExp(r'^0?\d{10,11}$');

    // Account number pattern: "Acct" or "Acct." followed by numbers
    final acctPattern = RegExp(r'[Aa]cct\.?\s*(\d+)', caseSensitive: false);

    // Date pattern: various formats like 12/5/20, 29/020, etc.
    final datePattern = RegExp(r'\d{1,2}/\d{1,2}/?\d{0,4}');

    // Name pattern: text with letters (possibly with M. or similar initials)
    final namePattern = RegExp(r'[A-Za-z]+(?:\s+[A-Za-z]\.?)?\s+[A-Za-z]+');

    // Box number pattern: numbers like 7.07, 113, etc. at start of line
    final boxNumberPattern = RegExp(r'^([\d.]+)\s+');

    for (int i = 0; i < cleanLines.length; i++) {
      final line = cleanLines[i];

      // Extract phone number as CCA number (line with just digits, 10-11 chars)
      final digitsOnly = line.replaceAll(RegExp(r'\D'), '');
      if (data.ccaNumber == null && phonePattern.hasMatch(digitsOnly)) {
        data.ccaNumber = digitsOnly;
        continue;
      }

      // Extract box number from start of line (e.g., 7.07, 113)
      // If multiple box numbers found, combine them with "/"
      final boxMatch = boxNumberPattern.firstMatch(line);
      if (boxMatch != null) {
        final boxNum = boxMatch.group(1);
        if (data.boxNumber == null) {
          data.boxNumber = boxNum;
        } else if (boxNum != null && !data.boxNumber!.contains(boxNum)) {
          data.boxNumber = '${data.boxNumber}/$boxNum';
        }
      }

      // Extract account number with "Acct" prefix
      final acctMatch = acctPattern.firstMatch(line);
      if (data.accountNumber == null && acctMatch != null) {
        data.accountNumber = acctMatch.group(1);

        // Try to extract address from the same line (text after account number, before date)
        String afterAcct = line.substring(acctMatch.end).trim();
        // Remove date from the end
        afterAcct = afterAcct.replaceAll(datePattern, '').trim();
        if (afterAcct.isNotEmpty && data.address == null) {
          data.address = afterAcct;
        }
        continue;
      }

      // Try to extract name from line with box number
      // Format: "7.07 Ruel M. Mendiog 12/5/20"
      if (data.name == null) {
        String workingLine = line;

        // Remove box number from start
        workingLine = workingLine.replaceFirst(boxNumberPattern, '').trim();

        // Remove date from end
        workingLine = workingLine.replaceAll(datePattern, '').trim();

        // Remove "Acct." and account number if present
        workingLine = workingLine.replaceAll(acctPattern, '').trim();

        // Check if remaining text looks like a name
        final nameMatch = namePattern.firstMatch(workingLine);
        if (nameMatch != null) {
          data.name = nameMatch.group(0)?.trim();
        } else if (workingLine.isNotEmpty &&
                   workingLine.contains(RegExp(r'[A-Za-z]')) &&
                   !workingLine.contains(RegExp(r'^\d+$'))) {
          // If no formal name pattern but contains letters, use it
          data.name = workingLine;
        }
      }
    }

    // Alternative: Extract account number from any line with long digit sequence (9+ digits)
    if (data.accountNumber == null) {
      final longNumPattern = RegExp(r'\b(\d{9,12})\b');
      for (final line in cleanLines) {
        final match = longNumPattern.firstMatch(line);
        if (match != null) {
          final num = match.group(1)!;
          // Don't use if it's already the CCA number
          if (num != data.ccaNumber) {
            data.accountNumber = num;
            break;
          }
        }
      }
    }
  }

  bool _isLabelLine(String line) {
    final upper = line.toUpperCase().trim();
    return upper.contains('NAME:') ||
        upper.contains('ADDRESS:') ||
        upper.contains('ACCOUNT') ||
        upper.contains('SERIAL') ||
        upper.contains('BOX') ||
        upper.contains('S/N') ||
        upper.contains('CCA');
  }

  String? _extractValueAfterLabel(String line, List<String> labels) {
    String workingLine = line;

    for (final label in labels) {
      final upperLine = workingLine.toUpperCase();
      final labelIndex = upperLine.indexOf(label.toUpperCase());

      if (labelIndex != -1) {
        String value = workingLine.substring(labelIndex + label.length).trim();
        value = value.replaceFirst(RegExp(r'^[:\s=]+'), '').trim();

        if (value.isNotEmpty) {
          return value;
        }
      }
    }

    return null;
  }

  List<String> _extractSerialNumbers(String text) {
    final List<String> serials = [];
    final lines = text.split(RegExp(r'[\n\r]+'));

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.toUpperCase().contains('S/N') ||
          trimmed.toUpperCase().contains('SERIAL') ||
          trimmed.toUpperCase().contains('CCA') ||
          trimmed.toUpperCase().contains('SN:') ||
          trimmed.toUpperCase().contains('SN ')) {
        final parts = trimmed.split(RegExp(r'[:\s]+'));
        for (int i = 0; i < parts.length; i++) {
          if (parts[i].toUpperCase() == 'S/N' ||
              parts[i].toUpperCase() == 'SN' ||
              parts[i].toUpperCase() == 'SERIAL' ||
              parts[i].toUpperCase() == 'CCA') {
            if (i + 1 < parts.length && parts[i + 1].length >= 4) {
              serials.add(parts[i + 1]);
            }
          }
        }
      }

      final alphanumericPattern =
          RegExp(r'^[A-Z0-9]{3,20}$', caseSensitive: false);
      if (alphanumericPattern.hasMatch(trimmed)) {
        if (!serials.contains(trimmed)) {
          serials.add(trimmed);
        }
      }

      final serialPattern =
          RegExp(r'[A-Z0-9]{2,}[-][A-Z0-9]{2,}[-]?[A-Z0-9]*', caseSensitive: false);
      final matches = serialPattern.allMatches(trimmed);
      for (final match in matches) {
        final found = match.group(0)!;
        if (!serials.contains(found) && found.length >= 3) {
          serials.add(found);
        }
      }
    }

    return serials.toSet().toList();
  }

  void _useExtractedData() {
    // Build result based on mode
    OcrExtractedData result;

    if (widget.securityCodeOnly) {
      // Security code only mode - serial controller contains the security code
      result = OcrExtractedData(
        pin: _serialController.text.isNotEmpty ? _serialController.text : null,
      );
    } else if (widget.serviceType == 'gsat_boxid' || widget.serviceType == 'inventory_serial' || widget.serviceType == 'transaction_id') {
      // GSAT Box ID or Inventory Serial only mode - only return serial number
      result = OcrExtractedData(
        serialNumber: _serialController.text.isNotEmpty ? _serialController.text : null,
      );
    } else {
      // Full mode - return all fields
      result = OcrExtractedData(
        serialNumber:
            _serialController.text.isNotEmpty ? _serialController.text : null,
        ccaNumber:
            _ccaController.text.isNotEmpty ? _ccaController.text : null,
        boxNumber: _boxNumberController.text.isNotEmpty
            ? _boxNumberController.text
            : null,
        name: _nameController.text.isNotEmpty ? _nameController.text : null,
        accountNumber: _accountNumberController.text.isNotEmpty
            ? _accountNumberController.text
            : null,
        address:
            _addressController.text.isNotEmpty ? _addressController.text : null,
        pin: _pinController.text.isNotEmpty ? _pinController.text : null,
      );
    }

    // Validation based on mode
    if (widget.securityCodeOnly) {
      if (result.pin == null || result.pin!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a Security Code'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    } else if (widget.serviceType == 'gsat_boxid' || widget.serviceType == 'inventory_serial' || widget.serviceType == 'transaction_id') {
      // For GSAT Box ID or Inventory Serial, only require the serial number
      if (result.serialNumber == null || result.serialNumber!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.serviceType == 'inventory_serial'
                ? 'Please enter a Serial Number'
                : widget.serviceType == 'transaction_id'
                    ? 'Please enter a Transaction ID'
                    : 'Please enter a Box ID / Serial Number'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    } else {
      // Require at least Serial OR CCA number
      if ((result.serialNumber == null || result.serialNumber!.isEmpty) &&
          (result.ccaNumber == null || result.ccaNumber!.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a Serial Number or CCA Number'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    Navigator.of(context).pop(result);
  }

  void _selectSerial(String serial) {
    setState(() {
      _serialController.text = serial;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _showResults ? _buildResultsView() : _buildCameraView(),
    );
  }

  Widget _buildCameraView() {
    return Stack(
      children: [
        // Camera preview
        if (_isCameraInitialized && _cameraController != null)
          Positioned.fill(
            child: CameraPreview(_cameraController!),
          )
        else
          const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),

        // Dark overlay with rectangular cutout
        if (_isCameraInitialized)
          Positioned.fill(
            child: CustomPaint(
              painter: ScannerOverlayPainter(
                borderColor: widget.primaryColor,
                overlayColor: Colors.black.withValues(alpha: 0.6),
              ),
            ),
          ),

        // Top bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      'OCR Scanner - ${widget.serviceName}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.photo_library, color: Colors.white),
                    onPressed: _pickFromGallery,
                    tooltip: 'Pick from Gallery',
                  ),
                ],
              ),
            ),
          ),
        ),

        // Instructions
        Positioned(
          top: MediaQuery.of(context).size.height * 0.18,
          left: 20,
          right: 20,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).size.width < 360 ? 12 : 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Position the document or QR code inside the frame',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: MediaQuery.of(context).size.width < 360 ? 12 : 14,
              ),
            ),
          ),
        ),

        // Processing indicator
        if (_isProcessing)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.7),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: widget.primaryColor),
                    const SizedBox(height: 16),
                    const Text(
                      'Processing image...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Capture button
        if (_isCameraInitialized && !_isProcessing)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _captureAndProcess,
                child: Container(
                  width: MediaQuery.of(context).size.width < 360 ? 70 : 80,
                  height: MediaQuery.of(context).size.width < 360 ? 70 : 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: Center(
                    child: Container(
                      width: MediaQuery.of(context).size.width < 360 ? 56 : 64,
                      height: MediaQuery.of(context).size.width < 360 ? 56 : 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.primaryColor,
                      ),
                      child: const Icon(
                        Icons.document_scanner,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Corner decorations for the scan area
        if (_isCameraInitialized) _buildCornerDecorations(),
      ],
    );
  }

  Widget _buildCornerDecorations() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final rectWidth = screenWidth * 0.9;
    final rectHeight = screenHeight * 0.225;
    final left = (screenWidth - rectWidth) / 2;
    final top = (screenHeight - rectHeight) / 2 - 30;
    const cornerSize = 30.0;
    const cornerWidth = 4.0;

    return Stack(
      children: [
        // Top-left corner
        Positioned(
          left: left,
          top: top,
          child: _buildCorner(cornerSize, cornerWidth, topLeft: true),
        ),
        // Top-right corner
        Positioned(
          right: left,
          top: top,
          child: _buildCorner(cornerSize, cornerWidth, topRight: true),
        ),
        // Bottom-left corner
        Positioned(
          left: left,
          bottom: screenHeight - top - rectHeight,
          child: _buildCorner(cornerSize, cornerWidth, bottomLeft: true),
        ),
        // Bottom-right corner
        Positioned(
          right: left,
          bottom: screenHeight - top - rectHeight,
          child: _buildCorner(cornerSize, cornerWidth, bottomRight: true),
        ),
      ],
    );
  }

  Widget _buildCorner(double size, double width,
      {bool topLeft = false,
      bool topRight = false,
      bool bottomLeft = false,
      bool bottomRight = false}) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: CornerPainter(
          color: widget.primaryColor,
          strokeWidth: width,
          topLeft: topLeft,
          topRight: topRight,
          bottomLeft: bottomLeft,
          bottomRight: bottomRight,
        ),
      ),
    );
  }

  Widget _buildResultsView() {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0A0A),
      appBar: AppBar(
        backgroundColor: widget.primaryColor,
        title: const Text('Scan Results'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _retake,
        ),
        actions: [
          TextButton.icon(
            onPressed: _retake,
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: const Text('Retake', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(MediaQuery.of(context).size.width < 360 ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Captured image preview
            if (_capturedImage != null)
              Container(
                height: MediaQuery.of(context).size.height < 700 ? 120 : 180,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: widget.primaryColor),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    _capturedImage!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),

            // Detected serial numbers (quick select) - hide in securityCodeOnly mode
            if (_detectedSerials.isNotEmpty && !widget.securityCodeOnly) ...[
              Text(
                'Detected Serial Numbers (tap to select):',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: MediaQuery.of(context).size.width < 360 ? 12 : 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _detectedSerials.map((serial) {
                  final isSelected = _serialController.text == serial;
                  final screenWidth = MediaQuery.of(context).size.width;
                  final maxItemWidth = screenWidth < 360
                      ? screenWidth - 60
                      : screenWidth - 80;
                  return InkWell(
                    onTap: () => _selectSerial(serial),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxItemWidth),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? widget.primaryColor
                              : const Color(0xFF2A1A1A),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? widget.primaryColor
                                : Colors.white24,
                          ),
                        ),
                        child: Text(
                          serial,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: screenWidth < 360 ? 12 : 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // Extracted/Editable Fields
            Container(
              padding: EdgeInsets.all(MediaQuery.of(context).size.width < 360 ? 12 : 16),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width),
              decoration: BoxDecoration(
                color: const Color(0xFF2A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.edit_note, color: widget.primaryColor, size: MediaQuery.of(context).size.width < 360 ? 20 : 24),
                      SizedBox(width: MediaQuery.of(context).size.width < 360 ? 6 : 8),
                      Flexible(
                        child: Text(
                          widget.securityCodeOnly
                              ? 'Security Code (Edit if needed)'
                              : 'Extracted Data (Edit if needed)',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: MediaQuery.of(context).size.width < 360 ? 14 : 16,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildEditableField(
                    controller: _serialController,
                    label: widget.securityCodeOnly
                        ? 'Security Code'
                        : widget.serviceType == 'sky'
                            ? 'Box Number'
                            : widget.serviceType == 'gsat_boxid'
                                ? 'Box ID / Serial Number'
                                : widget.serviceType == 'inventory_serial'
                                    ? 'Serial Number'
                                    : widget.serviceType == 'transaction_id'
                                        ? 'Transaction ID'
                                        : 'Serial No. (S/N)',
                    icon: widget.securityCodeOnly ? Icons.lock : Icons.qr_code,
                  ),
                  // GSAT Box ID and Inventory Serial only shows the Serial Number field
                  if (!widget.securityCodeOnly && widget.serviceType != 'gsat_boxid' && widget.serviceType != 'inventory_serial') ...[
                    // GSAT only shows: Serial Number, Name, Box Number, Address
                    if (widget.serviceType == 'gsat') ...[
                      const SizedBox(height: 12),
                      _buildEditableField(
                        controller: _nameController,
                        label: 'Name',
                        icon: Icons.person,
                      ),
                      const SizedBox(height: 12),
                      _buildEditableField(
                        controller: _boxNumberController,
                        label: 'Box No.',
                        icon: Icons.inventory_2,
                      ),
                      const SizedBox(height: 12),
                      _buildEditableField(
                        controller: _addressController,
                        label: 'Address',
                        icon: Icons.location_on,
                        maxLines: 2,
                      ),
                    ] else if (widget.serviceType == 'sky') ...[
                      // Sky shows: Box Number (serial), Box ID, Name, Address
                      const SizedBox(height: 12),
                      _buildEditableField(
                        controller: _ccaController,
                        label: 'Box ID',
                        icon: Icons.qr_code,
                      ),
                      const SizedBox(height: 12),
                      _buildEditableField(
                        controller: _nameController,
                        label: 'Name',
                        icon: Icons.person,
                      ),
                      const SizedBox(height: 12),
                      _buildEditableField(
                        controller: _addressController,
                        label: 'Address',
                        icon: Icons.location_on,
                        maxLines: 2,
                      ),
                    ] else ...[
                      // All other services show all fields
                      const SizedBox(height: 12),
                      _buildEditableField(
                        controller: _ccaController,
                        label: 'CCA No.',
                        icon: Icons.confirmation_number,
                      ),
                      const SizedBox(height: 12),
                      _buildEditableField(
                        controller: _boxNumberController,
                        label: 'Box No.',
                        icon: Icons.inventory_2,
                      ),
                      const SizedBox(height: 12),
                      _buildEditableField(
                        controller: _nameController,
                        label: 'Name',
                        icon: Icons.person,
                      ),
                      const SizedBox(height: 12),
                      _buildEditableField(
                        controller: _accountNumberController,
                        label: 'Account No.',
                        icon: Icons.account_circle,
                      ),
                      const SizedBox(height: 12),
                      _buildEditableField(
                        controller: _addressController,
                        label: 'Address',
                        icon: Icons.location_on,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      _buildEditableField(
                        controller: _pinController,
                        label: 'Security Code / PIN',
                        icon: Icons.lock,
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Use Data button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _useExtractedData,
                icon: const Icon(Icons.check_circle),
                label: Text('Use This Data',
                  style: TextStyle(
                    fontSize: MediaQuery.of(context).size.width < 360 ? 14 : 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2ECC71),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: MediaQuery.of(context).size.width < 360 ? 12 : 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            // Show all recognized text (collapsible)
            if (_recognizedText != null && _recognizedText!.isNotEmpty) ...[
              const SizedBox(height: 16),
              ExpansionTile(
                title: Text(
                  'View All Recognized Text',
                  style: TextStyle(color: Colors.white70, fontSize: MediaQuery.of(context).size.width < 360 ? 12 : 14),
                ),
                iconColor: Colors.white54,
                collapsedIconColor: Colors.white54,
                children: [
                  Container(
                    padding: EdgeInsets.all(MediaQuery.of(context).size.width < 360 ? 10 : 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A1A1A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width - 40,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        _recognizedText!,
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: MediaQuery.of(context).size.width < 360 ? 11 : 12,
                        ),
                        softWrap: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEditableField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
  }) {
    final hasValue = controller.text.isNotEmpty;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSlimPhone = screenWidth < 360;

    return SizedBox(
      width: double.infinity,
      child: TextField(
        controller: controller,
        style: TextStyle(
          color: Colors.white,
          fontSize: isSlimPhone ? 13 : 14,
        ),
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: hasValue
                ? widget.primaryColor
                : Colors.white.withValues(alpha: 0.5),
            fontSize: isSlimPhone ? 12 : 13,
          ),
          prefixIcon: Icon(
            icon,
            color: hasValue ? widget.primaryColor : Colors.white54,
            size: isSlimPhone ? 20 : 24,
          ),
          suffixIcon: hasValue
              ? const Icon(Icons.check, color: Color(0xFF2ECC71), size: 20)
              : null,
          filled: true,
          fillColor: hasValue
              ? widget.primaryColor.withValues(alpha: 0.1)
              : Colors.transparent,
          contentPadding: EdgeInsets.symmetric(
            horizontal: isSlimPhone ? 8 : 12,
            vertical: isSlimPhone ? 8 : 12,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: hasValue
                  ? widget.primaryColor.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.2),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: widget.primaryColor),
          ),
          isDense: isSlimPhone,
        ),
        onChanged: (value) {
          setState(() {});
        },
      ),
    );
  }
}

/// Custom painter for the scanner overlay with rectangular cutout
class ScannerOverlayPainter extends CustomPainter {
  final Color borderColor;
  final Color overlayColor;

  ScannerOverlayPainter({
    required this.borderColor,
    required this.overlayColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rectWidth = size.width * 0.9;
    final rectHeight = size.height * 0.225; // Increased by 50% (was 0.15)
    final left = (size.width - rectWidth) / 2;
    final top = (size.height - rectHeight) / 2 - 30;

    final scanRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, rectWidth, rectHeight),
      const Radius.circular(12),
    );

    // Draw the dark overlay
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(scanRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      overlayPath,
      Paint()..color = overlayColor,
    );

    // Draw the border
    canvas.drawRRect(
      scanRect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter for corner decorations
class CornerPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final bool topLeft;
  final bool topRight;
  final bool bottomLeft;
  final bool bottomRight;

  CornerPainter({
    required this.color,
    required this.strokeWidth,
    this.topLeft = false,
    this.topRight = false,
    this.bottomLeft = false,
    this.bottomRight = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final path = Path();

    if (topLeft) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (topRight) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (bottomLeft) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else if (bottomRight) {
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
