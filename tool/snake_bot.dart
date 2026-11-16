// Plays a checked Snake game by itself and prints the localStorage entry
// (web) that the app then signs and publishes as an ordinary result.
//
//   dart run tool/snake_bot.dart <private key hex> [score]
//
// The bot follows a Hamiltonian cycle (never dies), and once [score] is
// reached it steers into the top wall so the game is over.
import 'dart:convert';

import 'package:mobile_games/core/nostr/keys.dart';
import 'package:mobile_games/core/proof.dart';
import 'package:mobile_games/games/snake/snake_logic.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    print('dart run tool/snake_bot.dart <private key hex> [score]');
    return;
  }
  final pubkey = KeyPair(args[0]).publicKey;
  final target = args.length > 1 ? int.parse(args[1]) : 300;

  final g = SnakeGame(seed: newProofSeed(pubkey));
  final w = g.width, h = g.height;

  // Next direction on the cycle: columns snake through rows 1..h-1, row 0
  // leads back to the left.
  Dir next(int x, int y) {
    if (y == 0) return x > 0 ? Dir.left : Dir.down;
    if (x.isEven) return y < h - 1 ? Dir.down : Dir.right;
    if (y > 1) return Dir.up;
    return x < w - 1 ? Dir.right : Dir.up;
  }

  while (!g.over) {
    final (x, y) = g.body.first;
    var d = next(x, y);
    if (g.score >= target && y == 0) d = Dir.up; // into the wall
    // Only at the start the cycle can point backwards.
    if (d.isOpposite(g.direction)) d = Dir.right;
    if (d != g.direction) g.turn(d);
    g.step();
    if (g.steps > 199000 || g.log!.length > 19900) {
      throw StateError('Zu lang für den Mitschnitt – kleineren Score wählen');
    }
  }

  final proof = SnakeProof.of(g);
  final check = SnakeProof.verify(jsonDecode(jsonEncode(proof)), pubkey);
  if (check != g.score) throw StateError('Nachspielen ergibt $check');

  final entries = [
    {'v': g.score, 't': DateTime.now().millisecondsSinceEpoch, 'p': proof},
  ];
  // shared_preferences on the web stores every value JSON-encoded.
  final value = jsonEncode(jsonEncode(entries));
  print('Score ${g.score}, ${g.steps} Schritte, ${g.log!.length} Züge\n');
  print("localStorage.setItem('flutter.lb.snake', ${jsonEncode(value)});");
}
