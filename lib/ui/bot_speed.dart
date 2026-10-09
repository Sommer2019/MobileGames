import 'package:flutter/material.dart';

/// Fast-forward for the computer players: their pauses and animations run
/// much quicker while the button is on. Every game starts at normal speed.
class BotSpeed {
  BotSpeed._();

  static final ValueNotifier<bool> fast = ValueNotifier(false);

  /// How much faster the computer plays with fast-forward on.
  static const factor = 6.0;

  /// [d] shortened while fast-forward is on.
  static Duration of(Duration d) => fast.value ? d * (1 / factor) : d;

  /// [ms] milliseconds, shortened while fast-forward is on.
  static Duration ms(int ms) => of(Duration(milliseconds: ms));
}

/// App-bar button ⏩ that switches fast-forward on and off.
class FastForwardButton extends StatefulWidget {
  const FastForwardButton({super.key});

  @override
  State<FastForwardButton> createState() => _FastForwardButtonState();
}

class _FastForwardButtonState extends State<FastForwardButton> {
  @override
  void initState() {
    super.initState();
    // A new game starts at normal speed.
    BotSpeed.fast.value = false;
  }

  @override
  void dispose() {
    BotSpeed.fast.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: BotSpeed.fast,
    builder: (context, fast, _) => IconButton(
      key: const ValueKey('fastForward'),
      tooltip: fast ? 'Computer normal schnell' : 'Computer vorspulen',
      isSelected: fast,
      onPressed: () => BotSpeed.fast.value = !fast,
      icon: const Icon(Icons.fast_forward_outlined),
      selectedIcon: const Icon(Icons.fast_forward),
      color: fast ? Colors.amber.shade700 : null,
    ),
  );
}
