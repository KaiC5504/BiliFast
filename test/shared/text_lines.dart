import 'dart:ui' as ui;

import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stand_in_fonts.dart';

/// The app's theme as `main.dart` builds it for the current [BiliFonts.family].
ThemeData appTheme() =>
    ThemeData(fontFamily: BiliFonts.family, fontFamilyFallback: BiliFonts.fallback, textTheme: BiliFonts.untracked);

/// Where a laid-out text's lines sit, globally: each line's box, struts included, and the top of the first Han glyph's
/// ink box on each line. PingFang draws the Han glyphs of a Chinese line and of a mixed one alike, so equal glyph tops
/// are equal baselines.
final class TextLines {
  const TextLines(this.lines, this.han);

  final List<Rect> lines;
  final List<double> han;

  double get pitch => lines[1].top - lines[0].top;
}

final _hanChar = RegExp(r'\p{Script=Han}', unicode: true);

/// [TextLines] of the Text, RichText or EditableText [finder] finds. An editable's boxes are its glyphs' own, so its
/// [TextLines.lines] are left empty.
TextLines linesOf(WidgetTester tester, Finder finder) {
  RenderBox? render;
  void visit(Element element) {
    if (render != null) return;
    final object = element.renderObject;
    if (object is RenderParagraph || object is RenderEditable) {
      render = object! as RenderBox;
    } else {
      element.visitChildren(visit);
    }
  }

  visit(finder.evaluate().single);
  return _linesOf(render ?? (throw StateError('no text under $finder')));
}

TextLines _linesOf(RenderBox render) {
  final origin = render.localToGlobal(Offset.zero);
  final String text;
  final List<TextBox> Function(TextSelection, ui.BoxHeightStyle) boxes;
  switch (render) {
    case RenderParagraph():
      text = render.text.toPlainText();
      boxes = (selection, style) => render.getBoxesForSelection(selection, boxHeightStyle: style);
    case RenderEditable():
      text = render.text!.toPlainText();
      boxes = (selection, _) => render.getBoxesForSelection(selection);
    default:
      throw ArgumentError.value(render, 'render', 'not text');
  }
  final lines = <Rect>[];
  if (render is RenderParagraph) {
    for (final line in boxes(TextSelection(baseOffset: 0, extentOffset: text.length), ui.BoxHeightStyle.max)) {
      final rect = line.toRect().shift(origin);
      final same = lines.indexWhere((seen) => (seen.top - rect.top).abs() < 0.01);
      if (same < 0) {
        lines.add(rect);
      } else {
        lines[same] = lines[same].expandToInclude(rect);
      }
    }
    lines.sort((a, b) => a.top.compareTo(b.top));
  }
  final glyphs = [
    for (final match in _hanChar.allMatches(text))
      ...boxes(
        TextSelection(baseOffset: match.start, extentOffset: match.end),
        ui.BoxHeightStyle.tight,
      ).map((box) => box.toRect().shift(origin)),
  ];
  final han = lines.isEmpty
      ? [if (glyphs.isNotEmpty) glyphs.first.top]
      : [
          for (final line in lines)
            if (glyphs.where((glyph) => line.contains(glyph.center)).firstOrNull case final glyph?) glyph.top,
        ];
  return TextLines(lines, han);
}

/// Sets [BiliFonts.family] to the system font for the test, with the stand-ins loaded.
Future<void> useSystemFont(WidgetTester tester) async {
  final saved = BiliFonts.family;
  addTearDown(() => BiliFonts.family = saved);
  BiliFonts.family = BiliFonts.system;
  await tester.runAsync(loadSystemFontStandIns);
}
