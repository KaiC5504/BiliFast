import 'package:bili_core/engine.dart' show LocalPlaybackRequest;
import 'package:flutter/foundation.dart';

/// The 合集 a part was cached from; 离线缓存 groups its parts under [title] (155, 156).
@immutable
final class OfflineCollection {
  const OfflineCollection({required this.id, required this.title});

  final int id;
  final String title;

  Map<String, Object?> toJson() => {'id': id, 'title': title};

  static OfflineCollection? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    return id is int && title is String ? OfflineCollection(id: id, title: title) : null;
  }

  @override
  bool operator ==(Object other) => other is OfflineCollection && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);
}

/// One part to cache, as the 缓存 sheet knows it: what 离线缓存 shows of it is kept with the files, so it lasts after
/// Bilibili removes the video.
@immutable
final class OfflineRequest {
  const OfflineRequest({
    required this.bvid,
    required this.aid,
    required this.cid,
    required this.title,
    required this.duration,
    required this.cover,
    required this.ownerMid,
    required this.ownerName,
    this.page = 1,
    this.partTitle,
    this.ownerFace = '',
    this.collection,
  });

  final String bvid;
  final int aid;
  final int cid;

  /// The video's title.
  final String title;

  /// Seconds.
  final int duration;
  final String cover;
  final int ownerMid;
  final String ownerName;
  final String ownerFace;

  /// 1-based part number; [partTitle] is null for a video of one part.
  final int page;
  final String? partTitle;
  final OfflineCollection? collection;

  Map<String, Object?> toJson() => {
    'bvid': bvid,
    'aid': aid,
    'cid': cid,
    'title': title,
    'duration': duration,
    'cover': cover,
    'ownerMid': ownerMid,
    'ownerName': ownerName,
    'ownerFace': ownerFace,
    'page': page,
    'partTitle': ?partTitle,
    'collection': ?collection?.toJson(),
  };

  static OfflineRequest? fromJson(Object? json) {
    if (json is! Map) return null;
    final bvid = json['bvid'];
    final aid = json['aid'];
    final cid = json['cid'];
    final title = json['title'];
    if (bvid is! String || aid is! int || cid is! int || title is! String) return null;
    final duration = json['duration'];
    final page = json['page'];
    final ownerMid = json['ownerMid'];
    final partTitle = json['partTitle'];
    return OfflineRequest(
      bvid: bvid,
      aid: aid,
      cid: cid,
      title: title,
      duration: duration is int ? duration : 0,
      cover: '${json['cover'] ?? ''}',
      ownerMid: ownerMid is int ? ownerMid : 0,
      ownerName: '${json['ownerName'] ?? ''}',
      ownerFace: '${json['ownerFace'] ?? ''}',
      page: page is int ? page : 1,
      partTitle: partTitle is String ? partTitle : null,
      collection: OfflineCollection.fromJson(json['collection']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OfflineRequest && other.cid == cid && other.bvid == bvid && other.title == title;

  @override
  int get hashCode => Object.hash(cid, bvid, title);
}

/// 等待缓存, 缓存中, 已暂停, failed (the row says why), 已缓存.
enum OfflineState { waiting, downloading, paused, failed, done }

enum OfflineFailure {
  /// Every try failed on the network; a tap or 全部开始 tries again.
  network,

  /// The phone is full.
  disk,

  /// Bilibili no longer serves the video (removed, or the account can't watch it).
  unavailable,

  /// Something else; the log says what.
  unknown,
}

/// One part kept on the phone, finished or not.
@immutable
final class OfflineItem {
  const OfflineItem({
    required this.request,
    required this.state,
    required this.addedAt,
    this.failure,
    this.quality = 0,
    this.qualityName = '',
    this.vipOnly = false,
    this.bytes = 0,
    this.totalBytes = 0,
    this.bps = 0,
    this.position = 0,
    this.coverFile,
    this.faceFile,
  });

  final OfflineRequest request;
  final OfflineState state;
  final OfflineFailure? failure;
  final DateTime addedAt;

  /// The quality it is cached at, 0 until the playurl answer picks one.
  final int quality;
  final String qualityName;

  /// A 大会员 quality: 离线缓存 writes 大会员专享 before the size (156).
  final bool vipOnly;

  /// Bytes on the phone and the whole, both tracks; [totalBytes] is 0 until the sizes are known.
  final int bytes;
  final int totalBytes;

  /// Download speed while [OfflineState.downloading].
  final double bps;

  /// Seconds watched, for the cover's 00:23 / 06:23 and its pink line (145).
  final double position;

  /// The saved cover and uploader face on the phone; null until saved (draw [OfflineRequest.cover] meanwhile).
  final String? coverFile;
  final String? faceFile;

  int get cid => request.cid;
  bool get isDone => state == OfflineState.done;
  double get progress => totalBytes <= 0 ? 0 : (bytes / totalBytes).clamp(0, 1).toDouble();

  OfflineItem copyWith({
    OfflineState? state,
    OfflineFailure? failure,
    bool clearFailure = false,
    int? quality,
    String? qualityName,
    bool? vipOnly,
    int? bytes,
    int? totalBytes,
    double? bps,
    double? position,
    String? coverFile,
    String? faceFile,
  }) => OfflineItem(
    request: request,
    state: state ?? this.state,
    failure: clearFailure ? null : failure ?? this.failure,
    addedAt: addedAt,
    quality: quality ?? this.quality,
    qualityName: qualityName ?? this.qualityName,
    vipOnly: vipOnly ?? this.vipOnly,
    bytes: bytes ?? this.bytes,
    totalBytes: totalBytes ?? this.totalBytes,
    bps: bps ?? this.bps,
    position: position ?? this.position,
    coverFile: coverFile ?? this.coverFile,
    faceFile: faceFile ?? this.faceFile,
  );

  @override
  bool operator ==(Object other) =>
      other is OfflineItem &&
      other.request == request &&
      other.state == state &&
      other.failure == failure &&
      other.addedAt == addedAt &&
      other.quality == quality &&
      other.qualityName == qualityName &&
      other.vipOnly == vipOnly &&
      other.bytes == bytes &&
      other.totalBytes == totalBytes &&
      other.bps == bps &&
      other.position == position &&
      other.coverFile == coverFile &&
      other.faceFile == faceFile;

  @override
  int get hashCode => Object.hash(
    request,
    state,
    failure,
    addedAt,
    quality,
    qualityName,
    vipOnly,
    bytes,
    totalBytes,
    bps,
    position,
    coverFile,
    faceFile,
  );
}

/// What playing a finished part needs: its files for the engine, and its saved danmaku (`[danmakuFolder]/1.so` …
/// `[danmakuSegments].so`, each one 6-minute `seg.so` answer as Bilibili sent it).
@immutable
final class OfflinePlayback {
  const OfflinePlayback({required this.item, required this.files, this.danmakuFolder, this.danmakuSegments = 0});

  final OfflineItem item;
  final LocalPlaybackRequest files;
  final String? danmakuFolder;
  final int danmakuSegments;
}
