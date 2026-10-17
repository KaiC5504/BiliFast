import 'dart:typed_data';

import 'danmaku_elem.dart';
import 'protobuf_reader.dart';

final class DanmakuSegment {
  const DanmakuSegment({required this.elems, required this.closed});

  final List<DanmakuElem> elems;

  /// The uploader turned danmaku off for this video.
  final bool closed;

  static DanmakuSegment decode(Uint8List bytes) {
    final elems = <DanmakuElem>[];
    var state = 0;
    final reader = ProtobufReader(bytes);
    for (var tag = reader.next(); tag != null; tag = reader.next()) {
      switch ((tag.field, tag.wireType)) {
        case (1, 2):
          elems.add(DanmakuElem.decode(reader.lengthDelimited()));
        case (2, 0):
          state = reader.varint();
        default:
          reader.skip(tag.wireType);
      }
    }
    return DanmakuSegment(elems: elems, closed: state == 1);
  }
}

abstract final class DanmakuSegments {
  static const int lengthMs = 360000;
  static const int _prefetchWindowMs = 30000;

  /// 1-based, as the seg.so endpoint counts.
  static int indexForMs(int ms) => (ms < 0 ? 0 : ms) ~/ lengthMs + 1;

  static List<int> needed({required int atMs, required Set<int> loaded, required int durationMs}) {
    final current = indexForMs(atMs);
    final wanted = <int>[];
    if (!loaded.contains(current)) wanted.add(current);
    final boundary = current * lengthMs;
    if (boundary - atMs <= _prefetchWindowMs && durationMs > boundary && !loaded.contains(current + 1)) {
      wanted.add(current + 1);
    }
    return wanted;
  }
}
