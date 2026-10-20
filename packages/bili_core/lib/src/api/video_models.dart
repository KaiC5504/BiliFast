import 'json.dart';
import 'models.dart';

final class VideoOwner {
  const VideoOwner({required this.mid, required this.name, required this.face});

  factory VideoOwner.fromJson(Object? json) {
    final object = JsonObject.from(json);
    return VideoOwner(
      mid: object.integer('mid') ?? 0,
      name: object.string('name') ?? '',
      face: object.string('face') ?? '',
    );
  }

  static const empty = VideoOwner(mid: 0, name: '', face: '');

  final int mid;
  final String name;
  final String face;

  @override
  bool operator ==(Object other) => other is VideoOwner && other.mid == mid && other.name == name && other.face == face;

  @override
  int get hashCode => Object.hash(mid, name, face);
}

final class VideoStat {
  const VideoStat({
    required this.view,
    required this.danmaku,
    required this.reply,
    required this.favorite,
    required this.coin,
    required this.share,
    required this.like,
  });

  factory VideoStat.fromJson(Object? json) {
    final object = JsonObject.from(json);
    return VideoStat(
      view: object.count('view'),
      danmaku: object.count('danmaku'),
      reply: object.count('reply'),
      favorite: object.count('favorite', 'fav'),
      coin: object.count('coin'),
      share: object.count('share'),
      like: object.count('like'),
    );
  }

  static const zero = VideoStat(view: 0, danmaku: 0, reply: 0, favorite: 0, coin: 0, share: 0, like: 0);

  final int view;
  final int danmaku;
  final int reply;
  final int favorite;
  final int coin;
  final int share;
  final int like;

  @override
  bool operator ==(Object other) =>
      other is VideoStat &&
      other.view == view &&
      other.danmaku == danmaku &&
      other.reply == reply &&
      other.favorite == favorite &&
      other.coin == coin &&
      other.share == share &&
      other.like == like;

  @override
  int get hashCode => Object.hash(view, danmaku, reply, favorite, coin, share, like);
}

final class DescPart {
  const DescPart({required this.text, this.mentionMid});

  final String text;
  final int? mentionMid;

  @override
  bool operator ==(Object other) => other is DescPart && other.text == text && other.mentionMid == mentionMid;

  @override
  int get hashCode => Object.hash(text, mentionMid);

  @override
  String toString() => 'DescPart($text, mentionMid: $mentionMid)';
}

/// Null for an entry without text, which the description simply skips.
DescPart? _descEntry(Object? json) {
  final object = JsonObject.from(json);
  final text = object.string('raw_text');
  if (text == null) return null;
  final mid = object.integer('type') == 2 ? object.integer('biz_id') : null;
  return DescPart(text: text, mentionMid: mid);
}

final class SeasonEpisode {
  const SeasonEpisode({
    required this.aid,
    required this.bvid,
    required this.cid,
    required this.title,
    required this.cover,
    required this.duration,
    required this.pubdate,
    required this.views,
    required this.danmaku,
  });

  factory SeasonEpisode.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final arc = object.nested('arc');
    final page = object.nested('page');
    final bvid = object.string('bvid') ?? arc?.string('bvid');
    if (bvid == null || bvid.isEmpty) throw const DecodeError('missing bvid');
    final cid = object.integer('cid') ?? page?.integer('cid');
    if (cid == null) throw const DecodeError('missing cid');
    final stat = arc?.nested('stat');
    return SeasonEpisode(
      aid: object.integer('aid') ?? arc?.integer('aid') ?? 0,
      bvid: bvid,
      cid: cid,
      title: object.string('title') ?? arc?.string('title') ?? '',
      cover: arc?.string('pic') ?? '',
      duration: arc?.integer('duration') ?? page?.integer('duration') ?? 0,
      pubdate: arc?.integer('pubdate') ?? 0,
      views: stat?.count('view') ?? 0,
      danmaku: stat?.count('danmaku') ?? 0,
    );
  }

  final int aid;
  final String bvid;
  final int cid;
  final String title;
  final String cover;
  final int duration;
  final int pubdate;
  final int views;
  final int danmaku;

  @override
  bool operator ==(Object other) =>
      other is SeasonEpisode &&
      other.aid == aid &&
      other.bvid == bvid &&
      other.cid == cid &&
      other.title == title &&
      other.cover == cover &&
      other.duration == duration &&
      other.pubdate == pubdate &&
      other.views == views &&
      other.danmaku == danmaku;

  @override
  int get hashCode => Object.hash(aid, bvid, cid, title, cover, duration, pubdate, views, danmaku);
}

final class SeasonSection {
  const SeasonSection({required this.id, required this.title, required this.episodes});

  factory SeasonSection.fromJson(Object? json) {
    final object = JsonObject.from(json);
    return SeasonSection(
      id: object.integer('id') ?? 0,
      title: object.string('title') ?? '',
      episodes: object.lossyList('episodes', SeasonEpisode.fromJson),
    );
  }

  final int id;
  final String title;
  final List<SeasonEpisode> episodes;

  @override
  bool operator ==(Object other) =>
      other is SeasonSection && other.id == id && other.title == title && listEquals(other.episodes, episodes);

  @override
  int get hashCode => Object.hash(id, title, Object.hashAll(episodes));
}

final class UgcSeason {
  const UgcSeason({required this.id, required this.title, required this.intro, required this.sections});

  factory UgcSeason.fromJson(Object? json) {
    final object = JsonObject.from(json);
    return UgcSeason(
      id: object.integer('id') ?? 0,
      title: object.string('title') ?? '',
      intro: object.string('intro') ?? '',
      sections: object.lossyList('sections', SeasonSection.fromJson),
    );
  }

  final int id;
  final String title;
  final String intro;
  final List<SeasonSection> sections;

  @override
  bool operator ==(Object other) =>
      other is UgcSeason &&
      other.id == id &&
      other.title == title &&
      other.intro == intro &&
      listEquals(other.sections, sections);

  @override
  int get hashCode => Object.hash(id, title, intro, Object.hashAll(sections));
}

final class StaffMember {
  const StaffMember({required this.mid, required this.title, required this.name, required this.face});

  factory StaffMember.fromJson(Object? json) {
    final object = JsonObject.from(json);
    return StaffMember(
      mid: object.integer('mid') ?? 0,
      title: object.string('title') ?? '',
      name: object.string('name') ?? '',
      face: object.string('face') ?? '',
    );
  }

  final int mid;
  final String title;
  final String name;
  final String face;

  @override
  bool operator ==(Object other) =>
      other is StaffMember && other.mid == mid && other.title == title && other.name == name && other.face == face;

  @override
  int get hashCode => Object.hash(mid, title, name, face);
}

final class VideoDetail {
  const VideoDetail({
    required this.bvid,
    required this.aid,
    required this.title,
    required this.cover,
    required this.pubdate,
    required this.duration,
    required this.desc,
    required this.descParts,
    required this.copyright,
    required this.owner,
    required this.stat,
    required this.pages,
    required this.season,
    required this.staff,
    required this.width,
    required this.height,
    required this.honor,
    required this.redirectURL,
    this.argueMessage,
  });

  factory VideoDetail.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final bvid = object.required(object.string('bvid'), 'bvid');
    final desc = object.string('desc') ?? '';
    final parts = [for (final part in object.lenientList('desc_v2', _descEntry)) ?part];
    final dimension = object.nested('dimension');
    final rawWidth = dimension?.integer('width') ?? 0;
    final rawHeight = dimension?.integer('height') ?? 0;
    final rotated = dimension?.integer('rotate') == 1;
    final honors = object
        .nested('honor_reply')
        ?.lenientList('honor', (json) => JsonObject.from(json).string('desc') ?? '');
    final redirect = object.string('redirect_url');
    final argue = object.nested('argue_info')?.text('argue_msg');
    return VideoDetail(
      bvid: bvid,
      aid: object.integer('aid') ?? 0,
      title: object.string('title') ?? '',
      cover: object.string('pic') ?? '',
      pubdate: object.integer('pubdate') ?? 0,
      duration: object.integer('duration') ?? 0,
      desc: desc,
      descParts: parts.isEmpty && desc.isNotEmpty ? [DescPart(text: desc)] : parts,
      copyright: object.integer('copyright') ?? 0,
      owner: attempt(() => _optional(object.map['owner'], VideoOwner.fromJson)) ?? VideoOwner.empty,
      stat: attempt(() => _optional(object.map['stat'], VideoStat.fromJson)) ?? VideoStat.zero,
      pages: object.lossyList('pages', VideoPage.fromJson),
      season: attempt(() => _optional(object.map['ugc_season'], UgcSeason.fromJson)),
      staff: object.lenientList('staff', StaffMember.fromJson),
      width: rotated ? rawHeight : rawWidth,
      height: rotated ? rawWidth : rawHeight,
      honor: honors?.where((desc) => desc.isNotEmpty).firstOrNull,
      redirectURL: redirect == null || redirect.isEmpty ? null : redirect,
      argueMessage: argue == null || argue.trim().isEmpty ? null : argue,
    );
  }

  final String bvid;
  final int aid;
  final String title;
  final String cover;
  final int pubdate;
  final int duration;
  final String desc;
  final List<DescPart> descParts;
  final int copyright;
  final VideoOwner owner;
  final VideoStat stat;
  final List<VideoPage> pages;
  final UgcSeason? season;
  final List<StaffMember> staff;

  /// The shape as displayed: already swapped when the file is stored rotated (`dimension.rotate == 1`).
  final int width;
  final int height;
  final String? honor;

  /// Set for bangumi and other pages the ordinary video page cannot show.
  final String? redirectURL;

  /// The notice the site puts under the stats, such as 个人观点，仅供参考 (`argue_info.argue_msg`); null when none.
  final String? argueMessage;

  bool get isVertical => height > width;

  @override
  bool operator ==(Object other) =>
      other is VideoDetail &&
      other.bvid == bvid &&
      other.aid == aid &&
      other.title == title &&
      other.cover == cover &&
      other.pubdate == pubdate &&
      other.duration == duration &&
      other.desc == desc &&
      listEquals(other.descParts, descParts) &&
      other.copyright == copyright &&
      other.owner == owner &&
      other.stat == stat &&
      listEquals(other.pages, pages) &&
      other.season == season &&
      listEquals(other.staff, staff) &&
      other.width == width &&
      other.height == height &&
      other.honor == honor &&
      other.redirectURL == redirectURL &&
      other.argueMessage == argueMessage;

  @override
  int get hashCode => Object.hashAll([
    bvid, aid, title, cover, pubdate, duration, desc, Object.hashAll(descParts), copyright, owner, stat, //
    Object.hashAll(pages), season, Object.hashAll(staff), width, height, honor, redirectURL, argueMessage,
  ]);
}

T? _optional<T>(Object? json, T Function(Object? json) decode) => json == null ? null : decode(json);

final class Chapter {
  const Chapter({required this.from, required this.to, required this.title});

  final double from;
  final double to;
  final String title;

  @override
  bool operator ==(Object other) => other is Chapter && other.from == from && other.to == to && other.title == title;

  @override
  int get hashCode => Object.hash(from, to, title);

  @override
  String toString() => 'Chapter($from-$to, $title)';
}

final class PlayerInfo {
  const PlayerInfo({required this.lastPlayCid, required this.chapters});

  factory PlayerInfo.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final points = object.lossyList('view_points', (json) {
      final point = JsonObject.from(json);
      return (
        type: point.integer('type') ?? 0,
        chapter: Chapter(
          from: point.number('from') ?? 0,
          to: point.number('to') ?? 0,
          title: point.string('content') ?? '',
        ),
      );
    });
    return PlayerInfo(
      lastPlayCid: object.integer('last_play_cid') ?? 0,
      // type 1 is the uploader's highlight marks, not a chapter list.
      chapters: points.firstOrNull?.type == 2
          ? [
              for (final point in points)
                if (point.type == 2) point.chapter,
            ]
          : [],
    );
  }

  final int lastPlayCid;
  final List<Chapter> chapters;

  @override
  bool operator ==(Object other) =>
      other is PlayerInfo && other.lastPlayCid == lastPlayCid && listEquals(other.chapters, chapters);

  @override
  int get hashCode => Object.hash(lastPlayCid, Object.hashAll(chapters));
}

final class VideoCard {
  const VideoCard({
    required this.aid,
    required this.bvid,
    required this.cid,
    required this.title,
    required this.cover,
    required this.duration,
    required this.ownerMid,
    required this.ownerName,
    required this.views,
    required this.danmaku,
    required this.likes,
  });

  factory VideoCard.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final bvid = object.string('bvid');
    if (bvid == null || bvid.isEmpty) throw const DecodeError('missing bvid');
    final owner = object.nested('owner');
    final stat = object.nested('stat');
    return VideoCard(
      aid: object.integer('aid') ?? 0,
      bvid: bvid,
      cid: object.integer('cid') ?? 0,
      title: object.string('title') ?? '',
      cover: object.string('pic') ?? '',
      duration: object.integer('duration') ?? 0,
      ownerMid: owner?.integer('mid') ?? 0,
      ownerName: owner?.string('name') ?? '',
      views: stat?.count('view') ?? 0,
      danmaku: stat?.count('danmaku') ?? 0,
      likes: stat?.count('like') ?? 0,
    );
  }

  final int aid;
  final String bvid;
  final int cid;
  final String title;
  final String cover;
  final int duration;
  final int ownerMid;
  final String ownerName;
  final int views;
  final int danmaku;
  final int likes;

  @override
  bool operator ==(Object other) =>
      other is VideoCard &&
      other.aid == aid &&
      other.bvid == bvid &&
      other.cid == cid &&
      other.title == title &&
      other.cover == cover &&
      other.duration == duration &&
      other.ownerMid == ownerMid &&
      other.ownerName == ownerName &&
      other.views == views &&
      other.danmaku == danmaku &&
      other.likes == likes;

  @override
  int get hashCode => Object.hash(aid, bvid, cid, title, cover, duration, ownerMid, ownerName, views, danmaku, likes);
}
