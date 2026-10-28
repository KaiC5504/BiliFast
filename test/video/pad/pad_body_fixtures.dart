import 'package:bili_core/api.dart'
    show DescPart, OfficialKind, UploaderCard, VideoCard, VideoDetail, VideoOwner, VideoStat, VideoTag, VideoTagKind;

import '../../support/fake_video_actions.dart';

/// ipad/03's video, made up where the screenshot doesn't say.
VideoDetail padDetail({String bvid = 'BV1Fk4x7NqTz', int pubdate = 0, String? honor = '活动'}) => VideoDetail(
  bvid: bvid,
  aid: 1,
  title: '小猫们找朋友大会：深林山洞篇【AI全城创作者】',
  cover: '',
  pubdate: pubdate,
  duration: 254,
  desc: 'qwnrt?',
  descParts: const [DescPart(text: 'qwnrt?')],
  copyright: 1,
  owner: const VideoOwner(mid: 7, name: '山顶小松鼠', face: ''),
  stat: const VideoStat(view: 597000, danmaku: 77, reply: 63, favorite: 3741, coin: 176, share: 475, like: 3959),
  pages: const [],
  season: null,
  staff: const [],
  width: 1920,
  height: 1080,
  honor: honor,
  redirectURL: null,
  argueMessage: null,
);

const padUploader = UploaderCard(
  mid: 7,
  name: '山顶小松鼠',
  face: '',
  fans: 21000,
  videos: 519,
  isVip: false,
  following: false,
  official: OfficialKind.none,
);

const padTags = [
  VideoTag(id: 1, name: '乐乐', kind: VideoTagKind.normal),
  VideoTag(id: 2, name: '小蛙', kind: VideoTagKind.normal),
  VideoTag(id: 3, name: 'AI游戏全世界', kind: VideoTagKind.normal),
];

FakeVideoActions padActions() => FakeVideoActions(likeCount: 3959, coinCount: 176, favCount: 3741, shareCount: 475);

VideoCard padCard(String bvid, String title, String owner, int views, int danmaku, int duration) => VideoCard(
  aid: 2,
  bvid: bvid,
  cid: 3,
  title: title,
  cover: '',
  duration: duration,
  ownerMid: 4,
  ownerName: owner,
  views: views,
  danmaku: danmaku,
  likes: 1,
);

/// ipad/03's related rows after the ad.
final padRelated = [
  padCard('BV1r1', '小猫们跳房子大会–东边果园篇【AI全城创作者】', '木子_', 1703000, 679, 255),
  padCard('BV1r2', '从头到尾 细说小猫们', '云云书架s', 54000, 187, 206),
  padCard('BV1r3', '小猫们跳房子大会–旧城车站篇【AI全城创作者】', '木子_', 5585000, 1667, 270),
  padCard('BV1r4', '小妹帮爸爸做午饭', '午后小狗', 248000, 184, 64),
  padCard('BV1r5', '石头', '河边dot', 119000, 67, 61),
];
