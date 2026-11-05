import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';

bool get supported => true;

Widget buildView({
  required String html,
  required String baseUrl,
  required void Function(String message) onMessage,
  required void Function(void Function(String json) post) attach,
  bool interactive = true,
}) => _Frame(
  html: html,
  onMessage: onMessage,
  attach: attach,
  interactive: interactive,
);

class _Frame extends StatefulWidget {
  const _Frame({
    required this.html,
    required this.onMessage,
    required this.attach,
    required this.interactive,
  });

  final String html;

  /// Flutter widgets drawn over an iframe do not get clicks unless the
  /// iframe lets them through.
  final bool interactive;
  final void Function(String message) onMessage;
  final void Function(void Function(String json) post) attach;

  @override
  State<_Frame> createState() => _FrameState();
}

class _FrameState extends State<_Frame> {
  JSObject? _frame;
  JSFunction? _listener;

  @override
  void initState() {
    super.initState();
    _listener = ((JSObject e) {
      final frame = _frame;
      if (frame == null) return;
      final win = frame['contentWindow'];
      if (win == null || !identical(e['source'], win) && e['source'] != win) {
        return;
      }
      final data = e['data'];
      if (data == null || !data.isA<JSObject>()) return;
      final s = (data as JSObject)['geobingo'];
      if (s != null && s.isA<JSString>()) {
        widget.onMessage((s as JSString).toDart);
      }
    }).toJS;
    globalContext.callMethod<JSAny?>(
      'addEventListener'.toJS,
      'message'.toJS,
      _listener,
    );
    widget.attach((json) {
      final win = _frame?['contentWindow'];
      if (win == null || !win.isA<JSObject>()) return;
      final msg = JSObject()..['geobingoIn'] = json.toJS;
      (win as JSObject).callMethod<JSAny?>('postMessage'.toJS, msg, '*'.toJS);
    });
  }

  void _pointerEvents() {
    final style = _frame?['style'];
    if (style != null && style.isA<JSObject>()) {
      (style as JSObject)['pointerEvents'] =
          (widget.interactive ? 'auto' : 'none').toJS;
    }
  }

  @override
  void didUpdateWidget(_Frame old) {
    super.didUpdateWidget(old);
    if (old.interactive != widget.interactive) _pointerEvents();
  }

  @override
  void dispose() {
    globalContext.callMethod<JSAny?>(
      'removeEventListener'.toJS,
      'message'.toJS,
      _listener,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (Object el) {
      final f = el as JSObject;
      _frame = f;
      final style = f['style'] as JSObject;
      style['border'] = 'none'.toJS;
      style['width'] = '100%'.toJS;
      style['height'] = '100%'.toJS;
      f['allow'] = 'fullscreen; accelerometer; gyroscope'.toJS;
      f['srcdoc'] = widget.html.toJS;
      _pointerEvents();
    },
  );
}
