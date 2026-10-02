import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../games/registry.dart';
import '../ui/lobby_screen.dart';
import 'services.dart';

/// Feeds the home screen widgets ("Spieleabend": messages, friends online,
/// recently played games) and opens the app where a widget was tapped.
///
/// Links look like `mobilegames://game/chess?homeWidget`.
class HomeWidgets {
  HomeWidgets._();

  static const appGroup = 'group.de.sommer2019.mobileGames';
  static const androidGameNight = 'de.sommer2019.mobile_games.GameNightWidget';
  static const iosGameNight = 'GameNightWidget';
  static const _recentKey = 'widget.recent';

  static GlobalKey<NavigatorState>? _navigator;
  static Timer? _debounce;

  static final bool _testing =
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  static bool get _supported =>
      !_testing && !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Call once after the services are ready.
  static Future<void> init(GlobalKey<NavigatorState> navigator) async {
    _navigator = navigator;
    if (!_supported) return;
    try {
      await HomeWidget.setAppGroupId(appGroup);
      HomeWidget.widgetClicked.listen(open, onError: (_) {});
      final initial = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (initial != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => open(initial));
      }
    } catch (_) {}
    final s = Services.I;
    for (final l in <Listenable>[
      s.chat,
      s.presence,
      s.account,
      s.friendRequests,
    ]) {
      l.addListener(update);
    }
    update();
  }

  /// Remembers [gameId] for the quick start buttons.
  static Future<void> recordPlayed(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    final recent = prefs.getStringList(_recentKey) ?? [];
    recent
      ..remove(gameId)
      ..insert(0, gameId);
    await prefs.setStringList(_recentKey, recent.take(3).toList());
    update();
  }

  /// Opens the screen a widget link points to.
  static void open(Uri? uri) {
    final nav = _navigator?.currentState;
    if (uri == null || nav == null) return;
    final target = linkTarget(uri);
    if (target == null) return;
    final game = gameById(target);
    if (game == null) return;
    nav.popUntil((r) => r.isFirst);
    recordPlayed(game.id);
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => game.isMultiplayer
            ? LobbyScreen(game: game)
            : game.singleplayerBuilder!(),
      ),
    );
  }

  /// Game id from a widget link, or null.
  static String? linkTarget(Uri uri) {
    if (uri.scheme != 'mobilegames') return null;
    if (uri.host == 'dice') return 'dice';
    if (uri.host == 'game' && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    return null;
  }

  /// Pushes the current state to the widgets (debounced).
  static void update() {
    if (!_supported || !Services.isReady) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _push);
  }

  /// What the "Spieleabend" widget shows.
  static Future<Map<String, Object>> snapshot() async {
    final s = Services.I;
    final online = [
      for (final f in s.account.friends)
        if (s.presence.isOnline(f.pubkey)) f.name,
    ];
    final prefs = await SharedPreferences.getInstance();
    final recent = [
      for (final id in prefs.getStringList(_recentKey) ?? const <String>[])
        if (gameById(id) case final g?) {'id': g.id, 'title': g.title},
    ];
    return {
      'unread': s.chat.totalUnread,
      'requests': s.friendRequests.pending.length,
      'onlineCount': online.length,
      'online': online.take(4).join(', '),
      'recent': jsonEncode(recent),
    };
  }

  static Future<void> _push() async {
    try {
      final data = await snapshot();
      for (final e in data.entries) {
        await HomeWidget.saveWidgetData(e.key, e.value);
      }
      await HomeWidget.updateWidget(
        qualifiedAndroidName: androidGameNight,
        iOSName: iosGameNight,
      );
    } catch (_) {
      // Widgets are optional; never let them break the app.
    }
  }
}
