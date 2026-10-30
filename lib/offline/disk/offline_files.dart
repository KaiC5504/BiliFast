import 'dart:convert';
import 'dart:io';

import 'package:bili_core/engine.dart' show DownloadRanges, TrackKind;
import 'package:bili_core/shared.dart' show ByteRange;

/// Where 离线缓存 keeps things under its folder: `library.json`, and a folder per part named by its cid holding
/// `entry.json`, `v.m4s`, `a.m4s`, `cover.jpg`, `face.jpg` and `dm/<n>.so`.
final class OfflineFiles {
  OfflineFiles(this.root);

  static const entryName = 'entry.json';
  static const videoName = 'v.m4s';
  static const audioName = 'a.m4s';
  static const coverName = 'cover.jpg';
  static const faceName = 'face.jpg';
  static const danmakuName = 'dm';

  /// Appended, with `-<ms>`, to a deleted part's folder before it is removed, so a removal cut short is finished at
  /// launch.
  static const deletedSuffix = '.deleted';

  /// Written into a part's folder before it is deleted: a folder that still has it at launch is removed.
  static const deletingName = '.deleting';

  static final _separator = Platform.pathSeparator;

  /// Absolute, as found this launch.
  final String root;

  String get library => _join(root, 'library.json');

  /// The trips away and how each background method did (`BackgroundTrials`).
  String get trials => _join(root, 'trials.json');
  String part(int cid) => _join(root, '$cid');
  String entry(int cid) => _join(part(cid), entryName);
  String deleting(int cid) => _join(part(cid), deletingName);
  String video(int cid) => _join(part(cid), videoName);
  String audio(int cid) => _join(part(cid), audioName);
  String track(int cid, TrackKind kind) => kind == TrackKind.video ? video(cid) : audio(cid);
  String cover(int cid) => _join(part(cid), coverName);
  String face(int cid) => _join(part(cid), faceName);
  String danmakuFolder(int cid) => _join(part(cid), danmakuName);
  String danmaku(int cid, int index) => _join(danmakuFolder(cid), '$index.so');

  /// Every file a track's download leaves: the finished file, its part, its ranges and the background's ranges.
  List<String> trackFiles(int cid, TrackKind kind) {
    final path = track(cid, kind);
    return [
      path,
      DownloadRanges.partPath(path),
      DownloadRanges.rangesPath(path),
      DownloadRanges.backgroundRangesPath(path),
    ];
  }

  static String _join(String folder, String name) => '$folder$_separator$name';
}

/// [bytes] at [path] whole or not at all: written beside it, then renamed over it.
Future<void> writeAtomically(String path, List<int> bytes) async {
  final temporary = File('$path.tmp');
  await temporary.writeAsBytes(bytes, flush: true);
  await temporary.rename(path);
}

Future<void> writeJsonAtomically(String path, Object json) => writeAtomically(path, utf8.encode(jsonEncode(json)));

/// A `.ranges` or `.bg-ranges` file ([DownloadRanges]); null when it is missing or unreadable.
Future<({int total, List<ByteRange> done})?> readRanges(String path) async {
  try {
    final json = jsonDecode(await File(path).readAsString());
    if (json is! Map) return null;
    final total = json['total'];
    final done = json['done'];
    if (total is! int || done is! List) return null;
    return (
      total: total,
      done: [
        for (final pair in done)
          if (pair is List && pair.length == 2 && pair[0] is int && pair[1] is int)
            ?ByteRange.of(pair[0] as int, pair[1] as int),
      ],
    );
  } on Object {
    return null;
  }
}

/// [ranges] sorted, with overlapping and touching ones joined.
List<ByteRange> mergeRanges(Iterable<ByteRange> ranges) {
  final sorted = ranges.toList()..sort((a, b) => a.start.compareTo(b.start));
  final merged = <ByteRange>[];
  for (final range in sorted) {
    final last = merged.lastOrNull;
    if (last != null && range.start <= last.end + 1) {
      if (range.end > last.end) merged[merged.length - 1] = ByteRange(last.start, range.end);
    } else {
      merged.add(range);
    }
  }
  return merged;
}

/// The bytes of a track on the phone: the whole file once finished, else what its ranges files list.
Future<({int bytes, int total})> trackBytes(String path) async {
  final finished = File(path);
  if (await finished.exists()) {
    final length = await finished.length();
    return (bytes: length, total: length);
  }
  final own = await readRanges(DownloadRanges.rangesPath(path));
  final background = await readRanges(DownloadRanges.backgroundRangesPath(path));
  final held = mergeRanges([...?own?.done, ...?background?.done]);
  return (bytes: held.fold(0, (sum, range) => sum + range.length), total: own?.total ?? background?.total ?? 0);
}

/// What the files in [folder] take, media aside ([skip] names files at its top level left out); 0 when it is gone.
Future<int> folderBytes(String folder, {Set<String> skip = const {}}) async {
  final directory = Directory(folder);
  if (!await directory.exists()) return 0;
  var total = 0;
  await for (final entity in directory.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.lastOrNull ?? '';
    if (entity.parent.path == directory.path && skip.any(name.startsWith)) continue;
    try {
      total += await entity.length();
    } on FileSystemException {
      // Removed while listed.
    }
  }
  return total;
}
