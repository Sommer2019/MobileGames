import 'dart:io';

import 'package:flutter/foundation.dart';

/// Whether this device can scan QR codes with a camera (not on Windows and
/// Linux, where the scanner plugin has no implementation).
bool get canScanQr =>
    kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

/// Desktop computer (Windows, macOS, Linux).
bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
