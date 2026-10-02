import 'package:flutter/services.dart';

/// Player names: no emoji or pictographs (the 🎮 badge must not be
/// fakeable), single spaces, at most [maxLength] characters.
const int maxNameLength = 24;

bool _isPictograph(int c) =>
    (c >= 0x1F000 && c <= 0x1FAFF) || // emoji, flags, symbols
    (c >= 0x2600 && c <= 0x27BF) || // misc symbols, dingbats
    (c >= 0x2300 && c <= 0x23FF) || // technical (⌚ ⏰ …)
    (c >= 0x2B00 && c <= 0x2BFF) || // arrows, stars (⭐)
    (c >= 0x2190 && c <= 0x21FF) || // arrows
    (c >= 0x25A0 && c <= 0x25FF) || // geometric shapes
    (c >= 0xFE00 && c <= 0xFE0F) || // variation selectors
    (c >= 0xE0000 && c <= 0xE007F) || // tags
    c == 0x200D || // zero width joiner
    c == 0x20E3 || // keycap
    c == 0x3030 ||
    c == 0x303D ||
    c == 0x3297 ||
    c == 0x3299 ||
    (c < 0x20) ||
    (c >= 0x7F && c < 0xA0);

String _strip(String s) =>
    String.fromCharCodes(s.runes.where((c) => !_isPictograph(c)));

/// Cleans a name; empty if nothing usable is left.
String cleanName(String name) {
  final s = _strip(name).replaceAll(RegExp(r'\s+'), ' ').trim();
  final runes = s.runes.toList();
  return runes.length > maxNameLength
      ? String.fromCharCodes(runes.take(maxNameLength)).trim()
      : s;
}

/// For names received from others: null if missing or empty after cleaning.
String? cleanNameOrNull(Object? name) {
  if (name is! String) return null;
  final s = cleanName(name);
  return s.isEmpty ? null : s;
}

/// Keeps emoji out of the name field while typing.
class NameInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = _strip(newValue.text);
    if (cleaned == newValue.text) return newValue;
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
    );
  }
}
