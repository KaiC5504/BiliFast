import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:bili_core/danmaku.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../../app/form_factor.dart';
import '../../danmaku/block_rule_store.dart';
import '../../danmaku/danmaku_scene.dart';
import '../../danmaku/danmaku_settings.dart';
import '../../device/orientation.dart';
import '../room/live_room_model.dart';

/// The danmaku flying over the video (208), from [room]'s feed, drawn by the video page's danmaku painter under the
/// shared 弹幕设置 and 屏蔽词; nothing while [on] is false.
///
/// Live has no timeline to follow, so the layer keeps its own clock: frame time while anything is on screen, standing
/// still while the ticker sleeps. Each danmaku enters the scene's timeline a millisecond after the last frame, and the
/// scene hands it out on the next. Emotes fly as their text: the scene's sprites only lay out text.
class LiveDanmakuLayer extends StatefulWidget {
  const LiveDanmakuLayer({super.key, required this.room, required this.on});

  final LiveRoomModel room;
  final bool on;

  @override
  State<LiveDanmakuLayer> createState() => LiveDanmakuLayerState();
}

class LiveDanmakuLayerState extends State<LiveDanmakuLayer> with SingleTickerProviderStateMixin {
  /// The timeline is started afresh past this many, keeping only the last [_keepMs]: the scene's look-back for a re-lay
  /// is twice the slowest crossing (11 s), so nothing still flying is lost.
  static const _rotateAt = 600;
  static const _keepMs = 30000;

  /// 合并重复 has no later danmaku to count against a live one already flying, so a repeat within this is dropped.
  static const _repeatMs = 10000;

  final _scene = DanmakuScene();
  late final Ticker _ticker = createTicker(_tick);
  DanmakuTimeline _timeline = DanmakuTimeline();
  final List<DisplayDanmaku> _entered = [];
  final Map<String, int> _lastSeen = {};
  StreamSubscription<LiveChatMessage>? _feed;

  ValueListenable<DanmakuSettings>? _settings;
  BlockRuleStore? _blockRules;
  int Function() _ownUid = () => 0;
  DanmakuOptions _options = const DanmakuOptions();
  Presentation _presentation = Presentation.inline;

  /// The layer's clock, in seconds: the last frame's, held while the ticker sleeps.
  double _seconds = 0;
  bool _tickerEnabled = true;
  double _base = 0;
  int _lastMs = 0;

  @visibleForTesting
  DanmakuScene get scene => _scene;

  @visibleForTesting
  bool get ticking => _ticker.isActive;

  @visibleForTesting
  DanmakuOptions get options => _options;

  /// Danmaku the timeline holds (tests).
  @visibleForTesting
  int get held => _entered.length;

  @override
  void initState() {
    super.initState();
    if (widget.on) _listen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (!identical(services.danmakuSettings, _settings)) {
      _settings?.removeListener(_settingsChanged);
      _settings = services.danmakuSettings..addListener(_settingsChanged);
    }
    if (!identical(services.blockRules, _blockRules)) {
      _blockRules = services.blockRules;
      // Fetched by the first page that needs them, kept for ten minutes.
      unawaited(services.blockRules.refresh());
    }
    _ownUid = () => services.environment.mid ?? 0;
    // A muted ticker's elapsed time runs on; restarting it from the held clock keeps a paused picture's danmaku where
    // they stopped.
    final enabled = TickerMode.valuesOf(context).enabled;
    if (enabled && !_tickerEnabled && _ticker.isActive) {
      _ticker.stop();
      _base = _seconds;
      _ticker.start();
    }
    _tickerEnabled = enabled;
    final size = MediaQuery.sizeOf(context);
    // Full screen is the phone turned: laid out by the screen's shape, as the video page is.
    _presentation = size.width > size.height ? Presentation.landscape : Presentation.inline;
    // The build that follows takes a new opacity.
    _settingsChanged(rebuild: false);
  }

  @override
  void didUpdateWidget(LiveDanmakuLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.on == widget.on && identical(oldWidget.room, widget.room)) return;
    _stop();
    if (widget.on) _listen();
  }

  @override
  void dispose() {
    _settings?.removeListener(_settingsChanged);
    unawaited(_feed?.cancel());
    _ticker.dispose();
    _scene.dispose();
    super.dispose();
  }

  void _listen() => _feed = widget.room.flying.listen(_enter);

  /// Off: what is flying goes, and nothing is kept for later.
  void _stop() {
    unawaited(_feed?.cancel());
    _feed = null;
    _ticker.stop();
    _scene.reset();
    _timeline = DanmakuTimeline();
    _entered.clear();
    _lastSeen.clear();
  }

  void _settingsChanged({bool rebuild = true}) {
    final settings = _settings?.value ?? const DanmakuSettings();
    final options = settings.display(presentation: _presentation, formFactor: FormFactor.device);
    if (options == _options) return;
    final faded = options.opacity != _options.opacity;
    _options = options;
    if (faded && rebuild) setState(() {});
    _wake();
  }

  void _enter(LiveChatMessage message) {
    // A covered page's frames stop; what arrives meanwhile would only pile up behind its clock.
    if (!widget.on || _ticker.muted) return;
    final text = message.bigEmote != null && message.text.isEmpty ? message.bigEmote!.text : message.text;
    if (text.trim().isEmpty) return;
    final settings = _settings?.value ?? const DanmakuSettings();
    final ms = _lastMs + 1;
    final uid = message.user.uid;
    final own = uid != 0 && uid == _ownUid();
    final elem = DanmakuElem(
      progressMs: ms,
      mode: message.mode,
      color: message.color & 0xFFFFFF,
      midHash: uid == 0 ? '' : MidHash.of(uid),
      content: text,
      idStr: message.id,
    );
    final passed = DanmakuFilter.apply(
      [elem],
      options: settings.filter.copyWith(dedupe: false, blockCount: false),
      rules: _blockRules?.rules ?? const [],
      ownHash: own ? elem.midHash : null,
    );
    if (passed.isEmpty) return;
    if (!own && (settings.filter.dedupe || settings.filter.blockCount)) {
      final last = _lastSeen[text];
      _lastSeen[text] = ms;
      if (last != null && ms - last <= _repeatMs) return;
    }
    _entered.addAll(passed);
    _timeline.add(passed);
    if (_entered.length > _rotateAt) _rotate();
    _wake();
  }

  /// A fresh timeline with the last moments only. The scene re-lays from it as from a seek, each danmaku at its own
  /// start, so what is flying carries on where it was.
  void _rotate() {
    final keepFrom = _lastMs - _keepMs;
    final kept = _entered.where((danmaku) => danmaku.elem.progressMs >= keepFrom).toList();
    final recent = kept.length > _rotateAt ~/ 2 ? kept.sublist(kept.length - _rotateAt ~/ 2) : kept;
    _entered
      ..clear()
      ..addAll(recent);
    _timeline = DanmakuTimeline()..add(recent);
    _lastSeen.removeWhere((_, seen) => seen < keepFrom);
  }

  void _wake() {
    if (!widget.on || _ticker.isActive || _scene.size.isEmpty) return;
    _base = _seconds;
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    _seconds = _base + elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    _lastMs = math.max((_seconds * 1000).floor(), _lastMs);
    _scene.step(_seconds, timeline: _timeline, options: _options);
    if (_scene.idle && _timeline.nextAfter(_lastMs) == null) _ticker.stop();
  }

  late final Widget _layer = LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest.isFinite ? constraints.biggest : Size.zero;
      if (size != _scene.size) {
        _scene.size = size;
        // After layout: a resize re-lays what is flying at the new size on the next frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _wake();
        });
      }
      return CustomPaint(size: size, painter: _LivePainter(_scene), willChange: true);
    },
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.on) return const SizedBox.expand();
    return IgnorePointer(
      child: RepaintBoundary(
        child: Opacity(opacity: _options.opacity, child: _layer),
      ),
    );
  }
}

class _LivePainter extends CustomPainter {
  _LivePainter(this.scene) : super(repaint: scene);

  final DanmakuScene scene;

  @override
  void paint(Canvas canvas, Size size) => scene.paint(canvas);

  @override
  bool shouldRepaint(_LivePainter oldDelegate) => oldDelegate.scene != scene;
}
