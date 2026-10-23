import 'package:flutter/services.dart';

/// Thin platform boundary; the upstream Flutter text-input implementation is
/// untouched. A real Android EditText owns the IME only while this dialog is open.
class TvNativeInput {
  TvNativeInput._();

  static const channel = MethodChannel('kazumi/tv');

  static Future<String?> edit({
    required String title,
    required String text,
    bool obscureText = false,
    bool multiline = false,
    int? maxLength,
  }) => channel.invokeMethod<String>('editText', {
    'title': title,
    'text': text,
    'obscureText': obscureText,
    'multiline': multiline,
    'maxLength': maxLength,
  });
}
