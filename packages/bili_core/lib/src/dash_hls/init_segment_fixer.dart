import 'dart:typed_data';

sealed class InitFixResult {
  const InitFixResult();
}

final class InitUnchanged extends InitFixResult {
  const InitUnchanged();
}

final class InitRewritten extends InitFixResult {
  const InitRewritten(this.bytes);

  final Uint8List bytes;
}

final class InitUnplayable extends InitFixResult {
  const InitUnplayable(this.reason);

  final String reason;
}

abstract final class InitSegmentFixer {
  static InitFixResult fixHEV1(Uint8List bytes) => throw UnimplementedError('port of InitSegmentFixer.swift');

  static String? sampleEntry(Uint8List bytes) => throw UnimplementedError('port of InitSegmentFixer.swift');
}
