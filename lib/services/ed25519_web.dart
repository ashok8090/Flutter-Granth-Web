import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

/// Same check as the phone file. The phone file uses 64-bit ints, which a
/// browser cannot hold, so the website uses a pure-Dart implementation.
Uint8List sha512(List<int> data) => Uint8List.fromList(crypto.sha512.convert(data).bytes);

bool ed25519Verify(List<int> publicKey, List<int> message, List<int> sig) {
  try {
    return ed.verify(ed.PublicKey(publicKey), Uint8List.fromList(message), Uint8List.fromList(sig));
  } catch (_) {
    return false;
  }
}

// ---------------------------------------------------------------- canonical JSON

/// The text the server signs: keys sorted by UTF-16 code units, arrays in order, no whitespace,
/// `JSON.stringify` escaping. Mirrors `canonical()` in the admin server (src/util.js).
String canonicalJson(Object? v) {
  final b = StringBuffer();
  _canon(v, b);
  return b.toString();
}

void _canon(Object? v, StringBuffer b) {
  if (v == null) {
    b.write('null');
  } else if (v is bool) {
    b.write(v ? 'true' : 'false');
  } else if (v is num) {
    b.write(_num(v));
  } else if (v is String) {
    _str(v, b);
  } else if (v is List) {
    b.write('[');
    for (var i = 0; i < v.length; i++) {
      if (i > 0) b.write(',');
      _canon(v[i], b);
    }
    b.write(']');
  } else if (v is Map) {
    final keys = [for (final k in v.keys) '$k']..sort(); // String.compareTo = UTF-16 code units
    b.write('{');
    var first = true;
    for (final k in keys) {
      if (!first) b.write(',');
      first = false;
      _str(k, b);
      b.write(':');
      _canon(v[k], b);
    }
    b.write('}');
  } else {
    throw ArgumentError('not JSON: ${v.runtimeType}');
  }
}

String _num(num n) {
  if (n is int) return '$n';
  final d = n.toDouble();
  if (d.isNaN || d.isInfinite) return 'null';
  if (d == d.truncateToDouble() && d.abs() < 1e21) return d.toInt().toString();
  return d.toString();
}

void _str(String s, StringBuffer b) {
  b.write('"');
  final u = s.codeUnits;
  for (var i = 0; i < u.length; i++) {
    final c = u[i];
    switch (c) {
      case 0x22:
        b.write(r'\"');
      case 0x5c:
        b.write(r'\\');
      case 0x08:
        b.write(r'\b');
      case 0x0c:
        b.write(r'\f');
      case 0x0a:
        b.write(r'\n');
      case 0x0d:
        b.write(r'\r');
      case 0x09:
        b.write(r'\t');
      default:
        if (c < 0x20) {
          b.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
        } else if (c >= 0xd800 && c <= 0xdbff && i + 1 < u.length && u[i + 1] >= 0xdc00 && u[i + 1] <= 0xdfff) {
          b.writeCharCode(c);
          b.writeCharCode(u[++i]);
        } else if (c >= 0xd800 && c <= 0xdfff) {
          b.write('\\u${c.toRadixString(16)}'); // lone surrogate (well-formed JSON.stringify)
        } else {
          b.writeCharCode(c);
        }
    }
  }
  b.write('"');
}

/// The UTF-8 bytes of [canonicalJson].
Uint8List canonicalBytes(Object? v) => Uint8List.fromList(utf8.encode(canonicalJson(v)));
