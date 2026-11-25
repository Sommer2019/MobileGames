import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_games/core/gamepad.dart';
import 'package:mobile_games/games/snake/snake_screen.dart';
import 'package:mobile_games/ui/game_layout.dart';
import 'package:mobile_games/ui/gamepad_cursor.dart';

void main() {
  testWidgets('right stick moves a pointer, A taps, B goes back', (t) async {
    t.view.physicalSize = const Size(854, 480);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final sticks = StreamController<StickState>();
    final nav = GlobalKey<NavigatorState>();
    var taps = 0;
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        builder: (c, child) => GamepadCursor(
          sticks: sticks.stream,
          onBack: () => nav.currentState?.maybePop(),
          child: child!,
        ),
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                  c,
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Spiel')),
                      body: Align(
                        alignment: Alignment.bottomRight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => taps++,
                          child: const SizedBox(
                            key: ValueKey('target'),
                            width: 100,
                            height: 100,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('Öffnen'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('gamepadCursor')), findsNothing);

    // Without a pointer A presses the focused button (D-pad focus).
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await t.pumpAndSettle();
    expect(find.text('Spiel'), findsOneWidget);

    // Stick to the bottom right: the pointer appears and moves.
    sticks.add(const StickState(Offset.zero, Offset(0.8, 0.6)));
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('gamepadCursor')), findsOneWidget);
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    sticks.add(StickState.zero);
    await t.pump();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await t.pump(const Duration(milliseconds: 500));
    expect(taps, 1);

    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await t.pumpAndSettle();
    expect(find.text('Spiel'), findsNothing);
    await t.pump(const Duration(seconds: 7));
    expect(find.byKey(const ValueKey('gamepadCursor')), findsNothing);
  });

  test('dead zone cuts small deflections', () {
    Gamepad.I.add(const StickState(Offset(0.1, 0.05), Offset(1, 0)));
    expect(Gamepad.I.state.left, Offset.zero);
    expect(Gamepad.I.state.right.dx, closeTo(1, 1e-9));
  });

  testWidgets('GameLayout: side panel only on wide screens', (t) async {
    Future<void> at(Size s) async {
      t.view.physicalSize = s;
      t.view.devicePixelRatio = 1;
      await t.pumpWidget(
        const MaterialApp(
          home: GameLayout(
            children: [
              Text('Banner'),
              Expanded(child: Placeholder()),
              GameMain(child: Text('Hand')),
              Text('Knöpfe'),
            ],
          ),
        ),
      );
    }

    addTearDown(t.view.reset);
    await at(const Size(854, 480));
    final panel = find.byKey(const ValueKey('gameSidePanel'));
    expect(panel, findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text('Banner')), findsOne);
    expect(find.descendant(of: panel, matching: find.text('Knöpfe')), findsOne);
    expect(
      find.descendant(of: panel, matching: find.text('Hand')),
      findsNothing,
    );
    await at(const Size(400, 800));
    expect(panel, findsNothing);
    expect(find.text('Hand'), findsOneWidget);
  });

  testWidgets('Snake on a landscape handheld: A starts, Start pauses', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(1708, 960);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: SnakeScreen()));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await t.pump();
    expect(find.byKey(const ValueKey('snakePause')), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump(const Duration(milliseconds: 300));
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pump();
    expect(find.byKey(const ValueKey('snakeResume')), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await t.pump();
    expect(find.byKey(const ValueKey('snakePause')), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pumpWidget(const SizedBox());
  });
}
