import 'dart:async';
import 'dart:ui' as ui;

import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// An animated asset picture that costs the app one frame per picture. [Image] asks for a frame as each picture is
/// decoded and another when it is due, so a 33 fps gif drew 60 frames a second, and it decodes every picture again
/// on every lap. Here the pictures are decoded once and kept, a timer asks for the frame that shows the next one,
/// and nothing runs under a muted [TickerMode], with Reduce Motion (the first picture holds) or with the app away
/// (the frame never comes, so the loop waits for it).
class PacedGif extends StatefulWidget {
  const PacedGif(this.asset, {super.key, required this.size});

  final String asset;
  final Size size;

  static final _decoding = <String, Future<List<ui.FrameInfo>>>{};

  /// Once decoded, so a pill built later shows its picture in its first frame.
  static final _decoded = <String, List<ui.FrameInfo>>{};

  /// Decodes [asset]'s pictures once for every PacedGif drawing it; a test awaits it in runAsync.
  /// A failed decode is forgotten, so the next pill asks again.
  static Future<List<ui.FrameInfo>> load(String asset) => _decoding[asset] ??= () async {
    try {
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      try {
        return _decoded[asset] = [for (var i = 0; i < codec.frameCount; i++) await codec.getNextFrame()];
      } finally {
        codec.dispose();
      }
    } catch (_) {
      _decoding.remove(asset);
      rethrow;
    }
  }();

  @override
  State<PacedGif> createState() => _PacedGifState();
}

class _PacedGifState extends State<PacedGif> {
  List<ui.FrameInfo>? _frames;
  int _index = 0;
  ValueListenable<TickerModeData>? _mode;
  bool _still = false;
  Timer? _timer;
  int? _frameCallback;

  bool get _running => _timer != null || _frameCallback != null;

  @override
  void initState() {
    super.initState();
    _frames = PacedGif._decoded[widget.asset];
    if (_frames == null) unawaited(_load());
  }

  Future<void> _load() async {
    final List<ui.FrameInfo> frames;
    try {
      frames = await PacedGif.load(widget.asset);
    } catch (error) {
      Logger.shared.warn(LogCategory.ui, 'paced gif failed', {'error': '${error.runtimeType}'});
      return;
    }
    if (!mounted) return;
    setState(() => _frames = frames);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mode = TickerMode.getValuesNotifier(context);
    if (mode != _mode) {
      _mode?.removeListener(_sync);
      _mode = mode..addListener(_sync);
    }
    _still = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void dispose() {
    _stop();
    _mode?.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    final frames = _frames;
    final run = frames != null && frames.length > 1 && !_still && (_mode?.value.enabled ?? true);
    if (!run) {
      _stop();
      if (_still && _index != 0) setState(() => _index = 0);
    } else if (!_running) {
      _arm();
    }
  }

  /// Asks for the frame that shows the next picture one vsync before it is due, so it lands on the vsync at or just
  /// after its time.
  void _arm() {
    final due = _frames![_index].duration;
    final refresh = View.maybeOf(context)?.display.refreshRate ?? 60;
    final vsync = Duration(microseconds: (Duration.microsecondsPerSecond / (refresh > 0 ? refresh : 60)).round());
    final early = (due.inMicroseconds - 1) ~/ vsync.inMicroseconds;
    _timer = Timer(vsync * early, () {
      _timer = null;
      _frameCallback = SchedulerBinding.instance.scheduleFrameCallback(_advance);
    });
  }

  void _advance(Duration timestamp) {
    _frameCallback = null;
    if (!mounted) return;
    setState(() => _index = (_index + 1) % _frames!.length);
    _arm();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (_frameCallback case final id?) SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    _frameCallback = null;
  }

  @override
  Widget build(BuildContext context) => RawImage(
    image: _frames?[_index].image,
    width: widget.size.width,
    height: widget.size.height,
    fit: BoxFit.contain,
  );
}
