import 'package:flutter/material.dart';
import 'package:kazumi/tv/input/tv_text_input.dart';
import 'package:kazumi/tv/tv_mode.dart';

/// Keep original fields on touch/desktop; TV editing lives in a native dialog.
class TvAdaptiveTextField extends StatelessWidget {
  const TvAdaptiveTextField({
    super.key,
    required this.controller,
    this.decoration = const InputDecoration(),
    this.enabled = true,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.onChanged,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final InputDecoration decoration;
  final bool enabled, obscureText, autocorrect, enableSuggestions;
  final ValueChanged<String>? onChanged, onSubmitted;
  @override
  Widget build(BuildContext context) {
    if (!TvMode.enabled) {
      return TextField(
        controller: controller,
        decoration: decoration,
        enabled: enabled,
        obscureText: obscureText,
        autocorrect: autocorrect,
        enableSuggestions: enableSuggestions,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      );
    }
    return _tvField(
      controller: controller,
      decoration: decoration,
      enabled: enabled,
      obscureText: obscureText,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

class TvAdaptiveTextFormField extends StatelessWidget {
  const TvAdaptiveTextFormField({
    super.key,
    required this.controller,
    this.decoration = const InputDecoration(),
    this.enabled = true,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.keyboardType,
    this.textInputAction,
    this.onFieldSubmitted,
    this.validator,
  });
  final TextEditingController controller;
  final InputDecoration decoration;
  final bool enabled, obscureText, autocorrect, enableSuggestions;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldValidator<String>? validator;
  @override
  Widget build(BuildContext context) {
    if (!TvMode.enabled) {
      return TextFormField(
        controller: controller,
        decoration: decoration,
        enabled: enabled,
        obscureText: obscureText,
        autocorrect: autocorrect,
        enableSuggestions: enableSuggestions,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        validator: validator,
        onFieldSubmitted: onFieldSubmitted,
      );
    }
    return FormField<String>(
      initialValue: controller.text,
      enabled: enabled,
      validator: (_) => validator?.call(controller.text),
      builder: (field) => _tvField(
        controller: controller,
        decoration: decoration.copyWith(
          errorText: field.errorText ?? decoration.errorText,
        ),
        enabled: enabled,
        obscureText: obscureText,
        onChanged: field.didChange,
        onSubmitted: onFieldSubmitted,
      ),
    );
  }
}

Widget _tvField({
  required TextEditingController controller,
  required InputDecoration decoration,
  required bool enabled,
  required bool obscureText,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
}) => InputDecorator(
  decoration: InputDecoration(
    errorText: decoration.errorText,
    errorMaxLines: decoration.errorMaxLines,
    helperText: decoration.helperText,
    helperMaxLines: decoration.helperMaxLines,
    suffixIcon: decoration.suffixIcon,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    contentPadding: EdgeInsets.zero,
    filled: false,
    enabled: enabled,
  ),
  child: TvTextInput(
    controller: controller,
    label: decoration.labelText,
    hintText: decoration.hintText,
    enabled: enabled,
    obscureText: obscureText,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
  ),
);
