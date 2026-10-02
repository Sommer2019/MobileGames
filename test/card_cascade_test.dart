import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/solitaire/card_cascade.dart';
import 'package:mobile_games/games/solitaire/klondike_logic.dart';

void main() {
  List<CascadeCard> cards(int n) => [
    for (var i = 0; i < n; i++)
      CascadeCard(
        PlayingCard(i % 4, 13 - i ~/ 4, faceUp: true),
        Offset(i * 10, 40),
      ),
  ];

  Widget host(List<CascadeCard> c, List<int> launched, VoidCallback done) =>
      MaterialApp(
        home: Scaffold(
          body: CardCascade(
            cards: c,
            cardWidth: 40,
            seed: 1,
            interval: const Duration(milliseconds: 100),
            onLaunch: launched.add,
            onDone: done,
          ),
        ),
      );

  testWidgets('every card flies off, then it is done', (tester) async {
    final launched = <int>[];
    var done = false;
    await tester.pumpWidget(host(cards(6), launched, () => done = true));
    for (var i = 0; i < 1500 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(launched, [0, 1, 2, 3, 4, 5]);
    expect(done, isTrue);
  });

  testWidgets('a tap skips the animation', (tester) async {
    final launched = <int>[];
    var done = 0;
    await tester.pumpWidget(host(cards(52), launched, () => done++));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('cardCascade')));
    await tester.pump(const Duration(seconds: 1));
    expect(done, 1);
    expect(launched.length, lessThan(52));
  });
}
