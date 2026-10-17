import '../ripper/byte_range.dart';

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
String _str(Object? v) => v is String ? v : (v == null ? '' : '$v');

class FeedCard {
  FeedCard({
    required this.bvid,
    required this.cid,
    required this.title,
    required this.cover,
    required this.duration,
    required this.views,
    required this.danmaku,
    required this.ownerName,
    required this.reason,
  });

  final String bvid;
  final int cid;
  final String title;
  final String cover;
  final int duration;
  final int views;
  final int danmaku;
  final String ownerName;
  final String? reason;

  /// Ads and live rooms share the list; only `goto == "av"` rows are videos.
  static FeedCard? tryParse(Map<String, dynamic> item) {
    if (item['goto'] != 'av') return null;
    final bvid = _str(item['bvid']);
    if (bvid.isEmpty) return null;
    final stat = (item['stat'] as Map?) ?? const {};
    final owner = (item['owner'] as Map?) ?? const {};
    final reason = _str((item['rcmd_reason'] as Map?)?['content']);
    return FeedCard(
      bvid: bvid,
      cid: _int(item['cid']),
      title: _str(item['title']),
      cover: _str(item['pic']),
      duration: _int(item['duration']),
      views: _int(stat['view']),
      danmaku: _int(stat['danmaku']),
      ownerName: _str(owner['name']),
      reason: reason.isEmpty ? null : reason,
    );
  }
}

class DashStream {
  DashStream({
    required this.id,
    required this.baseUrl,
    required this.backupUrls,
    required this.bandwidth,
    required this.codecs,
    required this.codecid,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.initialization,
    required this.indexRange,
  });

  final int id;
  final String baseUrl;
  final List<String> backupUrls;
  final int bandwidth;
  final String codecs;
  final int codecid;
  final int width;
  final int height;
  final String frameRate;
  final ByteRange initialization;
  final ByteRange indexRange;

  static DashStream? tryParse(Map<String, dynamic> j) {
    final base = j['baseUrl'] ?? j['base_url'];
    if (base is! String) return null;
    final seg = (j['SegmentBase'] ?? j['segment_base']) as Map?;
    final init = ByteRange.parse(_str(seg?['Initialization'] ?? seg?['initialization']));
    final index = ByteRange.parse(_str(seg?['indexRange'] ?? seg?['index_range']));
    if (init == null || index == null) return null;
    return DashStream(
      id: _int(j['id']),
      baseUrl: base,
      backupUrls: [for (final u in (j['backupUrl'] ?? j['backup_url'] ?? const []) as List) _str(u)],
      bandwidth: _int(j['bandwidth']),
      codecs: _str(j['codecs']),
      codecid: _int(j['codecid']),
      width: _int(j['width']),
      height: _int(j['height']),
      frameRate: _str(j['frameRate'] ?? j['frame_rate']),
      initialization: init,
      indexRange: index,
    );
  }

  String get codecLabel {
    if (codecs.startsWith('dvh1') || codecs.startsWith('dvhe') || id == 126) return 'Dolby Vision';
    return switch (codecid) { 12 => 'HEVC', 13 => 'AV1', 7 => 'H.264', _ => codecs };
  }
}

class PlayInfo {
  PlayInfo({required this.quality, required this.qualities, required this.durationS, required this.video, required this.audio});

  final int quality;
  final Map<int, String> qualities;
  final int durationS;
  final List<DashStream> video;
  final List<DashStream> audio;

  static PlayInfo parse(Map<String, dynamic> data) {
    final dash = data['dash'] as Map<String, dynamic>?;
    if (dash == null) throw const FormatException('not a DASH response');
    final ids = [for (final q in (data['accept_quality'] ?? const []) as List) _int(q)];
    final names = [for (final q in (data['accept_description'] ?? const []) as List) _str(q)];
    return PlayInfo(
      quality: _int(data['quality']),
      qualities: {for (var i = 0; i < ids.length && i < names.length; i++) ids[i]: names[i]},
      durationS: _int(dash['duration']),
      video: [for (final v in (dash['video'] ?? const []) as List) ?DashStream.tryParse(v as Map<String, dynamic>)],
      audio: [for (final v in (dash['audio'] ?? const []) as List) ?DashStream.tryParse(v as Map<String, dynamic>)],
    );
  }

  /// The highest quality not above `maxQuality`, then the first codec of `codecOrder` it has.
  (DashStream, DashStream)? choose(int maxQuality, {List<int> codecOrder = const [12, 7, 13]}) {
    const audioRank = {30280: 3, 30232: 2, 30216: 1};
    final aac = audio.where((a) => a.codecs.startsWith('mp4a')).toList()
      ..sort((a, b) => (audioRank[b.id] ?? 0).compareTo(audioRank[a.id] ?? 0));
    if (aac.isEmpty || video.isEmpty) return null;
    final ids = video.map((v) => v.id).toSet().toList()..sort((a, b) => b.compareTo(a));
    final picked = ids.firstWhere((q) => q <= maxQuality, orElse: () => ids.last);
    final candidates = video.where((v) => v.id == picked).toList();
    for (final codec in codecOrder) {
      for (final v in candidates) {
        if (v.codecid == codec) return (v, aac.first);
      }
    }
    return (candidates.first, aac.first);
  }
}

class VideoInfo {
  VideoInfo({required this.bvid, required this.cid, required this.title, required this.owner, required this.durationS});

  final String bvid;
  final int cid;
  final String title;
  final String owner;
  final int durationS;
}
