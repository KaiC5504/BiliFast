import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import 'skin_loading.dart';

/// The equipped 加载动画 (119), contained in a [size] square. While [playing] it loops from its first frame, each
/// frame for the time the file gives it; held (a pull short of the trigger), under Reduce Motion or a muted
/// [TickerMode] it shows the first frame, as the TV shows its first face.
class SkinLoadingView extends StatefulWidget {
  const SkinLoadingView({super.key, required this.animation, this.playing = true, this.size = SkinLoadingTheme.size});

  final SkinLoadingAnimation animation;
  final bool playing;
  final double size;

  @override
  State<SkinLoadingView> createState() => _SkinLoadingViewState();
}

class _SkinLoadingViewState extends State<SkinLoadingView> {
  // A timer per frame rather than a ticker, as the TV's: a ticker would ask for every vsync to change a frame a few
  // times a second.
  Timer? _timer;
  ui.Codec? _codec;

  /// The frame on screen while playing, owned here; null shows the animation's first.
  ui.Image? _frame;

  /// Bumped by every start and stop, so a frame decoded for a run that ended is dropped.
  int _run = 0;
  bool _playing = false;
  bool _still = false;
  ValueListenable<TickerModeData>? _ticking;

  bool get _wanted => widget.playing && !_still && (_ticking?.value.enabled ?? true) && widget.animation.frames > 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    final ticking = TickerMode.getValuesNotifier(context);
    if (!identical(ticking, _ticking)) {
      _ticking?.removeListener(_tickingChanged);
      _ticking = ticking..addListener(_tickingChanged);
    }
    _sync();
  }

  @override
  void didUpdateWidget(SkinLoadingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.animation, widget.animation)) _stop();
    _sync();
  }

  void _tickingChanged() => setState(_sync);

  /// Starts or stops the frames; called where a build follows.
  void _sync() {
    if (_wanted) {
      if (!_playing) _start();
    } else {
      _stop();
    }
  }

  void _start() {
    _playing = true;
    final run = ++_run;
    unawaited(_open(run));
  }

  Future<void> _open(int run) async {
    final ui.Codec codec;
    try {
      codec = await widget.animation.codec();
    } on Exception {
      // Checked when it was kept, so this is only a memory squeeze: it holds its first frame.
      return;
    }
    if (run != _run || !mounted) {
      codec.dispose();
      return;
    }
    _codec = codec;
    // The first frame is on screen already; this one only gives its time.
    await _advance(run, show: false);
  }

  Future<void> _advance(int run, {bool show = true}) async {
    final codec = _codec;
    if (codec == null) return;
    final ui.FrameInfo frame;
    try {
      frame = await codec.getNextFrame();
    } on Exception {
      return;
    }
    if (run != _run || !mounted) {
      frame.image.dispose();
      return;
    }
    if (show) {
      final shown = _frame;
      setState(() => _frame = frame.image);
      // The render object holds a clone of what it draws.
      shown?.dispose();
    } else {
      frame.image.dispose();
    }
    _timer = Timer(_frameTime(frame.duration), () {
      _timer = null;
      unawaited(_advance(run));
    });
  }

  static Duration _frameTime(Duration time) =>
      time < SkinLoadingTheme.shortestFrame ? SkinLoadingTheme.defaultFrame : time;

  void _stop() {
    _run++;
    _playing = false;
    _timer?.cancel();
    _timer = null;
    _codec?.dispose();
    _codec = null;
    _frame?.dispose();
    _frame = null;
  }

  @override
  void dispose() {
    _stop();
    _ticking?.removeListener(_tickingChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '加载中',
    child: RawImage(
      key: const ValueKey('skin-loading'),
      image: _frame ?? widget.animation.first,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    ),
  );
}
