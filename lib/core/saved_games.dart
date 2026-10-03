import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Games in progress, kept when leaving a game so it can be continued.
///
/// Read synchronously (the preferences are loaded at startup), so a screen
/// can restore its round in initState without showing a fresh one first.
class SavedGames {
  SavedGames._();

  static const _prefix = 'save.';
  static SharedPreferences? _prefs;

  static Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Forget the loaded preferences (tests).
  static void reset() => _prefs = null;

  static Map<String, dynamic>? read(String key) {
    final raw = _prefs?.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Stores [data] for [key]; null deletes the saved game.
  static void write(String key, Map<String, dynamic>? data) {
    unawaited(_write(key, data));
  }

  static Future<void> _write(String key, Map<String, dynamic>? data) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    if (data == null) {
      await prefs.remove('$_prefix$key');
    } else {
      await prefs.setString('$_prefix$key', jsonEncode(data));
    }
  }

  static bool has(String key) => _prefs?.containsKey('$_prefix$key') ?? false;
}

/// Saves the running round when the screen is left (or the app goes to the
/// background) and restores it when the game is opened again.
mixin SavedGameState<T extends StatefulWidget> on State<T> {
  /// Where the round is stored; null = not saved (e.g. online games).
  String? get saveKey;

  /// The round to keep, or null when there is nothing worth keeping
  /// (not started yet, or over).
  Map<String, dynamic>? saveGame();

  /// Continues a saved round. Throwing discards the save.
  void restoreGame(Map<String, dynamic> data);

  AppLifecycleListener? _lifecycle;

  /// True if a saved round was restored in initState.
  bool restoredGame = false;

  @override
  void initState() {
    super.initState();
    final key = saveKey;
    if (key == null) return;
    _lifecycle = AppLifecycleListener(onHide: persistGame);
    final data = SavedGames.read(key);
    if (data == null) return;
    try {
      restoreGame(data);
      restoredGame = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Spielstand fortgesetzt'),
              duration: Duration(seconds: 2),
            ),
          );
      });
    } catch (_) {
      SavedGames.write(key, null);
    }
  }

  /// Writes the current round now.
  void persistGame() {
    final key = saveKey;
    if (key == null) return;
    Map<String, dynamic>? data;
    try {
      data = saveGame();
    } catch (_) {
      data = null;
    }
    SavedGames.write(key, data);
  }

  @override
  void dispose() {
    persistGame();
    _lifecycle?.dispose();
    super.dispose();
  }
}

/// App-bar button: starts the round over after asking.
class RestartButton extends StatelessWidget {
  const RestartButton({super.key, required this.onRestart, this.color});
  final VoidCallback? onRestart;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('restart'),
    tooltip: 'Neu starten',
    visualDensity: color == null ? null : VisualDensity.compact,
    icon: Icon(Icons.restart_alt, color: color),
    onPressed: onRestart == null
        ? null
        : () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Neu starten?'),
                content: const Text('Der aktuelle Spielstand geht verloren.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Abbrechen'),
                  ),
                  FilledButton(
                    key: const ValueKey('restartConfirm'),
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Neu starten'),
                  ),
                ],
              ),
            );
            if (ok == true) onRestart!();
          },
  );
}
