import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction,
    this.focusNode,
    this.style,
    this.textAlignVertical,
    this.onTapOutside,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
  });
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final TextStyle? style;
  final TextAlignVertical? textAlignVertical;
  final TapRegionCallback? onTapOutside;
  final List<TextInputFormatter>? inputFormatters;
  final TextEditingController controller;
  final InputDecoration decoration;
  final bool enabled, obscureText, autocorrect, enableSuggestions;
  final ValueChanged<String>? onChanged, onSubmitted;
  @override
  Widget build(BuildContext context) {
    if (!TvMode.enabled) {
      return TextField(
        autofocus: autofocus,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        focusNode: focusNode,
        style: style,
        textAlignVertical: textAlignVertical,
        onTapOutside: onTapOutside,
        inputFormatters: inputFormatters,
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
      autofocus: autofocus,
      focusNode: focusNode,
      inputFormatters: inputFormatters,
      controller: controller,
      decoration: decoration,
      enabled: enabled && decoration.enabled,
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
    this.autofocus = false,
    this.inputFormatters,
    this.autovalidateMode,
    this.onFieldSubmitted,
    this.validator,
  });
  final TextEditingController controller;
  final InputDecoration decoration;
  final bool enabled, obscureText, autocorrect, enableSuggestions;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final List<TextInputFormatter>? inputFormatters;
  final AutovalidateMode? autovalidateMode;
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldValidator<String>? validator;
  @override
  Widget build(BuildContext context) {
    if (!TvMode.enabled) {
      return TextFormField(
        autofocus: autofocus,
        inputFormatters: inputFormatters,
        autovalidateMode: autovalidateMode,
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
      autovalidateMode: autovalidateMode,
      initialValue: controller.text,
      enabled: enabled,
      validator: (_) => validator?.call(controller.text),
      builder: (field) => _tvField(
        autofocus: autofocus,
        inputFormatters: inputFormatters,
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
  bool autofocus = false,
  FocusNode? focusNode,
  List<TextInputFormatter>? inputFormatters,
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
    autofocus: autofocus,
    focusNode: focusNode,
    inputFormatters: inputFormatters,
    label: decoration.labelText,
    hintText: decoration.hintText,
    enabled: enabled,
    obscureText: obscureText,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
  ),
);

/// Dialog fields without a page-owned controller keep it until route disposal,
/// including the reverse transition on non-TV platforms.
class TvOwnedTextField extends StatefulWidget {
  const TvOwnedTextField({
    super.key,
    required this.builder,
    this.initialValue = '',
  });
  final String initialValue;
  final Widget Function(TextEditingController) builder;
  @override
  State<TvOwnedTextField> createState() => _TvOwnedTextFieldState();
}

class _TvOwnedTextFieldState extends State<TvOwnedTextField> {
  late final _controller = TextEditingController(text: widget.initialValue);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_controller);
}
