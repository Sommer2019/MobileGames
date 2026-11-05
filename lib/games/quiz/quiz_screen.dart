import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/mirror.dart';
import '../../core/net/room.dart';
import '../../core/sound.dart';
import '../../ui/play_setup.dart';
import 'quiz_logic.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> with GameMirror {
  /// Friends may watch a game on this device (online: through the room).
  @override
  String? get mirrorGame => setup.online ? null : 'quiz';

  @override
  Map<String, dynamic> get mirrorSetup => setup.mirrorInfo;

  @override
  Map<String, dynamic>? mirrorState() => {'events': game.events};

  @override
  void applyMirror(Map<String, dynamic> state) {
    game = QuizGame.replay(players, state['events'] as List);
  }

  PlaySetup get setup => widget.setup;
  int get players => setup.players;
  int get me => setup.mySeat;
  bool get isHost => setup.isHost && !setup.spectator;
  bool get canAct => !setup.spectator;

  late QuizGame game = QuizGame(players: players);
  StreamSubscription<RoomMessage>? _sub;
  Timer? _tick;
  Timer? _next;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _sub = setup.listen((m) {
      final e = m.data['e'];
      if (m.data['t'] != 'e' || e is! List || e.isEmpty) return;
      if (game.apply(List.from(e), m.seat)) _after(e);
    });
    if (isHost) _act(['cfg', _cfg()]);
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    _next?.cancel();
    super.dispose();
  }

  Map<String, dynamic> _cfg({QuizMode? mode, int? count, int? sec}) => {
    'mode': (mode ?? game.mode).name,
    'count': count ?? game.count,
    'sec': sec ?? game.seconds,
  };

  int _now() => DateTime.now().millisecondsSinceEpoch;

  void _act(List e) {
    if (!canAct || !game.apply(e, me)) return;
    setup.send({'t': 'e', 'e': e});
    _after(e);
  }

  void _after(List e) {
    switch (e.first) {
      case 'ans':
        if (isHost && game.allAnswered) _reveal();
      case 'reveal':
        final mine = game.answers[game.q]?[me];
        if (canAct) {
          Sound.play(
            mine != null && mine.$1 == game.question.correct
                ? Sfx.win
                : Sfx.lose,
          );
        }
        // The host moves on by itself after a moment.
        if (isHost) {
          _next?.cancel();
          _next = Timer(const Duration(milliseconds: 2500), _goOn);
        }
    }
    if (mounted) setState(() {});
  }

  void _onTick() {
    if (!mounted || game.phase != QuizPhase.question) return;
    if (isHost && game.timeLeft(_now()) == 0) _reveal();
    setState(() {});
  }

  void _reveal() {
    if (!isHost || game.phase != QuizPhase.question) return;
    _act([
      'reveal',
      game.q,
      {
        for (final MapEntry(:key, :value)
            in (game.answers[game.q] ?? {}).entries)
          '$key': [value.$1, value.$2],
      },
    ]);
  }

  void _goOn() {
    _next?.cancel();
    if (isHost && game.phase == QuizPhase.reveal) _act(['next', _now()]);
  }

  void _answer(int choice) {
    if (!canAct || game.answered(me) || game.phase != QuizPhase.question) {
      return;
    }
    final ms = _now() - game.startedAt;
    _act(['ans', game.q, choice, max(0, ms)]);
    Sound.play(Sfx.click);
  }

  // ------------------------------------------------------------- setup

  Widget _setup() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'Flaggen und Hauptstädte der Welt: vier Antworten, eine ist '
            'richtig. Richtig gibt 100 Punkte, wer schnell ist, bis zu 50 '
            'dazu.',
          ),
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.flag),
                title: Text('Fragen: ${game.mode.label}'),
                subtitle: isHost
                    ? Wrap(
                        spacing: 8,
                        children: [
                          for (final m in QuizMode.values)
                            ChoiceChip(
                              key: ValueKey('quizMode-${m.name}'),
                              label: Text(m.label),
                              selected: game.mode == m,
                              onSelected: (_) => _act(['cfg', _cfg(mode: m)]),
                            ),
                        ],
                      )
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.format_list_numbered),
                title: Text('Anzahl: ${game.count}'),
                subtitle: isHost
                    ? Wrap(
                        spacing: 8,
                        children: [
                          for (final n in QuizGame.counts)
                            ChoiceChip(
                              label: Text('$n'),
                              selected: game.count == n,
                              onSelected: (_) => _act(['cfg', _cfg(count: n)]),
                            ),
                        ],
                      )
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.timer),
                title: Text('Zeit pro Frage: ${game.seconds} s'),
                subtitle: isHost
                    ? Wrap(
                        spacing: 8,
                        children: [
                          for (final s in QuizGame.secondChoices)
                            ChoiceChip(
                              label: Text('$s s'),
                              selected: game.seconds == s,
                              onSelected: (_) => _act(['cfg', _cfg(sec: s)]),
                            ),
                        ],
                      )
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (isHost)
          FilledButton.icon(
            key: const ValueKey('quizStart'),
            onPressed: () => _act(['start', _random.nextInt(1 << 30), _now()]),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Los geht’s'),
          )
        else
          Center(
            child: Text(
              'Warte, bis der Host startet …',
              style: theme.textTheme.bodyLarge,
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------- question

  Widget _questionView() {
    final theme = Theme.of(context);
    final question = game.question;
    final reveal = game.phase == QuizPhase.reveal;
    final mine = game.answers[game.q]?[me];
    final left = game.timeLeft(_now());
    final rightOnes = [
      for (var p = 0; p < players; p++)
        if (game.points(game.q, p) > 0) setup.seatName(p),
    ];
    return Column(
      children: [
        TurnBanner(
          text:
              'Frage ${game.q + 1}/${game.questions.length} · '
              '${game.total(me)} Punkte',
          highlight: !reveal && mine == null,
        ),
        if (!reveal)
          LinearProgressIndicator(value: left / (game.seconds * 1000)),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (question.kind == QuestionKind.flag) ...[
                    FlagImage(code: question.answer, width: 240),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    question.prompt,
                    key: const ValueKey('quizPrompt'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  if (reveal && players > 1) ...[
                    const SizedBox(height: 12),
                    Text(
                      rightOnes.isEmpty
                          ? 'Niemand lag richtig.'
                          : 'Richtig: ${rightOnes.join(', ')}',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            children: [
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: ValueKey('quizChoice$i'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: _choiceColor(i, reveal, mine),
                        disabledBackgroundColor: _choiceColor(i, reveal, mine),
                        disabledForegroundColor: Colors.white,
                      ),
                      onPressed: reveal || mine != null || !canAct
                          ? null
                          : () => _answer(i),
                      child: Text(
                        question.choiceLabel(i),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 17),
                      ),
                    ),
                  ),
                ),
              if (reveal && isHost)
                TextButton(
                  key: const ValueKey('quizNext'),
                  onPressed: _goOn,
                  child: Text(game.lastQuestion ? 'Zum Ergebnis' : 'Weiter'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Color? _choiceColor(int i, bool reveal, (int, int)? mine) {
    final correct = game.question.correct;
    if (reveal) {
      if (i == correct) return Colors.green.shade600;
      if (mine?.$1 == i) return Colors.red.shade600;
      return Colors.grey.shade500;
    }
    if (mine?.$1 == i) return Colors.blueGrey.shade600;
    if (mine != null) return Colors.grey.shade500;
    return null;
  }

  // ----------------------------------------------------------- results

  Widget _results() {
    final theme = Theme.of(context);
    final order = [for (var p = 0; p < players; p++) p]
      ..sort((a, b) => game.total(b).compareTo(game.total(a)));
    final winners = game.winners();
    final name = setup.seatName(winners.first);
    return Column(
      children: [
        TurnBanner(
          text: players == 1
              ? '${game.rightAnswers(0)} von ${game.questions.length} richtig'
                    ' · ${game.total(0)} Punkte'
              : winners.length > 1
              ? 'Gleichstand! 🎉'
              : name == 'Du'
              ? 'Du gewinnst! 🏆'
              : '$name gewinnt! 🏆',
          highlight: true,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              for (final (rank, p) in order.indexed)
                Card(
                  child: ListTile(
                    key: ValueKey('quizResult$p'),
                    leading: CircleAvatar(child: Text('${rank + 1}')),
                    title: Text(setup.seatName(p)),
                    subtitle: Text(
                      '${game.rightAnswers(p)} von '
                      '${game.questions.length} richtig',
                    ),
                    trailing: Text(
                      '${game.total(p)}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 12, 8, 4),
                child: Text('Die Antworten'),
              ),
              for (final question in game.questions)
                ListTile(
                  dense: true,
                  leading: question.kind == QuestionKind.flag
                      ? FlagImage(code: question.answer, width: 40)
                      : null,
                  title: Text(question.countryName),
                  subtitle: Text(capitals[question.answer]!),
                ),
            ],
          ),
        ),
        GameOverActions(
          setup: setup,
          winnerSeats: winners,
          rematchLabel: 'Neues Quiz',
          onRematch: () {
            if (isHost) {
              _act(['new']);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Der Host startet das nächste Quiz.'),
                ),
              );
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => OnlineGameFrame(
    setup: setup,
    title: 'Länderquiz',
    child: switch (game.phase) {
      QuizPhase.setup => _setup(),
      QuizPhase.question || QuizPhase.reveal => _questionView(),
      QuizPhase.results => _results(),
    },
  );
}

/// A country's flag: a picture from flagcdn.com, the emoji without
/// internet.
class FlagImage extends StatelessWidget {
  const FlagImage({super.key, required this.code, required this.width});
  final String code;
  final double width;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(width * 0.04),
    child: DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: Colors.black12)),
      child: Image.network(
        'https://flagcdn.com/w320/$code.png',
        key: ValueKey('flag-$code'),
        width: width,
        fit: BoxFit.contain,
        errorBuilder: (context, _, _) => SizedBox(
          width: width,
          height: width * 0.66,
          child: FittedBox(child: Text(flagEmoji(code))),
        ),
      ),
    ),
  );
}
