import 'dart:convert';

import '../shared/byte_range.dart';
import 'json.dart';

typedef JsonDecode<T> = T Function(Object? json);

final class BiliEnvelope<T> {
  const BiliEnvelope({required this.code, this.message, this.data});

  final int code;
  final String? message;
  final T? data;

  /// Error replies carry data of another shape, or none; only a success must decode strictly.
  static BiliEnvelope<T> decode<T>(Object? json, JsonDecode<T> decodeData) {
    final object = JsonObject.from(json, 'envelope');
    final code = object.required(object.integer('code'), 'code');
    final message = object.string('message');
    final raw = object.map['data'];
    final T? data;
    if (raw == null) {
      data = null;
    } else if (code == 0) {
      data = decodeData(raw);
    } else {
      T? lenient;
      try {
        lenient = decodeData(raw);
      } on DecodeError {
        lenient = null;
      }
      data = lenient;
    }
    return BiliEnvelope(code: code, message: message, data: data);
  }

  /// Parses a response body; invalid JSON is a [DecodeError] like any other shape problem.
  static BiliEnvelope<T> parse<T>(String body, JsonDecode<T> decodeData) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException catch (error) {
      throw DecodeError('invalid JSON: ${error.message}');
    }
    return decode(json, decodeData);
  }
}

final class NavInfo {
  const NavInfo({
    required this.isLogin,
    this.mid,
    this.uname,
    this.face,
    this.vipStatus = 0,
    this.vipType = 0,
    this.imgURL = '',
    this.subURL = '',
  });

  factory NavInfo.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final images = object.nested('wbi_img');
    return NavInfo(
      isLogin: object.boolean('isLogin') ?? false,
      mid: object.integer('mid'),
      uname: object.string('uname'),
      face: object.string('face'),
      vipStatus: object.integer('vipStatus') ?? 0,
      vipType: object.integer('vipType') ?? 0,
      imgURL: images?.string('img_url') ?? '',
      subURL: images?.string('sub_url') ?? '',
    );
  }

  final bool isLogin;
  final int? mid;
  final String? uname;
  final String? face;
  final int vipStatus;
  final int vipType;
  final String imgURL;
  final String subURL;

  bool get isVip => vipStatus == 1;

  @override
  bool operator ==(Object other) =>
      other is NavInfo &&
      other.isLogin == isLogin &&
      other.mid == mid &&
      other.uname == uname &&
      other.face == face &&
      other.vipStatus == vipStatus &&
      other.vipType == vipType &&
      other.imgURL == imgURL &&
      other.subURL == subURL;

  @override
  int get hashCode => Object.hash(isLogin, mid, uname, face, vipStatus, vipType, imgURL, subURL);
}

final class SPIInfo {
  const SPIInfo({required this.b3, required this.b4});

  factory SPIInfo.fromJson(Object? json) {
    final object = JsonObject.from(json);
    return SPIInfo(
      b3: object.required(object.string('b_3'), 'b_3'),
      b4: object.required(object.string('b_4'), 'b_4'),
    );
  }

  final String b3;
  final String b4;
}

final class VideoPage {
  const VideoPage({required this.cid, required this.page, required this.part, required this.duration});

  factory VideoPage.fromJson(Object? json) {
    final object = JsonObject.from(json);
    return VideoPage(
      cid: object.required(object.integer('cid'), 'cid'),
      page: object.required(object.integer('page'), 'page'),
      part: object.required(object.string('part'), 'part'),
      duration: object.required(object.integer('duration'), 'duration'),
    );
  }

  final int cid;
  final int page;
  final String part;
  final int duration;

  @override
  bool operator ==(Object other) =>
      other is VideoPage && other.cid == cid && other.page == page && other.part == part && other.duration == duration;

  @override
  int get hashCode => Object.hash(cid, page, part, duration);
}

final class VideoView {
  const VideoView({required this.bvid, this.aid = 0, this.title = '', this.owner, this.pages = const []});

  factory VideoView.fromJson(Object? json) {
    final object = JsonObject.from(json);
    return VideoView(
      bvid: object.required(object.string('bvid'), 'bvid'),
      aid: object.integer('aid') ?? 0,
      title: object.string('title') ?? '',
      owner: object.nested('owner')?.string('name'),
      pages: strictList(object.list('pages'), VideoPage.fromJson),
    );
  }

  final String bvid;
  final int aid;
  final String title;
  final String? owner;
  final List<VideoPage> pages;

  @override
  bool operator ==(Object other) =>
      other is VideoView &&
      other.bvid == bvid &&
      other.aid == aid &&
      other.title == title &&
      other.owner == owner &&
      listEquals(other.pages, pages);

  @override
  int get hashCode => Object.hash(bvid, aid, title, owner, Object.hashAll(pages));
}

final class DashStream {
  const DashStream({
    required this.id,
    required this.baseURL,
    required this.backupURLs,
    required this.bandwidth,
    required this.mimeType,
    required this.codecs,
    required this.codecid,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.initialization,
    required this.indexRange,
  });

  factory DashStream.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final rate = object.string('frameRate', 'frame_rate');
    ({ByteRange start, ByteRange index})? ranges;
    for (final key in const ['SegmentBase', 'segment_base']) {
      final segmentBase = object.nested(key);
      if (segmentBase == null) continue;
      final start = attempt(() => segmentBase.string('Initialization', 'initialization'));
      final index = attempt(() => segmentBase.string('indexRange', 'index_range'));
      final startRange = start == null ? null : ByteRange.parse(start);
      final indexRange = index == null ? null : ByteRange.parse(index);
      if (startRange != null && indexRange != null) {
        ranges = (start: startRange, index: indexRange);
        break;
      }
    }
    if (ranges == null) throw const DecodeError('missing SegmentBase');
    return DashStream(
      id: object.integer('id') ?? 0,
      baseURL: object.required(object.string('baseUrl', 'base_url'), 'baseUrl'),
      backupURLs: strictList(object.list('backupUrl', 'backup_url'), (value) => asString(value, 'backupUrl')),
      bandwidth: object.integer('bandwidth') ?? 0,
      mimeType: object.string('mimeType', 'mime_type') ?? '',
      codecs: object.string('codecs') ?? '',
      codecid: object.integer('codecid') ?? 0,
      width: object.integer('width') ?? 0,
      height: object.integer('height') ?? 0,
      frameRate: rate == null || rate.isEmpty ? null : rate,
      initialization: ranges.start,
      indexRange: ranges.index,
    );
  }

  final int id;
  final String baseURL;
  final List<String> backupURLs;
  final int bandwidth;
  final String mimeType;
  final String codecs;
  final int codecid;
  final int width;
  final int height;
  final String? frameRate;
  final ByteRange initialization;
  final ByteRange indexRange;

  @override
  bool operator ==(Object other) =>
      other is DashStream &&
      other.id == id &&
      other.baseURL == baseURL &&
      listEquals(other.backupURLs, backupURLs) &&
      other.bandwidth == bandwidth &&
      other.mimeType == mimeType &&
      other.codecs == codecs &&
      other.codecid == codecid &&
      other.width == width &&
      other.height == height &&
      other.frameRate == frameRate &&
      other.initialization == initialization &&
      other.indexRange == indexRange;

  @override
  int get hashCode => Object.hash(id, baseURL, Object.hashAll(backupURLs), bandwidth, mimeType, codecs, codecid, width,
      height, frameRate, initialization, indexRange);
}

final class Dash {
  const Dash({required this.duration, required this.video, required this.audio});

  factory Dash.fromJson(Object? json) {
    final object = JsonObject.from(json);
    return Dash(
      duration: object.integer('duration') ?? 0,
      video: object.lossyList('video', DashStream.fromJson),
      audio: object.lossyList('audio', DashStream.fromJson),
    );
  }

  final int duration;
  final List<DashStream> video;
  final List<DashStream> audio;

  @override
  bool operator ==(Object other) =>
      other is Dash && other.duration == duration && listEquals(other.video, video) && listEquals(other.audio, audio);

  @override
  int get hashCode => Object.hash(duration, Object.hashAll(video), Object.hashAll(audio));
}

final class QualityOption {
  const QualityOption({required this.id, required this.name});

  final int id;
  final String name;

  @override
  bool operator ==(Object other) => other is QualityOption && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'QualityOption($id, $name)';
}

final class PlayURLInfo {
  const PlayURLInfo({
    required this.quality,
    required this.acceptQuality,
    required this.acceptDescription,
    required this.dash,
    required this.hasDurl,
    this.lastPlayTimeMs = 0,
    this.lastPlayCid = 0,
  });

  factory PlayURLInfo.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final durl = object.map['durl'];
    final dash = object.map['dash'];
    return PlayURLInfo(
      quality: object.integer('quality') ?? 0,
      acceptQuality: strictList(object.list('accept_quality'), (value) => asRequiredInt(value, 'accept_quality')),
      acceptDescription: strictList(object.list('accept_description'), (value) => asString(value, 'accept_description')),
      dash: dash == null ? null : Dash.fromJson(dash),
      hasDurl: durl is List && durl.isNotEmpty,
      lastPlayTimeMs: object.integer('last_play_time') ?? 0,
      lastPlayCid: object.integer('last_play_cid') ?? 0,
    );
  }

  final int quality;
  final List<int> acceptQuality;
  final List<String> acceptDescription;
  final Dash? dash;
  final bool hasDurl;
  final int lastPlayTimeMs;
  final int lastPlayCid;

  List<QualityOption> get qualityOptions => [
        for (var index = 0; index < acceptQuality.length && index < acceptDescription.length; index++)
          QualityOption(id: acceptQuality[index], name: acceptDescription[index]),
      ];
}
