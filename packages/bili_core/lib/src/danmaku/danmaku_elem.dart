import 'dart:convert';
import 'dart:typed_data';

import 'protobuf_reader.dart';

final class DanmakuElem {
  const DanmakuElem({
    this.id = 0,
    this.progressMs = 0,
    this.mode = 1,
    this.fontSize = 25,
    this.color = 0xFFFFFF,
    this.midHash = '',
    this.content = '',
    this.ctime = 0,
    this.weight = 0,
    this.pool = 0,
    this.idStr = '',
    this.attr = 0,
    this.colorful = 0,
  });

  final int id;
  final int progressMs;
  final int mode;
  final int fontSize;

  /// 24-bit RGB, held in 32 bits.
  final int color;
  final String midHash;
  final String content;
  final int ctime;
  final int weight;
  final int pool;
  final String idStr;
  final int attr;
  final int colorful;

  static DanmakuElem decode(Uint8List bytes) {
    var id = 0, progressMs = 0, mode = 0, fontSize = 0, color = 0, ctime = 0;
    var weight = 0, pool = 0, attr = 0, colorful = 0;
    var midHash = '', content = '', idStr = '';
    final reader = ProtobufReader(bytes);
    for (var tag = reader.next(); tag != null; tag = reader.next()) {
      // A known field arriving in another wire type is skipped rather than misread.
      switch ((tag.field, tag.wireType)) {
        case (1, 0):
          id = reader.varint();
        case (2, 0):
          progressMs = reader.varint();
        case (3, 0):
          mode = reader.varint();
        case (4, 0):
          fontSize = reader.varint();
        case (5, 0):
          color = reader.varint() & 0xFFFFFFFF;
        case (6, 2):
          midHash = _string(reader.lengthDelimited());
        case (7, 2):
          content = _string(reader.lengthDelimited());
        case (8, 0):
          ctime = reader.varint();
        case (9, 0):
          weight = reader.varint();
        case (11, 0):
          pool = reader.varint();
        case (12, 2):
          idStr = _string(reader.lengthDelimited());
        case (13, 0):
          attr = reader.varint();
        case (24, 0):
          colorful = reader.varint();
        default:
          reader.skip(tag.wireType);
      }
    }
    return DanmakuElem(
      id: id,
      progressMs: progressMs,
      mode: mode,
      fontSize: fontSize,
      color: color,
      midHash: midHash,
      content: content,
      ctime: ctime,
      weight: weight,
      pool: pool,
      idStr: idStr,
      attr: attr,
      colorful: colorful,
    );
  }

  static String _string(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);

  DanmakuElem copyWith({
    int? id,
    int? progressMs,
    int? mode,
    int? fontSize,
    int? color,
    String? midHash,
    String? content,
    int? ctime,
    int? weight,
    int? pool,
    String? idStr,
    int? attr,
    int? colorful,
  }) => DanmakuElem(
    id: id ?? this.id,
    progressMs: progressMs ?? this.progressMs,
    mode: mode ?? this.mode,
    fontSize: fontSize ?? this.fontSize,
    color: color ?? this.color,
    midHash: midHash ?? this.midHash,
    content: content ?? this.content,
    ctime: ctime ?? this.ctime,
    weight: weight ?? this.weight,
    pool: pool ?? this.pool,
    idStr: idStr ?? this.idStr,
    attr: attr ?? this.attr,
    colorful: colorful ?? this.colorful,
  );

  @override
  bool operator ==(Object other) =>
      other is DanmakuElem &&
      other.id == id &&
      other.progressMs == progressMs &&
      other.mode == mode &&
      other.fontSize == fontSize &&
      other.color == color &&
      other.midHash == midHash &&
      other.content == content &&
      other.ctime == ctime &&
      other.weight == weight &&
      other.pool == pool &&
      other.idStr == idStr &&
      other.attr == attr &&
      other.colorful == colorful;

  @override
  int get hashCode =>
      Object.hash(id, progressMs, mode, fontSize, color, midHash, content, ctime, weight, pool, idStr, attr, colorful);

  @override
  String toString() => 'DanmakuElem($progressMs ms, mode $mode, "$content")';
}
