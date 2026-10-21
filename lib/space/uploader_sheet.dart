import 'package:flutter/widgets.dart';

import 'uploader_tap.dart';

/// The uploader sheet over the video page's body (62, 68, 76).
class UploaderSheet extends StatefulWidget {
  const UploaderSheet({super.key, required this.uploader, required this.playingBvid, required this.onClose});

  final UploaderRef uploader;

  /// The page's video, whose card draws its title pink.
  final String playingBvid;
  final VoidCallback onClose;

  @override
  State<UploaderSheet> createState() => _UploaderSheetState();
}

class _UploaderSheetState extends State<UploaderSheet> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
