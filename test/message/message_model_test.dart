import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/message/fake_message_api.dart';
import 'package:bilifast/message/message_model.dart';
import 'package:bilifast/message/message_prefs.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The account half [MessageModel] follows: the test sets the account and counts the logins.
class _Environment extends ChangeNotifier implements AppEnvironment {
  _Environment(this._account);

  Account _account;

  @override
  Account get account => _account;

  set account(Account value) {
    _account = value;
    notifyListeners();
  }

  @override
  final ValueNotifier<int> logins = ValueNotifier(0);

  /// As didLogin goes: through unknown to logged in, then the login counted.
  void logIn() {
    account = const AccountUnknown();
    account = loggedIn;
    logins.value++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const loggedIn = LoggedIn(name: '测试账号', vip: false);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final demoTime = DateTime(2026, 11, 16, 12);

  late FakeMessageApi api;
  late _Environment environment;
  late DateTime clock;
  late MemorySink sink;
  late Logger logger;

  setUp(() {
    api = FakeMessageApi.demo(now: demoTime, pageSize: 4);
    clock = DateTime(2026, 11, 16, 12);
    sink = MemorySink();
    logger = Logger(session: 'test')..add(sink);
  });

  MessageModel make({Account account = loggedIn, MessagePrefs? prefs}) {
    environment = _Environment(account);
    final model = MessageModel(api: api, environment: environment, prefs: prefs, now: () => clock, logger: logger);
    addTearDown(model.dispose);
    return model;
  }

  Future<void> idle() => pumpEventQueue();

  String logged() => sink.events.map((event) => '${event.toJson()}').join();

  void backToApp() {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      binding.handleAppLifecycleStateChanged(state);
    }
  }

  int countOf(String call) => api.calls.where((each) => each == call).length;

  group('counts', () {
    test('logged in, start asks them once, and the badge is their total; start again asks nothing', () async {
      final model = make();
      expect(api.calls, isEmpty, reason: 'nothing before start');
      model.start();
      await idle();
      expect(api.calls, ['unread']);
      expect(model.unread, const MessageUnread(reply: 2, at: 1, like: 1, chat: 3));
      expect(model.badge, 7);

      model.start();
      await idle();
      expect(api.calls, ['unread']);
    });

    test('logged out, nothing is asked, by start, a return or a refresh', () async {
      final model = make(account: const LoggedOut());
      model.start();
      clock = clock.add(const Duration(minutes: 5));
      backToApp();
      await model.refresh();
      await model.refreshUnread(force: true);
      await model.loadMore();
      await idle();
      expect(api.calls, isEmpty);
      expect(model.badge, 0);
    });

    test('at launch the account is unknown: the counts wait for it to read logged in', () async {
      final model = make(account: const AccountUnknown());
      model.start();
      await idle();
      expect(api.calls, isEmpty);
      environment.account = loggedIn;
      await idle();
      expect(api.calls, ['unread']);
      environment.account = loggedIn;
      await idle();
      expect(api.calls, ['unread'], reason: 'the same account checked again asks nothing');
    });

    test('a login asks them once', () async {
      final model = make(account: const LoggedOut());
      model.start();
      environment.logIn();
      await idle();
      expect(api.calls, ['unread']);
      expect(model.badge, 7);
    });

    test('a return to the app asks again at most once a minute', () async {
      final model = make();
      model.start();
      await idle();
      clock = clock.add(const Duration(seconds: 30));
      backToApp();
      await idle();
      expect(countOf('unread'), 1, reason: 'within the minute');

      clock = clock.add(const Duration(seconds: 31));
      backToApp();
      await idle();
      expect(countOf('unread'), 2);
      backToApp();
      await idle();
      expect(countOf('unread'), 2);
      expect(model.badge, 7);
    });

    test('refreshUnread keeps the minute unless forced', () async {
      final model = make();
      model.start();
      await idle();
      await model.refreshUnread();
      expect(countOf('unread'), 1);
      await model.refreshUnread(force: true);
      expect(countOf('unread'), 2);
    });

    test('a count call out answers for the next', () async {
      final model = make();
      final hold = api.holds['unread'] = Completer<void>();
      model.start();
      final forced = model.refreshUnread(force: true);
      await idle();
      expect(countOf('unread'), 1);
      hold.complete();
      await forced;
      expect(model.badge, 7);
    });

    test('a failed count is logged by kind and code, the counts kept', () async {
      final model = make();
      model.start();
      await idle();
      api.failures['unread'] = const BiliAPIError(code: -352, message: '演示：风控的原话');
      await model.refreshUnread(force: true);
      expect(model.badge, 7);
      expect(logged(), contains('message unread failed'));
      expect(logged(), contains('api -352'));
      expect(logged(), isNot(contains('风控的原话')));
    });
  });

  group('the account', () {
    test('a logout clears the counts and sessions, says so, and drops an answer still out', () async {
      final model = make();
      model.start();
      await model.refresh();
      expect(model.sessions, isNotEmpty);
      final hold = api.holds['unread'] = Completer<void>();
      unawaited(model.refreshUnread(force: true));
      var notified = 0;
      model.addListener(() => notified++);

      environment.account = const LoggedOut();
      expect(notified, greaterThan(0));
      expect(model.unread, const MessageUnread());
      expect(model.sessions, isEmpty);
      expect(model.hasMore, isFalse);
      expect(model.badge, 0);

      hold.complete();
      await idle();
      expect(model.unread, const MessageUnread(), reason: 'the old account\'s answer is dropped');
    });

    test('an expired login clears them too', () async {
      final model = make();
      model.start();
      await model.refresh();
      environment.account = const LoginExpired();
      expect(model.unread, const MessageUnread());
      expect(model.sessions, isEmpty);
    });

    test('a login over a logged-in account, maybe another one, starts the counts and list again', () async {
      final model = make();
      model.start();
      await model.refresh();
      expect(api.calls, ['unread', 'sessions 0'], reason: 'the pull joins the launch\'s count call');
      api.calls.clear();

      environment.logIn();
      await idle();
      expect(api.calls, unorderedEquals(['unread', 'sessions 0']), reason: 'once each, not once per change');
      expect(model.sessions, hasLength(4));
    });

    test('logging in again after a logout asks the counts and, once 消息 has shown, its list', () async {
      final model = make();
      model.start();
      await model.refresh();
      environment.account = const LoggedOut();
      api.calls.clear();
      environment.logIn();
      await idle();
      expect(api.calls, unorderedEquals(['unread', 'sessions 0']));
    });

    test('the badge hides while the account is unknown', () async {
      final model = make();
      model.start();
      await idle();
      environment.account = const AccountUnknown();
      expect(model.badge, 0);
      environment.account = loggedIn;
      expect(model.badge, 7);
    });
  });

  group('sessions', () {
    test('refresh asks the first page and the counts; loadMore the next until the end', () async {
      final model = make();
      expect(model.hasMore, isFalse);
      await model.refresh();
      expect(api.calls, ['unread', 'sessions 0']);
      expect(model.sessions, hasLength(4));
      expect(model.sessions.first.talkerId, 501, reason: 'newest first');
      expect(model.hasMore, isTrue);

      await model.loadMore();
      expect(model.sessions, hasLength(8));
      await model.loadMore();
      expect(model.sessions, hasLength(10));
      expect(model.hasMore, isFalse);
      await model.loadMore();
      expect(api.calls.where((call) => call.startsWith('sessions')), hasLength(3));
      expect(model.sessions.map((session) => session.talkerId).toSet(), hasLength(10));
    });

    test('loading is the first page being out', () async {
      final model = make();
      final hold = api.holds['sessions'] = Completer<void>();
      final refreshed = model.refresh();
      await idle();
      expect(model.loading, isTrue);
      hold.complete();
      await refreshed;
      expect(model.loading, isFalse);
    });

    test('one session call is out at a time', () async {
      final model = make();
      var hold = api.holds['sessions'] = Completer<void>();
      final first = model.refresh();
      final again = model.refresh();
      final more = model.loadMore();
      await idle();
      expect(countOf('sessions 0'), 1, reason: 'a refresh and a next page join the first page out');
      hold.complete();
      await Future.wait([first, again, more]);
      expect(model.sessions, hasLength(4));

      hold = api.holds['sessions'] = Completer<void>();
      final next = model.loadMore();
      final pulled = model.refresh();
      await idle();
      expect(api.calls.where((call) => call.startsWith('sessions')), hasLength(2), reason: 'the pull waits');
      hold.complete();
      await Future.wait([next, pulled]);
      expect(api.calls.where((call) => call.startsWith('sessions')).last, 'sessions 0');
      expect(model.sessions, hasLength(4), reason: 'the pull starts the list again');
    });

    test('a failure is kept and logged by kind and code; loadMore waits for a refresh that works', () async {
      final model = make();
      await model.refresh();
      api.failures['sessions'] = const BiliAPIError(code: -412, message: '演示：原话不该进日志');
      await model.loadMore();
      expect(model.error, isA<BiliAPIError>());
      expect(model.sessions, hasLength(4), reason: 'what showed stays');
      expect(logged(), contains('message sessions failed'));
      expect(logged(), contains('api -412'));
      expect(logged(), isNot(contains('原话')));

      await model.loadMore();
      expect(api.calls.where((call) => call.startsWith('sessions')), hasLength(2), reason: 'no asking on and on');

      api.failures.remove('sessions');
      await model.refresh();
      expect(model.error, isNull);
      await model.loadMore();
      expect(model.sessions, hasLength(8));
    });
  });

  group('reading', () {
    test('回复与@ zeroes reply and @, 收到喜欢 zeroes likes, asking nothing', () async {
      final model = make();
      model.start();
      await idle();
      model.feedOpened(NoticeFeed.reply);
      expect(model.unread, const MessageUnread(like: 1, chat: 3));
      model.feedOpened(NoticeFeed.like);
      expect(model.unread, const MessageUnread(chat: 3));
      expect(model.badge, 3);
      expect(api.calls, ['unread']);
    });

    test('@我 counts as 回复与@ too', () async {
      final model = make();
      model.start();
      await idle();
      model.feedOpened(NoticeFeed.at);
      expect(model.unread, const MessageUnread(like: 1, chat: 3));
    });

    test('a count asked before a list was opened doesn\'t bring that count back', () async {
      final model = make();
      final hold = api.holds['unread'] = Completer<void>();
      model.start();
      await idle();
      model.feedOpened(NoticeFeed.reply);
      hold.complete();
      await idle();
      expect(model.unread, const MessageUnread(like: 1, chat: 3));
    });

    test('a chat with unread is acked to its newest message; its count and the 私信 count drop at once', () async {
      final model = make();
      model.start();
      await model.refresh();
      final sheep = model.sessions.firstWhere((session) => session.talkerId == 501);
      expect((sheep.unread, sheep.ackSeqno, sheep.maxSeqno), (2, 4, 6));

      final read = api.holds['read'] = Completer<void>();
      final opened = model.chatOpened(sheep);
      expect(model.unread.chat, 1, reason: 'before Bilibili answers');
      expect(model.sessions.firstWhere((session) => session.talkerId == 501).unread, 0);
      read.complete();
      await opened;
      expect(api.reads, [(talkerId: 501, seqno: 6)]);
      expect(model.badge, 5);
    });

    test('a chat with nothing unread asks nothing', () async {
      final model = make();
      await model.refresh();
      final idleChat = model.sessions.firstWhere((session) => session.unread == 0);
      await model.chatOpened(idleChat);
      expect(api.reads, isEmpty);
      expect(api.calls.where((call) => call.startsWith('read')), isEmpty);
    });

    test('a failed ack is logged and the count stays down', () async {
      final model = make();
      model.start();
      await model.refresh();
      api.failures['read'] = const BiliHTTPError(503);
      await model.chatOpened(model.sessions.firstWhere((session) => session.talkerId == 502));
      expect(model.unread.chat, 2);
      expect(logged(), contains('message read failed'));
      expect(logged(), contains('http 503'));
    });

    test('系统通知 goes by its own count', () async {
      api.counts = const MessageUnread(system: 4, chat: 1);
      final model = make();
      model.start();
      await idle();
      final system = ChatSession(
        talkerId: 0,
        name: NoticeBox.system.label,
        face: '',
        lastText: '',
        time: demoTime,
        maxSeqno: 2,
        box: NoticeBox.system,
      );
      await model.chatOpened(system);
      expect(model.unread, const MessageUnread(chat: 1));
      expect(api.reads, [(talkerId: 0, seqno: 2)]);
    });

    test('一键已读 asks Bilibili, then every count and session goes to 0', () async {
      final model = make();
      model.start();
      await model.refresh();
      final hold = api.holds['readAll'] = Completer<void>();
      final reading = model.readAll();
      await idle();
      expect(model.badge, 7, reason: 'nothing changes before Bilibili accepts it');
      hold.complete();
      await reading;
      expect(api.calls, contains('readAll'));
      expect(model.unread, const MessageUnread());
      expect(model.sessions.every((session) => session.unread == 0), isTrue);
      expect(model.badge, 0);
    });

    test('一键已读 refused throws, the counts as they were', () async {
      final model = make();
      model.start();
      await idle();
      api.failures['readAll'] = const BiliAPIError(code: -400, message: '演示');
      await expectLater(model.readAll(), throwsA(isA<BiliAPIError>()));
      expect(model.badge, 7);
      expect(logged(), contains('message read all failed'));
    });
  });

  group('消息提醒', () {
    test('off, the badge is 0 whatever the counts; on, their total; kept in the prefs', () async {
      final prefs = MessagePrefs.memory();
      final model = make(prefs: prefs);
      model.start();
      await idle();
      var notified = 0;
      model.addListener(() => notified++);

      await model.setBadgeOn(false);
      expect(model.badgeOn, isFalse);
      expect(prefs.badgeOn, isFalse);
      expect(model.badge, 0);
      expect(model.unread.total, 7, reason: 'the counts are still asked');
      expect(notified, 1);

      await model.setBadgeOn(false);
      expect(notified, 1);
      await model.setBadgeOn(true);
      expect(model.badge, 7);
    });

    test('a launch with it off starts off', () async {
      final model = make(prefs: MessagePrefs.memory(badgeOn: false));
      model.start();
      await idle();
      expect(model.badgeOn, isFalse);
      expect(model.badge, 0);
    });
  });

  test('requestShow fires showRequests', () {
    final model = make();
    var shown = 0;
    model.showRequests.addListener(() => shown++);
    model.requestShow();
    expect(shown, 1);
  });

  test('once disposed, the account, logins and returns to the app ask nothing', () async {
    environment = _Environment(loggedIn);
    final model = MessageModel(api: api, environment: environment, now: () => clock, logger: logger);
    model.start();
    await idle();
    model.dispose();
    api.calls.clear();
    clock = clock.add(const Duration(minutes: 5));
    backToApp();
    environment.logIn();
    environment.account = const LoggedOut();
    await idle();
    expect(api.calls, isEmpty);
  });

  group('the demo', () {
    test('counts 2 replies, 1 @, 1 like and 3 私信, which its sessions add up to', () async {
      final demo = FakeMessageApi.demo(now: demoTime);
      expect(await demo.unread(), const MessageUnread(reply: 2, at: 1, like: 1, chat: 3));
      final sessions = (await demo.sessions()).sessions;
      expect(sessions.fold<int>(0, (sum, session) => sum + session.unread), 3);
    });

    test('回复与@ has each kind of row, newest first, and pages', () async {
      final demo = FakeMessageApi.demo(now: demoTime, pageSize: 5);
      final first = await demo.replies();
      expect(first.items, hasLength(5));
      final rest = await demo.replies(cursor: first.next);
      expect(rest.next, isNull);
      final replies = [...first.items, ...rest.items];
      expect(replies, hasLength(8));
      expect(replies.where((reply) => reply.fromUploader), hasLength(1));
      expect(replies.where((reply) => reply.liked), hasLength(2));
      expect(replies.where((reply) => reply.text.contains('[doge]') && reply.text.length > 40), isNotEmpty);
      expect(replies.where((reply) => reply.business == 'video' && reply.targetText.isEmpty), hasLength(1));
      expect(replies.map((reply) => reply.time), _newestFirst);
      expect(demoTime.difference(replies.first.time), lessThan(const Duration(hours: 1)));
      expect(demoTime.difference(replies.last.time), greaterThan(const Duration(days: 365)));
      expect((await demo.mentions()).items, hasLength(2));
    });

    test('收到喜欢 has a row of 12, one on a 弹幕 and a single liker', () async {
      final likes = (await FakeMessageApi.demo(now: demoTime).likes()).items;
      expect(likes, hasLength(5));
      expect(likes.where((like) => like.count == 12), hasLength(1));
      expect(likes.where((like) => like.business == '弹幕'), hasLength(1));
      expect(likes.where((like) => like.count == 1 && like.users.length == 1), hasLength(1));
    });

    test('新增粉丝 has three, one followed back', () async {
      final fans = await FakeMessageApi.demo(now: demoTime).newFans(1, page: 1);
      expect(fans.users, hasLength(3));
      expect(fans.users.where((fan) => fan.mutual), hasLength(1));
    });

    test('the sessions: two boxes and eight people, every one with a chat, paging to the end', () async {
      final demo = FakeMessageApi.demo(now: demoTime, pageSize: 4);
      final sessions = <ChatSession>[];
      int? next;
      var pages = 0;
      do {
        final page = await demo.sessions(next: next);
        sessions.addAll(page.sessions);
        next = page.next;
        pages++;
      } while (next != null);
      expect(pages, 3);
      expect(sessions, hasLength(10));
      expect(sessions.map((session) => session.time), _newestFirst);
      expect(sessions.where((session) => session.box == NoticeBox.service), hasLength(1));
      expect(sessions.where((session) => session.box == NoticeBox.community), hasLength(1));
      final people = sessions.where((session) => session.box == null).toList();
      expect(people, hasLength(8));
      expect(people.every((session) => session.name.startsWith('演示') && session.face.isEmpty), isTrue);
      expect(people.where((session) => session.vipPink), isNotEmpty);
      expect(people.where((session) => session.bigVip), isNotEmpty);
      expect(people.where((session) => session.verify != DynamicVerify.none), isNotEmpty);
      expect(people.where((session) => session.lastText.startsWith('[自动回复] ')), isNotEmpty);

      for (final session in sessions) {
        final chat = (await demo.messages(session)).messages;
        expect(chat, isNotEmpty, reason: session.name);
        expect(chat.last.seqno, session.maxSeqno, reason: session.name);
      }
    });

    test('the chats have text both ways, emotes, an auto reply, a tip, a picture and the service cards', () async {
      final demo = FakeMessageApi.demo(now: demoTime);
      final all = [for (final chat in demo.chats.values) ...chat];
      expect(all.where((message) => message.senderMid == demo.selfMid), isNotEmpty);
      expect(
        all.where((message) => message.kind == ChatMessageKind.text && message.senderMid != demo.selfMid),
        isNotEmpty,
      );
      expect(all.where((message) => message.text.contains('[')), isNotEmpty);
      expect(all.where((message) => message.autoReply), isNotEmpty);
      expect(all.where((message) => message.kind == ChatMessageKind.tip), isNotEmpty);
      expect(all.where((message) => message.kind == ChatMessageKind.picture && message.picture.isEmpty), isNotEmpty);

      final service = (await demo.sessions()).sessions.firstWhere((session) => session.box == NoticeBox.service);
      final cards = demo.chats[service.talkerId]!;
      final notices = cards.where((message) => message.kind == ChatMessageKind.notice).toList();
      expect(notices, isNotEmpty);
      expect(notices.first.fields.map((field) => field.title), contains('有效期'));
      expect(notices.first.links.map((link) => link.text), ['立即查看', '更多个性装扮']);
      expect(
        cards.where((message) => message.kind == ChatMessageKind.text && message.text.contains('https://')),
        isNotEmpty,
      );

      final system = ChatSession(talkerId: 0, name: '', face: '', lastText: '', time: demoTime, box: NoticeBox.system);
      final notices0 = (await demo.messages(system)).messages;
      expect(notices0, isNotEmpty);
      expect(notices0.every((message) => message.kind == ChatMessageKind.notice), isTrue);
    });
  });
}

final _newestFirst = predicate<Iterable<DateTime>>((times) {
  final list = times.toList();
  for (var i = 1; i < list.length; i++) {
    if (!list[i - 1].isAfter(list[i])) return false;
  }
  return true;
}, 'newest first, no two at once');
