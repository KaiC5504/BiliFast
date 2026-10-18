import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_core/engine.dart';

import '../devtools/log_server_discovery.dart';
import '../playback/playback_setup.dart';

/// Checks a variant's engine overrides; [RipperConfig.withOverrides] on the app's config in the app.
typedef ConfigCheck = ({RipperConfig config, List<String> rejected}) Function(Map<String, Object?> overrides);

({RipperConfig config, List<String> rejected}) appConfigCheck(Map<String, Object?> overrides) =>
    appRipperConfig.withOverrides(overrides);

final class SpeedTestPlanError implements Exception {
  const SpeedTestPlanError(this.message);

  final String message;

  @override
  String toString() => message;
}

final class SpeedTestVariant {
  const SpeedTestVariant({
    required this.name,
    required this.overrides,
    required this.config,
    required this.connectionsPerHost,
  });

  /// One letter, as `order` names it.
  final String name;

  /// What the plan changes from the app's config, as given.
  final Map<String, Object?> overrides;
  final RipperConfig config;
  final int connectionsPerHost;
}

final class SpeedTestPass {
  const SpeedTestPass({
    required this.index,
    required this.video,
    required this.videoIndex,
    required this.quality,
    required this.variant,
    required this.repeat,
    required this.cold,
  });

  /// From 1.
  final int index;
  final String video;
  final int videoIndex;
  final int quality;
  final SpeedTestVariant variant;

  /// How many times this variant came earlier in `order`: ABBA's second A is 1.
  final int repeat;

  /// The first pass on its video at its quality: the CDN may not have that file yet. In 1.0.0 (2)'s run every first
  /// pass seeked in 5-15 s and every later one, wherever it seeked, in about 0.3 s.
  final bool cold;
}

final class SpeedTestPlan {
  const SpeedTestPlan({
    required this.id,
    required this.videos,
    required this.qualities,
    required this.variants,
    required this.order,
    this.rotate = false,
    required this.seeks,
    required this.hints,
    required this.backJumps,
    required this.dwellSeconds,
    required this.fastSeconds,
    required this.fastRate,
  });

  final String id;
  final List<String> videos;
  final List<int> qualities;
  final List<SpeedTestVariant> variants;
  final String order;

  /// Each video starts [order] one letter further along, at every quality alike, so the cold first pass falls on every
  /// variant in turn rather than always on the first.
  final bool rotate;
  final int seeks;
  final int hints;
  final int backJumps;
  final double dwellSeconds;
  final double fastSeconds;
  final double fastRate;

  /// The plan used when the PC has none; `tools/speedtest_plan.json` holds the same.
  static const builtinJson = '''
{"id": "builtin-3", "videos": [], "qualities": [127],
 "variants": [{"name": "A", "config": {}, "connectionsPerHost": 8},
              {"name": "D", "config": {"hurryPieceBytes": 196608}, "connectionsPerHost": 8}],
 "order": "AD", "rotate": true, "seeks": 8, "hints": 2, "backJumps": 2, "dwellSeconds": 3, "fastSeconds": 20, "fastRate": 2}
''';

  static const _keys = {
    'id',
    'videos',
    'qualities',
    'variants',
    'order',
    'rotate',
    'seeks',
    'hints',
    'backJumps',
    'dwellSeconds',
    'fastSeconds',
    'fastRate',
  };
  static const _variantKeys = {'name', 'config', 'connectionsPerHost'};

  SpeedTestVariant? variant(String name) => variants.where((variant) => variant.name == name).firstOrNull;

  /// For each video, each quality, each letter of [order] ([rotate]d one further for each video).
  List<SpeedTestPass> passes(List<String> videos) {
    final passes = <SpeedTestPass>[];
    final letters = order.split('');
    for (final (videoIndex, video) in videos.indexed) {
      final shift = rotate ? videoIndex % letters.length : 0;
      for (final quality in qualities) {
        final seen = <String, int>{};
        for (final (position, letter) in [...letters.skip(shift), ...letters.take(shift)].indexed) {
          final repeat = seen[letter] ?? 0;
          seen[letter] = repeat + 1;
          passes.add(SpeedTestPass(
            index: passes.length + 1,
            video: video,
            videoIndex: videoIndex,
            quality: quality,
            variant: variant(letter)!,
            repeat: repeat,
            cold: position == 0,
          ));
        }
      }
    }
    return passes;
  }

  /// Strict, so a typo never quietly tests something else: unknown keys, wrong types, an order naming a variant
  /// that isn't there, or a config name the engine doesn't know refuse the plan. Throws [SpeedTestPlanError].
  static SpeedTestPlan parse(String text, {ConfigCheck check = appConfigCheck}) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (error) {
      throw SpeedTestPlanError('计划不是有效的 JSON：${error.message}');
    }
    if (json is! Map<String, Object?>) throw const SpeedTestPlanError('计划必须是一个 JSON 对象');
    final unknown = json.keys.where((key) => !_keys.contains(key)).toList();
    if (unknown.isNotEmpty) throw SpeedTestPlanError('计划有未知字段：${unknown.join(', ')}');

    final id = _string(json, 'id');
    final videos = _list(json, 'videos', fallback: const []).map((video) {
      if (video is! String || video.trim().isEmpty) throw const SpeedTestPlanError('videos 里每项都必须是链接文字');
      return video.trim();
    }).toList();
    final qualities = _list(json, 'qualities').map((quality) {
      if (quality is! int || quality <= 0) throw const SpeedTestPlanError('qualities 里每项都必须是正整数');
      return quality;
    }).toList();
    if (qualities.isEmpty) throw const SpeedTestPlanError('qualities 不能为空');

    final variants = <SpeedTestVariant>[];
    for (final (index, raw) in _list(json, 'variants').indexed) {
      variants.add(_variant(raw, index, check));
    }
    if (variants.isEmpty) throw const SpeedTestPlanError('variants 不能为空');
    final names = variants.map((variant) => variant.name).toList();
    if (names.toSet().length != names.length) throw const SpeedTestPlanError('variants 的 name 不能重复');

    final order = _string(json, 'order');
    final missing = order.split('').where((letter) => !names.contains(letter)).toSet();
    if (missing.isNotEmpty) throw SpeedTestPlanError('order 里有不存在的方案：${missing.join(', ')}');

    final rotate = json['rotate'] ?? false;
    if (rotate is! bool) throw const SpeedTestPlanError('rotate 必须是 true 或 false');
    final fastRate = _number(json, 'fastRate', fallback: 2);
    if (fastRate <= 0) throw const SpeedTestPlanError('fastRate 必须大于 0');
    return SpeedTestPlan(
      id: id,
      videos: videos,
      qualities: qualities,
      variants: variants,
      order: order,
      rotate: rotate,
      seeks: _count(json, 'seeks', fallback: 8),
      hints: _count(json, 'hints', fallback: 2),
      backJumps: _count(json, 'backJumps', fallback: 2),
      dwellSeconds: _number(json, 'dwellSeconds', fallback: 3),
      fastSeconds: _number(json, 'fastSeconds', fallback: 20),
      fastRate: fastRate,
    );
  }

  static SpeedTestVariant _variant(Object? raw, int index, ConfigCheck check) {
    final where = 'variants[$index]';
    if (raw is! Map<String, Object?>) throw SpeedTestPlanError('$where 必须是对象');
    final unknown = raw.keys.where((key) => !_variantKeys.contains(key)).toList();
    if (unknown.isNotEmpty) throw SpeedTestPlanError('$where 有未知字段：${unknown.join(', ')}');
    final name = raw['name'];
    if (name is! String || name.length != 1) throw SpeedTestPlanError('$where 的 name 必须是一个字母');
    final overrides = raw['config'] ?? const <String, Object?>{};
    if (overrides is! Map<String, Object?>) throw SpeedTestPlanError('方案 $name 的 config 必须是对象');
    final perHost = raw['connectionsPerHost'] ?? 8;
    if (perHost is! int || perHost <= 0) throw SpeedTestPlanError('方案 $name 的 connectionsPerHost 必须是正整数');
    final checked = check(overrides);
    if (checked.rejected.isNotEmpty) {
      throw SpeedTestPlanError('方案 $name 的 config 有引擎不认识或类型不对的项：${checked.rejected.join(', ')}');
    }
    return SpeedTestVariant(
        name: name, overrides: Map.unmodifiable(overrides), config: checked.config, connectionsPerHost: perHost);
  }

  static String _string(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) throw SpeedTestPlanError('$key 必须是非空文字');
    return value;
  }

  static List<Object?> _list(Map<String, Object?> json, String key, {List<Object?>? fallback}) {
    final value = json[key] ?? fallback;
    if (value is! List<Object?>) throw SpeedTestPlanError('$key 必须是列表');
    return value;
  }

  static int _count(Map<String, Object?> json, String key, {required int fallback}) {
    final value = json[key] ?? fallback;
    if (value is! int || value < 0) throw SpeedTestPlanError('$key 必须是不小于 0 的整数');
    return value;
  }

  static double _number(Map<String, Object?> json, String key, {required double fallback}) {
    final value = json[key] ?? fallback;
    if (value is! num || value < 0) throw SpeedTestPlanError('$key 必须是不小于 0 的数');
    return value.toDouble();
  }
}

enum PlanSource { pc, builtin }

/// The plan to run and where it came from; [note] says why the built-in one was used.
final class PlanChoice {
  const PlanChoice({required this.plan, required this.source, required this.note});

  final SpeedTestPlan plan;
  final PlanSource source;
  final String note;
}

/// One GET; answers the status and body, or throws when the PC can't be reached.
typedef PlanGet = Future<({int status, String body})> Function(Uri url);

/// `GET /plan` from the PC's log server, when the log forwarder points at one: 200 is the plan, 404 or no answer
/// within [timeout] means the built-in plan. A plan the PC serves that doesn't parse is refused (throws
/// [SpeedTestPlanError]) rather than replaced, since the PC asked for it.
Future<PlanChoice> choosePlan(
  LogServerEndpoint? server, {
  PlanGet get = httpGet,
  ConfigCheck check = appConfigCheck,
  Duration timeout = const Duration(seconds: 2),
}) async {
  PlanChoice builtin(String note) =>
      PlanChoice(plan: SpeedTestPlan.parse(SpeedTestPlan.builtinJson, check: check), source: PlanSource.builtin, note: note);
  if (server == null) return builtin('没有连接电脑');
  final url = Uri(scheme: 'http', host: server.host, port: server.port, path: '/plan');
  final ({int status, String body}) answer;
  try {
    answer = await get(url).timeout(timeout);
  } on Object catch (error) {
    return builtin('连不上电脑（${error is TimeoutException ? '超时' : error.runtimeType}）');
  }
  if (answer.status == 404) return builtin('电脑上没有计划');
  if (answer.status != 200) return builtin('电脑回答 ${answer.status}');
  return PlanChoice(plan: SpeedTestPlan.parse(answer.body, check: check), source: PlanSource.pc, note: '电脑上的计划');
}

Future<({int status, String body})> httpGet(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return (status: response.statusCode, body: body);
  } finally {
    client.close(force: true);
  }
}
