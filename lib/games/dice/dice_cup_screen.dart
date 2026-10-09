import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/shake.dart';
import '../../core/mirror.dart';
import '../../core/sound.dart';
import '../../ui/dice.dart';
import '../../ui/widgets_sheet.dart';

/// Dice for board games: 1–6 dice, roll by tapping or shaking the phone.
/// Tapping a die puts it aside (it keeps its value); the last ten rolls are
/// listed with their sums.
class DiceCupScreen extends StatefulWidget {
  const DiceCupScreen({super.key, this.random});
  final Random? random;

  @override
  State<DiceCupScreen> createState() => _DiceCupScreenState();
}

class _DiceCupScreenState extends State<DiceCupScreen> with GameMirror {
  @override
  String? get mirrorGame => 'dice';

  @override
  Map<String, dynamic>? mirrorState() => {
    'count': count,
    'values': values,
    'held': held,
    'rolled': rolled,
    'history': history,
  };

  @override
  void applyMirror(Map<String, dynamic> state) {
    final v = [for (final x in state['values'] as List) x as int];
    if (rolled && v.join() != values.join()) Sound.play(Sfx.dice);
    count = state['count'] as int;
    values = v;
    held = [for (final x in state['held'] as List) x as bool];
    rolled = state['rolled'] as bool;
    history = [
      for (final r in state['history'] as List)
        [for (final x in r as List) x as int],
    ];
  }

  static const _countKey = 'dice.count';
  static const _historyKey = 'dice.history';
  static const historyLength = 10;
  late final Random _random = widget.random ?? Random();
  int count = 2;
  List<int> values = List.filled(6, 1);
  List<int> rolls = List.filled(6, 0);
  bool rolled = false;

  /// Dice put aside: they are not rolled again.
  List<bool> held = List.filled(6, false);

  /// Last rolls, newest first (values of all dice).
  List<List<int>> history = [];
  StreamSubscription<Object?>? _shake;

  @override
  void initState() {
    super.initState();
    if (mirroring) return;
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        count = p.getInt(_countKey) ?? 2;
        try {
          history = [
            for (final r
                in jsonDecode(p.getString(_historyKey) ?? '[]') as List)
              (r as List).cast<int>(),
          ];
        } catch (_) {}
      });
    });
    _shake = ShakeDetector.listen(() {
      if (mounted) _roll();
    });
  }

  @override
  void dispose() {
    _shake?.cancel();
    super.dispose();
  }

  bool get _allHeld => rolled && !held.take(count).contains(false);

  void _roll() {
    if (_allHeld) return;
    HapticFeedback.mediumImpact();
    Sound.play(Sfx.dice);
    setState(() {
      for (var i = 0; i < count; i++) {
        if (rolled && held[i]) continue;
        values[i] = 1 + _random.nextInt(6);
        rolls[i]++;
      }
      rolled = true;
      history = [
        values.take(count).toList(),
        ...history,
      ].take(historyLength).toList();
    });
    _saveHistory();
  }

  Future<void> _saveHistory() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_historyKey, jsonEncode(history));
  }

  void _toggleHold(int i) {
    if (!rolled) return _roll();
    HapticFeedback.selectionClick();
    setState(() => held[i] = !held[i]);
  }

  void _releaseAll() => setState(() => held = List.filled(6, false));

  void _clearHistory() {
    setState(() => history = []);
    _saveHistory();
  }

  Future<void> _setCount(int n) async {
    setState(() {
      count = n;
      held = List.filled(6, false);
    });
    final p = await SharedPreferences.getInstance();
    await p.setInt(_countKey, n);
  }

  @override
  Widget build(BuildContext context) {
    final sum = values.take(count).fold(0, (a, b) => a + b);
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: const Text('Würfelbecher'),
        actions: [
          if (!kIsWeb)
            IconButton(
              tooltip: 'Als Widget auf den Startbildschirm',
              icon: const Icon(Icons.widgets_outlined),
              onPressed: () => showWidgetsSheet(context),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<int>(
                key: const ValueKey('diceCount'),
                segments: [
                  for (var n = 1; n <= 6; n++)
                    ButtonSegment(value: n, label: Text('$n')),
                ],
                selected: {count},
                showSelectedIcon: false,
                onSelectionChanged: (s) => _setCount(s.first),
              ),
            ),
            Expanded(
              child: GestureDetector(
                key: const ValueKey('diceArea'),
                behavior: HitTestBehavior.opaque,
                onTap: _roll,
                child: Column(
                  children: [
                    if (held.take(count).contains(true)) _aside(),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            children: [
                              for (var i = 0; i < count; i++)
                                if (!held[i])
                                  SizedBox.square(
                                    dimension: count <= 2 ? 140 : 110,
                                    child: _die(i),
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                !rolled
                    ? 'Antippen oder Handy schütteln 📳'
                    : _allHeld
                    ? 'Alle Würfel liegen beiseite'
                    : (count > 1 ? 'Summe: $sum' : 'Gewürfelt: $sum'),
                key: const ValueKey('diceSum'),
                style: const TextStyle(color: Colors.white, fontSize: 22),
              ),
            ),
            if (rolled && !held.take(count).contains(true) && count > 1)
              const Text(
                'Würfel antippen, um ihn beiseitezulegen',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            _history(),
          ],
        ),
      ),
    );
  }

  Widget _die(int i) => GestureDetector(
    key: ValueKey('die$i'),
    onTap: () => _toggleHold(i),
    child: RollingDie(
      value: values[i],
      rollId: rolls[i],
      held: held[i],
      visible: rolled,
    ),
  );

  /// Dice put aside, shown small at the top.
  Widget _aside() => Container(
    key: const ValueKey('diceAside'),
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
    padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
    decoration: BoxDecoration(
      color: Colors.black26,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Text('Beiseite', style: TextStyle(color: Colors.white70)),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < count; i++)
                if (held[i]) SizedBox.square(dimension: 64, child: _die(i)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Alle zurücklegen',
          onPressed: _releaseAll,
          icon: const Icon(Icons.undo, color: Colors.white70),
        ),
      ],
    ),
  );

  /// The last rolls with their sums, newest first.
  Widget _history() {
    if (history.isEmpty) return const SizedBox(height: 12);
    return Container(
      key: const ValueKey('diceHistory'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Letzte ${history.length} Würfe',
                style: const TextStyle(color: Colors.white70),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Verlauf löschen',
                visualDensity: VisualDensity.compact,
                onPressed: _clearHistory,
                icon: const Icon(Icons.delete_outline, color: Colors.white54),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < history.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: i == 0 ? Colors.amber.shade200 : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    history[i].length == 1
                        ? '${history[i].single}'
                        : '${history[i].join('+')} = '
                              '${history[i].fold(0, (a, b) => a + b)}',
                    style: TextStyle(
                      fontWeight: i == 0 ? FontWeight.bold : null,
                      color: Colors.black87,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
