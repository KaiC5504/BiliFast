import 'package:bili_core/api.dart' show VideoCard;
import 'package:flutter/widgets.dart';

import '../intro/intro_tab.dart';
import '../intro/related_list.dart';
import '../page_details.dart';
import '../player_session.dart';

/// The iPad's 简介 sections without the related videos (ipad/03, 04, 06): the uploader, the title block, the actions,
/// the parts or the 合集 and the chips, in one column at the iPad's gutters. Sideways it heads the left column above
/// 热门评论; upright it heads 简介 above the related videos.
class PadIntroHead extends StatelessWidget {
  const PadIntroHead({
    super.key,
    required this.content,
    required this.details,
    required this.onSeek,
    required this.onOpenVideo,
    required this.onPlayEpisode,
    required this.onOpenEpisodes,
  });

  final IntroContent content;
  final PageDetails details;
  final ValueChanged<double> onSeek;
  final ValueChanged<String> onOpenVideo;
  final ValueChanged<Episode> onPlayEpisode;
  final VoidCallback onOpenEpisodes;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// The related videos as the iPad's right column sideways (ipad/03), scrolling on its own.
class PadRelatedColumn extends StatelessWidget {
  const PadRelatedColumn({super.key, required this.cards, required this.onOpen, required this.onWatchLater});

  final List<VideoCard> cards;
  final ValueChanged<VideoCard> onOpen;
  final ValueChanged<VideoCard> onWatchLater;

  @override
  Widget build(BuildContext context) =>
      CustomScrollView(slivers: [RelatedSliver(cards: cards, onOpen: onOpen, onWatchLater: onWatchLater)]);
}
