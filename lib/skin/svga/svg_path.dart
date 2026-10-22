import 'dart:ui';

/// One command of SVG path data, made absolute: M, L, C, Q or A with its numbers, or Z.
final class PathSegment {
  const PathSegment(this.command, [this.values = const []]);

  final String command;
  final List<double> values;

  @override
  bool operator ==(Object other) =>
      other is PathSegment &&
      other.command == command &&
      other.values.length == values.length &&
      Iterable<int>.generate(values.length).every((i) => other.values[i] == values[i]);

  @override
  int get hashCode => Object.hash(command, Object.hashAll(values));

  @override
  String toString() => values.isEmpty ? command : '$command ${values.map(_number).join(' ')}';

  static String _number(double value) => value == value.roundToDouble() ? value.round().toString() : '$value';
}

/// SVG path data (M, L, H, V, C, S, Q, T, A and Z, absolute and relative), as SVGA's clip paths and shapes write it.
abstract final class SvgPath {
  /// The data as absolute segments: H and V become L, S and T become C and Q with the control point reflected, and
  /// the pairs after a move are lines. As SVG asks, an error ends the path where it is; data that doesn't start with
  /// a move has no segments.
  static List<PathSegment> parse(String data) {
    final scanner = _Scanner(data);
    final segments = <PathSegment>[];
    double x = 0;
    double y = 0;
    double startX = 0;
    double startY = 0;
    // The last C/S's second control point and the last Q/T's control point, reflected by S and T.
    (double, double)? cubic;
    (double, double)? quad;
    String? command;
    parsing:
    while (true) {
      scanner.skipSeparators();
      if (scanner.atEnd) break;
      final letter = scanner.command();
      if (letter != null) {
        command = letter;
      } else if (command == null || command == 'Z' || command == 'z') {
        break;
      }
      final upper = command.toUpperCase();
      if (segments.isEmpty && upper != 'M') break;
      final relative = command != upper;
      final dx = relative ? x : 0.0;
      final dy = relative ? y : 0.0;
      (double, double)? nextCubic;
      (double, double)? nextQuad;
      switch (upper) {
        case 'Z':
          segments.add(const PathSegment('Z'));
          x = startX;
          y = startY;
        case 'M':
          final p = scanner.numbers(2);
          if (p == null) break parsing;
          x = p[0] + dx;
          y = p[1] + dy;
          startX = x;
          startY = y;
          segments.add(PathSegment('M', [x, y]));
          command = relative ? 'l' : 'L';
        case 'L':
          final p = scanner.numbers(2);
          if (p == null) break parsing;
          x = p[0] + dx;
          y = p[1] + dy;
          segments.add(PathSegment('L', [x, y]));
        case 'H':
          final p = scanner.numbers(1);
          if (p == null) break parsing;
          x = p[0] + dx;
          segments.add(PathSegment('L', [x, y]));
        case 'V':
          final p = scanner.numbers(1);
          if (p == null) break parsing;
          y = p[0] + dy;
          segments.add(PathSegment('L', [x, y]));
        case 'C':
          final p = scanner.numbers(6);
          if (p == null) break parsing;
          segments.add(PathSegment('C', [p[0] + dx, p[1] + dy, p[2] + dx, p[3] + dy, p[4] + dx, p[5] + dy]));
          nextCubic = (p[2] + dx, p[3] + dy);
          x = p[4] + dx;
          y = p[5] + dy;
        case 'S':
          final p = scanner.numbers(4);
          if (p == null) break parsing;
          final (cx, cy) = cubic == null ? (x, y) : (2 * x - cubic.$1, 2 * y - cubic.$2);
          segments.add(PathSegment('C', [cx, cy, p[0] + dx, p[1] + dy, p[2] + dx, p[3] + dy]));
          nextCubic = (p[0] + dx, p[1] + dy);
          x = p[2] + dx;
          y = p[3] + dy;
        case 'Q':
          final p = scanner.numbers(4);
          if (p == null) break parsing;
          segments.add(PathSegment('Q', [p[0] + dx, p[1] + dy, p[2] + dx, p[3] + dy]));
          nextQuad = (p[0] + dx, p[1] + dy);
          x = p[2] + dx;
          y = p[3] + dy;
        case 'T':
          final p = scanner.numbers(2);
          if (p == null) break parsing;
          final (cx, cy) = quad == null ? (x, y) : (2 * x - quad.$1, 2 * y - quad.$2);
          segments.add(PathSegment('Q', [cx, cy, p[0] + dx, p[1] + dy]));
          nextQuad = (cx, cy);
          x = p[0] + dx;
          y = p[1] + dy;
        case 'A':
          final radii = scanner.numbers(3);
          final large = radii == null ? null : scanner.flag();
          final sweep = large == null ? null : scanner.flag();
          final end = sweep == null ? null : scanner.numbers(2);
          if (radii == null || large == null || sweep == null || end == null) break parsing;
          x = end[0] + dx;
          y = end[1] + dy;
          segments.add(PathSegment('A', [radii[0].abs(), radii[1].abs(), radii[2], large, sweep, x, y]));
        default:
          break parsing;
      }
      cubic = nextCubic;
      quad = nextQuad;
    }
    return segments;
  }

  static Path toPath(List<PathSegment> segments) {
    final path = Path();
    for (final PathSegment(:command, values: v) in segments) {
      switch (command) {
        case 'M':
          path.moveTo(v[0], v[1]);
        case 'L':
          path.lineTo(v[0], v[1]);
        case 'C':
          path.cubicTo(v[0], v[1], v[2], v[3], v[4], v[5]);
        case 'Q':
          path.quadraticBezierTo(v[0], v[1], v[2], v[3]);
        case 'A':
          // SVG's sweep flag 1 turns towards positive angles, which is clockwise with y pointing down.
          path.arcToPoint(
            Offset(v[5], v[6]),
            radius: Radius.elliptical(v[0], v[1]),
            rotation: v[2],
            largeArc: v[3] != 0,
            clockwise: v[4] != 0,
          );
        case 'Z':
          path.close();
      }
    }
    return path;
  }

  static Path parsePath(String data) => toPath(parse(data));
}

final class _Scanner {
  _Scanner(this.text);

  final String text;
  int _pos = 0;

  static final _number = RegExp(r'[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?');
  static final _commands = RegExp('[MmLlHhVvCcSsQqTtAaZz]');

  bool get atEnd => _pos >= text.length;

  void skipSeparators() {
    while (!atEnd) {
      final unit = text.codeUnitAt(_pos);
      // Space, tab, line feed, carriage return, form feed and comma.
      if (unit != 0x20 && unit != 0x09 && unit != 0x0A && unit != 0x0D && unit != 0x0C && unit != 0x2C) return;
      _pos++;
    }
  }

  String? command() {
    if (atEnd || _commands.matchAsPrefix(text, _pos) == null) return null;
    return text[_pos++];
  }

  double? number() {
    skipSeparators();
    final match = _number.matchAsPrefix(text, _pos);
    if (match == null) return null;
    final value = double.tryParse(match[0]!);
    if (value == null || !value.isFinite) return null;
    _pos = match.end;
    return value;
  }

  List<double>? numbers(int count) {
    final values = <double>[];
    for (var i = 0; i < count; i++) {
      final value = number();
      if (value == null) return null;
      values.add(value);
    }
    return values;
  }

  /// An arc flag: one digit, which needs no separator after it ("a5 5 0 0110 10").
  double? flag() {
    skipSeparators();
    if (atEnd) return null;
    final unit = text.codeUnitAt(_pos);
    if (unit != 0x30 && unit != 0x31) return null;
    _pos++;
    return unit == 0x31 ? 1 : 0;
  }
}
