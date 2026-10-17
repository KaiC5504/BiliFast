import 'dart:convert';

import 'package:flutter/painting.dart';

import '../bili_player.dart';

/// The spike's EDL: mpv opens both DASH files as one source, so they start loading at once.
String edlUrl(Uri video, Uri audio) {
  String part(Uri uri) {
    final text = uri.toString();
    return '%${utf8.encode(text).length}%$text';
  }

  return 'edl://!no_chapters;${part(video)};!new_stream;!no_chapters;${part(audio)}';
}

/// User-Agent and Referer go to mpv's own options, as in the spike; anything else to http-header-fields.
({String? userAgent, String? referer, Map<String, String> others}) splitHeaders(Map<String, String> headers) {
  String? userAgent, referer;
  final others = <String, String>{};
  for (final MapEntry(:key, :value) in headers.entries) {
    switch (key.toLowerCase()) {
      case 'user-agent':
        userAgent = value;
      case 'referer':
        referer = value;
      default:
        others[key] = value;
    }
  }
  return (userAgent: userAgent, referer: referer, others: others);
}

/// mpv's string form of a time property; empty while nothing is loaded.
double? parseSeconds(String value) {
  final seconds = double.tryParse(value);
  return seconds == null || !seconds.isFinite ? null : seconds;
}

/// `seekable-ranges` from mpv's `demuxer-cache-state`, which mpv prints as JSON.
List<({double start, double end})> parseSeekableRanges(String cacheState) {
  if (cacheState.isEmpty) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(cacheState);
  } on FormatException {
    return const [];
  }
  if (decoded is! Map<String, Object?>) return const [];
  final ranges = decoded['seekable-ranges'];
  if (ranges is! List<Object?>) return const [];
  return [
    for (final range in ranges)
      if (range case {'start': final num start, 'end': final num end} when end > start)
        (start: start.toDouble(), end: end.toDouble()),
  ];
}

bool sameRanges(List<({double start, double end})> a, List<({double start, double end})> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if ((a[index].start - b[index].start).abs() > 0.05 || (a[index].end - b[index].end).abs() > 0.05) return false;
  }
  return true;
}

PlayerStatus deriveStatus({
  required bool loaded,
  required bool ready,
  required bool completed,
  required bool playing,
  required bool buffering,
}) {
  if (!loaded) return PlayerStatus.idle;
  if (completed) return PlayerStatus.ended;
  if (!ready) return PlayerStatus.loading;
  if (!playing) return PlayerStatus.paused;
  return buffering ? PlayerStatus.buffering : PlayerStatus.playing;
}

/// mpv names the URL it failed on; signed CDN URLs must not reach logs, so queries are cut.
String withoutQueries(String text) =>
    text.replaceAllMapped(RegExp(r'''(https?://[^\s?#"']+)[?#][^\s"']*'''), (match) => match[1]!);

/// The stream played but its format or codec was refused, so another codec may play.
bool looksLikeFormatError(String text) {
  final lower = text.toLowerCase();
  return const ['decoder', 'codec', 'unsupported', 'recognize file format', 'no video or audio']
      .any(lower.contains);
}

/// The Video widget's fit and forced aspect ratio for each mode; the ratio modes letterbox a frame of that shape
/// and stretch the picture into it, as `PlayerHostView.swift` does.
({BoxFit fit, double? aspectRatio}) videoFit(FitMode mode) => switch (mode) {
      FitMode.fit => (fit: BoxFit.contain, aspectRatio: null),
      FitMode.fill => (fit: BoxFit.cover, aspectRatio: null),
      FitMode.stretch => (fit: BoxFit.fill, aspectRatio: null),
      FitMode.ratio16x9 => (fit: BoxFit.contain, aspectRatio: 16 / 9),
      FitMode.ratio4x3 => (fit: BoxFit.contain, aspectRatio: 4 / 3),
    };
