import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

/// Website equivalent of saving into Downloads or opening the file.
Future<String?> saveBrowser(String name, List<int> bytes, String mime, {bool open = false}) async {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final blob = Blob([data.toJS].toJS, BlobPropertyBag(type: mime));
  final url = URL.createObjectURL(blob);
  if (open) {
    window.open(url, '_blank');
    return url;
  }
  final a = document.createElement('a') as HTMLAnchorElement;
  a.href = url;
  a.download = name;
  a.click();
  return url;
}
