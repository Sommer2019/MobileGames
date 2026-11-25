import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/companion/companion_app.dart';
import 'package:mobile_games/core/companion.dart';
import 'package:mobile_games/games/battleship/battleship_screen.dart';
import 'package:mobile_games/games/prophet/prophet_screen.dart';
import 'package:mobile_games/games/snake/snake_screen.dart';
import 'package:mobile_games/games/sudoku/sudoku_screen.dart';
import 'package:mobile_games/games/yahtzee/yahtzee_screen.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final sent = <CompanionPage>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sent.clear();
    Companion.I.reset();
    Companion.I.sendOverride = (json) async => sent.add(
      CompanionPage.fromJson(jsonDecode(json) as Map<String, dynamic>),
    );
  });

  test('pages survive the trip between the engines', () {
    const page = CompanionPage(
      title: 'T',
      status: 'S',
      statusColor: 0xFF112233,
      table: CompanionTable(
        columns: ['', 'A', 'B'],
        highlight: 2,
        rows: [
          CompanionRow(['x', '1', ''], actions: {2: 'go'}),
          CompanionRow(['Σ', '1', '0'], bold: true),
        ],
      ),
      buttonsTitle: 'Wähle',
      buttons: [CompanionButton('a', 'Eins', color: 0xFF00FF00)],
      hint: 'h',
    );
    final back = CompanionPage.fromJson(
      jsonDecode(jsonEncode(page.toJson())) as Map<String, dynamic>,
    );
    expect(jsonEncode(back.toJson()), jsonEncode(page.toJson()));
    expect(back.table!.rows.first.actions, {2: 'go'});
  });

  testWidgets('Kniffel: dice on top, the block below, scoring from below', (
    t,
  ) async {
    Companion.I.hasScreen.value = true;
    Companion.I.active.value = true;
    t.view.physicalSize = const Size(1708, 960);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      const MaterialApp(home: YahtzeeScreen(setup: PlaySetup.ai())),
    );
    await t.pump();
    // No sheet on top while the lower screen shows it.
    expect(find.byKey(const ValueKey('score-0-chance')), findsNothing);
    var page = sent.last;
    expect(page.title, 'Würfelkönig – Block');
    expect(page.status, contains('Du bist dran'));
    expect(page.table!.columns, ['', 'Du', 'Computer']);
    expect(page.buttons.single.action, 'roll');

    Companion.I.action('roll');
    await t.pump();
    await t.pump();
    page = sent.last;
    final chance = page.table!.rows.indexWhere((r) => r.cells[0] == 'Chance');
    expect(page.table!.rows[chance].actions[1], 'score:chance');

    Companion.I.action('score:chance');
    await t.pump();
    await t.pump();
    expect(sent.last.status, contains('Computer ist dran'));
    final row = sent.last.table!.rows.firstWhere((r) => r.cells[0] == 'Chance');
    expect(int.parse(row.cells[1]), greaterThan(4));
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
    await t.pumpWidget(const SizedBox());
    await t.pump();
    // Leaving the game clears the lower screen.
    expect(sent.last.table, isNull);
  });

  testWidgets('Stichprophet: block and bids on the lower screen', (t) async {
    Companion.I.hasScreen.value = true;
    Companion.I.active.value = true;
    t.view.physicalSize = const Size(1708, 960);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      const MaterialApp(
        home: ProphetScreen(setup: PlaySetup.local(players: 3, bots: {1, 2})),
      ),
    );
    var bid = false;
    for (var i = 0; i < 200 && !bid; i++) {
      await t.pump(const Duration(milliseconds: 300));
      final p = sent.isEmpty ? null : sent.last;
      if (p == null) continue;
      if (p.buttons.any((b) => b.action.startsWith('trump:'))) {
        Companion.I.action('trump:0');
        continue;
      }
      if (p.buttons.any((b) => b.action == 'bid:1')) {
        expect(p.table!.columns, ['Runde', 'Du', 'Computer 1', 'Computer 2']);
        expect(p.table!.rows.last.cells.first, 'Gesamt');
        Companion.I.action('bid:1');
        bid = true;
      }
    }
    expect(bid, isTrue);
    await t.pump(const Duration(milliseconds: 300));
    await t.pump();
    final ansage = sent.last.table!.rows.firstWhere(
      (r) => r.cells.first.contains('Ansage'),
    );
    expect(ansage.cells[1], '0/1');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('lower screen: idle help, then a tappable block', (t) async {
    t.view.physicalSize = const Size(1240, 1080);
    t.view.devicePixelRatio = 2.25;
    addTearDown(t.view.reset);
    final pages = StreamController<CompanionPage>();
    final actions = <String>[];
    await t.pumpWidget(
      CompanionApp(pages: pages.stream, onAction: actions.add),
    );
    expect(find.text('Mobile Games'), findsOneWidget);
    pages.add(
      const CompanionPage(
        title: 'Würfelkönig – Block',
        status: 'Du bist dran',
        table: CompanionTable(
          columns: ['', 'Du'],
          rows: [
            CompanionRow(['Chance', '23'], actions: {1: 'score:chance'}),
          ],
        ),
        buttons: [CompanionButton('roll', 'Würfeln')],
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Du bist dran'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('companion-cell-0-1')));
    await t.tap(find.byKey(const ValueKey('companion-roll')));
    expect(actions, ['score:chance', 'roll']);
  });

  Future<void> handheld(WidgetTester t, Widget home) async {
    Companion.I.hasScreen.value = true;
    Companion.I.active.value = true;
    t.view.physicalSize = const Size(1708, 960);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: home));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await t.pump();
    await t.pump();
  }

  testWidgets('Sudoku: digit pad below, D-pad picks the field above', (
    t,
  ) async {
    await handheld(t, const SudokuScreen());
    expect(find.byKey(const ValueKey('sudokuDigit1')), findsNothing);
    var page = sent.last;
    expect(page.grid!.columns, 3);
    expect(page.grid!.cells.map((c) => c.label), [
      for (var v = 1; v <= 9; v++) '$v',
    ]);
    // Find an empty field with the arrow keys, then enter a digit below.
    String cellText(int i) => (t.widget<Text>(
      find
          .descendant(
            of: find.byKey(ValueKey('sudokuCell$i')),
            matching: find.byType(Text),
          )
          .first,
    )).data!;
    var i = 40;
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    i = 41;
    while (find
        .descendant(
          of: find.byKey(ValueKey('sudokuCell$i')),
          matching: find.byType(Text),
        )
        .evaluate()
        .isNotEmpty) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      i = i ~/ 9 * 9 + (i % 9 + 1) % 9;
      if (i == 36) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        i = 45;
      }
    }
    await t.pump();
    final digit = page.grid!.cells.indexWhere((c) => c.action != null) + 1;
    Companion.I.action('d:$digit');
    await t.pump();
    expect(cellText(i), '$digit');
    Companion.I.action('undo');
    await t.pump();
    await t.pump();
    page = sent.last;
    expect(page.buttons.map((b) => b.action), ['undo', 'erase', 'notes']);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Schiffe versenken: own fleet on the lower screen', (t) async {
    await handheld(t, const BattleshipScreen(setup: PlaySetup.ai()));
    await t.tap(find.byKey(const ValueKey('fleetReady')));
    await t.pump();
    await t.pump();
    final page = sent.last;
    expect(page.title, 'Deine Flotte');
    expect(page.grid!.cells, hasLength(100));
    expect(page.grid!.cells.where((c) => c.color == 0xFF90A4AE), isNotEmpty);
    // Only the enemy sea is left on top.
    expect(find.text('Deine Flotte'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Snake: start and pause from below', (t) async {
    await handheld(t, const SnakeScreen());
    expect(sent.last.buttons.map((b) => b.action), ['start', 'wrap']);
    Companion.I.action('wrap');
    await t.pump();
    await t.pump();
    expect(sent.last.table!.rows.last.cells.last, 'durchlässig');
    Companion.I.action('start');
    await t.pump();
    await t.pump();
    expect(sent.last.buttons.single.action, 'pause');
    Companion.I.action('pause');
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('snakeResume')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
