import 'package:bili_core/danmaku.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../player/playback_clock.dart';
import 'danmaku_scene.dart';
import 'danmaku_settings.dart';
import 'danmaku_sprites.dart';

/// Danmaku over the video. While the clock runs, a ticker reads it every frame and only the painter repaints;
/// nothing rebuilds per frame. While it stands still the ticker sleeps, and [wake] (player events, a seek)
/// brings it back for a frame or for good. A 弹幕设置 change shows at once, mid-flight, rebuilding nothing but the
/// layer's opacity.
class DanmakuLayer extends StatefulWidget {
  const DanmakuLayer({
    super.key,
    required this.clock,
    required this.timeline,
    this.wake,
    this.enabled = true,
    this.options = const DanmakuOptions(),
    this.settings,
    this.fullScreen = false,
    this.sprites,
  });

  final PlaybackClock clock;
  final DanmakuTimeline? timeline;
  final Listenable? wake;
  final bool enabled;
  final DanmakuOptions options;

  /// The 弹幕设置 values, followed live in place of [options], for the presentation [fullScreen] says.
  final ValueListenable<DanmakuSettings>? settings;
  final bool fullScreen;

  /// Lays out the text; a test passes its own to count layouts.
  final DanmakuSprites? sprites;

  @override
  State<DanmakuLayer> createState() => DanmakuLayerState();
}

class DanmakuLayerState extends State<DanmakuLayer> with SingleTickerProviderStateMixin {
  late final DanmakuScene _scene = DanmakuScene(sprites: widget.sprites);
  late final Ticker _ticker = createTicker(_tick);

  @visibleForTesting
  DanmakuScene get scene => _scene;

  @visibleForTesting
  bool get ticking => _ticker.isActive;

  late DanmakuOptions _options = _resolve();

  @visibleForTesting
  DanmakuOptions get options => _options;

  bool get _active => widget.enabled && widget.timeline != null;

  DanmakuOptions _resolve() => widget.settings?.value.display(fullScreen: widget.fullScreen) ?? widget.options;

  @override
  void initState() {
    super.initState();
    widget.wake?.addListener(_wake);
    widget.settings?.addListener(_settingsChanged);
    _wake();
  }

  @override
  void didUpdateWidget(DanmakuLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wake != widget.wake) {
      oldWidget.wake?.removeListener(_wake);
      widget.wake?.addListener(_wake);
    }
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings?.removeListener(_settingsChanged);
      widget.settings?.addListener(_settingsChanged);
    }
    final options = _resolve();
    final changed = options != _options;
    _options = options;
    if (!_active) {
      _ticker.stop();
      _scene.reset();
    } else if (oldWidget.timeline != widget.timeline ||
        oldWidget.enabled != widget.enabled ||
        changed) {
      _wake();
    }
  }

  @override
  void dispose() {
    widget.wake?.removeListener(_wake);
    widget.settings?.removeListener(_settingsChanged);
    _ticker.dispose();
    _scene.dispose();
    super.dispose();
  }

  void _wake() {
    if (_active && !_ticker.isActive) _ticker.start();
  }

  /// The scene takes the rest on its next step; only the opacity is the widget's.
  void _settingsChanged() {
    final options = _resolve();
    if (options == _options) return;
    final faded = options.opacity != _options.opacity;
    _options = options;
    if (faded) setState(() {});
    _wake();
  }

  void _tick(Duration _) {
    final timeline = widget.timeline;
    if (timeline == null || !widget.enabled) {
      _ticker.stop();
      return;
    }
    _scene.step(widget.clock.seconds, timeline: timeline, options: _options);
    if (!widget.clock.running && !_scene.catchingUp) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.expand();
    final layer = LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.isFinite ? constraints.biggest : Size.zero;
        if (size != _scene.size) {
          _scene.size = size;
          _wake();
        }
        return CustomPaint(size: size, painter: _DanmakuPainter(_scene), willChange: true);
      },
    );
    // Always there, even at 1, so a 不透明度 change only sets the layer's alpha: nothing is laid out or repainted.
    return IgnorePointer(child: RepaintBoundary(child: Opacity(opacity: _options.opacity, child: layer)));
  }
}

class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter(this.scene) : super(repaint: scene);

  final DanmakuScene scene;

  @override
  void paint(Canvas canvas, Size size) => scene.paint(canvas);

  @override
  bool shouldRepaint(_DanmakuPainter oldDelegate) => oldDelegate.scene != scene;
}
