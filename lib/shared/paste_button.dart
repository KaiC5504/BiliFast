import 'package:flutter/material.dart';
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
  Widget build(BuildContext context) => IconButton(
    onPressed: enabled ? _read : null,
    tooltip: '粘贴',
    visualDensity: VisualDensity.compact,
    icon: const Icon(Icons.content_paste_rounded, size: 18, color: BiliColors.pink),
  );
}
