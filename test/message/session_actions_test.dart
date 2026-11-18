import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/message/chat/chat_page.dart';
import 'package:bilifast/message/fake_message_api.dart';
import 'package:bilifast/message/message_model.dart';
import 'package:bilifast/message/message_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../home/fake_login_gate.dart';
import '../playback/fakes.dart';
import '../video/mixed_lines.dart' show appTheme;

final _now = DateTime(2026, 11, 18, 7, 5);

ChatSession _person(int id, DateTime time, {int unread = 0, int topTs = 0}) => ChatSession(
  talkerId: id,
  name: '演示用户$id',
  face: '',
  lastText: '演示消息$id',
  time: time,
  unread: unread,
  maxSeqno: 10,
  ackSeqno: 10 - unread,
  topTs: topTs,
);

ChatSession _box(NoticeBox box, DateTime time) =>
    ChatSession(talkerId: 9000 + box.index, box: box, name: box.label, face: '', lastText: '演示通知', time: time);

/// 259's order: the two notice boxes, then people, newest first.
List<ChatSession> _sessions() => [
  _box(NoticeBox.service, DateTime(2026, 11, 13, 9)),
  _box(NoticeBox.community, DateTime(2026, 11, 12, 10)),
  _person(1, DateTime(2026, 11, 12, 8), unread: 2),
  _person(2, DateTime(2026, 10, 21)),
  _person(3, DateTime(2026, 10, 8)),
  _person(4, DateTime(2026, 10, 4)),
];

/// get_sessions answering strictly by time, pinned sessions where their time puts them.
class _TimeOrderApi extends FakeMessageApi {
  _TimeOrderApi({super.sessionList, super.pageSize});

  @override
  Future<ChatSessionPage> sessions({int? next}) async {
    calls.add('sessions ${next ?? 0}');
    final ordered = [...sessionList]..sort((a, b) => b.time.compareTo(a.time));
    final start = next == null ? 0 : ordered.indexWhere((session) => session.time.millisecondsSinceEpoch < next);
    final end = (start + pageSize).clamp(0, ordered.length);
    final page = ordered.sublist(start, end);
    return ChatSessionPage(sessions: page, next: end < ordered.length ? page.last.time.millisecondsSinceEpoch : null);
  }
}

/// Holds every page past the first until [_next] completes.
class _HeldNextApi extends FakeMessageApi {
  _HeldNextApi(this._next, {super.sessionList, super.pageSize});

  final Future<void> _next;

  @override
  Future<ChatSessionPage> sessions({int? next}) async {
    if (next != null) await _next;
    return super.sessions(next: next);
  }
}

/// Answers the session list as it stood when asked, held until the [gate] set then completes.
class _GatedListApi extends FakeMessageApi {
  _GatedListApi({super.sessionList, super.counts});

  Completer<void>? gate;

  @override
  Future<ChatSessionPage> sessions({int? next}) async {
    final held = gate;
    final page = await super.sessions(next: next);
    if (held != null) await held.future;
    return page;
  }
}

Finder _key(String key) => find.byKey(ValueKey(key));

/// The session ids top to bottom, as the model lists them.
List<int> _order(MessageModel model) => [for (final session in model.sessions) session.talkerId];

void main() {
  late MemorySink sink;
  late Logger logger;

  setUp(() {
    sink = MemorySink();
    logger = Logger(session: 'test')..add(sink);
  });

  String logged() => sink.events.map((event) => '${event.toJson()}').join('\n');

  Future<AppEnvironment> environment() async {
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: Canned.http(),
      logger: logger,
    );
    await environment.refreshAccount();
    return environment;
  }

  Future<MessageModel> loaded(FakeMessageApi api) async {
    final model = MessageModel(api: api, environment: await environment(), now: () => _now, logger: logger);
    addTearDown(model.dispose);
    await model.refresh();
    return model;
  }

  group('the model', () {
    testWidgets('pinned sessions head the list, the latest pinned first, wherever get_sessions puts them; a next page '
        'with one pinned puts it up there too', (tester) async {
      final api = _TimeOrderApi(
        pageSize: 4,
        sessionList: [
          ..._sessions(),
          _person(5, DateTime(2026, 9, 1), topTs: 100),
          _person(6, DateTime(2026, 8, 1), topTs: 200),
        ],
      );
      final model = await tester.runAsync(() => loaded(api));
      expect(_order(model!), [9000, 9001, 1, 2]);
      await tester.runAsync(model.loadMore);
      expect(_order(model), [6, 5, 9000, 9001, 1, 2, 3, 4]);
    });

    testWidgets('置顶 once Bilibili accepts: the row heads the list; 取消置顶 puts it back by its time; one log line '
        'each, no ids', (tester) async {
      final api = FakeMessageApi(sessionList: _sessions());
      final model = (await tester.runAsync(() => loaded(api)))!;
      final third = model.sessions[2];

      await tester.runAsync(() => model.setTop(third, on: true));
      expect(api.tops, [(talkerId: 1, on: true)]);
      expect(_order(model), [1, 9000, 9001, 2, 3, 4]);
      expect(model.sessions.first.top, isTrue);
      expect(model.sessions.first.topTs, _now.microsecondsSinceEpoch);

      await tester.runAsync(() => model.setTop(model.sessions.first, on: false));
      expect(api.tops.last, (talkerId: 1, on: false));
      expect(_order(model), [9000, 9001, 1, 2, 3, 4]);
      expect(model.sessions[2].top, isFalse);

      final lines = [for (final event in sink.events.where((event) => event.msg == 'message top')) event.toJson()['f']];
      expect('$lines', '[{on: true, result: ok}, {on: false, result: ok}]');
      expect(logged(), isNot(contains('演示用户')));
    });

    testWidgets('a refused 置顶 throws and leaves the row where it was; its line has the code', (tester) async {
      final api = FakeMessageApi(sessionList: _sessions())
        ..failures['setTop'] = const BiliAPIError(code: -400, message: '请求错误');
      final model = (await tester.runAsync(() => loaded(api)))!;
      Object? thrown;
      await tester.runAsync(() async {
        try {
          await model.setTop(model.sessions[2], on: true);
        } on Object catch (error) {
          thrown = error;
        }
      });
      expect(thrown, isA<BiliAPIError>());
      expect(_order(model), [9000, 9001, 1, 2, 3, 4]);
      expect(model.sessions[2].top, isFalse);
      expect(logged(), contains('api -400'));
    });

    testWidgets('删除 takes the row off and its unread off 私信\'s count; refused, it stays', (tester) async {
      final api = FakeMessageApi(sessionList: _sessions(), counts: const MessageUnread(chat: 5));
      final model = (await tester.runAsync(() => loaded(api)))!;
      expect(model.unread.chat, 5);

      await tester.runAsync(() => model.removeSession(model.sessions[2]));
      expect(api.removed, [1]);
      expect(_order(model), [9000, 9001, 2, 3, 4]);
      expect(model.unread.chat, 3);
      expect('${sink.events.where((event) => event.msg == 'message remove').single.toJson()['f']}', '{result: ok}');

      api.failures['removeSession'] = const BiliAPIError(code: 21026, message: '演示失败');
      Object? thrown;
      await tester.runAsync(() async {
        try {
          await model.removeSession(model.sessions[2]);
        } on Object catch (error) {
          thrown = error;
        }
      });
      expect(thrown, isA<BiliAPIError>());
      expect(_order(model), [9000, 9001, 2, 3, 4]);
      expect(logged(), contains('api 21026'));
    });

    testWidgets('删除 on a row with unread acks it up to its newest message first, so 私信\'s count stays down when '
        '消息 asks again; a row with none sends no ack', (tester) async {
      final api = FakeMessageApi(sessionList: _sessions(), counts: const MessageUnread(chat: 2));
      final model = (await tester.runAsync(() => loaded(api)))!;

      await tester.runAsync(() => model.removeSession(model.sessions[2]));
      expect(api.reads, [(talkerId: 1, seqno: 10)]);
      expect(api.calls.where((call) => call.startsWith(RegExp('read |removeSession'))), ['read 1 10', 'removeSession 1']);
      expect(_order(model), [9000, 9001, 2, 3, 4]);
      expect(model.unread.chat, 0);
      await tester.runAsync(() => model.refreshUnread(force: true));
      expect(model.unread.chat, 0);

      await tester.runAsync(() => model.removeSession(model.sessions[2]));
      expect(api.removed, [1, 2]);
      expect(api.reads, hasLength(1));
    });

    testWidgets("a first page answered between 删除's ack and its answer doesn't take the row's unread off twice", (
      tester,
    ) async {
      final sessions = [
        for (final session in _sessions()) session.talkerId == 3 ? _person(3, DateTime(2026, 10, 8), unread: 3) : session,
      ];
      final api = _GatedListApi(sessionList: sessions, counts: const MessageUnread(chat: 5));
      final model = (await tester.runAsync(() => loaded(api)))!;
      expect(model.unread.chat, 5);
      await tester.runAsync(() async {
        // Made in the real zone: completed here, one made outside would wait for a pump.
        final gate = api.gate = Completer<void>();
        final remove = api.holds['removeSession'] = Completer<void>();
        final refresh = model.refresh();
        api.gate = null;
        final removal = model.removeSession(model.sessions[2]);
        for (var turns = 0; turns < 20 && !api.calls.contains('removeSession 1'); turns++) {
          await Future<void>.value();
        }
        expect(api.calls, contains('removeSession 1'));
        expect(model.unread.chat, 3, reason: 'the ack took its 2 off');
        gate.complete();
        await refresh;
        remove.complete();
        await removal;
      });
      expect(_order(model), [9000, 9001, 2, 3, 4]);
      expect(model.unread.chat, 3);
    });

    testWidgets('a failed ack is logged and 删除 goes on; an ack through before a refused 删除 leaves the row read',
        (tester) async {
      final api = FakeMessageApi(sessionList: _sessions(), counts: const MessageUnread(chat: 2))
        ..failures['read'] = const BiliAPIError(code: -500, message: '演示失败');
      final model = (await tester.runAsync(() => loaded(api)))!;
      await tester.runAsync(() => model.removeSession(model.sessions[2]));
      expect(api.removed, [1]);
      expect(_order(model), [9000, 9001, 2, 3, 4]);
      expect(model.unread.chat, 0);
      expect(logged(), contains('message read failed'));

      final refused = FakeMessageApi(sessionList: _sessions(), counts: const MessageUnread(chat: 2))
        ..failures['removeSession'] = const BiliAPIError(code: 21026, message: '演示失败');
      final kept = (await tester.runAsync(() => loaded(refused)))!;
      await tester.runAsync(() async {
        await expectLater(kept.removeSession(kept.sessions[2]), throwsA(isA<BiliAPIError>()));
      });
      expect(refused.reads, [(talkerId: 1, seqno: 10)]);
      expect(_order(kept), [9000, 9001, 1, 2, 3, 4]);
      expect(kept.sessions[2].unread, 0);
      expect(kept.unread.chat, 0);
    });

    testWidgets('a first page asked before 置顶 and 删除 but answered after them keeps both; a page asked after a 删除 '
        'shows the session if Bilibili lists it again', (tester) async {
      final api = _GatedListApi(sessionList: _sessions());
      final model = (await tester.runAsync(() => loaded(api)))!;
      final gate = api.gate = Completer<void>();
      late Future<bool> refresh;
      await tester.runAsync(() async {
        refresh = model.refresh();
        api.gate = null;
        await model.setTop(model.sessions[4], on: true);
        await model.removeSession(model.sessions.last);
      });
      expect(_order(model), [3, 9000, 9001, 1, 2]);
      await tester.runAsync(() async {
        gate.complete();
        await refresh;
      });
      expect(_order(model), [3, 9000, 9001, 1, 2]);
      expect(model.sessions.first.top, isTrue);

      await tester.runAsync(() => model.removeSession(model.sessions.last));
      api.sessionList.add(_person(2, DateTime(2026, 11, 18, 7)));
      await tester.runAsync(model.refresh);
      expect(_order(model), [3, 2, 9000, 9001, 1]);
    });

    testWidgets('the fake keeps what was done: a refresh after 置顶 and 删除 answers them', (tester) async {
      final api = FakeMessageApi(sessionList: _sessions());
      final model = (await tester.runAsync(() => loaded(api)))!;
      await tester.runAsync(() => model.setTop(model.sessions[3], on: true));
      await tester.runAsync(() => model.removeSession(model.sessions.last));
      await tester.runAsync(model.refresh);
      expect(_order(model), [2, 9000, 9001, 1, 3]);
      expect(api.sessionList.firstWhere((session) => session.talkerId == 2).top, isTrue);
    });
  });

  group('the page', () {
    /// 消息 over [api] (its sessions by [_sessions] unless given) on a 440×956 screen under a 62 pt status bar.
    Future<(MessageModel, FakeMessageApi)> show(WidgetTester tester, {FakeMessageApi? api}) async {
      tester.view
        ..physicalSize = const Size(440, 956)
        ..devicePixelRatio = 1
        ..padding = const FakeViewPadding(top: 62, bottom: 34)
        ..viewPadding = const FakeViewPadding(top: 62, bottom: 34);
      addTearDown(tester.view.reset);
      final messageApi = api ?? FakeMessageApi(sessionList: _sessions());
      final env = await environment();
      final model = MessageModel(api: messageApi, environment: env, now: () => _now, logger: logger);
      addTearDown(model.dispose);
      final playback = AppPlayback(() async => throw UnimplementedError());
      addTearDown(playback.dispose);
      final services = AppServices(
        environment: env,
        playback: playback,
        recents: await RecentStore.load(null, logger: logger),
        loginGate: FakeLoginGate(),
        messageApi: messageApi,
        messages: model,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          builder: (context, child) => AppScope(services: services, child: child!),
          home: MessagePage(active: true, clock: () => _now),
        ),
      );
      await settle(tester);
      return (model, messageApi);
    }

    Rect row(WidgetTester tester, String id) => tester.getRect(_key('message-session-$id'));

    /// The row's buttons are out.
    bool open(WidgetTester tester, String id) => tester.any(_key('message-session-delete-$id'));

    Future<void> swipe(WidgetTester tester, String id, [double dx = -200]) async {
      await tester.drag(_key('message-session-$id'), Offset(dx, 0));
      await settle(tester);
    }

    testWidgets('259: a chat row swiped left slides 148 over 置顶 on grey and 删除 on red, 74 wide each and the row\'s '
        'height, their 16 pt white words centred', (tester) async {
      await show(tester);
      final before = tester.getTopLeft(_key('message-session-name-1'));
      await swipe(tester, '1');

      final rowRect = tester.getRect(find.byKey(const ValueKey('1-1')));
      final top = tester.getRect(_key('message-session-top-1'));
      final delete = tester.getRect(_key('message-session-delete-1'));
      expect(top, Rect.fromLTWH(440 - 148, rowRect.top, 74, MessageTabTheme.row));
      expect(delete, Rect.fromLTWH(440 - 74, rowRect.top, 74, MessageTabTheme.row));
      expect(tester.getTopLeft(_key('message-session-name-1')), before - const Offset(148, 0));

      ColoredBox fill(String key) =>
          tester.widget<ColoredBox>(find.descendant(of: _key(key), matching: find.byType(ColoredBox)).first);
      expect(fill('message-session-top-1').color, const Color(0xFFBBBBC1));
      expect(fill('message-session-delete-1').color, const Color(0xFFFC2125));
      for (final (key, word) in [('message-session-top-1', '置顶'), ('message-session-delete-1', '删除')]) {
        final text = find.descendant(of: _key(key), matching: find.text(word));
        final style = tester.widget<Text>(text).style!;
        expect((style.fontSize, style.color, style.fontWeight), (16.0, Colors.white, FontWeight.w400));
        expect(tester.getCenter(text), tester.getCenter(_key(key)));
      }
    });

    testWidgets('let go short of half the row springs back; past half it opens; a fling opens; a drag back closes', (
      tester,
    ) async {
      await show(tester);
      await swipe(tester, '1', -60);
      expect(open(tester, '1'), isFalse);
      await swipe(tester, '1', -100);
      expect(open(tester, '1'), isTrue);
      await swipe(tester, '1', 200);
      expect(open(tester, '1'), isFalse);

      await tester.fling(_key('message-session-1'), const Offset(-60, 0), 1000);
      await settle(tester);
      expect(open(tester, '1'), isTrue);
      await tester.fling(_key('message-session-1'), const Offset(50, 0), 1000);
      await settle(tester);
      expect(open(tester, '1'), isFalse);
    });

    testWidgets('a tap on the open row only closes it; a tap on another row or an entry closes it and opens nothing; '
        'once closed a tap opens the chat', (tester) async {
      await show(tester);
      await swipe(tester, '1');
      await tester.tap(_key('message-session-1'));
      await settle(tester);
      expect(open(tester, '1'), isFalse);
      expect(find.byType(ChatPage), findsNothing);

      await swipe(tester, '1');
      await tester.tap(_key('message-session-3'));
      await settle(tester);
      expect(open(tester, '1'), isFalse);
      expect(find.byType(ChatPage), findsNothing);

      await swipe(tester, '1');
      await tester.tap(_key('message-entry-likes'));
      await settle(tester);
      expect(open(tester, '1'), isFalse);
      expect(find.text('收到喜欢'), findsOneWidget, reason: 'still on 消息');

      await tester.tap(_key('message-session-3'));
      await settle(tester);
      expect(find.byType(ChatPage), findsOneWidget);
    });

    testWidgets('one row open at a time; a scroll puts it away', (tester) async {
      await show(tester);
      await swipe(tester, '1');
      await swipe(tester, '2');
      expect(open(tester, '1'), isFalse);
      expect(open(tester, '2'), isTrue);

      await tester.drag(_key('message-session-2'), const Offset(0, 120));
      await settle(tester, 30);
      expect(open(tester, '2'), isFalse);
    });

    testWidgets('a drag from the screen\'s left edge is the swipe back\'s: a closed row stays shut', (tester) async {
      await show(tester);
      final y = row(tester, '1').center.dy;
      await tester.dragFrom(Offset(BiliMetrics.swipeBackEdge - 6, y), const Offset(-200, 0));
      await settle(tester);
      expect(open(tester, '1'), isFalse);
      await tester.dragFrom(Offset(BiliMetrics.swipeBackEdge + 6, y), const Offset(-200, 0));
      await settle(tester);
      expect(open(tester, '1'), isTrue);
    });

    testWidgets('notice boxes don\'t swipe, and have no row actions', (tester) async {
      final semantics = tester.ensureSemantics();
      await show(tester);
      await swipe(tester, 'community');
      expect(find.text('置顶'), findsNothing);
      expect(
        tester.getSemantics(_key('message-session-community')),
        isNot(isSemantics(customActions: [const CustomSemanticsAction(label: '删除')])),
      );
      semantics.dispose();
    });

    testWidgets('262: 置顶 closes the row, which heads the list on grey; swiped again it reads 取消置顶, which puts it '
        'back by its time', (tester) async {
      final (model, api) = await show(tester);
      final first = row(tester, 'service').top;
      await swipe(tester, '2');
      await tester.tap(_key('message-session-top-2'));
      await settle(tester);
      expect(api.tops, [(talkerId: 2, on: true)]);
      expect(open(tester, '2'), isFalse);
      expect(row(tester, '2').top, first);
      expect(row(tester, 'service').top, first + MessageTabTheme.row);
      Color? fill(String id) => tester
          .widget<Container>(find.descendant(of: _key('message-session-$id'), matching: find.byType(Container)).first)
          .color;
      expect(fill('2'), const Color(0xFFF6F7F8));
      expect(fill('1'), isNull);

      await swipe(tester, '2');
      expect(find.descendant(of: _key('message-session-top-2'), matching: find.text('取消置顶')), findsOneWidget);
      await tester.tap(_key('message-session-top-2'));
      await settle(tester);
      expect(api.tops.last, (talkerId: 2, on: false));
      expect(row(tester, 'service').top, first);
      expect(row(tester, '2').top, row(tester, '1').bottom);
      expect(fill('2'), isNull);
      expect(model.sessions.where((session) => session.top), isEmpty);
    });

    testWidgets('a refused 置顶 leaves the row where it was and toasts Bilibili\'s words', (tester) async {
      final api = FakeMessageApi(sessionList: _sessions())
        ..failures['setTop'] = const BiliAPIError(code: 22001, message: '演示置顶失败');
      await show(tester, api: api);
      final where = row(tester, '2').top;
      await swipe(tester, '2');
      await tester.tap(_key('message-session-top-2'));
      await tester.pump();
      await tester.pump();
      expect(find.text('演示置顶失败'), findsOneWidget);
      await settle(tester, 60);
      expect(row(tester, '2').top, where);
    });

    testWidgets('260: 删除 asks first over the open row; 取消 keeps the row and closes it; 确认 takes it off', (
      tester,
    ) async {
      final (_, api) = await show(tester);
      await swipe(tester, '3');
      await tester.tap(_key('message-session-delete-3'));
      await settle(tester);
      expect(find.text('删除聊天记录'), findsOneWidget);
      expect(find.text('删除后所有聊天记录将被清空'), findsOneWidget);
      expect(tester.getSize(_key('message-delete')).width, MessageTabTheme.alertWidth);
      expect(open(tester, '3'), isTrue, reason: '260 keeps it open under the alert');

      await tester.tap(_key('message-delete-取消'));
      await settle(tester);
      expect(_key('message-delete'), findsNothing);
      expect(open(tester, '3'), isFalse);
      expect(api.removed, isEmpty);

      await swipe(tester, '3');
      await tester.tap(_key('message-session-delete-3'));
      await settle(tester);
      await tester.tap(_key('message-delete-确认'));
      await settle(tester);
      expect(api.removed, [3]);
      expect(_key('message-session-3'), findsNothing);
      expect(row(tester, '4').top, row(tester, '2').bottom);
    });

    testWidgets('a refused 删除 keeps the row, closes it and toasts', (tester) async {
      final api = FakeMessageApi(sessionList: _sessions())
        ..failures['removeSession'] = const BiliAPIError(code: 22002, message: '演示删除失败');
      await show(tester, api: api);
      await swipe(tester, '3');
      await tester.tap(_key('message-session-delete-3'));
      await settle(tester);
      await tester.tap(_key('message-delete-确认'));
      await tester.pump();
      await tester.pump();
      expect(find.text('演示删除失败'), findsOneWidget);
      await settle(tester, 60);
      expect(_key('message-session-3'), findsOneWidget);
      expect(open(tester, '3'), isFalse);
    });

    testWidgets('确认 closes the row; while its 删除 is out the row\'s actions only close it and send nothing; a second '
        '置顶 while the first is out sends nothing', (tester) async {
      final (model, api) = await show(tester);
      Iterable<String> sent(String call) => api.calls.where((each) => each.startsWith(call));
      final remove = api.holds['removeSession'] = Completer<void>();
      await swipe(tester, '3');
      await tester.tap(_key('message-session-delete-3'));
      await settle(tester);
      await tester.tap(_key('message-delete-确认'));
      await settle(tester);
      expect(open(tester, '3'), isFalse);

      await swipe(tester, '3');
      await tester.tap(_key('message-session-delete-3'));
      await settle(tester);
      expect(_key('message-delete'), findsNothing);
      expect(open(tester, '3'), isFalse);
      await swipe(tester, '3');
      await tester.tap(_key('message-session-top-3'));
      await settle(tester);
      expect(open(tester, '3'), isFalse);
      expect(sent('setTop'), isEmpty);

      remove.complete();
      await settle(tester);
      expect(sent('removeSession'), ['removeSession 3']);
      expect(_key('message-session-3'), findsNothing);

      final top = api.holds['setTop'] = Completer<void>();
      await swipe(tester, '2');
      await tester.tap(_key('message-session-top-2'));
      await settle(tester);
      await swipe(tester, '2');
      await tester.tap(_key('message-session-top-2'));
      await settle(tester);
      expect(sent('setTop'), ['setTop 2 true']);
      top.complete();
      await settle(tester);
      expect(api.tops, [(talkerId: 2, on: true)]);
      expect(model.sessions.first.talkerId, 2);
    });

    testWidgets('VoiceOver: a chat row offers 置顶 and 删除 as actions, which work without a swipe', (tester) async {
      final semantics = tester.ensureSemantics();
      final (_, api) = await show(tester);
      final node = tester.getSemantics(_key('message-session-2'));
      expect(
        node,
        isSemantics(
          customActions: [
            const CustomSemanticsAction(label: '置顶'),
            const CustomSemanticsAction(label: '删除'),
          ],
        ),
      );
      node.owner!.performAction(
        node.id,
        SemanticsAction.customAction,
        CustomSemanticsAction.getIdentifier(const CustomSemanticsAction(label: '置顶')),
      );
      await settle(tester);
      expect(api.tops, [(talkerId: 2, on: true)]);
      semantics.dispose();
    });

    testWidgets('261: past the last page 我可是有底线的_(:3ゝ∠)_ is centred under the last row in 12 pt grey; none while '
        'pages are left', (tester) async {
      final next = Completer<void>();
      final api = _HeldNextApi(next.future, sessionList: _sessions(), pageSize: 4);
      final (model, _) = await show(tester, api: api);
      expect(model.hasMore, isTrue);
      expect(_key('message-end'), findsNothing);

      next.complete();
      await settle(tester);
      expect(model.hasMore, isFalse);
      final end = find.text('我可是有底线的_(:3ゝ∠)_');
      expect(end, findsOneWidget);
      final style = tester.widget<Text>(end).style!;
      expect((style.fontSize, style.color), (12.0, const Color(0xFF9499A0)));
      final last = row(tester, '4');
      expect(tester.getCenter(end).dx, 220);
      expect(tester.getCenter(end).dy, moreOrLessEquals(last.bottom + 73 / 3, epsilon: 0.01));
      expect(tester.getSize(_key('message-end')).height, MessageTabTheme.endFoot);
    });
  });
}

Future<void> settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
