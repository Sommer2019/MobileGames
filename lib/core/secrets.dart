import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The things the Konami code unlocks (↑↑↓↓←→←→, volume up, volume down,
/// plug in the charger). Every extra can be switched on its own; none of
/// them makes a game easier where it counts for the leaderboard.
enum Secret {
  retro(
    'Retro-Modus',
    '8-Bit-Sounds, Snake im Retro-Handy-Look, Pixel-Billard',
  ),
  disco('Disco-Kugeln', 'Billardkugeln wechseln beim Rollen die Farbe'),
  rubberBall('Gummiball', 'Die Labyrinth-Kugel springt von den Wänden ab'),
  nightmare(
    'Albtraum-Labyrinth',
    'Steuerung spiegelverkehrt, die Kugel hat mehr Schwung',
  ),
  grandmaster('Großmeister', 'Schach und Dame: der Computer spielt stärker'),
  luckyComputer(
    'Glückspilz-Computer',
    'Würfelkönig: der Computer würfelt einmal pro Spiel verdächtig gut',
  ),
  labyrinthEasy('Easy Mode Labyrinth', 'Alle Labyrinth-Level freigeschaltet'),
  boxesPro('Käsekästchen-Profi', 'Der Computer spielt das Ende perfekt'),
  ludoRage('Ärger-Effekt', 'Ludo: Rauswerfen lässt das Brett wackeln'),
  halmaRainbow(
    'Regenbogen-Murmeln',
    'Sternhalma: schillernde Murmeln und Regenbogen-Sprungspur',
  ),
  dominoEffect(
    'Domino-Effekt',
    'Domino: am Rundenende fallen alle Steine nacheinander um',
  ),
  bingoTurbo('Bingo-Turbo', 'Bingo: die Kugeln fallen doppelt so schnell'),
  lastCardStack(
    'Stapel-Wahnsinn',
    'Letzte Karte: +2 und +4 lassen sich stapeln (gilt für deine Runden)',
  ),
  jokerRain(
    'Joker-Regen',
    'Stapelfix: doppelt so viele Joker im Spiel (gilt für deine Runden)',
  ),
  arrowsXray('Röntgenblick', 'Pfeile: freie Pfeile schimmern leicht grün'),
  botArena(
    'Bot-Arena',
    'Bei „Spieler & Computer wählen“ dürfen alle Plätze Computer sein – '
        'zurücklehnen und zuschauen',
  );

  const Secret(this.title, this.description);
  final String title;
  final String description;
}

class Secrets extends ChangeNotifier {
  Secrets._();
  static final Secrets I = Secrets._();

  static const _unlockedKey = 'secret.konami';
  static const _arenaKey = 'secret.arenaCode';
  static String _key(Secret s) =>
      s == Secret.labyrinthEasy ? 'labyrinth.cheat' : 'secret.${s.name}';

  bool _unlocked = false;
  final Set<Secret> _on = {};

  /// Whether the code was ever entered (shows the 🎮 badge).
  bool get unlocked => _unlocked;

  bool _arena = false;

  /// Whether the second code (backwards) was entered.
  bool get arenaUnlocked => _arena;

  /// Whether [s] can be switched on: the Bot-Arena has its own code.
  bool available(Secret s) => s == Secret.botArena ? _arena : _unlocked;

  /// Whether [s] is switched on (only possible once unlocked).
  bool isOn(Secret s) => available(s) && _on.contains(s);

  static bool on(Secret s) => I.isOn(s);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _unlocked = prefs.getBool(_unlockedKey) ?? false;
    _arena = prefs.getBool(_arenaKey) ?? false;
    _on
      ..clear()
      ..addAll([
        for (final s in Secret.values)
          if (prefs.getBool(_key(s)) ?? false) s,
      ]);
    // Older versions only had the labyrinth switch.
    if (_on.contains(Secret.labyrinthEasy)) _unlocked = true;
    notifyListeners();
  }

  /// The code was entered. Returns true the first time.
  Future<bool> unlock() async {
    final first = !_unlocked;
    _unlocked = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_unlockedKey, true);
    if (first) await set(Secret.retro, true);
    notifyListeners();
    return first;
  }

  /// The code backwards was entered: unlocks and switches on the
  /// Bot-Arena. Returns true the first time.
  Future<bool> unlockArena() async {
    final first = !_arena;
    _arena = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_arenaKey, true);
    await set(Secret.botArena, true);
    return first;
  }

  Future<void> set(Secret s, bool value) async {
    if (value) {
      _on.add(s);
    } else {
      _on.remove(s);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(s), value);
  }

  @visibleForTesting
  void reset() {
    _unlocked = false;
    _arena = false;
    _on.clear();
  }
}
