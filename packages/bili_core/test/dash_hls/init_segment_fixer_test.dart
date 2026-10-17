import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_core/dash_hls.dart';
import 'package:test/test.dart';

import 'mp4_builder.dart';
import 'real_hev1_init_segment.dart';

void main() {
  test('rewrites hev1 with parameter sets', () {
    final original = bytesOf([
      ...MP4Builder.initSegment(entryType: 'hev1', nalTypes: [32, 33, 34]),
      ...MP4Builder.box('sidx', [1, 2, 3]),
    ]);
    final result = InitSegmentFixer.fixHEV1(original);
    expect(result, isA<InitRewritten>());
    final fixed = (result as InitRewritten).bytes;
    expect(fixed.length, original.length);
    final position = indexOf('hev1', original)!;
    expect(fixed.sublist(position, position + 4), ascii.encode('hvc1'));
    final restored = Uint8List.fromList(fixed)..setRange(position, position + 4, ascii.encode('hev1'));
    expect(restored, original);
  });

  test('refuses hev1 without PPS', () {
    final result = InitSegmentFixer.fixHEV1(bytesOf(MP4Builder.initSegment(entryType: 'hev1', nalTypes: [32, 33])));
    expect(result, isA<InitUnplayable>());
  });

  test('reads the sample entry as served', () {
    expect(InitSegmentFixer.sampleEntry(bytesOf(MP4Builder.initSegment(entryType: 'hvc1', nalTypes: [32, 33, 34]))),
        'hvc1');
    expect(
        InitSegmentFixer.sampleEntry(
            bytesOf([...MP4Builder.initSegment(entryType: 'avc1', nalTypes: []), ...MP4Builder.box('sidx', [1])])),
        'avc1');
    expect(InitSegmentFixer.sampleEntry(realHEV1InitSegment), 'hev1');
    expect(InitSegmentFixer.sampleEntry(bytesOf([0, 1, 2])), isNull);
  });

  test('leaves other entries alone', () {
    expect(InitSegmentFixer.fixHEV1(bytesOf(MP4Builder.initSegment(entryType: 'hvc1', nalTypes: [32, 33, 34]))),
        const InitUnchanged());
    expect(InitSegmentFixer.fixHEV1(bytesOf(MP4Builder.initSegment(entryType: 'avc1', nalTypes: []))),
        const InitUnchanged());
    expect(InitSegmentFixer.fixHEV1(bytesOf([0, 1, 2])), const InitUnchanged());
  });

  test('refuses hev1 without an hvcC box', () {
    expect(InitSegmentFixer.fixHEV1(initSegmentWithChildren([])), isA<InitUnplayable>());
  });

  test('refuses hev1 whose parameter set arrays are empty', () {
    // The array header names VPS, SPS and PPS but each holds zero NAL units.
    final payload = [...MP4Builder.zeros(22), 3, 32, 0, 0, 33, 0, 0, 34, 0, 0];
    expect(InitSegmentFixer.fixHEV1(initSegmentWithChildren(MP4Builder.box('hvcC', payload))), isA<InitUnplayable>());
  });

  test('refuses hev1 whose hvcC is truncated inside a NAL unit', () {
    // Box sizes are consistent, but the last NAL unit claims more bytes than the hvcC holds.
    final payload = [
      ...MP4Builder.zeros(22), 3,
      32, ...MP4Builder.be16(1), ...MP4Builder.be16(2), 0xAA, 0xBB,
      33, ...MP4Builder.be16(1), ...MP4Builder.be16(2), 0xAA, 0xBB,
      34, ...MP4Builder.be16(1), ...MP4Builder.be16(500), 0xAA, 0xBB,
    ];
    expect(InitSegmentFixer.fixHEV1(initSegmentWithChildren(MP4Builder.box('hvcC', payload))), isA<InitUnplayable>());
  });

  test('refuses hev1 whose hvcC ends before the arrays', () {
    for (final payloadSize in [0, 10, 22, 23, 24]) {
      final original = initSegmentWithChildren(MP4Builder.box('hvcC', MP4Builder.zeros(payloadSize)));
      expect(InitSegmentFixer.fixHEV1(original), isA<InitUnplayable>(), reason: 'a $payloadSize byte hvcC');
    }
  });

  test('refuses hev1 shorter than its fixed fields', () {
    final entry = MP4Builder.box('hev1', MP4Builder.zeros(40));
    expect(InitSegmentFixer.fixHEV1(initSegmentWithEntries([entry])), isA<InitUnplayable>());
  });

  test('rewrites every hev1 entry and only those', () {
    final hev1 = MP4Builder.box('hev1', [...MP4Builder.zeros(78), ...MP4Builder.hvcC([32, 33, 34])]);
    final avc1 = MP4Builder.box('avc1', MP4Builder.zeros(78));
    final original = initSegmentWithEntries([hev1, avc1, hev1]);
    final result = InitSegmentFixer.fixHEV1(original);
    expect(result, isA<InitRewritten>());
    final fixed = (result as InitRewritten).bytes;
    expect(fixed.length, original.length);
    expect(indexOf('hev1', fixed), isNull);
    expect(occurrences('hvc1', fixed), 2);
    expect(occurrences('avc1', fixed), 1);
  });

  test('an unplayable entry wins over a rewritable one', () {
    final good = MP4Builder.box('hev1', [...MP4Builder.zeros(78), ...MP4Builder.hvcC([32, 33, 34])]);
    final bad = MP4Builder.box('hev1', [...MP4Builder.zeros(78), ...MP4Builder.hvcC([33])]);
    expect(InitSegmentFixer.fixHEV1(initSegmentWithEntries([good, bad])), isA<InitUnplayable>());
  });

  test('box sizes past the buffer never throw', () {
    final valid = bytesOf(MP4Builder.initSegment(entryType: 'hev1', nalTypes: [32, 33, 34]));
    for (var length = 0; length < valid.length; length++) {
      InitSegmentFixer.fixHEV1(Uint8List.sublistView(valid, 0, length));
    }
    final sizeOffsets = [boxStart('moov', valid)!, boxStart('hev1', valid)!, boxStart('hvcC', valid)!];
    for (final offset in sizeOffsets) {
      final hostile = Uint8List.fromList(valid)..setRange(offset, offset + 4, [0xFF, 0xFF, 0xFF, 0xFF]);
      InitSegmentFixer.fixHEV1(hostile);
    }
    final largeSize = Uint8List.fromList(valid)..setRange(sizeOffsets[0], sizeOffsets[0] + 4, MP4Builder.be32(1));
    InitSegmentFixer.fixHEV1(largeSize);
  });

  test('an oversized hev1 entry is unplayable', () {
    final original = bytesOf(MP4Builder.initSegment(entryType: 'hev1', nalTypes: [32, 33, 34]));
    final position = boxStart('hev1', original)!;
    original.setRange(position, position + 4, MP4Builder.be32(0x7FFFFFFF));
    expect(InitSegmentFixer.fixHEV1(original), isA<InitUnplayable>());
  });

  test('an oversized non-HEVC entry is left alone', () {
    final original = bytesOf(MP4Builder.initSegment(entryType: 'avc1', nalTypes: []));
    final position = boxStart('avc1', original)!;
    original.setRange(position, position + 4, MP4Builder.be32(0x7FFFFFFF));
    expect(InitSegmentFixer.fixHEV1(original), const InitUnchanged());
  });

  test('a buffer cut before moov ends is unplayable at every length', () {
    final valid = bytesOf(MP4Builder.initSegment(entryType: 'hev1', nalTypes: [32, 33, 34]));
    for (var length = 8; length < valid.length; length++) {
      expect(InitSegmentFixer.fixHEV1(Uint8List.sublistView(valid, 0, length)), isA<InitUnplayable>(),
          reason: 'at $length bytes');
    }
    expect(InitSegmentFixer.fixHEV1(valid), isA<InitRewritten>());
  });

  test('buffers without ftyp or moov are left alone', () {
    expect(InitSegmentFixer.fixHEV1(Uint8List(0)), const InitUnchanged());
    expect(InitSegmentFixer.fixHEV1(bytesOf(MP4Builder.box('free', [1, 2, 3]))), const InitUnchanged());
  });

  test('ftyp without moov is unplayable', () {
    final ftyp = MP4Builder.box('ftyp', [...ascii.encode('iso6'), ...MP4Builder.be32(0)]);
    final result = InitSegmentFixer.fixHEV1(bytesOf(ftyp));
    expect(result, const InitUnplayable('incomplete moov'));
  });

  test('rewrites an ffmpeg hev1 init segment', () {
    final original = realHEV1InitSegment;
    expect(original.length, 3195);
    final result = InitSegmentFixer.fixHEV1(original);
    expect(result, isA<InitRewritten>());
    final fixed = (result as InitRewritten).bytes;
    expect(fixed.length, original.length);
    final changed = [for (var i = 0; i < original.length; i++) if (original[i] != fixed[i]) i];
    // hev1 -> hvc1 changes only the second and third letters.
    final position = indexOf('hev1', original)!;
    expect(changed, [position + 1, position + 2]);
    expect(fixed.sublist(position, position + 4), ascii.encode('hvc1'));
    expect(InitSegmentFixer.sampleEntry(original), 'hev1', reason: 'the input is left as it was');
  });
}

Uint8List initSegmentWithChildren(List<int> entryChildren) =>
    initSegmentWithEntries([MP4Builder.box('hev1', [...MP4Builder.zeros(78), ...entryChildren])]);

Uint8List initSegmentWithEntries(List<List<int>> entries) {
  final stsd = MP4Builder.box('stsd', [0, 0, 0, 0, ...MP4Builder.be32(entries.length), ...entries.expand((e) => e)]);
  final trak = MP4Builder.box('trak', MP4Builder.box('mdia', MP4Builder.box('minf', MP4Builder.box('stbl', stsd))));
  return bytesOf([
    ...MP4Builder.box('ftyp', [...ascii.encode('iso6'), ...MP4Builder.be32(0)]),
    ...MP4Builder.box('moov', trak),
  ]);
}

List<int> _positions(String text, List<int> bytes) {
  final needle = ascii.encode(text);
  final found = <int>[];
  for (var start = 0; start + needle.length <= bytes.length; start++) {
    var match = true;
    for (var i = 0; i < needle.length; i++) {
      if (bytes[start + i] != needle[i]) {
        match = false;
        break;
      }
    }
    if (match) found.add(start);
  }
  return found;
}

int? indexOf(String text, List<int> bytes) {
  final found = _positions(text, bytes);
  return found.isEmpty ? null : found.first;
}

int? boxStart(String type, List<int> bytes) {
  final index = indexOf(type, bytes);
  return index == null ? null : index - 4;
}

int occurrences(String text, List<int> bytes) => _positions(text, bytes).length;
