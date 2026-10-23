import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:bili_core/api.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';

import 'skin_api.dart';
import 'skin_package.dart';
import 'stand_in_gif.dart';

/// Made-up answers for tests and `--fake-account` on the PC: no skin call leaves the machine. [demo] builds a package
/// of drawn stand-in pictures and a stand-in 加载动画 (never the official art). [calls] lists what was asked; [holds]
/// keeps a call waiting and [failures] makes it throw.
class FakeSkinApi implements SkinApi {
  FakeSkinApi({this.equip, this.package = const [], this.loading, this.loadingPicture = const []}) : _demo = false;

  /// [DemoSkin]'s equip, package and 加载动画, drawn on the first call.
  FakeSkinApi.demo() : _demo = true, package = const [], loadingPicture = const [];

  final bool _demo;
  Future<void>? _demoDrawn;

  SkinEquip? equip;
  List<int> package;
  SkinLoading? loading;
  List<int> loadingPicture;

  /// Answers with these as [SkinWorn]'s, the halves it didn't understand.
  String? equipError;
  String? loadingError;

  final calls = <String>[];
  final holds = <String, Completer<void>>{};
  final failures = <String, Object>{};

  Future<T> _answer<T>(String name, T Function() value) async {
    calls.add(name);
    if (_demo) await (_demoDrawn ??= _drawDemo());
    if (holds[name] case final hold?) await hold.future;
    if (failures[name] case final failure?) throw failure;
    return value();
  }

  Future<void> _drawDemo() async {
    final demo = await DemoSkin.build();
    equip = demo.equip;
    package = demo.package;
    loading = DemoSkin.loading;
    loadingPicture = DemoSkin.loadingGif();
  }

  @override
  Future<SkinWorn> equipped() => _answer(
    'equipped',
    () => SkinWorn(equip: equip, loading: loading, equipError: equipError, loadingError: loadingError),
  );

  @override
  Future<List<int>> download(Uri package) => _answer('download', () => this.package);

  @override
  Future<List<int>> downloadLoading(Uri picture) => _answer('loading', () => loadingPicture);
}

/// A package in the official layout with every picture role, drawn here (gradients, shapes and letters at about the
/// official sizes), and the equip that points at it: light text and both tail colours, so the bar is themed. It has
/// no header video, which can't be drawn.
final class DemoSkin {
  const DemoSkin._(this.equip, this.package);

  final SkinEquip equip;
  final Uint8List package;

  static Future<DemoSkin>? _built;

  /// Drawn once per run.
  static Future<DemoSkin> build() => _built ??= _draw();

  static const id = 1;
  static const ver = 1;

  /// Under an allowed CDN host so the model's checks pass; [FakeSkinApi] never fetches it.
  static const packageUrl = 'https://i0.hdslb.com/bilifast-demo/skin.zip';

  static const loading = SkinLoading(
    id: 1,
    name: 'BiliFast demo',
    url: 'https://i0.hdslb.com/bilifast-demo/loading.gif',
    ver: 1,
  );

  static const loadingSide = 144;
  static const loadingFrames = 8;

  /// The stand-in 加载动画: a figure under an umbrella, bobbing while a stripe turns round the canopy, as a looping
  /// gif of [loadingFrames] frames, [loadingSide] pixels square.
  static Uint8List loadingGif() => encodeStandInGif(
    width: loadingSide,
    height: loadingSide,
    frames: [for (var frame = 0; frame < loadingFrames; frame++) _loadingFrame(frame)],
    palette: const [0x000000, 0xFF8FB1, 0xFFFFFF, 0x1B1F3B],
  );

  static Uint8List _loadingFrame(int frame) {
    const side = loadingSide;
    const canopy = 1;
    const light = 2;
    const ink = 3;
    final pixels = Uint8List(side * side);
    final turn = frame / loadingFrames;
    final bob = (6 * math.sin(2 * math.pi * turn)).round();
    final stripe = math.pi + math.pi * turn;
    void dot(int x, int y, int colour) {
      if (x >= 0 && x < side && y >= 0 && y < side) pixels[y * side + x] = colour;
    }

    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final (cx, cy) = (x - 72, y - (48 + bob));
        if (cy <= 0 && cx * cx + cy * cy <= 46 * 46) {
          // From pi (left) to 2 pi (right) over the canopy, as the stripe runs.
          final angle = math.atan2(cy.toDouble(), cx.toDouble()) + 2 * math.pi;
          dot(x, y, (angle - stripe).abs() < 0.2 ? light : canopy);
        }
      }
    }
    for (var y = 48 + bob; y < 92 + bob; y++) {
      for (var x = 71; x <= 73; x++) {
        dot(x, y, ink);
      }
    }
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final (dx, dy) = (x - 72, y - (106 + bob));
        final distance = dx * dx + dy * dy;
        if (distance <= 26 * 26) dot(x, y, distance >= 23 * 23 ? ink : light);
      }
    }
    for (final eye in const [63, 81]) {
      for (var dy = -3; dy <= 3; dy++) {
        for (var dx = -3; dx <= 3; dx++) {
          if (dx * dx + dy * dy <= 9) dot(eye + dx, 102 + bob + dy, ink);
        }
      }
    }
    return pixels;
  }

  static Future<DemoSkin> _draw() async {
    final pictures = <String, Uint8List>{
      'head_bg.png': await _png(1320, 430, _head),
      'head_tab_bg.png': await _png(1320, 132, _tabStrip),
      'head_myself_bg.png': await _png(1320, 1000, _myself),
      'tail_bg.png': await _png(1320, 300, _tail),
      for (final (index, tab) in SkinNames.tabs.indexed) ...{
        'tail_icon_$tab.png': await _png(180, 135, (canvas, size) => _icon(canvas, size, _letters[index], false)),
        'tail_icon_selected_$tab.png': await _png(
          180,
          135,
          (canvas, size) => _icon(canvas, size, _letters[index], true),
        ),
      },
      'tail_icon_pub_btn_bg.png': await _png(180, 135, (canvas, size) => _publish(canvas, size, false)),
      'tail_icon_selected_pub_btn_bg.png': await _png(180, 135, (canvas, size) => _publish(canvas, size, true)),
    };
    final archive = Archive();
    for (final MapEntry(key: name, value: bytes) in pictures.entries) {
      archive.add(ArchiveFile.noCompress(name, bytes.length, bytes));
    }
    // A fixed time keeps the md5 the same from run to run, so a run reuses the last one's unpacked demo.
    final zip = ZipEncoder().encodeBytes(archive, modified: DateTime(2026, 10, 22));
    return DemoSkin._(
      SkinEquip(
        id: id,
        name: 'BiliFast demo',
        ver: ver,
        packageUrl: packageUrl,
        packageMd5: md5.convert(zip).toString(),
        colors: const SkinColors(
          color: 0xFFFFFFFF,
          lightText: true,
          tailColor: 0xFFB8C0CC,
          tailColorSelected: 0xFFFFC94D,
        ),
      ),
      zip,
    );
  }

  // The stand-in art's own colours, not the app's.
  static const _night = Color(0xFF1B1F3B);
  static const _ink = Color(0xFF0B0D1A);
  static const _violet = Color(0xFF6C4AB6);
  static const _teal = Color(0xFF1FA2A6);
  static const _gold = Color(0xFFFFC94D);
  static const _mist = Color(0xFFB8C0CC);
  static const _white = Color(0xFFFFFFFF);

  static const _letters = ['H', 'C', 'D', 'S', 'M'];

  static Future<Uint8List> _png(int width, int height, void Function(Canvas canvas, Size size) paint) async {
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  static void _head(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = ui.Gradient.linear(Offset.zero, size.bottomRight(Offset.zero), [_night, _violet]),
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = _white.withValues(alpha: 0.18);
    for (var i = 0; i < 5; i++) {
      canvas.drawCircle(Offset(size.width * 0.82, size.height * 0.3), 60.0 + i * 48, ring);
    }
    _text(canvas, 'HEAD', Offset(size.width * 0.3, size.height * 0.55), 150, _white.withValues(alpha: 0.35));
  }

  static void _tabStrip(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = ui.Gradient.linear(Offset.zero, size.topRight(Offset.zero), [_violet, _night]),
    );
    final dot = Paint()..color = _white.withValues(alpha: 0.25);
    for (var x = 30.0; x < size.width; x += 60) {
      canvas.drawCircle(Offset(x, size.height - 18), 6, dot);
    }
    _text(canvas, 'TABS', Offset(size.width * 0.88, size.height * 0.4), 54, _gold.withValues(alpha: 0.6));
  }

  static void _myself(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = ui.Gradient.radial(Offset(size.width * 0.75, size.height * 0.2), size.width, [_teal, _night]),
    );
    final star = Paint()..color = _white.withValues(alpha: 0.6);
    for (var i = 0; i < 40; i++) {
      // A fixed scatter, so every build draws the same package.
      final x = (i * 197 % 1320).toDouble();
      final y = (i * 383 % 1000).toDouble();
      canvas.drawCircle(Offset(x, y), 3.0 + i % 4, star);
    }
    _text(canvas, 'ME', Offset(size.width * 0.75, size.height * 0.62), 320, _white.withValues(alpha: 0.3));
  }

  static void _tail(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = ui.Gradient.linear(Offset.zero, size.bottomLeft(Offset.zero), [_night, _ink]),
    );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 6), Paint()..color = _gold);
    final stripe = Paint()..color = _violet.withValues(alpha: 0.35);
    for (var x = -size.height; x < size.width; x += 90) {
      canvas.drawPath(
        Path()
          ..moveTo(x, size.height)
          ..lineTo(x + 30, size.height)
          ..lineTo(x + 30 + size.height, 0)
          ..lineTo(x + size.height, 0)
          ..close(),
        stripe,
      );
    }
    _text(canvas, 'TAIL', Offset(size.width * 0.5, size.height * 0.55), 90, _white.withValues(alpha: 0.2));
  }

  static void _icon(Canvas canvas, Size size, String letter, bool selected) {
    final box = RRect.fromRectAndRadius(
      Rect.fromCenter(center: size.center(Offset.zero), width: 110, height: 110),
      const Radius.circular(28),
    );
    if (selected) {
      canvas.drawRRect(box, Paint()..color = _gold);
    } else {
      canvas.drawRRect(
        box.deflate(4),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..color = _mist,
      );
    }
    _text(canvas, letter, size.center(Offset.zero), 64, selected ? _night : _mist);
  }

  static void _publish(Canvas canvas, Size size, bool selected) {
    final pill = RRect.fromRectAndRadius(
      Rect.fromCenter(center: size.center(Offset.zero), width: 150, height: 100),
      const Radius.circular(50),
    );
    canvas.drawRRect(pill, Paint()..color = selected ? _gold : _violet);
    _text(canvas, '+', size.center(Offset.zero), 80, selected ? _night : _white);
  }

  /// [text] in stroked capitals centred on [center]. Stroked rather than set in a font: which font the engine has
  /// loaded at launch changed the drawing, and with it the package's md5, from one PC run to the next.
  static void _text(Canvas canvas, String text, Offset center, double fontSize, Color color) {
    final height = fontSize * 0.7;
    final width = height * 0.6;
    final gap = height * 0.25;
    final total = text.length * width + (text.length - 1) * gap;
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = height * 0.14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    var left = center.dx - total / 2;
    final top = center.dy - height / 2;
    // One path, so translucent strokes don't darken where they cross.
    final path = Path();
    for (final letter in text.split('')) {
      for (final stroke in _strokes[letter] ?? const <List<(double, double)>>[]) {
        final (startX, startY) = stroke.first;
        path.moveTo(left + startX * width, top + startY * height);
        for (final (x, y) in stroke.skip(1)) {
          path.lineTo(left + x * width, top + y * height);
        }
      }
      left += width + gap;
    }
    canvas.drawPath(path, pen);
  }

  /// The few capitals the demo writes, as polylines in a unit box.
  static const _strokes = <String, List<List<(double, double)>>>{
    'A': [
      [(0, 1), (0.5, 0), (1, 1)],
      [(0.25, 0.55), (0.75, 0.55)],
    ],
    'B': [
      [(0, 0), (0, 1), (0.75, 1), (1, 0.8), (1, 0.65), (0.75, 0.5), (0, 0.5)],
      [(0.75, 0.5), (0.95, 0.35), (0.95, 0.15), (0.75, 0), (0, 0)],
    ],
    'C': [
      [(1, 0.15), (0.8, 0), (0.2, 0), (0, 0.2), (0, 0.8), (0.2, 1), (0.8, 1), (1, 0.85)],
    ],
    'D': [
      [(0, 0), (0, 1), (0.6, 1), (1, 0.7), (1, 0.3), (0.6, 0), (0, 0)],
    ],
    'E': [
      [(1, 0), (0, 0), (0, 1), (1, 1)],
      [(0, 0.5), (0.8, 0.5)],
    ],
    'H': [
      [(0, 0), (0, 1)],
      [(1, 0), (1, 1)],
      [(0, 0.5), (1, 0.5)],
    ],
    'I': [
      [(0.5, 0), (0.5, 1)],
      [(0.2, 0), (0.8, 0)],
      [(0.2, 1), (0.8, 1)],
    ],
    'L': [
      [(0, 0), (0, 1), (1, 1)],
    ],
    'M': [
      [(0, 1), (0, 0), (0.5, 0.55), (1, 0), (1, 1)],
    ],
    'S': [
      [(1, 0.1), (0.8, 0), (0.2, 0), (0, 0.15), (0, 0.35), (0.2, 0.5), (0.8, 0.5), (1, 0.65), (1, 0.85), (0.8, 1)],
      [(0.8, 1), (0.2, 1), (0, 0.9)],
    ],
    'T': [
      [(0, 0), (1, 0)],
      [(0.5, 0), (0.5, 1)],
    ],
    '+': [
      [(0.5, 0.1), (0.5, 0.9)],
      [(0.1, 0.5), (0.9, 0.5)],
    ],
  };
}
