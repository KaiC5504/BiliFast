import 'dart:async';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The 我的 header's `head_myself_mp4_bg`: a muted video in a native view on the phone (`SkinVideoView.swift`, its
/// sound track left out so it never touches the audio session), [placeholder] elsewhere and until it draws.
///
/// The view's own `bilifast/skin_video/<id>` channel says `ready` once its first frame shows (and `failed` with a
/// reason when the file won't load or play, after which the view is dropped for the placeholder until the file
/// changes), and takes `play` and `pause`: it plays only while this subtree's [TickerMode] is on, so a hidden 我的 or a
/// covered page holds it.
class SkinVideo extends StatefulWidget {
  const SkinVideo({super.key, required this.file, required this.loop, required this.placeholder});

  static const viewType = 'bilifast/skin_video';

  final File file;
  final bool loop;
  final Widget placeholder;

  @override
  State<SkinVideo> createState() => _SkinVideoState();
}

class _SkinVideoState extends State<SkinVideo> {
  static final _logged = <String>{};

  MethodChannel? _channel;
  ValueListenable<TickerModeData>? _ticking;
  bool _ready = false;
  bool _failed = false;
  bool? _sent;

  bool get _native => defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ticking = TickerMode.getValuesNotifier(context);
    if (!identical(ticking, _ticking)) {
      _ticking?.removeListener(_sync);
      _ticking = ticking..addListener(_sync);
    }
    _sync();
  }

  @override
  void didUpdateWidget(SkinVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The new key below makes a new native view; until it draws, the placeholder shows again.
    if (oldWidget.file.path != widget.file.path || oldWidget.loop != widget.loop) {
      _detach();
      _failed = false;
    }
  }

  @override
  void dispose() {
    _ticking?.removeListener(_sync);
    _detach();
    super.dispose();
  }

  void _created(int id) {
    if (!mounted) return;
    _channel = MethodChannel('${SkinVideo.viewType}/$id')..setMethodCallHandler(_handle);
    _sent = null;
    _sync();
  }

  void _detach() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    _ready = false;
    _sent = null;
  }

  Future<void> _handle(MethodCall call) async {
    switch (call.method) {
      case 'ready':
        if (mounted && !_ready) setState(() => _ready = true);
      case 'failed':
        final reason = call.arguments is String ? call.arguments as String : 'unknown';
        if (_logged.add('${widget.file.path}|$reason')) {
          Logger.shared.warn(LogCategory.ui, 'skin video failed', {
            'file': widget.file.uri.pathSegments.last,
            'reason': reason,
          });
        }
        if (!mounted || _failed) return;
        _detach();
        setState(() => _failed = true);
    }
  }

  /// Sends `play` or `pause` when this subtree's ticking changed since the view last heard; a new view starts paused.
  void _sync() {
    final channel = _channel;
    if (channel == null) return;
    final play = _ticking?.value.enabled ?? true;
    if (play == _sent || (_sent == null && !play)) return;
    _sent = play;
    unawaited(_send(channel, play ? 'play' : 'pause'));
  }

  static Future<void> _send(MethodChannel channel, String method) async {
    try {
      await channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // The native view is already gone.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_native) return widget.placeholder;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Visibility(
          visible: !_ready,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          child: widget.placeholder,
        ),
        // A dead platform view would still be composited every frame.
        if (!_failed)
          Positioned.fill(
            child: IgnorePointer(
              child: UiKitView(
                key: ValueKey('${widget.file.path}|${widget.loop}'),
                viewType: SkinVideo.viewType,
                creationParams: <String, Object?>{'path': widget.file.path, 'loop': widget.loop},
                creationParamsCodec: const StandardMessageCodec(),
                hitTestBehavior: PlatformViewHitTestBehavior.transparent,
                onPlatformViewCreated: _created,
              ),
            ),
          ),
      ],
    );
  }
}
