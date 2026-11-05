import 'dart:math';

import '../geo/regions.dart';
import 'capitals.dart';

/// Capital per country code (sovereign states only).
final Map<String, String> capitals = {
  for (final line in capitalsTable.split('\n'))
    if (line.trim().isNotEmpty) line.substring(0, 2): line.substring(3),
};

enum QuizMode {
  flag('Flagge → Land'),
  capital('Land → Hauptstadt'),
  country('Hauptstadt → Land'),
  mixed('Gemischt');

  const QuizMode(this.label);
  final String label;
}

enum QuestionKind { flag, capital, country }

/// One question: what is asked about [answer] and four choices (country
/// codes, one of them the answer).
class QuizQuestion {
  const QuizQuestion(this.kind, this.answer, this.choices);
  final QuestionKind kind;
  final String answer;
  final List<String> choices;

  int get correct => choices.indexOf(answer);

  String get countryName => countryByCode[answer]!.name;

  /// The text of the question (flags show the picture instead).
  String get prompt => switch (kind) {
    QuestionKind.flag => 'Welches Land hat diese Flagge?',
    QuestionKind.capital => 'Was ist die Hauptstadt von $countryName?',
    QuestionKind.country => '${capitals[answer]} ist die Hauptstadt von …',
  };

  String choiceLabel(int i) {
    final c = choices[i];
    return kind == QuestionKind.capital ? capitals[c]! : countryByCode[c]!.name;
  }
}

/// The same questions on every device from [seed].
List<QuizQuestion> makeQuestions(int seed, QuizMode mode, int count) {
  final rnd = Random(seed);
  final codes = capitals.keys.where(countryByCode.containsKey).toList()..sort();
  final pool = List.of(codes)..shuffle(rnd);
  return [
    for (final answer in pool.take(count))
      () {
        final kind = switch (mode) {
          QuizMode.flag => QuestionKind.flag,
          QuizMode.capital => QuestionKind.capital,
          QuizMode.country => QuestionKind.country,
          QuizMode.mixed => QuestionKind.values[rnd.nextInt(3)],
        };
        // Wrong choices from the same continent if possible: harder.
        final continent = countryByCode[answer]!.continent;
        final near = codes
            .where(
              (c) => c != answer && countryByCode[c]!.continent == continent,
            )
            .toList();
        final far = codes.where((c) => c != answer && !near.contains(c));
        final others = (near..shuffle(rnd)).take(3).toList();
        if (others.length < 3) {
          others.addAll((far.toList()..shuffle(rnd)).take(3 - others.length));
        }
        final choices = [answer, ...others]..shuffle(rnd);
        return QuizQuestion(kind, answer, choices);
      }(),
  ];
}

enum QuizPhase { setup, question, reveal, results }

/// Länderquiz: flags and capitals, four choices, points for right
/// answers and for speed.
///
/// Played through [apply] with plain events (seat of the sender given):
/// host only: `['cfg', {mode, count, sec}]`, `['start', seed, epochMs]`,
/// `['reveal', q, {seat: [choice, ms]}]`, `['next', epochMs]`, `['new']`;
/// everybody: `['ans', q, choice, ms]`.
class QuizGame {
  QuizGame({required this.players});

  static const counts = [5, 10, 15, 20];
  static const secondChoices = [10, 15, 20, 30];

  final int players;
  final List<List> events = [];

  QuizPhase phase = QuizPhase.setup;
  QuizMode mode = QuizMode.mixed;
  int count = 10;
  int seconds = 15;

  List<QuizQuestion> questions = [];
  int q = 0;
  int startedAt = 0;

  /// question → seat → (choice, milliseconds taken).
  final Map<int, Map<int, (int, int)>> answers = {};

  bool get isOver => phase == QuizPhase.results;
  QuizQuestion get question => questions[q];
  bool get lastQuestion => q + 1 >= questions.length;

  bool apply(List e, int seat) {
    final host = seat == 0;
    switch (e) {
      case ['cfg', final Map c] when host && phase == QuizPhase.setup:
        final m = QuizMode.values.asNameMap()[c['mode']];
        final n = c['count'], s = c['sec'];
        if (m == null || !counts.contains(n) || !secondChoices.contains(s)) {
          return false;
        }
        mode = m;
        count = n as int;
        seconds = s as int;
      case ['start', final int seed, final int at]
          when host && phase == QuizPhase.setup:
        questions = makeQuestions(seed, mode, count);
        q = 0;
        answers.clear();
        startedAt = at;
        phase = QuizPhase.question;
      case ['ans', final int i, final int choice, final int ms]
          when phase == QuizPhase.question && i == q:
        if (choice < 0 || choice > 3 || ms < 0 || seat >= players) {
          return false;
        }
        final a = answers[q] ??= {};
        if (a.containsKey(seat)) return false;
        a[seat] = (choice, min(ms, seconds * 1000));
      case ['reveal', final int i, final Map a]
          when host && phase == QuizPhase.question && i == q:
        final all = <int, (int, int)>{};
        for (final MapEntry(:key, :value) in a.entries) {
          final s = int.tryParse('$key');
          if (s == null || s < 0 || s >= players || value is! List) continue;
          if (value.length != 2 || value.any((x) => x is! int)) continue;
          all[s] = (value[0] as int, value[1] as int);
        }
        answers[q] = all;
        phase = QuizPhase.reveal;
      case ['next', final int at] when host && phase == QuizPhase.reveal:
        if (lastQuestion) {
          phase = QuizPhase.results;
        } else {
          q++;
          startedAt = at;
          phase = QuizPhase.question;
        }
      case ['new'] when host && phase == QuizPhase.results:
        phase = QuizPhase.setup;
        questions = [];
        answers.clear();
      default:
        return false;
    }
    events.add([seat, ...e]);
    return true;
  }

  factory QuizGame.replay(int players, List log) {
    final g = QuizGame(players: players);
    for (final x in log) {
      final l = List.from(x as List);
      g.apply(l.sublist(1), l.first as int);
    }
    return g;
  }

  int timeLeft(int now) => max(0, startedAt + seconds * 1000 - now);

  bool answered(int seat) => answers[q]?.containsKey(seat) ?? false;

  bool get allAnswered => [for (var p = 0; p < players; p++) p].every(answered);

  /// 100 for a right answer plus up to 50 for speed.
  int points(int question, int seat) {
    final a = answers[question]?[seat];
    if (a == null || a.$1 != questions[question].correct) return 0;
    return 100 + (50 * (1 - a.$2 / (seconds * 1000))).round().clamp(0, 50);
  }

  int total(int seat) {
    final done = phase == QuizPhase.question ? q : questions.length;
    var sum = 0;
    for (var i = 0; i < done; i++) {
      sum += points(i, seat);
    }
    return sum;
  }

  int rightAnswers(int seat) {
    var n = 0;
    for (var i = 0; i < questions.length; i++) {
      if (points(i, seat) > 0) n++;
    }
    return n;
  }

  List<int> winners() {
    final best = [for (var p = 0; p < players; p++) total(p)].reduce(max);
    return [
      for (var p = 0; p < players; p++)
        if (total(p) == best) p,
    ];
  }
}

/// The flag as an emoji (regional indicator letters).
String flagEmoji(String code) => String.fromCharCodes([
  for (final c in code.toUpperCase().codeUnits) 0x1F1E6 + c - 0x41,
]);
