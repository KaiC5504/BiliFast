import 'dart:typed_data';

import '../shared/media_segment.dart';

abstract final class SidxParser {
  static List<MediaSegment>? parse(Uint8List bytes, {required int absoluteStart}) =>
      throw UnimplementedError('port of SidxParser.swift');
}
