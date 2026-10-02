import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'game_session.dart';

/// Direct peer-to-peer data channel using WebRTC. Public STUN servers are
/// used for NAT traversal; there is no TURN server (no own backend), so if
/// the networks of both players block direct connections, [GameSession]
/// keeps using the encrypted relay path.
class WebRtcTransport implements P2pTransport {
  static const _config = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
          'stun:stun.cloudflare.com:3478',
        ],
      },
    ],
  };

  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  final _incoming = StreamController<String>.broadcast();
  final _open = StreamController<bool>.broadcast();
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteSet = false;
  bool _isOpen = false;
  late void Function(Map<String, dynamic>) _sendSignal;
  final _ready = Completer<void>();
  // Signals are processed strictly one after another.
  Future<void> _chain = Future.value();

  @override
  Stream<String> get incoming => _incoming.stream;
  @override
  Stream<bool> get openChanges => _open.stream;
  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> start({
    required bool isHost,
    required void Function(Map<String, dynamic>) sendSignal,
  }) async {
    _sendSignal = sendSignal;
    final pc = await createPeerConnection(_config);
    _pc = pc;
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      _sendSignal({
        'kind': 'ice',
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };
    pc.onDataChannel = _attach;
    if (isHost) {
      _attach(
        await pc.createDataChannel(
          'game',
          RTCDataChannelInit()..ordered = true,
        ),
      );
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _sendSignal({'kind': 'sdp', 'type': offer.type, 'sdp': offer.sdp});
    }
    _ready.complete();
  }

  void _attach(RTCDataChannel dc) {
    _dc = dc;
    dc.onDataChannelState = (s) {
      final open = s == RTCDataChannelState.RTCDataChannelOpen;
      if (open != _isOpen) {
        _isOpen = open;
        _open.add(open);
      }
    };
    if (dc.state == RTCDataChannelState.RTCDataChannelOpen && !_isOpen) {
      _isOpen = true;
      _open.add(true);
    }
    dc.onMessage = (m) {
      if (!m.isBinary) _incoming.add(m.text);
    };
  }

  @override
  Future<void> onSignal(Map<String, dynamic> s) {
    _chain = _chain
        .then((_) => _ready.future)
        .then((_) => _handle(s))
        .catchError((_) {});
    return _chain;
  }

  Future<void> _handle(Map<String, dynamic> s) async {
    final pc = _pc;
    if (pc == null) return;
    if (s['kind'] == 'sdp') {
      await pc.setRemoteDescription(
        RTCSessionDescription(s['sdp'] as String?, s['type'] as String?),
      );
      _remoteSet = true;
      for (final c in _pendingCandidates) {
        await pc.addCandidate(c);
      }
      _pendingCandidates.clear();
      if (s['type'] == 'offer') {
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        _sendSignal({'kind': 'sdp', 'type': answer.type, 'sdp': answer.sdp});
      }
    } else if (s['kind'] == 'ice') {
      final c = RTCIceCandidate(
        s['candidate'] as String?,
        s['sdpMid'] as String?,
        s['sdpMLineIndex'] as int?,
      );
      if (_remoteSet) {
        await pc.addCandidate(c);
      } else {
        _pendingCandidates.add(c);
      }
    }
  }

  @override
  void send(String text) => _dc?.send(RTCDataChannelMessage(text));

  @override
  Future<void> close() async {
    _isOpen = false;
    await _dc?.close();
    await _pc?.close();
  }
}
