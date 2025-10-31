import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

bool get isDesktopOrElse =>
  kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux;
