import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_core/engine.dart';
import 'package:bilifast/devtools/log_server_discovery.dart';
import 'package:bilifast/playback/playback_setup.dart';
import 'package:bilifast/speedtest/speed_test_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_target.dart';

const server = LogServerEndpoint(name: 'pc', host: '10.0.0.2', port: 47321);

void main() {
  SpeedTestPlan parse(Map<String, Object?> changes, {ConfigCheck check = acceptAll}) =>
      SpeedTestPlan.parse(jsonEncode({...smallPlan, ...changes}), check: check);

  void refuses(Object? json, String saying, {ConfigCheck check = acceptAll}) => expect(
        () => SpeedTestPlan.parse(json is String ? json : jsonEncode(json), check: check),
        throwsA(isA<SpeedTestPlanError>().having((error) => error.message, 'message', contains(saying))),
      );

  test('a plan parses, and the optional numbers default to the built-in plan\'s', () {
    final plan = parse(const {});
    expect(plan.id, 'test-1');
    expect(plan.qualities, [120]);
    expect(plan.variants.map((variant) => (variant.name, variant.connectionsPerHost)), [('A', 8), ('B', 4)]);
    expect(plan.variant('B')!.overrides, {'peakBandwidth': true});
    expect((plan.seeks, plan.hints, plan.backJumps), (2, 1, 1));

    final bare = SpeedTestPlan.parse(
        jsonEncode({
          'id': 'bare',
          'qualities': [80],
          'variants': [
            {'name': 'A'},
          ],
          'order': 'A',
        }),
        check: acceptAll);
    expect(bare.videos, isEmpty);
    expect(bare.variants.single.connectionsPerHost, 8);
    expect(bare.variants.single.overrides, isEmpty);
    expect((bare.seeks, bare.hints, bare.backJumps, bare.dwellSeconds, bare.fastSeconds, bare.fastRate),
        (8, 2, 2, 3.0, 20.0, 2.0));
  });

  test('passes go video by video, quality by quality, letter by letter, counting each letter\'s repeats', () {
    final plan = parse(const {
      'qualities': [127, 120],
    });
    final passes = plan.passes(['BV1', 'BV2']);
    expect(passes, hasLength(16));
    expect(passes.map((pass) => pass.index), [for (var i = 1; i <= 16; i++) i]);
    expect(passes.take(8).map((pass) => '${pass.video} ${pass.quality} ${pass.variant.name}${pass.repeat}'), [
      'BV1 127 A0',
      'BV1 127 B0',
      'BV1 127 B1',
      'BV1 127 A1',
      'BV1 120 A0',
      'BV1 120 B0',
      'BV1 120 B1',
      'BV1 120 A1',
    ]);
    expect(passes.last.videoIndex, 1);
    expect(passes.where((pass) => pass.cold).map((pass) => pass.index), [1, 5, 9, 13],
        reason: 'the first pass on each video at each quality');
    expect(plan.rotate, isFalse);
  });

  test('rotate starts each video one letter further along, so every variant gets a cold pass at every quality', () {
    final plan = parse(const {'order': 'AB', 'rotate': true, 'qualities': [127, 120]});
    final passes = plan.passes(['BV1', 'BV2']);
    expect(passes.map((pass) => '${pass.variant.name}${pass.cold ? '*' : ''}').join(' '), 'A* B A* B B* A B* A');
    expect(passes.map((pass) => pass.repeat), everyElement(0));
    refuses({...smallPlan, 'rotate': 'yes'}, 'rotate');
  });

  test('anything off refuses the plan with what was wrong', () {
    refuses('{not json', '不是有效的 JSON');
    refuses([1, 2], 'JSON 对象');
    refuses({...smallPlan, 'seek': 3}, '未知字段：seek');
    refuses({...smallPlan, 'order': 'ABC'}, '不存在的方案：C');
    refuses({...smallPlan, 'qualities': ['127']}, 'qualities');
    refuses({...smallPlan, 'qualities': <int>[]}, 'qualities 不能为空');
    refuses({...smallPlan, 'seeks': -1}, 'seeks');
    refuses({...smallPlan, 'dwellSeconds': '3'}, 'dwellSeconds');
    refuses({...smallPlan, 'fastRate': 0}, 'fastRate');
    refuses({...smallPlan, 'id': ''}, 'id');
    refuses({...smallPlan, 'videos': [42]}, 'videos');
    refuses({
      ...smallPlan,
      'variants': [
        {'name': 'AB'},
      ],
    }, '一个字母');
    refuses({
      ...smallPlan,
      'variants': [
        {'name': 'A'},
        {'name': 'A'},
      ],
    }, '不能重复');
    refuses({
      ...smallPlan,
      'variants': [
        {'name': 'A', 'cfg': <String, Object?>{}},
      ],
    }, 'variants[0] 有未知字段：cfg');
    refuses({
      ...smallPlan,
      'variants': [
        {'name': 'A', 'connectionsPerHost': 0},
      ],
    }, 'connectionsPerHost');
  });

  test('a config name the engine does not know refuses the plan and names it', () {
    refuses({
      ...smallPlan,
      'variants': [
        {
          'name': 'B',
          'config': {'hurryKeepOffSlow': true, 'seekBurst': 'yes'},
        },
      ],
      'order': 'B',
    }, '方案 B 的 config 有引擎不认识或类型不对的项：hurryKeepOffSlow, seekBurst', check: appConfigCheck);

    final plan = parse({
      'variants': [
        {
          'name': 'A',
          'config': {'seekBurst': false, 'firstByteTimeoutMs': 900},
        },
      ],
      'order': 'A',
    }, check: appConfigCheck);
    final config = plan.variants.single.config;
    expect(config.seekBurst, isFalse);
    expect(config.firstByteTimeoutMs, 900);
    expect(config.primeStart, isTrue, reason: 'the rest is the app\'s config');
  });

  test('the built-in plan is the one in tools/speedtest_plan.json: A, B and D in ABD, rotated, at 8K', () {
    final file = File('tools/speedtest_plan.json').readAsStringSync();
    expect(jsonDecode(file), jsonDecode(SpeedTestPlan.builtinJson));
    final plan = SpeedTestPlan.parse(SpeedTestPlan.builtinJson);
    expect(plan.variant('D')!.config.hurryPieceBytes, 192 * 1024);
    expect(plan.variant('B')!.config.hurryKeepsOffSlow, isTrue);
    expect(plan.variant('A')!.config.toJson(), appRipperConfig.toJson());
    expect(plan.id, 'builtin-2');
    expect(plan.qualities, [127]);
    expect((plan.order, plan.rotate), ('ABD', true));
    expect(plan.variants.map((variant) => (variant.name, variant.connectionsPerHost)), [('A', 8), ('B', 8), ('D', 8)]);
    expect(plan.variant('A')!.overrides, isEmpty);
    expect(plan.variant('D')!.overrides, {...plan.variant('B')!.overrides, 'hurryPieceBytes': 196608});
    final passes = plan.passes(['BV1', 'BV2', 'BV3']);
    expect(passes.where((pass) => pass.cold).map((pass) => pass.variant.name), ['A', 'B', 'D']);
  });

  group('choosing the plan', () {
    Future<PlanChoice> choose(PlanGet get, {LogServerEndpoint? at = server, Duration? timeout}) =>
        choosePlan(at, get: get, check: acceptAll, timeout: timeout ?? const Duration(seconds: 2));

    PlanGet answering(int status, String body, {List<Uri>? asked}) => (url) async {
          asked?.add(url);
          return (status: status, body: body);
        };

    test('the PC\'s plan when it serves one', () async {
      final asked = <Uri>[];
      final choice = await choose(answering(200, jsonEncode(smallPlan), asked: asked));
      expect(asked.single.toString(), 'http://10.0.0.2:47321/plan');
      expect(choice.source, PlanSource.pc);
      expect(choice.plan.id, 'test-1');
    });

    test('the built-in plan without a PC, on a 404, another status, an error or no answer in time', () async {
      final none = await choose(answering(200, ''), at: null);
      expect((none.source, none.note, none.plan.id), (PlanSource.builtin, '没有连接电脑', 'builtin-2'));
      expect((await choose(answering(404, 'not found'))).note, '电脑上没有计划');
      expect((await choose(answering(500, ''))).note, '电脑回答 500');
      final unreachable = await choose((url) async => throw const SocketException('refused'));
      expect(unreachable.source, PlanSource.builtin);
      expect(unreachable.note, startsWith('连不上电脑'));
      final silent = await choose((url) => Completer<({int status, String body})>().future,
          timeout: const Duration(milliseconds: 20));
      expect(silent.note, '连不上电脑（超时）');
    });

    test('a plan from the PC that does not parse is refused, not replaced', () async {
      await expectLater(choose(answering(200, '{"id": "x"}')), throwsA(isA<SpeedTestPlanError>()));
    });

    test('httpGet reads status and body from a server on this machine', () async {
      final local = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => local.close(force: true));
      local.listen((request) {
        request.response
          ..statusCode = request.uri.path == '/plan' ? 200 : 404
          ..write(request.uri.path == '/plan' ? '{"id":"计划"}' : 'not found');
        unawaited(request.response.close());
      });
      final ok = await httpGet(Uri.parse('http://127.0.0.1:${local.port}/plan'));
      expect((ok.status, ok.body), (200, '{"id":"计划"}'));
      final missing = await httpGet(Uri.parse('http://127.0.0.1:${local.port}/other'));
      expect(missing.status, 404);
    });
  });

  test('a variant\'s config is the app\'s config with its overrides', () {
    final plan = parse(const {}, check: (overrides) => const RipperConfig(seekBurst: true).withOverrides(overrides));
    expect(plan.variant('B')!.config.peakBandwidth, isTrue);
    expect(plan.variant('B')!.config.seekBurst, isTrue);
    expect(plan.variant('A')!.config.peakBandwidth, isFalse);
  });
}
