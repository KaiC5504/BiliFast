import 'feed_models.dart';

/// Where a video was opened from and the page it plays on, as the official app's watch reports name them.
final class PlaySource {
  const PlaySource({
    required this.fromSpmid,
    this.from = '',
    this.trackId,
    this.flowData,
    this.spmid = videoPage,
    this.historySource,
  });

  /// A 推荐 card: the feed's own track id and flow data go back with every report of the play.
  PlaySource.recommend(FeedCard card)
    : this(fromSpmid: 'tm.recommend.0.0', from: '7', trackId: card.trackId, flowData: card.flowData);

  /// A video of 竖屏's feed, entered from [entry]: the page 竖屏 was entered from stays the `from_spmid`, the item's
  /// own track data goes back, and the history report names the video 竖屏 was [entered] on apart from the ones
  /// swiped to.
  PlaySource.story({required PlaySource entry, required bool entered, String? trackId, String? flowData})
    : this(
        fromSpmid: entry.fromSpmid,
        from: 'default-value',
        trackId: trackId,
        flowData: flowData,
        spmid: verticalPage,
        historySource: entered ? 'story-single' : 'story-series',
      );

  /// Opened from a place whose `from_spmid` hasn't been read from the official app.
  static const unknown = PlaySource(fromSpmid: '');

  static const videoPage = 'united.player-video-detail.0.0';
  static const verticalPage = 'main.ugc-video-detail-vertical.0.0';

  final String fromSpmid;

  /// The official `from` code, '' when unknown.
  final String from;
  final String? trackId;

  /// The card's `report_flow_data`, sent back as it came.
  final String? flowData;

  /// The page the video plays on.
  final String spmid;

  /// The history report's `source`; null leaves it out, as for the video page, whose value is not known.
  final String? historySource;
}
