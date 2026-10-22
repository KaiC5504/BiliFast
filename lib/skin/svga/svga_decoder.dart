import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart' show ZipDecoder;

import 'proto_reader.dart';
import 'svga_movie.dart';

/// Reads both SVGA formats (github.com/svga/SVGA-Format): 2.x, a zlib-deflated protobuf `MovieEntity`, and 1.x, a
/// zip holding `movie.spec` (JSON) with its PNGs beside it; a zip holding 2.x's `movie.binary` is read too.
///
/// What a frame leaves out reads as the format's defaults (proto3's for 2.x; 1.x writes a hidden frame as `{}`): no
/// alpha is 0, so an empty frame hides its sprite; no transform is the identity; no layout draws no picture; no clip
/// path clips nothing. Shapes that start with a KEEP shape are the previous frame's. A sprite with fewer frames than
/// the movie is hidden after its last.
abstract final class SvgaDecoder {
  /// Throws a [FormatException] for anything it can't read.
  static SvgaMovie decode(Uint8List bytes) {
    if (_isZip(bytes)) return _decodeZip(bytes);
    return _decodeProto(_inflate(bytes), const {});
  }

  static bool _isZip(Uint8List bytes) =>
      bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04;

  static Uint8List _inflate(Uint8List bytes) {
    try {
      final inflated = ZLibDecoder().convert(bytes);
      return inflated is Uint8List ? inflated : Uint8List.fromList(inflated);
    } catch (error) {
      throw FormatException('svga is neither a zip nor zlib data: $error');
    }
  }

  static SvgaMovie _decodeZip(Uint8List bytes) {
    final files = <String, Uint8List>{};
    try {
      for (final file in ZipDecoder().decodeBytes(bytes)) {
        if (!file.isFile || file.name.startsWith('__MACOSX/')) continue;
        final name = file.name.split(RegExp(r'[/\\]')).last;
        if (name.isEmpty || name.startsWith('.')) continue;
        files[name] = file.content;
      }
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('svga zip is unreadable: $error');
    }
    final binary = files['movie.binary'];
    if (binary != null) return _decodeProto(binary, files);
    final spec = files['movie.spec'];
    if (spec == null) throw const FormatException('svga zip has neither movie.spec nor movie.binary');
    return _decodeJson(spec, files);
  }

  static SvgaMovie _decodeProto(Uint8List bytes, Map<String, Uint8List> files) {
    final reader = ProtoReader(bytes);
    var version = '';
    double width = 0;
    double height = 0;
    var fps = 0;
    var frames = 0;
    final images = <String, Uint8List>{};
    final sprites = <SvgaSprite>[];
    while (!reader.done) {
      final tag = reader.readTag();
      switch (tag >> 3) {
        case 1:
          version = reader.stringField(tag);
        case 2:
          final params = reader.messageField(tag);
          if (params == null) break;
          while (!params.done) {
            final field = params.readTag();
            switch (field >> 3) {
              case 1:
                width = params.floatField(field);
              case 2:
                height = params.floatField(field);
              case 3:
                fps = params.intField(field);
              case 4:
                frames = params.intField(field);
              default:
                params.skip(field);
            }
          }
        case 3:
          final entry = reader.messageField(tag);
          if (entry == null) break;
          var key = '';
          Uint8List? value;
          while (!entry.done) {
            final field = entry.readTag();
            switch (field >> 3) {
              case 1:
                key = entry.stringField(field);
              case 2 when field & 7 == ProtoReader.lengthDelimited:
                value = entry.readBytes();
              default:
                entry.skip(field);
            }
          }
          if (value == null) break;
          if (_isPicture(value)) {
            images[key] = value;
          } else if (files.isNotEmpty) {
            // Inside a zip a value may name a file of the zip rather than hold the picture.
            final name = utf8.decode(value, allowMalformed: true);
            final picture = _file(files, [name, '$name.png', key, '$key.png']);
            if (picture != null) images[key] = picture;
          }
        case 4:
          final sprite = reader.messageField(tag);
          if (sprite != null) sprites.add(_protoSprite(sprite));
        default:
          reader.skip(tag);
      }
    }
    return _movie(version, width, height, fps, frames, images, sprites);
  }

  static SvgaSprite _protoSprite(ProtoReader reader) {
    var imageKey = '';
    String? matteKey;
    final frames = <SvgaFrame>[];
    while (!reader.done) {
      final tag = reader.readTag();
      switch (tag >> 3) {
        case 1:
          imageKey = reader.stringField(tag);
        case 2:
          final frame = reader.messageField(tag);
          if (frame != null) frames.add(_protoFrame(frame));
        case 3:
          final key = reader.stringField(tag);
          if (key.isNotEmpty) matteKey = key;
        default:
          reader.skip(tag);
      }
    }
    return SvgaSprite(imageKey: imageKey, matteKey: matteKey, frames: _keepShapes(frames));
  }

  static SvgaFrame _protoFrame(ProtoReader reader) {
    double alpha = 0;
    SvgaRect? layout;
    SvgaTransform? transform;
    String? clipPath;
    final shapes = <SvgaShape>[];
    while (!reader.done) {
      final tag = reader.readTag();
      switch (tag >> 3) {
        case 1:
          alpha = reader.floatField(tag);
        case 2:
          final message = reader.messageField(tag);
          if (message != null) layout = _protoRect(message);
        case 3:
          final message = reader.messageField(tag);
          if (message != null) transform = _protoTransform(message);
        case 4:
          final path = reader.stringField(tag);
          if (path.trim().isNotEmpty) clipPath = path;
        case 5:
          final shape = reader.messageField(tag);
          if (shape != null) shapes.add(_protoShape(shape));
        default:
          reader.skip(tag);
      }
    }
    return SvgaFrame(alpha: alpha, layout: layout, transform: transform, clipPath: clipPath, shapes: shapes);
  }

  /// Float fields 1 to [count], each 0 when left out.
  static List<double> _floats(ProtoReader reader, int count) {
    final values = List<double>.filled(count, 0);
    while (!reader.done) {
      final tag = reader.readTag();
      final number = tag >> 3;
      if (number >= 1 && number <= count) {
        values[number - 1] = reader.floatField(tag);
      } else {
        reader.skip(tag);
      }
    }
    return values;
  }

  static SvgaRect _protoRect(ProtoReader reader) {
    final values = _floats(reader, 4);
    return SvgaRect(values[0], values[1], values[2], values[3]);
  }

  static SvgaTransform _protoTransform(ProtoReader reader) {
    final values = _floats(reader, 6);
    return SvgaTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5]);
  }

  static SvgaShape _protoShape(ProtoReader reader) {
    var type = SvgaShapeType.path;
    String? d;
    List<double>? rect;
    List<double>? ellipse;
    SvgaShapeStyle? style;
    SvgaTransform? transform;
    while (!reader.done) {
      final tag = reader.readTag();
      switch (tag >> 3) {
        case 1:
          final value = reader.intField(tag);
          type = value >= 0 && value < SvgaShapeType.values.length ? SvgaShapeType.values[value] : SvgaShapeType.path;
        case 2:
          final args = reader.messageField(tag);
          if (args == null) break;
          while (!args.done) {
            final field = args.readTag();
            if (field >> 3 == 1) {
              d = args.stringField(field);
            } else {
              args.skip(field);
            }
          }
        case 3:
          final args = reader.messageField(tag);
          if (args != null) rect = _floats(args, 5);
        case 4:
          final args = reader.messageField(tag);
          if (args != null) ellipse = _floats(args, 4);
        case 10:
          final styles = reader.messageField(tag);
          if (styles != null) style = _protoStyle(styles);
        case 11:
          final message = reader.messageField(tag);
          if (message != null) transform = _protoTransform(message);
        default:
          reader.skip(tag);
      }
    }
    return SvgaShape(
      type: type,
      d: d,
      rect: rect == null ? null : SvgaRect(rect[0], rect[1], rect[2], rect[3]),
      cornerRadius: rect?[4] ?? 0,
      ellipseCenterX: ellipse?[0] ?? 0,
      ellipseCenterY: ellipse?[1] ?? 0,
      radiusX: ellipse?[2] ?? 0,
      radiusY: ellipse?[3] ?? 0,
      style: style,
      transform: transform,
    );
  }

  static SvgaShapeStyle _protoStyle(ProtoReader reader) {
    SvgaColor? fill;
    SvgaColor? stroke;
    double strokeWidth = 0;
    var lineCap = SvgaLineCap.butt;
    var lineJoin = SvgaLineJoin.miter;
    double miterLimit = 0;
    final dash = [0.0, 0.0, 0.0];
    while (!reader.done) {
      final tag = reader.readTag();
      switch (tag >> 3) {
        case 1:
          final color = reader.messageField(tag);
          if (color != null) fill = _protoColor(color);
        case 2:
          final color = reader.messageField(tag);
          if (color != null) stroke = _protoColor(color);
        case 3:
          strokeWidth = reader.floatField(tag);
        case 4:
          lineCap = _pick(SvgaLineCap.values, reader.intField(tag), SvgaLineCap.butt);
        case 5:
          lineJoin = _pick(SvgaLineJoin.values, reader.intField(tag), SvgaLineJoin.miter);
        case 6:
          miterLimit = reader.floatField(tag);
        case 7 || 8 || 9:
          dash[(tag >> 3) - 7] = reader.floatField(tag);
        default:
          reader.skip(tag);
      }
    }
    return SvgaShapeStyle(
      fill: fill,
      stroke: stroke,
      strokeWidth: strokeWidth,
      lineCap: lineCap,
      lineJoin: lineJoin,
      miterLimit: miterLimit,
      dash: dash[0],
      gap: dash[1],
      dashOffset: dash[2],
    );
  }

  static SvgaColor _protoColor(ProtoReader reader) => _color(_floats(reader, 4));

  static SvgaMovie _decodeJson(Uint8List bytes, Map<String, Uint8List> files) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } on FormatException catch (error) {
      throw FormatException('movie.spec is not JSON: ${error.message}');
    }
    if (json is! Map<String, Object?>) throw const FormatException('movie.spec is not an object');
    final movie = _map(json['movie']);
    final viewBox = _map(movie['viewBox']);
    final images = <String, Uint8List>{};
    for (final MapEntry(:key, :value) in _map(json['images']).entries) {
      final name = value is String ? value : key;
      final picture = _file(files, [name, '$name.png', '$key.png', key]);
      if (picture != null) images[key] = picture;
    }
    final sprites = [
      for (final sprite in _list(json['sprites']))
        if (sprite is Map<String, Object?>)
          SvgaSprite(
            imageKey: _string(sprite['imageKey']) ?? '',
            matteKey: _string(sprite['matteKey']),
            frames: _keepShapes([
              for (final frame in _list(sprite['frames'])) _jsonFrame(frame is Map<String, Object?> ? frame : const {}),
            ]),
          ),
    ];
    return _movie(
      _string(json['ver']) ?? '',
      _number(viewBox['width']),
      _number(viewBox['height']),
      _number(movie['fps']).round(),
      _number(movie['frames']).round(),
      images,
      sprites,
    );
  }

  static SvgaFrame _jsonFrame(Map<String, Object?> json) {
    final layout = json['layout'];
    final clipPath = _string(json['clipPath']);
    return SvgaFrame(
      alpha: _number(json['alpha']),
      layout: layout is Map<String, Object?> ? _jsonRect(layout, 'width', 'height') : null,
      transform: _jsonTransform(json['transform']),
      clipPath: clipPath == null || clipPath.trim().isEmpty ? null : clipPath,
      shapes: [
        for (final shape in _list(json['shapes']))
          if (shape is Map<String, Object?>) _jsonShape(shape),
      ],
    );
  }

  static SvgaRect _jsonRect(Map<String, Object?> json, String width, String height) =>
      SvgaRect(_number(json['x']), _number(json['y']), _number(json[width]), _number(json[height]));

  static SvgaTransform? _jsonTransform(Object? json) {
    if (json is! Map<String, Object?>) return null;
    return SvgaTransform(
      a: _number(json['a'], 1),
      b: _number(json['b']),
      c: _number(json['c']),
      d: _number(json['d'], 1),
      tx: _number(json['tx']),
      ty: _number(json['ty']),
    );
  }

  static SvgaShape _jsonShape(Map<String, Object?> json) {
    final type = switch (_string(json['type'])?.toLowerCase()) {
      'rect' => SvgaShapeType.rect,
      'ellipse' => SvgaShapeType.ellipse,
      'keep' => SvgaShapeType.keep,
      _ => SvgaShapeType.path,
    };
    final args = _map(json['args']);
    final styles = json['styles'];
    return SvgaShape(
      type: type,
      d: _string(args['d']),
      rect: type == SvgaShapeType.rect ? _jsonRect(args, 'width', 'height') : null,
      cornerRadius: _number(args['cornerRadius']),
      ellipseCenterX: _number(args['x']),
      ellipseCenterY: _number(args['y']),
      radiusX: _number(args['radiusX']),
      radiusY: _number(args['radiusY']),
      style: styles is Map<String, Object?> ? _jsonStyle(styles) : null,
      transform: _jsonTransform(json['transform']),
    );
  }

  static SvgaShapeStyle _jsonStyle(Map<String, Object?> json) {
    final dash = _list(json['lineDash']);
    double dashAt(int index) => index < dash.length ? _number(dash[index]) : 0;
    return SvgaShapeStyle(
      fill: _jsonColor(json['fill']),
      stroke: _jsonColor(json['stroke']),
      strokeWidth: _number(json['strokeWidth']),
      lineCap: SvgaLineCap.values.asNameMap()[_string(json['lineCap'])?.toLowerCase()] ?? SvgaLineCap.butt,
      lineJoin: SvgaLineJoin.values.asNameMap()[_string(json['lineJoin'])?.toLowerCase()] ?? SvgaLineJoin.miter,
      miterLimit: _number(json['miterLimit']),
      dash: dashAt(0),
      gap: dashAt(1),
      dashOffset: dashAt(2),
    );
  }

  static SvgaColor? _jsonColor(Object? json) {
    final values = _list(json);
    if (values.length < 4) return null;
    return _color([for (final value in values.take(4)) _number(value)]);
  }

  static SvgaMovie _movie(
    String version,
    double width,
    double height,
    int fps,
    int frames,
    Map<String, Uint8List> images,
    List<SvgaSprite> sprites,
  ) {
    if (!(width > 0) || !(height > 0)) throw FormatException('svga view box is $width × $height');
    final longest = sprites.fold(0, (longest, sprite) => math.max(longest, sprite.frames.length));
    return SvgaMovie(
      version: version,
      width: width,
      height: height,
      fps: fps,
      frames: frames > 0 ? frames : longest,
      images: images,
      sprites: sprites,
    );
  }

  static List<SvgaFrame> _keepShapes(List<SvgaFrame> frames) {
    final resolved = <SvgaFrame>[];
    var previous = const <SvgaShape>[];
    for (final frame in frames) {
      final keeps = frame.shapes.isNotEmpty && frame.shapes.first.type == SvgaShapeType.keep;
      final current = keeps
          ? SvgaFrame(
              alpha: frame.alpha,
              layout: frame.layout,
              transform: frame.transform,
              clipPath: frame.clipPath,
              shapes: previous,
            )
          : frame;
      resolved.add(current);
      previous = current.shapes;
    }
    return resolved;
  }

  /// Some exporters write channels from 0 to 255 instead of 0 to 1.
  static SvgaColor _color(List<double> values) {
    final scale = values.any((value) => value > 1) ? 255.0 : 1.0;
    double channel(double value) => (value / scale).clamp(0, 1).toDouble();
    return SvgaColor(channel(values[0]), channel(values[1]), channel(values[2]), channel(values[3]));
  }

  static Uint8List? _file(Map<String, Uint8List> files, List<String> names) {
    for (final name in names) {
      final file = files[name];
      if (file != null && _isPicture(file)) return file;
    }
    return null;
  }

  static bool _isPicture(Uint8List bytes) {
    bool starts(List<int> magic, [int at = 0]) {
      if (bytes.length < at + magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (bytes[at + i] != magic[i]) return false;
      }
      return true;
    }

    return starts(const [0x89, 0x50, 0x4E, 0x47]) ||
        starts(const [0xFF, 0xD8, 0xFF]) ||
        starts(const [0x47, 0x49, 0x46, 0x38]) ||
        (starts(const [0x52, 0x49, 0x46, 0x46]) && starts(const [0x57, 0x45, 0x42, 0x50], 8));
  }

  static T _pick<T>(List<T> values, int index, T fallback) =>
      index >= 0 && index < values.length ? values[index] : fallback;

  static Map<String, Object?> _map(Object? json) => json is Map<String, Object?> ? json : const {};

  static List<Object?> _list(Object? json) => json is List<Object?> ? json : const [];

  static String? _string(Object? json) => json is String ? json : null;

  static double _number(Object? json, [double fallback = 0]) => switch (json) {
    final num value when value.isFinite => value.toDouble(),
    final String text => double.tryParse(text) ?? fallback,
    _ => fallback,
  };
}
