import 'dart:async';
import 'dart:io' show Platform;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/logic.dart' show QualityNames;
import 'package:cupertino_http/cupertino_http.dart' show NSErrorClientException;
import 'package:flutter/widgets.dart';
import 'package:objective_c/objective_c.dart' show NSError$Methods;

import '../app/app_scope.dart';
import '../playback/cupertino_transport.dart';
import '../playback/playback_setup.dart';
import '../settings/settings_page.dart';
import '../shared/theme.dart';
import '../video/player_prefs.dart';

/// Asked when 最近打开 is empty: Rick Astley's official upload, years old and watched everywhere, so every node has its
/// start cached.
const nodeProbeFallbackBvid = 'BV1GJ411x7h7';

/// 1080P: the quality most people play, so its file is the likeliest to be on every node already.
const nodeProbeQuality = 80;

/// The stream every node is asked for. Its signed addresses stay here, in memory, and nothing prints them.
final class NodeProbeSource {
  const NodeProbeSource({
    required this.bvid,
    required this.title,
    required this.fromRecents,
    required this.quality,
    required this.codec,
    required this.primary,
    required this.backups,
  });

  final String bvid;
  final String title;
  final bool fromRecents;
  final int quality;
  final String codec;
  final String primary;
  final List<String> backups;
}

/// Where the card gets its stream and its probe; tests give their own through [NodeProbeScope].
class NodeProbeBackend {
  const NodeProbeBackend({this.load = loadNodeProbeSource, this.probe = platformNodeProbe});

  final Future<NodeProbeSource> Function(AppServices services) load;

  /// A probe for one run; its transport is closed when the run ends.
  final NodeProbe Function() probe;
}

class NodeProbeScope extends InheritedWidget {
  const NodeProbeScope({super.key, required this.backend, required super.child});

  final NodeProbeBackend backend;

  static NodeProbeBackend backendOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<NodeProbeScope>()?.backend ?? const NodeProbeBackend();

  @override
  bool updateShouldNotify(NodeProbeScope oldWidget) => !identical(backend, oldWidget.backend);
}

/// The newest of 最近打开, else [nodeProbeFallbackBvid] (whose part costs a view call first); then the run's one
/// playurl call, and its 1080P stream, AVC when there is one.
Future<NodeProbeSource> loadNodeProbeSource(AppServices services) async {
  final client = services.environment.client;
  final recent = services.recents.items.firstOrNull;
  final (:bvid, :cid, :title) = recent != null
      ? (bvid: recent.bvid, cid: recent.cid, title: recent.title)
      : await _fallbackPart(client);
  final info = await client.playURL(bvid: bvid, cid: cid, quality: nodeProbeQuality);
  final streams = info.dash?.video ?? const <DashStream>[];
  final asked = streams.where((stream) => stream.id == info.quality).toList();
  final pool = asked.isEmpty ? streams : asked;
  final stream = pool.where((stream) => TrackSelector.codecKind(stream) == 'avc').firstOrNull ?? pool.firstOrNull;
  if (stream == null) throw BiliError.notDash;
  return NodeProbeSource(
    bvid: bvid,
    title: title,
    fromRecents: recent != null,
    quality: stream.id,
    codec: TrackSelector.codecKind(stream),
    primary: stream.baseURL,
    backups: stream.backupURLs,
  );
}

Future<({String bvid, int cid, String title})> _fallbackPart(BiliClient client) async {
  final view = await client.view(bvid: nodeProbeFallbackBvid);
  final page = view.pages.firstOrNull;
  if (page == null) throw const BiliError.decoding('no pages');
  return (bvid: view.bvid, cid: page.cid, title: view.title);
}

/// The engine's own transport, as the platform runs it: URLSession on iOS, dart:io elsewhere.
NodeProbe platformNodeProbe() => NodeProbe(
  transport: Platform.isIOS ? createCupertinoTransport() : createIoTransport(),
  classify: classifyNodeProbeError,
);

/// URLSession's errors by their code; its error text carries the address.
NodeProbeFailure classifyNodeProbeError(Object error) => switch (error) {
  NSErrorClientException(error: final cause) => switch (cause.code) {
    -1001 => NodeProbeFailure.timeout,
    -1003 => const NodeProbeFailure(NodeProbeFailureKind.unresolved),
    -1004 => const NodeProbeFailure(NodeProbeFailureKind.refused),
    final code when code <= -1200 && code >= -1206 => const NodeProbeFailure(NodeProbeFailureKind.tls),
    final code => NodeProbeFailure(NodeProbeFailureKind.other, detail: 'URLSession $code'),
  },
  _ => NodeProbeFailure.of(error),
};

enum NodeProbePhase { idle, loading, probing, done, stopped, failed }

/// One run at a time: the stream, then every node in turn, until done or stopped.
class NodeProbeModel extends ChangeNotifier {
  NodeProbeModel({required this._services, this._backend = const NodeProbeBackend(), Logger? logger})
    : _logger = logger ?? Logger.shared;

  final AppServices _services;
  final NodeProbeBackend _backend;
  final Logger _logger;

  NodeProbePhase _phase = NodeProbePhase.idle;
  NodeProbeSource? _source;
  List<NodeProbeTarget> _targets = const [];
  final _results = <NodeProbeResult>[];
  String? _error;
  CancelToken? _cancel;
  bool _disposed = false;

  NodeProbePhase get phase => _phase;
  NodeProbeSource? get source => _source;
  List<NodeProbeTarget> get targets => _targets;
  List<NodeProbeResult> get results => List.unmodifiable(_results);
  String? get error => _error;
  bool get running => _phase == NodeProbePhase.loading || _phase == NodeProbePhase.probing;
  NodeProbeSummary get summary => NodeProbeSummary.of(_results);

  /// The node being asked now, while probing.
  NodeProbeTarget? get current =>
      _phase == NodeProbePhase.probing && _results.length < _targets.length ? _targets[_results.length] : null;

  Future<void> start() async {
    if (running || _disposed) return;
    final cancel = _cancel = CancelToken();
    _phase = NodeProbePhase.loading;
    _source = null;
    _targets = const [];
    _results.clear();
    _error = null;
    _notify();
    NodeProbe? probe;
    try {
      final source = await cancel.guard(_backend.load(_services));
      _source = source;
      probe = _backend.probe();
      final targets = _targets = probe.targets(primary: source.primary, backups: source.backups);
      if (targets.isEmpty) {
        _fail('这个视频没有可测的地址');
        return;
      }
      _phase = NodeProbePhase.probing;
      _notify();
      _logger.info(LogCategory.app, 'node probe start', {
        'bvid': source.bvid,
        'recent': source.fromRecents,
        'quality': source.quality,
        'codec': source.codec,
        'nodes': targets.length,
      });
      await for (final result in probe.run(targets, cancel: cancel)) {
        _results.add(result);
        _notify();
      }
      _phase = cancel.isCancelled ? NodeProbePhase.stopped : NodeProbePhase.done;
      _logDone();
    } on CancelledException {
      _phase = NodeProbePhase.stopped;
    } catch (error) {
      // A transport's error text can carry the signed address; Bilibili's own errors don't.
      _logger.warn(LogCategory.app, 'node probe failed', {'error': error is BiliError ? '$error' : '${error.runtimeType}'});
      _fail(error is BiliError ? error.userMessage : '取视频地址失败');
    } finally {
      probe?.transport.close();
      cancel.dispose();
      if (identical(_cancel, cancel)) _cancel = null;
      _notify();
    }
  }

  void stop() => _cancel?.cancel();

  void _fail(String message) {
    _phase = NodeProbePhase.failed;
    _error = message;
  }

  void _logDone() {
    final summary = this.summary;
    String speed(NodeGroup group) => summary.medianMbps[group]?.toStringAsFixed(2) ?? '-';
    _logger.info(LogCategory.app, 'node probe done', {
      'cancelled': _phase == NodeProbePhase.stopped,
      'mainlandMedianMbps': speed(NodeGroup.mainland),
      'overseasMedianMbps': speed(NodeGroup.overseas),
      'mainlandAnswered': summary.answered[NodeGroup.mainland]!,
      'overseasAnswered': summary.answered[NodeGroup.overseas]!,
      'fastest': summary.fastest?.node ?? '-',
      'faster': summary.faster?.name ?? '-',
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}

String nodeGroupLabel(NodeGroup group) => switch (group) {
  NodeGroup.mainland => '国内',
  NodeGroup.overseas => '海外',
};

NodeChoice nodeChoiceOf(NodeGroup group) => group == NodeGroup.mainland ? NodeChoice.mainland : NodeChoice.overseas;

String nodeProbeFailureLabel(NodeProbeFailure failure) => switch (failure.kind) {
  NodeProbeFailureKind.timeout => '超时',
  NodeProbeFailureKind.status => 'HTTP ${failure.status}',
  NodeProbeFailureKind.refused => '拒绝连接',
  NodeProbeFailureKind.unresolved => '解析失败',
  NodeProbeFailureKind.tls => 'TLS 失败',
  NodeProbeFailureKind.network => '网络错误',
  NodeProbeFailureKind.other => '出错',
};

String nodeProbeSpeed(double mbps) => mbps < 10 ? mbps.toStringAsFixed(2) : mbps.toStringAsFixed(1);

/// 设置 → CDN 节点's choice for the faster group, beside the one set now.
String nodeProbeSuggestion(NodeProbeSummary summary, NodeChoice current) {
  final faster = summary.faster;
  if (faster == null) return '两组都没测通，给不出建议';
  final choice = nodeChoiceOf(faster);
  return choice == current
      ? '建议：设置 → CDN 节点 选「${choice.label}」（现在就是）'
      : '建议：设置 → CDN 节点 改选「${choice.label}」（现在是「${current.label}」）';
}

/// 开发者's 节点测速 card: each CDN node's first byte and speed on the same range, grouped 国内 / 海外.
class NodeProbeSection extends StatefulWidget {
  const NodeProbeSection({super.key});

  @override
  State<NodeProbeSection> createState() => _NodeProbeSectionState();
}

class _NodeProbeSectionState extends State<NodeProbeSection> {
  NodeProbeModel? _model;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _model ??= NodeProbeModel(services: AppScope.of(context), backend: NodeProbeScope.backendOf(context));
  }

  @override
  void dispose() {
    _model?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = _model!;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => SettingsSection(
        key: const ValueKey('node-probe'),
        children: [
          SettingsRow(
            key: ValueKey(model.running ? 'node-probe-stop' : 'node-probe-start'),
            title: '节点测速',
            value: model.running ? '停止' : '开始测速',
            valueColor: model.running ? NodeProbeTheme.stop : NodeProbeTheme.action,
            onTap: model.running ? model.stop : () => unawaited(model.start()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NodeProbeTheme.inset,
              NodeProbeTheme.top,
              NodeProbeTheme.inset,
              NodeProbeTheme.bottom,
            ),
            child: _Body(model: model, current: PlayerPrefs.shared.node),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.model, required this.current});

  final NodeProbeModel model;
  final NodeChoice current;

  static TextStyle style({Color color = NodeProbeTheme.secondary, double size = NodeProbeTheme.noteText}) =>
      TextStyle(fontFamily: BiliFonts.family, fontSize: size, color: color);

  String get _status {
    final done = model.results.length;
    final total = model.targets.length;
    return switch (model.phase) {
      NodeProbePhase.idle => '同一段视频（前 4 MB）依次向每个节点要一遍',
      NodeProbePhase.loading => '正在取视频地址…',
      NodeProbePhase.probing => '正在测 ${model.current?.name ?? ''}（${done + 1}/$total）',
      NodeProbePhase.done => '测完 $total 个节点',
      NodeProbePhase.stopped => total == 0 ? '已停止' : '已停止，测了 $done/$total 个',
      NodeProbePhase.failed => model.error ?? '出错了',
    };
  }

  @override
  Widget build(BuildContext context) {
    final source = model.source;
    final results = model.results;
    final summary = model.summary;
    final fastest = summary.fastest;
    final cut = results.any((result) => result.ok && !result.complete);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: NodeProbeTheme.lineGap,
      children: [
        Text(
          _status,
          key: const ValueKey('node-probe-status'),
          style: style(color: model.phase == NodeProbePhase.failed ? NodeProbeTheme.error : NodeProbeTheme.secondary),
        ),
        if (source != null)
          Text(
            '${source.fromRecents ? '最近打开' : '热门视频'}：${source.title} · '
            '${QualityNames.short(qn: source.quality, serverText: null)} · ${source.codec.toUpperCase()}',
            key: const ValueKey('node-probe-video'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style(),
          ),
        for (final group in NodeGroup.values)
          if (results.any((result) => result.group == group))
            _GroupTable(
              group: group,
              results: [for (final result in results) if (result.group == group) result],
              summary: summary,
            ),
        if (fastest != null)
          Text(
            '最快：${fastest.name}（${nodeGroupLabel(fastest.group)}）${nodeProbeSpeed(fastest.mbps!)} MB/s',
            key: const ValueKey('node-probe-fastest'),
            style: style(color: NodeProbeTheme.text),
          ),
        if (model.phase == NodeProbePhase.done)
          Text(
            nodeProbeSuggestion(summary, current),
            key: const ValueKey('node-probe-suggestion'),
            style: style(color: NodeProbeTheme.text),
          ),
        if (cut) Text('* 8 秒内没下完，按已下的算', style: style()),
      ],
    );
  }
}

class _GroupTable extends StatelessWidget {
  const _GroupTable({required this.group, required this.results, required this.summary});

  final NodeGroup group;
  final List<NodeProbeResult> results;
  final NodeProbeSummary summary;

  @override
  Widget build(BuildContext context) {
    final median = summary.medianMbps[group];
    final header = TextStyle(
      fontFamily: BiliFonts.family,
      fontSize: NodeProbeTheme.groupText,
      fontWeight: NodeProbeTheme.groupWeight,
      color: NodeProbeTheme.text,
    );
    TextStyle cell(Color color) =>
        TextStyle(fontFamily: BiliFonts.family, fontSize: NodeProbeTheme.tableText, color: color);
    final fastest = summary.fastest;
    return Padding(
      padding: const EdgeInsets.only(top: NodeProbeTheme.groupGap - NodeProbeTheme.lineGap),
      child: Column(
        key: ValueKey('node-probe-${group.name}'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${nodeGroupLabel(group)}  中位 ${median == null ? '–' : '${nodeProbeSpeed(median)} MB/s'}'
            '  ${summary.answered[group]}/${summary.asked[group]} 通',
            key: ValueKey('node-probe-${group.name}-median'),
            style: header,
          ),
          const SizedBox(height: NodeProbeTheme.rowGap),
          Table(
            columnWidths: const {0: FlexColumnWidth(), 1: IntrinsicColumnWidth(), 2: IntrinsicColumnWidth()},
            defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              _row(const ['节点', '首字节', 'MB/s'], cell(NodeProbeTheme.secondary)),
              for (final result in results)
                _row(
                  _cells(result),
                  cell(
                    !result.ok
                        ? NodeProbeTheme.failed
                        : (identical(result, fastest) ? NodeProbeTheme.fastest : NodeProbeTheme.text),
                  ),
                  key: ValueKey('node-probe-row-${result.node}'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// A failure stands where its number would: in 首字节 when no answer came, else in MB/s.
  static List<String> _cells(NodeProbeResult result) {
    final failure = result.failure;
    final firstByte = result.firstByteMs;
    final mbps = result.mbps;
    String failed() => failure == null ? '–' : nodeProbeFailureLabel(failure);
    return [
      result.name,
      firstByte == null ? failed() : '${firstByte.round()} ms',
      mbps != null ? '${nodeProbeSpeed(mbps)}${result.complete ? '' : '*'}' : (firstByte == null ? '–' : failed()),
    ];
  }

  static TableRow _row(List<String> cells, TextStyle style, {LocalKey? key}) => TableRow(
    key: key,
    children: [
      for (final (index, text) in cells.indexed)
        Padding(
          padding: EdgeInsets.only(left: index == 0 ? 0 : NodeProbeTheme.columnGap, bottom: NodeProbeTheme.rowGap),
          child: Text(text, textAlign: index == 0 ? TextAlign.start : TextAlign.end, style: style),
        ),
    ],
  );
}
