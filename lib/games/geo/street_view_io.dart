import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

bool get supported => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

Widget buildView({
  required String html,
  required String baseUrl,
  required void Function(String message) onMessage,
  required void Function(void Function(String json) post) attach,
  bool interactive = true,
}) => IgnorePointer(
  ignoring: !interactive,
  child: _WebView(
    html: html,
    baseUrl: baseUrl,
    onMessage: onMessage,
    attach: attach,
  ),
);

class _WebView extends StatefulWidget {
  const _WebView({
    required this.html,
    required this.baseUrl,
    required this.onMessage,
    required this.attach,
  });

  final String html;
  final String baseUrl;
  final void Function(String message) onMessage;
  final void Function(void Function(String json) post) attach;

  @override
  State<_WebView> createState() => _WebViewState();
}

class _WebViewState extends State<_WebView> {
  late final WebViewController _c = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..addJavaScriptChannel(
      'GeoBridge',
      onMessageReceived: (m) => widget.onMessage(m.message),
    )
    ..loadHtmlString(widget.html, baseUrl: widget.baseUrl);

  @override
  void initState() {
    super.initState();
    widget.attach(
      (json) => _c.runJavaScript('window.geobingo.receive(${_jsString(json)})'),
    );
  }

  static String _jsString(String s) =>
      "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll('\n', r'\n')}'";

  @override
  Widget build(BuildContext context) {
    // The panorama gets every touch (dragging, pinching).
    final gestures = {
      Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
    };
    // Android: maps and 360° pictures draw with WebGL, which stays black on
    // some phones when the web view is shown as a texture.
    if (Platform.isAndroid) {
      return WebViewWidget.fromPlatformCreationParams(
        params:
            AndroidWebViewWidgetCreationParams.fromPlatformWebViewWidgetCreationParams(
              PlatformWebViewWidgetCreationParams(
                controller: _c.platform,
                gestureRecognizers: gestures,
              ),
              displayWithHybridComposition: true,
            ),
      );
    }
    return WebViewWidget(controller: _c, gestureRecognizers: gestures);
  }
}
