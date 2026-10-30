import 'package:bili_core/api.dart' show QualityOption, SeasonSection, VideoDetail, VideoOwner, VideoPage;
import 'package:bili_core/logic.dart' show QualityRules;
import 'package:flutter/foundation.dart';

import '../../video/player_session.dart';
import '../offline_models.dart';

/// One row of 缓存: the part it would cache, and how the row draws it.
@immutable
final class DownloadEntry {
  const DownloadEntry({required this.request, required this.title, required this.current, this.cover});

  final OfflineRequest request;
  final String title;

  /// The part playing: pink, with the playing bars.
  final bool current;

  /// Only a 合集's videos draw a cover (144, KaiC); a video and its parts are title rows (141).
  final String? cover;

  int get cid => request.cid;

  @override
  bool operator ==(Object other) =>
      other is DownloadEntry &&
      other.request == request &&
      other.title == title &&
      other.current == current &&
      other.cover == cover;

  @override
  int get hashCode => Object.hash(request, title, current, cover);
}

/// What 缓存 lists for the video [session] plays: the parts of a video in parts, else the 合集 section holding it
/// (as 选集 chooses), else the one video. Empty until the video is known.
List<DownloadEntry> downloadEntries(PlayerSession session) {
  final video = session.video;
  final detail = session.detail;
  if (video == null) return const [];
  final owner = detail?.owner ?? VideoOwner(mid: 0, name: video.owner ?? '', face: '');
  final season = detail?.season;
  final collection = season == null ? null : OfflineCollection(id: season.id, title: season.title);
  final pages = video.pages.isNotEmpty ? video.pages : detail?.pages ?? const <VideoPage>[];
  final playing = session.part?.cid;

  OfflineRequest part(VideoPage page, {required bool inParts}) => OfflineRequest(
    bvid: video.bvid,
    aid: video.aid != 0 ? video.aid : detail?.aid ?? 0,
    cid: page.cid,
    title: video.title.isNotEmpty ? video.title : detail?.title ?? '',
    duration: page.duration,
    cover: detail?.cover ?? '',
    ownerMid: owner.mid,
    ownerName: owner.name,
    ownerFace: owner.face,
    page: page.page,
    partTitle: inParts ? page.part : null,
    collection: collection,
  );

  if (session.episodesAreParts && pages.length > 1) {
    return [
      for (final page in pages)
        DownloadEntry(
          request: part(page, inParts: true),
          title: 'P${page.page} ${page.part}',
          current: page.cid == playing,
        ),
    ];
  }
  final section = _section(detail, video.bvid);
  if (collection != null && section != null && section.episodes.isNotEmpty) {
    return [
      for (final episode in section.episodes)
        DownloadEntry(
          request: OfflineRequest(
            bvid: episode.bvid,
            aid: episode.aid,
            cid: episode.cid,
            title: episode.title,
            duration: episode.duration,
            cover: episode.cover,
            ownerMid: owner.mid,
            ownerName: owner.name,
            ownerFace: owner.face,
            collection: collection,
          ),
          title: episode.title,
          current: episode.bvid == video.bvid,
          cover: episode.cover,
        ),
    ];
  }
  final page =
      session.part ?? pages.firstOrNull ?? VideoPage(cid: 0, page: 1, part: '', duration: detail?.duration ?? 0);
  if (page.cid == 0) return const [];
  return [DownloadEntry(request: part(page, inParts: false), title: session.title, current: true)];
}

/// The 合集 section holding [bvid], else the first, as 选集 picks it.
SeasonSection? _section(VideoDetail? detail, String bvid) {
  final sections = detail?.season?.sections ?? const <SeasonSection>[];
  return sections.where((section) => section.episodes.any((episode) => episode.bvid == bvid)).firstOrNull ??
      sections.firstOrNull;
}

/// 画质's choices best first, and the one 缓存 opens on: the best the account can have (KaiC: the highest offered;
/// a 大会员 quality only with 大会员, since the library would fall back below it anyway).
({List<QualityOption> options, int? best}) downloadQualities(PlayerSession session) {
  final options = [...session.qualities]..sort((a, b) => b.id.compareTo(a.id));
  final best =
      options.where((option) => session.isVip || !QualityRules.needsVip(option.id)).firstOrNull ?? options.firstOrNull;
  return (options: options, best: best?.id);
}
