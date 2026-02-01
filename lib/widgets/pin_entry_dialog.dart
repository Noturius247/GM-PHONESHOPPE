import 'package:flutter/material.dart';
import '../services/staff_pin_service.dart';

/// Dialog for staff to enter their 4-digit PIN before processing a transaction.
/// Returns the staff info {email, name, userId} on success, or null if cancelled.
class PinEntryDialog extends StatefulWidget {
  const PinEntryDialog({super.key});

  @override
  State<PinEntryDialog> createState() => _PinEntryDialogState();
}

class _PinEntryDialogState extends State<PinEntryDialog>
    with SingleTickerProviderStateMixin {
  static const Color _bgColor = Color(0xFF1A0A0A);
  static const Color _cardColor = Color(0xFF252525);
  static const Color _accentColor = Color(0xFFE67E22);
  static const Color _textPrimary = Colors.white;
  static const Color _textSecondary = Color(0xFFB0B0B0);

  String _pin = '';
  String? _errorText;
  bool _isVerifying = false;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _onDigitEntered(String digit) async {
    if (_pin.length >= 4 || _isVerifying) return;

    setState(() {
      _pin += digit;
      _errorText = null;
    });

    if (_pin.length == 4) {
      await _verifyPin();
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty || _isVerifying) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _errorText = null;
    });
  }

  void _onClear() {
    if (_isVerifying) return;
    setState(() {
      _pin = '';
      _errorText = null;
    });
  }

  Future<void> _verifyPin() async {
    setState(() => _isVerifying = true);

    final staffInfo = await StaffPinService.lookupPinFromCache(_pin);

    if (!mounted) return;

    if (staffInfo != null) {
      Navigator.pop(context, staffInfo);
    } else {
      _shakeController.forward(from: 0);
      setState(() {
        _errorText = 'Invalid PIN';
        _isVerifying = false;
      });
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        setState(() {
          _pin = '';
          _errorText = null;
        });
      }
    }
  }

  Widget _buildPinIndicators(double dotSize) {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(
            _shakeController.isAnimating
                ? _shakeAnimation.value *
                    (_shakeController.value > 0.5 ? -1 : 1)
                : 0,
            0,
          ),
          child: child,
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (index) {
          final isFilled = index < _pin.length;
          final hasError = _errorText != null;
          return Container(
            margin: EdgeInsets.symmetric(horizontal: dotSize * 0.5),
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isFilled
                  ? (hasError ? Colors.redAccent : _accentColor)
                  : Colors.transparent,
              border: Border.all(
                color: hasError
                    ? Colors.redAccent
                    : (isFilled ? _accentColor : _textSecondary),
                width: 2,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildKeypadButton(String label,
      {VoidCallback? onTap, IconData? icon, required double buttonHeight, required double fontSize, required double iconSize}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: _cardColor,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: buttonHeight,
              alignment: Alignment.center,
              child: icon != null
                  ? Icon(icon, color: _textPrimary, size: iconSize)
                  : Text(
                      label,
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: fontSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isLandscape = screenWidth > screenHeight;
    final isTablet = screenWidth >= 900;

    // Responsive sizing
    final double dialogMaxWidth;
    final double keypadWidth;
    final double buttonHeight;
    final double fontSize;
    final double iconSize;
    final double dotSize;
    final double titleFontSize;
    final double subtitleFontSize;
    final double padding;

    // Cap button height to fit 4 rows + header within available screen height
    final maxButtonHeight = (screenHeight - 280) / 4;

    if (isLandscape && screenWidth >= 900) {
      // Landscape (tablet or large phone) — horizontal layout
      dialogMaxWidth = 400;
      keypadWidth = 300;
      buttonHeight = maxButtonHeight.clamp(48, 60).toDouble();
      fontSize = 24;
      iconSize = 26;
      dotSize = 22;
      titleFontSize = 20;
      subtitleFontSize = 14;
      padding = 24;
    } else if (isTablet) {
      // Tablet portrait
      dialogMaxWidth = 380;
      keypadWidth = 300;
      buttonHeight = maxButtonHeight.clamp(48, 60).toDouble();
      fontSize = 24;
      iconSize = 26;
      dotSize = 22;
      titleFontSize = 20;
      subtitleFontSize = 14;
      padding = 28;
    } else {
      // Phone
      dialogMaxWidth = 320;
      keypadWidth = 240;
      buttonHeight = maxButtonHeight.clamp(44, 56).toDouble();
      fontSize = 22;
      iconSize = 24;
      dotSize = 20;
      titleFontSize = 18;
      subtitleFontSize = 13;
      padding = 24;
    }

    Widget keypadRow(List<Widget> children) => Row(children: children);

    Widget keypad = SizedBox(
      width: keypadWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          keypadRow([
            _buildKeypadButton('1', onTap: () => _onDigitEntered('1'), buttonHeight: buttonHeight, fontSize: fontSize, iconSize: iconSize),
            _buildKeypadButton('2', onTap: () => _onDigitEntered('2'), buttonHeight: buttonHeight, fontSize: fontSize, iconSize: iconSize),
            _buildKeypadButton('3', onTap: () => _onDigitEntered('3'), buttonHeight: buttonHeight, fontSize: fontSize, iconSize: iconSize),
          ]),
          keypadRow([
            _buildKeypadButton('4', onTap: () => _onDigitEntered('4'), buttonHeight: buttonHeight, fontSize: fontSize, iconSize: iconSize),
            _buildKeypadButton('5', onTap: () => _onDigitEntered('5'), buttonHeight: buttonHeight, fontSize: fontSize, iconSize: iconSize),
            _buildKeypadButton('6', onTap: () => _onDigitEntered('6'), buttonHeight: buttonHeight, fontSize: fontSize, iconSize: iconSize),
          ]),
          keypadRow([
            _buildKeypadButton('7', onTap: () => _onDigitEntered('7'), buttonHeight: buttonHeight, fontSize: fontSize, iconSize: iconSize),
            _buildKeypadButton('8', onTap: () => _onDigitEntered('8'), buttonHeight: buttonHeight, fontSize: fontSize, iconSize: iconSize),
            _buildKeypadButton('9', onTap: () => _onDigitEntered('9'), buttonHeight: buttonHeight, fontSize: fontSize, iconSize: iconSize),
          ]),
          keypadRow([
            _buildKeypadButton('C', onTap: _onClear, icon: Icons.clear, buttonHeight: buttonHeight, fontSize: fontSize, iconSize: iconSize),
            _buildKeypadButton('0', onTap: () => _onDigitEntered('0'), buttonHeight: buttonHeight, fontSize: fontSize, iconSize: iconSize),
            _buildKeypadButton('', onTap: _onBackspace, icon: Icons.backspace_outlined, buttonHeight: buttonHeight, fontSize: fontSize, iconSize: iconSize),
          ]),
        ],
      ),
    );

    Widget header = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.lock_outline, color: _accentColor, size: iconSize),
            const SizedBox(width: 8),
            Text(
              'Staff PIN',
              style: TextStyle(
                color: _textPrimary,
                fontSize: titleFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.close, color: _textSecondary),
          onPressed: () => Navigator.pop(context, null),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );

    Widget statusArea = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Enter your 4-digit PIN to continue',
          style: TextStyle(color: _textSecondary, fontSize: subtitleFontSize),
        ),
        SizedBox(height: isTablet ? 28 : 24),
        _buildPinIndicators(dotSize),
        const SizedBox(height: 8),
        SizedBox(
          height: 20,
          child: _errorText != null
              ? Text(
                  _errorText!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                )
              : _isVerifying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _accentColor,
                      ),
                    )
                  : null,
        ),
      ],
    );

    // In landscape with enough width, use horizontal layout: status left, keypad right
    if (isLandscape && screenWidth >= 900) {
      return Dialog(
        backgroundColor: _bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: keypadWidth + 260),
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                header,
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Left side: PIN indicators and status
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline, color: _accentColor, size: 48),
                          const SizedBox(height: 16),
                          statusArea,
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Right side: Keypad
                    keypad,
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Portrait / phone: vertical layout with scroll safety
    return Dialog(
      backgroundColor: _bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogMaxWidth),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                header,
                const SizedBox(height: 8),
                statusArea,
                const SizedBox(height: 16),
                keypad,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
