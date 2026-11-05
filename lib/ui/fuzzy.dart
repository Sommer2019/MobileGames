import 'dart:math';

/// Lower case without accents, so "wurfel" finds "Würfel".
String plainText(String s) => s
    .toLowerCase()
    .replaceAll('ä', 'a')
    .replaceAll('ö', 'o')
    .replaceAll('ü', 'u')
    .replaceAll('ß', 'ss')
    .replaceAll(RegExp('[éèê]'), 'e');

/// Edit distance (insert, delete, replace, swap two neighbours).
int editDistance(String a, String b) {
  final d = List.generate(a.length + 1, (i) => List.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = min(
        min(d[i - 1][j] + 1, d[i][j - 1] + 1),
        d[i - 1][j - 1] + cost,
      );
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        v = min(v, d[i - 2][j - 2] + 1);
      }
      d[i][j] = v;
    }
  }
  return d[a.length][b.length];
}

/// Whether every word of [query] is found in [text], allowing small typos:
/// one for words of 4+ letters, two for 7+. A word also matches the start
/// of a longer word ("schak" → "Schach", "solitar" → "Solitär").
bool fuzzyMatch(String query, String text) {
  final words = plainText(text).split(RegExp(r'[^a-z0-9]+'))
    ..removeWhere((w) => w.isEmpty);
  final whole = plainText(text);
  for (final q in plainText(query).split(RegExp(r'\s+'))) {
    if (q.isEmpty || whole.contains(q)) continue;
    final allowed = q.length >= 7
        ? 2
        : q.length >= 4
        ? 1
        : 0;
    if (allowed == 0) return false;
    final ok = words.any((w) {
      if (editDistance(q, w) <= allowed) return true;
      // Typo in the beginning of a longer word.
      if (w.length > q.length) {
        for (final n in [q.length - 1, q.length, q.length + 1]) {
          if (n > 0 &&
              n <= w.length &&
              editDistance(q, w.substring(0, n)) <= allowed) {
            return true;
          }
        }
      }
      return false;
    });
    if (!ok) return false;
  }
  return true;
}
