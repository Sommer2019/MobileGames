import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/geo/regions.dart';
import 'package:mobile_games/games/quiz/quiz_logic.dart';
import 'package:mobile_games/games/quiz/quiz_screen.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('every capital belongs to a known country', () {
    expect(capitals.length, greaterThan(190));
    for (final code in capitals.keys) {
      expect(countryByCode, contains(code), reason: code);
    }
    expect(capitals['de'], 'Berlin');
    expect(capitals['au'], 'Canberra');
    expect(flagEmoji('de'), '🇩🇪');
  });

  test('questions: the same everywhere, four different choices', () {
    final a = makeQuestions(42, QuizMode.mixed, 20);
    final b = makeQuestions(42, QuizMode.mixed, 20);
    expect([for (final q in a) q.answer], [for (final q in b) q.answer]);
    expect({for (final q in a) q.answer}, hasLength(20));
    for (final q in a) {
      expect(q.choices.toSet(), hasLength(4));
      expect(q.choices, contains(q.answer));
      expect(q.choiceLabel(q.correct), isNotEmpty);
    }
    final caps = makeQuestions(1, QuizMode.capital, 5);
    expect(caps.every((q) => q.kind == QuestionKind.capital), isTrue);
    expect(
      caps.first.choiceLabel(caps.first.correct),
      capitals[caps.first.answer],
    );
  });

  test('answers, reveal by the host, points for speed', () {
    final g = QuizGame(players: 2);
    expect(
      g.apply([
        'cfg',
        {'mode': 'flag', 'count': 5, 'sec': 10},
      ], 1),
      isFalse,
    );
    expect(
      g.apply([
        'cfg',
        {'mode': 'flag', 'count': 5, 'sec': 10},
      ], 0),
      isTrue,
    );
    expect(g.apply(['start', 7, 1000], 0), isTrue);
    final right = g.question.correct;
    expect(g.apply(['ans', 0, right, 0], 0), isTrue);
    expect(
      g.apply(['ans', 0, (right + 1) % 4, 100], 0),
      isFalse,
      reason: 'once',
    );
    expect(g.apply(['ans', 0, right, 5000], 1), isTrue);
    expect(g.allAnswered, isTrue);
    // The host never got seat 1's answer: it does not count.
    expect(
      g.apply([
        'reveal',
        0,
        {
          '0': [right, 0],
        },
      ], 0),
      isTrue,
    );
    expect(g.points(0, 0), 150);
    expect(g.points(0, 1), 0);
    expect(g.apply(['next', 2000], 0), isTrue);
    expect(g.q, 1);
    g.apply(['ans', 1, g.question.correct, 5000], 1);
    g.apply([
      'reveal',
      1,
      {
        '1': [g.question.correct, 5000],
      },
    ], 0);
    expect(g.points(1, 1), 125);
    for (var i = 1; i < 5; i++) {
      if (g.phase == QuizPhase.question) g.apply(['reveal', g.q, {}], 0);
      g.apply(['next', 0], 0);
    }
    expect(g.isOver, isTrue);
    expect(g.total(0), 150);
    expect(g.total(1), 125);
    expect(g.winners(), [0]);
    expect(QuizGame.replay(2, g.events).total(1), 125);
    expect(g.apply(['new'], 0), isTrue);
    expect(g.phase, QuizPhase.setup);
  });

  testWidgets('Länderquiz alone: answer all, see the score', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: QuizScreen(setup: PlaySetup.local(players: 1))),
    );
    await tester.tap(find.byKey(const ValueKey('quizMode-capital')));
    await tester.pump();
    await tester.tap(find.text('5'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('quizStart')));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      expect(find.textContaining('Was ist die Hauptstadt'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quizChoice0')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
    }
    expect(find.textContaining('von 5 richtig'), findsWidgets);
    expect(find.text('Neues Quiz'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
