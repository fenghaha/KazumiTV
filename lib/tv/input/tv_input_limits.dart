/// One policy for TV editing, phone requests and rule-import fields. Lengths
/// use UTF-16 code units, matching Dart String.length and Android/HTML inputs.
abstract final class TvInputLimits {
  static const defaultLength = 4096;
  static const maximumLength = 131072;
  static const jsonOverheadBytes = 1024;

  static int normalize(int? requested) =>
      (requested ?? defaultLength).clamp(1, maximumLength).toInt();

  /// A JSON encoder may escape each code unit as six ASCII bytes (\uXXXX).
  static int bodyBytes(int fieldLength) =>
      normalize(fieldLength) * 6 + jsonOverheadBytes;
}
