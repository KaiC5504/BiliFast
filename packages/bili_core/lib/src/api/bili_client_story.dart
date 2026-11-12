part of 'bili_client.dart';

/// 竖屏's feed, asked as the official iPhone app asks it (docs/reference/official-iphone-calls.md).
extension BiliClientStory on BiliClient {
  /// The videos after [aid] / [cid], the video 竖屏 was entered on: [page] counts from 1 (`display_id`), and page 1
  /// names where 竖屏 was entered from ([entry]) and starts with the entered video itself. [trackId] is the entry
  /// card's, the same on every page. Only `vertical_av` items come back; live rooms and ads are dropped. Without the
  /// app token it throws [BiliError.noAppToken], and under an Android one a [StateError], with nothing sent.
  Future<List<StoryItem>> storyFeed({
    required int aid,
    required int cid,
    required int page,
    required PlaySource entry,
    String? trackId,
  }) => throw UnimplementedError('story-api');
}
