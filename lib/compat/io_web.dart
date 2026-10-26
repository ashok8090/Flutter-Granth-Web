import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:archive/archive.dart' as arc;
import 'package:idb_shim/idb_browser.dart';
import 'package:web/web.dart' as web;

/// Browser stand-in for dart:io. The phone never compiles this file.
/// Files live in memory and are copied into IndexedDB so a refresh keeps them.

final gzip = _Gzip();

class _Gzip {
  List<int> encode(List<int> data) => arc.GZipEncoder().encode(data);
}

class Platform {
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isLinux => false;
  static bool get isMacOS => false;
  static bool get isWindows => false;
  static Map<String, String> get environment => const {};
}

class OSError {
  OSError([this.message = '', this.errorCode = 0]);
  final String message;
  final int errorCode;
}

class FileSystemException implements Exception {
  const FileSystemException([this.message = '', this.path = '', this.osError]);
  final String message;
  final String path;
  final OSError? osError;
  @override
  String toString() => 'FileSystemException: $message $path';
}

class HttpException implements Exception {
  HttpException(this.message);
  final String message;
  @override
  String toString() => 'HttpException: $message';
}

class SocketException implements Exception {
  SocketException(this.message);
  final String message;
}

class HandshakeException implements Exception {
  HandshakeException(this.message);
  final String message;
}

class FileMode {
  const FileMode._();
  static const read = FileMode._();
  static const write = FileMode._();
  static const append = FileMode._();
  static const writeOnly = FileMode._();
  static const writeOnlyAppend = FileMode._();
}

class FileStat {
  FileStat(this.size, this.modified);
  final int size;
  final DateTime modified;
}

class WebFs {
  static final files = <String, Uint8List>{};
  static final mtimes = <String, DateTime>{};
  static final dirs = <String>{'/'};
  static Database? _db;
  static var _ready = Future<void>.value();
  static var _started = false;

  static Future<void> get ready {
    if (!_started) {
      _started = true;
      _ready = _open();
    }
    return _ready;
  }

  static Future<void> _open() async {
    try {
      _db = await idbFactoryBrowser.open('granth-fs', version: 1, onUpgradeNeeded: (e) {
        e.database.createObjectStore('files');
      });
      final txn = _db!.transaction('files', idbModeReadOnly);
      final store = txn.objectStore('files');
      final keys = await store.getAllKeys();
      for (final key in keys) {
        final path = '$key';
        final raw = await store.getObject(key);
        if (raw is List) {
          files[path] = Uint8List.fromList(raw.cast<int>());
          mtimes[path] = DateTime.now();
          _addDir(_parent(path));
        }
      }
      await txn.completed;
    } catch (_) {
      _db = null;
    }
  }

  static void _addDir(String path) {
    var p = path;
    while (p.isNotEmpty && p != '/') {
      dirs.add(p);
      p = _parent(p);
    }
    dirs.add('/');
  }

  static String _parent(String path) {
    final i = path.lastIndexOf('/');
    if (i <= 0) return '/';
    return path.substring(0, i);
  }

  static void put(String path, Uint8List bytes) {
    files[path] = bytes;
    mtimes[path] = DateTime.now();
    _addDir(_parent(path));
    final db = _db;
    if (db == null) return;
    db.transaction('files', idbModeReadWrite).objectStore('files').put(bytes, path);
  }

  static void remove(String path) {
    files.remove(path);
    mtimes.remove(path);
    final db = _db;
    if (db == null) return;
    db.transaction('files', idbModeReadWrite).objectStore('files').delete(path);
  }
}

class FileSystemEntity {
  FileSystemEntity(this.path);
  final String path;

  Future<bool> exists() async {
    await WebFs.ready;
    return existsSync();
  }

  bool existsSync() => WebFs.files.containsKey(path) || WebFs.dirs.contains(path);

  Future<FileStat> stat() async {
    await WebFs.ready;
    return statSync();
  }

  FileStat statSync() => FileStat(WebFs.files[path]?.length ?? 0, WebFs.mtimes[path] ?? DateTime.fromMillisecondsSinceEpoch(0));

  Future<void> delete({bool recursive = false}) async {
    await WebFs.ready;
    deleteSync(recursive: recursive);
  }

  void deleteSync({bool recursive = false}) {
    WebFs.remove(path);
    if (recursive) {
      final prefix = path.endsWith('/') ? path : '$path/';
      for (final k in WebFs.files.keys.where((k) => k.startsWith(prefix)).toList()) {
        WebFs.remove(k);
      }
      WebFs.dirs.removeWhere((d) => d == path || d.startsWith(prefix));
    }
  }
}

class Directory extends FileSystemEntity {
  Directory(super.path);

  static Directory get systemTemp => Directory('/tmp');

  Directory get parent => Directory(WebFs._parent(path));

  Future<Directory> create({bool recursive = false}) async {
    await WebFs.ready;
    createSync(recursive: recursive);
    return this;
  }

  void createSync({bool recursive = false}) {
    WebFs.dirs.add(path);
    if (recursive) WebFs._addDir(path);
  }

  Future<Directory> createTemp([String prefix = '']) async {
    final d = Directory('$path/$prefix${DateTime.now().microsecondsSinceEpoch}');
    await d.create(recursive: true);
    return d;
  }

  List<FileSystemEntity> listSync({bool recursive = false, bool followLinks = true}) {
    final prefix = path.endsWith('/') ? path : '$path/';
    final out = <FileSystemEntity>[];
    for (final k in WebFs.files.keys) {
      if (!k.startsWith(prefix)) continue;
      final rest = k.substring(prefix.length);
      if (!recursive && rest.contains('/')) continue;
      out.add(File(k));
    }
    return out;
  }

  Stream<FileSystemEntity> list({bool recursive = false, bool followLinks = true}) async* {
    for (final e in listSync(recursive: recursive, followLinks: followLinks)) {
      yield e;
    }
  }
}

class RandomAccessFile {
  RandomAccessFile(this._file);
  final File _file;
  int _pos = 0;

  void writeFromSync(List<int> buffer, [int start = 0, int? end]) {
    final chunk = Uint8List.fromList(buffer.sublist(start, end ?? buffer.length));
    final cur = WebFs.files[_file.path] ?? Uint8List(0);
    final need = _pos + chunk.length;
    final next = Uint8List(need > cur.length ? need : cur.length);
    next.setRange(0, cur.length, cur);
    next.setRange(_pos, _pos + chunk.length, chunk);
    _pos += chunk.length;
    WebFs.put(_file.path, next);
  }

  void setPositionSync(int position) => _pos = position;

  Future<void> setPosition(int position) async => setPositionSync(position);

  Uint8List readSync(int count) {
    final cur = WebFs.files[_file.path] ?? Uint8List(0);
    final end = (_pos + count) > cur.length ? cur.length : _pos + count;
    final out = end <= _pos ? Uint8List(0) : Uint8List.sublistView(cur, _pos, end);
    _pos = end;
    return Uint8List.fromList(out);
  }

  Future<Uint8List> read(int count) async => readSync(count);

  void flushSync() {}

  void closeSync() {}

  Future<void> close() async {}
}

class File extends FileSystemEntity {
  File(super.path);

  Directory get parent => Directory(WebFs._parent(path));

  int lengthSync() => WebFs.files[path]?.length ?? 0;

  Future<int> length() async {
    await WebFs.ready;
    return lengthSync();
  }

  bool existsSync() {
    return WebFs.files.containsKey(path);
  }

  @override
  Future<bool> exists() async {
    await WebFs.ready;
    return existsSync();
  }

  Future<String> readAsString() async => utf8.decode(await readAsBytes());

  Future<File> writeAsString(String text, {bool flush = false}) => writeAsBytes(utf8.encode(text), flush: flush);

  void setLastModifiedSync(DateTime time) => WebFs.mtimes[path] = time;

  DateTime lastModifiedSync() => WebFs.mtimes[path] ?? DateTime.fromMillisecondsSinceEpoch(0);

  Uri get uri => Uri.parse('file://${path.startsWith('/') ? path : '/$path'}');

  Future<DateTime> lastModified() async {
    await WebFs.ready;
    return lastModifiedSync();
  }

  Future<Uint8List> readAsBytes() async {
    await WebFs.ready;
    return Uint8List.fromList(WebFs.files[path] ?? Uint8List(0));
  }

  Uint8List readAsBytesSync() => Uint8List.fromList(WebFs.files[path] ?? Uint8List(0));

  Future<File> writeAsBytes(List<int> bytes, {bool flush = false}) async {
    await WebFs.ready;
    WebFs.put(path, bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
    return this;
  }

  void _set(Uint8List bytes) => WebFs.put(path, bytes);

  Future<File> copy(String newPath) async {
    await WebFs.ready;
    final data = WebFs.files[path];
    if (data == null) throw const FileSystemException('not found');
    WebFs.put(newPath, Uint8List.fromList(data));
    return File(newPath);
  }

  Future<File> rename(String newPath) async {
    await WebFs.ready;
    final data = WebFs.files[path];
    if (data == null) throw const FileSystemException('not found');
    WebFs.put(newPath, data);
    WebFs.remove(path);
    return File(newPath);
  }

  RandomAccessFile openSync({FileMode mode = FileMode.read}) {
    if (mode == FileMode.write || mode == FileMode.writeOnly) {
      WebFs.put(path, Uint8List(0));
    }
    return RandomAccessFile(this);
  }

  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    await WebFs.ready;
    return openSync(mode: mode);
  }

  _MemSink openWrite({FileMode mode = FileMode.write}) {
    if (mode == FileMode.write || mode == FileMode.writeOnly) WebFs.put(path, Uint8List(0));
    return _MemSink(this);
  }

  Stream<List<int>> openRead([int? start, int? end]) async* {
    await WebFs.ready;
    final data = WebFs.files[path] ?? Uint8List(0);
    final a = start ?? 0;
    final b = end ?? data.length;
    yield Uint8List.sublistView(data, a, b < a ? a : b);
  }
}

class _MemSink implements StreamConsumer<List<int>> {
  _MemSink(this.file);
  final File file;
  final _b = BytesBuilder();
  var _closed = false;

  void add(List<int> data) => _b.add(data);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final c in stream) {
      _b.add(c);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    file._set(_b.toBytes());
  }
}

class ZLibEncoder {
  ZLibEncoder({this.level = 6});
  final int level;
  List<int> convert(List<int> data) => arc.ZLibEncoder().encode(data);
}

class ZLibDecoder {
  List<int> convert(List<int> data) => arc.ZLibDecoder().decodeBytes(data);
}

class HttpDate {
  static DateTime parse(String date) => DateTime.tryParse(date) ?? DateTime.fromMillisecondsSinceEpoch(0);
}

class InternetAddress {
  InternetAddress._();
  static final loopbackIPv4 = InternetAddress._();
}

class ContentType {
  ContentType(this.primaryType, this.subType, {this.charset});
  final String primaryType;
  final String subType;
  final String? charset;
  static final text = ContentType('text', 'plain', charset: 'utf-8');
  static ContentType parse(String value) {
    final parts = value.split('/');
    final primary = parts.isNotEmpty ? parts.first : 'application';
    final rest = parts.length > 1 ? parts[1] : 'octet-stream';
    final sub = rest.split(';').first.trim();
    return ContentType(primary, sub);
  }

  @override
  String toString() => '$primaryType/$subType';
}

class HttpHeaders {
  final _v = <String, String>{};
  ContentType? contentType;
  int contentLength = -1;

  void set(String name, Object value) => _v[name.toLowerCase()] = '$value';

  String? value(String name) => _v[name.toLowerCase()];
}

class HttpResponse {
  final headers = HttpHeaders();
  int statusCode = 200;
  final _body = BytesBuilder();

  void add(List<int> data) => _body.add(data);

  void write(Object? object) => add(utf8.encode('$object'));

  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final c in stream) {
      add(c);
    }
  }

  Future<void> close() async {}
}

class HttpRequest {
  HttpRequest(this.method, this.uri);
  final String method;
  final Uri uri;
  final headers = HttpHeaders();
  final response = HttpResponse();
}

class HttpServer {
  HttpServer._(this.port);
  var autoCompress = false;
  final int port;

  static Future<HttpServer> bind(Object address, int port) async => HttpServer._(port == 0 ? 80 : port);

  StreamSubscription<HttpRequest> listen(void Function(HttpRequest)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return const Stream<HttpRequest>.empty().listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  Future<void> close({bool force = false}) async {}
}

class HttpClientRequest {
  HttpClientRequest(this._url);
  final Uri _url;
  final headers = HttpHeaders();
  int contentLength = -1;
  final _body = BytesBuilder();

  void add(List<int> data) => _body.add(data);

  Future<HttpClientResponse> close() {
    final method = _body.isEmpty ? 'GET' : 'POST';
    return _browserSend(_url, method, headers, _body.toBytes());
  }
}

class HttpClientResponse extends Stream<List<int>> {
  HttpClientResponse(this.statusCode, Uint8List body) : _body = body;
  final int statusCode;
  final Uint8List _body;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<List<int>>.value(_body).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

class HttpClient {
  Duration? connectionTimeout;

  Future<HttpClientRequest> getUrl(Uri url) async => HttpClientRequest(url);

  Future<HttpClientRequest> postUrl(Uri url) async => HttpClientRequest(url);

  void close({bool force = false}) {}
}

Future<HttpClientResponse> _browserSend(Uri url, String method, HttpHeaders headers, Uint8List body) {
  final done = Completer<HttpClientResponse>();
  final xhr = web.XMLHttpRequest();
  xhr.open(method, url.toString(), true);
  xhr.responseType = 'arraybuffer';
  headers._v.forEach((name, value) => xhr.setRequestHeader(name, value));
  if (headers.contentType != null) xhr.setRequestHeader('content-type', headers.contentType.toString());
  xhr.onload = ((web.Event _) {
    final raw = xhr.response;
    Uint8List bytes = Uint8List(0);
    if (raw != null) {
      try {
        bytes = (raw as JSArrayBuffer).toDart.asUint8List();
      } catch (_) {}
    }
    done.complete(HttpClientResponse(xhr.status, bytes));
  }).toJS;
  xhr.onerror = ((web.Event _) => done.completeError(SocketException('network'))).toJS;
  if (body.isEmpty) {
    xhr.send();
  } else {
    xhr.send(body.toJS);
  }
  return done.future;
}

