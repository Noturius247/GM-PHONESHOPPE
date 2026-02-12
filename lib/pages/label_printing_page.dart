import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/inventory_service.dart';
import 'ocr_scanner_page.dart';
import '../utils/snackbar_utils.dart';

class LabelPrintingPage extends StatefulWidget {
  final List<Map<String, dynamic>>? inventoryItems;

  const LabelPrintingPage({super.key, this.inventoryItems});

  @override
  State<LabelPrintingPage> createState() => _LabelPrintingPageState();
}

class _LabelPrintingPageState extends State<LabelPrintingPage> with SingleTickerProviderStateMixin {
  // Dark theme colors (matching inventory page)
  static const Color _bgColor = Color(0xFF1A0A0A);
  static const Color _cardColor = Color(0xFF252525);
  static const Color _accentColor = Color(0xFFE67E22);
  static const Color _accentDark = Color(0xFFD35400);
  static const Color _textPrimary = Colors.white;
  static const Color _textSecondary = Color(0xFFB0B0B0);

  List<Map<String, dynamic>> _inventoryItems = [];
  bool _isLoading = false;

  // Paper size options
  String _paperSize = 'A4'; // 'A4' or 'Legal'

  // Label dimensions using explicit mm conversion (1 inch = 25.4mm)
  static final double _labelWidth = 38.1 * PdfPageFormat.mm;   // 1.5 inches
  static final double _labelHeight = 17.78 * PdfPageFormat.mm; // 0.70 inch
  static final double _labelGap = 1.5 * PdfPageFormat.mm;      // 1.5mm gap between labels
  static final double _pageMargin = 5.0 * PdfPageFormat.mm;    // 5mm margin

  // Item selection state
  final Map<String, int> _selectedItems = {}; // itemId -> quantity of labels
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Tab controller for Barcode / Inventory tabs
  late TabController _tabController;

  // Barcode prefix settings (SKU starting digits that go to "Barcode" tab)
  // Include both '7' (new random series) and '9' (old incremental series) for backward compatibility
  List<String> _barcodePrefixes = ['7', '9'];
  static const String _prefixesKey = 'label_barcode_prefixes';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadBarcodePrefixes();
    if (widget.inventoryItems != null) {
      _inventoryItems = widget.inventoryItems!;
    } else {
      _loadInventory();
    }
  }

  Future<void> _loadBarcodePrefixes() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_prefixesKey);
    if (saved != null && saved.isNotEmpty) {
      setState(() => _barcodePrefixes = saved);
    }
  }

  Future<void> _saveBarcodePrefixes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefixesKey, _barcodePrefixes);
  }

  Future<void> _loadInventory() async {
    setState(() => _isLoading = true);
    try {
      final items = await InventoryService.getAllItems();
      if (mounted) {
        setState(() {
          _inventoryItems = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        SnackBarUtils.showError(context, 'Error loading inventory: $e');
      }
    }
  }

  List<Map<String, dynamic>> get _filteredItems {
    if (_searchQuery.isEmpty) return _inventoryItems;
    final query = _searchQuery.toLowerCase();
    return _inventoryItems.where((item) {
      final name = (item['name'] as String? ?? '').toLowerCase();
      final sku = (item['sku'] as String? ?? item['serialNo'] as String? ?? '').toLowerCase();
      final modelNumber = (item['modelNumber'] as String? ?? '').toLowerCase();
      return name.contains(query) || sku.contains(query) || modelNumber.contains(query);
    }).toList();
  }

  bool _matchesBarcodePrefix(Map<String, dynamic> item) {
    final sku = (item['sku'] as String? ?? item['serialNo'] as String? ?? '');
    if (sku.isEmpty) return false;
    return _barcodePrefixes.any((prefix) => sku.startsWith(prefix));
  }

  List<Map<String, dynamic>> _sortByDateAdded(List<Map<String, dynamic>> items) {
    final sorted = List<Map<String, dynamic>>.from(items);
    sorted.sort((a, b) {
      final aTime = a['createdAt'] as int? ?? a['timestamp'] as int? ?? 0;
      final bTime = b['createdAt'] as int? ?? b['timestamp'] as int? ?? 0;
      return aTime.compareTo(bTime);
    });
    return sorted;
  }

  /// Items whose SKU starts with a configured barcode prefix
  List<Map<String, dynamic>> get _barcodeTabItems {
    return _sortByDateAdded(_filteredItems.where(_matchesBarcodePrefix).toList());
  }

  /// Items that don't match any barcode prefix
  List<Map<String, dynamic>> get _inventoryTabItems {
    return _sortByDateAdded(_filteredItems.where((item) => !_matchesBarcodePrefix(item)).toList());
  }

  /// Items for the currently active tab
  List<Map<String, dynamic>> get _currentTabItems {
    return _tabController.index == 0 ? _barcodeTabItems : _inventoryTabItems;
  }

  int get _totalLabels {
    int total = 0;
    _selectedItems.forEach((_, qty) => total += qty);
    return total;
  }

  PdfPageFormat get _pageFormat {
    return _paperSize == 'A4' ? PdfPageFormat.a4 : PdfPageFormat.legal;
  }

  int get _columnsPerPage {
    final printableWidth = _pageFormat.width - (_pageMargin * 2);
    return (printableWidth / (_labelWidth + _labelGap)).floor();
  }

  int get _rowsPerPage {
    final printableHeight = _pageFormat.height - (_pageMargin * 2);
    return (printableHeight / (_labelHeight + _labelGap)).floor();
  }

  int get _labelsPerPage => _columnsPerPage * _rowsPerPage;

  int get _totalPages => _totalLabels > 0 ? (_totalLabels / _labelsPerPage).ceil() : 0;

  void _toggleItem(String itemId) {
    setState(() {
      if (_selectedItems.containsKey(itemId)) {
        _selectedItems.remove(itemId);
      } else {
        _selectedItems[itemId] = 1;
      }
    });
  }

  void _updateQuantity(String itemId, int qty) {
    setState(() {
      if (qty <= 0) {
        _selectedItems.remove(itemId);
      } else {
        _selectedItems[itemId] = qty;
      }
    });
  }

  void _selectAll() {
    setState(() {
      for (var item in _currentTabItems) {
        final id = item['id'] as String;
        if (!_selectedItems.containsKey(id)) {
          _selectedItems[id] = 1;
        }
      }
    });
  }

  void _deselectAll() {
    setState(() {
      final currentIds = _currentTabItems.map((item) => item['id'] as String).toSet();
      _selectedItems.removeWhere((id, _) => currentIds.contains(id));
    });
  }

  Map<String, dynamic>? _findItemById(String id) {
    try {
      return _inventoryItems.firstWhere((item) => item['id'] == id);
    } catch (_) {
      return null;
    }
  }

  String _getQrData(Map<String, dynamic> item) {
    final sku = item['sku'] as String? ?? item['serialNo'] as String? ?? '';
    final name = item['name'] as String? ?? '';
    final price = item['sellingPrice'] != null
        ? NumberFormat.currency(symbol: '', decimalDigits: 2).format(item['sellingPrice'])
        : '0.00';
    return '$sku|$name|$price';
  }

  String _getSku(Map<String, dynamic> item) {
    return item['sku'] as String? ?? item['serialNo'] as String? ?? '-';
  }

  String _getName(Map<String, dynamic> item) {
    return item['name'] as String? ?? '';
  }

  String _getPrice(Map<String, dynamic> item) {
    if (item['sellingPrice'] == null) return '';
    return 'P${NumberFormat.currency(symbol: '', decimalDigits: 2).format(item['sellingPrice'])}';
  }

  Future<void> _openOcrQrScanner() async {
    final result = await Navigator.push<OcrExtractedData>(
      context,
      MaterialPageRoute(
        builder: (context) => const OcrScannerPage(
          serviceName: 'Label',
          primaryColor: _accentColor,
          serviceType: 'inventory_serial',
        ),
      ),
    );

    if (result != null && result.serialNumber != null && result.serialNumber!.isNotEmpty) {
      final scannedSerial = result.serialNumber!.trim().toLowerCase();
      // Find matching inventory item and auto-select it
      final match = _inventoryItems.cast<Map<String, dynamic>?>().firstWhere(
        (item) {
          final serialNo = (item?['serialNo'] as String? ?? '').toLowerCase();
          final sku = (item?['sku'] as String? ?? '').toLowerCase();
          return serialNo == scannedSerial || sku == scannedSerial;
        },
        orElse: () => null,
      );

      if (match != null) {
        final id = match['id'] as String;
        setState(() {
          if (!_selectedItems.containsKey(id)) {
            _selectedItems[id] = 1;
          } else {
            _selectedItems[id] = _selectedItems[id]! + 1;
          }
        });
        if (mounted) {
          SnackBarUtils.showSuccess(context, 'Selected: ${match['name']}');
        }
      } else {
        // Fall back to search filter
        setState(() {
          _searchController.text = result.serialNumber!;
          _searchQuery = result.serialNumber!;
        });
        if (mounted) {
          SnackBarUtils.showWarning(context, 'No exact match — filtered by: ${result.serialNumber}');
        }
      }
    }
  }

  // Build the list of label data (each entry = one label to print)
  List<Map<String, dynamic>> _buildLabelList() {
    final labels = <Map<String, dynamic>>[];
    _selectedItems.forEach((itemId, qty) {
      final item = _findItemById(itemId);
      if (item != null) {
        for (int i = 0; i < qty; i++) {
          labels.add(item);
        }
      }
    });
    return labels;
  }

  // ==================== PDF Generation ====================

  Future<pw.Document> _generatePdf() async {
    final pdf = pw.Document();
    final labels = _buildLabelList();
    final cols = _columnsPerPage;
    final rows = _rowsPerPage;
    final labelsPerPage = cols * rows;
    final totalPages = labels.isEmpty ? 0 : (labels.length / labelsPerPage).ceil();

    for (int page = 0; page < totalPages; page++) {
      final startIdx = page * labelsPerPage;
      final endIdx = (startIdx + labelsPerPage).clamp(0, labels.length);
      final pageLabels = labels.sublist(startIdx, endIdx);

      pdf.addPage(
        pw.Page(
          pageFormat: _pageFormat,
          margin: pw.EdgeInsets.all(_pageMargin),
          build: (pw.Context context) {
            // Build explicit grid rows/columns for exact sizing
            final tableRows = <pw.TableRow>[];
            for (int r = 0; r < rows; r++) {
              final cells = <pw.Widget>[];
              for (int c = 0; c < cols; c++) {
                final idx = r * cols + c;
                if (idx < pageLabels.length) {
                  cells.add(_buildPdfLabel(pageLabels[idx]));
                } else {
                  // Empty cell placeholder
                  cells.add(pw.SizedBox(width: _labelWidth, height: _labelHeight));
                }
              }
              tableRows.add(pw.TableRow(children: cells));
            }

            return pw.Table(
              columnWidths: {
                for (int c = 0; c < cols; c++)
                  c: pw.FixedColumnWidth(_labelWidth + _labelGap),
              },
              children: tableRows,
            );
          },
        ),
      );
    }

    return pdf;
  }

  pw.Widget _buildPdfLabel(Map<String, dynamic> item) {
    final qrData = _getQrData(item);
    final sku = _getSku(item);
    final name = _getName(item);
    final price = _getPrice(item);
    final brand = item['brand'] as String? ?? '';
    final qrSize = 17.78 * PdfPageFormat.mm; // 0.70 inch QR code (fills height)

    return pw.Container(
      width: _labelWidth,
      height: _labelHeight,
      margin: pw.EdgeInsets.only(bottom: _labelGap),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.5),
      ),
      padding: pw.EdgeInsets.all(1.0 * PdfPageFormat.mm),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // QR Code on the left
          pw.SizedBox(
            width: qrSize,
            height: qrSize,
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: qrData,
              width: qrSize,
              height: qrSize,
            ),
          ),
          pw.SizedBox(width: 1.0 * PdfPageFormat.mm),
          // Text info on the right
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                // Product name
                pw.Text(
                  name,
                  style: pw.TextStyle(
                    fontSize: 5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                ),
                // Brand
                if (brand.isNotEmpty)
                  pw.Text(
                    brand,
                    style: pw.TextStyle(
                      fontSize: 5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                  ),
                // Price
                if (price.isNotEmpty)
                  pw.Text(
                    price,
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    maxLines: 1,
                  ),
                // SKU/Serial — biggest, at the bottom
                pw.Text(
                  sku,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printLabels() async {
    if (_selectedItems.isEmpty) {
      SnackBarUtils.showWarning(context, 'Please select at least one item');
      return;
    }

    try {
      final pdf = await _generatePdf();
      final bytes = await pdf.save();

      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: 'GM_PhoneShoppe_Labels_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
        format: _pageFormat,
      );
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showError(context, 'Print error: $e');
      }
    }
  }

  // ==================== Preview ====================

  void _showPreview() {
    if (_selectedItems.isEmpty) {
      SnackBarUtils.showWarning(context, 'Please select at least one item');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _LabelPreviewDialog(
        labels: _buildLabelList(),
        paperSize: _paperSize,
        labelWidth: _labelWidth,
        labelHeight: _labelHeight,
        labelGap: _labelGap,
        pageMargin: _pageMargin,
        columns: _columnsPerPage,
        rows: _rowsPerPage,
        getSku: _getSku,
        getQrData: _getQrData,
        getName: _getName,
        getPrice: _getPrice,
      ),
    );
  }

  // ==================== Prefix Settings Dialog ====================

  void _showPrefixSettingsDialog() {
    final tempPrefixes = List<String>.from(_barcodePrefixes);
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: _cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.tune_rounded, color: _accentColor, size: 22),
              SizedBox(width: 10),
              Text('Barcode Prefixes', style: TextStyle(color: _textPrimary, fontSize: 17)),
            ],
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SKU/serial numbers starting with these digits will appear in the "Barcode" tab.',
                  style: TextStyle(color: _textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 16),
                // Current prefixes as chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: tempPrefixes.map((prefix) => Chip(
                    label: Text(prefix, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    backgroundColor: _accentColor,
                    side: BorderSide.none,
                    deleteIcon: const Icon(Icons.close, size: 16, color: Colors.white),
                    onDeleted: () => setDialogState(() => tempPrefixes.remove(prefix)),
                  )).toList(),
                ),
                const SizedBox(height: 16),
                // Add new prefix
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        style: const TextStyle(color: _textPrimary, fontSize: 14),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Enter prefix digit(s)...',
                          hintStyle: TextStyle(color: _textSecondary.withValues(alpha: 0.5), fontSize: 13),
                          filled: true,
                          fillColor: _bgColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        final value = controller.text.trim();
                        if (value.isNotEmpty && !tempPrefixes.contains(value)) {
                          setDialogState(() => tempPrefixes.add(value));
                          controller.clear();
                        }
                      },
                      icon: const Icon(Icons.add_circle, color: _accentColor),
                      tooltip: 'Add prefix',
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: _textSecondary.withValues(alpha: 0.7))),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() => _barcodePrefixes = tempPrefixes);
                _saveBarcodePrefixes();
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Build UI ====================

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        foregroundColor: _textPrimary,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_accentColor, _accentDark],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.qr_code_2, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Label Printing',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: _textSecondary),
            tooltip: 'Barcode prefix settings',
            onPressed: _showPrefixSettingsDialog,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _accentColor))
          : Column(
              children: [
                // Tab bar
                Container(
                  color: _cardColor,
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: _accentColor,
                    indicatorWeight: 3,
                    labelColor: _accentColor,
                    unselectedLabelColor: _textSecondary,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 13),
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.qr_code, size: 16),
                            const SizedBox(width: 6),
                            Text('Excluded (${_barcodeTabItems.length})'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.inventory_2_outlined, size: 16),
                            const SizedBox(width: 6),
                            Text('Inventory (${_inventoryTabItems.length})'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Paper size selector and stats bar
                _buildControlBar(),
                // Search
                _buildSearchBar(),
                // Select all / deselect all
                _buildSelectionControls(),
                // Item list
                Expanded(child: _buildItemList()),
              ],
            ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildControlBar() {
    final screenWidth = MediaQuery.of(context).size.width;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: _cardColor,
      child: Row(
        children: [
          // Paper size dropdown
          Text('Paper: ', style: TextStyle(color: _textSecondary, fontSize: screenWidth < 360 ? 11 : 13)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: _bgColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _accentColor.withValues(alpha: 0.5)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _paperSize,
                dropdownColor: _cardColor,
                style: const TextStyle(color: _textPrimary, fontSize: 13),
                items: const [
                  DropdownMenuItem(value: 'A4', child: Text('A4')),
                  DropdownMenuItem(value: 'Legal', child: Text('Legal')),
                ],
                onChanged: (v) => setState(() => _paperSize = v ?? 'A4'),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Stats
          Expanded(
            child: Text(
              '$_totalLabels labels | $_totalPages page${_totalPages != 1 ? 's' : ''} | ${_columnsPerPage}x$_rowsPerPage grid',
              style: TextStyle(color: _textSecondary, fontSize: screenWidth < 360 ? 10 : 12),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: _textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search items by name or SKU...',
          hintStyle: TextStyle(color: _textSecondary.withValues(alpha: 0.6), fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: _textSecondary, size: 20),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, color: _textSecondary, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
              IconButton(
                icon: const Icon(Icons.document_scanner, color: _accentColor, size: 20),
                onPressed: _openOcrQrScanner,
                tooltip: 'Scan QR / OCR',
              ),
            ],
          ),
          filled: true,
          fillColor: _cardColor,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _buildSelectionControls() {
    final tabItems = _currentTabItems;
    final tabSelectedCount = tabItems.where((item) => _selectedItems.containsKey(item['id'] as String)).length;
    final allSelected = tabItems.isNotEmpty &&
        tabItems.every((item) => _selectedItems.containsKey(item['id'] as String));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            '$tabSelectedCount selected',
            style: const TextStyle(color: _accentColor, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (_selectedItems.length != tabSelectedCount)
            Text(
              ' (${_selectedItems.length} total)',
              style: TextStyle(color: _textSecondary.withValues(alpha: 0.6), fontSize: 12),
            ),
          const Spacer(),
          TextButton(
            onPressed: allSelected ? _deselectAll : _selectAll,
            child: Text(
              allSelected ? 'Deselect All' : 'Select All',
              style: const TextStyle(color: _accentColor, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemList() {
    final items = _currentTabItems;

    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadInventory,
        color: _accentColor,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 48, color: _textSecondary.withValues(alpha: 0.4)),
                    const SizedBox(height: 12),
                    Text(
                      _searchQuery.isNotEmpty ? 'No items match your search' : 'No inventory items',
                      style: TextStyle(color: _textSecondary.withValues(alpha: 0.6), fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInventory,
      color: _accentColor,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final id = item['id'] as String;
        final isSelected = _selectedItems.containsKey(id);
        final qty = _selectedItems[id] ?? 0;
        final sku = _getSku(item);
        final name = item['name'] as String? ?? 'Unknown';
        final price = item['sellingPrice'] != null
            ? NumberFormat.currency(symbol: 'P', decimalDigits: 2).format(item['sellingPrice'])
            : '';
        final location = item['location'] as String? ?? '';
        final stockQty = item['quantity'] as int? ?? 0;

        return Card(
          color: isSelected ? _cardColor : _cardColor.withValues(alpha: 0.6),
          margin: const EdgeInsets.symmetric(vertical: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: isSelected
                ? const BorderSide(color: _accentColor, width: 1.2)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _toggleItem(id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // Row number
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: isSelected ? _accentColor : _textSecondary.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Checkbox
                  Icon(
                    isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                    color: isSelected ? _accentColor : _textSecondary,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  // Item info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'SKU: $sku  •  Qty: $stockQty${price.isNotEmpty ? '  •  $price' : ''}${location.isNotEmpty ? '  •  $location' : ''}',
                          style: const TextStyle(color: _textSecondary, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Quantity selector (only when selected)
                  if (isSelected) ...[
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: _textSecondary, size: 20),
                      onPressed: () => _updateQuantity(id, qty - 1),
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        '$qty',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _accentColor,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: _accentColor, size: 20),
                      onPressed: () => _updateQuantity(id, qty + 1),
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: _cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Preview button
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _totalLabels > 0 ? _showPreview : null,
                icon: const Icon(Icons.preview, size: 18),
                label: const Text('Preview'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accentColor,
                  side: BorderSide(color: _totalLabels > 0 ? _accentColor : _textSecondary.withValues(alpha: 0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Print button
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _totalLabels > 0 ? _printLabels : null,
                icon: const Icon(Icons.print, size: 18),
                label: Text('Print $_totalLabels Label${_totalLabels != 1 ? 's' : ''}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _textSecondary.withValues(alpha: 0.2),
                  disabledForegroundColor: _textSecondary.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== Preview Dialog ====================

class _LabelPreviewDialog extends StatelessWidget {
  final List<Map<String, dynamic>> labels;
  final String paperSize;
  final double labelWidth;
  final double labelHeight;
  final double labelGap;
  final double pageMargin;
  final int columns;
  final int rows;
  final String Function(Map<String, dynamic>) getSku;
  final String Function(Map<String, dynamic>) getQrData;
  final String Function(Map<String, dynamic>) getName;
  final String Function(Map<String, dynamic>) getPrice;

  const _LabelPreviewDialog({
    required this.labels,
    required this.paperSize,
    required this.labelWidth,
    required this.labelHeight,
    required this.labelGap,
    required this.pageMargin,
    required this.columns,
    required this.rows,
    required this.getSku,
    required this.getQrData,
    required this.getName,
    required this.getPrice,
  });

  static const Color _cardColor = Color(0xFF252525);
  static const Color _accentColor = Color(0xFFE67E22);
  static const Color _textPrimary = Colors.white;
  static const Color _textSecondary = Color(0xFFB0B0B0);

  @override
  Widget build(BuildContext context) {
    final labelsPerPage = columns * rows;
    final totalPages = labels.isEmpty ? 0 : (labels.length / labelsPerPage).ceil();

    // Scale the paper to fit in dialog
    final pageFormat = paperSize == 'A4' ? PdfPageFormat.a4 : PdfPageFormat.legal;
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 360 ? screenWidth * 0.95 : (screenWidth * 0.9).clamp(300, 800);
    final scale = (dialogWidth - 48) / pageFormat.width; // 48 = dialog padding
    final scaledHeight = pageFormat.height * scale;

    return Dialog(
      backgroundColor: _cardColor,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.preview, color: _accentColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Label Preview ($paperSize)',
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: _textSecondary, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '${labels.length} labels on $totalPages page${totalPages != 1 ? 's' : ''} • ${columns}x$rows grid • Each label: 1.5" x 0.70"',
              style: const TextStyle(color: _textSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          // Scrollable preview of page(s)
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                children: List.generate(totalPages.clamp(0, 3), (pageIdx) {
                  final startIdx = pageIdx * labelsPerPage;
                  final endIdx = (startIdx + labelsPerPage).clamp(0, labels.length);
                  final pageLabels = labels.sublist(startIdx, endIdx);

                  return Container(
                    width: dialogWidth - 40,
                    height: scaledHeight,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: EdgeInsets.all(pageMargin * scale),
                    child: Wrap(
                      spacing: labelGap * scale,
                      runSpacing: labelGap * scale,
                      children: pageLabels.map((item) {
                        final sku = getSku(item);
                        final name = getName(item);
                        final price = getPrice(item);
                        final scaledW = labelWidth * scale;
                        final scaledH = labelHeight * scale;
                        final qrSize = scaledH; // QR fills full height

                        return Container(
                          width: scaledW,
                          height: scaledH,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black, width: 0.5),
                          ),
                          padding: EdgeInsets.all(1.0 * scale),
                          child: Row(
                            children: [
                              // QR code on left
                              SizedBox(
                                width: qrSize,
                                height: qrSize,
                                child: QrImageView(
                                  data: getQrData(item),
                                  version: QrVersions.auto,
                                  backgroundColor: Colors.white,
                                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                                ),
                              ),
                              SizedBox(width: 1.0 * scale),
                              // Text on right
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: (5 * scale).clamp(2.0, 8.0),
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                        height: 1.1,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if ((item['brand'] as String? ?? '').isNotEmpty)
                                      Text(
                                        item['brand'] as String,
                                        style: TextStyle(
                                          fontSize: (5 * scale).clamp(2.0, 8.0),
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (price.isNotEmpty)
                                      Text(
                                        price,
                                        style: TextStyle(
                                          fontSize: (8 * scale).clamp(2.0, 12.0),
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                        maxLines: 1,
                                      ),
                                    Text(
                                      sku,
                                      style: TextStyle(
                                        fontSize: (12 * scale).clamp(4.0, 18.0),
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  );
                }),
              ),
            ),
          ),
          if (totalPages > 3)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '+ ${totalPages - 3} more page${totalPages - 3 != 1 ? 's' : ''} not shown',
                style: const TextStyle(color: _textSecondary, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
