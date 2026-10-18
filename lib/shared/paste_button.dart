import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// The link field's paste button. Reading the clipboard from code makes iOS ask "Allow Paste?" every time, so on
/// iOS this is the system's own paste control, which never asks (Swift's PasteButton); elsewhere it reads the
/// clipboard. [onText] gets the pasted text, trimmed, empty when there was none.
class PasteButton extends StatelessWidget {
  const PasteButton({super.key, required this.enabled, required this.onText});

  final bool enabled;
  final ValueChanged<String> onText;

  Future<void> _read() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    onText(data?.text?.trim() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb) {
      return _NativePasteControl(enabled: enabled, onText: onText);
    }
    return IconButton(
      onPressed: enabled ? _read : null,
      tooltip: '粘贴',
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.content_paste_rounded, size: BiliMetrics.iconSize, color: BiliColors.pink),
    );
  }
}

/// UIPasteControl in a platform view (PasteControl.swift), talking over its own `bilifast/paste_control/<id>`.
class _NativePasteControl extends StatefulWidget {
  const _NativePasteControl({required this.enabled, required this.onText});

  static const viewType = 'bilifast/paste_control';

  final bool enabled;
  final ValueChanged<String> onText;

  @override
  State<_NativePasteControl> createState() => _NativePasteControlState();
}

class _NativePasteControlState extends State<_NativePasteControl> {
  /// A compact IconButton's box, as the clipboard button has; the field's height caps it the same way.
  static final _side = kMinInteractiveDimension + VisualDensity.compact.baseSizeAdjustment.dx;

  /// The control must get the touch itself: the system pastes only on a real tap on it.
  static final _gestures = <Factory<OneSequenceGestureRecognizer>>{
    Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
  };

  MethodChannel? _channel;

  /// What the native control was last told; the creation params carry the first build's value.
  late bool _nativeEnabled;

  void _created(int id) {
    if (!mounted) return;
    _channel = MethodChannel('${_NativePasteControl.viewType}/$id')..setMethodCallHandler(_handle);
    _syncEnabled();
  }

  Future<void> _handle(MethodCall call) async {
    if (call.method != 'paste' || !mounted || !widget.enabled) return;
    widget.onText((call.arguments as String? ?? '').trim());
  }

  void _syncEnabled() {
    final channel = _channel;
    if (channel == null || widget.enabled == _nativeEnabled) return;
    _nativeEnabled = widget.enabled;
    // A view already gone has nothing left to disable.
    channel.invokeMethod<void>('setEnabled', widget.enabled).ignore();
  }

  @override
  void initState() {
    super.initState();
    _nativeEnabled = widget.enabled;
  }

  @override
  void didUpdateWidget(_NativePasteControl old) {
    super.didUpdateWidget(old);
    _syncEnabled();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !widget.enabled,
    child: SizedBox.square(
      dimension: _side,
      child: UiKitView(
        viewType: _NativePasteControl.viewType,
        creationParams: <String, Object?>{'color': BiliColors.pink.toARGB32(), 'enabled': widget.enabled},
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        gestureRecognizers: _gestures,
        onPlatformViewCreated: _created,
      ),
    ),
  );
}
