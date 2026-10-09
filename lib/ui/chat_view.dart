import 'dart:async';

import 'package:flutter/material.dart';

import '../core/konami.dart';
import 'confetti.dart';

class ChatEntry {
  const ChatEntry({
    required this.mine,
    required this.author,
    required this.text,
    required this.time,
    this.pending = false,
  });
  final bool mine;
  final String author;
  final String text;
  final DateTime time;
  final bool pending;
}

/// Simple chat UI used for friend chats and the in-game chat.
class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.lines,
    required this.onSend,
    this.quickReplies = const [],
    this.showAuthors = true,
    this.emptyText = 'Noch keine Nachrichten.',
  });

  final List<ChatEntry> lines;

  /// Sends a line; false means too many too fast (a hint is shown).
  final FutureOr<bool> Function(String text) onSend;
  final List<String> quickReplies;
  final bool showAuthors;
  final String emptyText;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _controller = TextEditingController();

  /// Messages already looked at (older ones don't trigger confetti).
  late int _seen;
  bool _confetti = false;

  @override
  void initState() {
    super.initState();
    _seen = widget.lines.length;
  }

  @override
  void didUpdateWidget(ChatView old) {
    super.didUpdateWidget(old);
    final lines = widget.lines;
    if (lines.length > _seen &&
        lines.skip(_seen).any((l) => isKonamiText(l.text))) {
      _confetti = true;
    }
    _seen = lines.length;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final t = (text ?? _controller.text).trim();
    if (t.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await widget.onSend(t)) {
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Nicht so schnell 🙂 Warte kurz.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (text == null && _controller.text.trim() == t) _controller.clear();
  }

  String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lines = widget.lines.reversed.toList();
    return Stack(
      children: [
        _column(context, scheme, lines),
        if (_confetti)
          Positioned.fill(
            child: Confetti(
              key: const ValueKey('confetti'),
              onDone: () => setState(() => _confetti = false),
            ),
          ),
      ],
    );
  }

  Widget _column(
    BuildContext context,
    ColorScheme scheme,
    List<ChatEntry> lines,
  ) {
    return Column(
      children: [
        Expanded(
          child: lines.isEmpty
              ? Center(child: Text(widget.emptyText))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: lines.length,
                  itemBuilder: (context, i) {
                    final l = lines[i];
                    return Align(
                      alignment: l.mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 320),
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: l.mine
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.showAuthors && !l.mine)
                              Text(
                                l.author,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: scheme.primary,
                                ),
                              ),
                            Text(l.text),
                            Text(
                              l.pending ? '${_time(l.time)} …' : _time(l.time),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (widget.quickReplies.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final q in widget.quickReplies)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ActionChip(
                      label: Text(q),
                      onPressed: () => _send(q),
                    ),
                  ),
              ],
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('chatInput'),
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: 'Nachricht …',
                      counterText: '',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(
                  key: const ValueKey('chatSend'),
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
