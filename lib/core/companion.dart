import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The second screen of dual-screen handhelds such as the AYN Thor.
///
/// Android draws one window per Flutter engine, so the lower screen runs a
/// second, small engine (see `companionMain`) that only shows [CompanionPage]s.
/// The game on the main screen describes what belongs below; taps there come
/// back as action strings. Like a Nintendo DS: dice on top, score sheet below.

/// One row of a [CompanionTable].
class CompanionRow {
  const CompanionRow(this.cells, {this.bold = false, this.actions = const {}});

  final List<String> cells;
  final bool bold;

  /// Column index → action sent when that cell is tapped.
  final Map<int, String> actions;

  Map<String, dynamic> toJson() => {
    'c': cells,
    if (bold) 'b': true,
    if (actions.isNotEmpty)
      'a': {for (final e in actions.entries) '${e.key}': e.value},
  };

  factory CompanionRow.fromJson(Map<String, dynamic> j) => CompanionRow(
    [for (final c in j['c'] as List) '$c'],
    bold: j['b'] == true,
    actions: {
      for (final e in (j['a'] as Map? ?? const {}).entries)
        int.parse('${e.key}'): '${e.value}',
    },
  );
}

/// A score sheet: a header row and rows of text; cells may be tappable.
class CompanionTable {
  const CompanionTable({
    required this.columns,
    required this.rows,
    this.highlight,
  });

  final List<String> columns;
  final List<CompanionRow> rows;

  /// Column of the player whose turn it is.
  final int? highlight;

  Map<String, dynamic> toJson() => {
    'h': columns,
    'r': [for (final r in rows) r.toJson()],
    'x': ?highlight,
  };

  factory CompanionTable.fromJson(Map<String, dynamic> j) => CompanionTable(
    columns: [for (final c in j['h'] as List) '$c'],
    rows: [
      for (final r in j['r'] as List)
        CompanionRow.fromJson((r as Map).cast<String, dynamic>()),
    ],
    highlight: j['x'] as int?,
  );
}

/// One field of a [CompanionGrid].
class CompanionCell {
  const CompanionCell({
    this.label = '',
    this.sub,
    this.color,
    this.action,
    this.marked = false,
  });

  final String label;

  /// Small text below the label (e.g. how many are left).
  final String? sub;
  final int? color;
  final String? action;

  /// Framed, e.g. the chosen one.
  final bool marked;

  Map<String, dynamic> toJson() => {
    if (label.isNotEmpty) 'l': label,
    'u': ?sub,
    'c': ?color,
    'a': ?action,
    if (marked) 'm': true,
  };

  factory CompanionCell.fromJson(Map<String, dynamic> j) => CompanionCell(
    label: j['l'] as String? ?? '',
    sub: j['u'] as String?,
    color: j['c'] as int?,
    action: j['a'] as String?,
    marked: j['m'] == true,
  );
}

/// Square fields in rows: a number pad, the own fleet …
class CompanionGrid {
  const CompanionGrid({
    required this.columns,
    required this.cells,
    this.gap = 6,
    this.caption,
  });

  final int columns;
  final List<CompanionCell> cells;

  /// Space between the fields (0: a board without gaps).
  final double gap;
  final String? caption;

  int get rows => (cells.length + columns - 1) ~/ columns;

  Map<String, dynamic> toJson() => {
    'n': columns,
    'f': [for (final c in cells) c.toJson()],
    'g': gap,
    'cp': ?caption,
  };

  factory CompanionGrid.fromJson(Map<String, dynamic> j) => CompanionGrid(
    columns: j['n'] as int,
    cells: [
      for (final c in j['f'] as List)
        CompanionCell.fromJson((c as Map).cast<String, dynamic>()),
    ],
    gap: (j['g'] as num? ?? 6).toDouble(),
    caption: j['cp'] as String?,
  );
}

/// A button on the lower screen.
class CompanionButton {
  const CompanionButton(this.action, this.label, {this.color});
  final String action;
  final String label;
  final int? color;

  Map<String, dynamic> toJson() => {'a': action, 'l': label, 'c': ?color};

  factory CompanionButton.fromJson(Map<String, dynamic> j) =>
      CompanionButton('${j['a']}', '${j['l']}', color: j['c'] as int?);
}

/// What the lower screen shows.
class CompanionPage {
  const CompanionPage({
    this.title,
    this.status,
    this.statusColor,
    this.table,
    this.grid,
    this.buttonsTitle,
    this.buttons = const [],
    this.hint,
  });

  /// Shown instead of (or above) the table.
  final CompanionGrid? grid;

  final String? title;
  final String? status;
  final int? statusColor;
  final CompanionTable? table;
  final String? buttonsTitle;
  final List<CompanionButton> buttons;
  final String? hint;

  CompanionPage copyWith({String? title, String? status, int? statusColor}) =>
      CompanionPage(
        title: title ?? this.title,
        status: status ?? this.status,
        statusColor: statusColor ?? this.statusColor,
        table: table,
        grid: grid,
        buttonsTitle: buttonsTitle,
        buttons: buttons,
        hint: hint,
      );

  Map<String, dynamic> toJson() => {
    't': ?title,
    's': ?status,
    'sc': ?statusColor,
    'tb': ?table?.toJson(),
    'gr': ?grid?.toJson(),
    'bt': ?buttonsTitle,
    if (buttons.isNotEmpty) 'b': [for (final b in buttons) b.toJson()],
    'hi': ?hint,
  };

  factory CompanionPage.fromJson(Map<String, dynamic> j) => CompanionPage(
    title: j['t'] as String?,
    status: j['s'] as String?,
    statusColor: j['sc'] as int?,
    table: j['tb'] == null
        ? null
        : CompanionTable.fromJson((j['tb'] as Map).cast<String, dynamic>()),
    grid: j['gr'] == null
        ? null
        : CompanionGrid.fromJson((j['gr'] as Map).cast<String, dynamic>()),
    buttonsTitle: j['bt'] as String?,
    buttons: [
      for (final b in j['b'] as List? ?? const [])
        CompanionButton.fromJson((b as Map).cast<String, dynamic>()),
    ],
    hint: j['hi'] as String?,
  );
}

class _Slot {
  _Slot(this.page, this.onAction);
  CompanionPage page;
  void Function(String action)? onAction;
  String? status;
  int? statusColor;
}

/// The main app's side of the second screen.
class Companion {
  Companion._();
  static final Companion I = Companion._();

  static const _channel = MethodChannel('mobilegames/companion');
  static const _prefKey = 'companion.enabled';

  /// Whether a second screen shows the companion right now.
  final ValueNotifier<bool> active = ValueNotifier(false);

  /// Whether the device has a second screen (shown or not).
  final ValueNotifier<bool> hasScreen = ValueNotifier(false);

  void _update() => active.value = hasScreen.value && enabled.value;

  /// The player may turn the second screen off.
  final ValueNotifier<bool> enabled = ValueNotifier(true);

  final List<_Slot> _slots = [];
  String? _sent;
  bool _scheduled = false;
  bool _started = false;

  /// Sends pages to the platform (replaced in tests).
  @visibleForTesting
  Future<void> Function(String json)? sendOverride;

  /// The last page sent, for tests.
  @visibleForTesting
  CompanionPage? get lastPage => _sent == null
      ? null
      : CompanionPage.fromJson(jsonDecode(_sent!) as Map<String, dynamic>);

  bool get _platform => !kIsWeb && Platform.isAndroid;

  Future<void> init() async {
    if (_started) return;
    _started = true;
    try {
      final p = await SharedPreferences.getInstance();
      enabled.value = p.getBool(_prefKey) ?? true;
    } catch (_) {}
    if (!_platform) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'available':
          hasScreen.value = call.arguments == true;
          _update();
        case 'action':
          action('${call.arguments}');
      }
      return null;
    });
    try {
      await _channel.invokeMethod<void>('setEnabled', enabled.value);
      hasScreen.value =
          await _channel.invokeMethod<bool>('available') ?? hasScreen.value;
      _update();
    } catch (_) {}
  }

  Future<void> setEnabled(bool on) async {
    enabled.value = on;
    _update();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_prefKey, on);
    } catch (_) {}
    if (_platform) {
      try {
        await _channel.invokeMethod<void>('setEnabled', on);
      } catch (_) {}
    }
  }

  /// A tap on the lower screen.
  void action(String a) {
    if (_slots.isEmpty) return;
    _slots.last.onAction?.call(a);
  }

  _Slot _push(CompanionPage page, void Function(String)? onAction) {
    final s = _Slot(page, onAction);
    _slots.add(s);
    _schedule();
    return s;
  }

  void _remove(_Slot s) {
    _slots.remove(s);
    _schedule();
  }

  void _changed() => _schedule();

  /// The turn banner of the game on top: shown below as well.
  void reportStatus(String text, int? color) {
    if (_slots.isEmpty) return;
    final s = _slots.last;
    if (s.status == text && s.statusColor == color) return;
    s
      ..status = text
      ..statusColor = color;
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      _publish();
    });
  }

  void _publish() {
    final top = _slots.isEmpty ? null : _slots.last;
    final page = top == null
        ? const CompanionPage()
        : top.page.status != null
        ? top.page
        : top.page.copyWith(status: top.status, statusColor: top.statusColor);
    final json = jsonEncode(page.toJson());
    if (json == _sent) return;
    _sent = json;
    final send = sendOverride;
    if (send != null) {
      send(json);
    } else if (_platform) {
      _channel.invokeMethod<void>('publish', json).catchError((_) {});
    }
  }

  @visibleForTesting
  void reset() {
    _slots.clear();
    _sent = null;
    hasScreen.value = false;
    enabled.value = true;
    active.value = false;
  }
}

/// Puts [page] on the lower screen while this widget is shown (the newest
/// one wins, so a game covers the home screen and leaving it brings the
/// home page back). Taps below call [onAction].
class CompanionSlot extends StatefulWidget {
  const CompanionSlot({
    super.key,
    required this.page,
    this.onAction,
    required this.child,
  });

  final CompanionPage page;
  final void Function(String action)? onAction;
  final Widget child;

  @override
  State<CompanionSlot> createState() => _CompanionSlotState();
}

class _CompanionSlotState extends State<CompanionSlot> {
  late final _Slot _slot;

  @override
  void initState() {
    super.initState();
    _slot = Companion.I._push(widget.page, widget.onAction);
  }

  @override
  void didUpdateWidget(CompanionSlot old) {
    super.didUpdateWidget(old);
    _slot
      ..page = widget.page
      ..onAction = widget.onAction;
    Companion.I._changed();
  }

  @override
  void dispose() {
    Companion.I._remove(_slot);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Rebuilds when the second screen comes or goes.
class CompanionBuilder extends StatelessWidget {
  const CompanionBuilder({super.key, required this.builder});
  final Widget Function(BuildContext context, bool active) builder;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: Companion.I.active,
    builder: (context, a, _) => builder(context, a),
  );
}
