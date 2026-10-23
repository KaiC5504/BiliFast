import 'dart:ui' show Size;

import 'package:bilifast/shared/cover_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("the presets' addresses are the official app's", () {
    expect(CoverPreset.feed.suffix, '@630w_473h_85q_!pegasus-ios-v2.avif');
    expect(CoverPreset.related.suffix, '@360w_202h_1e_1c_85q.avif');
    expect(CoverPreset.space.suffix, '@384w_216h_1e_1c_85q.webp');
    expect(CoverPreset.history.suffix, '@450w_251h_1e_1c_85q.avif');
    expect(CoverPreset.player.suffix, '@1260w_709h_85q_!pegasus-ios-v2.avif');
  });

  test("a box narrower than 3:2 takes 推荐's; a wider one the smallest wide preset at least 95% of it each way", () {
    for (final (width, height, preset) in [
      (633.0, 475.0, CoverPreset.feed),
      (100.0, 100.0, CoverPreset.feed),
      (449.0, 300.0, CoverPreset.feed),
      (450.0, 300.0, CoverPreset.list),
      (360.0, 202.0, CoverPreset.related),
      (378.0, 212.0, CoverPreset.related),
      (384.0, 216.0, CoverPreset.history),
      (408.0, 228.0, CoverPreset.history),
      (417.0, 234.0, CoverPreset.history),
      (516.0, 291.0, CoverPreset.list),
      (640.0, 360.0, CoverPreset.wide),
      (1320.0, 743.0, CoverPreset.player),
      (2000.0, 1125.0, CoverPreset.player),
    ]) {
      expect(CoverPreset.forBox(Size(width, height)), preset, reason: '$width × $height');
    }
  });

  test("a box never takes the space's own preset or exact", () {
    for (var width = 60.0; width <= 2400; width += 7) {
      for (final aspect in [1.5, 16 / 9, 2.0, 3.0]) {
        final preset = CoverPreset.forBox(Size(width, width / aspect));
        expect(preset, isNot(anyOf(CoverPreset.space, CoverPreset.exact)), reason: '$width at $aspect');
      }
    }
  });
}
