import 'package:bili_core/api.dart' show UploaderCard, VideoDetail;
import 'package:flutter/widgets.dart';

import '../actions/video_actions.dart';

/// The uploader (03): avatar with its verification badge, the name (pink for 大会员), 粉丝 and 视频, and the 关注 pill;
/// a 联合投稿 shows its staff instead.
class UploaderRow extends StatelessWidget {
  const UploaderRow({super.key, required this.detail, this.card, this.actions});

  final VideoDetail detail;

  /// The uploader's card (fans, videos, 大会员), null until it arrives.
  final UploaderCard? card;

  /// 关注 belongs to the actions; before they exist the pill shows the card's state.
  final VideoActions? actions;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
