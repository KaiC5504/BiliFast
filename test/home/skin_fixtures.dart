import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bili_core/api.dart';
import 'package:bilifast/skin/skin.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 110's and 109's colours: white tabs and indicator over light status-bar text, the bar's labels #FAF0E4 and #FFDA76
/// selected.
const standInColors = SkinColors(
  color: 0xFFFFFFFF,
  lightText: true,
  tailColor: 0xFFFAF0E4,
  tailColorSelected: 0xFFFFDA76,
);

/// Drawn stand-ins for a 装扮's pictures (never the official art), as PNGs in a temp folder, in the shapes 110 and 109
/// measure: the head 1320 × 318 px down to the top row's bottom, the tab strip's 108 px, the bar's picture 83 pt tall
/// with a wavy top, icons whose ink is 41 of their 45 pt box, 发布's cross 30 of its 38, and 我的's header a square in
/// the dark of 109's frame. `broken.png` is no picture at all.
class SkinPictures {
  SkinPictures._(this.folder);

  final Directory folder;

  File operator [](String name) => File('${folder.path}/$name');

  /// The five icons' colours, so a picture in the wrong place shows.
  static const _iconFills = [
    Color(0xFFF2A0B8),
    Color(0xFF8FB8E8),
    Color(0xFF9BD49B),
    Color(0xFFF2C27A),
    Color(0xFFC3A3E8),
  ];

  /// Draws them into a new temp folder; outside a test's fake time (`setUpAll`), as drawing waits on the engine.
  static Future<SkinPictures> draw() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final pictures = SkinPictures._(Directory.systemTemp.createTempSync('skin_pictures'));
    await _png(pictures['head_bg.png'], 1320, 318, _head);
    await _png(pictures['head_tab_bg.png'], 1320, 108, (canvas, size) {
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF161513));
    });
    await _png(pictures['tail_bg.png'], 1320, 249, _tail);
    await _png(pictures['tail_bg_tall.png'], 1320, 330, _tail);
    await _png(pictures['tail_bg_flat.png'], 1080, 156, _tail);
    for (var i = 0; i < 5; i++) {
      await _png(pictures['tail_icon_$i.png'], 180, 135, (canvas, size) => _icon(canvas, size, i, selected: false));
      await _png(
        pictures['tail_icon_selected_$i.png'],
        180,
        135,
        (canvas, size) => _icon(canvas, size, i, selected: true),
      );
    }
    await _png(pictures['pub.png'], 114, 114, _pub);
    await _png(pictures['head_myself.png'], 1320, 1320, (canvas, size) {
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF292323));
    });
    await pictures['broken.png'].writeAsBytes([for (var i = 0; i < 200; i++) i * 31 % 256]);
    // SvgaView reads its own files; these bytes only need to exist.
    for (final i in [0, 4]) {
      await pictures['tail_icon_selected_$i.svga'].writeAsBytes([0x53, 0x56, 0x47, 0x41]);
    }
    return pictures;
  }

  void dispose() => folder.deleteSync(recursive: true);

  /// A skin over these pictures. [icons] cuts the bar's icons short; [animated] makes those selected icons `.svga`
  /// ([svga] in place of the stand-in bytes); [iconFiles] swaps unselected icons' pictures by index; [me] dresses
  /// 我的's header too, [video] over it.
  Skin skin({
    bool head = true,
    String headPicture = 'head_bg.png',
    bool tab = true,
    String tabPicture = 'head_tab_bg.png',
    String? tail = 'tail_bg.png',
    int icons = 5,
    Set<int> animated = const {},
    File? svga,
    Map<int, String> iconFiles = const {},
    bool pub = true,
    String pubFile = 'pub.png',
    bool me = true,
    File? video,
    SkinColors colors = standInColors,
  }) => Skin(
    equip: SkinEquip(
      id: 1,
      name: '测试装扮',
      ver: 1,
      packageUrl: 'https://example.invalid/skin.zip',
      packageMd5: '00000000000000000000000000000000',
      colors: colors,
    ),
    headBg: head ? this[headPicture] : null,
    headTabBg: head && tab ? this[tabPicture] : null,
    headMyself: me ? this['head_myself.png'] : null,
    headMyselfVideo: me ? video : null,
    tailBg: tail == null ? null : this[tail],
    tailIcons: [for (var i = 0; i < icons; i++) SkinIcon(this[iconFiles[i] ?? 'tail_icon_$i.png'])],
    tailIconsSelected: [
      for (var i = 0; i < icons; i++)
        animated.contains(i)
            ? SkinIcon(svga ?? this['tail_icon_selected_$i.svga'], animated: true)
            : SkinIcon(this['tail_icon_selected_$i.png']),
    ],
    pubButton: pub ? SkinIcon(this[pubFile]) : null,
  );

  /// Decodes [skin]'s still pictures into the image cache, which a widget test can't do in its fake time. Call it
  /// before anything shows them: a picture asked for first would wait on that fake time for ever. One that won't
  /// decode stays cached as failed, so a gate on it answers at once too.
  static Future<void> load(WidgetTester tester, Skin skin) async {
    final files = <File>[
      ?skin.headBg,
      ?skin.headTabBg,
      ?skin.headMyself,
      ?skin.tailBg,
      for (final icon in [...skin.tailIcons, ...skin.tailIconsSelected, ?skin.pubButton])
        if (!icon.animated) icon.file,
    ];
    if (tester.binding.rootElement == null) await tester.pumpWidget(const SizedBox.shrink());
    final context = tester.binding.rootElement!;
    await tester.runAsync(
      () =>
          Future.wait([for (final file in files) precacheImage(FileImage(file), context, onError: (_, _) {})])
              .timeout(const Duration(seconds: 20)),
    );
  }

  static Future<void> _png(File file, int width, int height, void Function(Canvas canvas, Size size) paint) async {
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  }

  /// A dark checker under a gold scroll across the top, plain dark for its last 30 px as 110's is.
  static void _head(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF161412));
    final checker = Paint()..color = const Color(0xFF2A2622);
    for (var x = 0.0; x < size.width; x += 132) {
      for (var y = 0.0; y < size.height - 60; y += 132) {
        if (((x + y) / 132).round().isEven) canvas.drawRect(Rect.fromLTWH(x, y, 132, 132), checker);
      }
    }
    final gold = Paint()
      ..color = const Color(0xFFB08A4A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14;
    for (var i = 0; i < 6; i++) {
      final x = i * size.width / 5;
      canvas.drawPath(
        Path()
          ..moveTo(x - 140, 60)
          ..quadraticBezierTo(x, 230, x + 140, 60),
        gold,
      );
    }
    canvas.drawRect(Rect.fromLTWH(0, size.height - 30, size.width, 30), Paint()..color = const Color(0xFF161412));
  }

  /// Transparent above a wave dipping 52 px towards the middle, with a crown at the centre; dark below with gold
  /// strokes.
  static void _tail(Canvas canvas, Size size) {
    final scale = size.width / 1320;
    double top(double x) => (9 + 52 * math.pow(math.sin(math.pi * x / size.width), 2)) * scale;
    final body = Path()..moveTo(0, top(0));
    for (var x = 0.0; x <= size.width; x += 4) {
      body.lineTo(x, top(x));
    }
    body
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFF161513));
    final centre = size.width / 2;
    canvas.drawPath(
      Path()
        ..moveTo(centre - 70 * scale, top(centre) + 4)
        ..lineTo(centre, 6 * scale)
        ..lineTo(centre + 70 * scale, top(centre) + 4)
        ..close(),
      Paint()..color = const Color(0xFFA07C40),
    );
    final gold = Paint()
      ..color = const Color(0xFFA07C40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12 * scale;
    for (var i = 0; i < 4; i++) {
      final x = (i + 0.5) * size.width / 4;
      canvas.drawPath(
        Path()
          ..moveTo(x - 150 * scale, size.height * 0.45)
          ..quadraticBezierTo(x, size.height * 0.95, x + 150 * scale, size.height * 0.45),
        gold,
      );
    }
  }

  /// A face 123 px tall (41 pt) in the 45 pt box with a beige rim; the selected one has a star.
  static void _icon(Canvas canvas, Size size, int index, {required bool selected}) {
    final centre = size.center(Offset.zero);
    canvas
      ..drawCircle(centre, 61.5, Paint()..color = const Color(0xFFE8C987))
      ..drawCircle(centre, 55, Paint()..color = _iconFills[index]);
    if (!selected) return;
    final star = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? 16.0 : 7.0;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point = Offset(28 + radius * math.cos(angle), 28 + radius * math.sin(angle));
      i == 0 ? star.moveTo(point.dx, point.dy) : star.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(star..close(), Paint()..color = const Color(0xFFFFE9B0));
  }

  /// A rounded cross 90 px across (30 pt) in its 38 pt square, white rimmed.
  static void _pub(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    for (final (paint, half, arm) in [
      (Paint()..color = const Color(0xFFFFFFFF), 45.0, 17.0),
      (Paint()..color = const Color(0xFFF7C080), 39.0, 11.0),
    ]) {
      canvas
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: centre, width: half * 2, height: arm * 2),
            Radius.circular(arm),
          ),
          paint,
        )
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: centre, width: arm * 2, height: half * 2),
            Radius.circular(arm),
          ),
          paint,
        );
    }
  }
}
