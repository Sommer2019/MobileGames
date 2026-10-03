import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/shake.dart';
import '../../core/sound.dart';
import '../../ui/dice.dart';
import '../../ui/widgets_sheet.dart';

/// Dice for board games: 1–6 dice, roll by tapping or shaking the phone.
class DiceCupScreen extends StatefulWidget {
  const DiceCupScreen({super.key, this.random});
  final Random? random;

  @override
  State<DiceCupScreen> createState() => _DiceCupScreenState();
}

class _DiceCupScreenState extends State<DiceCupScreen> {
  static const _countKey = 'dice.count';
  late final Random _random = widget.random ?? Random();
  int count = 2;
  List<int> values = List.filled(6, 1);
  List<int> rolls = List.filled(6, 0);
  bool rolled = false;
  StreamSubscription<Object?>? _shake;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => count = p.getInt(_countKey) ?? 2);
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

  void _roll() {
    HapticFeedback.mediumImpact();
    Sound.play(Sfx.dice);
    setState(() {
      rolled = true;
      for (var i = 0; i < count; i++) {
        values[i] = 1 + _random.nextInt(6);
        rolls[i]++;
      }
    });
  }

  Future<void> _setCount(int n) async {
    setState(() => count = n);
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
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        for (var i = 0; i < count; i++)
                          SizedBox.square(
                            dimension: count <= 2 ? 140 : 110,
                            child: RollingDie(
                              value: values[i],
                              rollId: rolls[i],
                              visible: rolled,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                rolled
                    ? (count > 1 ? 'Summe: $sum' : 'Gewürfelt: $sum')
                    : 'Antippen oder Handy schütteln 📳',
                key: const ValueKey('diceSum'),
                style: const TextStyle(color: Colors.white, fontSize: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
