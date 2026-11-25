import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/companion.dart';

/// The app on the lower screen of dual-screen handhelds (AYN Thor). It runs
/// in its own engine without plugins and only shows what the game on the
/// main screen sends (see [Companion]).
class CompanionApp extends StatefulWidget {
  const CompanionApp({super.key, this.pages, this.onAction});

  /// Pages to show; by default from the main app through the platform.
  final Stream<CompanionPage>? pages;

  /// Where taps go; by default back to the main app.
  final void Function(String action)? onAction;

  @override
  State<CompanionApp> createState() => _CompanionAppState();
}

class _CompanionAppState extends State<CompanionApp> {
  static const _channel = MethodChannel('mobilegames/companion');
  CompanionPage _page = const CompanionPage();
  StreamSubscription<CompanionPage>? _sub;

  @override
  void initState() {
    super.initState();
    final pages = widget.pages;
    if (pages != null) {
      _sub = pages.listen((p) => setState(() => _page = p));
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'page') _show(call.arguments as String?);
      // Shown as an activity of its own: closes with the game.
      if (call.method == 'close') SystemNavigator.pop();
      return null;
    });
    // The main app may have sent its page before this engine was up.
    _channel
        .invokeMethod<String>('ready')
        .then(_show)
        .catchError((Object _) {});
  }

  void _show(String? json) {
    if (json == null || !mounted) return;
    try {
      final p = CompanionPage.fromJson(
        (jsonDecode(json) as Map).cast<String, dynamic>(),
      );
      setState(() => _page = p);
    } catch (_) {}
  }

  void _act(String a) {
    HapticFeedback.selectionClick();
    final cb = widget.onAction;
    if (cb != null) {
      cb(a);
    } else {
      _channel.invokeMethod<void>('action', a).catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3F51B5),
        brightness: Brightness.dark,
        visualDensity: VisualDensity.compact,
      ),
      home: Scaffold(
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _isEmpty(_page)
                ? const _IdlePage(key: ValueKey('companionIdle'))
                : CompanionPageView(
                    key: const ValueKey('companionPage'),
                    page: _page,
                    onAction: _act,
                  ),
          ),
        ),
      ),
    );
  }

  static bool _isEmpty(CompanionPage p) =>
      p.title == null &&
      p.status == null &&
      p.table == null &&
      p.grid == null &&
      p.buttons.isEmpty;
}

/// Shows one [CompanionPage]: title, turn, score sheet, buttons.
class CompanionPageView extends StatelessWidget {
  const CompanionPageView({
    super.key,
    required this.page,
    required this.onAction,
  });

  final CompanionPage page;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final table = page.table;
    final status = page.status;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (page.title != null)
            Text(
              page.title!,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          if (status != null)
            Container(
              key: const ValueKey('companionStatus'),
              margin: const EdgeInsets.only(top: 4, bottom: 6),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: page.statusColor != null
                    ? Color(page.statusColor!)
                    : scheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                status,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (page.grid case final grid?)
            Expanded(
              flex: table == null ? 1 : 2,
              child: _GridView(grid: grid, onAction: onAction),
            ),
          if (table != null)
            Expanded(
              flex: 3,
              child: _SheetView(table: table, onAction: onAction),
            )
          else if (page.grid == null)
            const Spacer(),
          if (page.buttons.isNotEmpty) ...[
            if (page.buttonsTitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Text(
                  page.buttonsTitle!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final b in page.buttons)
                  FilledButton(
                    key: ValueKey('companion-${b.action}'),
                    style: b.color == null
                        ? null
                        : FilledButton.styleFrom(
                            backgroundColor: Color(b.color!),
                            foregroundColor: Colors.white,
                          ),
                    onPressed: () => onAction(b.action),
                    child: Text(b.label),
                  ),
              ],
            ),
          ],
          if (page.chat.isNotEmpty || page.replies.isNotEmpty)
            _ChatStrip(page: page, onAction: onAction),
          if (page.hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                page.hint!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A score sheet like on paper: fills the screen, rows shrink to fit.
class _SheetView extends StatelessWidget {
  const _SheetView({required this.table, required this.onAction});
  final CompanionTable table;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        // A table of label/value pairs needs no header.
        final header = table.columns.any((c) => c.isNotEmpty);
        final rows = table.rows.length + (header ? 1 : 0);
        final h = (c.maxHeight / rows).clamp(16.0, 40.0) - 1;
        Widget cell(String text, {bool bold = false, Alignment? align}) =>
            SizedBox(
              height: h,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: align ?? Alignment.center,
                  child: Text(
                    text,
                    style: TextStyle(fontWeight: bold ? FontWeight.bold : null),
                  ),
                ),
              ),
            );
        final sheet = Table(
          border: TableBorder.all(color: theme.dividerColor),
          columnWidths: const {0: FlexColumnWidth(2)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            if (header)
              TableRow(
                children: [
                  for (var i = 0; i < table.columns.length; i++)
                    Container(
                      color: i == table.highlight
                          ? scheme.secondaryContainer
                          : null,
                      child: cell(table.columns[i], bold: true),
                    ),
                ],
              ),
            for (final (r, row) in table.rows.indexed)
              TableRow(
                children: [
                  for (var i = 0; i < table.columns.length; i++)
                    _cell(
                      context,
                      row,
                      r,
                      i,
                      cell(
                        i < row.cells.length ? row.cells[i] : '',
                        bold: row.bold,
                        align: i == 0 ? Alignment.centerLeft : null,
                      ),
                    ),
                ],
              ),
          ],
        );
        return h * rows <= c.maxHeight + 1
            ? Align(alignment: Alignment.topCenter, child: sheet)
            : SingleChildScrollView(child: sheet);
      },
    );
  }

  Widget _cell(BuildContext context, CompanionRow row, int r, int i, Widget w) {
    final a = row.actions[i];
    if (a == null) return w;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey('companion-cell-$r-$i'),
      onTap: () => onAction(a),
      child: ColoredBox(
        color: scheme.primaryContainer.withValues(alpha: 0.6),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: scheme.primary),
          child: w,
        ),
      ),
    );
  }
}

/// Nothing to show for this game: how the controls work.
class _IdlePage extends StatelessWidget {
  const _IdlePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget line(String key, String what) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 92,
            padding: const EdgeInsets.symmetric(vertical: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              key,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(what)),
        ],
      ),
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎮', style: TextStyle(fontSize: 44)),
              Text('Mobile Games', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              line('A', 'drücken'),
              line('B', 'zurück'),
              line('✚ / L-Stick', 'zwischen Knöpfen wechseln'),
              line('R-Stick', 'Zeiger – A oder R1 tippt'),
              line('Start', 'Pause (Snake)'),
              const SizedBox(height: 12),
              Text(
                'Hier unten erscheinen bei manchen Spielen Block, Punkte '
                'und Knöpfe.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Square fields as big as the space allows.
class _GridView extends StatelessWidget {
  const _GridView({required this.grid, required this.onAction});
  final CompanionGrid grid;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (grid.caption != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              grid.caption!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final cols = grid.columns, rows = grid.rows;
              final a = grid.aspect;
              final byHeight = (c.maxHeight - grid.gap * (rows - 1)) / rows / a;
              final side = ((c.maxWidth - grid.gap * (cols - 1)) / cols)
                  .clamp(0.0, byHeight)
                  .clamp(0.0, 120.0);
              final tall = side * a;
              Widget field(int i, CompanionCell cell) {
                final bg = cell.color != null
                    ? Color(cell.color!)
                    : cell.action != null
                    ? scheme.secondaryContainer
                    : scheme.surfaceContainerHighest;
                final fg =
                    ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
                    ? Colors.white
                    : Colors.black;
                final box = Container(
                  width: side,
                  height: tall,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(
                      grid.gap == 0 ? 0 : side * 0.18,
                    ),
                    border: cell.marked
                        ? Border.all(color: scheme.primary, width: 3)
                        : grid.gap == 0
                        ? Border.all(color: Colors.black26, width: 0.5)
                        : null,
                  ),
                  child: cell.label.isEmpty && cell.sub == null
                      ? null
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (cell.label.isNotEmpty)
                                  Text(
                                    cell.label,
                                    style: TextStyle(
                                      color: fg,
                                      fontSize: max(8, side * 0.42),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                if (cell.sub != null)
                                  Text(
                                    cell.sub!,
                                    style: TextStyle(
                                      color: fg.withValues(alpha: 0.7),
                                      fontSize: max(6, side * 0.16),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                );
                final a = cell.action;
                if (a == null) return box;
                return GestureDetector(
                  key: ValueKey('companion-grid-$i'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onAction(a),
                  child: box,
                );
              }

              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var r = 0; r < rows; r++)
                      Padding(
                        padding: EdgeInsets.only(top: r == 0 ? 0 : grid.gap),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var k = 0; k < cols; k++)
                              Padding(
                                padding: EdgeInsets.only(
                                  left: k == 0 ? 0 : grid.gap,
                                ),
                                child: r * cols + k < grid.cells.length
                                    ? field(
                                        r * cols + k,
                                        grid.cells[r * cols + k],
                                      )
                                    : SizedBox(width: side, height: tall),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The chat of an online game: the latest lines and quick replies.
class _ChatStrip extends StatelessWidget {
  const _ChatStrip({required this.page, required this.onAction});
  final CompanionPage page;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('companionChat'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final l in page.chat)
            Text(
              '💬 $l',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          if (page.replies.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final r in page.replies)
                    Padding(
                      padding: const EdgeInsets.only(right: 4, top: 4),
                      child: ActionChip(
                        key: ValueKey('companion-say-$r'),
                        visualDensity: VisualDensity.compact,
                        label: Text(r),
                        onPressed: () => onAction('say:$r'),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
