import 'package:flutter/material.dart' show TextTheme;
import 'package:flutter/widgets.dart';

/// Colours and sizes sampled from the official app's screenshots (BiliNative `Shared/Theme.swift`), so widgets
/// never carry literals.
abstract final class BiliColors {
  static const pink = Color(0xFFFF6699);
  static const pinkTint = Color(0x1FFF6699);
  static const text = Color(0xFF18191C);
  static const secondaryText = Color(0xFF9499A0);
  static const pageGrey = Color(0xFFF1F2F3);

  /// The fill behind the collection row, tag chips and reply previews on the video page.
  static const softGrey = Color(0xFFF6F7F8);
  static const divider = Color(0xFFE3E5E7);
  static const link = Color(0xFF00699D);
  static const card = Color(0xFFFFFFFF);

  /// The feed's 推荐 reason and 竖屏 tag (01) are orange-red, not the pink accent.
  static const reason = Color(0xFFFF6633);
  static const reasonTint = Color(0xFFFFF1ED);

  /// Counts, durations and progress drawn over covers.
  static const onCover = Color(0xFFFFFFFF);
  static const coverShade = Color(0x80000000);
  static const scrim = Color(0x33000000);
  static const toastFill = Color(0xEB000000);

  /// How dark the layer behind a panel is once it is fully in, as a share of black.
  static const panelShadeOpacity = 0.86;
  static const panelShade = Color(0xDB000000);

  /// Share of black at 0, 35, 70 and 100 per cent of the ramp that leads into a panel; the official app's frames
  /// give a slow start and about 0.74 where the cards begin.
  static const panelFade = <(double, double)>[(0, 0), (0.35, 0.2), (0.7, 0.55), (1, 0.74)];

  /// Over black this lands on the official #212327; over a bright video it lifts a few levels, as theirs does.
  static const panelCard = Color(0xCC2B2C30);
  static const panelText = Color(0xFFFFFFFF);
  static const panelSecondary = Color(0xFF9499A0);

  /// Inside the player's panels, measured on the official app's 05, 06, 20 and 21: hairlines, the off switch track,
  /// the dark sheet's grabber, the switch knob and the highlight under a pressed row.
  static const panelHairline = Color(0xFF484C52);
  static const panelTrackOff = Color(0x0FFFFFFF);
  static const panelGrabber = Color(0x4DFFFFFF);
  static const panelKnob = Color(0xFFFFFFFF);
  static const panelPressed = Color(0x14FFFFFF);

  /// The light 选集 sheet in portrait (19): its grabber, the cross in the grey close circle, and 内容到底啦.
  static const sheetGrabber = Color(0xFFC9CCCF);
  static const sheetCloseGlyph = Color(0xFF61666D);
  static const sheetHint = Color(0xFFC9CCCF);

  /// 19 dims the page below the player behind the 选集 sheet; the player stays undimmed.
  static const sheetDim = Color(0x80000000);

  /// Behind and over the video.
  static const videoBackground = Color(0xFF000000);
  static const onVideo = Color(0xFFFFFFFF);
  static const statsFill = Color(0x8C000000);
  static const statsBorder = Color(0x1FFFFFFF);

  /// The gesture HUD's pills, sampled on 25: a dark grey at 62%, the 倍速中 arrows white at 91% (front) and 59%.
  static const hudFill = Color(0x9E1D1D1D);
  static const hudArrowFront = Color(0xE8FFFFFF);
  static const hudArrowBack = Color(0x96FFFFFF);

  /// The test screen (slice 1): text on the pink button, and what went wrong.
  static const onPink = Color(0xFFFFFFFF);
  static const failure = Color(0xFFF2453D);

  /// The player's controls (BiliNative `ChromeTheme.swift`); the played part is [pink].
  static const chromeTrack = Color(0x33FFFFFF);
  static const chromeBuffered = Color(0x66FFFFFF);
  static const chromeShade = Color(0x73000000);
  static const chromeShadeClear = Color(0x00000000);
  static const thumbRim = Color(0x4DFF6699);
  static const thumbBody = Color(0xFF000000);
  static const thumbScreen = Color(0xFFFFFFFF);

  /// The small player's controls and end screen, and the bar's chapter ticks and 竖屏 style, measured on the official
  /// app's 03, 09, 15 and 26.
  static const chromeTick = Color(0xB3000000);
  static const verticalTrack = Color(0x26FFFFFF);
  static const verticalPlayed = Color(0x99FFFFFF);
  static const verticalThumb = Color(0xFFFFFFFF);
  static const chapterFill = Color(0x8C000000);
  static const badgeFill = Color(0x40000000);
  static const badgeBorder = Color(0x80FFFFFF);
  static const badgeText = Color(0xFFFFFFFF);

  /// 26's video never gets brighter than 41 of 255 under its dim.
  static const endDim = Color(0xD6000000);

  /// 立即播放 over 26's dimmed frame (about 10 of 255) comes out #535353.
  static const endButton = Color(0x4DFFFFFF);
  static const endCaption = Color(0x99FFFFFF);
  static const endMeta = Color(0x99FFFFFF);
  static const endPlayGlyph = Color(0xF2FFFFFF);
  static const endCoverShade = Color(0x8C000000);

  /// Danmaku outlines: very dark text gets the light one, or it would vanish inside it. 44, at 不透明度 70%, has
  /// its white text at 70% over black and its outlines at 70% black over light pictures: both are drawn opaque and
  /// the layer's opacity fades them together.
  static const danmakuOutline = Color(0xFF000000);
  static const danmakuOutlineLight = Color(0xFFFFFFFF);
  static const danmakuOwnBox = Color(0xFFFFFFFF);

  /// The full-screen controls and end screen (BiliNative `ChromeTheme.swift`, sampled on 04, 09 and 27).
  static const chromeFaint = Color(0x80FFFFFF);
  static const chromeViews = Color(0xD9FFFFFF);
  static const chromeDivider = Color(0x26FFFFFF);
  static const chromeDarkField = Color(0xFF262626);
  static const landscapeEndDim = Color(0x9E000000);
  static const landscapeEndRule = Color(0x12FFFFFF);
  static const landscapeEndPlaceholder = Color(0x38FFFFFF);

  /// The speed test's comparison with the first variant.
  static const faster = Color(0xFF34C759);
  static const slower = Color(0xFFF2453D);

  /// The loading cards' sweep.
  static const shimmerBase = Color(0xFFEDEEF0);
  static const shimmerHighlight = Color(0xFFF8F9FA);

  /// The menus' frosted glass, and the highlight under a pressed row.
  static const glassFill = Color(0xB8FFFFFF);
  static const glassBorder = Color(0x99FFFFFF);
  static const glassShadow = Color(0x26000000);
  static const pressedFill = Color(0x14000000);

  /// The 最近打开 tile runs from this down to [pink], one hue as Swift's `Theme.pink.gradient`.
  static const recentsTileTop = Color(0xFFFF8AB2);

  /// The stats overlay's node dots (iOS system green, orange, red and grey).
  static const nodeHealthy = Color(0xFF34C759);
  static const nodeBlocked = Color(0xFFFF9500);
  static const nodeBanned = Color(0xFFFF3B30);
  static const nodeOther = Color(0xFF8E8E93);
}

/// The app's font, picked in 设置 → 字体 and applied at launch by `FontStore`. MiSans (Xiaomi, free for apps that credit
/// it; see README) is bundled: one font draws all the Chinese, where the Windows fallback mixes Japanese and Chinese
/// fonts. The zh-Hans locale makes any character a font lacks fall back to a Chinese font.
abstract final class BiliFonts {
  static const miSans = 'MiSans';

  /// The system font: SF, with PingFang SC for Chinese, as the official app draws. iOS's engine registers no family by
  /// this name (only CupertinoSystemDisplay, SF's large face), so on the phone it matches nothing and the engine's
  /// default, SF, draws; tests load the SF stand-in under it. Named rather than left null so tests never draw it in the
  /// square test font.
  static const system = 'CupertinoSystemText';

  /// The family every style names.
  static String? family = miSans;

  /// The layout nudges that line MiSans up with the official app's PingFang apply only while MiSans is on.
  static bool get nudged => family == miSans;

  static const locale = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN');

  /// What the system font names after [system]: set only by [settleSystemFallback] at launch, and by tests
  /// (test/flutter_test_config.dart, the PingFang stand-in).
  static List<String>? systemFallback;

  static List<String>? get fallback => family == system ? systemFallback : null;

  /// SF by the family name UIKit gives the system font, which the engine also looks up for the font it draws when a
  /// style's families match nothing.
  static const appleSystem = '.AppleSystemUIFont';

  static const _sfThenPingFang = [appleSystem, 'PingFang SC'];

  /// On iOS, names SF and then PingFang SC after [system]. With no list, the first character SF lacks has iOS pick a
  /// font, and the engine keeps that font for the rest of the line: a reply opening with a katakana name drew the
  /// whole line in a Japanese font, its commas and Chinese included. Since [system] itself matches nothing on iOS, the
  /// first listed family the phone has becomes every run's font, so the list is taken only when [appleSystem] draws
  /// Latin exactly as the unnamed default does; otherwise PingFang SC would draw it all (as Apple Color Emoji drew 1.0.0
  /// (15)'s digits and spaces) and the system font names nothing, as before. Returns whether the list was taken.
  static bool settleSystemFallback() {
    systemFallback = chooseSystemFallback(_latinWidth);
    return systemFallback != null;
  }

  /// SF then PingFang SC when the system font draws Latin as wide with them named as with nothing named, else null.
  @visibleForTesting
  static List<String>? chooseSystemFallback(double Function(List<String>? fallback) latinWidth) =>
      latinWidth(_sfThenPingFang) == latinWidth(null) ? _sfThenPingFang : null;

  static double _latinWidth(List<String>? fallback) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'Wi-Fi 1080P 0.5x',
        style: TextStyle(fontFamily: system, fontFamilyFallback: fallback, fontSize: 17),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// Under the system font, the strut a wrapping text whose lines can mix Latin and Chinese needs: each run splits its
  /// line height by its own font's ascent and descent, and SF's split differs from PingFang's, so a line holding both
  /// is a point taller than a Chinese one and its baseline a point lower. PingFang's line for every line keeps the
  /// official app's pitch. Null under MiSans, which draws both scripts.
  static StrutStyle? strut(TextStyle style) => family == system && style.height != null
      ? StrutStyle(
          fontFamily: 'PingFang SC',
          fontSize: style.fontSize,
          height: style.height,
          leadingDistribution: style.leadingDistribution,
          forceStrutHeight: true,
        )
      : null;

  /// [strut] for [style] as a Text under [context] draws it, the inherited default style merged in (most text takes
  /// its height from the Material's body style).
  static StrutStyle? strutOf(BuildContext context, [TextStyle? style]) =>
      strut(DefaultTextStyle.of(context).style.merge(style));

  /// Material's type scale tracks its text 0.1 to 0.5 pt, and every style that doesn't set its own spacing took that
  /// from the page's Material. iOS text isn't tracked; at 3 px per pt the extra 0.75 px leaves Chinese glyphs between
  /// pixels, some drawn crisp and the next blurred thinner, and widens every line.
  static const untracked = TextTheme(
    displayLarge: TextStyle(letterSpacing: 0),
    displayMedium: TextStyle(letterSpacing: 0),
    displaySmall: TextStyle(letterSpacing: 0),
    headlineLarge: TextStyle(letterSpacing: 0),
    headlineMedium: TextStyle(letterSpacing: 0),
    headlineSmall: TextStyle(letterSpacing: 0),
    titleLarge: TextStyle(letterSpacing: 0),
    titleMedium: TextStyle(letterSpacing: 0),
    titleSmall: TextStyle(letterSpacing: 0),
    bodyLarge: TextStyle(letterSpacing: 0),
    bodyMedium: TextStyle(letterSpacing: 0),
    bodySmall: TextStyle(letterSpacing: 0),
    labelLarge: TextStyle(letterSpacing: 0),
    labelMedium: TextStyle(letterSpacing: 0),
    labelSmall: TextStyle(letterSpacing: 0),
  );
}

abstract final class BiliMetrics {
  static const gutter = 12.0;
  static const cardRadius = 6.0;
  static const pillHeight = 30.0;

  /// The test screen (slice 1).
  static const titleText = 17.0;
  static const bodyText = 15.0;
  static const smallText = 12.0;
  static const rowGap = 8.0;
  static const sectionGap = 16.0;
  static const avatarSize = 32.0;
  static const fieldHeight = 40.0;
  static const tagPadding = 6.0;
  static const tagVerticalPadding = 2.0;
  static const iconSize = 18.0;

  /// The video page's player box and its back arrow.
  static const videoAspect = 16 / 9;
  static const videoBackIcon = 20.0;
  static const videoBackShadow = 6.0;

  /// The gesture HUD's pills, measured on 25 (px / 3): 倍速中 is 92 × 44, 10 below the top, centred, with its icon 14
  /// in, and its two overlapping arrows are 28/3 × 12 each before rounding, the second 23/3 right of the first.
  static const hudHeight = 44.0;
  static const hudMinWidth = 92.0;
  static const hudRadius = 8.0;
  static const hudTop = 10.0;
  static const hudPadding = 13.0;
  static const hudSpeedPaddingLeft = 14.0;
  static const hudSpeedPaddingRight = 12.0;
  static const hudGap = 19 / 3;
  static const hudFont = 14.0;

  /// MiSans sits higher in its line than the official app's PingFang; this brings the labels level with 25's.
  static double get hudLabelDrop => BiliFonts.nudged ? 4 / 3 : 0;
  static const hudArrowWidth = 31 / 3;
  static const hudArrowHeight = 41 / 3;
  static const hudArrowStep = 22 / 3;
  static const hudArrowCorner = 3.0;
  static const hudIcon = 18.0;
  static const hudBarWidth = 100.0;
  static const hudBarHeight = 3.0;
  static const hudSeekGap = 4.0;

  /// Flutter's Cupertino back swipe starts within this many points of the left edge (its private
  /// `_kBackGestureWidth`), or the left safe-area inset when that is wider.
  static const swipeBackEdge = 20.0;

  /// The player's controls (BiliNative `ChromeTheme.swift`).
  static const chromeButton = 44.0;
  static const chromeIcon = 28.0;
  static const chromeShadeHeight = 70.0;
  static const chromeTimeFont = 12.0;
  static const chromeTimeLeading = 9.0;
  static const chromeTimeTrailing = 10.0;
  static const barHeight = 2.0;
  static const barTouchHeight = 24.0;
  static const thumbWidth = 18.0;
  static const thumbHeight = 16.0;
  static const hiddenLine = 2.0;

  /// The small player's controls and end screen, and the bar's chapter title and 竖屏 dot, measured on the official
  /// app's 03, 09, 15 and 26. While dragged, the thumb and the bar grow a little.
  static const verticalDot = 4.0;
  static const verticalDotDragging = 10.0;
  static const thumbDragScale = 1.25;
  static const barDragHeight = 3.0;
  static const chapterTitleFont = 13.0;
  static const chapterTitleHeight = 24.0;
  static const chapterTitlePadding = 8.0;
  static const chapterTitleRadius = 4.0;
  static const chapterTitleGap = 6.0;
  static const chromeEdge = 1.0;

  /// How far the rows slide as they fade, as a share of their height.
  static const chromeRise = 0.3;
  static const chromePressedScale = 0.86;
  static const chromeGlyphStroke = 1.7;
  static const backGlyphWidth = 8.7;
  static const backGlyphHeight = 18.0;
  static const backGlyphStroke = 1.6;
  static const playGlyphWidth = 14.7;
  static const playGlyphHeight = 16.0;
  static const pauseBarWidth = 4.6;
  static const pauseBarGap = 4.4;
  static const playGlyphRounding = 1.4;
  static const fullScreenGap = 2.0;
  static const moreDot = 3.3;
  static const moreDotGap = 3.2;
  static const fullScreenGlyph = 14.0;
  static const cornersGlyphWidth = 13.0;
  static const cornersGlyphHeight = 15.5;
  static const badgeFont = 8.0;
  static const badgeHeight = 11.5;
  static const badgePadding = 2.2;
  static const badgeBorderWidth = 0.7;
  static const badgeOffsetX = 12.0;
  static const badgeOffsetY = -16.0;
  static const endInset = 12.0;
  static const endCaptionFont = 12.0;
  static const endCaptionGap = 3.8;

  /// MiSans draws 推荐视频 higher in its line than PingFang; this brings it level with 26's.
  static double get endCaptionDrop => BiliFonts.nudged ? 0.5 : 0;
  static const endCoverWidth = 128.0;
  static const endCoverHeight = 72.0;
  static const endCoverRadius = 5.0;
  static const endCoverGap = 11.0;
  static const endCoverShadeHeight = 30.0;
  static const endCoverTextInset = 8.7;
  static const endCoverTextBottom = 4.0;
  static const endCoverTimeFont = 10.0;
  static const endPlayGlyphWidth = 18.7;
  static const endPlayGlyphHeight = 22.0;
  static const endTitleFont = 14.0;

  /// The uploader and counts rows sit at fixed heights inside the cover's 72.
  static const endUploaderTop = 40.0;
  static const endCountsTop = 58.0;
  static const endMetaRow = 12.0;
  static const endMetaFont = 10.0;
  static const endCountIconWidth = 13.3;
  static const endCountIconHeight = 11.3;
  static const endMetaGap = 5.0;
  static const endMetaSpacing = 12.3;
  static const endUpWidth = 13.3;
  static const endUpHeight = 11.3;
  static const endUpFont = 7.5;
  static const endUpRadius = 2.5;
  static const endUpBorder = 1.0;
  static const endButtonFont = 14.0;
  static const endButtonWidth = 78.0;
  static const endButtonHeight = 30.0;

  /// MiSans sits higher in its line than the official app's PingFang; this centres 立即播放 in its pill as on 26.
  static double get endButtonTextDrop => BiliFonts.nudged ? 2 : 0;
  static const endButtonTrailing = 12.0;
  static const endActionsLeading = 13.7;
  static const endActionFont = 14.0;
  static const endActionGap = 8.0;
  static const endActionSpacing = 12.0;
  static const replayGlyphWidth = 21.0;
  static const replayGlyphHeight = 18.0;
  static const shareGlyphWidth = 20.0;
  static const shareGlyphHeight = 17.0;

  /// How far the end screen's parts rise as they come in.
  static const endRise = 14.0;

  /// The stats overlay.
  static const statsFont = 10.0;
  static const statsPadding = 6.0;
  static const statsRadius = 6.0;
  static const statsLineGap = 2.0;
  static const statsDot = 5.0;
  static const statsDotGap = 4.0;

  /// The full-screen controls, measured on 04 (landscape, 956 × 440 pt) and 09 (竖屏, 440 × 956 pt) at 3 px per pt.
  static const chromeTopShade = 120.0;
  static const chromeBottomShade = 140.0;
  static const landscapeEdge = 5.0;
  static const chromeTitleText = 16.0;
  static const chromeMoreTop = 20.0;

  /// 点赞 评论 收藏 投币 充电 分享: six 44 pt buttons, each followed by 8 (the last by the 8 before ⋮), and 24 pt
  /// clear of the title: 6 × 52 + 24.
  static const chromeActionsRoom = 336.0;
  static const chromeLineStroke = 1.4;
  static const chromeSideGap = 9.0;
  static const chromeSideLift = 15.0;
  static const chromeCameraWidth = 20.0;
  static const chromeCameraHeight = 17.0;
  static const chromeLockWidth = 21.0;
  static const chromeLockHeight = 20.5;
  static const chromeLockKey = 1.7;
  static const chromeTimeBox = 16.0;
  static const chromeTimeInset = 1.0;
  static const chromeBarTop = 15.0;
  static const chromeRowTop = 3.0;
  static const chromeRowBottom = 1.0;
  static const chromeRowTrailing = 15.0;
  static const chromePlayWidth = 21.5;
  static const chromePlayHeight = 25.0;

  /// 04's triangle sits right of its button's centre by this much.
  static const chromePlayShift = 2.2;
  static const chromePlayCorner = 2.5;
  static const chromePauseBar = 6.0;
  static const chromePauseGap = 5.0;
  static const chromePauseShare = 0.8;
  static const chromeDanmakuWidth = 21.0;
  static const chromeDanmakuHeight = 20.0;
  static const chromeDanmakuText = 10.5;

  /// 04 sets the TV 1 pt further from play than [landscapeEdge]; 09's 竖屏 row has it where it is.
  static const landscapeDanmakuLead = 6.0;

  /// The gaps either side of 弹幕设置's 44 pt button, between the 弹 toggle and the field (04).
  static const chromeSettingsGap = 4.0;
  static const chromeFieldGap = 4.0;

  /// 04's 发个友善的弹幕见证当下: an 80% white capsule over the video, its text a 60% black.
  static const chromeFieldHeight = 30.0;
  static const chromeFieldInset = 8.0;
  static const chromeFieldText = 12.0;
  static const chromeFieldFill = Color(0xCCFFFFFF);
  static const chromeFieldInk = Color(0x99000000);

  /// MiSans sits higher in its line than PingFang; this brings the field's text level with 04's.
  static double get chromeFieldDrop => BiliFonts.nudged ? 2 : 0;
  static const chromeSpeedGap = 14.0;
  static const chromeQualityGap = 23.0;
  static const chromeTextPad = 8.0;
  static const chromeLabelText = 14.0;

  /// How far a bar slides in, as a share of its own size.
  static const chromeSlide = 0.4;
  static const verticalTopLift = 8.0;
  static const verticalBackWidth = 9.0;
  static const verticalBackHeight = 16.0;
  static const verticalInfoInset = 12.0;

  /// The action column: 44 pt wide, 6 from the edge, 12 from the title.
  static const verticalColumnRoom = 62.0;
  static const verticalTitleText = 14.0;
  static const verticalTitleLeading = 1.6;
  static const verticalViewsText = 12.0;
  static const verticalViewsGap = 4.0;
  static const verticalChevronGap = 2.0;
  static const verticalChevronWidth = 9.7;
  static const verticalChevronHeight = 5.0;
  static const verticalChevronStroke = 1.0;
  static const verticalChevronTop = 4.4;

  /// The uploader above the title; 粉丝 goes under the name.
  static const verticalAvatar = 36.0;
  static const verticalAvatarRing = 1.0;
  static const verticalAvatarInset = 13.0;
  static const verticalAvatarGap = 10.0;
  static const verticalNameText = 15.0;
  static const verticalUploaderGap = 9.7;

  /// The search suggestion row between the title and the bar.
  static const verticalSearchRoom = 37.0;

  /// 09's bottom row reaches this far into the home indicator's inset.
  static const verticalBottomDrop = 1.0;
  static const verticalRowLift = 4.5;
  static const verticalFieldHeight = 32.0;
  static const verticalToggleWidth = 50.0;
  static const verticalDividerWidth = 1.0;
  static const verticalDividerHeight = 18.0;
  static const verticalDetailGap = 3.0;
  static const verticalLandscapeGap = 1.0;
  static const verticalCornersWidth = 13.5;
  static const verticalCornersHeight = 15.0;
  static const verticalBadgeX = 9.0;
  static const verticalBadgeY = -18.0;

  /// The full-screen end screen, measured on 27.
  static const landscapeEndRule = 1.0;
  static const landscapeEndRow = 96.0;

  /// The actions' column ends this far into the right safe area.
  static const landscapeEndActionsOutset = 2.0;
  static const landscapeEndActionWidth = 59.0;
  static const landscapeEndActionIcon = 22.0;
  static const landscapeEndActionText = 12.0;
  static const landscapeEndActionTop = 24.4;
  static const landscapeEndActionGap = 11.2;
  static const landscapeEndDividerHeight = 48.0;
  static const landscapeEndDividerGap = 12.5;
  static const landscapeEndAvatar = 60.0;
  static const landscapeEndAvatarRing = 2.0;
  static const landscapeEndAvatarInset = 12.0;
  static const landscapeEndAvatarGap = 12.0;
  static const landscapeEndNameText = 16.0;
  static const landscapeEndInset = 12.0;
  static const landscapeEndHeaderText = 14.0;
  static const landscapeEndHeaderTop = 19.7;
  static const landscapeEndRowTop = 12.0;
  static const landscapeEndCardWidth = 201.0;
  static const landscapeEndCoverHeight = 113.0;
  static const landscapeEndCardGap = 13.0;
  static const landscapeEndCardTitle = 12.0;
  static const landscapeEndCardTitleTop = 8.1;
  static const landscapeEndCardTitleLeading = 1.125;
  static const landscapeEndUploaderText = 10.0;
  static const landscapeEndUploaderTop = 7.4;
  static const landscapeEndCoverInset = 7.0;
  static const landscapeEndCoverBottom = 3.3;
  static const landscapeEndCountText = 11.0;
  static const landscapeEndCountIconWidth = 11.3;
  static const landscapeEndCountIconHeight = 9.1;
  static const landscapeEndCountIconLead = 2.0;
  static const landscapeEndCountIconGap = 1.0;
  static const landscapeEndCountIconRise = 0.8;
  static const landscapeEndCountGap = 3.0;
  static const landscapeEndCountSpacing = 7.0;

  /// How far a related card rises as it fades in.
  static const landscapeEndRise = 24.0;

  /// 首页's feed cards (BiliNative FeedMetrics, measured on 01 at 3 px per point).
  static const feedSpacing = 6.0;

  /// 633 × 475 px on 01, so 4:3, not the 16:10 the spec guessed.
  static const coverAspect = 4 / 3;
  static const cardInset = 8.0;
  static const cardTitleTop = 10.0;
  static const cardFooterInset = 9.0;
  static const cardTitleText = 14.0;
  static const cardFooterText = 12.0;
  static const cardTagText = 11.0;
  static const cardTagHeight = 16.0;
  static const cardStatText = 11.0;
  static const cardStatIcon = 13.0;
  static const coverShadeHeight = 36.0;
  static const upBadgeHeight = 12.0;
  static const upBadgeText = 8.0;
  static const cardMoreTarget = 24.0;
  static const cardMenuWidth = 168.0;
  static const cardMenuGap = 4.0;
  static const feedSpinnerRadius = 10.0;

  /// The player's panels, measured on the official app's 05, 06, 20 and 21 (956 pt wide, 62 pt safe area at the
  /// right). Fractions are of the screen: widths in landscape, heights of the portrait sheet; the cards end
  /// [panelTrailing] before the safe area.
  static const panelWidth = 0.4;
  static const panelQualityWidth = 0.3;
  static const panelMoreWidth = 0.416;
  static const panelSpeedWidth = 270 / 956;
  static const panelSheetHeight = 0.62;
  static const panelSpeedSheetHeight = 0.32;
  static const panelMoreSheetHeight = 0.8;

  /// Where the dark layer starts to fade in before the cards: a share of the screen width in landscape, points above
  /// the portrait sheet.
  static const panelFadeFraction = 0.18;
  static const panelFadeHeight = 90.0;
  static const panelTop = 16.0;
  static const panelTrailing = 16.0;

  /// Over 21's 21 pt home-indicator inset, so ⋮'s last card ends 28.3 above the bottom.
  static const panelBottom = 7.3;
  static const panelHeaderHeight = 28.0;

  /// The touch box of the small things a finger aims at (back, 高级设置, the sheet's cross); their drawings keep
  /// their own size. A page whose header has one starts [panelHeaderTop] down, so the title stays where it was.
  static const panelHitBox = 44.0;
  static const panelHeaderTop = panelTop - (panelHitBox - panelHeaderHeight) / 2;
  static const panelGap = 8.0;
  static const panelRowRadius = 8.0;
  static const panelGroupRadius = 10.0;
  static const panelCardHeight = 54.0;
  static const panelCardPadX = 16.0;
  static const panelCardPadY = 8.0;
  static const panelSubtitleGap = 1.5;

  /// 05's two-line HDR card sits its text this far above the card's middle.
  static const panelSubtitleLift = 3.2;
  static const panelTitleText = 14.0;
  static const panelDetailText = 12.0;
  static const panelSubtitleText = 10.0;
  static const panelBadgeHeight = 14.0;
  static const panelBadgePad = 4.0;
  static const panelBadgeGap = 10.0;
  static const panelInfoIcon = 16.0;
  static const panelInfoInset = 12.0;
  static const panelChevronWidth = 5.0;
  static const panelChevronHeight = 10.0;
  static const panelChevronGap = 4.7;
  static const panelChevronTrailing = 4.7;

  /// ⋮'s rows: 51 tall, the icon centred 26 in, the label 44 in and the hairline from there.
  static const panelRowHeight = 51.0;
  static const panelRowLead = 16.0;
  static const panelRowIcon = 20.0;
  static const panelRowTrailing = 15.0;
  static const panelLabelInset = 44.0;
  static const panelHairline = 1 / 3;
  static const panelSegmentDivider = 20.0;
  static const panelSegmentPad = 13.0;
  static const panelSwitchWidth = 33.0;
  static const panelSwitchHeight = 20.0;
  static const panelSwitchKnob = 17.5;
  static const panelAutoplayGlyphWidth = 12.6;
  static const panelAutoplayGlyphHeight = 14.0;
  static const panelLoopGlyphWidth = 18.0;
  static const panelLoopGlyphHeight = 16.0;
  static const panelFitGlyph = 13.0;
  static const panelMirrorGlyphWidth = 16.4;
  static const panelMirrorGlyphHeight = 14.0;

  /// ⋮'s top: the squares, their labels, then 定时关闭's title.
  static const panelActionSize = 48.0;
  static const panelActionIcon = 24.0;
  static const panelActionText = 11.0;
  static const panelActionLabel = 14.0;
  static const panelActionGap = 36.0;
  static const panelActionLead = 6.0;

  /// 小窗播放 where picture in picture isn't available.
  static const panelDisabledOpacity = 0.4;
  static const panelSectionGap = 36.0;
  static const panelSectionTitle = 20.0;
  static const panelTitleGap = 12.0;
  static const panelCardGap = 16.0;
  static const panelSpeedRow = 50.0;

  /// 倍速's strip starts 16.5 before its column, which stays centred at 06's x 790.
  static const panelSpeedLead = 16.5;
  static const panelSpeedCell = 40.0;
  static const panelWheelHeight = 150.0;
  static const panelWheelItem = 32.0;
  static const panelButtonHeight = 40.0;

  /// The dark portrait sheet's grabber, and how far (or how fast, in points a second) a drag on it must go before
  /// the sheet lets go.
  static const panelGrabberWidth = 36.0;
  static const panelGrabberHeight = 4.0;
  static const panelGrabberPad = 8.0;
  static const panelDismissDrag = 40.0;
  static const panelDismissVelocity = 700.0;

  /// How far a row slides while it fades in as the panel opens.
  static const panelRevealShift = 18.0;

  /// The light 选集 sheet in portrait (19), whose top meets the player's bottom.
  static const sheetRadius = 12.0;
  static const sheetGrabberWidth = 30.0;
  static const sheetGrabberHeight = 3.0;
  static const sheetGrabberTop = 8.0;
  static const sheetHeaderHeight = 52.0;
  static const sheetTitleText = 16.0;
  static const sheetClose = 24.0;
  static const sheetCloseGlyph = 17.0;
  static const sheetRowHeight = 52.0;

  /// 19's 合集 header and rows, measured from the sheet's top: the intro line, 选集 with 正序, then rows 100.3 apart
  /// (12 above and below a 134.7 × 76 cover, and the hairline) with their text lines placed from the cover's top.
  static const sheetLineHeight = 1.2;
  static const sheetIntroText = 12.0;
  static const sheetIntroTop = 1.8;
  static const sheetIntroTrailing = 146.0;
  static const sheetSectionText = 14.0;
  static const sheetSectionLead = 14.0;
  static const sheetSectionTop = 21.2;
  static const sheetSectionHeight = 29.0;
  static const sheetOrderTrailing = 13.0;
  static const sheetOrderGap = 6.3;
  static const sheetOrderGlyphWidth = 12.5;
  static const sheetOrderGlyphHeight = 11.0;
  static const sheetListTop = 1.0;
  static const sheetRowPad = 12.0;
  static const sheetCoverWidth = 134.7;
  static const sheetCoverHeight = 76.0;
  static const sheetCoverGap = 8.3;
  static const sheetBadgeText = 10.0;
  static const sheetBadgeHeight = 13.6;
  static const sheetBadgePad = 3.8;
  static const sheetBadgeRadius = 1.7;
  static const sheetBadgeInsetX = 3.8;
  static const sheetBadgeInsetY = 4.4;
  static const sheetEpisodeTitleText = 14.0;
  static const sheetEpisodeTitleLine = 20.0;
  static const sheetEpisodeTitleTop = -1.0;
  static const sheetPlayingGlyphWidth = 12.0;
  static const sheetPlayingLead = 1.7;
  static const sheetPlayingDrop = 1.4;
  static const sheetPlayingGlyphHeight = 14.0;
  static const sheetPlayingBar = 2.4;
  static const sheetPlayingGap = 6.5;
  static const sheetMetaText = 12.0;

  /// MiSans digits are narrower than the official PingFang's.
  static double get sheetMetaSpacing => BiliFonts.nudged ? 0.6 : 0;
  static const sheetMetaLine = 16.0;
  static const sheetDateCentre = 51.1;
  static const sheetCountsCentre = 69.7;

  /// MiSans digits sit higher in their line than PingFang's, which centre on the count glyphs.
  static double get sheetCountTextDrop => BiliFonts.nudged ? 1 : 0;
  static const sheetCountGlyphWidth = 13.4;
  static const sheetCountLead = 1.0;
  static const sheetCountGlyphHeight = 11.4;
  static const sheetCountGap = 4.0;
  static const sheetCountSpacing = 12.0;
  static const sheetFooterText = 12.0;
  static const sheetFooterTop = 21.9;
  static const sheetFooterGap = 32.6;

  /// How far a pressed card shrinks.
  static const pressedScale = 0.97;

  /// How far a new card rises while it fades in, as a share of its height.
  static const cardRise = 0.06;

  /// 首页's top row, the menus and the toast.
  static const topRowHeight = 44.0;
  static const topRowMargin = 15.0;
  static const homeAvatar = 38.0;
  static const linkFieldHeight = 34.0;

  /// The system paste control inside the link field, with a little of the field showing above and below it.
  /// The room UIPasteControl asks for at its smallest text size on iOS 27 (logged from KaiC's phone): squeezed
  /// below it, it drops its glyph and turns itself off, a pale empty square in the 34 pt field.
  static const pasteControlWidth = 38.0;
  static const pasteControlHeight = 31.0;
  static const linkFieldIcon = 17.0;
  static const linkClearIcon = 18.0;
  static const tabText = 16.0;
  static const tabIndicatorWidth = 18.0;
  static const tabIndicatorHeight = 3.0;

  /// 首页's tab row (01, 14): from the field row to 推荐's line box, from that line box to the pink bar, and from the bar
  /// to the hairline at 141.67 pt.
  static const tabRowTop = 20 / 3;
  static const tabIndicatorGap = 2 / 3;
  static const tabRowBottom = 8 / 3;
  static const menuRowHeight = 46.0;
  static const menuRadius = 12.0;
  static const menuIconBox = 24.0;
  static const menuIcon = 20.0;
  static const vipBadgeHeight = 16.0;
  static const vipBadgeText = 10.0;
  static const toastRadius = 16.0;
  static const openingPadding = 28.0;
  static const openingSpinner = 32.0;
  static const recentsTile = 40.0;
  static const recentsTileRadius = 10.0;
  static const recentsTileIcon = 26.0;

  /// 设置 and its pages (50): a row with the hairline under it is 130 or 131 px, kept at 130 so every hairline lands on a
  /// whole pixel; the grey between sections is 41 px and the grey values 14 pt. [SettingsTheme] has the rest.
  static const settingsRowHeight = 43 + 1 / 3;
  static const settingsSectionGap = 41 / 3;
  static const settingsValueText = 14.0;
  static const settingsValueWidth = 240.0;
  static const fontRowPadding = 12.0;
  static const fontSampleGap = 4.0;
  static const fontCheck = 20.0;

  /// 竖屏 full screen centres a landscape video at this fraction of the screen's height (screen 09).
  static const verticalVideoCentre = 0.415;

  /// The menus' frosted glass.
  static const glassBlur = 24.0;
  static const glassHairline = 0.5;
  static const glassShadowBlur = 24.0;
  static const glassShadowDrop = 8.0;

  /// Danmaku text at an elem's normal fontSize of 25, which other sizes scale. 44's full screen is 22 pt, as in Swift;
  /// the small player's, read off 10 (CJK advances of 37–38 px), is 12.5 pt where Swift had 17: the official app
  /// sizes them about by the player's height (22 × 247.5 / 440).
  static const danmakuFont = 12.5;
  static const danmakuFontFullScreen = 22.0;
  static const danmakuOutline = 1.0;
  static const danmakuPad = 1.0;
  static const danmakuOwnPadX = 5.0;
  static const danmakuOwnPadY = 1.5;
  static const danmakuOwnRadius = 3.0;

  /// Lane spacing per point of the font size: 44's lanes are about 95 px apart at 22 pt, as Swift's 1.2 line
  /// heights of the system font are.
  static const danmakuLaneHeight = 1.44;
}

/// The tab row under the player (简介 / 评论 N, the 弹 toggle and 点我发弹幕) and the 简介 page's spacing (03, 18).
abstract final class PageTheme {
  /// 40 pt from the player's bottom to the hairline's, which the underline covers.
  static const tabRowHeight = 40.0;
  static const hairline = 0.5;
  static const tabText = Color(0xFF61666D);

  /// 简介 and 评论 in 61666D or pink, 评论's count smaller on their baseline (03, 10, 18). The official app's
  /// glyphs are 35 px tall to the system font's 37 at 13.5 (font-check 02).
  static double get tabLabelText => BiliFonts.nudged ? 13.5 : 12.75;
  static const tabCountText = 10.5;
  static const tabCountGap = 3.5;

  /// Off the shared baseline the count sat ⅔ pt low; on 10 its middle is level with 评论's.
  static const tabCountRise = 2 / 3;

  /// Where 简介's label starts, and the room between the labels; each tab's touch area takes half that room.
  static const tabFirstLabel = 33.2;
  static const tabSpacing = 48.6;

  /// The underline: as wide as the tab's label and count, flush with the row's bottom.
  static const underlineHeight = 2.0;
  static const underlineRadius = 1.0;

  /// 点我发弹幕 joined to the 弹 toggle (18), or the toggle alone in a 44 pt capsule (03), 12 pt from the edge.
  static const capsuleHeight = 30.0;
  static const capsuleBorder = 0.7;
  static const danmakuFieldWidth = 97.0;
  static double get danmakuFieldText => BiliFonts.nudged ? 13.5 : 12.75;
  static const danmakuToggleOn = 40.0;
  static const danmakuToggleOff = 44.0;

  /// The 弹 glyph sits 22 pt from the capsule's right end, on or off.
  static const danmakuMarkBox = 44.0;
  static const danmakuMark = 23.0;

  /// The on glyph's tick, in the official pink: everything right of half the glyph and below 58.8% of it.
  static const danmakuTickLeft = 0.5;
  static const danmakuTickTop = 0.588;

  /// Below the related list, above the home indicator.
  static const introBottom = 12.0;

  /// How far the 简介 column rises while it fades in for a new video.
  static const introRise = 8.0;
}

/// The uploader row and the title block, measured on the official app's 03, 18 and 26 at 3 px per point. Each part
/// owns the gap above it and its gutters.
abstract final class IntroTheme {
  /// The avatar starts this far below the tab row's hairline.
  static const uploaderTop = 12.0;
  static const avatar = 30.0;
  static const avatarGap = 12.0;

  /// 大会员 names are [BiliColors.pink]; everyone else's is this grey, lighter than the title (18).
  static const name = Color(0xFF484C52);
  static const nameText = 13.0;
  static const fansText = 10.0;

  /// The extra room PingFang leaves where the counts' digits meet 粉丝 and 视频 (03).
  static const fansHanGap = 1.8;

  /// Where the name's and the counts' lines centre, down from the avatar's top.
  static const nameCentre = 7.8;
  static const fansCentre = 24.8;
  static const nameLine = 16.0;
  static const fansLine = 13.0;

  /// 03's bolt disc sits flush with the avatar's lower right inside a ring of the page's white.
  static const badge = 10.0;
  static const badgeRing = 1.0;
  static const badgePerson = Color(0xFFFFCC00);
  static const badgeOrganisation = Color(0xFF3EA2F4);
  static const badgeBolt = Color(0xFFFFFFFF);

  static const followWidth = 72.0;
  static const followHeight = 24.0;
  static const followText = 13.0;
  static const followPlus = 9.0;
  static const followPlusStroke = 1.2;
  static const followPlusGap = 4.0;
  static const followedFill = BiliColors.pageGrey;
  static const followedText = BiliColors.secondaryText;
  static const followPressedScale = 0.94;

  /// 联合投稿: each member's avatar with the name and the role under it, in a row that scrolls sideways.
  static const staffAvatar = 30.0;
  static const staffWidth = 60.0;
  static const staffSpacing = 16.0;
  static const staffNameText = 11.0;
  static const staffRoleText = 10.0;
  static const staffNameTop = 3.0;
  static const staffLine = 14.0;
  static const staffRoleLine = 13.0;

  /// The title row starts this far below the avatar; its first line centres in [titleRow].
  static const titleTop = 18.0;
  static const titleRow = 22.0;

  /// Under the system font 15.25: the official title's glyphs are 43 px tall to our 45 at 16 (font-check 02).
  static double get titleText => BiliFonts.nudged ? 16 : 15.25;
  static const titleLine = 22.0;
  static const honorText = 12.0;
  static const honorPadding = 8.0;
  static const honorGap = 4.0;
  static const chevronWidth = 12.0;
  static const chevronHeight = 6.0;
  static const chevronStroke = 1.0;
  static const chevronGap = 8.0;

  /// The ⌄'s centre sits this far in from the right edge.
  static const chevronTrailing = 14.0 + chevronWidth / 2;

  /// 03's meta line centres 24.8 below the title row's centre.
  static const metaGap = 5.8;

  /// 03's ▶ starts this far in from the gutter.
  static const metaLead = 1.3;
  static const metaLine = 16.0;
  static const metaText = 12.0;
  static const metaIconGap = 3.8;
  static const metaGroupGap = 8.0;
  static const metaIconWidth = 13.3;
  static const metaIconHeight = 11.3;
  static const onlineIconHeight = 11.7;
  static const metaStroke = 1.0;

  /// Expanded (18): the BV line 18 below the meta line, the description's first line 19.2 below that, 17 between
  /// its lines, and the tags 20.3 below the last line's centre.
  static const bvGap = 2.0;
  static const forbiddenIcon = 12.0;
  static const forbiddenGap = 9.0;
  static const forbiddenTextGap = 4.5;
  static const forbidden = Color(0xFFF85A54);
  static const descGap = 2.7;
  static const descText = 12.0;
  static const descLine = 17.0;
  static const tagsGap = 11.8;
  static const tagHeight = 26.0;
  static const tagText = 12.0;
  static const tagPadding = 13.0;
  static const tagSpacing = 8.0;
  static const tagInk = Color(0xFF61666D);

  /// 18 sets the action icons 30 below the plain tags, more than the action row's own top gap leaves; the tags keep
  /// the rest under them.
  static const tagsBottom = 23 / 3;

  static const expandDuration = Duration(milliseconds: 280);

  /// MiSans's Chinese is about 2% wider than the official PingFang, which in turn spaces digits and Latin letters
  /// away from Chinese; these bring each line to the official width, so the description wraps where 18's does. The
  /// title's two differences cancel out.
  static double get nameSpacing => BiliFonts.nudged ? -0.4 : 0;
  static double get fansSpacing => BiliFonts.nudged ? 0.2 : 0;
  static double get metaSpacing => BiliFonts.nudged ? 0.3 : 0;
  static double get proseSpacing => BiliFonts.nudged ? -0.2 : 0;

  /// MiSans sets the counts half a point higher in their line than PingFang.
  static double get fansDrop => BiliFonts.nudged ? 0.5 : 0;

  /// 个人观点，仅供参考 (font-check 02 and 03): a 16 pt line 2 under the meta line, its ⓘ (a ring 13.33 across) where the
  /// meta line's ▶ is and the text 3.2 after it. Collapsed, the actions sit only 16 lower for it, so the line's last
  /// [noticeHang] hangs below the block; expanded, the BV line keeps its usual gap under the line.
  static const noticeGap = 2.0;
  static const noticeLine = 16.0;
  static const noticeHang = 2.0;
  static const noticeText = 12.0;
  static const noticeIcon = 40 / 3;
  static const noticeIconGap = 3.2;

  /// 03 and font-check 02 draw the action row's coin 7/6 lower than the thumbs, star and arrow beside it; its 三连
  /// ring follows it.
  static const actionCoinDrop = 7 / 6;

  /// iOS sets a tab on its default stops, 28 pt apart, so a description paragraph that opens with one is indented by
  /// 28 (font-check 03).
  static const descTabStop = 28.0;
}

/// 合集, the part strip, the topic and BGM chips and the related rows (03, 18).
abstract final class IntroListTheme {
  /// 03 and 18 put the 合集 card, the chips and the related list's first hairline 18 apart, so each section owns
  /// [sectionTop] above it and [sectionBottom] below.
  static const sectionTop = 46 / 3;
  static const sectionBottom = 8 / 3;

  /// The action row ends this far below its count line, which puts the first section's top 45.17 under the icons'
  /// centre, as on 03 and font-check 02 (18 under 不喜欢's ink).
  static const actionsBottom = 0.5;

  /// 合集 (03): a 36 pt card inside the gutters, its title 12 in, then the playing bars, the place and the ›, which
  /// ends 15.7 before the card's edge.
  static const collectionHeight = 36.0;
  static const collectionLead = 12.0;
  static const collectionTrailing = 47 / 3;
  static const collectionTitleText = 14.0;

  /// The official digits are taller and narrower than MiSans's; 13 matches their width.
  static const collectionPlaceText = 13.0;
  static const collectionBarsGap = 7.0;
  static const collectionChevronGap = 6.5;
  static const collectionChevronWidth = 20 / 3;
  static const collectionChevronHeight = 12.0;
  static const chevronStroke = 1.3;

  /// Three round-ended bars 1.72 wide and 4.2 apart, centred on the line: tall, short, tall, as font-check 02 draws
  /// them (11.75, 5.67 and 11). The official mark moves; 03 caught it tall, short, short.
  static const barWidth = 31 / 18;
  static const barStep = 4.2;
  static const barsWidth = barWidth + 2 * barStep;
  static const barsHeight = 11.75;
  static const barShares = <double>[1, 17 / 35.25, 33 / 35.25];

  /// The part strip (no screenshot; the official app's style): 选集 N/M › over 140 × 52 chips with two lines.
  static const partHeaderHeight = 36.0;
  static const partChipWidth = 140.0;
  static const partChipHeight = 52.0;
  static const partChipPad = 10.0;
  static const partChipGap = 8.0;
  static const partChipText = 13.0;
  static const partChipLine = 17.0;
  static const partChipBorder = 1.0;
  static const partPlayingGap = 5.0;

  /// The topic and BGM capsules (03, 18): 26 tall, 8 apart. One takes up to half the row (208 on 18); three share it,
  /// so 03's long two are 133.3 wide, as three long ones would fill it.
  static const chipHeight = 26.0;
  static const chipLead = 10.0;
  static const chipTrailing = 32 / 3;
  static const chipGap = 8.0;
  static const chipText = 12.0;
  static const chipIconGap = 5.5;
  static const chipChevronGap = 4.5;
  static const chipFade = 12.0;
  static const chipChevronWidth = 16 / 3;
  static const chipChevronHeight = 28 / 3;
  static const chipChevronStroke = 1.2;
  static const musicGlyphWidth = 12.1;
  static const musicGlyphHeight = 12.8;
  static const topicGlyphWidth = 13.2;
  static const topicGlyphHeight = 12.9;
  static const topicGlyphStroke = 1.1;

  /// Points a second the name scrolls, the rest before it starts, and the gap before it comes round again.
  static const marqueeSpeed = 30.0;
  static const marqueeRest = Duration(milliseconds: 1500);
  static const marqueeGap = 24.0;

  static const chipTextColor = Color(0xFF61666D);
  static const chipGlyphColor = Color(0xFF656668);

  /// A related row (03, 18): 92 apart, a 128 × 72 cover 10.33 below the hairline, the text 8 right of it.
  static const relatedRowHeight = 92.0;
  static const relatedCoverTop = 31 / 3;
  static const relatedCoverWidth = 128.0;
  static const relatedCoverHeight = 72.0;
  static const relatedCoverRadius = 4.0;
  static const relatedTextGap = 8.0;
  static const relatedTitleText = 14.0;
  static const relatedTitleLine = 17.0;

  /// The title's line box starts this far above the cover's top, which puts its ink 1 pt below it.
  static const relatedTitleLift = 1.0;

  /// The UP line's and the counts' centres, below the cover's top.
  static const relatedUploaderCentre = 46.5;
  static const relatedCountsCentre = 191 / 3;
  static const relatedMetaText = 12.0;
  static const relatedMetaLine = 16.0;
  static const relatedMetaGap = 3.5;

  /// The UP badge and the count icons start 2.33 right of the title.
  static const relatedMetaLead = 7 / 3;
  static const relatedCountSpacing = 12.0;

  /// Between rows the hairline starts 10 in; the first runs the full width.
  static const relatedDividerInset = 10.0;

  /// The duration's dark tag, 4 in from the cover's corner.
  static const durationHeight = 16.0;
  static const durationPad = 4.0;
  static const durationRadius = 1.8;
  static const durationInset = 4.0;
  static const durationText = 10.5;
  static const durationFill = Color(0x8C000000);

  /// ⋮: three 2.67 dots 1.33 apart, their column centred 20 from the right edge on the counts' line.
  static const moreDot = 8 / 3;
  static const moreDotGap = 4 / 3;
  static const moreCentreFromRight = 20.0;
  static const moreTarget = 36.0;

  /// The rows that are there when the list arrives come in one after another.
  static const revealStagger = Duration(milliseconds: 35);
  static const revealDuration = Duration(milliseconds: 320);
  static const revealRows = 8;
  static const revealRise = 8.0;
}

/// The action row under the title, the 三连 rings and the coin dialog (03, 15).
abstract final class ActionTheme {
  /// The solid glyphs' cut-out lines (投币's 币): 4.5 px on font-check 02, as landscape's outlines.
  static const cutStroke = 1.5;

  /// 03's icons are #61666D and their counts the page's grey; on, both turn [BiliColors.pink].
  static const icon = Color(0xFF61666D);
  static const count = BiliColors.secondaryText;
  static const unavailableOpacity = 0.4;

  /// From 03 (px / 3): the icons' ink starts 23.7 pt under the meta line's and spans 20 pt (a 24 pt icon), the counts'
  /// digits are centred 22.7 pt under the icons'. [rowHeight] ends at the bottom of the count line; 简介 adds
  /// [IntroListTheme.actionsBottom] under it.
  static const topGap = 19.0;
  static const iconSize = 24.0;
  static const countGap = 10 / 3;
  static const countLine = 14.0;

  /// The official app's 10 pt; MiSans draws its digits taller, so they come out about half a point over 03's.
  static const countFont = 10.0;
  static const rowHeight = topGap + iconSize + countGap + countLine;
  static const popScale = 1.24;

  /// The 三连 ring round 点赞, 投币 and 收藏, clear of the counts, and the burst of eight dots when it fires.
  static const ring = 32.0;
  static const ringWidth = 2.0;
  static const burstDot = 4.0;
  static const burstSpread = 1.6;

  /// The coin dialog (15): white over the page dimmed to 40%, the hint and the ✕ at 60% and 50%.
  static const coinDim = Color(0x99000000);
  static const coinText = Color(0xFFFFFFFF);
  static const coinHint = Color(0x99FFFFFF);
  static const coinClose = Color(0x80FFFFFF);
  static const coinUnaffordable = Color(0x66000000);

  /// The crate art has a shadow round it: drawn 84 and 100 pt, its boxes show 72 and 86 pt, 114 pt apart and centred
  /// at 49.8% of the height. The coin art is 56% of the crate art and sits a little low. The arrows' centres are 22 pt
  /// in from the edges.
  static const crate = 84.0;
  static const selectedCrate = 100.0;
  static const crateSpacing = 114.0;
  static const coinArt = 0.56;
  static const coinArtDrop = 0.017;
  static const cratesCentre = 0.498;
  static const arrowWidth = 15.6;
  static const arrowHeight = 30.0;
  static const arrowCentreInset = 22.0;

  /// 22娘's art is 150 pt tall, 34 pt under the crate art; the two lines under her are 18 pt apart, the first centred
  /// 17 pt under her art.
  static const mascotGap = 34.0;
  static const mascotHeight = 150.0;
  static const mascotAspect = 321 / 447;
  static const hintGap = 8.0;
  static const hintLine = 18.0;
  static const hintFont = 13.0;

  /// The bottom row is centred 30 pt above the safe area: ☐ 同时点赞内容 17 pt in, ✕ 30 pt, 如何获取硬币？ 13 pt in.
  static const bottomLift = 30.0;
  static const bottomRow = 44.0;
  static const bottomInset = 17.0;
  static const bottomEndInset = 13.0;
  static const bottomFont = 12.0;
  static const checkbox = 14.0;
  static const checkboxLine = 1.0;
  static const checkboxTick = 1.4;
  static const checkboxRadius = 2.0;
  static const checkboxGap = 5.0;
  static const close = 30.0;
  static const closeRing = 1.0;
  static const closeCross = 1.3;
  static const closeCrossHalf = 4.3;

  /// Landscape lays the portrait column out 440 pt wide, scaled down to fit the height.
  static const landscapeColumn = 440.0;

  /// The lightning frames are 1080 px wide round a 225 px crate; the first one's crate is 27.5 px below its centre.
  static const thunderWidth = 1080 / 225;
  static const thunderFirstDrop = 27.5 / 225;
}

/// The favourites sheet and panel, and the unfollow confirm.
abstract final class FavouriteTheme {
  /// Over the whole page, player included (BiliNative `Theme.Favourites.dim`).
  static const dim = Color(0x66000000);
  static const rowHeight = 56.0;
  static const newRowHeight = 48.0;
  static const titleText = 15.0;
  static const countText = 12.0;
  static const countGap = 3.0;
  static const lockIcon = 12.0;
  static const plusIcon = 18.0;
  static const plusGap = 6.0;

  /// The tick circle: an empty ring, or pink with a white tick drawn in.
  static const check = 21.0;
  static const checkStroke = 1.2;
  static const tickStroke = 1.8;
  static const ringLight = Color(0xFFC9CCCF);
  static const ringDark = Color(0x66FFFFFF);
  static const tick = Color(0xFFFFFFFF);
  static const doneHeight = 40.0;
  static const doneText = 15.0;
  static const doneTop = 12.0;

  /// 新建收藏夹's form; Bilibili refuses names longer than [maxTitle].
  static const maxTitle = 20;
  static const fieldHeight = 38.0;
  static const fieldPad = 12.0;
  static const formGap = 10.0;
  static const formButtonHeight = 32.0;
  static const formButtonPad = 10.0;
  static const formSpinnerRadius = 7.0;
  static const darkField = Color(0x1AFFFFFF);
  static const switchOffLight = Color(0xFFE3E5E7);
  static const knobShadow = Color(0x33000000);
  static const knobShadowBlur = 2.0;

  /// Loading and failure inside the list, and 重试.
  static const statePad = 32.0;
  static const stateText = 13.0;
  static const spinnerRadius = 10.0;
  static const retryHeight = 30.0;
  static const retryPad = 18.0;
  static const retryBorder = 0.8;

  /// The unfollow confirm, an iOS-sized alert in the official app's light style.
  static const alertWidth = 280.0;
  static const alertRadius = 12.0;
  static const alertTitleText = 16.0;
  static const alertTitlePadTop = 26.0;
  static const alertTitlePadBottom = 22.0;
  static const alertButtonHeight = 48.0;
  static const alertButtonText = 16.0;
  static const alertDim = Color(0x80000000);

  /// The alert settles from this, slightly large, to its size as it fades in.
  static const alertStartScale = 1.08;
}

/// Landscape's top actions, uploader and 关注 (04, 05), the bgm row, ⏭ and 选集 on the bottom row (05), and its end
/// screen's actions (27), measured at 3 px per pt.
abstract final class LandscapeActionTheme {
  /// The glyphs' ink is 20 pt on both screens, 0.84 of the icon's box.
  static const iconSize = 24.0;

  /// After each 44 pt button, the last one's before ⋮.
  static const buttonGap = 8.0;

  /// 04 and 05 draw the outlines and the 币 4.5 px (1.5 pt) wide, as 简介 cuts its 币 ([ActionTheme.cutStroke]).
  static const outline = 1.5;

  /// 05's 👍, 💬 and ⭐ are shorter than the outlines 简介 shares (19.7, 19.4 and 18.7 pt of ink against 20.2, 19.9
  /// and 19.7), their widths the same, and 👍 and ⭐ sit higher: each is squeezed upright about its button's centre,
  /// then lifted.
  static const likeSquash = 0.975;
  static const likeLift = 1.14;
  static const commentSquash = 0.973;
  static const favouriteSquash = 0.945;
  static const favouriteLift = 0.8;

  /// The title starts where N人正在看's icon under it does (04, 05), clear of back's 44 pt target.
  static const titleInset = onlineInset;

  /// The superscript count: its left edge this far right of its button's centre, its digits standing on a baseline
  /// 12 pt into the button (32 pt down on 04 and 05, in either font), in proportional figures as 05's 1127 is.
  static const countText = 9.5;
  static const countLead = 6.7;
  static const countBaseline = 12.0;

  /// N人正在看 under the title, centred 64.8 pt down: the icon 4.7 pt right of the back button.
  static const onlineTop = 56.8;
  static const onlineHeight = 16.0;
  static const onlineInset = 4.7;
  static const onlineIconWidth = 13.0;
  static const onlineIconHeight = 11.0;
  static const onlineIconStroke = 0.85;
  static const onlineGap = 5.5;
  static const onlineText = 12.0;
  static const online = Color(0x99FFFFFF);

  /// 25's faint N人正在看 at the bottom left while the controls are hidden (27 keeps it under the end screen's dim):
  /// the glyph 33.3 pt past the left inset, the line centred 9.7 pt above the screen's edge, inside the home
  /// indicator's band rather than above it.
  static const cornerInset = 33.3;
  static const cornerCentre = 9.7;
  static const cornerHeight = 12.0;
  static const cornerIconWidth = 9.0;
  static const cornerIconHeight = 7.6;
  static const cornerIconStroke = 0.7;
  static const cornerGap = 4.9;
  static const cornerText = 9.0;
  static const corner = Color(0x59FFFFFF);

  /// Under the end screen's dim 27 shows the corner at about 22% white where the dim alone leaves 38%.
  static const cornerUnderEndOpacity = 0.58;

  /// The uploader's avatar and + 关注 on the line below, centred 93 pt down.
  static const uploaderHeight = 40.4;
  static const avatar = 24.0;
  static const avatarInset = 12.0;
  static const avatarGap = 7.7;
  static const plus = 10.7;
  static const plusStroke = 0.8;
  static const plusGap = 4.7;
  static const followText = 12.5;
  static const followed = Color(0x99FFFFFF);

  /// 05's uploader chip: a 15% black capsule 26 pt tall on the uploader's line, its left end 1 pt outside the avatar,
  /// holding the avatar, the name 8 pt on (12.5 pt, as 关注), a 0.67 × 12 pt half-white divider 8.6 pt either side,
  /// then + 关注, which ends 16 pt before the capsule does (05 and 34 alike). Text stands on a baseline 4.67 pt below
  /// the capsule's centre, which 'der' and 'Takes' share.
  static const chipHeight = 26.0;
  static const chipFill = Color(0x26000000);
  static const chipInset = 1.0;
  static const chipBaselineDrop = 4.67;
  static const nameGap = 8.0;
  static const dividerGap = 8.6;
  static const dividerWidth = 0.67;
  static const dividerHeight = 12.0;
  static const divider = Color(0x80FFFFFF);
  static const followTrailing = 16.0;

  /// 05's bgm row, 发现《…》 in its own chip 8 pt under the uploader's (centred 127 pt down): two beamed quavers 6.67
  /// pt in, the name 8.75 pt after them and the chip's end 9 pt after the name. Its left end is over the black bar
  /// beside the video on 05, so it is taken to line up with the uploader's chip.
  static const chipGap = 8.0;
  static const musicLead = 6.67;
  static const musicGlyphWidth = 13.67;
  static const musicGlyphHeight = 14.33;
  static const musicGap = 8.75;
  static const musicTrailing = 9.0;

  /// 05's ⏭: a rounded triangle against a bar in a 16.9 × 16.67 box, centred 1 pt right of its 44 pt button, which
  /// follows ▶ with the 6 pt the 弹 toggle keeps, the toggle 6 pt after it in turn. 34 greys it to half white when
  /// nothing plays next.
  static const nextWidth = 16.9;
  static const nextHeight = 16.67;
  static const nextShift = 1.0;
  static const nextTip = 14.67;
  static const nextBar = 4.2;
  static const nextCorner = 1.5;
  static const nextOffOpacity = 0.5;

  /// 选集 before 倍速 (05, 34): their labels' centres 62 pt apart, so 17.67 pt between their buttons.
  static const episodesGap = 17.67;

  /// 27's 充电 and 关注 pills under the uploader's name, level with the avatar's bottom.
  static const pillWidth = 88.0;
  static const pillHeight = 30.0;
  static const pillGap = 8.0;
  static const pillBorder = 1.0;
  static const pillText = 14.0;
  static const boltWidth = 7.2;
  static const boltHeight = 11.6;
  static const boltGap = 7.6;

  /// Padding before the bolt and 充电, which 27 sets half this right of its pill's centre.
  static const chargeShift = 4.0;
  static const pillPlus = 9.0;
  static const pillPlusStroke = 1.2;
  static const pillPlusGap = 5.0;

  /// 已关注's pill, as BiliNative's end screen draws it.
  static const followedPill = Color(0x38FFFFFF);

  /// How far an action's icon swells as it turns on.
  static const pop = 1.28;
}

/// The status bar landscape full screen draws while iOS's is hidden (04, 05, 34), from the screen's top edge. Text is
/// placed by its baseline, where digits and capitals stand in any font.
abstract final class LandscapeStatusTheme {
  /// The clock: 12 pt regular, centred on the screen, on a baseline 14.33 pt down.
  static const timeText = 12.0;
  static const timeBaseline = 14.33;

  /// WIFI and the percentage: 10 pt regular on a baseline 13.67 pt down.
  static const smallText = 10.0;
  static const smallBaseline = 13.67;

  /// Everything on the right is centred 10 pt down; the battery's cap ends 11 pt inside the right safe inset.
  static const centre = 10.0;
  static const trailing = 11.0;

  /// WIFI's 33 × 14 capsule, outlined 1 pt in 30% white, 8 pt before the percentage.
  static const capsuleWidth = 33.0;
  static const capsuleHeight = 14.0;
  static const capsuleStroke = 1.0;
  static const capsuleOutline = Color(0x4DFFFFFF);
  static const capsuleGap = 8.0;

  /// The percentage ends this far before the battery.
  static const batteryGap = 3.75;

  /// The battery: a 19 × 10 body outlined 0.45 pt in white with 2 pt corners, and a 1 × 4 cap. The level fills it
  /// 1.5 pt inside the outline, 16 pt when full, with 1 pt corners: white (04), or 05's green under a white bolt
  /// while charging.
  static const batteryWidth = 19.0;
  static const batteryHeight = 10.0;
  static const batteryStroke = 0.45;
  static const batteryCorner = 2.0;
  static const capWidth = 1.0;
  static const capHeight = 4.0;
  static const fillInset = 1.5;
  static const fillCorner = 1.0;
  static const charging = Color(0xFF9EDEA2);
}

/// 竖屏's action column, uploader, 粉丝, 关注 and 发弹幕 (09), and the 选集 sheet's share circle and 收藏 (19).
abstract final class VerticalActionTheme {
  /// 发弹幕, 已关闭弹幕 (35) or UP主已关闭弹幕 in the bottom row's dark field (09).
  static const fieldInset = 14.6;
  static const fieldText = 12.0;
  static const fieldInk = Color(0xFF939393);
  static double get fieldDrop => BiliFonts.nudged ? 1.8 : 0;

  /// 09's column: 44 wide, centred 27 in from the right edge, items 69 apart with the icon centre 27.5 above its
  /// count's; the last count's line ends 62.5 above the bottom row's bottom, about where the bar's touch starts.
  static const columnWidth = 44.0;
  static const columnTrailing = 5.0;
  static const columnLift = 62.5;
  static const itemSpacing = 17.5;
  static const iconBox = 32.0;
  static const countGap = 3.5;
  static const countLine = 16.0;
  static const countText = 13.0;

  /// [ActionIcon] sizes that draw 09's glyphs at their measured size (30, 30, 32, 29.3 and 30 × 24.3).
  static const likeIcon = 36.0;
  static const commentIcon = 35.0;
  static const coinIcon = 38.0;
  static const favouriteIcon = 32.0;
  static const shareIcon = 34.0;

  /// The icons are a 90% white; the counts full white.
  static const icon = Color(0xE6FFFFFF);
  static const count = Color(0xFFFFFFFF);

  /// How far a glyph swells as it turns pink.
  static const popScale = 1.3;

  /// The name's and 粉丝's lines beside the 36 pt avatar, centred 10.5 and 28.5 below its top.
  static const nameLine = 21.0;
  static const fansLine = 15.0;
  static const fansText = 11.5;
  static const fans = Color(0xE6FFFFFF);

  /// MiSans sits higher in its line than the official app's PingFang; these bring the name and 粉丝 level with 09's.
  static double get nameDrop => BiliFonts.nudged ? 1.7 : 0;
  static double get fansDrop => BiliFonts.nudged ? 1 : 0;

  /// + 关注: 60 × 24 on 09, 8.7 after the name.
  static const followGap = 8.7;
  static const followHeight = 24.0;
  static const followLead = 11.5;
  static const followTrailing = 10.0;
  static const followText = 13.0;
  static double get followTextDrop => BiliFonts.nudged ? 1 : 0;
  static const followPlus = 9.0;
  static const followPlusStroke = 1.3;
  static const followPlusGap = 5.0;
  static const followingFill = Color(0x33FFFFFF);
  static const followingText = Color(0xB3FFFFFF);

  /// The viewers mark and 479人正在看 after the back arrow, a 40% white.
  static const online = Color(0x66FFFFFF);
  static const onlineLead = 8.3;
  static const onlineIconWidth = 11.3;
  static const onlineIconHeight = 10.0;
  static const onlineIconStroke = 1.1;
  static const onlineGap = 5.6;
  static const onlineText = 12.0;

  /// 19's share circle and 收藏 at the right of the 合集 description, centred 5 above its first line: a 24 pt grey
  /// circle, 12 before a 71 × 24 pill, 12 from the edge. The list starts [sheetLift] into the header's empty bottom,
  /// so the two clear its clip, which cuts their tops on 19.
  static const sheetLift = 8.0;
  static const sheetShare = 24.0;
  static const sheetShareGlyph = 15.0;
  static const sheetGap = 12.0;
  static const sheetPillHeight = 24.0;
  static const sheetPillPad = 15.0;
  static const sheetStar = 13.0;
  static const sheetStarGap = 2.5;
  static const sheetPillText = 13.0;

  /// MiSans sits higher in its line than PingFang; this centres 收藏 in its pill as on 19.
  static double get sheetPillTextDrop => BiliFonts.nudged ? 1.5 : 0;
  static const sheetPill = Color(0xFFED7098);
  static const sheetPillLabel = Color(0xFFFFFFFF);
  static const sheetSubscribedFill = BiliColors.pageGrey;
  static const sheetSubscribedLabel = BiliColors.secondaryText;

  /// The playing episode's title and bars in the light 选集 sheet: 19 draws them in 收藏's pink, not the app's.
  static const sheetPlaying = sheetPill;
}

/// A comment row and its badges (10, 12, 13), measured at 3× on KaiC's phone. Heights count down from the row's top,
/// which is the hairline above it.
abstract final class CommentRowTheme {
  static const gutter = BiliMetrics.gutter;

  /// The name and the text start here; the avatar sits in the gutter before it.
  static const textLeading = 56.0;
  static const avatarTop = 62 / 3;
  static const avatar = 30.0;

  /// Under a pendant the face shrinks to 24 and the frame is 1.75 times that, centred on the same point.
  static const pendantAvatar = 24.0;
  static const pendantScale = 1.75;

  /// 大会员's pink 大: 10 across, 5/3 in from the avatar's right and 2 up from its bottom, in a ring of white.
  static const vipMark = 10.0;
  static const vipMarkRing = 1.0;
  static const vipMarkRight = 5 / 3;
  static const vipMarkBottom = 2.0;
  static const vipMarkText = 7.0;
  static const vipMarkFill = BiliColors.pink;
  static const vipMarkInk = Color(0xFFFFFFFF);
  static const vipMarkRim = Color(0xFFFFFFFF);

  /// The name and the LV badge centre 28.8-30 down on 10 and 13, lower in the first row under a header than in the
  /// rows after it; 29.5 is within 0.7 of each.
  static const nameCentre = 29.5;

  /// Short enough to end above the text's line at [textTop].
  static const nameLine = 16.0;
  static const nameText = 13.0;
  static const name = BiliColors.secondaryText;
  static const vipName = Color(0xFFFB7299);
  static const badgeGap = 5.0;
  static const upGap = 4.0;

  /// LV0 to LV6, 56 × 28 px: the LV block 1 pt shorter than the digit's. LV5 and LV6 are the fills' mode on 10 and
  /// 13, the rest follow Bilibili's level colours.
  static const levelWidth = 56 / 3;
  static const levelHeight = 28 / 3;
  static const levels = [
    Color(0xFFC0C4CC),
    Color(0xFFC0C4CC),
    Color(0xFF8BD29B),
    Color(0xFF7BCDEF),
    Color(0xFFFEBB8B),
    Color(0xFFDF6729),
    Color(0xFFE3524E),
  ];
  static const levelInk = Color(0xFFFFFFFF);
  static const upFill = BiliColors.pink;
  static const upInk = Color(0xFFFFFFFF);
  static const upText = 8.0;
  static const upPadding = 3.0;
  static const upRadius = 2.0;

  /// 置顶 before a pinned comment's text.
  static const pinnedText = 11.0;
  static const pinnedInk = BiliColors.pink;
  static const pinnedBorder = 0.8;
  static const pinnedRadius = 3.0;
  static const pinnedPadding = 4.0;

  /// The text's first line is centred 50.2 down. 12 sets lines 24.3 apart, but Flutter rounds a line's height to
  /// whole points, so ours are 24, which leaves 13's three-line reply within a point of its meta line. A single
  /// line still leaves the pictures or the meta line [textMinBottom] down, as 13's 没人看的 does; longer text pushes
  /// them on without a gap.
  static const textFirstCentre = 50.2;
  static const textLine = 24.0;
  static const textText = 15.0;
  static const textMinBottom = 200 / 3;
  static const text = BiliColors.text;

  /// Under the system font PingFang's glyphs sit higher in their line than MiSans's, so the text starts 1.8 lower:
  /// the official app centres it 22 below the name in the list (differences 12) and 21.1-21.3 in a thread
  /// (font-check 04), where ours sat 20.2; 1.4 lower lands within half a point of both.
  static double get textTop => textFirstCentre - textLine / 2 + (BiliFonts.nudged ? 0 : 1.4);

  /// One picture: a tall one 162 wide, cut at 3:4, a wide one 240; 135 and 200 in 评论详情 (13). Long pictures show
  /// their top.
  static const pictureTall = 162.0;
  static const pictureWide = 240.0;
  static const threadPictureTall = 135.0;
  static const threadPictureWide = 200.0;
  static const tallestRatio = 4 / 3;
  static const flattestRatio = 9 / 16;
  static const pictureRadius = 4.0;
  static const pictureSpacing = 4.0;
  static const picturePlaceholder = BiliColors.pageGrey;

  /// The meta line centres 16 below a picture's bottom: ⋮'s middle dot does on font-check 04, 10 and 13.
  static const pictureGap = 4.0;

  /// The meta line: time and place, 回复 8 after them, 👍 N with the count's box ending 73 from the right edge (its ink
  /// 73.7, as on 10), 👎 centred 49 from it and ⋮ 17.
  static const metaHeight = 24.0;
  static const metaText = 12.0;
  static const meta = Color(0xFFC9CCD0);
  static const action = Color(0xFF61666D);
  static const liked = BiliColors.pink;
  static const replyGap = 8.0;
  static const replyTrailing = 10.0;
  static const likeTrailing = 73.0;
  static const thumbInk = 14.0;

  /// 👍 is drawn above the line's centre: its ink centres 2 px above ⋮'s middle dot and the count on font-check 04,
  /// 10 and 13 (15.2 below a picture's bottom).
  static const thumbLift = 2 / 3;

  /// 👎 sits 4 px lower than 👍.
  static const dislikeDrop = 4 / 3;
  static const thumbCountGap = 17 / 3;

  /// The widest count, 999.9万.
  static const countRoom = 48.0;
  static const dislikeCentre = 49.0;
  static const moreCentre = 17.0;

  /// ⋮'s dots are 6.4 px across (each one's ink area on font-check 04 and 13) and 13 px apart.
  static const moreDot = 6.4 / 3;
  static const morePitch = 13 / 3;
  static const likeTarget = 6.0;
  static const dislikeTarget = 32.0;
  static const moreTarget = 30.0;
  static const likePop = 1.3;
  static const likePopDuration = Duration(milliseconds: 320);

  /// UP主觉得很赞 under the meta line.
  static const upLikedHeight = 18.0;
  static const upLikedIcon = 12.0;
  static const upLikedGap = 3.0;
  static const upLiked = BiliColors.secondaryText;

  /// 评论详情 draws UP主觉得很赞 as a box instead (font-check 04, under the root and under a reply): no thumb, #757575
  /// in #F4F4F4, 16 tall and 2 round, its top 22 below the meta text's centre and its bottom 8 above the band or the
  /// reply's hairline. The glyphs are 10 pt tall but 31.25 px apart, wider than PingFang's em as iOS tracks small
  /// text, which makes the box 75 wide.
  static double get upChipTop => 22 - metaTextRise - metaHeight / 2;
  static const upChipHeight = 16.0;
  static const upChipBottom = 8.0;
  static const upChipText = 10.0;
  static const upChipSpacing = 0.4;
  static const upChipPadding = 13 / 3;
  static const upChipRadius = 2.0;
  static const upChipFill = Color(0xFFF4F4F4);
  static const upChipInk = Color(0xFF757575);

  static TextStyle get upChipStyle => TextStyle(
    fontFamily: BiliFonts.family,
    fontSize: upChipText,
    height: upChipHeight / upChipText,
    leadingDistribution: TextLeadingDistribution.even,
    letterSpacing: upChipSpacing,
    color: upChipInk,
  );

  /// The replies box: 19.8 below the meta text's centre on 10, which is 21.2 below the meta line's (1.75 less under
  /// the system font, whose meta text sits higher); 54 from the left and 12 from the right, 8 round.
  static double get boxGap => 127 / 6 - metaHeight / 2 - (BiliFonts.nudged ? 0 : 1.75);
  static const boxLeading = 54.0;
  static const boxRadius = 8.0;
  static const box = BiliColors.softGrey;
  static const boxPadding = 10.0;

  /// A preview's lines are 23.33 apart on 12 and the thread shot, which Flutter rounds to 23; the first is centred
  /// 16.67 down. Previews follow each other with no gap, so the next one's first line is 18.75 below the last one's
  /// last line, closer than two lines of one preview.
  static const previewTop = 16.67 - previewLine / 2;
  static const previewLine = 23.0;
  static const previewText = 13.0;
  static const previewOverlap = previewLine - 18.75;

  /// A preview cut short with "…" stands 7 taller below its last line (12), one that ends on its own doesn't (the
  /// thread shot).
  static const previewCutGrowth = 7.0;
  static const preview = Color(0xFF2F3238);
  static const previewName = BiliColors.secondaryText;
  static const previewRuleGap = 7.0;
  static const previewRuleWidth = 1.0;
  static const previewRuleHeight = 10.0;
  /// 共N条回复 centres in a 36 pt slot at the bottom, 26 below a preview's last line that ends on its own.
  static const moreSlot = 36.0;
  static const moreSlotOverlap = previewLine / 2 + moreSlot / 2 - 26;
  static const moreText = 12.0;
  static const moreLink = BiliColors.link;
  static const chevronGap = 7.0;
  static const chevronWidth = 14 / 3;
  static const chevronHeight = 28 / 3;
  static const chevronStroke = 1.0;

  /// The hairline under a row, 2 px of [BiliColors.divider] from 54 to the edge, 20.3 below the meta line's centre or
  /// 12 below the replies box. Under the system font it is 20 below the meta text's centre (font-check 04), which
  /// sits [metaTextRise] above the line's.
  static const dividerLeading = 54.0;
  static const divider = 2 / 3;
  static const dividerColour = BiliColors.divider;
  static double get bottom => BiliFonts.nudged ? 61 / 3 - metaHeight / 2 : 20 - metaTextRise - metaHeight / 2;

  /// How far the meta text's centre sits above the meta line's: 0.5 under the system font (font-check 04), MiSans's
  /// 1.2 below it. The hairline, the thread's band and its UP主觉得很赞 box are placed from the text.
  static double get metaTextRise => BiliFonts.nudged ? -1.2 : 0.5;
  static const boxBottom = 12.0;

  /// The fan card's art 36.3 tall, 0.7 down, its left 81 from the right edge; the two lines of its number start 31
  /// into it, the first 13 down.
  static const fanCardTop = 2 / 3;
  static const fanCardHeight = 109 / 3;
  static const fanCardLeft = 81.0;
  static const fanNumberLead = 31.0;
  static const fanNumberTop = 13.0 - fanCardTop;
  static const fanGlyphWidth = 4.5;
  static const fanGlyphHeight = 5.1;
  static const fanGlyphWeight = 1.15;
  static const fanGlyphGap = 1.0;
  static const fanLineGap = 2.05;

  /// A card whose colour the server left out.
  static const fanNumber = Color(0xFF998245);

  /// The name stops this far before the card's art.
  static const fanCardClearance = 4.0;

  static TextStyle get textStyle => TextStyle(
    fontFamily: BiliFonts.family,
    fontSize: textText,
    height: textLine / textText,
    leadingDistribution: TextLeadingDistribution.even,
    color: text,
  );

  static TextStyle get previewStyle => TextStyle(
    fontFamily: BiliFonts.family,
    fontSize: previewText,
    height: previewLine / previewText,
    leadingDistribution: TextLeadingDistribution.even,
    color: preview,
  );

  static TextStyle metaStyle(Color color) => TextStyle(
    fontFamily: BiliFonts.family,
    fontSize: metaText,
    height: metaHeight / metaText,
    leadingDistribution: TextLeadingDistribution.even,
    color: color,
  );

  /// MiSans sets the meta line's text a point higher in its line than PingFang does on 13.
  static double get metaDrop => BiliFonts.nudged ? 1 : 0;
}

/// 评论's list, its sort header, footers and 发条评论 bar, and 评论详情's header and band (10-13), measured at 3 px per
/// pt.
abstract final class CommentListTheme {
  static const gutter = BiliMetrics.gutter;

  /// Always white, as the official page.
  static const background = BiliColors.card;

  /// The hairlines over the 发条评论 bar and under 评论详情's header.
  static const rule = BiliColors.divider;

  /// 热门评论 and ≡ 按热度 centre 16.5 below the list's top in a 28 pt header, so the first row's fan card starts 31
  /// below it (10). 评论详情's 相关回复共N条 sits lower in 35 pt under the band (13). The official app sets them in
  /// PingFang at 12 and 11 pt (their glyphs 31 and 29 px tall on 10); MiSans matched at 13 and 12.
  static const sortHeight = 28.0;
  static const sortCentre = 16.5;
  static const threadSortHeight = 35.0;
  static const threadSortCentre = 55 / 3;
  static const sortLine = 18.0;
  static double get sortTitleText => BiliFonts.nudged ? 13 : 12;
  static double get sortText => BiliFonts.nudged ? 12 : 11;
  static const sortInk = BiliColors.secondaryText;

  /// ≡: three bars 1 pt thick and 4 apart, 35/3 wide, 4 before 按热度.
  static const sortIconWidth = 35 / 3;
  static const sortIconBar = 1.0;
  static const sortIconPitch = 4.0;
  static const sortIconGap = 4.0;

  /// The sort button's touch reaches this far left of ≡.
  static const sortTouchLead = 16.0;

  /// The footer under a list: 没有更多了 and the empty and failed lines, more room when the list is empty.
  static const footerText = 12.0;
  static const footerLine = 17.0;
  static const footerInk = Color(0xFFC9CCD0);
  static const footerPadding = 20.0;
  static const emptyPadding = 48.0;
  static const retryInk = BiliColors.secondaryText;
  static const retryAction = BiliColors.link;

  /// The server's reason over 加载失败，点击重试, as the Swift app showed it.
  static const retryGap = 6.0;
  static const spinnerRadius = 10.0;

  /// The section the uploader closed: a bubble over the server's words.
  static const closedTop = 80.0;
  static const closedIcon = 34.0;
  static const closedGap = 10.0;
  static const closedText = 14.0;
  static const closedInk = BiliColors.secondaryText;

  /// The 发条评论 bar (10, 13): a hairline over it, the 34 pt pill 17/3 below the hairline and 5 above the home
  /// indicator, 12 in from the left and 44 short of the right, where the 20 pt emote face centres 22 in.
  static const barHairline = 0.5;
  static const barTop = 17 / 3;
  static const barBottom = 5.0;
  static const fieldHeight = 34.0;
  static const fieldFill = BiliColors.pageGrey;
  static const fieldPadding = 13.0;
  static const fieldText = 15.0;
  static const fieldInk = BiliColors.secondaryText;
  static const faceBox = 44.0;
  static const face = 20.0;
  static const faceStroke = 1.28;
  static const faceInk = BiliColors.secondaryText;

  /// 评论详情's header over the thread: 40 as the tab row it covers, then its 1 pt hairline (3 px at 239.7 on 13).
  static const threadHeaderHeight = 41.0;
  static const threadHairline = 1.0;
  /// Under the system font 13.75: the official 评论详情's glyphs are 38 px tall to our 41.5 at 15 (font-check 04).
  static double get threadTitleText => BiliFonts.nudged ? 15 : 13.75;
  static const threadTitleInk = BiliColors.text;

  /// ✕: 38/3 pt square, 1.2 pt strokes, centred 26 in from the right edge in a 44 pt button.
  static const close = 38 / 3;
  static const closeStroke = 1.2;
  static const closeBox = 44.0;
  static const closeTrailing = 4.0;
  static const closeInk = BiliColors.secondaryText;

  /// The grey band between the thread's root and its replies, straight under the root's meta line.
  static const bandHeight = 10.0;
  static const band = BiliColors.pageGrey;

  /// The band starts 20 below the root's meta text's centre, where a reply's hairline does (13 and font-check 04).
  /// MiSans keeps the hairline's room.
  static double get bandGap => BiliFonts.nudged
      ? CommentRowTheme.bottom + CommentRowTheme.divider
      : 20 - CommentRowTheme.metaTextRise - CommentRowTheme.metaHeight / 2;

  /// MiSans sets Chinese wider than the official PingFang (热门评论 37.3 px a character on 10, MiSans 38.7; 按热度 33
  /// against 36); these close most of it without crowding the glyphs.
  static double get sortTitleSpacing => BiliFonts.nudged ? -0.4 : 0;
  static double get sortSpacing => BiliFonts.nudged ? -0.6 : 0;
  static double get fieldSpacing => BiliFonts.nudged ? -0.6 : 0;
  static double get threadTitleSpacing => BiliFonts.nudged ? -0.4 : 0;
}

/// A comment's rich text and the picture viewer.
abstract final class CommentTextTheme {
  /// The only blue the official comments show (12's 共N条回复) is the app's link blue.
  static const link = BiliColors.link;

  /// A reply's "回复 名字: " lead names whom it answers in grey, #9499A0 on font-check 04, without the @.
  static const replyTarget = BiliColors.secondaryText;

  /// An emote's side per step of its `size`, as a share of the text's size: 12's 😑 is 20 pt beside 15 pt text.
  static const emoteScale = 4 / 3;

  /// Two emotes in a row stand apart by this share of the text's size: the thread shot's (differences 12) are 24 pt
  /// apart beside 15 pt text, 4 more than their side. One after text gets no gap.
  static const emoteGap = 4 / 15;

  /// How far an emote's middle sits above the baseline, as a share of the text's size: on the middle of the Chinese
  /// glyphs beside it, as on 12.
  static const emoteRise = 0.35;

  /// A line holding an emote reaches this much further below its text than a plain line: on 12 the meta under a line
  /// ending in 😑 sits 2 pt lower than under plain text.
  static const emoteLineGrowth = 2.0;

  static const viewerBackground = Color(0xFF000000);
  static const viewerText = Color(0xFFFFFFFF);
  static const viewerCountText = 15.0;

  /// The "2/5" count, below the safe area.
  static const viewerCountTop = 12.0;

  /// The invisible 关闭 target in the top corner, for VoiceOver; a tap anywhere closes the viewer anyway.
  static const viewerCloseTarget = 44.0;
  static const viewerFadeIn = Duration(milliseconds: 200);
  static const viewerZoomDuration = Duration(milliseconds: 250);
  static const viewerDoubleTapScale = 2.5;
  static const viewerMaxScale = 4.0;

  /// While a picture loads, the list's thumbnail under a spinner; a failed one shows a picture glyph at half white.
  static const viewerSpinnerRadius = 14.0;
  static const viewerFailedGlyph = 48.0;
  static const viewerFailedGlyphStroke = 2.0;
  static const viewerFailedGlyphColor = Color(0x80FFFFFF);
  static const viewerCrossFade = Duration(milliseconds: 200);
}

/// The composer and its emote panel (14), measured at 3 px per pt.
abstract final class ComposerTheme {
  static const gutter = BiliMetrics.gutter;

  /// 14's page shows through at 80%: its white reads #CCCCCC.
  static const dim = BiliColors.scrim;
  static const sheet = BiliColors.card;

  /// The keyboard toggle and 发布 are a deeper pink than [BiliColors.pink]; 发布 with nothing to post is it at about
  /// 30% on white.
  static const accent = Color(0xFFED7098);
  static const accentFaded = Color(0xFFF8D3DF);
  static const publishText = Color(0xFFFFFFFF);
  static const text = BiliColors.text;
  static const placeholder = Color(0xFFC9CCCF);

  /// @, ⊕, ⤢ and the emote face.
  static const tool = Color(0xFF95999F);
  static const syncText = Color(0xFF62666C);
  static const syncRing = placeholder;
  static const panel = BiliColors.pageGrey;
  static const tabBar = BiliColors.card;
  static const tabSelected = BiliColors.pageGrey;
  static const sectionTitle = syncText;
  static const kaomoji = BiliColors.text;
  static const kaomojiTab = Color(0xFFA7A7A7);

  /// The sheet rises as the page dims, and falls when it closes itself; ⤢ grows the field.
  static const rise = Duration(milliseconds: 250);
  static const fall = Duration(milliseconds: 200);
  static const expand = Duration(milliseconds: 250);

  /// How long the emote panel waits for the keyboard it gave way to before going anyway: a hardware keyboard shows no
  /// software one.
  static const keyboardWait = Duration(milliseconds: 600);

  /// The sheet is 115 pt over the emote panel's top: the field, then the toolbar. The first line's ink is centred
  /// 24.7 pt under the sheet's top and 13 pt in; ⤢'s 10.7 pt arrows are centred 24 pt down and 20 pt from the right.
  static const sheetRadius = 4.0;
  static const editorHeight = 67.0;
  static const expandedEditorHeight = 260.0;
  static const editorTop = 13.5;
  static const editorLeading = 12.0;
  static const editorTrailing = 40.0;
  static const editorFont = 15.0;
  static const expandCellHeight = 48.0;
  static const expandIcon = 32 / 3;
  static const expandStroke = 4 / 3;

  /// The toolbar's row, everything on its middle: ○ 11 pt in with 转到动态 5 pt after it, the keyboard toggle, @ and
  /// ⊕ in 44 pt cells centred at 96, 140 and 184 pt, and 发布 12 pt from the right.
  static const toolbarHeight = 48.0;
  static const syncLeading = 11.0;
  static const syncRingSize = 10.0;
  static const syncRingStroke = 1.0;
  static const syncGap = 5.0;
  static const syncWidth = 74.0;
  static const syncFont = 10.0;
  static const toolCell = 44.0;
  static const toolIcon = 20.0;
  static const keyboardIconHeight = 52 / 3;
  static const toolStroke = 1.5;
  static const publishWidth = 56.0;
  static const publishHeight = 24.0;
  static const publishTrailing = 12.0;
  static const publishFont = 13.0;
  static const publishSpinnerRadius = 7.0;

  /// The emote panel takes the keyboard's place at its height; before the keyboard has been seen, the grid is 14's
  /// 226 pt over its 44 pt tab bar (878-922) and the home indicator's strip.
  static const panelHeight = 226.0;
  static const tabHeight = 44.0;
  static const tabWidth = 50.0;
  static const tabIcon = 28.0;

  /// 14's section titles sit 1.5 pt under the middle of their band. A row's emote is centred 31 pt down; 最近使用's
  /// row is cut short under it.
  static const sectionHeight = 34.0;
  static const sectionTitleTop = 3.0;
  static const sectionFont = 12.0;
  static const gridSide = 3.0;
  static const columns = 7;
  static const emote = 28.0;
  static const row = 62.0;
  static const recentRow = 53.0;
  static const largeColumns = 4;
  static const largeEmote = 52.0;
  static const largeRow = 80.0;
  static const textColumns = 3;
  static const textRow = 44.0;
  static const kaomojiFont = 13.0;
  static const kaomojiPad = 4.0;
  static const kaomojiTabFont = 9.0;
  static const kaomojiTabPad = 3.0;
  static const spinnerRadius = 10.0;
}

/// The comment overlays: the rising thread and the delete confirm.
abstract final class CommentOverlayTheme {
  static const threadRise = Duration(milliseconds: 300);

  /// ✕, back or a released swipe slide 评论详情 off the bottom; part of the way takes its share of this.
  static const threadFall = Duration(milliseconds: 300);

  /// Behind 评论详情, so the list under it never shows through and touches stop there.
  static const threadFill = BiliColors.card;

  /// A released swipe closes 评论详情 once it is this share of its height down, or when the finger moves right faster
  /// than [threadFlingWidths] screen widths a second (Flutter's Cupertino back swipe's `_kMinFlingVelocity`).
  static const threadCloseShare = 1 / 3;
  static const threadFlingWidths = 1.0;

  /// The picture viewer fades in and out (BiliNative's 0.2 s ease out).
  static const viewerFade = Duration(milliseconds: 200);

  /// The delete confirm comes and goes as the unfollow confirm does, in the same alert with a message under the
  /// title (Swift's 删除评论 alert).
  static const confirmIn = Duration(milliseconds: 300);
  static const confirmOut = Duration(milliseconds: 220);
  static const alertWidth = FavouriteTheme.alertWidth;
  static const alertRadius = FavouriteTheme.alertRadius;
  static const alertTitleText = FavouriteTheme.alertTitleText;
  static const alertButtonHeight = FavouriteTheme.alertButtonHeight;
  static const alertButtonText = FavouriteTheme.alertButtonText;
  static const alertDim = FavouriteTheme.alertDim;
  static const alertStartScale = FavouriteTheme.alertStartScale;
  static const alertTitlePadTop = 22.0;
  static const alertMessageText = 14.0;
  static const alertMessageGap = 6.0;
  static const alertMessagePadBottom = 20.0;
  static const alertTitle = BiliColors.text;
  static const alertMessage = BiliColors.secondaryText;
  static const alertCancel = BiliColors.secondaryText;
  static const alertDelete = BiliColors.pink;
}

/// The paused player shrinking to the 继续播放 bar (11, 12).
abstract final class CollapseTheme {
  /// 12's bar is 202 px tall; BiliNative's 56 pt was short of it.
  static const barHeight = 202 / 3;

  /// Over the bar at 12's darkness (its danmaku keep 11% of their white); it deepens with the shrink, as on 11.
  static const shade = Color(0xE3000000);

  /// ▶ 继续播放 is fully in once the player has gone this share of the way, then its opacity holds.
  static const labelFade = 1.6;

  /// 12 centres the bar's row 2.5 px above the bar's middle.
  static const rowLift = 2.5 / 3;
  static const playGlyphWidth = 40 / 3;
  static const playGlyphHeight = 44 / 3;

  /// 12 sets ▶ 17.4 pt before 继续播放 and the pair 1.5 pt right of the bar's middle.
  static const labelGap = 3.3;
  static const labelShift = 1.5;
  static const labelText = 16.0;
  static const label = BiliColors.onVideo;

  /// The chevron's left edge and the dots' right edge from the screen's sides.
  static const backLeft = 17.0;
  static const backGlyphWidth = 9.0;
  static const backGlyphHeight = 16.0;
  static const moreRight = 61 / 3;

  /// ‹ and ⋮ joining the label once it is the bar.
  static const controlsFade = Duration(milliseconds: 150);

  /// 继续播放's scroll back to the top, and the player growing back to full once it plays.
  static const resume = Duration(milliseconds: 300);
}

/// The composer's @ picker and attached pictures.
abstract final class MentionTheme {
  static const gutter = BiliMetrics.gutter;

  /// How long typing must rest before the picker searches.
  static const debounce = Duration(milliseconds: 300);

  /// The search pill under the header, filled as 14's emote panel.
  static const fieldHeight = 36.0;
  static const fieldFill = BiliColors.pageGrey;
  static const fieldText = 15.0;
  static const fieldIcon = 18.0;
  static const fieldIconGap = 6.0;
  static const fieldPadX = 12.0;
  static const fieldBottom = 4.0;
  static const fieldSpinnerRadius = 7.0;
  static const clearSize = 16.0;
  static const clearGlyph = 11.0;
  static const clearFill = BiliColors.sheetHint;
  static const clearGlyphColor = BiliColors.card;

  /// 最近关注 over the list, in 14's 最近使用 grey.
  static const sectionHeight = 36.0;
  static const sectionText = 13.0;
  static const sectionColour = BiliColors.sheetCloseGlyph;

  static const rowHeight = 60.0;
  static const avatar = 40.0;
  static const avatarGap = 12.0;
  static const nameText = 15.0;

  /// The part of a name that matches the search.
  static const match = BiliColors.pink;

  /// Loading, no matches and 加载失败.
  static const statePad = 40.0;
  static const stateText = 14.0;
  static const spinnerRadius = 10.0;

  /// The attached pictures: square thumbnails under the field, each with a ✕ in its top right corner.
  static const thumb = 72.0;
  static const thumbGap = 8.0;
  static const thumbRadius = BiliMetrics.cardRadius;
  static const thumbBottom = 8.0;
  static const thumbBorder = BiliColors.divider;
  static const thumbBorderWidth = 0.5;
  static const removeHitBox = 28.0;
  static const removeSize = 18.0;
  static const removeGlyph = 11.0;
  static const removeInset = 4.0;
  static const removeFill = Color(0x8C000000);
  static const removeGlyphColor = Color(0xFFFFFFFF);
}

/// The avatar's page (49), measured from the safe area's top: the bar, the four shortcuts, then the white card of
/// 最近在看的视频 whose rows are [rowExtent] apart with the cover [rowCoverTop] into each.
abstract final class AvatarPageTheme {
  static const background = BiliColors.softGrey;
  static const barHeight = 44.0;
  static const barIcon = Color(0xFF61666D);
  static const backLeft = 19.5;
  static const tabCentreX = 132.3;
  static const tabText = 16.0;
  static const tabWeight = FontWeight.w600;
  static const tabUnderlineTop = 34.0;
  static const tabUnderlineWidth = 12.0;
  static const tabUnderlineHeight = 2.0;
  static const gearCentreX = 416.0;
  static const gearBox = 22.0;
  static const gearRadius = 9.4;
  static const gearCorner = 2.0;
  static const gearHole = 3.1;
  static const gearStroke = 1.5;
  static const tapTarget = 44.0;

  /// The shortcuts: a quarter of the width each, their 32 pt icon box centred [shortcutIconCentre] below the bar and
  /// the label's middle [shortcutLabelCentre] below it.
  static const shortcutsHeight = 96.0;
  static const shortcutIconBox = 32.0;
  static const shortcutIconCentre = 37.0;
  static const shortcutLabelCentre = 61.6;
  static const shortcutStroke = 5 / 3;
  static const shortcutText = 12.0;

  static const cardRadius = 20.0;
  static const headerHeight = 36.0;
  static const headerCentre = 26.0;
  static const headerText = 14.0;
  static const headerWeight = FontWeight.w500;
  static const allText = 12.0;
  static const allChevronWidth = 4.7;
  static const allChevronHeight = 9.0;
  static const allChevronGap = 7.6;
  static const allChevronStroke = 1.2;
  static const allRight = 15.0;

  static const rowExtent = 104.0;
  static const rowCoverTop = 14.0;
  static const coverWidth = 136.0;
  static const coverHeight = 76.0;
  static const coverRadius = 5.0;
  static const progressHeight = 2.0;
  static const durationHeight = IntroListTheme.durationHeight;
  static const durationPad = 3.0;
  static const durationRadius = IntroListTheme.durationRadius;
  static const durationInset = IntroListTheme.durationInset;
  static const durationText = IntroListTheme.durationText;
  static const durationFill = IntroListTheme.durationFill;
  static const textLeft = 156.0;
  static const titleText = 14.0;
  static const titleLine = 50 / 3;

  /// How far the title's line box starts above the cover, so its ink lines up with the cover's top.
  static const titleLift = 2.0;
  static const timeText = 12.0;

  /// How far the time's line box ends below the cover, so its ink ends a point above the cover's bottom.
  static const timeDrop = 2.2;
  static const removeCentreFromRight = 20.0;
  static const removeCentreBelowCover = 70.0;
  static const removeGlyph = 8.6;
  static const removeStroke = 1.0;
  static const remove = Color(0xFFC9CCD0);
  static const shown = 5;
}

/// The swipe back from a 推荐 card (03, 04 in local/differences, measured frame by frame): the page shrinks into a
/// floating card over the dimmed home and flies into the card it came from.
abstract final class ZoomBackTheme {
  /// Over home while the page is still full size, lightening to [dimShrunk] as it reaches [minScale].
  static const dim = Color(0x8C000000);
  static const dimShrunk = Color(0x57000000);

  /// Shares of the screen's width the finger has moved right. The page shrinks slowly to [kneeScale] by
  /// [kneeTravel], then quickly to [minScale] by [minScaleTravel] while its centre holds still, then only moves.
  static const kneeTravel = 0.366;
  static const kneeScale = 0.8;
  static const minScaleTravel = 0.477;
  static const minScale = 0.6;

  /// In the page's own points, so it shrinks with the page (6.6 pt on screen at 0.6).
  static const cornerRadius = 11.0;

  /// Let go past this share of the width, or flung right at [flingSpeed] widths a second or more, and the page goes;
  /// otherwise it springs back over [settle].
  static const completeTravel = 0.24;
  static const flingSpeed = 1.0;
  static const settle = Duration(milliseconds: 350);

  /// Let go, the page flies into its card in about ten frames, the dim lifting with it. The card's picture is in by
  /// [pictureIn] of the way, from the first frame; under it the page drops at once to [pageUnder] and fades out by
  /// [pageOut], so it is the card that flies.
  static const fly = Duration(milliseconds: 170);
  static const flyCurve = Curves.easeOut;
  static const pictureIn = 0.05;
  static const pageUnder = 0.3;
  static const pageOut = 0.7;

  /// With no picture of the card to turn into, the page fades onto the card itself from this share of the way.
  static const fadeOntoCard = 0.35;

  /// The 〈 button and system back fly the full page into its card.
  static const flyFromFull = Duration(milliseconds: 350);

  /// With its card off screen or gone, the page shrinks this much more towards the middle as it fades.
  static const lostScale = 0.5;

  /// Reduce Motion: let go, the page fades where it is.
  static const fade = Duration(milliseconds: 150);
}

/// Turning to landscape full screen and back (01 in local/differences): the video grows from its small spot to full
/// screen over the whole turn, starting as the presentation changes, or as the system's turn starts when the page draws
/// it. The official turn moves visibly for 16 to 17 frames at 60 fps either way, its ease-in-out's ends barely moving.
abstract final class RotationTheme {
  /// The official turn's length both ways, fitted with [curve] to 298.5 and 300.1 ms: UIKit's 0.3 s. A turn the page
  /// draws takes it too, since iOS reports no length for a turn asked for with its animations off.
  static const grow = Duration(milliseconds: 300);

  /// The official page's angle, measured frame by frame both ways, fits this to within 0.2° rms (0.9° at worst), and
  /// its box grows in step. A turn the page draws itself (旋转动画) turns and grows on it too.
  static const curve = Curves.easeInOut;

  /// While the page draws the turns, how long a change of presentation waits for the system's turn before the player
  /// grows without one, as a refused or lost turn would leave it.
  static const takeoverWait = Duration(milliseconds: 250);
}

/// 弹幕设置 (07, 08, 24, 29, 33, 40, 41). Landscape is a hard-edged dark strip at the right, portrait the light
/// sheet; both lay out the same, measured from the top of the scrolling content and the left of the cards.
abstract final class DanmakuPanelTheme {
  /// The strip's share of the screen's width (382 of 956 pt) and the portrait sheet's height when it isn't hung
  /// from the small player (497 of 956).
  static const width = 382 / 956;
  static const sheetHeight = 497 / 956;

  /// No ramp into the video in front of it, unlike the other panels: 07, 24 and 29 cut straight to this.
  static const shade = Color(0xE1000000);

  /// The cards lie [inset] in from the strip's left and the safe area's edge, and their rows another [inset].
  static const inset = 16.0;
  static const cardRadius = 8.0;

  /// From the top of the content to the first card; the title and 查看更多 are centred [headerCentre] down.
  static const headerHeight = 48.0;
  static const headerCentre = 26.2;
  static const titleText = 14.0;
  static const detailText = 12.0;

  /// The box a line of text is centred in.
  static const labelBox = 20.0;
  static const moreGap = 5.5;
  static const moreTrailing = 2.0;

  /// A slider row: label and value centred [sliderLabelCentre] down, the track centred [sliderTrackCentre] down,
  /// [sliderTrackInset] in from the card, the thumb's centre travelling to [sliderThumbInset] from the track's
  /// ends and the stop dots [sliderDotInset].
  static const sliderRow = 68.0;
  static const sliderLabelCentre = 22.0;
  static const sliderTrackCentre = 46.3;
  static const sliderTrackInset = 14.0;
  static const sliderTrack = 6.0;
  static const sliderThumb = 14.0;
  static const sliderThumbInset = 4.0;
  static const sliderDot = 3.7;
  static const sliderDotInset = 5.6;

  /// Section titles sit between cards [sectionHeight] apart, centred [sectionCentre] below the card above.
  static const sectionHeight = 56.0;
  static const sectionCentre = 34.2;

  /// 按弹幕类型屏蔽: its label, the row of squares and their labels, then the hairline at the block's foot.
  static const typeBlock = 140.0;
  static const typeLabelCentre = 26.2;
  static const squareTop = 52.0;
  static const squareHeight = 48.0;
  static const squareGap = 6.0;
  static const squareRadius = 12.0;
  static const squareLabelCentre = 13.2;

  /// The type glyphs' box, and the ⊘ on a blocked type: its centre in the box, its radius to the stroke's middle,
  /// and how far round it the screen's outline is cut away.
  static const glyphWidth = 26.0;
  static const glyphHeight = 22.2;
  static const glyphStroke = 1.5;
  static const markStroke = 1.5;
  static const badgeCentre = Offset(21.8, 17.5);
  static const badgeRadius = 5.4;
  static const badgeClear = 8.3;

  /// A row with a switch: its title and subtitle centred [toggleTitleCentre] and [toggleSubtitleCentre] down.
  static const toggleRow = 72.0;
  static const toggleTitleCentre = 27.7;
  static const toggleSubtitleCentre = 48.8;

  /// 添加屏蔽词's button under 弹幕观看屏蔽词, then the gap to 当前弹幕列表's hairline.
  static const buttonHeight = 36.0;
  static const buttonRadius = 8.0;
  static const buttonTextInset = 16.0;
  static const buttonChevronTrailing = 20.3;
  static const buttonGap = 15.0;
  static const listRow = 51.0;
  static const listChevronTrailing = 21.0;

  /// ↻ 重置弹幕设置 under the last card: centred [resetCentre] below it, its text ending [resetTrailing] short of
  /// the cards' right edge, and the content ending [endGap] below its row (portrait adds the safe area).
  static const resetCentre = 24.0;
  static const resetHeight = 20.0;
  static const resetGap = 3.0;
  static const resetTrailing = 1.0;

  /// MiSans sets 重置弹幕设置 a point wider than 08's PingFang, which would push ↻ left of where 08 has it.
  static double get resetSpacing => BiliFonts.nudged ? -0.2 : 0;
  static const endGap = 6.0;

  /// The portrait sheet's content starts this far under its grabber.
  static const sheetTop = 8.0;

  static const chevronDownWidth = 11.3;
  static const chevronDownHeight = 6.0;
  static const buttonChevronWidth = 6.7;
  static const buttonChevronHeight = 11.3;
  static const listChevronWidth = 5.7;
  static const listChevronHeight = 11.7;
  static const chevronStroke = 1.1;
  static const resetGlyphWidth = 13.3;
  static const resetGlyphHeight = 12.3;
  static const resetStroke = 1.0;

  /// The reset confirm (33): over the whole screen, dimming everything, the panel included.
  static const dialogWidth = 280.0;
  static const dialogTitleHeight = 67.3;
  static const dialogButtonHeight = 44.0;
  static const dialogRadius = 8.0;
  static const dialogTitleText = 16.0;
  static const dialogButtonText = 14.0;

  /// 我再想想 and 确定 are centred this far either side of the dialog's middle.
  static const dialogButtonSpread = 66.0;
  static const dialogDim = BiliColors.sheetDim;
  static const dialog = Color(0xFF242628);
  static const dialogText = Color(0xFFE7E9EB);
  static const dialogConfirm = Color(0xFFD44E7D);
  static const dialogDivider = Color(0xFF2F3134);

  /// Landscape, over the video: the cards and squares let a little of it through.
  static const card = Color(0xB32F3238);
  static const square = Color(0x0DFFFFFF);
  static const track = Color(0x26FFFFFF);
  static const hairline = BiliColors.panelHairline;
  static const text = BiliColors.panelText;
  static const value = Color(0xFFC9CCD0);
  static const secondary = BiliColors.panelSecondary;
  static const reset = Color(0xFFC9CCD0);

  /// Portrait's light sheet (40, 41): the fill left of the thumb is half pink, the thumb and dots pink.
  static const lightBackground = Color(0xFFF6F7F8);
  static const lightCard = BiliColors.card;
  static const lightSquare = Color(0xFFF6F7F8);
  static const lightTrack = Color(0xFFE3E5E7);
  static const lightFill = Color(0xFFFFB3CA);
  static const lightHairline = Color(0xFFE3E5E7);
  static const lightText = BiliColors.text;
  static const lightSecondary = BiliColors.secondaryText;
  static const lightReset = Color(0xFF61666D);
  static const lightSwitchOff = Color(0xFFE9E9EA);
  static const lightKnobShadow = Color(0x29000000);
  static const lightKnobShadowBlur = 1.5;
  static const lightKnobShadowOffset = Offset(0, 0.5);
}

/// 添加屏蔽词 (30). Across, sizes count from the safe area's left edge (62 pt on the Pro Max); the top row ends at its
/// right edge.
abstract final class BlockWordsTheme {
  /// 30's white slide comes out at about 40 of 255.
  static const dim = Color(0xD6000000);

  /// The selected tab and its underline are Bilibili's #FB7299, not the app's [BiliColors.pink].
  static const pink = Color(0xFFFB7299);
  static const text = Color(0xFFFFFFFF);
  static const grey = Color(0xFF999999);

  static const closeCentreX = 27.0;
  static const closeHitBox = 44.0;

  /// From the ✕'s centre to the end of each stroke, along each axis.
  static const closeArm = 5.8;
  static const closeStroke = 2.1;

  static const rowTop = 7.0;
  static const rowHeight = 30.0;
  static const fieldLeft = 54.17;
  static const fieldFill = Color(0xFFFFFFFF);
  static const fieldInk = BiliColors.text;
  static const fieldRadius = 3.5;
  static const fieldPadX = 10.0;
  static const fieldText = 12.0;

  /// MiSans's Chinese is about 5% wider than 30's PingFang at 12 pt; this brings the placeholder and the tabs to its
  /// widths.
  static double get smallSpacing => BiliFonts.nudged ? -0.35 : 0;

  /// 添加 and 同步: white at 20% over the dim.
  static const buttonFill = Color(0x33FFFFFF);
  static const buttonGap = 12.33;
  static const buttonWidth = 77.67;
  static const buttonText = 14.0;
  static const addIcon = 17.0;
  static const addIconLeft = 13.6;
  static const addIconGap = 6.67;

  /// The pencil sits a point above the row's centre in 30.
  static const addIconLift = 1.0;
  static const addStroke = 1.33;
  static const syncIcon = 19.0;
  static const syncIconLeft = 8.17;
  static const syncIconGap = 5.0;
  static const syncStroke = 1.5;

  /// 关键词 / 正则 / 举报屏蔽用户 sit 4 pt in, their row from the top row's bottom to the list.
  static const tabsLeft = 4.0;
  static const tabsTop = 44.0;
  static const tabsHeight = 30.0;
  static const tabText = 12.0;
  static const tabGap = 22.33;
  static const underline = 2.0;

  /// The two columns split at the screen's centre by a third-of-a-point line down to the safe area's bottom.
  static const dividerWidth = 1 / 3;
  static const divider = Color(0x1AFFFFFF);
  static const listPad = 20.0;

  /// 30 has a single row; the gap between rows is the top row's button gap.
  static const rowGap = 12.0;

  static const chipHeight = 32.0;
  static const chipRadius = 4.0;
  static const chipFill = Color(0x0DFFFFFF);
  static const chipText = 14.0;
  static const chipPadLeft = 12.0;
  static const chipGlyphGap = 13.0;
  static const chipPadRight = 11.0;
  static const chipGlyph = 14.0;
  static const chipGlyphInset = 0.6;
  static const chipStroke = 1.65;
}

/// The send bar and the style panel (22, 23, 36-39).
abstract final class DanmakuSendTheme {
  /// Landscape's dark bar over its darker area (22, 23); portrait's white bar with a hairline over a grey panel (36-39).
  static const darkBar = Color(0xFF242627);
  static const darkArea = Color(0xFF1A1B1C);
  static const lightBar = BiliColors.card;
  static const lightArea = BiliColors.pageGrey;
  static const hairline = Color(0xFFE3E5E7);
  static const hairlineWidth = 1 / 3;

  /// Landscape's pink is deeper than the light pages'; 竖屏's send arrow turns it too (37), while A and the options
  /// take the page pink there (38).
  static const darkAccent = Color(0xFFED7098);
  static const lightAccent = BiliColors.pink;
  static const sendReady = darkAccent;
  static const darkGlyph = Color(0xFFFFFFFF);
  static const lightGlyph = Color(0xFF62666C);
  static const hintDot = Color(0xFFD04B44);

  /// 39's empty arrow is the dark glyph grey, 36's the placeholder grey.
  static const verticalSendIdle = Color(0xFFC9CCCF);

  /// The page under the small player (39).
  static const dim = BiliColors.scrim;

  /// The bar is 42 pt: on the small player and in landscape A is centred 21 pt in, the field runs from 42 pt to 42 pt
  /// short of the far edge and the arrow is centred 21 pt from it, inside the safe areas (22, 39). 竖屏 sets them
  /// wider: A at 24, the field from 48 to 58 short, a larger arrow centred 30.5 pt from the edge (36).
  static const barHeight = 42.0;
  static const aCell = 42.0;
  static const sendCell = 42.0;
  static const verticalACell = 48.0;
  static const verticalSendCell = 55.0;
  static const verticalSendTrailing = 3.0;

  /// 竖屏's bar is a sheet with rounded top corners (36).
  static const verticalBarRadius = 8.5;

  /// The A glyph and its red dot, 9 pt up and right of its middle until A is first pressed (22).
  static const aWidth = 14.6;
  static const aHeight = 17.75;
  static const aStroke = 1.4;
  static const hintDotSize = 5.5;
  static const hintDotOffset = 9.0;

  /// The paper plane, outlined at 1.5 pt; 竖屏's is 18% larger and filled once there is text (36, 37).
  static const sendWidth = 18.0;
  static const sendHeight = 17.5;
  static const sendStroke = 1.5;
  static const verticalSendScale = 1.18;
  static const sendSpinnerRadius = 7.0;

  /// The 30 pt pill: white in landscape, grey on the light bar, with a hairline in 竖屏. Text starts 8 pt in (12 in
  /// 竖屏) behind a 20 pt pink cursor.
  static const fieldHeight = 30.0;
  static const darkField = Color(0xFFFFFFFF);
  static const lightField = BiliColors.pageGrey;
  static const fieldText = BiliColors.text;
  static const fieldFont = 15.0;
  static const fieldPad = 8.0;
  static const verticalFieldPad = 12.0;
  static const placeholder = Color(0xFFC9CCCF);

  /// MiSans sets Chinese a touch wider than the official PingFang: this ends the placeholder where 22's and 36's do.
  static double get placeholderSpacing => BiliFonts.nudged ? -0.15 : 0;

  /// 竖屏's placeholder is smaller and darker than the text it gives way to (36, 37).
  static const verticalPlaceholder = Color(0xFF95999F);
  static const verticalPlaceholderFont = 13.0;
  static const cursorHeight = 20.0;
  static const cursorWidth = 2.0;

  /// The clear ⓧ, centred 15 pt in from the field's end (37).
  static const clearSize = 14.0;
  static const clearCell = 30.0;
  static const clearFill = Color(0xFFC9CCCF);
  static const clearGlyph = Color(0xFFFFFFFF);
  static const clearArm = 2.2;
  static const clearStroke = 1.1;

  /// The keyboard's height in the official shots, which the style panel takes until a keyboard has been seen: 22's
  /// landscape one and 36's portrait one with the home indicator's strip.
  static const landscapePanelHeight = 224.0;
  static const portraitPanelHeight = 347.0;

  /// How long the panel waits for the keyboard it gave way to before going anyway: a hardware keyboard shows none.
  static const keyboardWait = Duration(milliseconds: 600);

  /// The panel: a 64 pt label column 12 pt in, then rows 54 pt apart from 7 pt down in landscape (23) and 12 pt in
  /// portrait (38). Options are 94 pt apart in landscape and 121 pt in portrait.
  static const panelGutter = BiliMetrics.gutter;
  static const panelTop = 7.0;
  static const portraitPanelTop = 12.0;
  static const rowHeight = 54.0;
  static const labelWidth = 64.0;
  static const labelFont = 12.0;
  static double get labelSpacing => BiliFonts.nudged ? -0.4 : 0;
  static const darkSecondary = Color(0xFF95999F);
  static const lightSecondary = Color(0xFF9499A0);
  static const option = 94.0;
  static const portraitOption = 121.0;
  static const optionHeight = 44.0;
  static const optionFont = 13.0;
  static const optionIconLead = 1.5;
  static const optionIconWidth = 21.1;
  static const optionIconHeight = 17.1;
  static const optionIconRadius = 5.5;
  static const optionIconStroke = 1.6;
  static const optionGap = 6.8;
  static const sizeGlyphStroke = 1.6;
  static const smallSizeGlyphStroke = 1.4;
  static const modeDot = 0.9;
  static const modeStroke = 1.5;

  /// 弹幕颜色: 26×22 swatches in a ring, one row of 46 pt cells in landscape starting 13 pt into the label column; two
  /// rows 44 pt apart of 49.67 pt cells in portrait, seven then six, starting 14.8 pt into it (23, 38).
  static const swatchCell = 46.0;
  static const swatchLead = -13.0;
  static const portraitSwatchCell = 49.67;
  static const portraitSwatchLead = -14.83;
  static const portraitSwatchesPerRow = 7;
  static const secondSwatchRow = 34.0;
  static const swatchWidth = 26.0;
  static const swatchHeight = 22.0;
  static const swatchRadius = 7.0;
  static const swatchFillRadius = 5.0;
  static const swatchFillInset = 2.2;
  static const swatchRingWidth = 1.4;
  static const lightSwatchRingWidth = 1.1;
  static const darkSwatchRing = Color(0xFF46494C);
  static const lightSwatchRing = Color(0xFFC9CCD0);

  /// The dark picker shows the colours dimmed, in the same order as `DanmakuStyle.colors` (23 against 38).
  static const darkSwatches = [
    Color(0xFFFFFFFF), Color(0xFFD42D25), Color(0xFFFCF150), Color(0xFF42954C), Color(0xFF469DE4), //
    Color(0xFFCF2C7D), Color(0xFF9AC143), Color(0xFF102859), Color(0xFFE6AE48), Color(0xFF613C77), //
    Color(0xFF91BEC9), Color(0xFF8E7A43),
  ];

  /// The 会员 chip: the gradient ring around a white middle, with its pink 会员 pill over the top right corner.
  static const darkVipLeading = Color(0xFFD896D5);
  static const darkVipTrailing = Color(0xFF7AB2E6);
  static const lightVipLeading = Color(0xFFE492D9);
  static const lightVipTrailing = Color(0xFF71B2EA);
  static const vipInsetX = 5.0;
  static const vipInsetY = 4.5;
  static const vipInnerRadius = 4.0;
  static const vipWidth = 24.6;
  static const vipHeight = 20.7;
  static const vipShift = 1.0;
  static const vipBadgeWidth = 22.7;
  static const vipBadgeHeight = 10.3;
  static const vipBadgeFont = 7.0;
  static const vipBadgeX = 8.7;
  static const vipBadgeY = -9.2;
  static const vipBadgeBorder = Color(0xD9FFFFFF);
  static const vipBadgeBorderWidth = 0.5;

  /// The tick on the chosen swatch: a pink 11 pt disc in a white ring over its bottom right corner.
  static const tickSize = 11.0;
  static const tickRing = 1.0;
  static const tickOffset = 0.5;
  static const tickStroke = 1.1;
  static const tickColour = Color(0xFFFFFFFF);
}

/// 当前弹幕列表 (31, 32). Positions across the row count from the panel's content edge, [BiliMetrics.panelTrailing]
/// before the safe area.
abstract final class DanmakuListTheme {
  /// A one-line row is 49 tall; longer text grows it by whole lines, the same 16.3 above and below.
  static const rowPadY = 49 / 3;
  static const rowMinHeight = 49.0;
  static const text = 14.0;
  static const textLine = 49 / 3;
  static const textColor = Color(0xFFFFFFFF);

  /// Between the text's widest and the 👍's box: 31's long danmaku wraps after 15 characters.
  static const textGap = 12.0;

  /// The 👍's ink is 16.5 square (an action icon's ink spans 0.84 of its box), centred 54 in from the
  /// content's edge.
  static const thumbIcon = 16.5 / 0.84;
  static const thumbCentre = 54.0;
  static const thumbTarget = 40.0;

  /// 31's 👍 sits 2 px above the row's middle.
  static const thumbRise = 2 / 3;
  static const thumb = Color(0xFFFFFFFF);
  static const liked = BiliColors.pink;

  /// The count sits off the 👍's top right: its left 1.5 past the ink, its middle 9 above the row's.
  static const countText = 10.0;
  static const countGap = 1.5;
  static const countRise = 9.0;

  static const dividerCentre = 28.8;
  static const dividerWidth = 2 / 3;
  static const dividerHeight = 16.0;
  static const divider = Color(0xFF2F3237);

  /// ⋮: three 8 px dots 16 px apart, centred 3.8 in from the content's edge.
  static const moreCentre = 3.8;
  static const moreDot = 8.6 / 3;
  static const morePitch = 16 / 3;
  static const more = Color(0xFFFFFFFF);

  /// While the popover is up, the other rows fade (32's white text reads 140).
  static const dimmed = 0.53;

  /// 32's popover, one 60.3 wide cell (we offer no 举报): its right edge on the safe area, the arrow under ⋮.
  static const popoverCell = 60.3;
  static const popoverPadX = 7.5;
  static const popoverHeight = 67.3;
  static const popoverRadius = 9.0;
  static const popoverFill = Color(0xF72C2F33);
  static const popoverArrowWidth = 12.0;
  static const popoverArrowHeight = 7.7;

  /// The arrow's tip rises this far into the row above it.
  static const popoverOverlap = 4.0;
  static const popoverIconWidth = 22.0;
  static const popoverIconHeight = 17.8;
  static const popoverIconStroke = 1.3;
  static const popoverIconCentre = 26.0;
  static const popoverLabelCentre = 49.0;
  static const popoverText = 10.0;
  static const popoverInk = Color(0xFFFFFFFF);

  static const emptyColor = BiliColors.panelSecondary;

  static TextStyle get textStyle => TextStyle(
    fontFamily: BiliFonts.family,
    fontSize: text,
    height: textLine / text,
    color: textColor,
    decoration: TextDecoration.none,
  );

  static TextStyle countStyle(Color color) => TextStyle(
    fontFamily: BiliFonts.family,
    fontSize: countText,
    height: 1,
    color: color,
    decoration: TextDecoration.none,
  );

  static TextStyle get popoverStyle => TextStyle(
    fontFamily: BiliFonts.family,
    fontSize: popoverText,
    height: 1,
    color: popoverInk,
    decoration: TextDecoration.none,
  );
}

/// 开发者's log tools, in the dev page's own style (no official screen shows it).
abstract final class DevToolsTheme {
  static const crashInk = BiliColors.failure;

  /// Between the log card and the note under it.
  static const footnoteGap = BiliMetrics.rowGap;
}

/// 历史记录 (28).
abstract final class HistoryTheme {
  /// The title bar under the status bar, measured on 45 at 3 px per pt: ‹ is #484C52, 7 × 15 with 1.5 strokes, its
  /// tip 26.7 in; 历史记录 is bold and centred. The 🔍, ⋮ and the tab row are left out, so the hairline that ends the
  /// tab row ends the bar.
  static const barHeight = 44.0;
  static const barHairline = 1 / 3;
  static const backTarget = 44.0;
  static const backTipX = 27.0;
  static const backWidth = 7.0;
  static const backHalfHeight = 7.35;
  static const backStroke = 1.4;
  static const backDrop = -0.33;
  static const back = Color(0xFF484C52);
  static const titleText = 20.0;
  static const titleWeight = FontWeight.w600;

  /// Every other word on the page and its sheet is regular (45, 47, 48).
  static const textWeight = FontWeight.w400;

  /// MiSans sets 历史记录 1 pt lower in the bar than 45's.
  static double get titleDrop => BiliFonts.nudged ? -1 : 0;

  /// 今天, 昨天 and 更早: 46 tall, pinned while their rows scroll under them.
  static const headerHeight = 46.0;
  static const headerText = 16.0;
  static const headerInset = 12.0;

  /// Where the title's box starts, which puts its ink 21.3 below the header's top as on 45.
  static const headerTextTop = 20.5;

  /// A row is 100: the 136 × 76 cover 12 down, then a hairline (none after a section's last row) from the gutter
  /// to the right edge.
  static const rowHeight = 100.0;
  static const rowPadTop = 12.0;
  static const gutter = 12.0;
  static const coverWidth = 136.0;
  static const coverHeight = 76.0;
  static const coverRadius = 14 / 3;
  static const textGap = 9.0;
  static const hairline = 1 / 3;
  static const divider = BiliColors.divider;

  /// The title: two lines 19.3 apart.
  static const rowTitleText = 14.0;
  static const rowTitleLine = 58 / 3;
  static const rowTitleTop = -1.27;

  /// Where a title wraps: 45's lines end past 420.4 but never reach 422.
  static const titleRight = 18.0;
  static const rowTitle = BiliColors.text;

  /// The UP and device lines, their ink ending level with the cover's bottom.
  static const metaText = 12.0;
  static const metaLine = 16.0;
  static const metaGap = 2.3;
  static const metaBottom = 1.6;

  /// MiSans digits are narrower than PingFang's, so the time would end 9 pt short of 45's.
  static double get timeSpacing => BiliFonts.nudged ? 0.55 : 0;
  static const meta = BiliColors.secondaryText;
  static const glyphBox = 41 / 3;
  static const glyphGap = 3.3;
  static const glyphStroke = 1.0;

  /// The UP glyph's frame and letters.
  static const upWidth = 13.0;
  static const upHeight = 11.2;
  static const upRadius = 2.7;
  static const upLetterWidth = 3.5;
  static const upLetterHeight = 5.0;
  static const upDrop = 0.5;

  /// The PC's screen and stand, and the phone with its notch and bar.
  static const pcWidth = 13.2;
  static const pcHeight = 9.5;
  static const pcRadius = 2.3;
  static const pcBaseWidth = 5.8;
  static const pcStand = 2.0;
  static const phoneWidth = 8.7;
  static const phoneHeight = 12.0;
  static const phoneRadius = 2.3;
  static const phoneNotch = 3.0;
  static const phoneBar = 2.0;
  static const phoneMark = 1.2;
  static const pcStandStroke = 1.6;

  /// ⋮: three 2 pt dots 4.3 apart, centred 20 from the right and on the device line.
  static const moreDot = 2.0;
  static const morePitch = 13 / 3;
  static const moreCentreRight = 20.0;
  static const moreTarget = 44.0;
  static const more = Color(0xFFC9CCCF);

  /// The time on the cover: a 14 tall pill of half black, 3.7 from the right and 4 from the bottom.
  static const pillText = 11.0;

  /// MiSans digits stand taller and wider than the official app's; this size matches 45's ink.
  static double get pillFont => BiliFonts.nudged ? 10.5 : pillText;
  static const pillHeight = 14.0;
  static const pillPadX = 14 / 3;
  static const pillRight = 11 / 3;
  static const pillBottom = 4.0;
  static const pillRadius = 2.0;
  static const pillFill = BiliColors.coverShade;
  static const pillInk = BiliColors.onCover;

  /// The pink line along the cover's bottom; a few seconds in still shows this much of it.
  static const progressHeight = 2.0;
  static const progressMin = 23 / 3;
  static const progress = Color(0xFFEA6E96);

  /// The page's own states: logged out, empty, failed.
  static const stateText = 15.0;
  static const stateGap = 16.0;
  static const stateInk = BiliColors.secondaryText;
  static const loginText = 15.0;
  static const loginHeight = 36.0;
  static const loginPadX = 36.0;
  static const retryText = 14.0;
  static const retryPadX = 20.0;
  static const retryHeight = 30.0;
  static const buttonWeight = FontWeight.w500;
  static const footerText = 12.0;
  static const footerPad = 16.0;
  static const footerInk = Color(0xFFC9CCD0);
  static const spinnerRadius = 10.0;

  /// ⋮'s sheet (48): the page dimmed to 30 %, a white sheet 291 tall over the home indicator's inset.
  static const sheetDim = Color(0xB3000000);
  static const sheetIn = Duration(milliseconds: 280);
  static const sheetOut = Duration(milliseconds: 220);
  static const sheetFill = BiliColors.card;
  static const sheetHeaderHeight = 44.0;
  static const sheetHeaderText = 14.0;
  static const sheetHeaderInset = 12.7;
  static const sheetHeaderInk = Color(0xFF505050);
  static const sheetItemCentre = 33.0;
  static const sheetCircle = 44.0;
  static const sheetCircleFill = BiliColors.pink;
  static const sheetCircleGlyph = BiliColors.onPink;
  static const sheetShareGlyphWidth = 17.0;
  static const sheetShareGlyphHeight = 20.0;
  static const sheetShareStroke = 1.6;
  static const sheetLabelText = 12.0;
  static const sheetLabelGap = 6.0;
  static const sheetLabelInk = Color(0xFF999999);
  static const sheetItemWidth = 66.0;
  static const sheetShareBottom = 127.0;
  static const sheetDivider = 1.0;
  static const sheetDividerInk = BiliColors.divider;

  /// 删除: the trash glyph centred 42 below the divider, its label under it.
  static const sheetDeleteHeight = 102.7;
  static const sheetTrashWidth = 30.0;
  static const sheetTrashHeight = 28.0;
  static const sheetTrashTop = 28.0;
  static const sheetTrashStroke = 1.5;
  static const sheetDeleteLabelGap = 14.2;
  static const sheetDeleteInk = Color(0xFF61666D);
  static const sheetBand = 16 / 3;
  static const sheetBandFill = Color(0xFFF4F4F4);
  static const sheetCancelHeight = 55.0;
  static const sheetCancelText = 16.0;
  static const sheetCancelInk = Color(0xFF505050);

  /// MiSans sets its text higher in the line than PingFang; this brings the sheet's words level with 48's.
  static double get sheetTextDrop => BiliFonts.nudged ? 1.5 : 0;
}

/// The login page and its bar.
abstract final class LoginTheme {
  /// No official screenshot shows this frame: it keeps 设置's white bar, and Bilibili's own page fills the rest.
  static const bar = BiliColors.card;
  static const page = BiliColors.card;
  static const title = BiliColors.text;
  static const titleText = BiliMetrics.titleText;

  /// The ✕ that closes the page, in a 44 pt target.
  static const close = BiliColors.text;
  static const closeIcon = 24.0;
  static const closeTarget = 44.0;

  static const spinnerRadius = 14.0;

  /// 请在手机上登录, a load error or a login that didn't take, with 重试 under the last two.
  static const message = BiliColors.secondaryText;
  static const messageText = BiliMetrics.bodyText;
  static const inset = BiliMetrics.sectionGap;
  static const gap = BiliMetrics.rowGap;
  static const retry = BiliColors.pink;
  static const retryHeight = BiliMetrics.pillHeight;
  static const retryPadX = BiliMetrics.sectionGap;

  static TextStyle get titleStyle => TextStyle(fontFamily: BiliFonts.family, fontSize: titleText, color: title);

  static TextStyle get messageStyle => TextStyle(fontFamily: BiliFonts.family, fontSize: messageText, color: message);

  static TextStyle get retryStyle => TextStyle(fontFamily: BiliFonts.family, fontSize: messageText, color: retry);
}

/// 设置's sections beyond 字体, and its confirms: 50 and 51, measured at 3 px per pt.
abstract final class SettingsTheme {
  /// The white bar under the status bar, its bold title and the ‹ whose ink starts 79 px in.
  static const bar = BiliColors.card;
  static const barHeight = 44.0;
  static const barTitleText = 20.0;
  static const barTitleWeight = FontWeight.w600;
  static const barTitle = BiliColors.text;

  /// MiSans sits lower than 50's PingFang: the bar's title rides up 1.5 px and the rows' titles 2.5 px.
  static double get barTitleDrop => BiliFonts.nudged ? -1.5 / 3 : 0;
  static double get rowTitleDrop => BiliFonts.nudged ? -2.5 / 3 : 0;
  static const backLeft = 79 / 3;
  static const backGlyphWidth = 25 / 3;
  static const backGlyphHeight = 47 / 3;
  static const backStroke = 1.6;
  static const backGlyph = Color(0xFF484C53);
  static const backTarget = 44.0;

  static const page = BiliColors.pageGrey;
  static const row = BiliColors.card;
  static const rowTitleText = 16.0;
  static const rowTitle = BiliColors.text;
  static const rowDisabled = BiliColors.secondaryText;
  static const value = BiliColors.secondaryText;

  /// The titles and the hairlines under every row, the last included, start 15 pt in; a full-width one tops each
  /// section.
  static const rowInset = 15.0;
  static const hairline = 1 / 3;
  static const hairlineColor = BiliColors.divider;

  /// The grey ›'s ink ends 48 px from the right, the value's 24 px before it.
  static const chevronWidth = 20 / 3;
  static const chevronHeight = 12.0;
  static const chevronStroke = 2.5 / 3;
  static const chevronRight = 47 / 3;
  static const chevron = BiliColors.secondaryText;
  static const valueGap = 7.0;

  /// The BTR 加速 switch, the light sheets' shape.
  static const switchRight = 16.0;
  static const switchOn = BiliColors.pink;
  static const switchOff = FavouriteTheme.switchOffLight;
  static const switchKnob = BiliColors.panelKnob;
  static const switchKnobShadow = FavouriteTheme.knobShadow;
  static const switchKnobShadowBlur = FavouriteTheme.knobShadowBlur;
  static const switchMotion = Duration(milliseconds: 200);

  /// Grey notes under a section: CDN 节点's and the BTR licence.
  static const footerText = 12.0;
  static const footer = BiliColors.secondaryText;
  static const footerTop = 8.0;
  static const footerBottom = 4.0;

  /// 51's alert: 280 pt wide with 8 pt corners over a 70% dim, the title's middle 35.8 pt down, the grey line's
  /// 74.4 pt, a 2 px rule 28 pt below that, and two 44 pt buttons with no rule between them.
  static const confirmWidth = 280.0;
  static const confirmRadius = 8.0;
  static const confirmDim = Color(0xB3000000);
  static const confirm = BiliColors.card;
  static const confirmTitleText = 16.0;
  static const confirmTitleLine = 22.0;
  static const confirmTitleWeight = FontWeight.w500;
  static const confirmTitle = BiliColors.text;
  static const confirmTitleTop = 35.8 - confirmTitleLine / 2;
  static const confirmMessageText = 13.0;
  static const confirmMessageLine = 18.0;
  static const confirmMessage = BiliColors.secondaryText;
  static const confirmMessageGap = 74.4 - 35.8 - (confirmTitleLine + confirmMessageLine) / 2;
  static const confirmMessageBottom = 28.0 - confirmMessageLine / 2;
  static const confirmSide = 20.0;
  static const confirmRule = 2 / 3;
  static const confirmRuleColor = BiliColors.divider;
  static const confirmButtonHeight = 44.0;
  static const confirmButtonText = 16.0;
  static const confirmCancel = BiliColors.text;
  static const confirmAction = BiliColors.pink;
  static const confirmPressed = BiliColors.pressedFill;
  static const confirmPressMotion = Duration(milliseconds: 120);

  /// It comes and goes as the other alerts do, settling from slightly large.
  static const confirmIn = CommentOverlayTheme.confirmIn;
  static const confirmOut = CommentOverlayTheme.confirmOut;
  static const confirmStartScale = FavouriteTheme.alertStartScale;

  /// 大会员 on the 账号 row: the name in pink and the avatar menu's pink pill after it.
  static const vipName = BiliColors.pink;
  static const vipBadge = BiliColors.pink;
  static const vipBadgeLabel = BiliColors.card;
  static const vipBadgePadding = 6.0;
  static const vipBadgeGap = 6.0;
}

/// 首页's bottom bar (01, 02): its height over the home indicator, the hairline above it, the labels.
abstract final class HomeTabBarTheme {
  static const bar = BiliColors.card;

  /// 49 pt from the hairline's top to the home indicator's safe area, in five slots of a fifth of the width each.
  static const height = 49.0;
  static const hairline = BiliColors.divider;
  static const hairlineWidth = 1 / 3;

  /// Below the bar's top: a glyph's centre, the pink +'s (centred under the hairline) and a label's line box top.
  static const iconCentre = 18.0;
  static const postCentre = 74 / 3;
  static const labelTop = 94 / 3;
  static const labelText = 11.0;
  static const label = Color(0xFF61666D);
  static const selected = BiliColors.pink;

  /// 首页's search entry beside the avatar (01): 300 pt of the row, ending 76 pt short of the screen's edge, in a
  /// 2 px grey outline; the magnifier's centre and the word's start from the outline's left edge, the word cut
  /// short of the right one.
  static const fieldGap = 11.0;
  static const fieldWidth = 300.0;
  static const fieldOutline = BiliColors.secondaryText;
  static const fieldOutlineWidth = 2 / 3;
  static const fieldGlyph = SearchGlyphTheme.magnifierSize;
  static const fieldGlyphCentre = 18.0;
  static const fieldGlyphRise = 1 / 3;
  static const fieldTextStart = 89 / 3;
  static const fieldTextEnd = 14.0;
  static const fieldText = 15.0;
  static const fieldInk = Color(0xFF61666D);

  /// The 推荐 refresh 首页's tap runs: the scroll back to the top, then the pull-to-refresh TV's room opening.
  static const reloadScroll = Duration(milliseconds: 300);
  static const reloadHeader = Duration(milliseconds: 200);
}

/// The bottom bar's glyphs (01, 02): their size, strokes and colours, and the + on its pink rounded square.
abstract final class TabIconTheme {
  /// The square each line glyph is drawn in. On 01 and 02 every glyph's ink is centred on its column (88 pt wide) at
  /// y 891 pt; the widest, 关注 and 我的, are 21.33 pt.
  static const size = 22.0;

  static const ink = Color(0xFF61666D);
  static const selectedInk = BiliColors.pink;

  /// Outlines; 关注's pinwheel is a touch heavier on both shots.
  static const line = 2.0;
  static const fanLine = 2.1;

  /// 首页's smile or mouth, 我的's eyes and antennae.
  static const faceLine = 1.5;

  /// 发布: a 38 pt square (centred at y 897.67 pt on 01, its top at 878.67) with 14 pt corners, shaded top to bottom,
  /// and a white + 13 pt across with 2.5 pt round-capped strokes.
  static const postSquare = 38.0;
  static const postRadius = 14.0;
  static const postTop = Color(0xFFFE739A);
  static const postBottom = Color(0xFFFF4AA4);
  static const postPlus = 13.0;
  static const postPlusLine = 2.5;
  static const postPlusInk = Color(0xFFFFFFFF);
}

/// 搜索's page (52-55): the field row, the empty page's 热搜, 搜索历史 and 搜索发现, and the suggestions.
abstract final class SearchTheme {
  static const page = BiliColors.card;

  /// Measured on 52-55 at 3 px per pt. Every word on the page is #18191C; the field's grey word, ‹ and 反馈 are
  /// #61666D, the sections' glyphs and 完整榜单 #9499A0.
  static const text = BiliColors.text;
  static const dim = Color(0xFF61666D);
  static const grey = BiliColors.secondaryText;
  static const highlight = BiliColors.pink;

  /// The row under the status bar: ‹ (8.7 × 16.7, its middle 19 in), the 34 tall stadium from 38 to 376 with its
  /// 0.67 grey rim drawn over it (insetting nothing), and 搜索 centred in the 64 after it. The magnifier's ink is
  /// centred 56 in and half a point above the field's middle (its box raised 2/3, as its ink sits low in it); the
  /// word's box starts at 68.
  static const barHeight = 44.0;
  static const backTarget = 38.0;
  static const backWidth = 26 / 3;
  static const backHeight = 50 / 3;
  static const backStroke = 1.5;
  static const fieldHeight = 34.0;
  static const fieldRim = 0.67;
  static const fieldRimColor = BiliColors.secondaryText;
  static const fieldText = 15.0;
  static const fieldLine = 21.0;
  static const magnifierInset = 35 / 3;
  static const magnifier = SearchGlyphTheme.magnifierSize;
  static const magnifierLift = 2 / 3;
  static const magnifierGap = 6.0;
  static const caret = BiliColors.pink;

  /// The grey ⓧ: 13.3 across, its middle 18 from the field's right end, in a 36 wide target.
  static const clear = 40 / 3;
  static const clearColor = Color(0xFFC9CCCF);
  static const clearRight = 18.0;
  static const submitWidth = 64.0;
  static const submitText = 16.0;
  static const submitDrop = 0.5;
  static const submit = BiliColors.pink;

  /// The opening spinner over the page, as 首页's.
  static const openingFill = BiliColors.toastFill;
  static const openingSpinner = BiliColors.panelText;

  /// The empty page's sections: a 14 pt medium title whose middle is 17 down a 34 tall header, its glyphs centred
  /// 73 and 20 (⌄) or 26 (👁) from the right edge with a 1 px #C9CCD0 rule 46.5 in between. Each glyph is pressed in
  /// a 44 wide target. 🗑's box is raised 2/3 and ⌃'s 5/6, where their ink would otherwise sit low (53, 54).
  static const gutter = 12.0;
  static const headerHeight = 34.0;
  static const headerText = 14.0;
  static const headerWeight = FontWeight.w500;
  static const headerLine = 20.0;
  static const headerFirstGlyph = 73.0;
  static const headerRule = 46.5;
  static const headerExpandGlyph = 20.0;
  static const headerEyeGlyph = 26.0;
  static const headerGlyphTarget = 44.0;
  static const trashLift = 2 / 3;
  static const collapseLift = 5 / 6;
  static const ruleWidth = 1 / 3;
  static const ruleHeight = 8.0;
  static const rule = Color(0xFFC9CCD0);
  static const trash = 40 / 3;
  static const expand = 12.0;
  static const refresh = 40 / 3;
  static const eye = 46 / 3;

  /// The words in the sections and the suggestions: 14 pt on a 20 pt line.
  static const wordText = 14.0;
  static const wordLine = 20.0;

  /// bilibili热搜: 1/3 below the bar, then rows 34 tall in two 196 wide columns 24 apart, each word's 14 pt badge 4
  /// after it. 完整榜单 is 12 pt with a 5.3 × 9.3 › 4 after it, ending 15.3 from the right.
  static const hotTop = 1 / 3;
  static const hotRowHeight = 34.0;
  static const hotColumnGap = 24.0;
  static const hotWords = 10;
  static const badge = 14.0;
  static const badgeGap = 4.0;
  static const moreText = 12.0;
  static const moreGap = 4.0;
  static const moreChevronWidth = 16 / 3;
  static const moreChevronHeight = 28 / 3;
  static const moreChevronStroke = 1.2;
  static const moreRight = 46 / 3;

  /// The gap after 热搜's rows, and after the chips or cells of the other sections, before the next title's header.
  static const afterHot = 12.0;
  static const afterList = 61 / 3;

  /// Between a header and its chips or cells.
  static const listTop = 8 / 3;

  /// 搜索历史's chips: 30 tall, 14 in on both sides, 10 apart and 8 between rows, 4 corners; a word is cut with … at
  /// 117 (the chip at 145). Folded it shows two rows (52, 53).
  static const chipHeight = 30.0;
  static const chipPadding = 14.0;
  static const chipSpacing = 10.0;
  static const chipRunSpacing = 8.0;
  static const chipRadius = 4.0;
  static const chipTextMax = 117.0;
  static const chipFill = BiliColors.softGrey;
  static const foldedRows = 2;
  static const historyMotion = Duration(milliseconds: 250);

  /// 搜索发现's cells: two columns 7 apart, 30 tall, 8 between rows, the word 8 in.
  static const cellHeight = 30.0;
  static const cellGap = 7.0;
  static const cellRunSpacing = 8.0;
  static const cellPadding = 8.0;
  static const cellRadius = 4.0;
  static const cellFill = BiliColors.softGrey;
  static const discoveryWords = 12;

  /// A 搜索发现 word's grey "·昨天更新" (52's first cell).
  static const suffix = grey;

  /// The 反馈 pill, 28 under the last cell: 66 × 24 with a 0.67 #C9CCD0 rim, its 14 pt glyph 3 before the 12.5 pt
  /// word.
  static const feedbackTop = 28.0 - afterList;
  static const feedbackWidth = 66.0;
  static const feedbackHeight = 24.0;
  static const feedbackRim = 0.67;
  static const feedbackGlyph = 14.0;
  static const feedbackGap = 3.0;
  static const feedbackText = 12.5;
  static const feedbackBottom = 24.0;
  static const feedbackPressedScale = IntroTheme.followPressedScale;

  /// The pressed 反馈 pill shrinking; chips, cells and words darken with [BiliColors.pressedFill] instead.
  static const pressMotion = Duration(milliseconds: 120);

  /// The suggestions (55): rows 44 tall, each ending in a 1 px #D9DBDE hairline from the gutter to the right edge.
  static const suggestionHeight = 44.0;
  static const suggestionHairline = 1 / 3;
  static const suggestionHairlineColor = Color(0xFFD9DBDE);
}

/// 搜索's results (56, 57, 59-61): the tab row, the video and uploader rows, the ⋮ sheet.
abstract final class SearchResultTheme {
  static const page = BiliColors.card;

  /// The tab row: 40 under the field row (which ends 106 down, where 55's suggestions start), then a hairline across
  /// the page, lighter than the rows' own. Labels sit in 54 wide slots from the left edge, the shown one 16 and pink,
  /// the others 15 and grey, all on one baseline.
  static const tabRowHeight = 40.0;
  static const hairline = 1 / 3;
  static const hairlineInk = Color(0xFFE3E5E7);
  static const rowHairlineInk = Color(0xFFD9DBDE);
  static const tabSlot = 54.0;
  static const tabText = 15.0;
  static const tabSelectedText = 16.0;
  static const tabBaseline = 77 / 3;
  static const tabInk = Color(0xFF61666D);
  static const tabSelected = BiliColors.pink;
  static const indicatorWidth = 18.0;
  static const indicatorHeight = 3.0;
  static const indicatorTop = 34.0;
  static const tabMotion = Duration(milliseconds: 200);

  /// 筛选's funnel, centred 26 from the right edge and 19.5 down the tab row; pink while 筛选 is open (58).
  static const funnel = 52 / 3;
  static const funnelCentreRight = 26.0;
  static const funnelCentreTop = 19.5;
  static const funnelTarget = 44.0;
  static const funnelInk = tabInk;
  static const funnelOpen = BiliColors.pink;

  /// 用户's 默认排序 and 全部用户 (60), each centred in half the width; on 用户 the hairline runs under this row, not the
  /// tab row.
  static const sortRowHeight = 119 / 3;
  static const sortText = 13.0;
  static const sortInk = tabInk;
  static const sortChevronWidth = 8.0;
  static const sortChevronHeight = 4.4;
  static const sortChevronStroke = 1.1;
  static const sortChevronGap = 4.3;

  /// Rows scrolled this close to the end ask for the next page.
  static const loadAhead = 360.0;

  /// A video row (56, 61): the 172 × 97 cover 12 down, 11.67 under it to the hairline, which runs from the gutter to
  /// the right edge.
  static const gutter = 12.0;
  static const rowPadTop = 12.0;
  static const rowPadBottom = 35 / 3;
  static const coverWidth = 172.0;
  static const coverHeight = 97.0;
  static const coverRadius = 13 / 3;
  static const coverPlaceholder = BiliColors.pageGrey;
  static const textGap = 8.0;

  /// Two title lines 19.33 apart, their first ink 3.3 under the cover's top; they wrap before 422.
  static const titleText = 14.0;
  static const titleLine = 58 / 3;
  static const titleTop = 0.0;
  static const titleRight = 18.0;
  static const titleInk = BiliColors.text;
  static const highlight = BiliColors.pink;

  /// UP and ▷ lines, ink centred 27.33 and 8.5 above the cover's bottom; both glyphs start 1.33 into their 13.67
  /// slot, ▷ 12.67 wide.
  static const metaText = 12.0;
  static const metaLine = 17.0;
  static const metaGap = 2.2;
  static const metaBottom = -0.2;
  static const metaInk = BiliColors.secondaryText;
  static const metaGlyphSlot = 41 / 3;
  static const metaGlyphInset = 4 / 3;
  static const metaGlyph = 38 / 3;
  static const metaGlyphGap = 4.0;

  /// The · between counts has 6.67 clear on each side (56, 60): a space and this much more.
  static const dotSpacing = 5 / 3;

  /// ⋮, centred 16 from the right edge on the ▷ line.
  static const moreCentreRight = 16.0;
  static const moreTarget = 32.0;

  /// The length on the cover: a 14 tall pill 4 in from its right and bottom.
  static const durationText = 10.0;
  static const durationHeight = 14.0;
  static const durationPadX = 8 / 3;
  static const durationRight = 4.0;
  static const durationBottom = 4.0;
  static const durationRadius = 3.0;
  static const durationFill = Color(0x99000000);
  static const durationInk = BiliColors.onCover;

  /// An uploader row (60): 80 with its hairline, inset 12 at both ends; the 48 avatar 16 down, the text 8 after it.
  static const userRowHeight = 80.0;
  static const avatar = 48.0;
  static const avatarTop = 16.0;
  static const userTextGap = 8.0;
  static const nameText = 14.0;
  static const nameInk = BiliColors.text;
  static const nameLine = 20.0;
  static const levelGap = 5.0;
  static const countsText = 12.0;
  static const countsLine = 17.0;
  static const countsInk = BiliColors.secondaryText;

  /// Where each line centres from the avatar's centre, with the counts alone or with the description under them.
  static const nameCentreTwo = -11.17;
  static const countsCentreTwo = 13.0;
  static const nameCentreThree = -18.67;
  static const countsCentreThree = 1.33;
  static const descCentreThree = 20.33;

  /// The bolt disc at the avatar's lower right, ringed in white: yellow for a person, blue for an organisation.
  static const badge = 40 / 3;
  static const badgeRing = 4 / 3;
  static const badgePerson = IntroTheme.badgePerson;
  static const badgeOrganisation = IntroTheme.badgeOrganisation;
  static const badgeBolt = IntroTheme.badgeBolt;

  /// "+ 关注": the pink pill 12 from the right, level with the avatar; followed, 简介's grey 已关注.
  static const followWidth = 70.0;
  static const followHeight = 24.0;
  static const followText = 13.0;
  static const followPlus = 29 / 3;
  static const followPlusStroke = 1.2;
  static const followPlusGap = 13 / 3;
  static const followFill = BiliColors.pink;
  static const followInk = BiliColors.onPink;
  static const followedFill = IntroTheme.followedFill;
  static const followedInk = IntroTheme.followedText;
  static const followPressedScale = IntroTheme.followPressedScale;

  /// 简介's: the fill and words change over [followMotion], the label fading in from [followSwapScale]; a press
  /// shrinks the pill over [followPressMotion].
  static const followMotion = Duration(milliseconds: 220);
  static const followPressMotion = Duration(milliseconds: 120);
  static const followSwapScale = 0.85;
  static const textRight = 12.0;

  /// The next page's spinner, 重试 and 没有找到相关内容.
  static const stateText = 14.0;
  static const stateInk = BiliColors.secondaryText;
  static const stateGap = 16.0;
  static const spinnerRadius = 10.0;
  static const footerPad = 16.0;
  static const retryText = 14.0;
  static const retryHeight = 30.0;
  static const retryPadX = 20.0;
  static const retryRim = 1.0;

  /// Let go with the header part shown, it finishes coming in or going out, whichever is nearer.
  static const headerSnap = Duration(milliseconds: 200);

  /// 筛选's dim over the rows only (58).
  static const filterDim = Color(0x4D000000);
  static const filterMotion = Duration(milliseconds: 220);

  /// ⋮'s sheet (59): the page dimmed, the soft-grey sheet rising to 411.33 tall from the screen's bottom with a 12
  /// corner, white cards 16 in.
  static const sheetDim = Color(0x52000000);
  static const sheetIn = Duration(milliseconds: 280);
  static const sheetOut = Duration(milliseconds: 220);
  static const sheetFill = BiliColors.softGrey;
  static const sheetRadius = 12.0;
  static const sheetInset = 16.0;
  static const grabberTop = 8.0;
  static const grabberWidth = 30.0;
  static const grabberHeight = 3.0;
  static const grabberInk = Color(0xFFC5C6C6);
  static const sheetCardTop = 19.0;
  static const sheetCardHeight = 137 / 3;
  static const sheetCardRadius = 6.0;
  static const sheetCardFill = BiliColors.card;
  static const sheetIcon = 18.0;
  static const sheetIconLeft = 13.0;
  static const sheetIconGap = 9.0;
  static const sheetText = 18.0;
  static const sheetInk = BiliColors.text;
  static const sheetHeaderText = 55 / 3;

  /// The words on the sheet's cards sit this much lower in their boxes than the stand-ins put them (59).
  static const sheetTextDrop = 2 / 3;
  static const sheetHeaderWeight = FontWeight.w600;

  /// A heading's block runs from the card above to its buttons, the words centred 32.67 down it.
  static const sheetHeaderBlock = 172 / 3;
  static const sheetHeaderCentre = 98 / 3;
  static const sheetButtonHeight = 44.0;
  static const sheetButtonGap = 8.0;
  static const sheetBottom = 6.0;

  /// Dragged down this far, or flung, the sheet closes.
  static const sheetDragClose = 0.25;
  static const sheetFlingClose = 700.0;
}

/// 筛选 (58): its chip rows and the dimmed list under it.
abstract final class SearchFilterTheme {
  static const panel = BiliColors.card;

  /// 58's rhythm: the first title's middle 20 below the panel's top, each title's middle 18.67 above its chips and
  /// 24.33 below the chips before it. 58 cuts the panel off under a fade at 450 pt, so the bottom is the space a chip
  /// grid leaves above the next title's ink.
  static const side = BiliMetrics.gutter;
  static const firstTitleMiddle = 20.0;
  static const titleToChips = 56 / 3;
  static const chipsToTitle = 73 / 3;
  static const bottom = 56 / 3;

  static const titleText = 12.0;
  static const title = BiliColors.text;

  /// Four to a row, 99 wide at 440 pt: 58 floors the width to a whole point, leaving 14 on the right.
  static const columns = 4;
  static const chipHeight = 26.0;
  static const chipGap = 6.0;
  static const chipRowGap = 10.0;
  static const chipRadius = 4.0;
  static const chipText = 12.0;

  /// 58 draws 内容时长's digits a pixel further apart than SF and a point further from Chinese; Flutter's SF draws
  /// neither.
  static double get chipLatinSpacing => BiliFonts.nudged ? 0 : 1 / 3;
  static double get chipHanGap => BiliFonts.nudged ? 0 : 1.0;

  /// The chosen chip keeps the same grey; only its label turns the deeper pink of the comment composer's accent.
  static const chip = BiliColors.softGrey;
  static const chipLabel = Color(0xFF62666C);
  static const chipChosenLabel = Color(0xFFED7098);
}

/// 搜索's glyphs (52-60): their strokes.
abstract final class SearchGlyphTheme {
  static const stroke = 1.0;

  /// Each glyph's ink box, the larger side, measured at 3 px per pt: pass it as the icon's size. Strokes below are at
  /// these sizes and scale with them.
  static const magnifierSize = 12.33;
  static const clearSize = 13.33;
  static const trashSize = 13.33;
  static const expandSize = 12.0;
  static const refreshSize = 13.33;
  static const eyeSize = 15.33;
  static const feedbackSize = 14.0;
  static const chevronSize = 9.33;
  static const funnelSize = 16.67;
  static const playSize = 13.33;
  static const plusSize = 9.33;
  static const watchLaterSize = 18.0;

  static const magnifierStroke = 1.5;
  static const clearStroke = 1.1;
  static const funnelStroke = 1.3;
  static const plusStroke = 1.1;
  static const watchLaterStroke = 1.2;
}

/// The official app's loading TV (14, 64, 67).
abstract final class LoadingTvTheme {
  static const size = 60.0;
  static const frame = Duration(milliseconds: 133);

  /// 正在努力加载... under the TV on a page's first load (64, 67).
  static const stateText = 14.0;
  static const stateInk = Color(0xFF86898B);

  /// From the TV's box to the text's line box.
  static const stateGap = 6.0;

  /// From the top of a list's area (under 搜索's field row, 历史记录's title bar) to the TV's box (67).
  static const stateTop = 892 / 3;
}

/// The player's 正在缓冲... with its pink TV (65, 66), measured in px / 3: the TV's ink is 64 × 60 px, the Lottie's
/// 24 pt design at 1:1, centred on the video box's centre in both presentations; the line is 14 pt regular white
/// (CJK pitch 40-43 px, digits 30 px tall), with no shadow, its baseline 21.3 pt below the TV's box.
abstract final class PlayerLoadingTheme {
  static const tvSize = 24.0;
  static const text = 14.0;
  static const ink = BiliColors.onVideo;

  /// From the TV's box to the line's box: the system font's baseline lands where the recordings have it.
  static const gap = 6.5;

  /// A wait for data shorter than this shows nothing: the controller's 卡顿 line (`StallFilter.afterMs`), so the TV
  /// shows for exactly the waits the app counts as stalls or slow seeks.
  static const grace = Duration(milliseconds: 750);
}

/// The uploader sheet over the video page's body (62, 68, 76), measured on 68 and 76 at 3 px per pt from the sheet's
/// top, which meets the player box's bottom.
abstract final class UploaderSheetTheme {
  static const fill = BiliColors.card;
  static const radius = 12.0;
  static const grabberTop = 8.0;
  static const grabberWidth = 30.0;
  static const grabberHeight = 3.0;
  static const grabber = BiliColors.sheetGrabber;

  static const rise = Duration(milliseconds: 300);
  static const fall = Duration(milliseconds: 220);

  /// Let go dragged down past this share of its height, or flung faster than [flingClose] points a second, the sheet
  /// closes; short of both it springs back over [dragBack].
  static const dragClose = 0.25;
  static const flingClose = 700.0;
  static const dragBack = Duration(milliseconds: 200);

  /// An edge swipe closes it as one closes 评论详情.
  static const edgeCloseShare = CommentOverlayTheme.threadCloseShare;
  static const edgeFlingWidths = CommentOverlayTheme.threadFlingWidths;

  /// The header: the face 16 in and 31 down, the name and its pill on a line centred 35.33 down, the counts on one
  /// 62 down, both 12 after the face; 进入空间 › centred 44 down, its chevron ending 16.33 from the right edge. The
  /// grid starts 77 down.
  static const side = 16.0;
  static const face = 34.0;
  static const faceTop = 31.0;
  static const textGap = 12.0;
  static const nameText = 14.0;
  static const nameWeight = FontWeight.w500;
  static const nameInk = BiliColors.text;
  static const nameLine = 20.0;
  static const nameCentre = 106 / 3;

  /// The name's line ends this far from the right edge, clear of 进入空间.
  static const nameRight = 100.0;
  static const countsText = 12.0;
  static const countsInk = BiliColors.secondaryText;
  static const countsLine = 17.0;

  static const countsCentre = 62.0;
  static const countsGap = 8.5;

  /// The counts fade in once the space answers.
  static const countsFade = Duration(milliseconds: 220);

  /// PingFang sets digits a little apart from the Chinese they meet ("3 万粉丝"); Flutter's layout sets them touching.
  static const countsHanGap = 5 / 3;
  static const enterText = 13.0;
  static const enterInk = Color(0xFF61666D);
  static const enterCentre = 44.0;
  static const enterLine = 18.0;

  /// 进入空间's Chinese draws half a point under its line's middle, where the chevron centres.
  static const enterTextLift = 0.5;
  static const enterRight = 49 / 3;
  static const chevronWidth = 20 / 3;
  static const chevronHeight = 12.0;
  static const chevronStroke = 1.0;
  static const chevronInk = Color(0xFF939393);
  static const chevronGap = 14.0;

  /// The tap target around the face and around 进入空间 ›.
  static const targetPad = 8.0;

  /// + 关注: a 60 × 24 pink pill 9 after the name; followed, 03's grey 已关注.
  static const followGap = 9.0;
  static const followWidth = 60.0;
  static const followHeight = 24.0;
  static const followText = 13.0;
  static const followPlus = 28 / 3;
  static const followPlusStroke = 1.1;
  static const followPlusGap = 4.0;
  static const followedFill = IntroTheme.followedFill;
  static const followedInk = IntroTheme.followedText;
  static const followPressedScale = IntroTheme.followPressedScale;

  /// 简介's: the fill and words change over [followMotion]; a press shrinks the pill over [followPressMotion].
  static const followMotion = SearchResultTheme.followMotion;
  static const followPressMotion = SearchResultTheme.followPressMotion;

  static const gridTop = 77.0;

  /// Two columns of 16:9 covers, 8 from the sides and each other; a card is its cover and 52 under it.
  static const gridSide = 8.0;
  static const gridGap = 8.0;
  static const coverAspect = 16 / 9;
  static const belowCover = 52.0;
  static const coverRadius = 4.0;
  static const coverShadeHeight = 30.0;

  /// The title's two 13 pt lines 15.33 apart (Flutter draws them 15 apart), the first centred 16.17 under the cover.
  static const titleText = 13.0;
  static const titleLine = 46 / 3;
  static const titleTop = 16.17 - titleLine / 2;
  static const titleInk = BiliColors.text;

  /// The page's own video: its title pink after the playing mark, three rounded bars (10, 5.33 and 10 tall, 3.45
  /// apart) 2 in from the title's start and 6 before its text, a little under the line's middle.
  static const playingInk = BiliColors.pink;
  static const barsInk = Color(0xFFEB7093);
  static const barsLead = 2.0;
  static const barsTrail = 6.0;
  static const barsDrop = 0.25;
  static const barWidth = 1.5;
  static const barPitch = 3.45;
  static const barTall = 10.0;
  static const barShort = 16 / 3;

  /// The cover's ▶ count and date at its bottom left, the length at its bottom right: 10 pt white, its digits
  /// centred 11 above the cover's bottom and the ▶ box 11.17, 7.33 in with 3.5 after it and 11 between the count
  /// and the date.
  static const statText = 10.0;
  static const statInk = BiliColors.onCover;
  static const statCentre = 11.5;
  static const statIconDrop = 2 / 3;
  static const statLine = 14.0;
  static const statLeft = 22 / 3;
  static const statRight = 8.0;
  static const statIconWidth = 40 / 3;
  static const statIconHeight = 11.0;
  static const statIconGap = 3.5;
  static const statDateGap = 11.0;

  /// The end of the grid: 已经到底啦~ (76) or the next page's spinner, in a 40 band.
  static const footerHeight = 40.0;
  static const endText = 14.0;
  static const endInk = Color(0xFF727272);
  static const spinnerRadius = 10.0;

  /// The first load's TV, its failure and 重试.
  static const stateText = 14.0;
  static const stateInk = BiliColors.secondaryText;
  static const stateGap = 16.0;
  static const retryText = 14.0;
  static const retryHeight = 30.0;
  static const retryPadX = 20.0;
  static const retryRim = 1.0;
}

/// UP主空间's header, its collapsed bar and its tab row (63, 69-73, 75, 77-79), measured in px / 3 from the screen's
/// top with the header unscrolled.
abstract final class SpaceTheme {
  static const page = BiliColors.card;

  /// The banner runs under the status bar to 187.67; a space without one draws this light fill in its place.
  static const bannerHeight = 563 / 3;
  static const bannerDefault = Color(0xFFF3F2F7);

  /// 〈, 私信, search and ⋮: 30 pt discs of black at 30% centred 7 under the safe area's top, 〈 25 from the left and
  /// the others 109, 67 and 25 from the right. Their glyphs are white over the banner and grey on the white bar.
  static const buttonDrop = 7.0;
  static const button = 30.0;
  static const buttonTarget = 44.0;
  static const buttonFill = Color(0x4D000000);
  static const buttonInk = Color(0xFFFFFFFF);
  static const barInk = Color(0xFF61666D);
  static const backCentre = 25.0;
  static const chatCentreRight = 109.0;
  static const searchCentreRight = 67.0;
  static const moreCentreRight = 25.0;

  /// The glyphs' ink boxes and strokes (63, 73). 〈's ink centres 0.83 left of its disc, the magnifier's 0.5 up and
  /// left.
  static const glyphStroke = 1.5;
  static const backGlyphShift = -5 / 6;
  static const searchGlyphShift = -0.5;
  static const backWidth = 23 / 3;
  static const backHeight = 44 / 3;
  static const chatWidth = 16.0;
  static const chatHeight = 46 / 3;
  static const searchSize = 15.0;
  static const moreDot = 8 / 3;
  static const moreStep = 16 / 3;

  /// Scrolled, the white bar (73) covers the status bar and 32 more; it shows once the name passes under the status
  /// bar (77), fading in while the discs fade out.
  static const barRow = 32.0;
  static const bar = Color(0xFFFFFFFF);
  static const barFade = Duration(milliseconds: 150);

  /// The bar's centred pill: a 28 tall tint with the 26 pt face 2 in from its left, + 关注 8.33 after it and 13 clear
  /// of the text's ink on the right.
  static const pillHeight = 28.0;
  static const pillFace = 26.0;
  static const pillFaceInset = 2.0;
  static const pillFaceGap = 25 / 3;
  static const pillPadRight = 12.0;
  static const pillFill = Color(0xFFFFECF1);
  static const pillInk = BiliColors.pink;
  static const pillFollowedFill = Color(0xFFF1F2F3);
  static const pillFollowedInk = BiliColors.secondaryText;
  static const pillText = 14.0;
  static const pillPlus = 35 / 3;
  static const pillPlusGap = 4.0;

  /// While the space loads, the bar shows the face and name the tap knew.
  static const loadingNameText = 15.0;
  static const loadingNameGap = 8.0;
  static const loadingNameWidth = 240.0;

  /// The face: an 80 pt picture in a 2 pt white ring, the ring's box 30 from the left and 165.67 down, its badge a
  /// 20 pt disc in its own 2 pt ring flush with the box's lower right (70, 78).
  static const faceLeft = 30.0;
  static const faceTop = 497 / 3;
  static const face = 84.0;
  static const faceRing = 2.0;
  static const faceRingInk = Color(0xFFFFFFFF);
  static const faceBadge = 24.0;

  /// 粉丝 | 关注 | 获赞: three equal columns from 153.5 to 9.5 short of the right edge with 1 pt rules between them,
  /// the count's ink centred 202.5 down and the label's 220.5.
  static const statsLeft = 153.5;
  static const statsRight = 9.5;
  static const countCentre = 202.5;
  static const countLine = 18.0;
  static const countText = 14.0;
  static const countInk = BiliColors.text;
  static const labelCentre = 220.5;
  static const labelLine = 14.0;
  static const labelText = 11.0;
  static const labelInk = BiliColors.secondaryText;
  static const statsRuleTop = 607 / 3;
  static const statsRule = 16.0;
  static const statsRuleWidth = 1.0;
  static const statsRuleInk = BiliColors.divider;

  /// The 关注 row, 30 tall at 232.67 from 156 to 12 short of the right edge: + 关注 pink across all of it; followed,
  /// 充电 (83 wide, outlined) 4 before 已关注 (grey) and ▽ (30 square) 2 after it (70). 充电 shows whenever the
  /// uploader takes it (78, 79).
  static const followTop = 698 / 3;
  static const followHeight = 30.0;
  static const followLeft = 156.0;
  static const followRight = 12.0;
  static const followRadius = 4.0;
  static const followText = 14.0;
  static const followFill = BiliColors.pink;
  static const followInk = Color(0xFFFFFFFF);
  static const followPlus = 34 / 3;
  static const followPlusStroke = 1.0;
  static const followPlusGap = 13 / 3;

  /// Each label sits a little right of its button's middle: + 关注 and 已关注 by 0.67, 充电 by 2.33 (63, 70).
  static const followShift = 2 / 3;
  static const chargeShift = 7 / 3;
  static const followedFill = BiliColors.divider;
  static const followedInk = BiliColors.secondaryText;
  static const followedListWidth = 12.0;
  static const followedListHeight = 26 / 3;
  static const followedListStroke = 0.9;
  static const followedListGap = 11 / 3;
  static const chargeWidth = 83.0;
  static const chargeGap = 4.0;
  static const chargeBorder = 1.0;
  static const chargeInk = BiliColors.pink;
  static const chargeBoltWidth = 7.0;
  static const chargeBoltHeight = 12.0;
  static const chargeBoltGap = 6.5;
  static const chargeText = 13.0;
  static const moreWidth = 30.0;
  static const moreGap = 2.0;
  static const moreChevronWidth = 12.0;
  static const moreChevronHeight = 19 / 3;
  static const moreChevronStroke = 1.0;
  static const moreChevronDrop = 5 / 6;

  /// The rows under the face, 12 from the edges: the name's box from 280, 25 tall; the bio's 6.83 under it, 21 tall
  /// (its ink centred 322.83); the tag row's 6.83 under that, 15 tall; the cards 12 under that, 40 tall; then 16 to the
  /// tab row.
  static const gutter = 12.0;
  static const topBlock = 280.0;
  static const nameBox = 25.0;
  static const nameText = 18.0;
  static const nameInk = Color(0xFF2F3238);
  static const nameVipInk = BiliColors.pink;
  static const levelGap = 25 / 3;
  static const vipLabelGap = 22 / 3;
  static const vipLabelHeight = 18.0;
  static const vipLabelWidth = 82.0;

  /// The LV badge, 11.33 tall and 22 wide; 硬核会员's runs 6 further with its bolt. LV4-6 are the space's own
  /// colours, brighter than 评论's (63, 69, 75); LV0-3 have no shot yet and keep 评论's.
  static const levelHeight = 34 / 3;
  static const levelWidth = 22.0;
  static const levelSeniorExtra = 6.0;
  static const levels = [
    Color(0xFFC0C4CC),
    Color(0xFFC0C4CC),
    Color(0xFF8BD29B),
    Color(0xFF7BCDEF),
    Color(0xFFFFB37C),
    Color(0xFFEE672A),
    Color(0xFFF04C49),
  ];
  static const levelInk = Color(0xFFFFFFFF);

  /// bilibili UP主认证's line takes the bio's place and moves the rest down 30 (78): a 22 tall grey pill with the
  /// verification's 16 pt disc 5 in.
  static const officialBlock = 30.0;
  static const officialCentre = 18.5;
  static const officialHeight = 22.0;
  static const officialFill = BiliColors.pageGrey;
  static const officialDisc = 16.0;
  static const officialDiscInset = 5.0;
  static const officialTextGap = 6.0;
  static const officialPadRight = 8.0;
  static const officialText = 12.0;
  static const officialInk = Color(0xFF61666D);

  /// The bio stops short of 详情 even when 详情 is on the line above (69, 78).
  static const bioGap = 41 / 6;
  static const bioBox = 21.0;
  static const bioText = 12.0;
  static const bioInk = BiliColors.secondaryText;
  static const bioRight = 40.0;
  static const detailText = 12.0;
  static const detailInk = BiliColors.link;

  /// IP属地 and the like on one row, 11.33 apart: a 10.33 × 8.67 IP box 1 in, the text's ink 3.33 after it; a link
  /// ends with ›.
  static const tagGap = 41 / 6;
  static const tagBox = 15.0;
  static const tagText = 10.0;
  static const tagInk = Color(0xFF61666D);
  static const tagSpacing = 34 / 3;
  static const tagIconWidth = 31 / 3;
  static const tagIconHeight = 26 / 3;
  static const tagIconInset = 1.0;
  static const tagIconGap = 3.0;
  static const tagIconStroke = 0.9;
  static const tagIconRadius = 2.0;
  static const tagChevronWidth = 10 / 3;
  static const tagChevronHeight = 6.0;
  static const tagChevronGap = 3.0;

  /// 小店 and 充电: 40 tall grey cards, side by side 8 apart when there are two (78), the icon 10 in, the title 12 pt
  /// and the note 11 pt, its ink ending 9 from the right.
  static const entriesGap = 12.0;
  static const entryHeight = 40.0;
  static const entrySpacing = 8.0;
  static const entryRadius = 4.5;
  static const entryFill = BiliColors.softGrey;
  static const entryPad = 10.0;
  static const entryPadRight = 25 / 3;
  static const entryIcon = 12.0;
  static const entryBoltWidth = 25 / 3;
  static const entryBoltHeight = 13.0;
  static const entryIconGap = 13 / 3;
  static const entryText = 12.0;
  static const entryTextDrop = 2 / 3;
  static const entryInk = BiliColors.text;
  static const entryNoteText = 11.0;
  static const entryNoteInk = Color(0xFF61666D);
  static const entryIconInk = Color(0xFFFFC200);
  static const bottomGap = 16.0;

  /// The tab row: 39.5 between 0.5 pt hairlines. Its labels sit in equal cells across the width and 4 beyond each
  /// edge (63's five, 78's four, 69's three); the shown one pink over a 14 × 2 bar 4 above the lower hairline.
  static const tabsHairline = 0.5;
  static const tabsBody = 39.5;
  static const tabsHeight = tabsHairline * 2 + tabsBody;
  static const tabsHairlineInk = BiliColors.divider;
  static const tabsSpread = 4.0;
  static const tabText = 16.0;
  static const tabLine = 22.0;
  static const tabInk = Color(0xFF61666D);
  static const tabSelected = BiliColors.pink;
  static const indicatorWidth = 14.0;
  static const indicatorHeight = 2.0;
  static const indicatorBottom = 4.0;

  /// 已关注's sheet (71): rows 50 tall, the second and third with a 0.5 pt rule along their top from 20 in, a 5 pt
  /// gap, then 取消 in a 56 tall row with 14 under it, over the page dimmed by half.
  static const sheetDim = Color(0x80000000);
  static const sheetFill = Color(0xFFFFFFFF);
  static const sheetShadow = Color(0x1F000000);
  static const sheetShadowBlur = 12.0;
  static const sheetRow = 50.0;
  static const sheetRule = 0.5;
  static const sheetRuleInk = Color(0xFFAEB3B9);
  static const sheetInset = 20.0;
  static const sheetText = 14.0;
  static const sheetInk = BiliColors.text;
  static const sheetGap = 5.0;
  static const sheetGapFill = BiliColors.divider;
  static const sheetCancel = 56.0;
  static const sheetCancelText = 16.0;
  static const sheetBottom = 14.0;
  static const sheetIn = Duration(milliseconds: 280);
  static const sheetOut = Duration(milliseconds: 220);

  /// 加载失败，点击重试 in the middle of the page.
  static const retryText = 14.0;
  static const retryInk = BiliColors.secondaryText;
  static const retryAction = BiliColors.link;
}

/// 投稿's chips, 播放全部, sort and rows, and a row's ⋮ menu (63, 69, 70, 74). Measured in px / 3 from the tab row's
/// hairline, where the list starts.
abstract final class SpaceVideosTheme {
  static const gutter = BiliMetrics.gutter;

  /// The chips (69, 70): 28 tall, 6.33 under the hairline and 12 apart, in a 42 band; 14 pt words about 8 in from each
  /// side, a long title cut with … at [chipMaxText] (70's cut title is 102.7 wide with its …, a glyph more would be
  /// 116.3; between them, so the stand-in's 1 em … fits too). The chosen one is pink on a pink tint, the others
  /// #61666D in a 0.5 hairline rim drawn 0.5 inside the chip's box. A two-glyph chip is 43.8 wide (69's six chips end
  /// at 362.33): the padding gives back what the official app's narrower Chinese (about 0.993 em) leaves.
  static const chipsBlock = 42.0;
  static const chipsTop = 19 / 3;
  static const chipHeight = 28.0;
  static const chipGap = 12.0;
  static const chipPadX = 7.9;
  static const chipMaxText = 110.0;
  static const chipRadius = 4.0;
  static const chipText = 14.0;
  static const chipInk = Color(0xFF61666D);
  static const chipChosenInk = BiliColors.pink;
  static const chipChosenFill = Color(0xFFFFECF1);
  static const chipRim = BiliColors.divider;
  static const chipRimWidth = 0.5;
  static const chipRimInset = 0.5;

  /// 播放全部 and the sort share a strip 27.33 tall, their line 14.33 down it (63's first cover is 37.33 under the
  /// hairline). The ring is 16.67 across from 13.67, its ▶ 5.17 long and 5.67 tall; the words start at 40.
  static const stripHeight = 82 / 3;
  static const stripCentre = 43 / 3;
  static const playAllRing = 50 / 3;
  static const playAllRingLeft = 41 / 3;
  static const playAllStroke = 3.5 / 3;
  static const playAllTriangleLeft = -1.75;
  static const playAllTriangleRight = 2.85;
  static const playAllTriangleHalf = 2.6;
  static const playAllTriangleRound = 0.5;
  static const playAllGlyphInk = BiliColors.pink;
  static const playAllTextLeft = 40.0;
  static const playAllText = 14.0;
  static const playAllInk = BiliColors.text;

  /// ≡ 最新发布: three 12 wide bars 1.33 thick and 4 apart, 3.67 before 12 pt grey words ending 12.33 from the edge.
  static const sortGlyphWidth = 12.0;
  static const sortGlyphBar = 4 / 3;
  static const sortGlyphPitch = 4.0;
  static const sortGlyphInk = Color(0xFF999999);
  static const sortGlyphGap = 11 / 3;
  static const sortText = 12.0;
  static const sortInk = BiliColors.secondaryText;
  static const sortRight = 37 / 3;

  /// A row (63, 69, 70): 93 with its hairline, the 128 × 72 cover 10 down with a 4 corner, then 10 to a 1 pt hairline
  /// from the gutter to the edge.
  static const rowHeight = 93.0;
  static const rowPadTop = 10.0;
  static const rowPadBottom = 10.0;
  static const hairline = 1.0;
  static const hairlineInk = BiliColors.divider;
  static const coverWidth = 128.0;
  static const coverHeight = 72.0;
  static const coverRadius = 4.0;
  static const coverPlaceholder = BiliColors.pageGrey;
  static const textGap = 10.0;

  /// Two 14 pt title lines 18 apart, the first's ink 0.67 under the cover's top; they wrap before 428.
  static const titleText = 14.0;
  static const titleLine = 18.0;
  static const titleTop = -1.88;
  static const titleRight = 12.0;
  static const titleInk = BiliColors.text;

  /// The date and the counts in 11 pt grey, centred 46.67 and 66 under the cover's top. The ▶ box starts 1 in, the
  /// danmaku box 80 after it whatever the plays' width; each number 3 after its 14 × 12 box.
  static const metaText = 11.0;
  static const metaLine = 14.0;
  static const metaInk = BiliColors.secondaryText;
  static const dateCentre = 140 / 3;
  static const countsCentre = 66.0;
  static const countsInset = 1.0;
  static const countGlyphWidth = 14.0;
  static const countGlyphHeight = 12.0;
  static const countGap = 3.0;
  static const danmakuColumn = 80.0;

  /// ⋮ on the counts' line, centred 20 from the edge: 2.33 dots 4.33 apart.
  static const moreCentreRight = 20.0;
  static const moreTarget = 32.0;
  static const moreDot = 7 / 3;
  static const morePitch = 13 / 3;
  static const moreInk = BiliColors.secondaryText;

  /// The length: a 16 tall pill 4 in from the cover's right and 5 up from its bottom, black at half.
  static const durationText = 10.0;
  static const durationHeight = 16.0;
  static const durationPadX = 14 / 3;
  static const durationRight = 4.0;
  static const durationBottom = 5.0;
  static const durationRadius = 2.0;
  static const durationFill = Color(0x80000000);
  static const durationInk = BiliColors.onCover;

  /// 合作 and the like: pink, 16 tall, 4 in from the cover's top right corner.
  static const badgeText = 10.0;
  static const badgeHeight = 16.0;
  static const badgePadX = 4.0;
  static const badgeTop = 4.0;
  static const badgeRight = 4.0;
  static const badgeGap = 4.0;
  static const badgeRadius = 2.0;
  static const badgeFill = BiliColors.pink;
  static const badgeInk = BiliColors.onPink;

  /// Rows scrolled this close to the end ask for the next page.
  static const loadAhead = 360.0;

  /// Under the rows: the next page's small spinner, 已经到底啦~ (76's #727272 14 pt) or the failure, in a 20 line 16
  /// clear of the last hairline. Before the first page: the loading TV, the failure or the end, 40 under the strip.
  static const footerPad = 16.0;
  static const footerLine = 20.0;
  static const spinnerRadius = 10.0;
  static const endText = 14.0;
  static const endInk = Color(0xFF727272);
  static const stateTop = 40.0;
  static const stateText = 14.0;
  static const stateInk = BiliColors.secondaryText;
  static const stateGap = 16.0;

  /// 重试, as 搜索's.
  static const retryHeight = SearchResultTheme.retryHeight;
  static const retryPadX = SearchResultTheme.retryPadX;
  static const retryRim = SearchResultTheme.retryRim;
  static const retryText = SearchResultTheme.retryText;
  static const retryPressedScale = SearchResultTheme.followPressedScale;
  static const retryPressMotion = SearchResultTheme.followPressMotion;

  /// ⋮'s popover (74): the page under black at half; a white box 200 × 104 with a 12 corner, its top 16 under the dots'
  /// centre and its right 15 past it (5 from the screen's edge at most), an arrow 5.33 tall with 45° sides pointing
  /// at the dots. Two 52 rows: pink icons centred 26.83 and 25.67 in, 14 pt words from 44.
  static const menuDim = BiliColors.sheetDim;
  static const menuIn = Duration(milliseconds: 200);
  static const menuOut = Duration(milliseconds: 150);
  static const menuStartScale = 0.85;
  static const menuFill = BiliColors.card;
  static const menuWidth = 200.0;
  static const menuRowHeight = 52.0;
  static const menuRadius = 12.0;
  static const menuGap = 16.0;
  static const menuPastAnchor = 15.0;
  static const menuMargin = 5.0;
  static const menuArrowHeight = 16 / 3;
  static const menuArrowFoot = 0.5;
  static const menuArrowRound = 0.5;

  /// The arrow's tip sits this far right of the dots' centre.
  static const menuArrowShift = 2.5 / 3;
  static const menuText = 14.0;
  static const menuInk = BiliColors.text;
  static const menuTextLeft = 44.0;
  static const menuIconInk = BiliColors.pink;
  static const menuIconSlot = 24.0;
  static const menuWatchLaterCentre = 80.5 / 3;
  static const menuWatchLaterIcon = 55 / 3;
  static const menuShareCentre = 77 / 3;
  static const menuShareIcon = 59.5 / 3;
  static const menuShareStroke = 1.2;

  /// 分享's icon sits a little above its row's middle (74).
  static const menuShareLift = 2.5 / 3;
}
