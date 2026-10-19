import 'dart:async';
import 'dart:io' show SocketException;

import 'package:bili_core/api.dart';
import 'package:bili_core/danmaku.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/danmaku/block_rule_store.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sink implements LogSink {
  final events = <LogEvent>[];

  @override
  void receive(LogEvent event) => events.add(event);
}

void main() {
  late FakePageApi api;
  late DateTime now;
  late bool loggedIn;
  late _Sink sink;
  late BlockRuleStore store;
  late int notified;

  setUp(() {
    api = FakePageApi()
      ..blockRules = [
        const BlockRule(id: 1, kind: BlockRuleKind.keyword, filter: 'CA'),
        const BlockRule(id: 2, kind: BlockRuleKind.regex, filter: '/^6+\$/'),
      ];
    now = DateTime(2026, 10, 19, 12);
    loggedIn = true;
    sink = _Sink();
    final logger = Logger(session: 'test')..add(sink);
    store = BlockRuleStore(api: api, isLoggedIn: () => loggedIn, now: () => now, logger: logger);
    notified = 0;
    store.addListener(() => notified++);
  });

  tearDown(() => store.dispose());

  int fetches() => api.calls.where((call) => call == 'danmakuBlockRules').length;

  test('the first refresh fetches the rules and notifies', () async {
    expect(await store.refresh(), isNull);
    expect(store.rules.map((rule) => rule.filter), ['CA', '/^6+\$/']);
    expect(notified, greaterThan(0));
    expect(store.loading, isFalse);
  });

  test('loading is true while the server has not answered', () async {
    final hold = api.holds['danmakuBlockRules'] = Completer<void>();
    final refresh = store.refresh();
    expect(store.loading, isTrue);
    hold.complete();
    await refresh;
    expect(store.loading, isFalse);
  });

  test('a list younger than 10 minutes is not fetched again', () async {
    await store.refresh();
    now = now.add(const Duration(minutes: 9, seconds: 59));
    await store.refresh();
    expect(fetches(), 1);
    now = now.add(const Duration(seconds: 1));
    await store.refresh();
    expect(fetches(), 2);
  });

  test('force (同步) fetches even a fresh list', () async {
    await store.refresh();
    api.blockRules = [...api.blockRules, const BlockRule(id: 7, kind: BlockRuleKind.keyword, filter: '剧透')];
    await store.refresh(force: true);
    expect(fetches(), 2);
    expect(store.rules.last.filter, '剧透');
  });

  test('refreshes at the same time share one request', () async {
    final hold = api.holds['danmakuBlockRules'] = Completer<void>();
    final first = store.refresh();
    final second = store.refresh(force: true);
    hold.complete();
    await Future.wait([first, second]);
    expect(fetches(), 1);
  });

  test('adds a keyword through the server and notifies', () async {
    await store.refresh();
    notified = 0;
    expect(await store.add(BlockRuleKind.keyword, '  剧透 '), isNull);
    expect(api.calls.last, 'addBlockRule keyword=剧透');
    expect(store.rules.last, isA<BlockRule>().having((rule) => rule.filter, 'filter', '剧透'));
    expect(api.blockRules.map((rule) => rule.filter), contains('剧透'));
    expect(notified, 1);
  });

  test('adds a regex with its slashes, as BiliNative sends it', () async {
    expect(await store.add(BlockRuleKind.regex, '/^哈+\$/'), isNull);
    expect(api.calls.last, 'addBlockRule regex=/^哈+\$/');
    expect(store.rules.last.kind, BlockRuleKind.regex);
  });

  test('a regex that does not compile is refused before the server', () async {
    expect(await store.add(BlockRuleKind.regex, '/(/'), BlockRuleStore.invalidRegexMessage);
    expect(await store.add(BlockRuleKind.regex, '//'), BlockRuleStore.invalidRegexMessage);
    expect(api.calls.where((call) => call.startsWith('addBlockRule')), isEmpty);
  });

  test('a user rule stores the uid as its CRC-32', () async {
    expect(await store.add(BlockRuleKind.user, '12345'), isNull);
    expect(api.calls.last, 'addBlockRule user=${MidHash.of(12345)}');
    expect(await store.add(BlockRuleKind.user, 'not a uid'), BlockRuleStore.invalidUserMessage);
  });

  test('a rule already in the list is not added twice', () async {
    await store.refresh();
    api.calls.clear();
    expect(await store.add(BlockRuleKind.keyword, 'CA'), BlockRuleStore.duplicateMessage);
    expect(api.calls, isEmpty);
    expect(store.rules.where((rule) => rule.filter == 'CA'), hasLength(1));
  });

  test('empty text is not sent', () async {
    expect(await store.add(BlockRuleKind.keyword, '   '), BlockRuleStore.emptyMessage);
    expect(api.calls, isEmpty);
  });

  test('removes a rule through the server and notifies', () async {
    await store.refresh();
    notified = 0;
    expect(await store.remove(store.rules.first), isNull);
    expect(api.calls.last, 'deleteBlockRule id=1');
    expect(store.rules.map((rule) => rule.id), [2]);
    expect(api.blockRules.map((rule) => rule.id), [2]);
    expect(notified, 1);
  });

  test('a refusal shows the server\'s words, other failures Swift\'s, and each is logged', () async {
    await store.refresh();
    api.failures['addBlockRule'] = const BiliError.api(code: 36701, message: '屏蔽词数量已达上限');
    expect(await store.add(BlockRuleKind.keyword, '新词'), '屏蔽词数量已达上限');
    api.failures['addBlockRule'] = const SocketException('offline');
    expect(await store.add(BlockRuleKind.keyword, '新词'), BlockRuleStore.addFailed);
    api.failures['deleteBlockRule'] = const BiliError.http(500);
    expect(await store.remove(store.rules.first), BlockRuleStore.removeFailed);
    api.failures['danmakuBlockRules'] = const SocketException('offline');
    expect(await store.refresh(force: true), BlockRuleStore.syncFailed);
    expect(store.rules, hasLength(2));
    expect(sink.events.where((event) => event.level == LogLevel.warn), hasLength(4));
  });

  test('an expired login empties the list and asks to log in', () async {
    await store.refresh();
    api.failures['danmakuBlockRules'] = const BiliError.api(code: -101, message: '账号未登录');
    expect(await store.refresh(force: true), BlockRuleStore.needLogin);
    expect(store.rules, isEmpty);
    api.failures['addBlockRule'] = const BiliError.api(code: -101, message: '账号未登录');
    expect(await store.add(BlockRuleKind.keyword, '新词'), BlockRuleStore.needLogin);
  });

  test('logged out: no calls, the list is emptied, add and remove ask to log in', () async {
    await store.refresh();
    loggedIn = false;
    api.calls.clear();
    expect(await store.refresh(force: true), BlockRuleStore.needLogin);
    expect(store.rules, isEmpty);
    expect(await store.add(BlockRuleKind.keyword, '新词'), BlockRuleStore.needLogin);
    expect(
      await store.remove(const BlockRule(id: 1, kind: BlockRuleKind.keyword, filter: 'CA')),
      BlockRuleStore.needLogin,
    );
    expect(api.calls, isEmpty);
  });

  test('an answer that lands after logging out is dropped', () async {
    final hold = api.holds['danmakuBlockRules'] = Completer<void>();
    final refresh = store.refresh();
    loggedIn = false;
    await store.refresh();
    hold.complete();
    await refresh;
    expect(store.rules, isEmpty);
  });
}
