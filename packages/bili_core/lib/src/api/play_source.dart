import 'feed_models.dart';

/// Where a video was opened from, as the official app's watch reports name it.
final class PlaySource {
  const PlaySource({required this.fromSpmid, this.from = '', this.trackId, this.flowData});

  /// A 推荐 card: the feed's own track id and flow data go back with every report of the play.
  PlaySource.recommend(FeedCard card)
    : this(fromSpmid: 'tm.recommend.0.0', from: '7', trackId: card.trackId, flowData: card.flowData);

  /// Opened from somewhere whose name the official app's reports are not known for.
  static const unknown = PlaySource(fromSpmid: '');

  final String fromSpmid;

  /// The official `from` code, '' when unknown.
  final String from;
  final String? trackId;

  /// The card's `report_flow_data`, sent back as it came.
  final String? flowData;
}
