/// Colones helpers. Amounts travel as integer céntimos (`price_minor`); the UI
/// only accepts whole colones. Never uses floating point.
abstract final class Money {
  /// Largest accepted price: ₡1.000.000.000.
  static const int maxColones = 1000000000;

  /// ₡2.000 · ₡1.234.567,89
  static String crc(int minor) {
    final negative = minor < 0;
    final abs = minor.abs();
    final whole = (abs ~/ 100).toString();
    final cents = abs % 100;
    final buf = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buf.write('.');
      buf.write(whole[i]);
    }
    final out =
        '₡$buf${cents == 0 ? '' : ',${cents.toString().padLeft(2, '0')}'}';
    return negative ? '-$out' : out;
  }

  /// Parses whole colones typed by a merchant ("2000", "2.000", "₡ 2 000").
  /// Returns céntimos, or null if empty/invalid/out of range.
  static int? parseColones(String input) {
    final cleaned = input.replaceAll(RegExp(r'[₡\s.]'), '');
    if (cleaned.isEmpty || !RegExp(r'^\d{1,10}$').hasMatch(cleaned)) {
      return null;
    }
    final colones = int.parse(cleaned);
    if (colones <= 0 || colones > maxColones) return null;
    return colones * 100;
  }

  /// Formats céntimos back into the editable whole-colones text.
  static String editable(int minor) => (minor ~/ 100).toString();
}
