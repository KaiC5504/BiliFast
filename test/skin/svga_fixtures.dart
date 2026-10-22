import 'dart:convert';
import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

import 'package:archive/archive.dart' show Archive, ArchiveFile, ZipEncoder, getCrc32;

/// Protobuf's wire format, written by hand for SVGA 2 test files.
final class ProtoWriter {
  final _bytes = BytesBuilder();

  void varint(int field, int value) {
    _tag(field, 0);
    _varint(value);
  }

  void float(int field, double value) {
    _tag(field, 5);
    _bytes.add((ByteData(4)..setFloat32(0, value, Endian.little)).buffer.asUint8List());
  }

  void fixed64(int field, int value) {
    _tag(field, 1);
    _bytes.add((ByteData(8)..setUint64(0, value, Endian.little)).buffer.asUint8List());
  }

  void string(int field, String value) => bytes(field, utf8.encode(value));

  void bytes(int field, List<int> value) {
    _tag(field, 2);
    _varint(value.length);
    _bytes.add(value);
  }

  void message(int field, ProtoWriter message) => bytes(field, message.toBytes());

  Uint8List toBytes() => _bytes.toBytes();

  void _tag(int field, int wireType) => _varint(field << 3 | wireType);

  void _varint(int value) {
    var rest = value;
    while (true) {
      final byte = rest & 0x7F;
      rest = rest >>> 7;
      if (rest == 0) {
        _bytes.addByte(byte);
        return;
      }
      _bytes.addByte(byte | 0x80);
    }
  }
}

ProtoWriter floats(List<double> values) {
  final writer = ProtoWriter();
  for (final (index, value) in values.indexed) {
    // proto3 leaves zeros out.
    if (value != 0) writer.float(index + 1, value);
  }
  return writer;
}

ProtoWriter frame2({
  double? alpha,
  List<double>? layout,
  List<double>? transform,
  String? clipPath,
  List<ProtoWriter> shapes = const [],
}) {
  final writer = ProtoWriter();
  if (alpha != null) writer.float(1, alpha);
  if (layout != null) writer.message(2, floats(layout));
  if (transform != null) writer.message(3, floats(transform));
  if (clipPath != null) writer.string(4, clipPath);
  for (final shape in shapes) {
    writer.message(5, shape);
  }
  return writer;
}

/// A ShapeEntity; [type] 0 path, 1 rect, 2 ellipse, 3 keep.
ProtoWriter shape2({
  int type = 0,
  String? d,
  List<double>? rect,
  List<double>? ellipse,
  List<double>? fill,
  List<double>? stroke,
  double? strokeWidth,
  int? lineCap,
  List<double>? dash,
  List<double>? transform,
}) {
  final writer = ProtoWriter();
  if (type != 0) writer.varint(1, type);
  if (d != null) writer.message(2, ProtoWriter()..string(1, d));
  if (rect != null) writer.message(3, floats(rect));
  if (ellipse != null) writer.message(4, floats(ellipse));
  if (fill != null || stroke != null) {
    final style = ProtoWriter();
    if (fill != null) style.message(1, floats(fill));
    if (stroke != null) style.message(2, floats(stroke));
    if (strokeWidth != null) style.float(3, strokeWidth);
    if (lineCap != null) style.varint(4, lineCap);
    if (dash != null) {
      for (final (index, value) in dash.indexed) {
        style.float(7 + index, value);
      }
    }
    writer.message(10, style);
  }
  if (transform != null) writer.message(11, floats(transform));
  return writer;
}

ProtoWriter sprite2(String imageKey, List<ProtoWriter> frames, {String? matteKey}) {
  final writer = ProtoWriter()..string(1, imageKey);
  for (final frame in frames) {
    writer.message(2, frame);
  }
  if (matteKey != null) writer.string(3, matteKey);
  return writer;
}

/// An SVGA 2 file: a zlib-deflated MovieEntity.
Uint8List movie2({
  String version = '2.0.0',
  double width = 100,
  double height = 100,
  int fps = 10,
  int frames = 1,
  Map<String, List<int>> images = const {},
  List<ProtoWriter> sprites = const [],
  void Function(ProtoWriter movie)? extra,
}) {
  final movie = ProtoWriter()..string(1, version);
  final params = ProtoWriter()
    ..float(1, width)
    ..float(2, height)
    ..varint(3, fps)
    ..varint(4, frames);
  movie.message(2, params);
  for (final MapEntry(:key, :value) in images.entries) {
    movie.message(
      3,
      ProtoWriter()
        ..string(1, key)
        ..bytes(2, value),
    );
  }
  for (final sprite in sprites) {
    movie.message(4, sprite);
  }
  extra?.call(movie);
  return Uint8List.fromList(ZLibEncoder().convert(movie.toBytes()));
}

/// An SVGA 1 file: a zip of `movie.spec` (left out when null) and its files.
Uint8List movie1(Map<String, Object?>? spec, {Map<String, List<int>> files = const {}}) {
  final archive = Archive();
  if (spec != null) archive.addFile(ArchiveFile.bytes('movie.spec', utf8.encode(jsonEncode(spec))));
  for (final MapEntry(:key, :value) in files.entries) {
    archive.addFile(ArchiveFile.bytes(key, value));
  }
  return ZipEncoder().encodeBytes(archive, modified: DateTime(2026, 10, 22));
}

/// A PNG of one colour (0xAARRGGBB), [width] × [height].
Uint8List png(int width, int height, int argb) {
  final row = [
    0,
    for (var x = 0; x < width; x++) ...[argb >> 16 & 0xFF, argb >> 8 & 0xFF, argb & 0xFF, argb >>> 24 & 0xFF],
  ];
  final raw = [for (var y = 0; y < height; y++) ...row];
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  final out = BytesBuilder()..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final typed = [...ascii.encode(type), ...data];
    out
      ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
      ..add(typed)
      ..add((ByteData(4)..setUint32(0, getCrc32(typed))).buffer.asUint8List());
  }

  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', ZLibEncoder().convert(raw));
  chunk('IEND', const []);
  return out.toBytes();
}
