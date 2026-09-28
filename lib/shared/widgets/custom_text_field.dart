import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';

/// Labelled text field. Borders, fill and focus colors come from the theme's
/// InputDecorationTheme. Keyboard behaviour defaults from [keyboardType]:
/// emails and passwords get no autocorrect or suggestions; names can pass
/// `textCapitalization: TextCapitalization.words`.
class CustomTextField extends StatelessWidget {
  final String? label;
  final String? hint;
  final String? hintText;
  final String? helperText;
  final TextEditingController? controller;
  final IconData? prefixIcon;
  final String? prefixText;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType keyboardType;
  final int maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final String? Function(String?)? validator;
  final bool readOnly;
  final VoidCallback? onTap;
  final String? errorText;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization? textCapitalization;
  final TextInputAction? textInputAction;
  final bool? autocorrect;
  final bool? enableSuggestions;
  final Iterable<String>? autofillHints;
  final FocusNode? focusNode;
  final bool enabled;

  const CustomTextField({
    super.key,
    this.label,
    this.hint,
    this.hintText,
    this.helperText,
    this.controller,
    this.prefixIcon,
    this.prefixText,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
    this.onFieldSubmitted,
    this.validator,
    this.readOnly = false,
    this.onTap,
    this.errorText,
    this.inputFormatters,
    this.textCapitalization,
    this.textInputAction,
    this.autocorrect,
    this.enableSuggestions,
    this.autofillHints,
    this.focusNode,
    this.enabled = true,
  });

  bool get _isCredential =>
      obscureText || keyboardType == TextInputType.emailAddress || keyboardType == TextInputType.visiblePassword;

  @override
  Widget build(BuildContext context) {
    final multiline = maxLines > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
          const SizedBox(height: 8),
        ],
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          readOnly: readOnly,
          onTap: onTap,
          obscureText: obscureText,
          keyboardType: multiline && keyboardType == TextInputType.text ? TextInputType.multiline : keyboardType,
          maxLines: obscureText ? 1 : maxLines,
          maxLength: maxLength,
          onChanged: onChanged,
          onFieldSubmitted: onFieldSubmitted,
          validator: validator,
          inputFormatters: inputFormatters,
          autofillHints: autofillHints,
          textCapitalization:
              textCapitalization ?? (multiline ? TextCapitalization.sentences : TextCapitalization.none),
          textInputAction: textInputAction ?? (multiline ? TextInputAction.newline : null),
          autocorrect: autocorrect ?? !_isCredential,
          enableSuggestions: enableSuggestions ?? !_isCredential,
          style: AppTypography.body.copyWith(color: AppColors.ink, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint ?? hintText,
            helperText: helperText,
            helperMaxLines: 2,
            errorText: errorText,
            errorMaxLines: 3,
            prefixText: prefixText,
            prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 20) : null,
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}
