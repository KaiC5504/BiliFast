import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'svga/svga_loader.dart';
import 'svga/svga_painter.dart';

/// An `.svga` animation (SVGA 2's zlib protobuf, or SVGA 1's zip with `movie.spec`), drawn by our own decoder.
/// [play] runs it from the first frame, once, or looping with [loop]; stopped it shows the first frame. [fallback]
/// shows while it decodes or when it can't be read.
class SvgaView extends StatefulWidget {
  const SvgaView({
    super.key,
    required this.file,
    required this.play,
    this.loop = false,
    this.fit = BoxFit.contain,
    this.fallback,
  });

  final File file;
  final bool play;
  final bool loop;
  final BoxFit fit;
  final Widget? fallback;

  @override
  State<SvgaView> createState() => _SvgaViewState();
}

class _SvgaViewState extends State<SvgaView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _frame = ValueNotifier<int>(0);
  ValueListenable<TickerModeData>? _ticking;
  SvgaComposition? _movie;
  Object? _loading;

  /// The frame the running ticker started from: a hidden page holds its frame and goes on from it when shown.
  int _runStart = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ticking = TickerMode.getValuesNotifier(context);
    if (!identical(ticking, _ticking)) {
      _ticking?.removeListener(_run);
      _ticking = ticking..addListener(_run);
    }
    _run();
  }

  @override
  void didUpdateWidget(SvgaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.file, widget.file)) _load();
    final restart = widget.play != oldWidget.play || (widget.play && widget.loop && !oldWidget.loop && _finished);
    if (restart) _restart();
    _run();
  }

  @override
  void dispose() {
    _ticking?.removeListener(_run);
    _ticker
      ..stop()
      ..dispose();
    _frame.dispose();
    super.dispose();
  }

  void _load() {
    final token = _loading = Object();
    final result = SvgaLoader.shared.load(widget.file);
    if (result is Future<SvgaComposition?>) {
      _show(null);
      unawaited(
        result.then((movie) {
          if (mounted && identical(_loading, token)) setState(() => _show(movie));
        }),
      );
    } else {
      _show(result);
    }
  }

  void _show(SvgaComposition? movie) {
    if (identical(movie, _movie)) return;
    _movie = movie;
    _restart();
    _run();
  }

  void _restart() {
    _ticker.stop();
    _runStart = 0;
    _finished = false;
    _frame.value = 0;
  }

  /// Starts or stops the ticker for what's asked and whether this subtree may tick.
  void _run() {
    final movie = _movie?.movie;
    final runs =
        movie != null &&
        widget.play &&
        !_finished &&
        movie.fps > 0 &&
        movie.frames > 1 &&
        (_ticking?.value.enabled ?? true);
    if (runs == _ticker.isActive) return;
    if (runs) {
      _runStart = _frame.value;
      _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final movie = _movie?.movie;
    if (movie == null) return;
    // A hundredth of a frame early, so vsync timestamps a microsecond short of a frame's time still reach it.
    final advanced = (elapsed.inMicroseconds * movie.fps / Duration.microsecondsPerSecond + 0.01).floor();
    var index = _runStart + advanced;
    if (index >= movie.frames) {
      if (widget.loop) {
        index %= movie.frames;
      } else {
        index = movie.frames - 1;
        _finished = true;
        _ticker.stop();
      }
    }
    _frame.value = index;
  }

  @override
  Widget build(BuildContext context) {
    final movie = _movie;
    if (movie == null) return widget.fallback ?? const SizedBox.shrink();
    return RepaintBoundary(
      child: CustomPaint(
        size: movie.size,
        painter: SvgaPainter(composition: movie, frame: _frame, fit: widget.fit),
      ),
    );
  }
}
