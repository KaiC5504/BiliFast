import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/devtools/node_probe_section.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import '../settings/settings_fakes.dart';

const _primary = 'https://upos-sz-mirrorcos.bilivideo.com/v/120-avc.m4s?deadline=9&upsig=secret';

const _source = NodeProbeSource(
  bvid: 'BV1xx411c7mD',
  title: '最近看的视频',
  fromRecents: true,
  quality: 120,
  codec: 'avc',
  primary: _primary,
  backups: [],
);

/// How one node answers, keyed by its short name.
final class _Node {
  const _Node({this.firstByteMs = 100, this.mbps, this.status = 206, this.error, this.hang = false});

  final double firstByteMs;
  final double? mbps;
  final int status;
  final Object? error;
  final bool hang;
}

/// Answers each node from [script] on a [ManualClock], so speeds come out exact; never reaches a network.
final class _ScriptedTransport implements RangeTransport {
  _ScriptedTransport(this.script, this.clock);

  final Map<String, _Node> script;
  final ManualClock clock;
  final asked = <String>[];
  bool closed = false;

  @override
  Future<TransportResponse> fetch(Uri url, ByteRange range, {CancelToken? cancel}) {
    final name = NodeProbe.shortName(url.host);
    asked.add(name);
    final node = script[name] ?? const _Node(mbps: 1);
    if (node.error case final error?) return Future.error(error);
    if (node.hang) {
      final hung = Completer<TransportResponse>();
      cancel?.onCancel(() {
        if (!hung.isCompleted) hung.completeError(const CancelledException());
      });
      return hung.future;
    }
    clock.advance(node.firstByteMs);
    if (node.status != 206) {
      return Future.value(TransportResponse(status: node.status, headers: const {}, body: const Stream.empty()));
    }
    Stream<List<int>> body() async* {
      clock.advance(range.length / 1048576 / node.mbps! * 1000);
      yield Uint8List(range.length);
    }

    return Future.value(TransportResponse(status: 206, headers: const {}, body: body()));
  }

  @override
  int? get connectionsPerHost => null;

  @override
  String get name => 'scripted';

  @override
  void close() => closed = true;
}

class _ClientEnvironment extends FakeEnvironment {
  _ClientEnvironment(this._client) : super(const LoggedOut());

  final BiliClient _client;

  @override
  BiliClient get client => _client;
}

void main() {
  late PlayerPrefs savedPrefs;

  setUp(() {
    savedPrefs = PlayerPrefs.shared;
    PlayerPrefs.shared = PlayerPrefs.memory()..node = NodeChoice.mainland;
  });

  tearDown(() => PlayerPrefs.shared = savedPrefs);

  group('the card', () {
    late SettingsWorld world;
    late MemorySink logs;
    late _ScriptedTransport transport;
    late int loads;
    Completer<void>? loadGate;

    const script = {
      'cos': _Node(firstByteMs: 120, mbps: 2),
      'ali': _Node(mbps: 3),
      'hw': _Node(status: 403),
      'bos': _Node(error: SocketException('Connection refused')),
      '08c': _Node(mbps: 4),
      'bd': _Node(mbps: 5),
      '14b': _Node(mbps: 6),
      'estgoss': _Node(mbps: 1),
      'cosov': _Node(firstByteMs: 300, mbps: 10),
      'aliov': _Node(firstByteMs: 250, mbps: 12),
      'hk-eq-01-01': _Node(mbps: 0.5),
      'hk-eq-01-03': _Node(hang: true),
    };

    Future<void> pumpCard(WidgetTester tester, NodeProbeBackend backend) => tester.pumpWidget(
      MaterialApp(
        home: AppScope(
          services: world.services,
          child: NodeProbeScope(
            backend: backend,
            child: const Scaffold(body: SingleChildScrollView(child: NodeProbeSection())),
          ),
        ),
      ),
    );

    Future<void> show(WidgetTester tester, {Map<String, _Node> nodes = script, NodeProbeBackend? backend}) async {
      tester.view
        ..physicalSize = const Size(440, 956) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      world = await SettingsWorld.create();
      addTearDown(world.dispose);
      logs = MemorySink();
      final logger = Logger(session: 'test')..add(logs);
      final clock = ManualClock();
      transport = _ScriptedTransport(nodes, clock);
      loads = 0;
      await pumpCard(
        tester,
        backend ??
            NodeProbeBackend(
              load: (services) async {
                loads += 1;
                expect(services, same(world.services));
                await loadGate?.future;
                return _source;
              },
              probe: () => NodeProbe(transport: transport, bytes: 64 * 1024, clock: clock.clock, logger: logger),
            ),
      );
    }

    testWidgets('a run: every node in turn, the groups\' medians, the fastest node and 设置\'s choice to make', (tester) async {
      await show(tester);
      expect(find.text('同一段视频（前 4 MB）依次向每个节点要一遍'), findsOneWidget);
      expect(find.byKey(const ValueKey('node-probe-start')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('node-probe-start')));
      await tester.pump();
      await tester.pump();
      expect(loads, 1);
      expect(find.byKey(const ValueKey('node-probe-stop')), findsOneWidget);
      expect(_text(tester, 'node-probe-status'), '正在测 hk-eq-01-03（12/12）', reason: 'the last node hangs');
      expect(_text(tester, 'node-probe-video'), '最近打开：最近看的视频 · 4K · AVC');
      expect(find.byKey(const ValueKey('node-probe-suggestion')), findsNothing);

      await tester.pump(const Duration(seconds: 9));
      expect(_text(tester, 'node-probe-status'), '测完 12 个节点');
      expect(transport.asked, [
        'cos', 'ali', 'hw', 'bos', '08c', 'bd', '14b', 'estgoss', //
        'cosov', 'aliov', 'hk-eq-01-01', 'hk-eq-01-03',
      ]);
      expect(transport.closed, isTrue);
      expect(_text(tester, 'node-probe-mainland-median'), '国内  中位 3.50 MB/s  6/8 通');
      expect(_text(tester, 'node-probe-overseas-median'), '海外  中位 10.0 MB/s  3/4 通');
      expect(_text(tester, 'node-probe-fastest'), '最快：aliov（海外）12.0 MB/s');
      expect(_text(tester, 'node-probe-suggestion'), '建议：设置 → CDN 节点 改选「海外节点」（现在是「大陆节点」）');

      expect(_row(tester, 'upos-sz-mirrorcos.bilivideo.com'), ['cos', '120 ms', '2.00']);
      expect(_row(tester, 'upos-sz-mirrorhw.bilivideo.com'), ['hw', '100 ms', 'HTTP 403']);
      expect(_row(tester, 'upos-sz-mirrorbos.bilivideo.com'), ['bos', '拒绝连接', '–']);
      expect(_row(tester, 'upos-sz-mirroraliov.bilivideo.com'), ['aliov', '250 ms', '12.0']);
      expect(_row(tester, 'cn-hk-eq-01-03.bilivideo.com'), ['hk-eq-01-03', '超时', '–']);

      final cells = find.descendant(of: find.byKey(const ValueKey('node-probe-overseas')), matching: find.byType(Text));
      final colours = {for (final cell in tester.widgetList<Text>(cells)) cell.data: cell.style?.color};
      expect(colours['超时'], colours['节点'], reason: 'a failed node is greyed');
      expect(colours['12.0'], isNot(colours['10.0']), reason: 'the fastest node stands out');

      final lines = logs.events.where((event) => event.msg == 'node probe').toList();
      expect(lines.map((line) => (line.f['host'] as LogString?)?.value), [
        'upos-sz-mirrorcos.bilivideo.com',
        ...NodeCatalog.mainland.take(7),
        ...NodeCatalog.overseas,
      ]);
      expect(lines.expand((line) => line.f.values).whereType<LogString>().any((value) => value.value.contains('upsig')),
          isFalse);
    });

    testWidgets('the faster group already chosen says so; no group answering gives no advice', (tester) async {
      PlayerPrefs.shared.node = NodeChoice.overseas;
      await show(tester, nodes: {for (final name in script.keys) name: script[name]!.hang ? const _Node(mbps: 0.2) : script[name]!});
      await tester.tap(find.byKey(const ValueKey('node-probe-start')));
      await tester.pump();
      await tester.pump();
      expect(_text(tester, 'node-probe-suggestion'), '建议：设置 → CDN 节点 选「海外节点」（现在就是）');

      expect(nodeProbeSuggestion(NodeProbeSummary.of(const []), NodeChoice.overseas), '两组都没测通，给不出建议');
      final mainlandOnly = NodeProbeSummary.of(const [
        NodeProbeResult(group: NodeGroup.mainland, node: 'a', firstByteMs: 1, bytes: 1048576, transferMs: 1000),
        NodeProbeResult(group: NodeGroup.overseas, node: 'b', failure: NodeProbeFailure.timeout),
      ]);
      expect(nodeProbeSuggestion(mainlandOnly, NodeChoice.overseas), '建议：设置 → CDN 节点 改选「大陆节点」（现在是「海外节点」）');
    });

    testWidgets('停止 while a node hangs ends the run at once, through accessibility presses too', (tester) async {
      final semantics = tester.ensureSemantics();
      await show(tester, nodes: {...script, 'cos': const _Node(hang: true)});
      tester.semantics.tap(find.semantics.byLabel(RegExp('开始测速')));
      await tester.pump();
      await tester.pump();
      expect(_text(tester, 'node-probe-status'), '正在测 cos（1/12）');

      tester.semantics.tap(find.semantics.byLabel(RegExp('停止')));
      await tester.pump();
      await tester.pump();
      expect(_text(tester, 'node-probe-status'), '已停止，测了 0/12 个');
      expect(find.byKey(const ValueKey('node-probe-start')), findsOneWidget);
      expect(transport.asked, ['cos'], reason: 'no node after the stopped one is asked');
      expect(transport.closed, isTrue);
      expect(logs.events.where((event) => event.msg == 'node probe'), isEmpty);

      await tester.pump(const Duration(seconds: 10));
      expect(transport.asked, ['cos']);
      semantics.dispose();
    });

    testWidgets('停止 while the address is still loading stops before any node is asked', (tester) async {
      loadGate = Completer<void>();
      addTearDown(() => loadGate = null);
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('node-probe-start')));
      await tester.pump();
      expect(_text(tester, 'node-probe-status'), '正在取视频地址…');
      await tester.tap(find.byKey(const ValueKey('node-probe-stop')));
      await tester.pump();
      expect(_text(tester, 'node-probe-status'), '已停止');
      loadGate!.complete();
      await tester.pump();
      expect(transport.asked, isEmpty);
    });

    testWidgets('a stream with no address the nodes take, or a failed load, says why', (tester) async {
      Future<void> run(NodeProbeBackend backend) async {
        await tester.pumpWidget(const SizedBox());
        await pumpCard(tester, backend);
        await tester.tap(find.byKey(const ValueKey('node-probe-start')));
        await tester.pump();
        await tester.pump();
      }

      await show(tester);
      await run(NodeProbeBackend(
        load: (_) async => const NodeProbeSource(
          bvid: 'BV1',
          title: '视频',
          fromRecents: true,
          quality: 80,
          codec: 'avc',
          primary: 'http://example.com/v.m4s',
          backups: [],
        ),
        probe: () => NodeProbe(transport: transport),
      ));
      expect(_text(tester, 'node-probe-status'), '这个视频没有可测的地址');
      expect(transport.closed, isTrue);

      await run(NodeProbeBackend(
        load: (_) async => throw const BiliError.api(code: -404, message: '啥都木有'),
        probe: () => NodeProbe(transport: transport),
      ));
      expect(_text(tester, 'node-probe-status'), '视频不存在或已被删除');
      expect(transport.asked, isEmpty);
    });
  });

  group('the stream it asks', () {
    Future<(AppServices, CannedHttp)> servicesWith({RecentVideo? recent}) async {
      final http = Canned.http();
      final logger = Logger(session: 'test');
      final client = BiliClient(transport: http, cookies: CookieJar(Canned.cookies), logger: logger);
      final recents = await RecentStore.load(null);
      if (recent != null) recents.add(recent);
      final playback = AppPlayback(() => Completer<PlaybackController>().future, logger: logger);
      addTearDown(playback.dispose);
      final services = AppServices(
        environment: _ClientEnvironment(client),
        playback: playback,
        recents: recents,
        fonts: FontStore.memory(logger: logger),
        pageApi: FakePageApi(),
        loginGate: FakeLoginGate(),
      );
      return (services, http);
    }

    testWidgets('the newest of 最近打开: one playurl call for its part at 1080P, and the AVC stream of what came', (tester) async {
      final (services, http) = await servicesWith(
        recent: const RecentVideo(bvid: 'BV1xx411c7mD', cid: 42, title: '最近看的', part: '', page: 1, pageCount: 1),
      );
      final source = await loadNodeProbeSource(services);
      expect(http.to(Canned.viewPath), isEmpty);
      final asked = http.to(Canned.playUrlPath).single.url.queryParameters;
      expect((asked['bvid'], asked['cid'], asked['qn']), ('BV1xx411c7mD', '42', '80'));
      expect((source.bvid, source.title, source.fromRecents, source.quality, source.codec),
          ('BV1xx411c7mD', '最近看的', true, 120, 'avc'));
      expect(source.primary, contains('/v/120-avc.m4s'));
      expect(source.backups, isEmpty);
    });

    testWidgets('without one, the fixed popular video: its view for the part, then one playurl call', (tester) async {
      final (services, http) = await servicesWith();
      final source = await loadNodeProbeSource(services);
      expect(http.to(Canned.viewPath).single.url.queryParameters['bvid'], nodeProbeFallbackBvid);
      final asked = http.to(Canned.playUrlPath).single.url.queryParameters;
      expect((asked['bvid'], asked['cid']), (nodeProbeFallbackBvid, '137649199'));
      expect((source.fromRecents, source.title), (false, '测试视频'));
    });
  });

  test('URLSession\'s refusals, timeouts and lookups read as dart:io\'s do; other errors as their type', () {
    expect(classifyNodeProbeError(const SocketException('Connection refused')).kind, NodeProbeFailureKind.refused);
    expect(classifyNodeProbeError(StateError('https://x/v.m4s?upsig=1')).toString(), 'StateError');
    expect(nodeProbeFailureLabel(const NodeProbeFailure.status(403)), 'HTTP 403');
    expect(nodeProbeFailureLabel(NodeProbeFailure.timeout), '超时');
    expect((nodeProbeSpeed(3.456), nodeProbeSpeed(12.34)), ('3.46', '12.3'));
  });
}

String? _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(ValueKey(key))).data;

List<String?> _row(WidgetTester tester, String node) {
  final row = tester
      .widgetList<Table>(find.byType(Table))
      .expand((table) => table.children)
      .firstWhere((row) => row.key == ValueKey('node-probe-row-$node'));
  return [for (final cell in row.children) ((cell as Padding).child! as Text).data];
}
