// Phone and tests keep real dart:io. The browser build uses the memory files below.
export 'dart:io' if (dart.library.html) 'io_web.dart';
