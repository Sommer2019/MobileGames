/// Limits how many chat messages one sender gets through: at most [burst]
/// within [window]. Used when sending (with a hint) and when receiving
/// (so a changed app cannot flood others either).
class FloodGuard {
  FloodGuard({this.burst = 5, this.window = const Duration(seconds: 10)});

  final int burst;
  final Duration window;
  final Map<Object, List<DateTime>> _times = {};

  /// Whether a message from [sender] at [at] (default: now) may pass;
  /// counts it if so.
  bool allow(Object sender, [DateTime? at]) {
    final t = at ?? DateTime.now();
    final list = _times.putIfAbsent(sender, () => []);
    list.removeWhere((x) => (t.difference(x)).abs() >= window);
    if (list.length >= burst) return false;
    list.add(t);
    return true;
  }
}
