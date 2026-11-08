import 'dart:math' as math;

import 'package:bili_core/danmaku.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../app/form_factor.dart';
import '../device/orientation.dart';
import '../player/bili_player.dart';
import '../player/playback_clock.dart';
import 'danmaku_pace.dart';
import 'danmaku_scene.dart';
import 'danmaku_settings.dart';
import 'danmaku_sprites.dart';
import 'mask/mask_feed.dart';

/// Danmaku over the video. While the clock runs, a ticker reads it every frame and only the painter repaints;
/// nothing rebuilds per frame. While it stands still the ticker sleeps, and [wake] (player events, a seek)
/// brings it back for a frame or for good. A 弹幕设置 change shows at once, mid-flight; only 不透明度 rebuilds
/// anything, and then just the Opacity above the painter.
///
/// Given 人像防挡's [mask] and the [picture], the danmaku pass behind the people in it.
class DanmakuLayer extends StatefulWidget {
  const DanmakuLayer({
    super.key,
    required this.clock,
    required this.timeline,
    this.wake,
    this.enabled = true,
    this.options = const DanmakuOptions(),
    this.settings,
    this.presentation = Presentation.inline,
    this.sprites,
    this.formFactor,
    this.mask,
    this.picture,
    this.mirrored = false,
  });

  final PlaybackClock clock;
  final DanmakuTimeline? timeline;
  final Listenable? wake;
  final bool enabled;
  final DanmakuOptions options;

  /// The 弹幕设置 values, followed live in place of [options], for [presentation].
  final ValueListenable<DanmakuSettings>? settings;
  final Presentation presentation;

  /// Lays out the text; a test passes its own to count layouts.
  final DanmakuSprites? sprites;

  /// [FormFactor.device] unless given.
  final FormFactor? formFactor;

  /// 人像防挡's feed for the part playing, followed as it changes.
  final ValueListenable<MaskFeed?>? mask;

  /// Where the player draws the picture, in the layer's own coordinates: the mask's frames are stretched onto it.
  /// Without it nothing is masked.
  final Rect? picture;

  /// 镜像: the picture is drawn flipped, so the mask is too.
  final bool mirrored;

  @override
  State<DanmakuLayer> createState() => DanmakuLayerState();
}

class DanmakuLayerState extends State<DanmakuLayer> with SingleTickerProviderStateMixin {
  late final DanmakuScene _scene = DanmakuScene(sprites: widget.sprites);
  late final Ticker _ticker = createTicker(_tick);
  final _pace = DanmakuPace();
  final _clip = _MaskClip();
  MaskFeed? _maskFeed;

  @visibleForTesting
  DanmakuScene get scene => _scene;

  @visibleForTesting
  bool get ticking => _ticker.isActive;

  late DanmakuOptions _options = _resolve();

  @visibleForTesting
  DanmakuOptions get options => _options;

  bool get _active => widget.enabled && widget.timeline != null;

  DanmakuOptions _resolve() {
    final formFactor = widget.formFactor ?? FormFactor.device;
    if (widget.settings case final settings?) {
      return settings.value.display(presentation: widget.presentation, formFactor: formFactor);
    }
    final options = widget.options;
    if (options.formFactor == formFactor) return options;
    return DanmakuOptions(
      area: options.area,
      opacity: options.opacity,
      scale: options.scale,
      scrollDuration: options.scrollDuration,
      presentation: options.presentation,
      formFactor: formFactor,
    );
  }

  @override
  void initState() {
    super.initState();
    widget.wake?.addListener(_wake);
    widget.settings?.addListener(_settingsChanged);
    widget.mask?.addListener(_maskChanged);
    _clip.place(widget.picture, mirrored: widget.mirrored);
    _maskChanged();
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
    if (oldWidget.mask != widget.mask) {
      oldWidget.mask?.removeListener(_maskChanged);
      widget.mask?.addListener(_maskChanged);
      _maskChanged();
    }
    _clip.place(widget.picture, mirrored: widget.mirrored);
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
    widget.mask?.removeListener(_maskChanged);
    _maskFeed?.removeListener(_maskLanded);
    _ticker.dispose();
    _scene.dispose();
    _clip.dispose();
    super.dispose();
  }

  void _wake() {
    if (_active && !_ticker.isActive) {
      _pace.restart();
      _ticker.start();
    }
  }

  void _maskChanged() {
    final feed = widget.mask?.value;
    if (identical(feed, _maskFeed)) return;
    _maskFeed?.removeListener(_maskLanded);
    _maskFeed = feed;
    feed?.addListener(_maskLanded);
    if (feed != null && _active) feed.follow(widget.clock.seconds);
    _maskLanded();
  }

  /// Frames landing for a paused picture show without the ticker.
  void _maskLanded() => _clip.show(_maskFeed?.frameAt(widget.clock.seconds));

  /// The scene takes the rest on its next step; only the opacity is the widget's.
  void _settingsChanged() {
    final options = _resolve();
    if (options == _options) return;
    final faded = options.opacity != _options.opacity;
    _options = options;
    if (faded) setState(() {});
    _wake();
  }

  void _tick(Duration elapsed) {
    final timeline = widget.timeline;
    if (timeline == null || !widget.enabled) {
      _ticker.stop();
      return;
    }
    final clock = widget.clock;
    final seconds = _pace.follow(
      clock.seconds,
      rate: clock.rate,
      running: clock.running,
      frameSeconds: elapsed.inMicroseconds / Duration.microsecondsPerSecond,
    );
    _scene.step(seconds, timeline: timeline, options: _options);
    // The mask goes with the picture on screen: by the playhead itself, not danmaku's paced time.
    if (_maskFeed case final feed?) {
      final playhead = clock.seconds;
      feed.follow(playhead);
      _clip.show(feed.frameAt(playhead));
    }
    if (!clock.running && !_scene.catchingUp) _ticker.stop();
  }

  /// Built once: a rebuild for 不透明度 hands Opacity the same child, so the builder doesn't run again.
  late final Widget _layer = LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest.isFinite ? constraints.biggest : Size.zero;
      if (size != _scene.size) {
        _scene.size = size;
        _wake();
      }
      return CustomPaint(size: size, painter: _DanmakuPainter(_scene, _clip), willChange: true);
    },
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.expand();
    // Always there, even at 1, so a 不透明度 change only sets the layer's alpha: nothing is laid out or repainted.
    return IgnorePointer(child: RepaintBoundary(child: Opacity(opacity: _options.opacity, child: _layer)));
  }
}

class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter(this.scene, this.mask) : super(repaint: Listenable.merge([scene, mask]));

  final DanmakuScene scene;
  final _MaskClip mask;

  @override
  void paint(Canvas canvas, Size size) {
    final clip = mask.pathFor(size);
    if (clip == null) return scene.paint(canvas);
    canvas
      ..save()
      ..clipPath(clip);
    scene.paint(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DanmakuPainter oldDelegate) => oldDelegate.scene != scene || oldDelegate.mask != mask;
}

/// 人像防挡's clip for the painter: the frame showing, stretched onto the picture, kept until the frame, the picture,
/// 镜像 or the layer's size changes.
final class _MaskClip extends ChangeNotifier {
  MaskFrame? _frame;
  Rect? _picture;
  bool _mirrored = false;
  Path? _path;
  Size? _pathSize;

  void show(MaskFrame? frame) {
    if (frame == _frame) return;
    _frame = frame;
    _path = null;
    notifyListeners();
  }

  void place(Rect? picture, {required bool mirrored}) {
    if (picture == _picture && mirrored == _mirrored) return;
    _picture = picture;
    _mirrored = mirrored;
    _path = null;
    if (_frame != null) notifyListeners();
  }

  Path? pathFor(Size size) {
    final frame = _frame;
    final picture = _picture;
    if (frame == null || picture == null || picture.isEmpty || frame.box.isEmpty) return null;
    if (_path case final path? when _pathSize == size) return path;
    _pathSize = size;
    return _path = maskClipPath(frame, picture: picture, mirrored: _mirrored, size: size);
  }
}

/// Where danmaku may draw for [frame] in a layer of [size]: the frame's filled area stretched onto [picture] (flipped
/// when [mirrored]), and everything outside the picture, so those over the letterbox bars draw as ever. The picture's
/// outline is wound against the outer one, which cancels it inside the picture under either fill rule and leaves the
/// frame's own winding to count there, so no path operation runs for each of the mask's frames.
@visibleForTesting
Path maskClipPath(MaskFrame frame, {required Rect picture, required bool mirrored, required Size size}) {
  final box = frame.box;
  final scaleX = picture.width / box.width;
  final matrix = Float64List(16)
    ..[0] = mirrored ? -scaleX : scaleX
    ..[5] = picture.height / box.height
    ..[10] = 1
    ..[12] = mirrored ? picture.right : picture.left
    ..[13] = picture.top
    ..[15] = 1;
  // Danmaku run past the layer's sides as they enter and leave.
  final reach = (Offset.zero & size).inflate(size.longestSide);
  return Path()
    ..fillType = frame.path.fillType
    ..addPolygon([reach.topLeft, reach.topRight, reach.bottomRight, reach.bottomLeft], true)
    ..addPolygon([picture.topLeft, picture.bottomLeft, picture.bottomRight, picture.topRight], true)
    ..addPath(frame.path, Offset.zero, matrix4: matrix);
}

/// Where the player draws a [video] picture in its [box] for [fit], as `PlayerHostView.swift` and the Windows player
/// place it: fitted (适应) or covering (填充), the box itself (拉伸), or stretched into a 16:9 or 4:3 frame fitted in
/// the box, always centred. Null when the fit needs the video's shape and it isn't known yet.
Rect? videoPicture(Size box, {required FitMode fit, Size? video}) {
  Rect centred(Size shape, {bool cover = false}) {
    final scaleX = box.width / shape.width;
    final scaleY = box.height / shape.height;
    final scale = cover ? math.max(scaleX, scaleY) : math.min(scaleX, scaleY);
    return Rect.fromCenter(center: box.center(Offset.zero), width: shape.width * scale, height: shape.height * scale);
  }

  return switch (fit) {
    FitMode.stretch => Offset.zero & box,
    FitMode.ratio16x9 => centred(const Size(16, 9)),
    FitMode.ratio4x3 => centred(const Size(4, 3)),
    FitMode.fit || FitMode.fill when video == null || video.isEmpty => null,
    FitMode.fit => centred(video!),
    FitMode.fill => centred(video!, cover: true),
  };
}
