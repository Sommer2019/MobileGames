import 'package:flutter/material.dart';

import '../ui/play_setup.dart';
import 'battleship/battleship_screen.dart';
import 'billiard/billiard_screen.dart';
import 'chess/chess_screen.dart';
import 'connect_four/connect_four_screen.dart';
import 'labyrinth/labyrinth_screen.dart';
import 'mahjong/mahjong_screen.dart';
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
  });

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
    ],
    multiplayerBuilder: (s) => BattleshipScreen(setup: s),
  ),
  GameInfo(
    id: 'connect_four',
    title: '4 gewinnt',
    description: 'Vier in einer Reihe gewinnt',
    icon: Icons.grid_view_rounded,
    color: const Color(0xFFD32F2F),
    offlineModes: const [
      OfflineMode('Gegen Computer', Icons.smart_toy, PlaySetup.ai()),
      OfflineMode('2 Spieler, 1 Gerät', Icons.people, PlaySetup.local()),
    ],
    multiplayerBuilder: (s) => ConnectFourScreen(setup: s),
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
    multiplayerBuilder: (s) => YahtzeeScreen(setup: s),
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
    description: 'Versenke alle Kugeln mit möglichst wenigen Stößen',
    icon: Icons.sports_baseball,
    color: const Color(0xFF1B5E20),
    singleplayerBuilder: () => const BilliardScreen(),
  ),
];

GameInfo? gameById(String id) {
  for (final g in games) {
    if (g.id == id) return g;
  }
  return null;
}
