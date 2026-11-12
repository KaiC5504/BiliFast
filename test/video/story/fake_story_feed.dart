import 'package:bili_core/api.dart' show PlaySource;
import 'package:bilifast/video/story/story_feed.dart';

/// 竖屏's feed over a fixed list, recording each move; [onMove] runs with the entry moved to, as the app's feed opens it.
class FakeStoryFeed extends StoryFeed {
  FakeStoryFeed(this.entries, {this.onMove});

  @override
  final List<StoryEntry> entries;

  void Function(StoryEntry entry)? onMove;

  /// The index after each move, in order.
  final moves = <int>[];
  bool disposed = false;
  int _index = 0;

  @override
  int get index => _index;

  @override
  bool get loading => false;

  @override
  bool moveNext() => _moveTo(_index + 1);

  @override
  bool movePrevious() => _moveTo(_index - 1);

  bool _moveTo(int index) {
    if (index < 0 || index >= entries.length) return false;
    _index = index;
    moves.add(index);
    onMove?.call(entries[index]);
    notifyListeners();
    return true;
  }

  /// More videos came in.
  void add(StoryEntry entry) {
    entries.add(entry);
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// A video in the feed; upright unless [width] and [height] say otherwise, with no pictures unless [cover] is given.
StoryEntry storyEntry(String bvid, {int width = 1080, int height = 1920, String cover = '', String? firstFrame}) =>
    StoryEntry(
      bvid: bvid,
      title: '视频 $bvid',
      cover: cover,
      firstFrame: firstFrame,
      width: width,
      height: height,
      ownerMid: 1,
      ownerName: 'UP',
      source: PlaySource.unknown,
    );

/// A picture's address on Bilibili's CDN, named [name].
String pic(String name) => 'https://i1.hdslb.com/bfs/archive/$name.jpg';
