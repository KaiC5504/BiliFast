import '../page_playback.dart';
import 'story_feed.dart';

/// The app's 竖屏 feed for [playback]'s video.
StoryFeed pageStoryFeed(PagePlayback playback) => _EnteredOnly(playback.storyEntry);

/// Stands in until the feed is built: the entered video alone.
class _EnteredOnly extends StoryFeed {
  _EnteredOnly(StoryEntry? entered) : entries = [?entered];

  @override
  final List<StoryEntry> entries;

  @override
  int get index => 0;

  @override
  bool get loading => false;

  @override
  bool moveNext() => false;

  @override
  bool movePrevious() => false;
}
