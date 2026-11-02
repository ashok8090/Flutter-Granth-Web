/// Firebase (project granth-management): Analytics, Crashlytics, optional Google sign-in and
/// FCM topic subscriptions. Everything is optional and guarded: when Firebase can not start
/// (tests, no Play services, offline first run) the app works exactly as before.
library;

import 'dart:async';
import 'dart:convert';
import 'package:granthprabandhan/compat/io.dart';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../state/router.dart';
import '../state/toast.dart';
import 'analytics.dart';
import 'remote_config.dart';
import 'storage.dart';

/// Optional Web OAuth client id (when google-services.json carries none).
const String kGoogleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID', defaultValue: '386256348529-55gsprsn906i00e6726tu1gdo253kipv.apps.googleusercontent.com');

/// FCM topics (provisional until CONTRACT.md names them; see round14_backend_needs.md).
/// CONTRACT §6.3 FCM topics. `all` is always on (unless `flags.notifications_enabled` is false).
class PushTopics {
  static const all = 'all';
  static const newPraman = 'new_praman';
  static const newTopic = 'new_topic';
  static const trending = 'trending';
  static const daily = 'daily';
  static const toggles = [daily, newPraman, newTopic, trending];
  static const every = [all, ...toggles];
}

class AccountInfo {
  const AccountInfo({required this.email, this.name = '', this.photo = ''});
  final String email, name, photo;
  Map<String, String> toJson() => {'email': email, 'name': name, 'photo': photo};
  static AccountInfo? fromJson(Object? j) =>
      j is Map && j['email'] is String && (j['email'] as String).isNotEmpty ? AccountInfo(email: j['email'] as String, name: '${j['name'] ?? ''}', photo: '${j['photo'] ?? ''}') : null;
}

class FirebaseBridge extends ChangeNotifier {
  FirebaseBridge._();
  static final FirebaseBridge I = FirebaseBridge._();

  static const kAccount = 'granth-account';
  static const kPush = 'granth-push-topics';

  bool ready = false;
  bool busy = false;
  String? error;

  /// Round-2: what the sign-in is doing right now (shown under the button), e.g. "Google खाता…".
  String? stage;
  AccountInfo? _account;

  static bool get _supported => !kIsWeb && Platform.isAndroid && !Platform.environment.containsKey('FLUTTER_TEST');

  AccountInfo? get account => _account ??= AccountInfo.fromJson(_decode(Store.I.getString(kAccount)));
  bool get signedIn => account != null;

  /// The Firebase uid while signed in (for presence); null when signed out or Firebase is off.
  String? get uid {
    if (!signedIn || !ready) return null;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  static Object? _decode(String? s) {
    try {
      return s == null ? null : jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> init() async {
    if (!_supported || ready) return;
    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 4));
      ready = true;
    } catch (e) {
      debugPrint('firebase: init: $e');
      return;
    }
    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        prev?.call(d);
        FirebaseCrashlytics.instance.recordFlutterError(d);
      };
      final prevP = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (e, st) {
        FirebaseCrashlytics.instance.recordError(e, st, fatal: true);
        return prevP?.call(e, st) ?? true;
      };
    } catch (e) {
      debugPrint('firebase: crashlytics: $e');
    }
    Analytics.screenForward = (screen) => unawaited(FirebaseAnalytics.instance.logScreenView(screenName: screen).catchError((_) {}));
    Analytics.forward = (name, params) => unawaited(FirebaseAnalytics.instance.logEvent(name: name, parameters: params).catchError((_) {}));
    // The signed-in Firebase user wins over the cache (e.g. revoked on another device).
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null && _account != null) await _setAccount(null);
      if (u != null && u.email != null) await _setAccount(AccountInfo(email: u.email!, name: u.displayName ?? '', photo: u.photoURL ?? ''));
    } catch (_) {}
    unawaited(syncTopics());
    unawaited(_initMessaging());
    notifyListeners();
  }

  /// Records a non-fatal error (no-op without Firebase).
  void recordError(Object e, StackTrace? st) {
    if (!ready) return;
    try {
      FirebaseCrashlytics.instance.recordError(e, st);
    } catch (_) {}
  }

  Future<void> _setAccount(AccountInfo? a) async {
    _account = a;
    if (a == null) {
      await Store.I.remove(kAccount);
    } else {
      await Store.I.setString(kAccount, jsonEncode(a.toJson()));
    }
    notifyListeners();
  }

  /// Google sign-in (optional). Returns null on success, or a Hindi message.
  Future<void>? _gInit;

  Future<String?> signIn() async {
    if (busy) return null;
    if (!ready) {
      debugPrint('sign-in: firebase not ready (google-services.json missing from build?)');
      return error = 'लॉगिन अभी उपलब्ध नहीं है (Firebase चालू नहीं)।';
    }
    busy = true;
    error = null;
    _stage('Google से जुड़ रहे हैं…');
    try {
      final g = GoogleSignIn.instance;
      // google_sign_in 7.x: initialize() must be called exactly once per app run.
      await (_gInit ??= g.initialize(serverClientId: kGoogleWebClientId.isEmpty ? null : kGoogleWebClientId).catchError((Object e) {
        _gInit = null;
        throw e;
      }));
      if (!g.supportsAuthenticate()) throw StateError('authenticate-unsupported');
      _stage('Google खाता चुनें…');
      final acc = await g.authenticate();
      _stage('खाता मिला, लॉगिन हो रहा है…');
      final idToken = acc.authentication.idToken;
      if (idToken == null || idToken.isEmpty) throw StateError('no-id-token');
      // signInWithCredential also creates the Firebase user on the first sign-in (sign-up).
      final cred = await FirebaseAuth.instance.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken)).timeout(const Duration(seconds: 30));
      final u = cred.user;
      if (u == null) throw StateError('no-firebase-user');
      await _setAccount(AccountInfo(email: u.email ?? acc.email, name: u.displayName ?? acc.displayName ?? '', photo: u.photoURL ?? acc.photoUrl ?? ''));
      return null;
    } on GoogleSignInException catch (e) {
      debugPrint('google sign-in failed: code=${e.code.name} desc=${e.description}');
      recordError(e, StackTrace.current);
      // Round-2: "canceled" is also what Credential Manager reports when the account was picked
      // but Google refused the token (OAuth client / SHA / consent problems), so it is shown too.
      final desc = (e.description ?? '').trim();
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return error = 'लॉगिन पूरा नहीं हुआ (canceled${desc.isEmpty ? '' : ': $desc'})। दोबारा प्रयास करें।';
      }
      return error = 'Google लॉगिन नहीं हो सका (${e.code.name}${desc.isEmpty ? '' : ': $desc'})। कृपया इंटरनेट जाँचें और दोबारा प्रयास करें।';
    } on FirebaseAuthException catch (e) {
      debugPrint('firebase auth sign-in failed: code=${e.code} msg=${e.message}');
      recordError(e, StackTrace.current);
      return error = 'लॉगिन नहीं हो सका (${e.code})। कृपया दोबारा प्रयास करें।';
    } catch (e) {
      debugPrint('sign-in failed: $e');
      recordError(e, StackTrace.current);
      return error = 'Google लॉगिन नहीं हो सका ($e)।';
    } finally {
      busy = false;
      stage = null;
      notifyListeners();
    }
  }

  void _stage(String s) {
    stage = s;
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      if (ready) {
        await FirebaseAuth.instance.signOut();
        await GoogleSignIn.instance.signOut();
      }
    } catch (_) {}
    await _setAccount(null);
  }

  /// A fresh Firebase ID token (for the server's Firebase verify), or null.
  Future<String?> idToken() async {
    try {
      return ready ? await FirebaseAuth.instance.currentUser?.getIdToken() : null;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------ push topics
  Set<String> get topics {
    final j = _decode(Store.I.getString(kPush));
    if (j is List) {
      return {
        PushTopics.all,
        for (final e in j)
          if (e is String && PushTopics.every.contains(e)) e,
      };
    }
    return {...PushTopics.every};
  }

  bool subscribed(String t) => topics.contains(t);

  Future<void> setTopic(String t, bool on) async {
    final s = topics;
    on ? s.add(t) : s.remove(t);
    await Store.I.setString(kPush, jsonEncode(s.toList()..sort()));
    notifyListeners();
    if (!ready || !RemoteConfig.I.notificationsEnabled) return;
    try {
      if (on) {
        await FirebaseMessaging.instance.requestPermission();
        await FirebaseMessaging.instance.subscribeToTopic(t);
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(t);
      }
    } catch (e) {
      debugPrint('fcm: $t: $e');
    }
  }

  bool? _pushOn;

  /// Subscribes to the chosen topics, or unsubscribes from every topic when
  /// `flags.notifications_enabled === false` (CONTRACT §6.1). Re-run on config change.
  Future<void> syncTopics() async {
    if (!ready) return;
    final on = RemoteConfig.I.notificationsEnabled;
    _pushOn = on;
    try {
      final m = FirebaseMessaging.instance;
      final want = on ? topics : <String>{};
      for (final t in PushTopics.every) {
        want.contains(t) ? await m.subscribeToTopic(t) : await m.unsubscribeFromTopic(t);
      }
    } catch (e) {
      debugPrint('fcm: sync: $e');
    }
  }

  void _onConfig() {
    if (ready && _pushOn != RemoteConfig.I.notificationsEnabled) unawaited(syncTopics());
  }

  /// `data {topic, id?}` → the screen to open (CONTRACT §6.3), or null.
  static String? linkFor(Map<String, dynamic> data) {
    final id = '${data['id'] ?? ''}'.trim();
    if (id.isEmpty || !RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(id)) return null;
    final kind = '${data['kind'] ?? data['type'] ?? ''}';
    if (kind == 'granth') return '#/pramans?granth=$id';
    return switch ('${data['topic'] ?? ''}') {
      PushTopics.newTopic || PushTopics.trending => '#/pramans?topic=$id',
      _ => kind == 'topic' ? '#/pramans?topic=$id' : '#/pramans?id=$id',
    };
  }

  void _openMessage(RemoteMessage m) {
    final l = linkFor(m.data);
    if (l != null) AppNav.I.openLink(l);
  }

  Future<void> _initMessaging() async {
    RemoteConfig.I.addListener(_onConfig);
    try {
      FirebaseMessaging.onMessageOpenedApp.listen(_openMessage);
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n != null && (n.title ?? n.body) != null) Toast.show([n.title, n.body].whereType<String>().join(' · '));
      });
      final first = await FirebaseMessaging.instance.getInitialMessage();
      if (first != null) _openMessage(first);
    } catch (e) {
      debugPrint('fcm: init: $e');
    }
  }

  @visibleForTesting
  Future<void> debugSetAccount(AccountInfo? a) => _setAccount(a);

  /// For tests: a cold start (the account is read again from the saved settings).
  @visibleForTesting
  void debugForgetMemory() => _account = null;
}
