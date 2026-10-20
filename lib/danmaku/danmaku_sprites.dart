import 'dart:ui' as ui;

import 'package:bili_core/danmaku.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../shared/theme.dart';

/// One danmaku's text, laid out and recorded once; each frame only moves it.
final class DanmakuSprite {
  const DanmakuSprite(this.picture, this.size);

  final ui.Picture picture;
  final Size size;
}

/// Lays out danmaku text into [DanmakuSprite]s, keeping recent ones so repeated text is laid out once.
final class DanmakuSprites {
  DanmakuSprites({this.capacity = 256});

  final int capacity;

  /// Danmaku laid out so far; the per-frame path must never add to it.
  int layouts = 0;

  // Insertion ordered: the first key is the least recently used.
  final _cache = <String, DanmakuSprite>{};
  final _lineHeights = <String, double>{};

  DanmakuSprite of(DisplayDanmaku danmaku, {required double pointSize}) {
    final rgb = danmaku.elem.color & 0xFFFFFF;
    final key = '${BiliFonts.family}|$pointSize|$rgb|${danmaku.isOwn}|${danmaku.text}';
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    final made = _render(danmaku.text, pointSize: pointSize, rgb: rgb, own: danmaku.isOwn);
    _cache[key] = made;
    if (_cache.length > capacity) _cache.remove(_cache.keys.first);
    return made;
  }

  /// The height of one line of danmaku text, which the lanes are spaced by.
  double lineHeight(double pointSize) =>
      _lineHeights['${BiliFonts.family}|$pointSize'] ??= _paragraph('弹幕Ag', pointSize, Paint()).height;

  /// The text with a 1 pt outline; one's own danmaku also get a white rounded box.
  DanmakuSprite _render(String text, {required double pointSize, required int rgb, required bool own}) {
    layouts += 1;
    final line = text.contains('\n') || text.contains('\r') ? text.split(RegExp(r'\r\n|\r|\n')).join(' ') : text;
    final red = ((rgb >> 16) & 0xFF) / 255, green = ((rgb >> 8) & 0xFF) / 255, blue = (rgb & 0xFF) / 255;
    final dark = 0.299 * red + 0.587 * green + 0.114 * blue < 0.25;
    // The stroke is centred on the glyph edges; the fill drawn over it hides the inner half.
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = BiliMetrics.danmakuOutline * 2
      ..strokeJoin = StrokeJoin.round
      ..color = dark ? BiliColors.danmakuOutlineLight : BiliColors.danmakuOutline;
    final stroke = _paragraph(line, pointSize, outline);
    final fill = _paragraph(line, pointSize, Paint()..color = Color(0xFF000000 | rgb));

    final padX = own ? BiliMetrics.danmakuOwnPadX : BiliMetrics.danmakuPad;
    final padY = own ? BiliMetrics.danmakuOwnPadY : BiliMetrics.danmakuPad;
    final size = Size(
      fill.maxIntrinsicWidth.ceilToDouble() + padX * 2,
      fill.height.ceilToDouble() + padY * 2,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawParagraph(stroke, Offset(padX, padY));
    canvas.drawParagraph(fill, Offset(padX, padY));
    if (own) {
      final box = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(0.5),
        const Radius.circular(BiliMetrics.danmakuOwnRadius),
      );
      canvas.drawRRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = BiliColors.danmakuOwnBox,
      );
    }
    return DanmakuSprite(recorder.endRecording(), size);
  }

  /// Built by hand for the paragraph, so it carries no ambient style: the system font's fallback has to be named here.
  @visibleForTesting
  static TextStyle textStyle(double pointSize, Paint foreground) => TextStyle(
    fontFamily: BiliFonts.family,
    fontFamilyFallback: BiliFonts.fallback,
    locale: BiliFonts.locale,
    fontSize: pointSize,
    fontWeight: FontWeight.w600,
    foreground: foreground,
  );

  static ui.Paragraph _paragraph(String text, double pointSize, Paint foreground) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(textDirection: TextDirection.ltr, maxLines: 1))
      ..pushStyle(textStyle(pointSize, foreground).getTextStyle())
      ..addText(text);
    return builder.build()..layout(const ui.ParagraphConstraints(width: double.infinity));
  }
}
