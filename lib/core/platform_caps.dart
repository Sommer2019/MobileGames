import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether this device can scan QR codes with a camera (not on Windows and
/// Linux, where the scanner plugin has no implementation).
bool get canScanQr =>
    kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

/// Desktop computer (Windows, macOS, Linux).
bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

bool? _naturalLandscape;

/// Whether the device is landscape in its natural orientation, like gaming
/// handhelds (AYN Thor, Odin, Retroid) and some tablets. Its motion sensor
/// axes then follow the landscape screen.
Future<bool> naturalLandscape() async {
  if (_naturalLandscape case final v?) return v;
  var v = false;
  if (!kIsWeb && Platform.isAndroid) {
    try {
      v =
          await const MethodChannel('mobilegames/device')
              .invokeMethod<bool>('naturalLandscape') ??
          false;
    } catch (_) {}
  }
  return _naturalLandscape = v;
}
