import 'package:flutter/material.dart';

/// Screens that are much wider than high: landscape phones and handhelds
/// such as the AYN Thor (16:9 top screen).
bool isWideScreen(BoxConstraints c) =>
    c.maxWidth >= 560 && c.maxWidth > c.maxHeight * 1.3;

/// Little height left (landscape phones, handhelds): app bars, banners and
/// paddings get smaller.
bool isShortScreen(BuildContext context) =>
    MediaQuery.sizeOf(context).height < 520;

/// A drop-in replacement for the [Column] of a game screen.
///
/// Upright it is that column. On wide screens the board (every [Expanded] or
/// [Flexible] child) keeps the whole height, the rest – turn banner, scores,
/// buttons – moves into a scrollable panel on the left, in the same order.
class GameLayout extends StatelessWidget {
  const GameLayout({
    super.key,
    required this.children,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.sideWidth,
  });

  final List<Widget> children;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;

  /// Width of the side panel (default: about a third, 220–340).
  final double? sideWidth;

  @override
  Widget build(BuildContext context) {
    Widget column(List<Widget> c) => Column(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      children: c,
    );
    return LayoutBuilder(
      builder: (context, c) {
        final main = [
          for (final w in children)
            if (w is Flexible) w,
        ];
        final side = [
          for (final w in children)
            if (w is! Flexible) w,
        ];
        if (!c.hasBoundedHeight ||
            !isWideScreen(c) ||
            main.isEmpty ||
            side.isEmpty) {
          return column(children);
        }
        final width = sideWidth ?? (c.maxWidth * 0.32).clamp(220.0, 340.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: const ValueKey('gameSidePanel'),
              width: width,
              child: LayoutBuilder(
                builder: (context, s) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: s.maxHeight),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: side,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: column(main)),
          ],
        );
      },
    );
  }
}

/// Marks a child of a [GameLayout] that is part of the board – such as the
/// own hand of cards – without taking up the free height: on wide screens
/// it stays next to the board instead of moving to the side panel.
class GameMain extends Flexible {
  const GameMain({super.key, required super.child}) : super(flex: 0);
}
