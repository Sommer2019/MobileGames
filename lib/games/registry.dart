import 'package:flutter/material.dart';

import '../ui/play_setup.dart';
import 'battleship/battleship_local_screen.dart';
import 'battleship/battleship_screen.dart';
import 'billiard/billiard_screen.dart';
import 'billiard/eight_ball_screen.dart';
import 'checkers/checkers_screen.dart';
import 'darts/darts_screen.dart';
import 'chess/chess_screen.dart';
import 'connect_four/connect_four_screen.dart';
import 'labyrinth/labyrinth_screen.dart';
import 'mahjong/mahjong_screen.dart';
import 'mill/mill_screen.dart';
import 'snake/snake_screen.dart';
import 'tournament/tournament_screen.dart';
import 'yahtzee/yahtzee_screen.dart';

/// An offline way to play a multiplayer game.
class OfflineMode {
  const OfflineMode(this.label, this.icon, this.setup);
  final String label;
  final IconData icon;
  final PlaySetup setup;
}

class GameInfo {
  const GameInfo({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    this.offlineModes = const [],
    this.multiplayerBuilder,
    this.singleplayerBuilder,
    this.maxOnlinePlayers = 2,
    this.alsoSingleplayer = false,
  });

  /// Multiplayer game that can also be played alone (listed in both sections).
  final bool alsoSingleplayer;

  /// Online games support 2..[maxOnlinePlayers] players.
  final int maxOnlinePlayers;

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final List<OfflineMode> offlineModes;
  final Widget Function(PlaySetup setup)? multiplayerBuilder;
  final Widget Function()? singleplayerBuilder;

  bool get isMultiplayer => multiplayerBuilder != null;
}

final List<GameInfo> games = [
  GameInfo(
    id: 'chess',
    title: 'Schach',
    description: 'Der Klassiker mit allen Regeln',
    icon: Icons.castle,
    color: const Color(0xFF6D4C41),
    offlineModes: const [
      OfflineMode('Gegen Computer', Icons.smart_toy, PlaySetup.ai()),
      OfflineMode('2 Spieler, 1 Gerät', Icons.people, PlaySetup.local()),
    ],
    multiplayerBuilder: (s) => ChessScreen(setup: s),
  ),
  GameInfo(
    id: 'battleship',
    title: 'Schiffe versenken',
    description: 'Finde und versenke die gegnerische Flotte',
    icon: Icons.directions_boat,
    color: const Color(0xFF1565C0),
    offlineModes: const [
      OfflineMode('Gegen Computer', Icons.smart_toy, PlaySetup.ai()),
      OfflineMode('2 Spieler, 1 Gerät', Icons.people, PlaySetup.local()),
    ],
    multiplayerBuilder: (s) => s.kind == PlayKind.local
        ? const BattleshipLocalScreen()
        : BattleshipScreen(setup: s),
  ),
  GameInfo(
    id: 'connect_four',
    title: '4 gewinnt',
    description: 'Vier in einer Reihe gewinnt – 2 bis 4 Spieler',
    icon: Icons.grid_view_rounded,
    color: const Color(0xFFD32F2F),
    offlineModes: const [
      OfflineMode('Gegen Computer', Icons.smart_toy, PlaySetup.ai()),
      OfflineMode('2 Spieler, 1 Gerät', Icons.people, PlaySetup.local()),
      OfflineMode(
        '3 Spieler, 1 Gerät',
        Icons.groups,
        PlaySetup.local(players: 3),
      ),
      OfflineMode(
        '4 Spieler, 1 Gerät',
        Icons.groups,
        PlaySetup.local(players: 4),
      ),
    ],
    maxOnlinePlayers: 4,
    multiplayerBuilder: (s) => ConnectFourScreen(setup: s),
  ),
  GameInfo(
    id: 'checkers',
    title: 'Dame',
    description: 'Schlagen ist Pflicht – mit fliegenden Damen',
    icon: Icons.blur_on,
    color: const Color(0xFF5D4037),
    offlineModes: const [
      OfflineMode('Gegen Computer', Icons.smart_toy, PlaySetup.ai()),
      OfflineMode('2 Spieler, 1 Gerät', Icons.people, PlaySetup.local()),
    ],
    multiplayerBuilder: (s) => CheckersScreen(setup: s),
  ),
  GameInfo(
    id: 'mill',
    title: 'Mühle',
    description: 'Drei in einer Reihe – und dem Gegner einen Stein nehmen',
    icon: Icons.crop_square,
    color: const Color(0xFFEF6C00),
    offlineModes: const [
      OfflineMode('Gegen Computer', Icons.smart_toy, PlaySetup.ai()),
      OfflineMode('2 Spieler, 1 Gerät', Icons.people, PlaySetup.local()),
    ],
    multiplayerBuilder: (s) => MillScreen(setup: s),
  ),
  GameInfo(
    id: 'yahtzee',
    title: 'Kniffel',
    description: 'Würfelglück mit Taktik',
    icon: Icons.casino,
    color: const Color(0xFF2E7D32),
    offlineModes: const [
      OfflineMode('Allein spielen', Icons.person, PlaySetup.local(players: 1)),
      OfflineMode(
        '2 Spieler, 1 Gerät',
        Icons.people,
        PlaySetup.local(players: 2),
      ),
      OfflineMode(
        '3 Spieler, 1 Gerät',
        Icons.groups,
        PlaySetup.local(players: 3),
      ),
      OfflineMode(
        '4 Spieler, 1 Gerät',
        Icons.groups,
        PlaySetup.local(players: 4),
      ),
    ],
    maxOnlinePlayers: 4,
    multiplayerBuilder: (s) => YahtzeeScreen(setup: s),
  ),
  GameInfo(
    id: 'darts',
    title: 'Darts',
    description: '501, 301 oder Rund um die Uhr – allein oder bis zu 4 Spieler',
    icon: Icons.adjust,
    color: const Color(0xFFC62828),
    offlineModes: const [
      OfflineMode('Allein üben', Icons.person, PlaySetup.local(players: 1)),
      OfflineMode('2 Spieler, 1 Gerät', Icons.people, PlaySetup.local()),
      OfflineMode(
        '3 Spieler, 1 Gerät',
        Icons.groups,
        PlaySetup.local(players: 3),
      ),
      OfflineMode(
        '4 Spieler, 1 Gerät',
        Icons.groups,
        PlaySetup.local(players: 4),
      ),
    ],
    multiplayerBuilder: (s) => DartsScreen(setup: s),
    maxOnlinePlayers: 4,
    alsoSingleplayer: true,
  ),
  GameInfo(
    id: 'labyrinth',
    title: 'Kugellabyrinth',
    description: 'Kippe das Handy und rolle die Kugel ins Ziel',
    icon: Icons.blur_circular,
    color: const Color(0xFF8D6E63),
    singleplayerBuilder: () => const LabyrinthLevelsScreen(),
  ),
  GameInfo(
    id: 'snake',
    title: 'Snake',
    description: 'Fressen, wachsen, nicht in den Schwanz beißen',
    icon: Icons.gesture,
    color: const Color(0xFF558B2F),
    singleplayerBuilder: () => const SnakeScreen(),
  ),
  GameInfo(
    id: 'mahjong',
    title: 'Mahjong',
    description: 'Räume alle Steinpaare ab',
    icon: Icons.view_module,
    color: const Color(0xFF00897B),
    singleplayerBuilder: () => const MahjongScreen(),
  ),
  GameInfo(
    id: 'billiard',
    title: 'Billard',
    description: 'Allein alle Kugeln versenken oder 8-Ball zu zweit',
    icon: Icons.sports_baseball,
    color: const Color(0xFF1B5E20),
    offlineModes: const [
      OfflineMode(
        'Allein: Tisch abräumen',
        Icons.person,
        PlaySetup.local(players: 1),
      ),
      OfflineMode(
        '8-Ball: 2 Spieler, 1 Gerät',
        Icons.people,
        PlaySetup.local(),
      ),
    ],
    multiplayerBuilder: (s) =>
        s.players == 1 ? const BilliardScreen() : EightBallScreen(setup: s),
    alsoSingleplayer: true,
  ),
];

GameInfo? gameById(String id) {
  if (id == tournamentId) return tournamentInfo();
  for (final g in games) {
    if (g.id == id) return g;
  }
  return null;
}
