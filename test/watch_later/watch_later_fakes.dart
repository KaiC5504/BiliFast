import 'package:bili_core/api.dart';

/// A made-up row; [progress] -1 is watched to the end.
WatchLaterItem laterItem(int i, {int progress = 30, int duration = 300, String? title}) => WatchLaterItem(
  aid: 83000000 + i,
  bvid: 'BV1test$i',
  cid: 142000000 + i,
  title: title ?? '测试视频 $i',
  cover: '',
  ownerMid: 900 + i,
  ownerName: '测试UP$i',
  duration: duration,
  progress: progress,
  play: 1000 + i,
  danmaku: i,
);

List<WatchLaterItem> laterItems(int count) => [for (var i = 1; i <= count; i++) laterItem(i)];

const testFolders = [
  FavFolder(id: 9101, title: '默认收藏夹', count: 0, isPrivate: false, contains: false, isDefault: true),
  FavFolder(id: 9102, title: '测试收藏夹', count: 8, isPrivate: true, contains: false, isDefault: false),
];
