import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import '../services/firebase_database_service.dart';
import '../services/auth_service.dart';
import '../utils/csv_download.dart' as csv_helper;

class GsatActivationPage extends StatefulWidget {
  const GsatActivationPage({super.key});

  @override
  State<GsatActivationPage> createState() => _GsatActivationPageState();
}

class _GsatActivationPageState extends State<GsatActivationPage> {
  List<Map<String, dynamic>> _activations = [];
  bool _isLoading = true;
  String _currentUserName = '';

  // GSAT gradient colors
  static const gsatGradient = [Color(0xFF2ECC71), Color(0xFF27AE60)];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadActivations(),
      _loadCurrentUser(),
    ]);
  }

  Future<void> _loadCurrentUser() async {
    final user = await AuthService.getCurrentUser();
    if (user != null && mounted) {
      setState(() {
        _currentUserName = user['name'] ?? '';
      });
    }
  }

  Future<void> _loadActivations() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final activations = await FirebaseDatabaseService.getGsatActivations();
      if (mounted) {
        setState(() {
          _activations = activations;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _exportToCsv() {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Export is only available on web'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_activations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No data to export'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Generate CSV content
    final csvBuffer = StringBuffer();

    // Add headers
    csvBuffer.writeln('SERIAL NUMBER,NAME,ADDRESS,CONTACT NUMBER,DEALER');

    // Add data rows
    for (final activation in _activations) {
      final serialNumber = _escapeCsvField(activation['serialNumber'] ?? '');
      final name = _escapeCsvField(activation['name'] ?? '');
      final address = _escapeCsvField(activation['address'] ?? '');
      final contactNumber = _escapeCsvField(activation['contactNumber'] ?? '');
      final dealer = _escapeCsvField(activation['dealer'] ?? '');

      csvBuffer.writeln('$serialNumber,$name,$address,$contactNumber,$dealer');
    }

    // Generate filename with date
    final now = DateTime.now();
    final dateStr = DateFormat('MM-dd-yyyy').format(now);
    final fileName = 'GM Phoneshoppe $dateStr.csv';

    // Download file (web only)
    csv_helper.downloadCsvFile(csvBuffer.toString(), fileName);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exported to $fileName'),
        backgroundColor: gsatGradient[0],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _escapeCsvField(String field) {
    // Escape fields containing commas, quotes, or newlines
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  void _confirmDelete(Map<String, dynamic> activation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A1A1A),
        title: const Text('Delete Activation?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete the activation for ${activation['name']}?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              if (activation['id'] != null) {
                await FirebaseDatabaseService.deleteGsatActivation(activation['id']);
                _loadActivations();
                if (mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Activation deleted'),
                      backgroundColor: Colors.red, 
                    ),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddDialog() {
    final formKey = GlobalKey<FormState>();
    final serialNumberController = TextEditingController();
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final contactNumberController = TextEditingController();
    final dealerController = TextEditingController(text: 'Romeo dalocanog');
    bool isSubmitting = false;

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
              Icon(Icons.add_circle, color: gsatGradient[0], size: 28),
              const SizedBox(width: 12),
              const Text(
                'Add New Activation',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDialogTextField(
                      controller: serialNumberController,
                      label: 'Serial Number *',
                      icon: Icons.qr_code,
                      validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildDialogTextField(
                      controller: nameController,
                      label: 'Name *',
                      icon: Icons.person,
                      validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildDialogTextField(
                      controller: addressController,
                      label: 'Address (Municipality, Province) *',
                      icon: Icons.location_on,
                      validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildDialogTextField(
                      controller: contactNumberController,
                      label: 'Contact Number *',
                      icon: Icons.phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      validator: (v) {
                        if (v?.isEmpty ?? true) return 'Required';
                        if (v!.length < 10) return 'Invalid number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildDialogTextField(
                      controller: dealerController,
                      label: 'Dealer *',
                      icon: Icons.store,
                      validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;

                      setDialogState(() => isSubmitting = true);

                      try {
                        await FirebaseDatabaseService.addGsatActivation(
                          serialNumber: serialNumberController.text.trim(),
                          name: nameController.text.trim(),
                          address: addressController.text.trim(),
                          contactNumber: contactNumberController.text.trim(),
                          dealer: dealerController.text.trim(),
                        );

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: const Text('Activation added successfully!'),
                              backgroundColor: gsatGradient[0],
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          _loadActivations();
                        }
                      } catch (e) {
                        setDialogState(() => isSubmitting = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: gsatGradient[0],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> activation) {
    final formKey = GlobalKey<FormState>();
    final serialNumberController = TextEditingController(text: activation['serialNumber'] ?? '');
    final nameController = TextEditingController(text: activation['name'] ?? '');
    final addressController = TextEditingController(text: activation['address'] ?? '');
    final contactNumberController = TextEditingController(text: activation['contactNumber'] ?? '');
    final dealerController = TextEditingController(text: activation['dealer'] ?? 'Romeo dalocanog');
    bool isSubmitting = false;

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
              Icon(Icons.edit, color: gsatGradient[0], size: 28),
              const SizedBox(width: 12),
              const Text(
                'Edit Activation',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDialogTextField(
                      controller: serialNumberController,
                      label: 'Serial Number *',
                      icon: Icons.qr_code,
                      validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildDialogTextField(
                      controller: nameController,
                      label: 'Name *',
                      icon: Icons.person,
                      validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildDialogTextField(
                      controller: addressController,
                      label: 'Address (Municipality, Province) *',
                      icon: Icons.location_on,
                      validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildDialogTextField(
                      controller: contactNumberController,
                      label: 'Contact Number *',
                      icon: Icons.phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      validator: (v) {
                        if (v?.isEmpty ?? true) return 'Required';
                        if (v!.length < 10) return 'Invalid number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildDialogTextField(
                      controller: dealerController,
                      label: 'Dealer *',
                      icon: Icons.store,
                      validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;

                      setDialogState(() => isSubmitting = true);

                      try {
                        await FirebaseDatabaseService.updateGsatActivation(
                          activationId: activation['id'],
                          serialNumber: serialNumberController.text.trim(),
                          name: nameController.text.trim(),
                          address: addressController.text.trim(),
                          contactNumber: contactNumberController.text.trim(),
                          dealer: dealerController.text.trim(),
                        );

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: const Text('Activation updated successfully!'),
                              backgroundColor: gsatGradient[0],
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          _loadActivations();
                        }
                      } catch (e) {
                        setDialogState(() => isSubmitting = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: gsatGradient[0],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      cursorColor: gsatGradient[0],
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        prefixIcon: Icon(icon, color: gsatGradient[0]),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: gsatGradient[0]),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}-${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: const Color(0xFF1A0A0A),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: gsatGradient[0],
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add Activation',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: isMobile ? 12 : 16,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gsatGradient,
              ),
              boxShadow: [
                BoxShadow(
                  color: gsatGradient[0].withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  // Logo
                  Container(
                    width: isMobile ? 40 : 50,
                    height: isMobile ? 40 : 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'Photos/GSAT.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.rocket_launch,
                            color: gsatGradient[0],
                            size: isMobile ? 24 : 30,
                          );
                        },
                      ),
                    ),
                  ),
                  SizedBox(width: isMobile ? 12 : 16),
                  // Title
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GSAT Activation',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isMobile ? 18 : 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_activations.length} activation${_activations.length != 1 ? 's' : ''} recorded',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: isMobile ? 12 : 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Export CSV button (web only)
                  if (kIsWeb)
                    isMobile
                        ? IconButton(
                            onPressed: _exportToCsv,
                            icon: const Icon(Icons.download, color: Colors.white),
                            tooltip: 'Export CSV',
                          )
                        : Container(
                            margin: const EdgeInsets.only(right: 8),
                            child: ElevatedButton.icon(
                              onPressed: _exportToCsv,
                              icon: const Icon(Icons.download, size: 18),
                              label: const Text('Export CSV'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white.withValues(alpha: 0.2),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                                ),
                              ),
                            ),
                          ),
                  // Refresh button
                  IconButton(
                    onPressed: _loadActivations,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),
          ),

          // Table Content
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: gsatGradient[0]),
                  )
                : _activations.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              color: Colors.white.withValues(alpha: 0.3),
                              size: 64,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No activations yet',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap the button below to add your first activation',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        padding: EdgeInsets.all(isMobile ? 12 : 24),
                        child: isMobile
                            ? SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: _buildDataTable(isMobile),
                              )
                            : SizedBox(
                                width: double.infinity,
                                child: _buildDataTable(isMobile),
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTable(bool isMobile) {
    return Container(
      width: isMobile ? null : double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF2A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: gsatGradient[0].withValues(alpha: 0.3),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            gsatGradient[0].withValues(alpha: 0.2),
          ),
          dataRowColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return gsatGradient[0].withValues(alpha: 0.1);
            }
            return Colors.transparent;
          }),
          dividerThickness: 0,
          showCheckboxColumn: false,
          columnSpacing: isMobile ? 20 : 56,
          horizontalMargin: isMobile ? 12 : 32,
          columns: [
            DataColumn(
              label: Text(
                'SERIAL NUMBER',
                style: TextStyle(
                  color: gsatGradient[0],
                  fontWeight: FontWeight.bold,
                  fontSize: isMobile ? 12 : 14,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'NAME',
                style: TextStyle(
                  color: gsatGradient[0],
                  fontWeight: FontWeight.bold,
                  fontSize: isMobile ? 12 : 14,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'ADDRESS',
                style: TextStyle(
                  color: gsatGradient[0],
                  fontWeight: FontWeight.bold,
                  fontSize: isMobile ? 12 : 14,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'CONTACT NUMBER',
                style: TextStyle(
                  color: gsatGradient[0],
                  fontWeight: FontWeight.bold,
                  fontSize: isMobile ? 12 : 14,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'DEALER',
                style: TextStyle(
                  color: gsatGradient[0],
                  fontWeight: FontWeight.bold,
                  fontSize: isMobile ? 12 : 14,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'DATE',
                style: TextStyle(
                  color: gsatGradient[0],
                  fontWeight: FontWeight.bold,
                  fontSize: isMobile ? 12 : 14,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'ACTION',
                style: TextStyle(
                  color: gsatGradient[0],
                  fontWeight: FontWeight.bold,
                  fontSize: isMobile ? 12 : 14,
                ),
              ),
            ),
          ],
          rows: _activations.map((activation) {
            return DataRow(
              cells: [
                DataCell(
                  Text(
                    activation['serialNumber'] ?? 'N/A',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isMobile ? 12 : 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    activation['name'] ?? 'N/A',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: isMobile ? 12 : 14,
                    ),
                  ),
                ),
                DataCell(
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isMobile ? 120 : 300),
                    child: Text(
                      activation['address'] ?? 'N/A',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: isMobile ? 12 : 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    activation['contactNumber'] ?? 'N/A',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: isMobile ? 12 : 14,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    activation['dealer'] ?? 'N/A',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: isMobile ? 12 : 14,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    _formatDate(activation['createdAt']),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: isMobile ? 11 : 13,
                    ),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit, color: gsatGradient[0]),
                        onPressed: () => _showEditDialog(activation),
                        tooltip: 'Edit',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _confirmDelete(activation),
                        tooltip: 'Delete',
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
