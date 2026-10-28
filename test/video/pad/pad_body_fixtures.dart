import 'package:bili_core/api.dart'
    show DescPart, OfficialKind, UploaderCard, VideoCard, VideoDetail, VideoOwner, VideoStat, VideoTag, VideoTagKind;

import '../../support/fake_video_actions.dart';

/// ipad/03's video, made up where the screenshot doesn't say.
VideoDetail padDetail({String bvid = 'BV1a8xK6MEfM', int pubdate = 0, String? honor = '活动'}) => VideoDetail(
  bvid: bvid,
  aid: 1,
  title: '奶家人捉迷藏大赛：幽邃地窟篇【AI全民制作人】',
  cover: '',
  pubdate: pubdate,
  duration: 254,
  desc: 'kskbl?',
  descParts: const [DescPart(text: 'kskbl?')],
  copyright: 1,
  owner: const VideoOwner(mid: 7, name: '暴风城老鼠', face: ''),
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
  name: '暴风城老鼠',
  face: '',
  fans: 21000,
  videos: 519,
  isVip: false,
  following: false,
  official: OfficialKind.none,
);

const padTags = [
  VideoTag(id: 1, name: '康康', kind: VideoTagKind.normal),
  VideoTag(id: 2, name: '奶蛙', kind: VideoTagKind.normal),
  VideoTag(id: 3, name: 'AI整活全宇宙', kind: VideoTagKind.normal),
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
  padCard('BV1r1', '奶家人躲猫猫大赛–南瓜庄园篇【AI全民制作人】', '奶史_', 1703000, 679, 255),
  padCard('BV1r2', '从夯到区 锐评奶家人', '史史事托s', 54000, 187, 206),
  padCard('BV1r3', '奶家人躲猫猫大赛–废弃医院篇【AI全民制作人】', '奶史_', 5585000, 1667, 270),
  padCard('BV1r4', '奶妹帮哥哥做早晨', '防御老猫', 248000, 184, 64),
  padCard('BV1r5', '奶石', '流道did', 119000, 67, 61),
];
