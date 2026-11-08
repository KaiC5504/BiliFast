import 'dart:ui' show Color;

import '../../shared/theme.dart';

/// What 设置's playback pages (170-174, 178, 179) add to [SettingsTheme], measured off KaiC's screenshots at 3 px a
/// pt. Their pages don't agree with each other: 首页推荐设置 (170) and the two pickers (178, 179) each have their own
/// insets, row heights and ✓.
abstract final class SettingsListTheme {
  /// A section's grey label and 178's note, 12 pt; a row's grey second line, 13 pt.
  static const labelText = 12.0;
  static const label = BiliColors.secondaryText;
  static const subtitleText = 13.0;
  static const subtitle = BiliColors.secondaryText;

  /// Where a Chinese glyph's middle sits above its line box's, in em: what turns the screenshots' glyph middles into
  /// line places, measured off the system font's stand-in.
  static const glyphRise = 0.0;

  /// 174's label: 92 px of grey, the label's middle 17.17 pt down and 15 pt in, then the full-width hairline every
  /// section starts with.
  static const labelHeight = 92 / 3;
  static const labelCentre = 17.17;
  static const labelInset = 15.0;

  /// 170's: 31 pt of grey with the label a point further in, and no hairline under it.
  static const feedLabelHeight = 31.0;
  static const feedLabelCentre = 17.0;
  static const feedLabelInset = 16.0;

  /// 178's note over its picks: 42 pt of grey, no hairline.
  static const noteHeight = 42.0;
  static const noteCentre = 20.67;

  /// 170's last section and 179 start 20 pt under the bar, without a hairline.
  static const plainGap = 20.0;

  /// The switch (172-174): a 124 × 55 px pill ending 23 px from the screen's edge, its knob a white pill 73 px wide
  /// inset 4 px, at the end the switch is set to.
  static const switchWidth = 124 / 3;
  static const switchHeight = 55 / 3;
  static const switchKnobWidth = 73 / 3;
  static const switchBorder = 4 / 3;
  static const switchRight = 23 / 3;
  static const switchOn = BiliColors.pink;
  static const switchOff = Color(0xFFC5C5C7);
  static const switchKnob = BiliColors.card;

  /// A switch row with a second line (172-174): 177 px from hairline to hairline; the switch's middle sits a little
  /// above the row's, a one-line row's a little above too.
  static const switchTallHeight = 176 / 3;
  static const switchTitleCentre = 20.92;
  static const switchSubtitleCentre = 45.5;
  static const switchTallCentre = 28.75;
  static const switchCentre = 21.0;

  /// 首页推荐设置's ✓ rows (170): 130 px over a 2 px hairline, 190 with a second line, titles 15 pt in; the ✓'s ink
  /// ends 61 px from the edge.
  static const feedRule = 2 / 3;
  static const feedHeight = 130 / 3;
  static const feedTitleCentre = 22.0;
  static const feedCheckCentre = 21.5;
  static const feedTallHeight = 190 / 3;
  static const feedTallTitleCentre = 22.04;
  static const feedTallSubtitleCentre = 44.17;
  static const feedTallCheckCentre = 31.5;
  static const feedCheckEnd = 61 / 3;
  static const feedCheckShort = 3.5;
  static const feedCheckLong = 8.0;
  static const feedCheckStroke = 1.1;

  /// 首页单双列切换 under its 20 pt gap: 131 px over a 1 px hairline.
  static const feedLinkHeight = 131 / 3;

  /// The pickers (178, 179): 125 px rows 12 pt in, the hairlines stopping 37 px short of 178's right edge, a smaller
  /// ✓ ending 43 px from the edge.
  static const pickerInset = 12.0;
  static const pickerRuleEnd = 37 / 3;
  static const pickerHeight = 125 / 3;
  static const pickerTitleCentre = 20.17;
  static const pickerCheckCentre = 21.67;
  static const pickerCheckEnd = 43 / 3;
  static const pickerCheckShort = 3.4;
  static const pickerCheckLong = 7.2;
  static const pickerCheckStroke = 1.0;
  static const pickerTitleText = SettingsTheme.rowTitleText;
}
