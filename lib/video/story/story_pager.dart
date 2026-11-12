import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../player_ui/vertical_chrome_preview.dart';
import '../../shared/cover_preset.dart';
import '../../shared/remote_image.dart';
import '../../shared/theme.dart';
import '../video_player_area.dart' show VideoSurfaceLayout, verticalBand;
import 'story_drag.dart';
import 'story_feed.dart';

/// 竖屏's swipe between videos (185, 186): shapes the finger's travel on [drag], answers its release, moves the page the
/// rest of the way by itself and lands it on the neighbour, which it opens on [feed]. The page keeps one for its life;
/// [feed] is set while 竖屏 is up. Notifies when the neighbours or the held still change, not as the page moves.
class StoryPager extends ChangeNotifier {
  StoryPager({required this.drag, required TickerProvider vsync, this.clean}) {
    _ticker = vsync.createTicker(_tick);
    drag.addListener(_dragChanged);
  }

  final StoryDrag drag;

  /// 清屏, off once the page lands on another video: it arrives with its controls.
  final ValueNotifier<bool>? clean;

  late final Ticker _ticker;
  StoryFeed? _feed;
  StoryEntry? _arrived;
  double _from = 0;
  double _to = 0;

  /// The page's height, from its last layout: one swipe moves exactly this far.
  double extent = 0;

  StoryFeed? get feed => _feed;

  set feed(StoryFeed? value) {
    if (identical(value, _feed)) return;
    _ticker.stop();
    _feed?.removeListener(_feedChanged);
    _feed = value;
    _arrived = null;
    value?.addListener(_feedChanged);
    drag
      ..shape = value == null ? null : _shape
      ..unshape = value == null ? null : _unshape
      ..onRelease = value == null ? null : _release
      ..onCancel = value == null ? null : _goBack;
    notifyListeners();
  }

  /// The video the page landed on, whose still stays in its band until the player shows its first frame ([framed]).
  StoryEntry? get arrived => _arrived;

  /// The player has shown a frame of [bvid] since its open; null while it hasn't of any.
  void framed(String? bvid) {
    if (bvid == null || _arrived?.bvid != bvid) return;
    _arrived = null;
    notifyListeners();
  }

  void _feedChanged() {
    // A feed started over on a video the page opened itself (选集 or 合集 in landscape) never plays the one landed on,
    // whose still would cover it for good.
    if (_arrived != null && _feed?.current?.bvid != _arrived?.bvid) _arrived = null;
    notifyListeners();
  }

  /// 下一个视频 for VoiceOver and the Windows test tool: the swipe's settle without the finger. False with none, or
  /// while the page is under a finger or already moving; with none, the feed may ask again, as after a swipe.
  bool moveNext() => _move(-1);

  /// 上一个视频, as [moveNext].
  bool movePrevious() => _move(1);

  bool _move(int direction) {
    final feed = _feed;
    if (feed == null || drag.moving || extent <= 0) return false;
    if ((direction < 0 ? feed.next : feed.previous) == null) {
      if (direction < 0) feed.wantMore();
      return false;
    }
    _settle(direction * extent);
    return true;
  }

  bool _open(double offset) => offset < 0 ? _feed?.next != null : offset > 0 && _feed?.previous != null;

  double _shape(double travel) {
    final offset = _open(travel) ? travel : travel * StoryPagerTheme.resistance;
    return extent > 0 ? offset.clamp(-extent, extent) : offset;
  }

  double _unshape(double offset) => _open(offset) ? offset : offset / StoryPagerTheme.resistance;

  void _release(double velocity) {
    final offset = drag.offset;
    // The finger's own travel: towards no neighbour the page lags it.
    final passed = _unshape(offset).abs() > extent * StoryPagerTheme.releaseShare;
    final flung = velocity.abs() > StoryPagerTheme.flingVelocity && velocity.sign == offset.sign;
    final moves = passed || flung;
    // Past the last video known the page springs back, but a feed that stopped asking may ask again.
    if (moves && offset < 0 && _feed?.next == null) _feed?.wantMore();
    _settle(_open(offset) && moves ? offset.sign * extent : 0);
  }

  void _goBack() => _settle(0);

  void _settle(double to) {
    _from = drag.offset;
    _to = to;
    _ticker.stop();
    if ((_from - _to).abs() < StoryPagerTheme.landWithin) {
      _land();
      return;
    }
    drag.settleTo(_from);
    _ticker.start();
  }

  // Timed rather than counted, so 120 Hz screens land as soon as 60 Hz ones; the first tick already shows one frame's
  // step.
  void _tick(Duration elapsed) {
    final frames = elapsed.inMicroseconds / StoryPagerTheme.frame.inMicroseconds + 1;
    final left = (_from - _to) * math.pow(StoryPagerTheme.settleRatioPerFrame, frames);
    if (left.abs() < StoryPagerTheme.landWithin) {
      _ticker.stop();
      _land();
    } else {
      drag.settleTo(_to + left);
    }
  }

  void _land() {
    final feed = _feed;
    final moved = switch (_to) {
      < 0 => feed?.moveNext() ?? false,
      > 0 => feed?.movePrevious() ?? false,
      _ => false,
    };
    if (moved) {
      _arrived = feed?.current;
      clean?.value = false;
    }
    drag.land();
    if (moved) notifyListeners();
  }

  void _dragChanged() {
    // A finger taking the page stops its settle where it is; so does the page being put back from outside.
    if (_ticker.isActive && (drag.dragging || !drag.moving)) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    drag.removeListener(_dragChanged);
    _feed?.removeListener(_feedChanged);
    if (_feed != null) {
      drag
        ..shape = null
        ..unshape = null
        ..onRelease = null
        ..onCancel = null;
    }
    super.dispose();
  }
}

/// Moves its child with the page under the finger; with no [drag] it stays put. Always the same widgets, so the native
/// view under it keeps its element whether 竖屏 is up or not.
class StoryShift extends StatelessWidget {
  const StoryShift({super.key, required this.drag, required this.child});

  final StoryDrag? drag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final drag = this.drag;
    return ListenableBuilder(
      listenable: drag ?? const AlwaysStoppedAnimation<double>(0),
      builder: (context, child) => Transform.translate(offset: Offset(0, drag?.offset ?? 0), child: child),
      child: child,
    );
  }
}

/// The pages beside the one playing: the video before one screen above, the next one screen below, each its still
/// picture in its band with its controls dimmed over it, moving with the finger. Over the playing page, the still of
/// the video just landed on until its first frame shows. Takes no touches and says nothing to VoiceOver.
class StoryNeighbours extends StatelessWidget {
  const StoryNeighbours({super.key, required this.pager, this.danmakuOn = true, this.slide});

  final StoryPager pager;

  /// The page's 弹, which the neighbours' 发弹幕 fields show as the next video will open with it.
  final bool danmakuOn;

  /// Where the page has put the video's box instead of its band (the uploader sheet's room, 181; the slide, 187): the
  /// held still goes there with it, and the neighbours are left out.
  final Rect? slide;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          pager.extent = constraints.maxHeight;
          return ListenableBuilder(
            listenable: pager,
            builder: (context, _) {
              final feed = pager.feed;
              final arrived = pager.arrived;
              return StoryShift(
                drag: pager.drag,
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    if (feed?.previous case final previous? when slide == null)
                      _StoryPage(key: ObjectKey(previous), entry: previous, at: -1, danmakuOn: danmakuOn),
                    if (arrived != null)
                      _StoryPage(key: ObjectKey(arrived), entry: arrived, at: 0, danmakuOn: danmakuOn, box: slide),
                    if (feed?.next case final next? when slide == null)
                      _StoryPage(key: ObjectKey(next), entry: next, at: 1, danmakuOn: danmakuOn),
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

/// [entry]'s page [at] screens below the playing one: its still in its band, or in [box] where the page has put the
/// video's, and its controls unless it is the page itself.
class _StoryPage extends StatelessWidget {
  const _StoryPage({super.key, required this.entry, required this.at, required this.danmakuOn, this.box});

  final StoryEntry entry;
  final int at;
  final bool danmakuOn;
  final Rect? box;

  @override
  Widget build(BuildContext context) => FractionalTranslation(
    translation: Offset(0, at.toDouble()),
    child: Stack(
      fit: StackFit.expand,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final heightFactor = verticalBand(upright: entry.upright);
            return CustomSingleChildLayout(
              delegate: VideoSurfaceLayout(heightFactor: heightFactor, slid: box),
              // Asked at the band's size and scaled into a box that moves, so a moving box asks no new picture.
              child: FittedBox(
                child: _still(Size(constraints.maxWidth, constraints.maxHeight * heightFactor)),
              ),
            );
          },
        ),
        if (at != 0)
          Opacity(
            opacity: VerticalCleanTheme.movingOpacity,
            child: VerticalChromePreview(entry: entry, danmakuOn: danmakuOn),
          ),
      ],
    ),
  );

  /// The picture fitted into the band as the video will be, asked at that size.
  Widget _still(Size band) {
    final aspect = entry.width > 0 && entry.height > 0 ? entry.width / entry.height : BiliMetrics.videoAspect;
    final width = math.min(band.width, band.height * aspect);
    final size = Size(width, width / aspect);
    return SizedBox.fromSize(
      key: const ValueKey('story-still'),
      size: size,
      child: RemoteImage(
        entry.still,
        size: size,
        cover: true,
        // The player's preset is a wide one; an upright picture is asked at its own shape.
        preset: entry.upright ? CoverPreset.exact : CoverPreset.player,
        placeholder: const ColoredBox(color: BiliColors.videoBackground),
      ),
    );
  }
}
