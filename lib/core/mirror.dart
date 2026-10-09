import 'package:flutter/widgets.dart';

/// Watching games that are played on one device (alone, against the
/// computer or with people at the same device): the playing device sends
/// its game state now and then, the watching device shows the same game
/// screen without input and applies each state ("mirror").

/// A game on this device that friends may watch.
abstract interface class MirrorSource {
  /// Game id from the registry; null: this screen offers no mirror (e.g.
  /// online games, which are watched through their room).
  String? get mirrorGame;

  /// What the watcher needs to build the screen (players, computers …).
  Map<String, dynamic> get mirrorSetup;

  /// The current state, or null when there is nothing to show yet.
  Map<String, dynamic>? mirrorState();

  /// How often the state is checked for changes.
  Duration get mirrorInterval;
}

/// The game currently played on this device that can be watched.
class Mirrors {
  Mirrors._();
  static final ValueNotifier<MirrorSource?> current = ValueNotifier(null);
}

/// A friend's game shown on this device.
class MirrorFeed {
  MirrorFeed({
    required this.gameId,
    required this.friendName,
    required this.setup,
    Map<String, dynamic>? state,
    this.onClose,
  }) : state = ValueNotifier(state);

  final String gameId;
  final String friendName;
  final Map<String, dynamic> setup;
  final ValueNotifier<Map<String, dynamic>?> state;

  /// The friend stopped playing (or the connection is gone).
  final ValueNotifier<bool> ended = ValueNotifier(false);
  final Future<void> Function()? onClose;

  Future<void> close() async => onClose?.call();
}

/// Above a game screen that shows a friend's game.
class MirrorScope extends InheritedWidget {
  const MirrorScope({super.key, required this.feed, required super.child});
  final MirrorFeed feed;

  static MirrorFeed? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MirrorScope>()?.feed;

  @override
  bool updateShouldNotify(MirrorScope old) => feed != old.feed;
}

/// For game screens: offers the game for watching while it is played here,
/// and shows a friend's game when opened inside a [MirrorScope].
mixin GameMirror<T extends StatefulWidget> on State<T> implements MirrorSource {
  MirrorFeed? _feed;

  /// This screen shows a friend's game (no input, no saving).
  bool get mirroring => _feed != null;

  @override
  Map<String, dynamic> get mirrorSetup => const {};

  @override
  Duration get mirrorInterval => const Duration(milliseconds: 300);

  /// Shows [state] (sent by [mirrorState] on the friend's device).
  void applyMirror(Map<String, dynamic> state);

  @override
  void initState() {
    super.initState();
    _feed = MirrorScope.of(context);
    final feed = _feed;
    if (feed != null) {
      feed.state.addListener(_onFeed);
      WidgetsBinding.instance.addPostFrameCallback((_) => _onFeed());
    } else if (mirrorGame != null) {
      Mirrors.current.value = this;
    }
  }

  void _onFeed() {
    final s = _feed?.state.value;
    if (s == null || !mounted) return;
    try {
      setState(() => applyMirror(s));
    } catch (_) {
      // A state this version cannot show: keep the last one.
    }
  }

  @override
  void dispose() {
    _feed?.state.removeListener(_onFeed);
    if (Mirrors.current.value == this) Mirrors.current.value = null;
    super.dispose();
  }
}
