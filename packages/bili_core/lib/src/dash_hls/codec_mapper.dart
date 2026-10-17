final class HLSVideoCodec {
  const HLSVideoCodec({required this.codecs, required this.supplemental, required this.videoRange});

  final String codecs;
  final String? supplemental;
  final String videoRange;

  @override
  bool operator ==(Object other) =>
      other is HLSVideoCodec &&
      other.codecs == codecs &&
      other.supplemental == supplemental &&
      other.videoRange == videoRange;

  @override
  int get hashCode => Object.hash(codecs, supplemental, videoRange);

  @override
  String toString() => 'HLSVideoCodec($codecs, $supplemental, $videoRange)';
}

abstract final class CodecMapper {
  static HLSVideoCodec video({required String codecs, required int qualityId, String? sampleEntry}) =>
      throw UnimplementedError('port of CodecMapper.swift');

  static String frameRate(String? text) => throw UnimplementedError('port of CodecMapper.swift');
}
