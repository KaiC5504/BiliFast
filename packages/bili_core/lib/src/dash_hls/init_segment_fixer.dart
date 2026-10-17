import 'dart:convert';
import 'dart:typed_data';

import 'box_reader.dart';

sealed class InitFixResult {
  const InitFixResult();
}

final class InitUnchanged extends InitFixResult {
  const InitUnchanged();

  @override
  bool operator ==(Object other) => other is InitUnchanged;

  @override
  int get hashCode => (InitUnchanged).hashCode;

  @override
  String toString() => 'InitUnchanged';
}

final class InitRewritten extends InitFixResult {
  const InitRewritten(this.bytes);

  final Uint8List bytes;

  @override
  bool operator ==(Object other) {
    if (other is! InitRewritten || other.bytes.length != bytes.length) return false;
    for (var i = 0; i < bytes.length; i++) {
      if (other.bytes[i] != bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(InitRewritten, bytes.length);

  @override
  String toString() => 'InitRewritten(${bytes.length} bytes)';
}

final class InitUnplayable extends InitFixResult {
  const InitUnplayable(this.reason);

  final String reason;

  @override
  bool operator ==(Object other) => other is InitUnplayable && other.reason == reason;

  @override
  int get hashCode => Object.hash(InitUnplayable, reason);

  @override
  String toString() => 'InitUnplayable($reason)';
}

/// AVPlayer only plays HEVC from HLS when the sample entry is `hvc1` (parameter sets out of band).
/// Bilibili often labels HEVC `hev1`. When the `hvcC` box already carries VPS, SPS and PPS, the
/// two labels describe the same bytes, so renaming the four-character code is enough.
abstract final class InitSegmentFixer {
  /// Never modifies [bytes]; a rewrite comes back as a copy.
  static InitFixResult fixHEV1(Uint8List bytes) {
    Uint8List? output;
    final topLevel = BoxReader.boxes(bytes, from: 0, to: bytes.length);
    final moovs = topLevel.where((box) => box.type == 'moov').toList();
    // Boxes cut off by the end of the buffer are dropped by BoxReader, so a missing moov after an
    // ftyp means the caller's buffer is short, and an unpatched hev1 could be hiding in the rest.
    if (moovs.isEmpty && _startsWithFtyp(bytes)) return const InitUnplayable('incomplete moov');
    for (final moov in moovs) {
      final (:entries, :hasBrokenHev1) = _sampleEntries(bytes, moov);
      if (hasBrokenHev1) return const InitUnplayable('hev1 sample entry is truncated or malformed');
      for (final entry in entries.where((entry) => entry.type == 'hev1')) {
        if (!_hasParameterSets(bytes, entry)) return const InitUnplayable('hev1 without VPS/SPS/PPS in hvcC');
        (output ??= Uint8List.fromList(bytes)).setRange(entry.start + 4, entry.start + 8, _hvc1);
      }
    }
    return output == null ? const InitUnchanged() : InitRewritten(output);
  }

  /// The type of the first sample entry in the first moov, or null when there is none.
  static String? sampleEntry(Uint8List bytes) {
    final moov = BoxReader.boxes(bytes, from: 0, to: bytes.length).where((box) => box.type == 'moov').firstOrNull;
    if (moov == null) return null;
    return _sampleEntries(bytes, moov).entries.firstOrNull?.type;
  }

  static final _hvc1 = ascii.encode('hvc1');

  static bool _startsWithFtyp(Uint8List bytes) => bytes.length >= 8 && BoxReader.type(bytes, 4) == 'ftyp';

  static Iterable<BoxHeader> _children(Uint8List bytes, BoxHeader box, String type) =>
      BoxReader.boxes(bytes, from: box.payloadStart, to: box.end).where((child) => child.type == type);

  static ({List<BoxHeader> entries, bool hasBrokenHev1}) _sampleEntries(Uint8List bytes, BoxHeader moov) {
    final entries = <BoxHeader>[];
    var hasBrokenHev1 = false;
    for (final trak in _children(bytes, moov, 'trak')) {
      for (final mdia in _children(bytes, trak, 'mdia')) {
        for (final minf in _children(bytes, mdia, 'minf')) {
          for (final stbl in _children(bytes, minf, 'stbl')) {
            for (final stsd in _children(bytes, stbl, 'stsd')) {
              // stsd is a full box: version/flags and entry_count come first.
              final entriesStart = stsd.payloadStart + 8;
              final found = BoxReader.boxes(bytes, from: entriesStart, to: stsd.end);
              entries.addAll(found);
              // BoxReader stops at an entry whose size runs past stsd; its type is still readable.
              final rest = found.lastOrNull?.end ?? entriesStart;
              if (rest + 8 <= stsd.end && BoxReader.type(bytes, rest + 4) == 'hev1') hasBrokenHev1 = true;
            }
          }
        }
      }
    }
    return (entries: entries, hasBrokenHev1: hasBrokenHev1);
  }

  static bool _hasParameterSets(Uint8List bytes, BoxHeader entry) {
    // A VisualSampleEntry has 78 bytes of fixed fields before its child boxes.
    final childStart = entry.payloadStart + 78;
    if (childStart > entry.end) return false;
    final hvcC =
        BoxReader.boxes(bytes, from: childStart, to: entry.end).where((child) => child.type == 'hvcC').firstOrNull;
    if (hvcC == null) return false;
    var cursor = hvcC.payloadStart + 22;
    if (cursor >= hvcC.end) return false;
    final arrayCount = bytes[cursor];
    cursor += 1;
    final found = <int>{};
    for (var array = 0; array < arrayCount; array++) {
      if (cursor + 3 > hvcC.end) return false;
      final nalType = bytes[cursor] & 0x3f;
      final nalCount = BoxReader.uint16(bytes, cursor + 1);
      cursor += 3;
      for (var nal = 0; nal < nalCount; nal++) {
        if (cursor + 2 > hvcC.end) return false;
        cursor += 2 + BoxReader.uint16(bytes, cursor);
        if (cursor > hvcC.end) return false;
      }
      if (nalCount > 0) found.add(nalType);
    }
    // 32 = VPS, 33 = SPS, 34 = PPS.
    return found.containsAll(const [32, 33, 34]);
  }
}
