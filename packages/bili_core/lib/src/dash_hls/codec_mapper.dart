import 'c_format.dart';

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
  /// `sampleEntry` is the four-character code in the init segment AVPlayer reads: `hvc1` after BTR
  /// mode's rewrite, and Bilibili's own bytes in direct mode, which can be `hvc1` under a `hev1` label.
  static HLSVideoCodec video({required String codecs, required int qualityId, String? sampleEntry}) {
    // Dolby Vision profile 8 is declared as its HEVC base layer plus a supplemental codec, so
    // devices without Dolby Vision still play the base layer.
    if (codecs == 'dvh1.08.07' || codecs == 'dvh1.08.03') {
      return HLSVideoCodec(codecs: 'hvc1.2.4.L153.b0', supplemental: '$codecs/db4h', videoRange: 'HLG');
    }
    if (codecs == 'dvh1.08.06') {
      return HLSVideoCodec(codecs: 'hvc1.2.4.L150', supplemental: '$codecs/db1p', videoRange: 'PQ');
    }
    if (codecs.startsWith('dvh1.05')) {
      return HLSVideoCodec(codecs: codecs, supplemental: null, videoRange: 'PQ');
    }
    final mapped = sampleEntry == 'hvc1' && codecs.startsWith('hev1') ? 'hvc1${codecs.substring(4)}' : codecs;
    // 125 is 真彩 HDR (HDR10).
    return HLSVideoCodec(codecs: mapped, supplemental: null, videoRange: qualityId == 125 ? 'PQ' : 'SDR');
  }

  static String frameRate(String? text) {
    final value = text == null ? null : _swiftDouble(text);
    if (value == null || !value.isFinite || value <= 0) return '30.000';
    return formatFixed(value, 3);
  }

  static final _decimal = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$');

  /// Swift's `Double(String)` for decimal text: no surrounding whitespace, unlike double.tryParse. Its
  /// hex floats (`0x1Ep0`) are not read; Bilibili sends decimals.
  static double? _swiftDouble(String text) => _decimal.hasMatch(text) ? double.parse(text) : null;
}
