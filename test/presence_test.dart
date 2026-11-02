import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/services/presence.dart';
import 'package:granthprabandhan/state/router.dart';

/// Records presence posts; [script] gives status codes (0 = network failure).
class Net implements HttpClientAdapter {
  final List<String> paths = [];
  final List<Map<String, dynamic>> bodies = [];
  final List<RequestOptions> opts = [];
  final List<int> script = [];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final raw = <int>[];
    await for (final c in requestStream ?? const Stream<Uint8List>.empty()) {
      raw.addAll(c);
    }
    final code = script.isEmpty ? 204 : script.removeAt(0);
    paths.add(options.uri.path);
    opts.add(options);
    bodies.add(jsonDecode(utf8.decode(raw)) as Map<String, dynamic>);
    if (code == 0) throw DioException.connectionError(requestOptions: options, reason: 'offline');
    return ResponseBody.fromString('', code);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  const iid = '0123456789abcdef0123456789abcdef';
  late Net net;
  late Presence p;
  var screen = 'home';
  String? uid;

  Presence make({String key = 'gak_test'}) {
    final dio = Dio()..httpClientAdapter = net;
    return Presence(dio: dio, base: 'https://w.example/', appKey: key, iid: () => iid, uid: () => uid, screen: () => screen, enabled: true);
  }

  setUp(() {
    net = Net();
    screen = 'home';
    uid = null;
  });

  Future<void> life(WidgetTester t, AppLifecycleState s) async {
    t.binding.handleAppLifecycleStateChanged(s);
    await t.pump(const Duration(milliseconds: 10));
  }

  testWidgets('heartbeat on start with X-App-Key and the §19.1 body, then every 20 s', (t) async {
    p = make();
    p.start();
    await t.pump(const Duration(milliseconds: 10));
    expect(net.paths, ['/presence/heartbeat']);
    expect(net.opts.first.headers['X-App-Key'], 'gak_test');
    expect(net.opts.first.contentType, startsWith('application/json'));
    expect(net.bodies.first, {'install_id': iid, 'screen': 'home', 'app_version': '1.0.0'});
    await t.pump(const Duration(seconds: 20));
    await t.pump(const Duration(seconds: 20));
    expect(net.paths.where((x) => x == '/presence/heartbeat').length, 3);
    p.stop();
  });

  testWidgets('leave on paused/hidden; nothing in the background; heartbeat again on resume', (t) async {
    p = make();
    p.start();
    await t.pump(const Duration(milliseconds: 10));
    await life(t, AppLifecycleState.inactive);
    expect(net.paths, ['/presence/heartbeat']); // inactive = still on screen
    await life(t, AppLifecycleState.hidden);
    await life(t, AppLifecycleState.paused);
    expect(net.paths, ['/presence/heartbeat', '/presence/leave']); // one leave only
    await t.pump(const Duration(seconds: 90));
    expect(net.paths.length, 2);
    await life(t, AppLifecycleState.resumed);
    expect(net.paths.last, '/presence/heartbeat');
    await life(t, AppLifecycleState.detached);
    expect(net.paths.last, '/presence/leave');
    p.stop();
  });

  testWidgets('uid only when signed in; bad optional fields are left out', (t) async {
    p = make(key: '');
    uid = 'Abc_123-x';
    screen = 'Reader';
    expect(p.body(), {'install_id': iid, 'uid': 'Abc_123-x', 'screen': 'reader', 'app_version': '1.0.0'});
    uid = 'bad uid!';
    screen = 'a very long screen name that is too long';
    expect(p.body(), {'install_id': iid, 'app_version': '1.0.0'});
    p.start();
    await t.pump(const Duration(milliseconds: 10));
    expect(net.opts.first.headers.containsKey('X-App-Key'), isFalse);
    p.stop();
  });

  testWidgets('fails silently: 401/503/offline are ignored and never retried', (t) async {
    net.script.addAll([401, 503, 0]);
    p = make();
    p.start();
    await t.pump(const Duration(milliseconds: 10));
    expect(net.paths.length, 1);
    await t.pump(const Duration(seconds: 5));
    expect(net.paths.length, 1); // no retry loop
    await t.pump(const Duration(seconds: 15));
    await t.pump(const Duration(seconds: 20));
    expect(net.paths.length, 3);
    expect(t.takeException(), isNull);
    p.stop();
  });

  testWidgets('heartbeat on a screen change (with the new screen), not on same-screen nav', (t) async {
    p = make();
    p.start();
    await t.pump(const Duration(milliseconds: 10));
    screen = 'topics';
    AppNav.I.go('#/topics');
    await t.pump(const Duration(milliseconds: 10));
    expect(net.paths.length, 2);
    expect(net.bodies.last['screen'], 'topics');
    AppNav.I.go('#/topics?x=1');
    await t.pump(const Duration(milliseconds: 10));
    expect(net.paths.length, 2);
    p.stop();
    AppNav.I.go('#/dashboard');
  });
}
