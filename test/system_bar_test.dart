import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/main.dart';

void main() {
  Widget app(MediaQueryData data) => MediaQuery(
    data: data,
    child: const Directionality(
      textDirection: TextDirection.ltr,
      child: SystemBarInsets(child: SizedBox.expand(key: ValueKey('c'))),
    ),
  );

  testWidgets('content stays above the navigation bar', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const nav = EdgeInsets.only(top: 24, bottom: 48);
    await tester.pumpWidget(
      app(const MediaQueryData(padding: nav, viewPadding: nav)),
    );
    final box = tester.getRect(find.byKey(const ValueKey('c')));
    expect(box.bottom, 800 - 48);
    final inner = MediaQuery.of(
      tester.element(find.byKey(const ValueKey('c'))),
    );
    expect(inner.padding.bottom, 0);
    expect(inner.padding.top, 24);

    // With the keyboard open, the keyboard inset alone counts.
    await tester.pumpWidget(
      app(
        const MediaQueryData(
          padding: EdgeInsets.only(top: 24),
          viewPadding: nav,
          viewInsets: EdgeInsets.only(bottom: 300),
        ),
      ),
    );
    expect(tester.getRect(find.byKey(const ValueKey('c'))).bottom, 800);
  });
}
