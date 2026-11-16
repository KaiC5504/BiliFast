import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/message/chat/chat_page.dart';
import 'package:bilifast/message/fake_message_api.dart';
import 'package:bilifast/message/feed/likes_page.dart';
import 'package:bilifast/message/feed/new_fans_page.dart';
import 'package:bilifast/message/feed/replies_page.dart';
import 'package:bilifast/message/message_model.dart';
import 'package:bilifast/message/message_page.dart';
import 'package:bilifast/message/session_row.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../home/fake_login_gate.dart';
import '../playback/fakes.dart';
import '../video/mixed_lines.dart' show appTheme;

/// 消息's model with its answers set by the test: [refresh] waits on [hold] when set, then shows [next] or fails with
/// [nextFailure]; every call is listed in [calls].
class _Messages extends MessageModel {
  _Messages({required super.environment, List<ChatSession> sessions = const [], this.counts = const MessageUnread()})
    : list = [...sessions],
      super(api: FakeMessageApi());

  final List<ChatSession> list;
  MessageUnread counts;
  bool on = true;
  bool firstLoading = false;
  bool more = false;
  Object? failure;
  final calls = <String>[];
  Completer<void>? hold;
  Completer<void>? moreHold;
  Completer<void>? readAllHold;
  List<ChatSession>? next;
  Object? nextFailure;
  Object? readAllFailure;

  @override
  MessageUnread get unread => counts;

  @override
  bool get badgeOn => on;

  @override
  int get badge => on ? counts.total : 0;

  @override
  List<ChatSession> get sessions => List.unmodifiable(list);

  @override
  bool get loading => firstLoading;

  @override
  bool get hasMore => more;

  @override
  Object? get error => failure;

  @override
  Future<void> refreshUnread({bool force = false}) async => calls.add('unread force=$force');

  @override
  Future<bool> refresh() async {
    calls.add('refresh');
    if (list.isEmpty) {
      firstLoading = true;
      notifyListeners();
    }
    await hold?.future;
    firstLoading = false;
    failure = nextFailure;
    if (next case final sessions? when failure == null) {
      list
        ..clear()
        ..addAll(sessions);
    }
    notifyListeners();
    return true;
  }

  @override
  Future<void> loadMore() async {
    calls.add('more');
    await moreHold?.future;
    more = false;
    notifyListeners();
  }

  @override
  void feedOpened(NoticeFeed feed) => calls.add('opened ${feed.name}');

  @override
  Future<void> readAll() async {
    calls.add('readAll');
    await readAllHold?.future;
    if (readAllFailure case final failure?) throw failure;
  }
}

/// Logs in as the login page would: Bilibili's nav answers logged in from now on, and the environment takes the new
/// cookies through didLogin's account check.
final class _LoggingIn implements LoginGate {
  _LoggingIn(this.environment, this.http);

  final AppEnvironment environment;
  final CannedHttp http;
  int requests = 0;

  @override
  Future<bool> request(BuildContext context) async {
    requests++;
    http.routes[Canned.navPath] = (200, Canned.navLoggedIn);
    return environment.didLogin(const {'SESSDATA': 's2'});
  }
}

/// [count] people, newest first, a minute apart.
List<ChatSession> _people(int count) => [
  for (var id = 1; id <= count; id++)
    ChatSession(
      talkerId: id,
      name: '演示用户$id',
      face: '',
      lastText: '演示消息$id',
      time: DateTime(2026, 11, 10, 8).subtract(Duration(minutes: id)),
    ),
];

ChatSession _session(int id, {int unread = 0, NoticeBox? box}) => ChatSession(
  talkerId: id,
  box: box,
  name: box?.label ?? '演示用户$id',
  face: '',
  lastText: '演示消息$id',
  time: DateTime(2026, 11, 10, 8),
  unread: unread,
);

List<ChatSession> _sessions(int count) => [for (var id = 1; id <= count; id++) _session(id)];

Finder _key(String key) => find.byKey(ValueKey(key));

class _Clock {
  DateTime now = DateTime(2026, 11, 16, 9, 55);
}

void main() {
  late _Clock clock;
  late FakeLoginGate gate;

  setUp(() {
    clock = _Clock();
    gate = FakeLoginGate();
  });

  /// 消息 on a 440×956 screen under a 62 pt status bar, its model built over the environment by [model] (a [_Messages]
  /// unless given); [active] toggles the page's place being shown. [checked] false leaves the launch's account check
  /// to the test; [loginGate] stands for the login page in place of [gate].
  Future<(M, ValueNotifier<bool>, ChangeNotifier)> show<M extends MessageModel>(
    WidgetTester tester, {
    bool loggedIn = true,
    bool active = true,
    bool checked = true,
    M Function(AppEnvironment environment)? model,
    LoginGate Function(AppEnvironment environment, CannedHttp http)? loginGate,
  }) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34)
      ..viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    final http = Canned.http(loggedIn: loggedIn);
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    if (checked) await environment.refreshAccount();
    final playback = AppPlayback(() async => throw UnimplementedError());
    addTearDown(playback.dispose);
    final messages = model?.call(environment) ?? _Messages(environment: environment) as M;
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      loginGate: loginGate?.call(environment, http) ?? gate,
      messageApi: FakeMessageApi(),
      messages: messages,
    );
    final shown = ValueNotifier(active);
    final reloads = ChangeNotifier();
    addTearDown(shown.dispose);
    addTearDown(reloads.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => AppScope(services: services, child: child!),
        home: ValueListenableBuilder<bool>(
          valueListenable: shown,
          builder: (context, active, _) => MessagePage(active: active, reloads: reloads, clock: () => clock.now),
        ),
      ),
    );
    await settle(tester);
    return (messages, shown, reloads);
  }

  /// The app's own model over [api], for what a stand-in would hide.
  MessageModel real(FakeMessageApi api, AppEnvironment environment) {
    final model = MessageModel(api: api, environment: environment);
    addTearDown(model.dispose);
    return model;
  }

  void backToApp(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  testWidgets('the header: white under the status bar, 消息 centred on its 44 pt row, the broom and ⋮ at the right', (
    tester,
  ) async {
    await show(tester);
    expect(tester.getRect(_key('message-header')), const Rect.fromLTWH(0, 0, 440, 62 + MessageTabTheme.barRow));
    expect(tester.getCenter(find.text('消息')).dx, 220);
    expect(
      tester.getCenter(find.text('消息')).dy,
      moreOrLessEquals(62 + MessageTabTheme.barRow / 2 + MessageTabTheme.titleDrop, epsilon: 0.01),
    );
    expect(tester.getCenter(_key('message-read-all-button')).dx, 440 - MessageTabTheme.broomCentreRight);
    expect(tester.getCenter(_key('message-more-button')).dx, 440 - MessageTabTheme.moreCentreRight);
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(region.value, SystemUiOverlayStyle.dark);
  });

  testWidgets('shown, it asks the counts at once and the list the first time; again within a minute only the counts, '
      'after a minute the list too; hidden, nothing', (tester) async {
    final (model, shown, _) = await show(tester, active: false, model: (e) => _Messages(environment: e));
    expect(model.calls, isEmpty);
    expect(find.byType(LoadingTvState), findsNothing, reason: 'nothing drawn before it shows');

    shown.value = true;
    await settle(tester);
    expect(model.calls, ['unread force=true', 'refresh']);

    shown.value = false;
    await settle(tester);
    clock.now = clock.now.add(const Duration(seconds: 50));
    shown.value = true;
    await settle(tester);
    expect(model.calls, ['unread force=true', 'refresh', 'unread force=true']);

    shown.value = false;
    await settle(tester);
    clock.now = clock.now.add(const Duration(seconds: 20));
    shown.value = true;
    await settle(tester);
    expect(model.calls, ['unread force=true', 'refresh', 'unread force=true', 'unread force=true', 'refresh']);
  });

  testWidgets('the entries: three squares 127.33 apart under the header with their labels, then the list', (
    tester,
  ) async {
    await show(
      tester,
      model: (e) => _Messages(environment: e, sessions: _sessions(3)),
    );
    const top = 62 + MessageTabTheme.barRow;
    for (final (i, name) in ['replies', 'likes', 'fans'].indexed) {
      final entry = tester.getRect(_key('message-entry-$name'));
      expect(entry.center.dx, moreOrLessEquals(220 + (i - 1) * MessageTabTheme.entryPitch, epsilon: 0.01));
      final square = tester.getRect(
        find.descendant(of: _key('message-entry-$name'), matching: find.byType(DecoratedBox)).first,
      );
      expect(square.top, top + MessageTabTheme.entryTop);
      expect(square.size, const Size.square(MessageTabTheme.entrySquare));
    }
    expect(find.text('回复与@'), findsOneWidget);
    expect(find.text('收到喜欢'), findsOneWidget);
    expect(find.text('新增粉丝'), findsOneWidget);
    const squareBottom = top + MessageTabTheme.entryTop + MessageTabTheme.entrySquare;
    expect(
      tester.getCenter(find.text('收到喜欢')).dy,
      moreOrLessEquals(squareBottom + MessageTabTheme.entryLabelCentre, epsilon: 0.01),
    );
    // 196's label ink is centred 13.83 under the squares, a third of a point under its line box.
    expect(MessageTabTheme.entryLabelCentre + 1 / 3, moreOrLessEquals(13.83, epsilon: 0.01));
    expect(tester.getTopLeft(_key('message-session-1')).dy, moreOrLessEquals(top + MessageTabTheme.entries));
  });

  testWidgets('回复与@ counts replies and @s, 收到喜欢 likes, 新增粉丝 nothing; none with 消息提醒 off', (tester) async {
    final (model, _, _) = await show(
      tester,
      model: (e) => _Messages(environment: e, counts: const MessageUnread(reply: 2, at: 3, like: 120, chat: 4)),
    );
    expect(find.descendant(of: _key('message-entry-count-replies'), matching: find.text('5')), findsOneWidget);
    expect(find.descendant(of: _key('message-entry-count-likes'), matching: find.text('99+')), findsOneWidget);
    expect(_key('message-entry-count-fans'), findsNothing);
    final square = tester.getRect(
      find.descendant(of: _key('message-entry-replies'), matching: find.byType(DecoratedBox)).first,
    );
    expect(tester.getCenter(_key('message-entry-count-replies')), square.topRight);

    model
      ..on = false
      ..notifyListeners();
    await settle(tester);
    expect(find.byType(TabCount), findsNothing);
  });

  testWidgets('the entries clear their counts and open 回复与@, 收到喜欢 and 新增粉丝', (tester) async {
    final (model, _, _) = await show<_Messages>(tester);
    await tester.tap(_key('message-entry-replies'));
    await settle(tester);
    expect(find.byType(RepliesPage), findsOneWidget);
    expect(tester.widget<RepliesPage>(find.byType(RepliesPage)).mentions, isFalse);
    Navigator.of(tester.element(find.byType(RepliesPage))).pop();
    await settle(tester);

    await tester.tap(_key('message-entry-likes'));
    await settle(tester);
    expect(find.byType(LikesPage), findsOneWidget);
    Navigator.of(tester.element(find.byType(LikesPage))).pop();
    await settle(tester);

    await tester.tap(_key('message-entry-fans'));
    await settle(tester);
    expect(find.byType(NewFansPage), findsOneWidget);
    expect(model.calls.where((call) => call.startsWith('opened')), ['opened reply', 'opened like']);
  });

  testWidgets('the first load shows the TV, then the rows; a session opens its chat', (tester) async {
    final hold = Completer<void>();
    final (model, _, _) = await show(
      tester,
      model: (e) => _Messages(environment: e)
        ..hold = hold
        ..next = [_session(1, unread: 2), _session(2, box: NoticeBox.service)],
    );
    expect(find.byType(LoadingTvState), findsOneWidget);
    expect(find.byType(SessionRow), findsNothing);

    hold.complete();
    await settle(tester);
    expect(find.byType(LoadingTvState), findsNothing);
    expect(find.byType(SessionRow), findsNWidgets(2));
    expect(find.text('演示用户1'), findsOneWidget);
    expect(find.text('服务通知'), findsOneWidget);

    await tester.tap(_key('message-session-1'));
    await settle(tester);
    expect(tester.widget<ChatPage>(find.byType(ChatPage)).session, model.sessions.first);
    expect(model.calls, isNot(contains('chat')), reason: 'the chat page acks it');
  });

  testWidgets('a failed first load says why with 重试, which asks again; an empty list shows the empty picture', (
    tester,
  ) async {
    final (model, _, _) = await show(
      tester,
      model: (e) => _Messages(environment: e)..nextFailure = const BiliError.api(code: -500, message: '服务器错误'),
    );
    expect(_key('message-failed'), findsOneWidget);
    expect(find.text('B 站返回错误 -500：服务器错误'), findsOneWidget);

    model
      ..nextFailure = null
      ..next = [];
    await tester.tap(_key('message-retry'));
    await settle(tester);
    expect(model.calls.where((call) => call == 'refresh'), hasLength(2));
    expect(_key('message-failed'), findsNothing);
    expect(_key('message-empty'), findsOneWidget);
    expect(find.text('这里还什么都没有呢～'), findsOneWidget);
  });

  testWidgets('a pull past the TV refreshes when the finger lets go', (tester) async {
    final (model, _, _) = await show(
      tester,
      model: (e) => _Messages(environment: e, sessions: _sessions(3)),
    );
    expect(model.calls.where((call) => call == 'refresh'), hasLength(1));
    final gesture = await tester.startGesture(tester.getCenter(_key('message-session-1')));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(model.calls.where((call) => call == 'refresh'), hasLength(1), reason: 'nothing while held');
    await gesture.up();
    await settle(tester, 30);
    expect(model.calls.where((call) => call == 'refresh'), hasLength(2));
  });

  testWidgets('near the end the next page is asked once, the small spinner under the rows meanwhile', (tester) async {
    final (model, _, _) = await show(
      tester,
      model: (e) => _Messages(environment: e, sessions: _sessions(30))..more = true,
    );
    expect(model.calls, isNot(contains('more')), reason: 'the end is screens away');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
    await settle(tester);
    expect(model.calls.where((call) => call == 'more'), hasLength(1));
    expect(model.hasMore, isFalse);
    expect(_key('message-more'), findsNothing, reason: 'no spinner past the end');
  });

  testWidgets('while more are left the footer spins; a failed page says why', (tester) async {
    final (model, _, _) = await show(
      tester,
      model: (e) => _Messages(environment: e, sessions: _sessions(2))
        ..more = true
        ..moreHold = Completer<void>()
        ..next = _sessions(2),
    );
    expect(model.calls.last, 'more', reason: 'the end is on screen');
    expect(_key('message-more'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

    model
      ..failure = const BiliError.api(code: -500, message: '服务器错误')
      ..notifyListeners();
    await settle(tester);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.text('B 站返回错误 -500：服务器错误，点击重试'), findsOneWidget);
  });

  testWidgets('点击重试 under the rows asks the failed next page again, or the first page when that failed', (
    tester,
  ) async {
    final api = FakeMessageApi(sessionList: _people(60), pageSize: 40);
    final (model, _, _) = await show(tester, model: (e) => real(api, e));
    expect(find.byType(SessionRow), findsWidgets);
    api.failures['sessions'] = const BiliError.api(code: -500, message: '服务器错误');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2400));
    await settle(tester);
    expect(api.calls.last, startsWith('sessions '), reason: 'the next page');
    expect(api.calls.last, isNot('sessions 0'));
    expect(model.nextPageFailed, isTrue);
    expect(_key('message-footer-retry'), findsOneWidget);

    api.failures.remove('sessions');
    final asked = api.calls.length;
    await tester.tap(_key('message-footer-retry'));
    await settle(tester);
    expect(api.calls.sublist(asked), [isNot('sessions 0')]);
    expect(model.sessions, hasLength(60));
    expect(model.error, isNull);

    // A pull that failed over the rows: the footer's retry asks the first page.
    api.failures['sessions'] = const BiliError.api(code: -500, message: '服务器错误');
    await model.refresh();
    await settle(tester);
    expect(model.nextPageFailed, isFalse);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
    await settle(tester);
    api.failures.remove('sessions');
    final again = api.calls.length;
    await tester.tap(_key('message-footer-retry'));
    await settle(tester);
    expect(api.calls.sublist(again), containsAll(['unread', 'sessions 0']));
    expect(model.error, isNull);
  });

  testWidgets('消息 tapped again goes back to the top and refreshes with the TV held there', (tester) async {
    final (model, _, reloads) = await show(
      tester,
      model: (e) => _Messages(environment: e, sessions: _sessions(30))..next = _sessions(30),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
    await settle(tester);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(scroll.pixels, greaterThan(0));

    final hold = model.hold = Completer<void>();
    reloads.notifyListeners();
    await settle(tester, 12);
    expect(scroll.pixels, 0);
    expect(_key('message-reload'), findsOneWidget);
    expect(model.calls.where((call) => call == 'refresh'), hasLength(2));

    hold.complete();
    await settle(tester, 12);
    expect(_key('message-reload'), findsNothing);
  });

  testWidgets('logged out: the login message under the header, 登录 through the login gate; nothing asked', (
    tester,
  ) async {
    final (model, _, _) = await show<_Messages>(tester, loggedIn: false);
    expect(_key('message-logged-out'), findsOneWidget);
    expect(find.text('登录后查看消息'), findsOneWidget);
    expect(_key('message-entry-replies'), findsNothing);
    expect(model.calls, isEmpty);

    await tester.tap(_key('message-login'));
    await settle(tester);
    expect(gate.requests, 1);

    await tester.tap(_key('message-read-all-button'));
    await settle(tester);
    expect(gate.requests, 2, reason: '一键已读 asks for the login too');
    expect(find.text('一键已读'), findsNothing);
  });

  testWidgets('a -101 with nothing shown asks for the login as logged out does', (tester) async {
    await show(
      tester,
      model: (e) => _Messages(environment: e)..nextFailure = const BiliError.api(code: -101, message: '账号未登录'),
    );
    expect(_key('message-logged-out'), findsOneWidget);
  });

  testWidgets('the broom asks 一键已读 first: 清除 reads all, 取消 doesn\'t', (tester) async {
    final (model, _, _) = await show(
      tester,
      model: (e) => _Messages(environment: e, sessions: _sessions(2)),
    );
    await tester.tap(_key('message-read-all-button'));
    await settle(tester);
    expect(find.text('是否清除全部新消息提醒？'), findsOneWidget);
    await tester.tap(_key('message-read-all-取消'));
    await settle(tester);
    expect(find.text('是否清除全部新消息提醒？'), findsNothing);
    expect(model.calls, isNot(contains('readAll')));

    await tester.tap(_key('message-read-all-button'));
    await settle(tester);
    await tester.tap(_key('message-read-all-清除'));
    await settle(tester);
    expect(model.calls.last, 'readAll');
    expect(find.text('B 站返回错误 -500：服务器错误'), findsNothing);
  });

  testWidgets('一键已读 that fails says why', (tester) async {
    final (model, _, _) = await show(
      tester,
      model: (e) =>
          _Messages(environment: e, sessions: _sessions(2))
            ..readAllFailure = const BiliError.api(code: -500, message: '服务器错误'),
    );
    await tester.tap(_key('message-read-all-button'));
    await settle(tester);
    await tester.tap(_key('message-read-all-清除'));
    await tester.pump();
    await tester.pump();
    expect(model.calls.last, 'readAll');
    expect(find.text('B 站返回错误 -500：服务器错误'), findsOneWidget);
    await settle(tester, 60);
  });

  testWidgets('一键已读\'s failure is the model\'s to log: the page logs nothing of its own', (tester) async {
    final sink = MemorySink();
    Logger.shared.add(sink);
    addTearDown(() => Logger.shared.remove(sink));
    await show(
      tester,
      model: (e) =>
          _Messages(environment: e, sessions: _sessions(2))
            ..readAllFailure = const BiliError.api(code: -500, message: '服务器错误'),
    );
    await tester.tap(_key('message-read-all-button'));
    await settle(tester);
    await tester.tap(_key('message-read-all-清除'));
    await settle(tester, 60);
    expect(sink.events.where((event) => '${event.toJson()}'.contains('read all failed')), isEmpty);
  });

  testWidgets('while 一键已读 is out the broom does nothing; once answered it asks again', (tester) async {
    final hold = Completer<void>();
    final (model, _, _) = await show(
      tester,
      model: (e) => _Messages(environment: e, sessions: _sessions(2))..readAllHold = hold,
    );
    await tester.tap(_key('message-read-all-button'));
    await settle(tester);
    await tester.tap(_key('message-read-all-清除'));
    await settle(tester);
    await tester.tap(_key('message-read-all-button'));
    await settle(tester);
    expect(find.text('是否清除全部新消息提醒？'), findsNothing);
    expect(model.calls.where((call) => call == 'readAll'), hasLength(1));

    hold.complete();
    await settle(tester);
    await tester.tap(_key('message-read-all-button'));
    await settle(tester);
    expect(find.text('是否清除全部新消息提醒？'), findsOneWidget);
  });

  testWidgets('一键已读 refused with -101 asks for the login, no toast', (tester) async {
    await show(
      tester,
      model: (e) =>
          _Messages(environment: e, sessions: _sessions(2))
            ..readAllFailure = const BiliError.api(code: -101, message: '账号未登录'),
    );
    await tester.tap(_key('message-read-all-button'));
    await settle(tester);
    await tester.tap(_key('message-read-all-清除'));
    await settle(tester);
    expect(gate.requests, 1);
    expect(find.text('需要登录'), findsNothing);
  });

  testWidgets('a pull refused with -101 over rows already shown asks for the login, no toast', (tester) async {
    final (model, _, _) = await show(
      tester,
      model: (e) => _Messages(environment: e, sessions: _sessions(3)),
    );
    model.nextFailure = const BiliError.api(code: -101, message: '账号未登录');
    final gesture = await tester.startGesture(tester.getCenter(_key('message-session-1')));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester, 30);
    expect(model.calls.where((call) => call == 'refresh'), hasLength(2));
    expect(gate.requests, 1);
    expect(find.text('需要登录'), findsNothing);
  });

  testWidgets('⋮ while logged out asks for the login instead of opening its sheet', (tester) async {
    await show(tester, loggedIn: false);
    await tester.tap(_key('message-more-button'));
    await settle(tester);
    expect(gate.requests, 1);
    expect(_key('message-sheet'), findsNothing);
  });

  testWidgets('logging in from 消息\'s 登录 loads the list once the account reads logged in', (tester) async {
    final api = FakeMessageApi(sessionList: _people(3));
    late _LoggingIn login;
    await show(
      tester,
      loggedIn: false,
      model: (e) => real(api, e),
      loginGate: (environment, http) => login = _LoggingIn(environment, http),
    );
    expect(_key('message-logged-out'), findsOneWidget);
    expect(api.calls, isEmpty);

    await tester.tap(_key('message-login'));
    await settle(tester);
    expect(login.requests, 1);
    expect(api.calls, containsAll(['unread', 'sessions 0']));
    expect(find.byType(SessionRow), findsNWidgets(3));
    expect(_key('message-empty'), findsNothing);
  });

  testWidgets('opened while the launch\'s account check is out, 消息 shows the TV and loads once it reads logged in', (
    tester,
  ) async {
    final api = FakeMessageApi(sessionList: _people(3));
    late AppEnvironment environment;
    await show(tester, checked: false, model: (e) => real(api, environment = e));
    expect(environment.account, isA<AccountUnknown>());
    expect(find.byType(LoadingTvState), findsOneWidget);
    expect(api.calls, isEmpty);

    await environment.refreshAccount();
    await settle(tester);
    expect(api.calls, containsAll(['unread', 'sessions 0']));
    expect(find.byType(SessionRow), findsNWidgets(3));
  });

  testWidgets('a show request while 消息 is shown checks again, the list whatever its age; one while hidden asks the '
      'list as it shows', (tester) async {
    final (model, shown, _) = await show(
      tester,
      model: (e) => _Messages(environment: e, sessions: _sessions(2)),
    );
    expect(model.calls, ['unread force=true', 'refresh']);
    model.requestShow();
    await settle(tester);
    expect(model.calls, ['unread force=true', 'refresh', 'unread force=true', 'refresh']);

    model.calls.clear();
    shown.value = false;
    await settle(tester);
    model.requestShow();
    clock.now = clock.now.add(const Duration(seconds: 20));
    shown.value = true;
    await settle(tester);
    expect(model.calls, ['unread force=true', 'refresh']);
  });

  testWidgets('a return to the app with 消息 on screen asks the counts, and the list once it is over a minute old; '
      'hidden or covered, nothing', (tester) async {
    final (model, shown, _) = await show(
      tester,
      model: (e) => _Messages(environment: e, sessions: _sessions(2)),
    );
    model.calls.clear();
    backToApp(tester);
    await settle(tester);
    expect(model.calls, ['unread force=true']);

    clock.now = clock.now.add(const Duration(minutes: 2));
    backToApp(tester);
    await settle(tester);
    expect(model.calls, ['unread force=true', 'unread force=true', 'refresh']);

    model.calls.clear();
    final navigator = Navigator.of(tester.element(find.byType(MessagePage)));
    unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => const SizedBox())));
    await settle(tester);
    clock.now = clock.now.add(const Duration(minutes: 2));
    backToApp(tester);
    await settle(tester);
    expect(model.calls, isEmpty, reason: 'covered');

    navigator.pop();
    await settle(tester);
    shown.value = false;
    await settle(tester);
    backToApp(tester);
    await settle(tester);
    expect(model.calls, isEmpty, reason: 'hidden');
  });
}

Future<void> settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
