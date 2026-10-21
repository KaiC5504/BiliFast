import 'dart:async';

import 'package:flutter/cupertino.dart' show RefreshIndicatorMode;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import 'theme.dart';

/// The official app's loading TV (14, 64, 67): its four faces in turn, [LoadingTvTheme.frame] each, drawn
/// [LoadingTvTheme.size] square. It stops under a muted [TickerMode] (a hidden tab), and Reduce Motion holds the first
/// face.
class LoadingTv extends StatefulWidget {
  const LoadingTv({super.key, this.playing = true});

  /// False holds the first face, as a pull short of the trigger does.
  final bool playing;

  static const frames = [
    'assets/images/loading/tv_1.webp',
    'assets/images/loading/tv_2.webp',
    'assets/images/loading/tv_3.webp',
    'assets/images/loading/tv_4.webp',
  ];

  /// Decodes the faces ahead of the first pull, so its first frames don't come up blank.
  static Future<void> precache(BuildContext context) =>
      Future.wait([for (final frame in frames) precacheImage(AssetImage(frame), context)]);

  @override
  State<LoadingTv> createState() => _LoadingTvState();
}

class _LoadingTvState extends State<LoadingTv> {
  // A timer rather than a ticker: an AnimationController would ask for every vsync (120 Hz on the phone) to change a
  // face 7.5 times a second. TickerMode's notifier still stops it on a hidden tab or a covered page.
  Timer? _timer;
  ValueListenable<TickerModeData>? _ticking;
  int _face = 0;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    unawaited(LoadingTv.precache(context));
    final ticking = TickerMode.getValuesNotifier(context);
    if (!identical(ticking, _ticking)) {
      _ticking?.removeListener(_tickingChanged);
      _ticking = ticking..addListener(_tickingChanged);
    }
    _run();
  }

  @override
  void didUpdateWidget(LoadingTv oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) _run();
  }

  void _tickingChanged() => setState(_run);

  /// Starts or stops the faces; called where a build follows.
  void _run() {
    if (widget.playing && !_still && (_ticking?.value.enabled ?? true)) {
      _timer ??= Timer.periodic(LoadingTvTheme.frame, (_) {
        if (mounted) setState(() => _face = (_face + 1) % LoadingTv.frames.length);
      });
    } else {
      _timer?.cancel();
      _timer = null;
      _face = 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ticking?.removeListener(_tickingChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '加载中',
    child: Image.asset(
      LoadingTv.frames[_face],
      key: ValueKey('loading-tv-$_face'),
      width: LoadingTvTheme.size,
      height: LoadingTvTheme.size,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    ),
  );
}

/// A page's first load (64, 67): the TV over 正在努力加载....
class LoadingTvState extends StatelessWidget {
  const LoadingTvState({super.key});

  static const message = '正在努力加载...';

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: BiliFonts.family,
      fontFamilyFallback: BiliFonts.fallback,
      fontSize: LoadingTvTheme.stateText,
      color: LoadingTvTheme.stateInk,
      letterSpacing: 0,
      decoration: TextDecoration.none,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The text says it; the TV's own 加载中 would be a second stop for VoiceOver.
        const ExcludeSemantics(child: LoadingTv()),
        const SizedBox(height: LoadingTvTheme.stateGap),
        Text(message, style: style, strutStyle: BiliFonts.strutOf(context, style), maxLines: 1),
      ],
    );
  }
}

/// [CupertinoSliverRefreshControl]'s `builder` with the TV in place of the spinner: it comes down out from under
/// what's above as the list is pulled, holding its first face until the pull would refresh, then cycles until the
/// refresh is done and the gap closes. Callers set `refreshIndicatorExtent` to [LoadingTvTheme.size], the gap 14 holds
/// while refreshing.
Widget loadingTvRefreshIndicator(
  BuildContext context,
  RefreshIndicatorMode mode,
  double pulledExtent,
  double refreshTriggerPullDistance,
  double refreshIndicatorExtent,
) {
  if (mode == RefreshIndicatorMode.inactive) return const SizedBox.shrink();
  return ClipRect(
    child: OverflowBox(
      alignment: Alignment.bottomCenter,
      minHeight: LoadingTvTheme.size,
      maxHeight: LoadingTvTheme.size,
      child: LoadingTv(playing: mode != RefreshIndicatorMode.drag),
    ),
  );
}
