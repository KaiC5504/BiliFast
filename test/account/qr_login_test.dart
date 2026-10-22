import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_page.dart';
import 'package:bilifast/account/qr_login.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import 'fake_web_cookies.dart';

/// Hands out numbered codes and answers polls from [answers] in order (a [WebLoginPoll], or anything else to throw),
/// then "not scanned".
final class FakeQrLoginApi implements QrLoginApi {
  int generates = 0;
  Object? generateError;
  final answers = <Object>[];
  final polled = <String>[];

  /// While set, a poll answers only when the test completes it.
  Completer<WebLoginPoll>? hold;
  int inFlight = 0;
  int mostInFlight = 0;

  @override
  Future<WebLoginQr> generate() async {
    generates += 1;
    if (generateError case final error?) throw error;
    return WebLoginQr(
      url: 'https://passport.bilibili.com/h5-app/passport/login/scan?n=$generates',
      key: 'KEY$generates',
    );
  }

  @override
  Future<WebLoginPoll> poll(String key) async {
    polled.add(key);
    inFlight += 1;
    if (inFlight > mostInFlight) mostInFlight = inFlight;
    try {
      if (hold case final held?) return await held.future;
      final next = answers.isEmpty ? const WebLoginWaiting(scanned: false) : answers.removeAt(0);
      if (next is WebLoginPoll) return next;
      throw next;
    } finally {
      inFlight -= 1;
    }
  }
}

const _session = {'SESSDATA': 'sess%2C1%2Cx%2A1', 'bili_jct': 'jct', 'DedeUserID': '12345'};

final class _Events implements LogSink {
  final List<LogEvent> events = [];

  @override
  void receive(LogEvent event) => events.add(event);

  String get text => events.map((event) => event.encode()).join('\n');
}

void main() {
  group('QrLoginModel', () {
    /// A model over [api], run inside [body] with fake time; [logins] records what [QrLoginModel.didLogin] was handed.
    void run(
      void Function(FakeAsync async, QrLoginModel model, FakeQrLoginApi api, List<Map<String, String>> logins) body, {
      FakeQrLoginApi? api,
      List<bool> loginAnswers = const [true],
      bool checkFailed = false,
      void Function()? onLoggedIn,
      Logger? logger,
    }) {
      fakeAsync((async) {
        final calls = api ?? FakeQrLoginApi();
        final logins = <Map<String, String>>[];
        final answers = List.of(loginAnswers);
        final model = QrLoginModel(
          api: calls,
          didLogin: (cookies) async {
            logins.add(cookies);
            return answers.isEmpty ? false : answers.removeAt(0);
          },
          checkFailed: () => checkFailed,
          onLoggedIn: onLoggedIn ?? () {},
          logger: logger ?? Logger(session: 'test'),
        );
        body(async, model, calls, logins);
        model.dispose();
        async.flushTimers();
      });
    }

    test('one code on open, then a poll of it every 2 s', () {
      run((async, model, api, logins) {
        model.start();
        expect(model.phase, QrLoginPhase.loading);
        async.flushMicrotasks();
        expect(api.generates, 1);
        expect(model.phase, QrLoginPhase.waiting);
        expect(model.url, contains('n=1'));

        async.elapse(const Duration(milliseconds: 1999));
        expect(api.polled, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(api.polled, ['KEY1']);
        async.elapse(const Duration(seconds: 6));
        expect(api.polled, ['KEY1', 'KEY1', 'KEY1', 'KEY1']);

        model.start();
        async.flushMicrotasks();
        expect(api.generates, 1, reason: 'start asks once');
      });
    });

    test('one poll in flight at a time: a slow answer holds the next tick back', () {
      run((async, model, api, logins) {
        // Made inside fake time, so its answer is delivered there.
        api.hold = Completer<WebLoginPoll>();
        model.start();
        async.elapse(const Duration(seconds: 20));
        expect(api.polled, hasLength(1));
        api.hold!.complete(const WebLoginWaiting(scanned: false));
        api.hold = null;
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        expect(api.polled, hasLength(2));
        expect(api.mostInFlight, 1);
      });
    });

    test('86090 reads scanned until the phone confirms', () {
      final api = FakeQrLoginApi()..answers.addAll([const WebLoginWaiting(scanned: true)]);
      run(api: api, (async, model, api, logins) {
        model.start();
        async.elapse(const Duration(seconds: 2));
        expect(model.phase, QrLoginPhase.scanned);
        expect(model.url, isNotNull, reason: 'the code stays up');
        api.answers.add(const WebLoginWaiting(scanned: true));
        async.elapse(const Duration(seconds: 2));
        expect(model.phase, QrLoginPhase.scanned);
      });
    });

    test('after 90 polls the code reads expired and nothing more is sent, not even a new code', () {
      run((async, model, api, logins) {
        model.start();
        async.elapse(const Duration(seconds: 178));
        expect(api.polled, hasLength(89));
        expect(model.phase, QrLoginPhase.waiting);
        async.elapse(const Duration(seconds: 2));
        expect(api.polled, hasLength(QrLoginModel.pollLimit));
        expect(model.phase, QrLoginPhase.expired);
        expect(model.url, isNull);
        async.elapse(const Duration(minutes: 30));
        expect(api.polled, hasLength(90));
        expect(api.generates, 1);
      });
    });

    test('86038 stops the polls and never asks for a new code by itself', () {
      final api = FakeQrLoginApi()..answers.add(const WebLoginExpired());
      run(api: api, (async, model, api, logins) {
        model.start();
        async.elapse(const Duration(seconds: 2));
        expect(model.phase, QrLoginPhase.expired);
        async.elapse(const Duration(minutes: 30));
        expect(api.polled, hasLength(1));
        expect(api.generates, 1);
      });
    });

    test('刷新 asks for one new code, however often it is tapped, and polls it from the start', () {
      final api = FakeQrLoginApi()..answers.add(const WebLoginExpired());
      run(api: api, (async, model, api, logins) {
        model.start();
        async.elapse(const Duration(seconds: 2));
        model
          ..retry()
          ..retry();
        async.flushMicrotasks();
        model.retry();
        expect(api.generates, 2);
        expect(model.phase, QrLoginPhase.waiting);
        expect(model.url, contains('n=2'));
        expect(model.polls, 0);
        async.elapse(const Duration(seconds: 2));
        expect(api.polled, ['KEY1', 'KEY2']);
      });
    });

    test('retry does nothing while a code is up', () {
      run((async, model, api, logins) {
        model.start();
        async.flushMicrotasks();
        model.retry();
        async.elapse(const Duration(seconds: 2));
        expect(api.generates, 1);
        expect(model.phase, QrLoginPhase.waiting);
      });
    });

    test('a failed poll is tried on the next tick; 3 in a row stop the polls at 加载失败, and 重试 starts afresh', () {
      final error = const BiliError.network('SocketException');
      final api = FakeQrLoginApi()..answers.addAll([error, const WebLoginWaiting(scanned: false), error, error]);
      run(api: api, (async, model, api, logins) {
        model.start();
        async.elapse(const Duration(seconds: 8));
        expect(model.phase, QrLoginPhase.waiting, reason: 'a success in between starts the count again');
        api.answers.add(error);
        async.elapse(const Duration(seconds: 2));
        expect(model.phase, QrLoginPhase.failed);
        expect(api.polled, hasLength(5));
        async.elapse(const Duration(minutes: 10));
        expect(api.polled, hasLength(5));
        expect(api.generates, 1);

        model.retry();
        async.flushMicrotasks();
        expect(api.generates, 2);
        expect(model.phase, QrLoginPhase.waiting);
        async.elapse(const Duration(seconds: 2));
        expect(api.polled.last, 'KEY2');
      });
    });

    test('a code that can\'t be had reads 加载失败 and isn\'t asked for again until 重试', () {
      final api = FakeQrLoginApi()..generateError = const BiliError.http(412);
      run(api: api, (async, model, api, logins) {
        model.start();
        async.elapse(const Duration(minutes: 5));
        expect(model.phase, QrLoginPhase.failed);
        expect(api.generates, 1);
        expect(api.polled, isEmpty);

        api.generateError = null;
        model.retry();
        async.flushMicrotasks();
        expect(model.phase, QrLoginPhase.waiting);
      });
    });

    test('a confirmed login hands the session to the account once and says it is logged in', () {
      var loggedIn = 0;
      final api = FakeQrLoginApi()..answers.add(const WebLoginDone(_session));
      run(api: api, onLoggedIn: () => loggedIn += 1, (async, model, api, logins) {
        model.start();
        async.elapse(const Duration(seconds: 2));
        expect(logins, [_session]);
        expect(model.phase, QrLoginPhase.done);
        expect(loggedIn, 1);
        async.elapse(const Duration(minutes: 1));
        expect(api.polled, hasLength(1), reason: 'no poll after the login');
        expect(loggedIn, 1);
      });
    });

    test('a session that doesn\'t log in reads 登录失败, and 重试 asks for a new code', () {
      var loggedIn = 0;
      final api = FakeQrLoginApi()..answers.add(const WebLoginDone(_session));
      run(api: api, loginAnswers: [false], onLoggedIn: () => loggedIn += 1, (async, model, api, logins) {
        model.start();
        async.elapse(const Duration(seconds: 2));
        expect(model.phase, QrLoginPhase.rejected);
        expect(loggedIn, 0);
        async.elapse(const Duration(minutes: 1));
        expect(api.generates, 1);
        model.retry();
        async.flushMicrotasks();
        expect(api.generates, 2);
        expect(logins, hasLength(1));
      });
    });

    test('a check that couldn\'t reach Bilibili asks again with the same session, no new code', () {
      var loggedIn = 0;
      final api = FakeQrLoginApi()..answers.add(const WebLoginDone(_session));
      run(api: api, loginAnswers: [false, true], checkFailed: true, onLoggedIn: () => loggedIn += 1, (
        async,
        model,
        api,
        logins,
      ) {
        model.start();
        async.elapse(const Duration(seconds: 2));
        expect(model.phase, QrLoginPhase.checkFailed);
        model.retry();
        async.flushMicrotasks();
        expect(logins, [_session, _session]);
        expect(api.generates, 1);
        expect(loggedIn, 1);
      });
    });

    test('once disposed nothing more is sent, and an answer on its way is dropped', () {
      fakeAsync((async) {
        final api = FakeQrLoginApi()..hold = Completer<WebLoginPoll>();
        var logins = 0;
        final model = QrLoginModel(
          api: api,
          didLogin: (_) async {
            logins += 1;
            return true;
          },
          onLoggedIn: () {},
          logger: Logger(session: 'test'),
        )..start();
        async.elapse(const Duration(seconds: 2));
        model.dispose();
        api.hold!.complete(const WebLoginDone(_session));
        async.elapse(const Duration(minutes: 1));
        expect(api.polled, hasLength(1));
        expect(logins, 0);
      });
    });

    test('the log names phases and errors, never the code\'s link, its key or the session', () {
      final events = _Events();
      final api = FakeQrLoginApi()
        ..answers.addAll([
          const BiliError.api(code: 86039, message: '其他'),
          const WebLoginWaiting(scanned: true),
          const WebLoginDone(_session),
        ]);
      run(api: api, logger: Logger(session: 'test')..add(events), (async, model, api, logins) {
        model.start();
        async.elapse(const Duration(seconds: 6));
        expect(model.phase, QrLoginPhase.done);
        expect(events.text, contains('scanned'));
        for (final secret in ['KEY1', 'passport.bilibili.com/h5-app', 'sess%2C', 'jct']) {
          expect(events.text, isNot(contains(secret)), reason: secret);
        }
      });
    });
  });

  group('QrLogin', () {
    late AppEnvironment environment;
    late FakeQrLoginApi api;
    late int loggedIn;

    Future<void> show(WidgetTester tester, {CannedHttp? http}) async {
      environment = await AppEnvironment.load(
        keychain: FakeKeychain(const StoredCookies({'buvid3': 'b3', 'buvid4': 'b4'})),
        webCookies: FakeWebCookies(),
        http: http ?? Canned.http(),
        logger: Logger(session: 'test'),
      );
      api = FakeQrLoginApi();
      loggedIn = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QrLogin(environment: environment, api: api, onLoggedIn: () => loggedIn += 1),
          ),
        ),
      );
    }

    Text message(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('qr-login-message')));

    testWidgets('the TV while the code loads, then the code over 请使用哔哩哔哩客户端扫码登录, then 已扫码', (tester) async {
      await show(tester);
      expect(find.byType(LoadingTvState), findsOneWidget);
      await tester.pump();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(tester.getSize(find.byType(QrImageView)), const Size.square(200));
      expect(message(tester).data, '请使用哔哩哔哩客户端扫码登录');
      expect(find.bySemanticsLabel('登录二维码'), findsOneWidget);

      api.answers.add(const WebLoginWaiting(scanned: true));
      await tester.pump(const Duration(seconds: 2));
      expect(message(tester).data, '已扫码，请在手机上确认');
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('二维码已失效 with 刷新; a tap and an accessibility press each bring one new code', (tester) async {
      final semantics = tester.ensureSemantics();
      await show(tester);
      await tester.pump();
      api.answers.add(const WebLoginExpired());
      await tester.pump(const Duration(seconds: 2));
      expect(message(tester).data, '二维码已失效');
      expect(find.byType(QrImageView), findsNothing);
      await tester.pump(const Duration(minutes: 5));
      expect(api.generates, 1);

      await tester.tap(find.byKey(const ValueKey('qr-login-refresh')));
      await tester.pump();
      expect(api.generates, 2);
      expect(find.byType(QrImageView), findsOneWidget);

      api.answers.add(const WebLoginExpired());
      await tester.pump(const Duration(seconds: 2));
      final refresh = tester.getSemantics(find.byKey(const ValueKey('qr-login-refresh')));
      expect(refresh, isSemantics(label: '刷新', isButton: true, hasTapAction: true));
      tester.semantics.tap(find.semantics.byLabel('刷新'));
      await tester.pump();
      expect(api.generates, 3);
      expect(message(tester).data, '请使用哔哩哔哩客户端扫码登录');
      semantics.dispose();
    });

    testWidgets('加载失败 with 重试, pressed through accessibility', (tester) async {
      final semantics = tester.ensureSemantics();
      await show(tester);
      await tester.pump();
      api.answers.addAll(List.filled(3, const BiliError.network('SocketException')));
      await tester.pump(const Duration(seconds: 6));
      expect(message(tester).data, '加载失败');
      final retry = find.byKey(const ValueKey('qr-login-retry'));
      expect(tester.getSemantics(retry), isSemantics(label: '重试', isButton: true, hasTapAction: true));

      api.generateError = const BiliError.http(500);
      final node = tester.getSemantics(retry);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
      expect(api.generates, 2);
      expect(message(tester).data, '加载失败', reason: 'the new code failed too');

      api.generateError = null;
      await tester.tap(retry);
      await tester.pump();
      expect(api.generates, 3);
      expect(find.byType(QrImageView), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a confirmed login logs the account in and says so', (tester) async {
      await show(tester);
      await tester.pump();
      api.answers.add(const WebLoginDone(_session));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(loggedIn, 1);
      expect(environment.account, isA<LoggedIn>());
      expect(environment.cookies.value('SESSDATA'), _session['SESSDATA']);
      expect(environment.cookies.value('buvid3'), 'b3', reason: 'the session joins the jar');
    });

    testWidgets('a session Bilibili doesn\'t take reads 登录失败, and 重试 brings a new code', (tester) async {
      await show(tester, http: Canned.http(loggedIn: false));
      await tester.pump();
      api.answers.add(const WebLoginDone(_session));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('qr-login-signing-in')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(message(tester).data, '登录失败');
      expect(loggedIn, 0);
      await tester.tap(find.byKey(const ValueKey('qr-login-retry')));
      await tester.pump();
      expect(api.generates, 2);
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('a check that couldn\'t reach Bilibili reads 网络错误，请重试, and 重试 asks with the same session', (
      tester,
    ) async {
      final http = Canned.http()..routes[Canned.navPath] = (502, '');
      await show(tester, http: http);
      await tester.pump();
      api.answers.add(const WebLoginDone(_session));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(message(tester).data, '网络错误，请重试');

      http.routes[Canned.navPath] = (200, Canned.navLoggedIn);
      await tester.tap(find.byKey(const ValueKey('qr-login-retry')));
      await tester.pump();
      await tester.pump();
      expect(loggedIn, 1);
      expect(api.generates, 1);
    });
  });

  group('LoginPage on the PC', () {
    const generated =
        '{"code":0,"message":"0","ttl":1,"data":{"url":"https://passport.bilibili.com/h5-app/passport/login/scan?qrcode_key=K","qrcode_key":"K"}}';
    const waiting =
        '{"code":0,"message":"0","data":{"url":"","refresh_token":"","timestamp":0,"code":86101,"message":"未扫码"}}';
    const confirmed =
        '{"code":0,"message":"0","data":{"url":"https://passport.biligame.com/x/passport-login/web/crossDomain?DedeUserID=12345&DedeUserID__ckMd5=ab&SESSDATA=s%2C1%2Cx%2A1&bili_jct=j&gourl=x","refresh_token":"r","timestamp":0,"code":0,"message":""}}';

    testWidgets('the client\'s calls show the code, and a confirmed login pops the page with true', (tester) async {
      final http = Canned.http()
        ..routes['/x/passport-login/web/qrcode/generate'] = (200, generated)
        ..routes['/x/passport-login/web/qrcode/poll'] = (200, waiting);
      final environment = await AppEnvironment.load(
        keychain: FakeKeychain(const StoredCookies({'buvid3': 'b3', 'buvid4': 'b4'})),
        webCookies: FakeWebCookies(),
        http: http,
        logger: Logger(session: 'test'),
      );
      final services = AppServices(
        environment: environment,
        playback: AppPlayback(() => Completer<PlaybackController>().future),
        recents: await RecentStore.load(null, logger: Logger(session: 'test')),
        pageApi: FakePageApi(),
      );
      addTearDown(services.playback.dispose);
      late BuildContext host;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AppScope(services: services, child: child!),
          home: Builder(
            builder: (context) {
              host = context;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      bool? answer;
      unawaited(
        Navigator.of(host).push<bool>(MaterialPageRoute(builder: (_) => const LoginPage())).then((v) => answer = v),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('登录'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(http.to('/x/passport-login/web/qrcode/generate'), hasLength(1));

      await tester.pump(const Duration(seconds: 2));
      expect(http.to('/x/passport-login/web/qrcode/poll'), hasLength(1));
      http.routes['/x/passport-login/web/qrcode/poll'] = (200, confirmed);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
      expect(find.byType(LoginPage), findsNothing);
      expect(environment.account, isA<LoggedIn>());
      expect(environment.cookies.value('SESSDATA'), 's%2C1%2Cx%2A1');
      expect(http.to('/x/passport-login/web/qrcode/poll'), hasLength(2));
    });
  });
}
