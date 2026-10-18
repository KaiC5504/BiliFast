import 'package:bili_core/api.dart' show VideoDetail, VideoTag;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The title with its 活动 tag and ⌄, and the meta line with N人正在看 (03). Expanded (18): the BV id, the reprint
/// notice, the description with seeking timestamps, links and video ids, and the plain tags.
class TitleBlock extends StatelessWidget {
  const TitleBlock({
    super.key,
    required this.detail,
    required this.online,
    required this.tags,
    required this.onSeek,
    required this.onOpenVideo,
  });

  final VideoDetail detail;
  final ValueListenable<String?> online;
  final List<VideoTag> tags;

  /// A timestamp in the description, in seconds.
  final ValueChanged<double> onSeek;

  /// A BV or av id in the description.
  final ValueChanged<String> onOpenVideo;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
