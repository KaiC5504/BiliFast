import 'package:flutter/material.dart' show TextTheme;
import 'package:flutter/widgets.dart';

/// Whether the app draws its dark colours (深色模式); [AppearanceModel] sets it and rebuilds everything.
abstract final class BiliTheme {
  static bool dark = false;
}

/// A token's colour: [day] in light mode, [night] in dark (the official palette's night value where it has one).
Color tone(int day, int night) => Color(BiliTheme.dark ? night : day);

/// Colours and sizes sampled from the official app's screenshots (BiliNative `Shared/Theme.swift`), so widgets
/// never carry literals.
abstract final class BiliColors {
  static Color get pink => tone(0xFFFF6699, 0xFFD44E7D);
  static Color get pinkTint => tone(0x1FFF6699, 0x1FD44E7D);
  static Color get text => tone(0xFF18191C, 0xFFE7E9EB);
  static Color get secondaryText => tone(0xFF9499A0, 0xFF757A81);
  static Color get pageGrey => tone(0xFFF1F2F3, 0xFF0A0B0C);

  /// The fill behind the collection row, tag chips and reply previews on the video page.
  static Color get softGrey => tone(0xFFF6F7F8, 0xFF101011);
  static Color get divider => tone(0xFFE3E5E7, 0xFF2F3134);
  static Color get link => tone(0xFF00699D, 0xFF58B1D4);
  static Color get card => tone(0xFFFFFFFF, 0xFF17181A);

  /// Alerts and the player's light sheets' cards (255, 258): white by day, the palette's Ga11 at night, a step above
  /// [card].
  static Color get dialog => tone(0xFFFFFFFF, 0xFF242628);

  /// [pink] over the video: the player's controls and panels look the same in 深色模式.
  static const videoPink = Color(0xFFFF6699);

  /// The feed's 推荐 reason and 竖屏 tag (01) are orange-red, not the pink accent.
  /// At night as 239's 1千点赞 and 竖屏 tags.
  static Color get reason => tone(0xFFFF6633, 0xFFBF5330);
  static Color get reasonTint => tone(0xFFFFF1ED, 0xFF3D2D29);

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

  /// The light 选集 sheet in portrait (19): its ground (Ga12's night, as 258's sheet), the grey close circle (Ga13_s),
  /// its grabber, the cross in the circle, and 内容到底啦.
  static Color get sheetFill => tone(0xFFFFFFFF, 0xFF202123);
  static Color get sheetCloseFill => tone(0xFFF1F2F3, 0xFF2F3134);
  static Color get sheetGrabber => tone(0xFFC9CCD0, 0xFF46494D);
  static Color get sheetCloseGlyph => tone(0xFF61666D, 0xFFA2A7AE);
  static Color get sheetHint => tone(0xFFC9CCD0, 0xFF46494D);

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

  /// The seek bar's plain round handle, in the TV's place while its Lotties aren't there.
  static const thumbHandle = Color(0xFFFFFFFF);

  /// The small player's controls and end screen, and the bar's chapter ticks and 竖屏 style, measured on the official
  /// app's 03, 09, 15 and 26.
  static const chromeTick = Color(0xB3000000);
  static const verticalTrack = Color(0x26FFFFFF);
  static const verticalPlayed = Color(0x99FFFFFF);
  static const verticalThumb = Color(0xFFFFFFFF);

  /// 竖屏's played part, paused and held (118, 19 and 20), is Bilibili's #FB7299, not [pink].
  static const verticalPink = Color(0xFFFB7299);
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
  /// At night a step above the 17181A card they sit on (Ga1_s), the sweep a step above that (Ga0_s).
  static Color get shimmerBase => tone(0xFFEDEEF0, 0xFF232527);
  static Color get shimmerHighlight => tone(0xFFF6F7F8, 0xFF2B2C2F);

  /// The menus' frosted glass, and the highlight under a pressed row. At night the glass is the dark alert's grey
  /// (Ga11) letting as much through, under a faint light rim, and a pressed row lightens as much as it darkens by day.
  static Color get glassFill => tone(0xB8FFFFFF, 0xB8242628);
  static Color get glassBorder => tone(0x99FFFFFF, 0x1FFFFFFF);
  static const glassShadow = Color(0x26000000);
  static Color get pressedFill => tone(0x14000000, 0x14FFFFFF);

  /// The 最近打开 tile runs from this down to [pink], one hue as Swift's `Theme.pink.gradient`.
  static Color get recentsTileTop => tone(0xFFFF8CB0, 0xFFA73E65);

  /// The stats overlay's node dots (iOS system green, orange, red and grey).
  static const nodeHealthy = Color(0xFF34C759);
  static const nodeBlocked = Color(0xFFFF9500);
  static const nodeBanned = Color(0xFFFF3B30);
  static const nodeOther = Color(0xFF8E8E93);
}

/// The app's font: the system's, as the official app draws. The zh-Hans locale makes any character a font lacks fall
/// back to a Chinese font.
abstract final class BiliFonts {
  /// The system font: SF, with PingFang SC for Chinese, as the official app draws. iOS's engine registers no family by
  /// this name (only CupertinoSystemDisplay, SF's large face), so on the phone it matches nothing and the engine's
  /// default, SF, draws; tests load the SF stand-in under it. Named rather than left null so tests never draw it in the
  /// square test font.
  static const system = 'CupertinoSystemText';

  /// The family every style names. Settable so tests can draw another family and check what follows [system] alone.
  static String? family = system;

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
  /// official app's pitch. Null under any other family.
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

  static const hudArrowWidth = 31 / 3;
  static const hudArrowHeight = 41 / 3;
  static const hudArrowStep = 22 / 3;
  static const hudArrowCorner = 3.0;
  static const hudIcon = 18.0;
  static const hudBarWidth = 100.0;
  static const hudBarHeight = 3.0;
  static const hudSeekGap = 4.0;

  /// The small player draws the level pill at its box's height over this, up to full size: 0.8× in the iPhone's
  /// 247.5 pt box, clear of its top and bottom rows; full size in the iPad's and an upright video's taller boxes.
  static const hudInlineLevelFullHeight = 440 / videoAspect / 0.8;

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

  /// The official TV's Lottie box, centred on the bar and on the played part's end (04, 15 and 102: its 15 pt ink and
  /// 12 pt screen land there in each). Without its Lotties, a plain round handle as wide as that screen.
  static const thumbWidth = 18.0;
  static const thumbHeight = 18.0;
  static const thumbHandle = 12.0;
  static const hiddenLine = 2.0;

  /// The small player's controls and end screen, and the bar's chapter title and 竖屏 dot, measured on the official
  /// app's 03, 09, 15 and 26. While dragged, the bar thickens: the TV style's to 4 pt (102), 竖屏's to 6 pt (19 and
  /// 20), where the TV's box grows to 22 pt (its screen 15 × 11.33 pt): from nothing while playing, from [thumbWidth]
  /// while paused.
  static const verticalDot = 4.0;
  static const tvBarDragHeight = 4.0;
  static const verticalBarDragHeight = 6.0;
  static const verticalThumbHeld = 22.0;
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

  /// An upright video's row ends at 竖屏, with no 全屏 (17): the pill then sits only this far right of the corners,
  /// 6 pt clear of the player's edge.
  static const badgeEdgeOffsetX = 6.0;
  static const endInset = 12.0;
  static const endCaptionFont = 12.0;
  static const endCaptionGap = 3.8;

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

  static const chromeSpeedGap = 14.0;
  static const chromeQualityGap = 23.0;
  static const chromeTextPad = 8.0;
  static const chromeLabelText = 14.0;

  /// The 60帧 or 高码率 tag over 1080P (KaiC's landscape screenshots, 2026-10-23): 11 pt high with 8 pt text, its
  /// middle 15.2 pt above the name's and its right 8.8 pt past it. A tagged name keeps only 2.67 pt each side, so 倍速
  /// sits 15 pt further left than beside 4K.
  static const chromeTaggedPad = 2.67;
  static const chromeTagHeight = 11.0;
  static const chromeTagText = 8.0;
  static const chromeTagPad = 3.5;
  static const chromeTagBorder = 1 / 3;
  static const chromeTagLine = Color(0xCCFFFFFF);
  static const chromeTagTop = chromeButton / 2 - 15.2 - chromeTagHeight / 2;
  static const chromeTagOverhang = 8.8 - chromeTaggedPad;

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

  /// 118 and 19 draw the bar this much above where the rows put it, at rest and held.
  static const verticalBarLift = 0.5;
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

  /// 竖屏's danmaku start this far under the top row: 118's first lane is centred at 331.5 px.
  static const verticalDanmakuDrop = 1.0;

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

  /// 01's title lines are 20 pt apart. With the footer the card is 242 pt tall on a 211 pt column, its covers 248 pt
  /// apart.
  static const cardTitleTop = 9.75;
  static const cardTitleLine = 20.0;
  static const cardFooterInset = 9.0;
  static const cardTitleText = 14.0;
  static const cardFooterText = 12.0;
  static const cardTagText = 11.0;
  static const cardTagHeight = 16.0;

  /// The counts over the cover (01, 14), in proportional figures: digits 7.33 pt tall, "94.7万" 28.67 and "405" 16.67
  /// wide, as the system font draws them at 9.67 pt. The play and danmaku icons start [cardStatLead] from the
  /// cover's left edge; a count's ink starts 5.67 after its icon and the next icon 15 after the count's ink, the
  /// digits' side bearings taken off the gaps. Icons and digits are centred [cardStatCentre] above the cover's bottom;
  /// a line centred there draws its digits [cardStatTextDrop] high.
  static const cardStatText = 29 / 3;
  static const cardStatIconWidth = 40 / 3;
  static const cardStatIconHeight = 34 / 3;
  static const cardStatLead = 31 / 3;
  static const cardStatIconGap = 16 / 3;
  static const cardStatGap = 44 / 3;
  static const cardStatTrail = 8.0;
  static const cardStatCentre = 13.0;
  static const cardStatTextDrop = 0.5;
  static const coverShadeHeight = 36.0;
  static const cardMoreTarget = 24.0;

  /// 01's ⋮ sits this far under the footer's middle, where the tag and the name are.
  static const cardMoreDrop = 1.0;
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

  static const sheetMetaLine = 16.0;
  static const sheetDateCentre = 51.1;
  static const sheetCountsCentre = 69.7;

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
  static const tabRowTop = 19 / 3;
  static const tabIndicatorGap = 2 / 3;
  static const tabRowBottom = 8 / 3;
  static const menuRowHeight = 46.0;
  static const menuRadius = 12.0;
  static const menuIconBox = 24.0;
  static const menuIcon = 20.0;
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
  static const fontCheck = 20.0;

  /// 竖屏 full screen centres a landscape video at this fraction of the screen's height (screen 09).
  static const verticalVideoCentre = 0.415;

  /// And an upright video here: 16's 3:4 one spans 169.67-756.33 pt, its bottom meeting the uploader row.
  static const verticalUprightCentre = 463 / 956;

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

  /// 竖屏's danmaku are smaller than landscape's (118: CJK advances of 45.25 px, identical lines 69 px apart), and
  /// run from under the top row over the black above the video, down to the video's bottom.
  static const danmakuFontVertical = 15.0;
  static const danmakuLaneVertical = 23.0;
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
  static Color get tabText => tone(0xFF61666D, 0xFFA2A7AE);

  /// The 点我发弹幕 capsule, the tags, 合集 and the chips under it: Ga0_s at night (1E2021 on 240), lighter than the
  /// replies box's Ga0 ([BiliColors.softGrey]).
  static Color get chipFill => tone(0xFFF6F7F8, 0xFF1E2022);

  /// 简介 and 评论 in 61666D or pink, 评论's count smaller on their baseline (03, 10, 18). The official app's
  /// glyphs are 35 px tall to the system font's 37 at 13.5 (font-check 02).
  static const tabLabelText = 12.75;
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
  static const danmakuFieldText = 12.75;
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
  static Color get name => tone(0xFF484C53, 0xFFB9BDC2);
  static const nameText = 13.0;
  static const fansText = 10.0;

  /// The extra room PingFang leaves where the counts' digits meet 粉丝 and 视频 (03).
  static const fansHanGap = 1.8;

  /// Where the name's and the counts' lines centre, down from the avatar's top.
  static const nameCentre = 7.8;
  static const fansCentre = 24.8;
  static const nameLine = 16.0;
  static const fansLine = 13.0;

  /// 03's bolt disc sits flush with the avatar's lower right inside a ring of the page's white. The marks keep their
  /// day colours at night, as 241's 大 does.
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
  static Color get followedFill => BiliColors.pageGrey;
  static Color get followedText => BiliColors.secondaryText;
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
  static const titleText = 15.25;
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
  /// 240 keeps 未经作者授权禁止转载's ⃠ at its day red.
  static const forbidden = Color(0xFFF85A54);
  static const descGap = 2.7;
  static const descText = 12.0;
  static const descLine = 17.0;
  static const tagsGap = 11.8;
  static const tagHeight = 26.0;
  static const tagText = 12.0;
  static const tagPadding = 13.0;
  static const tagSpacing = 8.0;
  static Color get tagInk => tone(0xFF61666D, 0xFFA2A7AE);

  /// The description's @ and links: 240's @ is Lb6's night blue, not [BiliColors.link]'s.
  static Color get descLink => tone(0xFF00699D, 0xFF2C9CC8);

  /// 18 sets the action icons 30 below the plain tags, more than the action row's own top gap leaves; the tags keep
  /// the rest under them.
  static const tagsBottom = 23 / 3;

  static const expandDuration = Duration(milliseconds: 280);

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

  /// 合集's bars and ›, and the related rows' small icons: the text's grey by day, 240 draws them a shade darker.
  static Color get iconInk => tone(0xFF9499A0, 0xFF70747C);

  /// The action row ends this far below its count line, which puts the first section's top 45.17 under the icons'
  /// centre, as on 03 and font-check 02 (18 under 不喜欢's ink).
  static const actionsBottom = 0.5;

  /// 合集 (03): a 36 pt card inside the gutters, its title 12 in, then the playing bars, the place and the ›, which
  /// ends 15.7 before the card's edge.
  static const collectionHeight = 36.0;
  static const collectionLead = 12.0;
  static const collectionTrailing = 47 / 3;
  static const collectionTitleText = 14.0;

  /// 03's 221/221 is 41.67 pt of ink and its digits 8.67 tall, as font-check 02's under the real SF: 12 pt, not 13.
  static const collectionPlaceText = 12.0;
  static const collectionBarsGap = 7.0;
  static const collectionChevronGap = 6.5;
  static const collectionChevronWidth = 20 / 3;
  static const collectionChevronHeight = 12.0;
  static const chevronStroke = 1.3;

  /// The playing mark, the APK's detail_playing Lottie: an 80 pt comp whose three strokes, 10 wide and 24 apart,
  /// stretch to 71 tall. 03 and font-check 02 draw it at 4.2/24 of that, its bars 1.75 wide and 4.2 apart and 12.43
  /// tall at full stretch, centred on the line. The box is 02's frame (11.75 tall), so the rows keep their places and
  /// a full stretch reaches 0.34 past it above and below.
  static const barWidth = 1.75;
  static const barStep = 4.2;
  static const barsWidth = barWidth + 2 * barStep;
  static const barsHeight = 11.75;
  static const barsComp = 80 * barStep / 24;

  /// Reduce Motion holds font-check 02's frame, 23.4 of 1-80: tall, short, nearly tall (11.87, 5.73 and 11.03; 02
  /// measures 11.76, 5.66 and 11.03). 03 caught frame 14.1, tall, short, short.
  static const barsStill = (23.4 - 1) / 79;

  /// The file is 60 fps, the APK's night version of it 30: drawn at 30, its fastest bar moves 0.6 pt a frame.
  static const barsFps = 30.0;

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

  /// At night the chips' text is the palette's text_title (828282 on 240) and the glyph a lighter grey.
  static Color get chipTextColor => tone(0xFF61666D, 0xFF828282);
  static Color get chipGlyphColor => tone(0xFF656668, 0xFFAAA9AE);

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

  /// 03's icons are #61666D and their counts the page's grey; on, both turn [BiliColors.pink], except 不喜欢's name,
  /// which stays grey under its pink thumb (88, 89).
  static Color get icon => tone(0xFF61666D, 0xFFA2A7AE);
  static Color get count => BiliColors.secondaryText;

  /// From 03 (px / 3): the icons' ink starts 23.7 pt under the meta line's and spans 20 pt (a 24 pt icon), the counts'
  /// digits are centred 22.7 pt under the icons'. [rowHeight] ends at the bottom of the count line; 简介 adds
  /// [IntroListTheme.actionsBottom] under it.
  static const topGap = 19.0;
  static const iconSize = 24.0;
  static const countGap = 10 / 3;
  static const countLine = 14.0;

  /// The official app's 10 pt.
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
  static Color get ringLight => tone(0xFFC9CCD0, 0xFF46494D);
  static const ringDark = Color(0x66FFFFFF);
  static const tick = Color(0xFFFFFFFF);

  /// The light sheet and the alerts; at night the palette's Ga11, as 255's alert and 257's composer.
  static Color get sheetFill => tone(0xFFFFFFFF, 0xFF242628);
  static Color get field => tone(0xFFF6F7F8, 0xFF1E2022);

  /// Under a pressed row: black darkens nothing at night, so white lifts it.
  static Color get pressed => tone(0x14000000, 0x14FFFFFF);
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
  static Color get switchOffLight => tone(0xFFE3E5E7, 0xFF2F3134);
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

  /// 09's column: 44 wide, centred 27 in from the right edge, items 69 apart with the icon centre 27.5 above its
  /// count's; the last count's line ends 62.5 above the bottom row's bottom, about where the bar's touch starts.
  static const columnWidth = 44.0;
  static const columnTrailing = 5.0;
  static const columnLift = 62.5;
  static const itemSpacing = 17.5;
  static const iconBox = 32.0;
  static const countGap = 3.5;
  static const countLine = 16.0;
  static const countText = 11.0;

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

  /// + 关注: 60 × 24 on 09, 8.7 after the name.
  static const followGap = 8.7;
  static const followHeight = 24.0;
  static const followLead = 11.5;
  static const followTrailing = 10.0;
  static const followText = 13.0;
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

  static const sheetPill = Color(0xFFED7098);
  static const sheetPillLabel = Color(0xFFFFFFFF);
  static Color get sheetSubscribedFill => BiliColors.pageGrey;
  static Color get sheetSubscribedLabel => BiliColors.secondaryText;

  /// The playing episode's title and bars in the light 选集 sheet: 19 draws them in 收藏's pink, not the app's.
  static const sheetPlaying = sheetPill;

  /// Paused, 118's ▶ (the APK's `bili_player_play`, drawn at its file's 3× size) hangs from
  /// [BiliMetrics.verticalVideoCentre] whatever the video's shape (16), at a quarter of its white, with the time
  /// [pausedTimeTop] below the picture's top in 16 pt white over a shade.
  static const pausedPlayAsset = 'assets/images/player/paused_play.png';
  static const pausedPlayWidth = 80.0;
  static const pausedPlayHeight = 77.0;
  static const pausedPlayOpacity = 0.25;
  static const pausedTimeText = 16.0;
  static const pausedTimeTop = 272 / 3;
  static const pausedTimeShadowBlur = 3.0;

  /// An upright video's last bottom button (16): the APK's `bili_story_ctrl_normal`, an upright phone beside half a
  /// landscape screen, at its own 24 pt in place of 横屏全屏's corners.
  static const screenModeAsset = 'assets/images/player/screen_mode_normal.png';
  static const screenModeGlyph = 24.0;

  /// 118's 合集 line in place of the plain title: the layers glyph, 合集 · 第N集 in semibold, a 1 × 10 pt bar, then
  /// the title. The glyph's 12 pt box starts 2.3 into the title's inset; its three layers are 1.3 pt lines. The dot
  /// is a 2 pt one centred in 50 px between 合集 and 第N集.
  static const collectionGlyph = 12.0;
  static const collectionGlyphLead = 2.3;
  static const collectionGlyphGap = 6.33;
  static const collectionGlyphStroke = 1.3;
  static const collectionDotRoom = 50 / 3;
  static const collectionDot = 2.0;
  static const collectionBarWidth = 1.0;
  static const collectionBarHeight = 10.0;
  static const collectionBarLead = 25 / 3;
  static const collectionBarTrail = 20 / 3;
}

/// 竖屏's 清屏 (180, 186), its last bottom button by the video's shape, and the controls while the page moves under the
/// finger (185).
abstract final class VerticalCleanTheme {
  /// 清屏's last bottom button: the APK's `bili_story_ctrl_clean`, level 1 of `bili_story_screen_mode_selector`.
  static const screenModeCleanAsset = 'assets/images/player/screen_mode_clean.png';

  /// While the page moves, everything but the pictures is drawn at this much of itself (the feed's own
  /// `config.swipe_opacity.other_ui_alpha_percent`).
  static const movingOpacity = 0.1;

  /// With ‹ gone, 人正在看's mark starts 9 pt in (180) where it was 52.3, five sixths of its size on the same line,
  /// and its 40% white dims to 44/255.
  static const backRoom = 1.0;
  static const onlineOpacity = 44 / 102;
  static const onlineText = 10.0;
  static const onlineIconWidth = 9.3;
  static const onlineIconHeight = 8.0;
  static const onlineGap = 6.7;

  /// 180's ▶ and 186's ❚❚ at the bottom left: 18.3 × 20.3 pt of ink from 16.3 in, centred 17.3 above the bar's row;
  /// the ▶'s corners rounded by [playCorner], the bars 5.7 apart and round-ended. 00:07 in white and / 01:18 in a 60%
  /// white from 43 in.
  static const playLeft = 49 / 3;
  static const playWidth = 55 / 3;
  static const playHeight = 61 / 3;
  static const playCorner = 2.0;
  static const pauseBar = 17 / 3;
  static const pauseGap = 17 / 3;
  static const rowAboveBar = 52 / 3;
  static const timeLeft = 43.0;
  static const timeText = 12.0;

  /// The digits' ink sits 1 pt under the ▶'s centre on 180 and 186.
  static const timeDrop = 1.0;
  static const timeTotal = Color(0x99FFFFFF);
}

/// 竖屏's swipe between videos (185, 186, measured at 60 fps).
abstract final class StoryPagerTheme {
  /// After the finger lifts, the distance left roughly halves every frame: landing within 120 to 170 ms, no bounce.
  static const settleRatioPerFrame = 0.5;

  /// The frame [settleRatioPerFrame] was measured over (60 fps).
  static const frame = Duration(microseconds: 16667);

  /// The page lands once less than this is left, in points: from a normal swipe's 850 that is 9 frames (150 ms).
  static const landWithin = 2.0;

  /// A drag let go past this share of the screen moves to the neighbour; one shorter goes back.
  static const releaseShare = 0.5;

  /// Let go faster than this towards a neighbour (points a second), a shorter drag moves too: a normal swipe's finger
  /// covers about 100 pt in 0.1 s.
  static const flingVelocity = 400.0;

  /// Towards no neighbour (the first video, or none loaded yet) the page moves this share of the finger's travel.
  static const resistance = 0.3;

  /// The Windows build's 下一个视频 and 上一个视频 buttons, for its test tool alone (Windows' accessibility bridge leaves
  /// custom actions out): invisible and touch-through, but big enough for the bridge to place them on screen.
  static const moveTarget = 8.0;

  /// A video swiped to shows its still alone until it plays, as the official app's does; a start slower than this
  /// brings the loading TV back over it, so the wait is seen. The phone's opens take 0.5 to 0.7 s.
  static const quietLoading = Duration(seconds: 3);
}

/// The way into 竖屏 from the video page and back out (187, measured frame by frame at 60 fps): the picture slides
/// between the small player's box and its place in 竖屏, a wide one keeping its size (171 pt down on 187's 4:3 video).
abstract final class VerticalEnterTheme {
  /// In: the body is black from the first frame and the picture lands 7 frames later, at a nearly even pace a little
  /// ahead of linear; this fits each frame to within 0.01. The controls come with the landing; 187's come 2 frames
  /// after it.
  static const enter = Duration(microseconds: 116667);
  static const enterCurve = Cubic(0.15, 0.15, 0.2, 0.3);

  /// Out: the body is back from the first frame, the picture already 30% of the way up there, then slowing to land
  /// 10 frames in; this fits each frame to within 0.03.
  static const exit = Duration(microseconds: 166667);
  static const exitCurve = Cubic(0, 0.4, 0.9, 1);
}

/// The uploader sheet over 竖屏 (181): the sheet risen to 947 px, the controls gone, and the picture fitted into a box
/// above it.
abstract final class VerticalSheetTheme {
  static const sheetTop = 947 / 3;

  /// The box the picture fits into, the screen's width. 181's video is 9:16 with black above and below its picture,
  /// which spans 449-871 × 334-741 px, centred: its frame fills the box's height, 162-913 px.
  static const pictureTop = 162 / 3;
  static const pictureBottom = 913 / 3;
}

/// 竖屏's 简介/评论 sheet (264-268): its stops, header and moves. First readings, to be measured on the references.
abstract final class StorySheetTheme {
  /// The half sheet's top edge (264, 265, 269: 946 px).
  static const halfTop = 946 / 3;

  /// The full sheet's top edge, under the status bar (266: 162 px).
  static const fullTop = 162 / 3;

  /// The grabber and the tab row, above the tab's content (264).
  static const headerHeight = 60.0;
}

/// The 竖屏 sheet's 简介 (265, 269, 271), measured at 3 px per pt. Places are read from the sheet's top (946 px on 265
/// and 269), so they hold wherever the sheet's header ends.
abstract final class StoryIntroTheme {
  /// The official grid holds at most 20 related videos (KaiC).
  static const relatedLimit = 20;

  /// The title: 18 pt medium at PingFang's own 1.4 em pitch (269's two lines 75 px apart), its first line's glyphs
  /// centred 244.5 px below the sheet's top. 269 wraps a 但 that would have ended 424.5 pt in, so the lines stop at
  /// least 15.5 short of the right edge.
  static const titleText = 18.0;
  static const titleLine = 25.2;
  static const titleWeight = FontWeight.w500;
  static const titleTop = 244.5 / 3 - StorySheetTheme.headerHeight - titleLine / 2;
  static const titleTrailing = 16.0;

  /// The stats line centres 91.5 px under the title's last line (265, 269); it is set a pixel lower, as the stand-in
  /// fonts draw its digits a pixel high. ☰ sits further from the views than the date from the danmaku; the BV id
  /// further still.
  static const statsGap = 92.5 / 3 - titleLine / 2 - IntroTheme.metaLine / 2;
  static const statsIconGap = 9.0;
  static const statsDateGap = 7.0;
  static const statsBvGap = 13.5;

  /// The description's first line ("-" on 265) 63 px under the stats line's centre; a description puts 84 px more
  /// above 相关视频 than none does (265 against 269).
  static const descTop = 3.5;
  static const descBottom = 22 / 3;

  /// 相关视频 (14 pt semibold) and the room under it to the first cover: pinned (271), its glyphs centre 203 px and the
  /// grid is cut 280 px below the sheet's top; unpinned (265, 269) the first cover is that 77 px under its centre.
  static const headingText = 14.0;
  static const headingWeight = FontWeight.w600;
  static const headingCentre = 203 / 3 - StorySheetTheme.headerHeight;
  static const headingExtent = 280 / 3 - StorySheetTheme.headerHeight;

  /// From the stats line's centre to the heading's (269, no description: 128 px).
  static const headingGap = 128 / 3 - IntroTheme.metaLine / 2 - headingCentre;

  /// Two columns, 12 in from the left and 9 apart, each a whole number of points wide (203 on 265, so the right column
  /// ends 13 from the edge); 16:9 covers with 3.5 pt corners, 190 pt from one row's covers to the next's.
  static const gridInset = 12.0;
  static const gridGap = 9.0;
  static const coverAspect = 16 / 9;
  static const coverRadius = 3.5;
  static const cardBelowCover = 227 / 3;

  /// The cover's shade: black rising to 57% at the bottom over its last 100 px, darkening faster near the bottom (265's
  /// flat purple and grey under it).
  static const shadeHeight = 100 / 3;
  static const shade = [Color(0x00000000), Color(0x09000000), Color(0x24000000), Color(0x51000000), Color(0x90000000)];

  /// ▷ 15.1万  ☰ 5 over the cover's foot and the duration (00:41, with its zero) at the right: the play icon 19 px in,
  /// everything centred 12 pt above the bottom (a line centred there draws its digits [statTextDrop] high), the
  /// duration's ink ending 6 pt before the right edge.
  static const statText = 29 / 3;
  static const statLead = 19 / 3;
  static const statCentre = 12.0;
  static const statTextDrop = 0.5;
  static const statIconWidth = 40 / 3;
  static const statIconHeight = 34 / 3;
  static const statIconGap = 14 / 3;
  static const statGap = 14.0;
  static const statTrail = 5.0;

  /// The title (13 pt, two lines at 1.4 em, 5 pt in), its line box 5.57 under the cover, which centres its first
  /// line's glyphs 15.33 under it; the UP icon (the APK's, as 推荐's) and the name (12 pt) centred 55.67 under the
  /// cover, the icon 19 px in.
  static const cardTitleText = 13.0;
  static const cardTitleLine = 18.2;
  static const cardTitleTop = 44 / 3 - cardTitleLine / 2;
  static const cardTitleInset = 5.0;
  static const upCentre = 167 / 3;
  static const upLead = 19 / 3;
  static const upIconWidth = 40 / 3;
  static const upIconHeight = 34 / 3;
  static const upGap = 3.5;
  static const upText = 12.0;
  static const upLine = 16.0;

  /// 已经到底了… (12 pt) centred 36.33 pt under the last UP line, 15.67 over the home indicator's inset (271).
  static const endHeight = 32.0;
  static const endCentre = 49 / 3;
  static const endText = 12.0;
}

/// The picture above the 竖屏 sheet and 竖屏's controls standing aside for it (264, 268, 269).
abstract final class StorySheetRoomTheme {
  /// The room's top: the picture never goes above the status bar.
  static const pictureTop = 162 / 3;
}

/// The `相关视频 (n/N)` capsule in 竖屏's top bar on a page opened from the sheet's 相关视频 (270).
abstract final class StoryCounterTheme {
  static const label = '相关视频';
}

/// 竖屏's held 2× and its lock (182, 183, 186).
abstract final class SpeedLockTheme {
  /// The APK's `biligame_vector_lock_fill`, the filled lock 183 shows.
  static const lockAsset = 'assets/images/player/speed_lock.png';

  /// Drawn in a box this size, its ink lands 12 × 13 as on 183 and 186 (the art's square holds a 75% × 81% ink).
  static const lockSize = 16.0;
  static const lockInk = BiliColors.onVideo;

  /// The band starts right under the 2 pt progress line, 7 above the bottom row; its row is centred between there and
  /// the home indicator. The hint's band is black (182), the armed one a lighter grey (183).
  static const bandOverRow = 7.0;
  static const hintFill = Color(0xFF000000);
  static const armedFill = Color(0xFF505153);
  static const text = 14.0;
  static const textInk = BiliColors.onVideo;

  /// 182's ↓: 11.33 × 11.67 pt of ink, a 1.2 pt round-capped stroke, 8.3 before the text.
  static const arrowWidth = 34 / 3;
  static const arrowHeight = 35 / 3;
  static const arrowStroke = 1.2;
  static const arrowGap = 8.3;

  /// The lock before 松手锁定倍速 and 锁定倍速中 (183, 186).
  static const lockGap = 7.0;

  /// 竖屏's 倍速中 (182) and the locked pill in its place (186): 36 pt high right under the top row, smaller arrows than
  /// landscape's 25 (the iPad's), 8 pt corners in the HUD's fill.
  static const pillHeight = 36.0;
  static const arrowsWidth = PadFullScreenTheme.hudArrowWidth;
  static const arrowsHeight = PadFullScreenTheme.hudArrowHeight;
  static const arrowsStep = PadFullScreenTheme.hudArrowStep;
  static const arrowsGap = PadFullScreenTheme.hudGap;

  /// 186's 锁定倍速中 | 取消: 157.33 wide, centred.
  static const lockedLeading = 11.8;
  static const cancelGap = 13.0;
  static const lockedTrailing = 12.7;
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
  /// 241 keeps the 大 at its day pink and white; only the ring follows the page.
  static const vipMarkFill = Color(0xFFFF6699);
  static const vipMarkInk = Color(0xFFFFFFFF);
  static Color get vipMarkRim => BiliColors.card;

  /// The name and the LV badge centre 28.8-30 down on 10 and 13, lower in the first row under a header than in the
  /// rows after it; 29.5 is within 0.7 of each.
  static const nameCentre = 29.5;

  /// Short enough to end above the text's line at [textTop].
  static const nameLine = 16.0;
  static const nameText = 13.0;
  static Color get name => BiliColors.secondaryText;
  /// 241 keeps it at night.
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
  static Color get upFill => BiliColors.pink;
  static const upInk = Color(0xFFFFFFFF);
  static const upText = 8.0;
  static const upPadding = 3.0;
  static const upRadius = 2.0;

  /// 置顶 before a pinned comment's text.
  static const pinnedText = 11.0;
  static Color get pinnedInk => BiliColors.pink;
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
  static Color get text => BiliColors.text;

  /// The official app centres the text 22 below the name in the list (differences 12) and 21.1-21.3 in a thread
  /// (font-check 04); 1.4 under its line's own centre lands within half a point of both.
  static const textTop = textFirstCentre - textLine / 2 + 1.4;

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
  static Color get picturePlaceholder => BiliColors.pageGrey;

  /// The meta line centres 16 below a picture's bottom: ⋮'s middle dot does on font-check 04, 10 and 13.
  static const pictureGap = 4.0;

  /// The meta line: time and place, 回复 8 after them, 👍 N with the count's box ending 73 from the right edge (its ink
  /// 73.7, as on 10), 👎 centred 49 from it and ⋮ 17.
  static const metaHeight = 24.0;
  static const metaText = 12.0;
  static Color get meta => tone(0xFFC9CCD0, 0xFF46494D);
  static Color get action => tone(0xFF61666D, 0xFFA2A7AE);
  static const liked = BiliColors.videoPink;
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
  static Color get upLiked => BiliColors.secondaryText;

  /// 评论详情 draws UP主觉得很赞 as a box instead (font-check 04, under the root and under a reply): no thumb, #757575
  /// in #F4F4F4, 16 tall and 2 round, its top 22 below the meta text's centre and its bottom 8 above the band or the
  /// reply's hairline. The glyphs are 10 pt tall but 31.25 px apart, wider than PingFang's em as iOS tracks small
  /// text, which makes the box 75 wide.
  static const upChipTop = 22 - metaTextRise - metaHeight / 2;
  static const upChipHeight = 16.0;
  static const upChipBottom = 8.0;
  static const upChipText = 10.0;
  static const upChipSpacing = 0.4;
  static const upChipPadding = 13 / 3;
  static const upChipRadius = 2.0;
  /// No night screenshot: the page's chip fill and the nearest palette grey's night (Ga6).
  static Color get upChipFill => tone(0xFFF4F4F4, 0xFF1E2022);
  static Color get upChipInk => tone(0xFF757575, 0xFF8B9097);

  static TextStyle get upChipStyle => TextStyle(
    fontFamily: BiliFonts.family,
    fontSize: upChipText,
    height: upChipHeight / upChipText,
    leadingDistribution: TextLeadingDistribution.even,
    letterSpacing: upChipSpacing,
    color: upChipInk,
  );

  /// The replies box: 19.8 below the meta text's centre on 10, which sits higher in its line than the official one; 54
  /// from the left and 12 from the right, 8 round.
  static const boxGap = 127 / 6 - metaHeight / 2 - 1.75;
  static const boxLeading = 54.0;
  static const boxRadius = 8.0;
  static Color get box => BiliColors.softGrey;
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
  static Color get preview => tone(0xFF2F3238, 0xFFD0D3D7);
  static Color get previewName => BiliColors.secondaryText;
  static const previewRuleGap = 7.0;
  static const previewRuleWidth = 1.0;
  static const previewRuleHeight = 10.0;
  /// 共N条回复 centres in a 36 pt slot at the bottom, 26 below a preview's last line that ends on its own.
  static const moreSlot = 36.0;
  static const moreSlotOverlap = previewLine / 2 + moreSlot / 2 - 26;
  static const moreText = 12.0;
  static Color get moreLink => BiliColors.link;
  static const chevronGap = 7.0;
  static const chevronWidth = 14 / 3;
  static const chevronHeight = 28 / 3;
  static const chevronStroke = 1.0;

  /// The hairline under a row, 2 px of [BiliColors.divider] from 54 to the edge, 20 below the meta text's centre
  /// (font-check 04), which sits [metaTextRise] above the line's, or 12 below the replies box.
  static const dividerLeading = 54.0;
  static const divider = 2 / 3;
  static Color get dividerColour => BiliColors.divider;
  static const bottom = 20 - metaTextRise - metaHeight / 2;

  /// How far the meta text's centre sits above the meta line's (font-check 04). The hairline, the thread's band and
  /// its UP主觉得很赞 box are placed from the text.
  static const metaTextRise = 0.5;
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

  /// A card whose colour the server left out; the server's own colours are drawn as given at night too (241).
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
}

/// 评论's list, its sort header, footers and 发条评论 bar, and 评论详情's header and band (10-13), measured at 3 px per
/// pt.
abstract final class CommentListTheme {
  static const gutter = BiliMetrics.gutter;

  /// Always white, as the official page.
  static Color get background => BiliColors.card;

  /// The hairlines over the 发条评论 bar and under 评论详情's header.
  static Color get rule => BiliColors.divider;

  /// 热门评论 and ≡ 按热度 centre 16.5 below the list's top in a 28 pt header, so the first row's fan card starts 31
  /// below it (10). 评论详情's 相关回复共N条 sits lower in 35 pt under the band (13). The official app sets them in
  /// PingFang at 12 and 11 pt (their glyphs 31 and 29 px tall on 10).
  static const sortHeight = 28.0;
  static const sortCentre = 16.5;
  static const threadSortHeight = 35.0;
  static const threadSortCentre = 55 / 3;
  static const sortLine = 18.0;
  static const sortTitleText = 12.0;
  static const sortText = 11.0;
  static Color get sortInk => BiliColors.secondaryText;

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
  static Color get footerInk => tone(0xFFC9CCD0, 0xFF46494D);
  static const footerPadding = 20.0;
  static const emptyPadding = 48.0;
  static Color get retryInk => BiliColors.secondaryText;
  static Color get retryAction => BiliColors.link;

  /// The server's reason over 加载失败，点击重试, as the Swift app showed it.
  static const retryGap = 6.0;
  static const spinnerRadius = 10.0;

  /// The section the uploader closed: a bubble over the server's words.
  static const closedTop = 80.0;
  static const closedIcon = 34.0;
  static const closedGap = 10.0;
  static const closedText = 14.0;
  static Color get closedInk => BiliColors.secondaryText;

  /// The 发条评论 bar (10, 13): a hairline over it, the 34 pt pill 17/3 below the hairline and 5 above the home
  /// indicator, 12 in from the left and 44 short of the right, where the 20 pt emote face centres 22 in.
  static const barHairline = 0.5;
  static const barTop = 17 / 3;
  static const barBottom = 5.0;
  static const fieldHeight = 34.0;
  /// Ga1_s at night (232526 on 241), not the page gap's Ga1.
  static Color get fieldFill => tone(0xFFF1F2F3, 0xFF232527);
  static const fieldPadding = 13.0;
  static const fieldText = 15.0;
  static Color get fieldInk => BiliColors.secondaryText;
  static const faceBox = 44.0;
  static const face = 20.0;
  static const faceStroke = 1.28;
  static Color get faceInk => BiliColors.secondaryText;

  /// 评论详情's header over the thread: 40 as the tab row it covers, then its 1 pt hairline (3 px at 239.7 on 13).
  static const threadHeaderHeight = 41.0;
  static const threadHairline = 1.0;
  /// Under the system font 13.75: the official 评论详情's glyphs are 38 px tall to our 41.5 at 15 (font-check 04).
  static const threadTitleText = 13.75;
  static Color get threadTitleInk => BiliColors.text;

  /// ✕: 38/3 pt square, 1.2 pt strokes, centred 26 in from the right edge in a 44 pt button.
  static const close = 38 / 3;
  static const closeStroke = 1.2;
  static const closeBox = 44.0;
  static const closeTrailing = 4.0;
  static Color get closeInk => BiliColors.secondaryText;

  /// The grey band between the thread's root and its replies, straight under the root's meta line.
  static const bandHeight = 10.0;
  static Color get band => BiliColors.pageGrey;

  /// The band starts 20 below the root's meta text's centre, where a reply's hairline does (13 and font-check 04).
  static const bandGap = 20 - CommentRowTheme.metaTextRise - CommentRowTheme.metaHeight / 2;
}

/// A comment's rich text and the picture viewer.
abstract final class CommentTextTheme {
  /// The only blue the official comments show (12's 共N条回复) is the app's link blue.
  static Color get link => BiliColors.link;

  /// A reply's "回复 名字: " lead names whom it answers in grey, #9499A0 on font-check 04, without the @.
  static Color get replyTarget => BiliColors.secondaryText;

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

  /// A vertical swipe throws the picture back to the comments, as 105 shows: it follows the finger, shrinking to 60%
  /// while the black fades out over a third of the screen's height. Let go past [viewerThrowCommit] or flicked
  /// faster than [viewerThrowFlick], it flies on off the screen; otherwise it settles back.
  static const viewerThrownScale = 0.6;
  static const viewerThrowFade = 1 / 3;
  static const viewerThrowCommit = 100.0;
  static const viewerThrowFlick = 700.0;
  static const viewerThrowAway = Duration(milliseconds: 220);
  static const viewerThrowBack = Duration(milliseconds: 250);
}

/// Landscape's seek preview while the bar is dragged, measured on KaiC's recording 102 (956 × 440): the frame in a
/// 1 pt white border with 6 pt corners, 184 pt from the top of the screen, and the time 15 pt under it, centred.
abstract final class SeekPreviewTheme {
  static const frameWidth = 168.0;
  static const frameHeight = 93.0;
  static const border = 1.0;
  static const radius = 6.0;
  static const borderColor = Color(0xFFFFFFFF);

  /// The frame's top above the screen's middle.
  static const aboveMiddle = 36.0;
  static const timeGap = 15.0;
  static const timeFont = 15.0;
  static const time = Color(0xFFFFFFFF);

  /// Reads #999999 over 19's black.
  static const duration = Color(0x99FFFFFF);
  static const fade = Duration(milliseconds: 200);

  /// 竖屏's (19 and 20, 440 × 956): the frame 81 × 144 pt for an upright video and 144 × 81 for a wide one, border
  /// included, centred with its bottom at 788 pt, and the time's digits at 802-814 pt under it. Both are placed from
  /// 竖屏's bottom rows (33 pt above the screen's bottom there), so they keep their distance from its bar.
  static const uprightLong = 144.0;
  static const uprightShort = 81.0;
  static const uprightTimeFont = 16.0;
  static const uprightTimeGap = 12.57;
  static const uprightTimeLift = 106.43;
}

/// The composer and its emote panel (14), measured at 3 px per pt.
abstract final class ComposerTheme {
  static const gutter = BiliMetrics.gutter;

  /// 14's page shows through at 80%: its white reads #CCCCCC; 257's dark page takes the same 20%.
  static const dim = Color(0x33000000);

  /// Ga11 at night (242628 on 257), lighter than the page.
  static Color get sheet => tone(0xFFFFFFFF, 0xFF242628);

  /// The keyboard toggle and 发布 are a deeper pink than [BiliColors.pink]; 发布 with nothing to post is it at about
  /// 30% on white. 257's faded 发布 is Pi5's night at 30% over the sheet, its label the palette's supplementary grey.
  static Color get accent => tone(0xFFED7098, 0xFFD44E7D);
  static Color get accentFaded => tone(0xFFF8D3DF, 0xFF593242);
  static const publishText = Color(0xFFFFFFFF);
  static Color get publishTextFaded => tone(0xFFFFFFFF, 0xFF686868);
  static Color get text => BiliColors.text;
  static Color get placeholder => tone(0xFFC9CCD0, 0xFF46494D);

  /// @, ⊕, ⤢ and the emote face.
  static Color get tool => tone(0xFF9499A0, 0xFF757A81);
  static Color get syncText => tone(0xFF61666D, 0xFFA2A7AE);
  /// 257's ○ stays C9CCD0 at night, unlike the placeholder.
  static const syncRing = Color(0xFFC9CCD0);

  /// No night screenshot of the panel: darker than the sheet as by day (Ga13), the tab bar the sheet's.
  static Color get panel => tone(0xFFF1F2F3, 0xFF1A1B1D);
  static Color get tabBar => sheet;
  static Color get tabSelected => panel;
  static Color get sectionTitle => syncText;
  static Color get kaomoji => BiliColors.text;
  static Color get kaomojiTab => tone(0xFFA7A7A7, 0xFF5E6267);

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
  static Color get threadFill => BiliColors.card;

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
  static Color get alertFill => FavouriteTheme.sheetFill;
  static Color get alertPressed => FavouriteTheme.pressed;
  static Color get alertTitle => BiliColors.text;
  static Color get alertMessage => BiliColors.secondaryText;
  static Color get alertCancel => BiliColors.secondaryText;
  static Color get alertDelete => BiliColors.pink;
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

  /// An upright video's box is at most this many widths tall. A guess: 17's 3:4 is the only sample, so a 9:16 sits in
  /// the 3:4 box with bars.
  static const uprightLimit = 4 / 3;

  /// The box taking a new shape: 18's shrink to 16:9 at the end and 重播's grow back (60 fps frames 89-98, 209-217).
  static const reshape = Duration(milliseconds: 150);
  static const reshapeCurve = Curves.easeInOut;
}

/// The composer's @ picker and attached pictures.
abstract final class MentionTheme {
  static const gutter = BiliMetrics.gutter;

  /// How long typing must rest before the picker searches.
  static const debounce = Duration(milliseconds: 300);

  /// The search pill under the header, filled as 14's emote panel.
  static const fieldHeight = 36.0;
  static Color get fieldFill => CommentListTheme.fieldFill;
  static const fieldText = 15.0;
  static const fieldIcon = 18.0;
  static const fieldIconGap = 6.0;
  static const fieldPadX = 12.0;
  static const fieldBottom = 4.0;
  static const fieldSpinnerRadius = 7.0;
  static const clearSize = 16.0;
  static const clearGlyph = 11.0;
  static Color get clearFill => BiliColors.sheetHint;
  static Color get clearGlyphColor => BiliColors.card;

  /// 最近关注 over the list, in 14's 最近使用 grey.
  static const sectionHeight = 36.0;
  static const sectionText = 13.0;
  static Color get sectionColour => BiliColors.sheetCloseGlyph;

  static const rowHeight = 60.0;
  static const avatar = 40.0;
  static const avatarGap = 12.0;
  static const nameText = 15.0;

  /// The part of a name that matches the search.
  static Color get match => BiliColors.pink;

  /// Loading, no matches and 加载失败.
  static const statePad = 40.0;
  static const stateText = 14.0;
  static const spinnerRadius = 10.0;

  /// The attached pictures: square thumbnails under the field, each with a ✕ in its top right corner.
  static const thumb = 72.0;
  static const thumbGap = 8.0;
  static const thumbRadius = BiliMetrics.cardRadius;
  static const thumbBottom = 8.0;
  static Color get thumbBorder => BiliColors.divider;
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
  static Color get background => BiliColors.softGrey;
  static const barHeight = 44.0;
  static Color get barIcon => tone(0xFF61666D, 0xFFA2A7AE);
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
  static Color get remove => tone(0xFFC9CCD0, 0xFF46494D);
  static const shown = 5;
}

/// 我的 (87, 106, 107). The fixed part (the top icons, the header, the counts and the 会员 card) is measured from the
/// safe area's top; the list that scrolls under the card from the card's bottom, its viewport's top.
abstract final class MeTheme {
  static Color get background => BiliColors.card;

  /// The top row: four glyphs 40.67 apart, the last centred 24.67 from the right edge, all 22 below the safe area.
  static const topCentre = 22.0;
  static const topLastFromRight = 24.67;
  static const topPitch = 40.67;
  static const topGlyphBox = 24.0;
  static const topGlyphStroke = 1.5;

  /// 日间模式's ☀ (251): a ring 7.1 to the stroke's middle, a hair thinner than the other glyphs, and six dots 2
  /// across, 10 out at every 60° from the side.
  static const sunRing = 7.1;
  static const sunStroke = 1.45;
  static const sunDot = 1.0;
  static const sunRays = 10.0;
  static Color get topGlyph => tone(0xFF61666D, 0xFFA2A7AE);
  static const castDot = 1.1;
  static const topTapHeight = 44.0;

  /// The avatar: 64 across without a frame; under a frame the face shrinks to 49 about the same middle and the frame
  /// is 评论's 1.75 times the face.
  static const avatarLeft = 15.0;
  static const avatarTop = 64.0;
  static const avatar = 64.0;
  static const pendantFace = 49.0;
  static const pendantScale = CommentRowTheme.pendantScale;

  /// With no profile (logged out, loading, failed), 首页's grey head: a person glyph at this share of the circle.
  static const blankHead = 0.55;

  /// The 大 disc on its corner, in a white ring: flush with the avatar's box, 3 in from it under a frame.
  static const vipDisc = 16.0;
  static const vipRing = 2.0;
  static const vipPendantInset = 3.0;
  /// The disc keeps the light pink and white 大 in dark (251), as do the LV badge, the pill and 会员中心's text.
  static const vipDiscFill = Color(0xFFFF6699);
  static const vipDiscInk = Color(0xFFFFFFFF);
  static Color get vipRingInk => tone(0xFFFFFFFF, 0xFF17181A);
  static const vipDiscStroke = 1.6;

  /// The column right of the avatar starts 2 further right under a frame.
  static const textLeft = 94.33;
  static const pendantTextShift = 2.0;

  /// A line of text sits centred in a box this tall at its middle.
  static const lineBox = 30.0;

  /// The name's middle below the safe area.
  static const nameCentre = 74.0;
  static const nameText = 16.0;
  static const nameWeight = FontWeight.w500;
  static Color get name => BiliColors.text;
  static Color get vipName => BiliColors.pink;
  static const loggedOutText = 16.0;

  /// ✏️ and the LV badge after the name, the gaps between their inks.
  static const pencilGap = 8.3;
  static const pencilBox = 20.8;
  static const pencilInk = 13.7;
  static const pencilStroke = 1.4;
  static Color get pencil => BiliColors.secondaryText;
  static const levelGap = 9.5;
  static const levelWidth = 20.0;
  static const levelHeight = 10.0;
  static const levels = [
    Color(0xFFC0C4CC),
    Color(0xFFC0C4CC),
    Color(0xFF8BD29B),
    Color(0xFF7BCDEF),
    Color(0xFFFEBB8B),
    Color(0xFFED672A),
    Color(0xFFE3524E),
  ];
  static const levelInk = Color(0xFFFFFFFF);

  static const vipLabelTop = 90.0;
  static const vipLabelHeight = 14.0;
  static const vipLabelPad = 6.3;
  static const vipLabelText = 11.0;
  static const vipLabelWeight = FontWeight.w600;

  /// The pill after the level (年度大会员), a darker pink than the accent.
  static const vipLabelFill = Color(0xFFFF548C);
  static const vipLabelInk = Color(0xFFFFFFFF);

  /// The B币 line's middle below the safe area.
  static const coinsCentre = 121.2;
  static const coinsText = 12.0;
  static Color get coins => BiliColors.secondaryText;
  static const coinsGap = 20.5;

  /// 空间 ›, its middle within a point of the avatar's.
  static const spaceCentre = 95.2;
  static const spaceText = 12.0;
  static Color get space => BiliColors.secondaryText;
  static const spaceChevronGap = 7.3;
  static const spaceRight = 16.67;
  static const chevronWidth = 20 / 3;
  static const chevronHeight = 12.0;
  static const chevronStroke = 1.0;

  /// 动态, 关注 and 粉丝 in thirds of the width, a 1 pt rule 20 tall at each third.
  static const countCentre = 167.5;
  static const countText = 15.0;
  static const countWeight = FontWeight.w500;
  static Color get count => BiliColors.text;
  static const countLabelCentre = 186.0;
  static const countLabelText = 12.0;
  static Color get countLabel => BiliColors.secondaryText;
  static const countRuleTop = 166.0;
  static const countRuleHeight = 20.0;
  static const countRuleWidth = 1.0;
  static Color get countRule => BiliColors.divider;
  static const countTap = 44.0;

  /// The 会员 card, 12 in from each side.
  static const cardTop = 204.0;
  static const cardHeight = 54.0;
  static const cardInset = 12.0;
  static const cardRadius = 8.0;
  /// Dark is 251's, a little lighter than the palette's Pi1 night (#2F1A22).
  static Color get card => tone(0xFFFFECF1, 0xFF37232C);
  static const cardLineCentre = 18.0;
  static const cardTitleGap = 4.0;
  static const cardTitleText = 14.0;
  static const cardTitleWeight = FontWeight.w400;
  static Color get cardTitle => BiliColors.pink;
  static const cardMoreCentre = 38.5;
  static const cardMoreText = 12.0;
  static Color get cardMore => tone(0x9918191C, 0x99E7E9EB);
  static const cardMoreChevronGap = 3.0;
  static const cardMoreChevronWidth = 16 / 3;
  static const cardMoreChevronHeight = 28 / 3;
  static const cardMoreChevronStroke = 0.8;
  static const cardButtonWidth = 80.0;
  static const cardButtonHeight = 30.0;
  static const cardButtonText = 14.0;
  static Color get cardButtonFill => BiliColors.pink;
  static const cardButtonInk = Color(0xFFFFFFFF);

  /// A 大会员's card coming in once the profile answers; the header's height follows at the same pace.
  static const cardFade = Duration(milliseconds: 250);
  static const cardFadeCurve = Curves.easeOut;

  /// The list's viewport starts this far under the header, leaving 106's white band under the card; what it holds
  /// keeps the rest positions below, measured from the card's bottom.
  static const listCut = 8.0;

  /// The four shortcuts: a quarter of the width each, in 87's blue, their icon box and label centred below the card.
  static const shortcutIconCentre = 26.0;
  static const shortcutLabelCentre = 51.4;
  static const shortcutHeight = 72.0;
  /// No dark screenshot shows them; 251's pink glyphs keep about their light ink, so the blue keeps its own.
  static const shortcutGlyph = Color(0xFF2CA1DD);
  static const shortcutText = 12.0;
  static Color get shortcutLabel => BiliColors.text;

  /// 更多服务: its title 48 below the shortcuts' labels, as 87's is below 我的服务's last labels, then 106's rows.
  static const servicesTitleCentre = 99.5;
  static const servicesTitleText = 14.0;
  static const servicesTitleWeight = FontWeight.w500;
  static Color get servicesTitle => BiliColors.text;
  static const serviceFirstCentre = 141.2;
  static const serviceRow = 48.0;
  static const serviceGlyphCentre = 37.0;
  static const serviceGlyphBox = 30.0;
  static const serviceGlyphStroke = 1.5;
  /// 106's glyphs differ a little (sRGB): 听视频's is pinker than 联系客服's and 设置's.
  static Color get serviceGlyph => tone(0xFFF9739D, 0xFFE96D97);
  static Color get listenGlyph => tone(0xFFFD679D, 0xFFF06294);
  static const serviceTextLeft = 60.5;
  static const serviceText = 14.0;
  static Color get serviceLabel => BiliColors.text;
  static Color get serviceChevron => tone(0xFF999999, 0xFF919191);
  static const bottomPad = 24.0;

  /// The equipped 装扮 (109): its picture fills the width from the screen's top to the list's, and its last
  /// [skinFade] (the card and the band under it) whitens into the list. The stops are the white's measured over the
  /// picture's dark edges, which give the same curve at every column. Dark fades into its page the same way (252).
  static const skinFade = 62.0;
  static const skinFadeStops = [0.0, 0.086, 0.333, 0.538, 0.634, 1.0];
  static const _skinFadeAlphas = [0x00, 0x1C, 0x4D, 0xCC, 0xE6, 0xFF];
  static List<Color> get skinFadeColors => [for (final alpha in _skinFadeAlphas) background.withAlpha(alpha)];

  /// The text and icons over the picture when the skin asks for light text but names no colour. 109's are this
  /// white, at 87's places and sizes; the counts' rules go.
  static const skinLightInk = Color(0xFFFFFFFF);
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

  /// Portrait's light sheet (40, 41): the fill left of the thumb is half pink, the thumb and dots pink. At night as ⋮'s
  /// sheet (258): Ga12 under Ga11 cards, the squares a step lighter (Ga12_s), the rest the palette's night values.
  static Color get lightBackground => DownloadSheetTheme.sheet;
  static Color get lightCard => DownloadSheetTheme.card;
  static Color get lightSquare => tone(0xFFF6F7F8, 0xFF2B2C2F);
  static Color get lightTrack => tone(0xFFE3E5E7, 0xFF2F3134);
  static Color get lightFill => tone(0xFFFFB3CA, 0xFF76304B);
  static Color get lightHairline => tone(0xFFE3E5E7, 0xFF2F3134);
  static Color get lightText => BiliColors.text;
  static Color get lightSecondary => BiliColors.secondaryText;
  static Color get lightReset => tone(0xFF61666D, 0xFFA2A7AE);
  static Color get lightSwitchOff => tone(0xFFE9E9EA, 0xFF5F6065);
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
  static const fieldInk = Color(0xFF18191C);
  static const fieldRadius = 3.5;
  static const fieldPadX = 10.0;
  static const fieldText = 12.0;

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
  /// Landscape's are over the video, so they stay in 深色模式.
  static const darkBar = Color(0xFF242627);
  static const darkArea = Color(0xFF18191C);
  static Color get lightBar => BiliColors.card;
  static Color get lightArea => BiliColors.pageGrey;
  static Color get hairline => tone(0xFFE3E5E7, 0xFF2F3134);
  static const hairlineWidth = 1 / 3;

  /// Landscape's pink is deeper than the light pages'; 竖屏's send arrow turns it too (37), while A and the options
  /// take the page pink there (38).
  static const darkAccent = Color(0xFFED7098);
  static Color get lightAccent => BiliColors.pink;
  static Color get sendReady => darkAccent;
  static const darkGlyph = Color(0xFFFFFFFF);
  static Color get lightGlyph => tone(0xFF61666D, 0xFFA2A7AE);
  static const hintDot = Color(0xFFD04B44);

  /// 39's empty arrow is the dark glyph grey, 36's the placeholder grey.
  static Color get verticalSendIdle => tone(0xFFC9CCD0, 0xFF46494D);

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
  static Color get lightField => BiliColors.pageGrey;
  static Color get fieldText => BiliColors.text;
  static const darkFieldText = Color(0xFF18191C);
  static const fieldFont = 15.0;
  static const fieldPad = 8.0;
  static const verticalFieldPad = 12.0;
  static Color get placeholder => tone(0xFFC9CCD0, 0xFF46494D);
  static const darkPlaceholder = Color(0xFFC9CCD0);

  /// 竖屏's placeholder is smaller and darker than the text it gives way to (36, 37).
  static Color get verticalPlaceholder => tone(0xFF9499A0, 0xFF757A81);
  static const verticalPlaceholderFont = 13.0;
  static const cursorHeight = 20.0;
  static const cursorWidth = 2.0;

  /// The clear ⓧ, centred 15 pt in from the field's end (37).
  static const clearSize = 14.0;
  static const clearCell = 30.0;
  static Color get clearFill => tone(0xFFC9CCD0, 0xFF46494D);
  static Color get clearGlyph => tone(0xFFFFFFFF, 0xFF17181A);
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
  static const darkSecondary = Color(0xFF9499A0);
  static Color get lightSecondary => tone(0xFF9499A0, 0xFF757A81);
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
  static Color get lightSwatchRing => tone(0xFFC9CCD0, 0xFF46494D);

  /// The dark picker shows the colours dimmed, in the same order as `DanmakuStyle.colors` (23 against 38).
  static const darkSwatches = [
    Color(0xFFFFFFFF), Color(0xFFD42D25), Color(0xFFFCF150), Color(0xFF42954C), Color(0xFF469DE4), //
    Color(0xFFCF2C7D), Color(0xFF9AC143), Color(0xFF102859), Color(0xFFE6AE48), Color(0xFF613C77), //
    Color(0xFF91BEC9), Color(0xFF8E7A43),
  ];

  /// The 会员 chip: the gradient ring around a white middle, with its pink 会员 pill over the top right corner. The
  /// middle is the white swatch's colour, so it and the ring stay as they are in 深色模式.
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
  static const liked = BiliColors.videoPink;

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

/// 开发者 (dev builds), in 设置's look: no official screen shows it, so what 设置 lacks is set here.
abstract final class DevToolsTheme {
  static const crashInk = BiliColors.failure;

  /// Rows that act at once (开始速度测试, 授权), and 连接: the pink of 设置's alert action.
  static Color get actionInk => BiliColors.pink;

  /// Each group's grey title, sunk into 设置's own gap above its first section so it sits nearer that section than
  /// the one before.
  static const headerText = 13.0;
  static Color get header => BiliColors.secondaryText;
  static const headerTop = 22.0;
  static const headerSink = 6.0;
  static const pageBottom = 32.0;

  /// 状态's lines under a row (节点's hosts, 后台下载's ways), level with the row's title.
  static const subText = 13.0;
  static Color get sub => BiliColors.secondaryText;
  static Color get subValue => BiliColors.text;
  static const subLineGap = 6.0;
  static const subBottom = 12.0;
  static const subColumnGap = 8.0;
  static const dot = 6.0;
  static const dotGap = 6.0;

  /// What is typed into a row: 设置's title size, the hint in its value grey.
  static const fieldText = SettingsTheme.rowTitleText;
  static Color get fieldHint => SettingsTheme.value;
  static const fieldVertical = 12.0;
  static const fieldButtonPadding = 10.0;

  /// The speed test's status lines, results table and the note under it.
  static const noteText = 12.0;
  static Color get note => BiliColors.secondaryText;
  static const noteLineGap = 3.0;
  static const blockVertical = 12.0;
  static const tableText = 12.0;
  static Color get tableHeader => BiliColors.secondaryText;
  static Color get tableInk => BiliColors.text;
  static const tableCellGap = 10.0;

  /// Each number column with its gap before it: a time's room for +0.00 and 15.00, a count's for +120, so the label
  /// column takes the rest of the card.
  static const tableTimeColumn = 46.0;
  static const tableCountColumn = 40.0;
  static const tableRowGap = 5.0;
  static const tableGap = 10.0;
}

/// 开发者's 节点测速: a 设置 section, its row, then the table and its notes inset as the row's title.
abstract final class NodeProbeTheme {
  static const inset = SettingsTheme.rowInset;
  static Color get action => BiliColors.pink;
  static Color get stop => BiliColors.secondaryText;

  static const top = 10.0;
  static const bottom = 12.0;
  static const lineGap = 4.0;
  static const groupGap = 10.0;
  static const columnGap = 12.0;
  static const rowGap = 3.0;

  static const noteText = 13.0;
  static const tableText = 13.0;
  static const groupText = 14.0;
  static const groupWeight = FontWeight.w600;
  static Color get text => BiliColors.text;
  static Color get secondary => BiliColors.secondaryText;

  /// A node that didn't answer, and its row's numbers.
  static Color get failed => BiliColors.secondaryText;
  static const fastest = BiliColors.faster;
  static const error = BiliColors.failure;
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
  static Color get back => tone(0xFF484C53, 0xFFE7E9EB);
  static const titleText = 20.0;
  static const titleWeight = FontWeight.w600;

  /// Every other word on the page and its sheet is regular (45, 47, 48).
  static const textWeight = FontWeight.w400;

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
  static Color get divider => BiliColors.divider;

  /// The title: two lines 19.3 apart.
  static const rowTitleText = 14.0;
  static const rowTitleLine = 58 / 3;
  static const rowTitleTop = -1.27;

  /// Where a title wraps: 45's lines end past 420.4 but never reach 422.
  static const titleRight = 18.0;
  static Color get rowTitle => BiliColors.text;

  /// The UP and device lines, their ink ending level with the cover's bottom.
  static const metaText = 12.0;
  static const metaLine = 16.0;
  static const metaGap = 2.3;
  static const metaBottom = 1.6;

  static Color get meta => BiliColors.secondaryText;
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
  static Color get more => tone(0xFFC9CCD0, 0xFF46494D);

  /// The time on the cover: a 14 tall pill of half black, 3.7 from the right and 4 from the bottom.
  static const pillText = 11.0;

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
  static Color get progress => tone(0xFFEA6E96, 0xFFD44E7D);

  /// The page's own states: logged out, empty, failed.
  static const stateText = 15.0;
  static const stateGap = 16.0;
  static Color get stateInk => BiliColors.secondaryText;
  static const loginText = 15.0;
  static const loginHeight = 36.0;
  static const loginPadX = 36.0;
  static const retryText = 14.0;
  static const retryPadX = 20.0;
  static const retryHeight = 30.0;
  static const buttonWeight = FontWeight.w500;
  static const footerText = 12.0;
  static const footerPad = 16.0;
  static Color get footerInk => tone(0xFFC9CCD0, 0xFF46494D);
  static const spinnerRadius = 10.0;

  /// ⋮'s sheet (48): the page dimmed to 30 %, a white sheet 291 tall over the home indicator's inset.
  static const sheetDim = Color(0xB3000000);
  static const sheetIn = Duration(milliseconds: 280);
  static const sheetOut = Duration(milliseconds: 220);
  static Color get sheetFill => tone(0xFFFFFFFF, 0xFF1E2022);
  static const sheetHeaderHeight = 44.0;
  static const sheetHeaderText = 14.0;
  static const sheetHeaderInset = 12.7;
  static Color get sheetHeaderInk => tone(0xFF505050, 0xFFB9BDC2);
  static const sheetItemCentre = 33.0;
  static const sheetCircle = 44.0;
  static Color get sheetCircleFill => BiliColors.pink;
  static const sheetCircleGlyph = BiliColors.onPink;
  static const sheetShareGlyphWidth = 17.0;
  static const sheetShareGlyphHeight = 20.0;
  static const sheetShareStroke = 1.6;
  static const sheetLabelText = 12.0;
  static const sheetLabelGap = 6.0;
  static Color get sheetLabelInk => tone(0xFF999999, 0xFF757A81);
  static const sheetItemWidth = 66.0;
  static const sheetShareBottom = 127.0;
  static const sheetDivider = 1.0;
  static Color get sheetDividerInk => BiliColors.divider;

  /// 删除: the trash glyph centred 42 below the divider, its label under it.
  static const sheetDeleteHeight = 102.7;
  static const sheetTrashWidth = 30.0;
  static const sheetTrashHeight = 28.0;
  static const sheetTrashTop = 28.0;
  static const sheetTrashStroke = 1.5;
  static const sheetDeleteLabelGap = 14.2;
  static Color get sheetDeleteInk => tone(0xFF61666D, 0xFFA2A7AE);
  static const sheetBand = 16 / 3;
  static Color get sheetBandFill => tone(0xFFF4F4F4, 0xFF0A0B0C);
  static const sheetCancelHeight = 55.0;
  static const sheetCancelText = 16.0;
  static Color get sheetCancelInk => tone(0xFF505050, 0xFFB9BDC2);
}

/// The login page and its bar.
abstract final class LoginTheme {
  /// No official screenshot shows this frame: it keeps 设置's white bar, and Bilibili's own page fills the rest.
  static Color get bar => BiliColors.card;
  static Color get page => BiliColors.card;
  static Color get title => BiliColors.text;
  static const titleText = BiliMetrics.titleText;

  /// The ✕ that closes the page, in a 44 pt target.
  static Color get close => BiliColors.text;
  static const closeIcon = 24.0;
  static const closeTarget = 44.0;

  static const spinnerRadius = 14.0;

  /// 请在手机上登录, a load error or a login that didn't take, with 重试 under the last two; the QR login's messages
  /// too.
  static Color get message => BiliColors.secondaryText;
  static const messageText = BiliMetrics.bodyText;
  static const inset = BiliMetrics.sectionGap;
  static const gap = BiliMetrics.rowGap;
  static Color get retry => BiliColors.pink;
  static const retryHeight = BiliMetrics.pillHeight;
  static const retryPadX = BiliMetrics.sectionGap;

  static TextStyle get titleStyle => TextStyle(fontFamily: BiliFonts.family, fontSize: titleText, color: title);

  static TextStyle get messageStyle => TextStyle(fontFamily: BiliFonts.family, fontSize: messageText, color: message);

  static TextStyle get retryStyle => TextStyle(fontFamily: BiliFonts.family, fontSize: messageText, color: retry);

  /// The PC's QR login (`qr_login.dart`), which the official app has no screen for: the code centred on the white
  /// page with a quiet zone of about 4 modules, the message [qrGap] under it.
  static const qrSize = 200.0;
  static const qrQuietZone = 16.0;
  static const qrModule = Color(0xFF18191C);
  static const qrBackground = Color(0xFFFFFFFF);
  static const qrGap = BiliMetrics.sectionGap;

  /// Once scanned, the code steps back while 确认 is waited for on the phone.
  static const qrScannedOpacity = 0.3;
  static const qrFade = Duration(milliseconds: 200);
}

/// 设置's sections and its confirms: 50 and 51, measured at 3 px per pt.
abstract final class SettingsTheme {
  /// The white bar under the status bar, its bold title and the ‹ whose ink starts 79 px in.
  static Color get bar => BiliColors.card;
  static const barHeight = 44.0;
  static const barTitleText = 20.0;
  static const barTitleWeight = FontWeight.w600;
  static Color get barTitle => BiliColors.text;

  static const backLeft = 79 / 3;
  static const backGlyphWidth = 25 / 3;
  static const backGlyphHeight = 47 / 3;
  static const backStroke = 1.6;
  static Color get backGlyph => tone(0xFF484C53, 0xFFB9BDC2);
  static const backTarget = 44.0;

  static Color get page => BiliColors.pageGrey;
  static Color get row => BiliColors.card;
  static const rowTitleText = 16.0;
  static Color get rowTitle => BiliColors.text;
  static Color get rowDisabled => BiliColors.secondaryText;
  static Color get value => BiliColors.secondaryText;

  /// The titles and the hairlines under every row, the last included, start 15 pt in; a full-width one tops each
  /// section.
  static const rowInset = 15.0;
  static const hairline = 1 / 3;
  static Color get hairlineColor => BiliColors.divider;

  /// The grey ›'s ink ends 48 px from the right, the value's 24 px before it.
  static const chevronWidth = 20 / 3;
  static const chevronHeight = 12.0;
  static const chevronStroke = 2.5 / 3;
  static const chevronRight = 47 / 3;
  static Color get chevron => BiliColors.secondaryText;
  static const valueGap = 7.0;

  static const switchMotion = Duration(milliseconds: 200);

  /// Grey notes under a section: CDN 节点's and the BTR licence.
  static const footerText = 12.0;
  static Color get footer => BiliColors.secondaryText;
  static const footerTop = 8.0;
  static const footerBottom = 4.0;

  /// 51's alert: 280 pt wide with 8 pt corners over a 70% dim, the title's middle 35.8 pt down, the grey line's
  /// 74.4 pt, a 2 px rule 28 pt below that, and two 44 pt buttons with no rule between them.
  static const confirmWidth = 280.0;
  static const confirmRadius = 8.0;
  static const confirmDim = Color(0xB3000000);
  static Color get confirm => tone(0xFFFFFFFF, 0xFF242628);
  static const confirmTitleText = 16.0;
  static const confirmTitleLine = 22.0;
  static const confirmTitleWeight = FontWeight.w500;
  static Color get confirmTitle => BiliColors.text;
  static const confirmTitleTop = 35.8 - confirmTitleLine / 2;
  static const confirmMessageText = 13.0;
  static const confirmMessageLine = 18.0;
  static Color get confirmMessage => BiliColors.secondaryText;
  static const confirmMessageGap = 74.4 - 35.8 - (confirmTitleLine + confirmMessageLine) / 2;
  static const confirmMessageBottom = 28.0 - confirmMessageLine / 2;
  static const confirmSide = 20.0;
  static const confirmRule = 2 / 3;
  static Color get confirmRuleColor => BiliColors.divider;
  static const confirmButtonHeight = 44.0;
  static const confirmButtonText = 16.0;
  static Color get confirmCancel => BiliColors.text;
  static Color get confirmAction => BiliColors.pink;
  static Color get confirmPressed => BiliColors.pressedFill;
  static const confirmPressMotion = Duration(milliseconds: 120);

  /// It comes and goes as the other alerts do, settling from slightly large.
  static const confirmIn = CommentOverlayTheme.confirmIn;
  static const confirmOut = CommentOverlayTheme.confirmOut;
  static const confirmStartScale = FavouriteTheme.alertStartScale;
}

/// 首页's bottom bar (01, 02): its height over the home indicator, the hairline above it, the labels.
abstract final class HomeTabBarTheme {
  static Color get bar => BiliColors.card;

  /// 49 pt from the hairline's top to the home indicator's safe area, in five slots of a fifth of the width each.
  static const height = 49.0;
  static Color get hairline => BiliColors.divider;

  /// One pixel, as 01's: this bar's and the one under the tab row.
  static const hairlineWidth = 1 / 3;

  /// Below the bar's top: a glyph's centre, the pink +'s (centred under the hairline) and a label's line box top.
  static const iconCentre = 18.0;
  static const postCentre = 74 / 3;
  static const labelTop = 94 / 3;
  static const labelText = 11.0;
  static Color get label => tone(0xFF61666D, 0xFFA2A7AE);
  static Color get selected => BiliColors.pink;

  /// 首页's search entry beside the avatar (01): 300 pt of the row, ending 76 pt short of the screen's edge, in a
  /// 2 px grey outline; the magnifier's centre and the word's start from the outline's left edge, the word cut
  /// short of the right one.
  static const fieldGap = 11.0;
  static const fieldWidth = 300.0;
  static Color get fieldOutline => BiliColors.secondaryText;
  static const fieldOutlineWidth = 2 / 3;
  static const fieldGlyph = SearchGlyphTheme.magnifierSize;
  static const fieldGlyphCentre = 18.0;
  static const fieldGlyphRise = 1 / 3;
  static const fieldTextStart = 89 / 3;
  static const fieldTextEnd = 14.0;
  static const fieldText = 15.0;
  static Color get fieldInk => tone(0xFF61666D, 0xFFA2A7AE);

  /// The 推荐 refresh 首页's tap runs: the scroll back to the top, then the pull-to-refresh TV's room opening.
  static const reloadScroll = Duration(milliseconds: 300);
  static const reloadHeader = Duration(milliseconds: 200);

  /// Once a refresh's cards come (14), from the same frame: [reloadCollapse] closes the room 首页's tap opened for its
  /// TV (a pull's room closes by the scroll's own spring), and over [handOff] the cards on screen fade out over the new
  /// ones, which stand in place at full opacity, with no rise. Fitted to the recording's frames.
  static const reloadCollapse = Duration(milliseconds: 100);
  static const reloadCollapseCurve = Curves.easeInOut;
  static const handOff = Duration(milliseconds: 180);
  static const handOffCurve = Curves.easeOutQuad;

  /// 首页's top dressed by the equipped 装扮 (110): `head_bg` reaches from the screen's top to the top row's bottom
  /// (318 px, where 110's picture meets the tab strip's), `head_tab_bg` fills the tab strip to its hairline, which
  /// takes the page's grey (110's grey starts at 142 pt). The field is filled white with no rim; the avatar, the
  /// field's ink and 推荐's place are 01's.
  static Color get headDivider => BiliColors.pageGrey;
  /// Dressed, the field and its ink are the day's at night too, as the official app keeps them (KaiC).
  static const headField = Color(0xFFFFFFFF);
  static const headFieldInk = Color(0xFF61666D);
  static const headFieldPressed = Color(0x14000000);

  /// The bar dressed by the 装扮 (109, 110), its labels where 01's are, in the skin's colours. On both shots every
  /// icon's ink is 41 pt tall (859-900 pt) and centred 19/3 pt under the bar's top, so its 60 × 45 box (fit centre,
  /// as Android's) rises 16 pt over the bar. 发布's picture is centred 88/3 pt under the bar's top, in the stock +'s
  /// square.
  static const skinIconWidth = 60.0;
  static const skinIconHeight = 45.0;
  static const skinIconCentre = 19 / 3;
  static const skinPostCentre = 88 / 3;
  static const skinPostSize = TabIconTheme.postSquare;

  /// How far an icon's box rises over the bar's top. The bar takes taps that high over each icon (pages run under a
  /// dressed bar, so a press on the icon's top would otherwise land on the page), not over the rest of its picture.
  static const skinIconOverhang = skinIconHeight / 2 - skinIconCentre;

  /// With `tail_icon_ani`, each change of place fades the incoming picture in, rising this far into place.
  static const skinIconMotion = Duration(milliseconds: 300);
  static const skinIconRise = 20.0;
}

/// A 推荐 cover still loading (14): the official grey with its faint 小电视, centred on the cover. The asset is cut to
/// its ink, 117 × 109 px at 3× (the clip's is 117 × 110 px of #CDCDCD); it is drawn white and tinted.
abstract final class CoverPlaceholderTheme {
  /// The APK's art has no night version; at night the palette's nearest greys, Ga2 and Ga3.
  static Color get fill => tone(0xFFDEDFE1, 0xFF2F3134);
  static Color get ink => tone(0xFFCDCDCD, 0xFF46494D);
  static const width = 117 / 3;
  static const height = 109 / 3;

  /// The default face at night: each channel turned over so its light ground (E5E8EF) lands on [fill]'s night value
  /// and its TV (B0B9C0) on [ink]'s.
  static const nightFace = <double>[
    -0.434, 0, 0, 0, 146.4, //
    0, -0.511, 0, 0, 167.5, //
    0, 0, -0.532, 0, 179.1, //
    0, 0, 0, 1, 0,
  ];
}

/// The bottom bar's glyphs (01, 02): their size, strokes and colours, and the + on its pink rounded square.
abstract final class TabIconTheme {
  /// The square each line glyph is drawn in. On 01 and 02 every glyph's ink is centred on its column (88 pt wide) at
  /// y 891 pt; the widest, 关注 and 我的, are 21.33 pt.
  static const size = 22.0;

  static Color get ink => tone(0xFF61666D, 0xFFA2A7AE);
  static Color get selectedInk => BiliColors.pink;

  /// Outlines; 关注's pinwheel is a touch heavier on both shots.
  static const line = 2.0;
  static const fanLine = 2.1;

  /// 首页's smile or mouth, 我的's eyes and antennae.
  static const faceLine = 1.5;

  /// 发布: a 38 pt square (centred at y 897.67 pt on 01, its top at 878.67) with 14 pt corners, shaded top to bottom,
  /// and a white + 13 pt across with 2.5 pt round-capped strokes.
  static const postSquare = 38.0;
  static const postRadius = 14.0;
  static Color get postTop => tone(0xFFFE739A, 0xFFF06C91);
  static Color get postBottom => tone(0xFFFF4AA4, 0xFFF2469C);
  static const postPlus = 13.0;
  static const postPlusLine = 2.5;
  static Color get postPlusInk => tone(0xFFFFFFFF, 0xFFEFF2F2);
}

/// 搜索's page (52-55): the field row, the empty page's 热搜, 搜索历史 and 搜索发现, and the suggestions.
abstract final class SearchTheme {
  static Color get page => BiliColors.card;

  /// Measured on 52-55 at 3 px per pt. Every word on the page is #18191C; the field's grey word, ‹ and 反馈 are
  /// #61666D, the sections' glyphs and 完整榜单 #9499A0.
  static Color get text => BiliColors.text;
  static Color get dim => tone(0xFF61666D, 0xFFA2A7AE);
  static Color get grey => BiliColors.secondaryText;
  static Color get highlight => BiliColors.pink;

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
  static Color get fieldRimColor => BiliColors.secondaryText;
  static const fieldText = 15.0;
  static const fieldLine = 21.0;
  static const magnifierInset = 35 / 3;
  static const magnifier = SearchGlyphTheme.magnifierSize;
  static const magnifierLift = 2 / 3;
  static const magnifierGap = 6.0;
  static Color get caret => BiliColors.pink;

  /// The grey ⓧ: 13.3 across, its middle 18 from the field's right end, in a 36 wide target.
  static const clear = 40 / 3;
  static Color get clearColor => tone(0xFFC9CCD0, 0xFF46494D);
  static const clearRight = 18.0;
  static const submitWidth = 64.0;
  static const submitText = 16.0;
  static const submitDrop = 0.5;
  static Color get submit => BiliColors.pink;

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
  static Color get rule => tone(0xFFC9CCD0, 0xFF46494D);
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
  static Color get chipFill => tone(0xFFF6F7F8, 0xFF1E2022);
  static const foldedRows = 2;
  static const historyMotion = Duration(milliseconds: 250);

  /// 搜索发现's cells: two columns 7 apart, 30 tall, 8 between rows, the word 8 in.
  static const cellHeight = 30.0;
  static const cellGap = 7.0;
  static const cellRunSpacing = 8.0;
  static const cellPadding = 8.0;
  static const cellRadius = 4.0;
  static Color get cellFill => tone(0xFFF6F7F8, 0xFF1E2022);
  static const discoveryWords = 12;

  /// A 搜索发现 word's grey "·昨天更新" (52's first cell).
  static Color get suffix => grey;

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
  static Color get suggestionHairlineColor => tone(0xFFD9DBDE, 0xFF383A3E);
}

/// 搜索's results (56, 57, 59-61): the tab row, the video and uploader rows, the ⋮ sheet.
abstract final class SearchResultTheme {
  static Color get page => BiliColors.card;

  /// Over results the field row and the tab row: white by day; at night 254's darker grey, which ends the header
  /// in place of [hairlineInk].
  static Color get headerFill => tone(0xFFFFFFFF, 0xFF101011);

  /// The tab row: 40 under the field row (which ends 106 down, where 55's suggestions start), then a hairline across
  /// the page, lighter than the rows' own. Labels sit in 54 wide slots from the left edge, the shown one 16 and pink,
  /// the others 15 and grey, all on one baseline.
  static const tabRowHeight = 40.0;
  static const hairline = 1 / 3;
  static Color get hairlineInk => tone(0xFFE3E5E7, 0xFF101011);
  static Color get rowHairlineInk => tone(0xFFD9DBDE, 0xFF383A3E);
  static const tabSlot = 54.0;
  static const tabText = 15.0;
  static const tabSelectedText = 16.0;
  static const tabBaseline = 77 / 3;
  static Color get tabInk => tone(0xFF61666D, 0xFFA2A7AE);
  static Color get tabSelected => BiliColors.pink;
  static const indicatorWidth = 18.0;
  static const indicatorHeight = 3.0;
  static const indicatorTop = 34.0;
  static const tabMotion = Duration(milliseconds: 200);

  /// 筛选's funnel, centred 26 from the right edge and 19.5 down the tab row; pink while 筛选 is open (58).
  static const funnel = 52 / 3;
  static const funnelCentreRight = 26.0;
  static const funnelCentreTop = 19.5;
  static const funnelTarget = 44.0;
  static Color get funnelInk => tabInk;
  static Color get funnelOpen => BiliColors.pink;

  /// 用户's 默认排序 and 全部用户 (60), each centred in half the width; on 用户 the hairline runs under this row, not the
  /// tab row.
  static const sortRowHeight = 119 / 3;
  static const sortText = 13.0;
  static Color get sortInk => tabInk;
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
  static Color get coverPlaceholder => tone(0xFFF1F2F3, 0xFF1E2022);
  static const textGap = 8.0;

  /// Two title lines 19.33 apart, their first ink 3.3 under the cover's top; they wrap before 422.
  static const titleText = 14.0;
  static const titleLine = 58 / 3;
  static const titleTop = 0.0;
  static const titleRight = 18.0;
  static Color get titleInk => BiliColors.text;
  static Color get highlight => BiliColors.pink;

  /// UP and ▷ lines, ink centred 27.33 and 8.5 above the cover's bottom; both glyphs start 1.33 into their 13.67
  /// slot, ▷ 12.67 wide.
  static const metaText = 12.0;
  static const metaLine = 17.0;
  static const metaGap = 2.2;
  static const metaBottom = -0.2;
  static Color get metaInk => BiliColors.secondaryText;
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
  static Color get nameInk => BiliColors.text;
  static const nameLine = 20.0;
  static const levelGap = 5.0;
  static const countsText = 12.0;
  static const countsLine = 17.0;
  static Color get countsInk => BiliColors.secondaryText;

  /// Where each line centres from the avatar's centre, with the counts alone or with the description under them.
  static const nameCentreTwo = -11.17;
  static const countsCentreTwo = 13.0;
  static const nameCentreThree = -18.67;
  static const countsCentreThree = 1.33;
  static const descCentreThree = 20.33;

  /// The bolt disc at the avatar's lower right, ringed in white: yellow for a person, blue for an organisation.
  static const badge = 40 / 3;
  static const badgeRing = 4 / 3;
  static Color get badgePerson => IntroTheme.badgePerson;
  static Color get badgeOrganisation => IntroTheme.badgeOrganisation;
  static const badgeBolt = Color(0xFFFFFFFF);

  /// "+ 关注": the pink pill 12 from the right, level with the avatar; followed, 简介's grey 已关注.
  static const followWidth = 70.0;
  static const followHeight = 24.0;
  static const followText = 13.0;
  static const followPlus = 29 / 3;
  static const followPlusStroke = 1.2;
  static const followPlusGap = 13 / 3;
  static Color get followFill => BiliColors.pink;
  static const followInk = BiliColors.onPink;
  static Color get followedFill => IntroTheme.followedFill;
  static Color get followedInk => IntroTheme.followedText;
  static const followPressedScale = IntroTheme.followPressedScale;

  /// 简介's: the fill and words change over [followMotion], the label fading in from [followSwapScale]; a press
  /// shrinks the pill over [followPressMotion].
  static const followMotion = Duration(milliseconds: 220);
  static const followPressMotion = Duration(milliseconds: 120);
  static const followSwapScale = 0.85;
  static const textRight = 12.0;

  /// The next page's spinner, 重试 and 没有找到相关内容.
  static const stateText = 14.0;
  static Color get stateInk => BiliColors.secondaryText;
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
  static Color get sheetFill => tone(0xFFF6F7F8, 0xFF202123);
  static const sheetRadius = 12.0;
  static const sheetInset = 16.0;
  static const grabberTop = 8.0;
  static const grabberWidth = 30.0;
  static const grabberHeight = 3.0;
  static Color get grabberInk => tone(0xFFC5C6C6, 0xFF4D4D4F);
  static const sheetCardTop = 19.0;
  static const sheetCardHeight = 137 / 3;
  static const sheetCardRadius = 6.0;
  static Color get sheetCardFill => tone(0xFFFFFFFF, 0xFF242628);
  static const sheetIcon = 18.0;
  static const sheetIconLeft = 13.0;
  static const sheetIconGap = 9.0;
  static const sheetText = 18.0;
  static Color get sheetInk => BiliColors.text;
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
  static Color get panel => BiliColors.card;

  /// 58's rhythm: the first title's middle 20 below the panel's top, each title's middle 18.67 above its chips and
  /// 24.33 below the chips before it. 58 cuts the panel off under a fade at 450 pt, so the bottom is the space a chip
  /// grid leaves above the next title's ink.
  static const side = BiliMetrics.gutter;
  static const firstTitleMiddle = 20.0;
  static const titleToChips = 56 / 3;
  static const chipsToTitle = 73 / 3;
  static const bottom = 56 / 3;

  static const titleText = 12.0;
  static Color get title => BiliColors.text;

  /// Four to a row, 99 wide at 440 pt: 58 floors the width to a whole point, leaving 14 on the right.
  static const columns = 4;
  static const chipHeight = 26.0;
  static const chipGap = 6.0;
  static const chipRowGap = 10.0;
  static const chipRadius = 4.0;
  static const chipText = 12.0;

  /// 58 draws 内容时长's digits a pixel further apart than SF and a point further from Chinese; Flutter's SF draws
  /// neither.
  static const chipLatinSpacing = 1 / 3;
  static const chipHanGap = 1.0;

  /// The chosen chip keeps the same grey; only its label turns the deeper pink of the comment composer's accent.
  static Color get chip => tone(0xFFF6F7F8, 0xFF1E2022);
  static Color get chipLabel => tone(0xFF61666D, 0xFFA2A7AE);
  static Color get chipChosenLabel => tone(0xFFED7098, 0xFFD44E7D);
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

  /// How far a pull goes before it arms.
  static const trigger = 100.0;

  /// 正在努力加载... under the TV on a page's first load (64, 67).
  static const stateText = 14.0;
  static Color get stateInk => tone(0xFF86898B, 0xFF757A81);

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
  static Color get fill => BiliColors.card;
  static const radius = 12.0;
  static const grabberTop = 8.0;
  static const grabberWidth = 30.0;
  static const grabberHeight = 3.0;
  static Color get grabber => BiliColors.sheetGrabber;

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
  static Color get nameInk => BiliColors.text;
  static const nameLine = 20.0;
  static const nameCentre = 106 / 3;

  /// The name's line ends this far from the right edge, clear of 进入空间.
  static const nameRight = 100.0;
  static const countsText = 12.0;
  static Color get countsInk => BiliColors.secondaryText;
  static const countsLine = 17.0;

  static const countsCentre = 62.0;
  static const countsGap = 8.5;

  /// The counts fade in once the space answers.
  static const countsFade = Duration(milliseconds: 220);

  /// PingFang sets digits a little apart from the Chinese they meet ("3 万粉丝"); Flutter's layout sets them touching.
  static const countsHanGap = 5 / 3;
  static const enterText = 13.0;
  static Color get enterInk => tone(0xFF61666D, 0xFFA2A7AE);
  static const enterCentre = 44.0;
  static const enterLine = 18.0;

  /// 进入空间's Chinese draws half a point under its line's middle, where the chevron centres.
  static const enterTextLift = 0.5;
  static const enterRight = 49 / 3;
  static const chevronWidth = 20 / 3;
  static const chevronHeight = 12.0;
  static const chevronStroke = 1.0;
  static Color get chevronInk => tone(0xFF939393, 0xFF757A81);
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
  static Color get followedFill => IntroTheme.followedFill;
  static Color get followedInk => IntroTheme.followedText;
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
  static Color get titleInk => BiliColors.text;

  /// The page's own video: its title pink after the playing mark, 2 in from the title's start and 6 before its text,
  /// a little under the line's middle. The mark is 简介's moving one with its bars 3.6 apart, as 62 and 68 draw it
  /// (1.5 wide, 10.65 tall at full stretch), centred in the 8.4 × 10 box the still bars took.
  static Color get playingInk => BiliColors.pink;
  static Color get barsInk => tone(0xFFEB7093, 0xFFD44E7D);
  static const barsLead = 2.0;
  static const barsTrail = 6.0;
  static const barsDrop = 0.25;
  static const barsBox = Size(8.4, 10);
  static const barPitch = 3.6;
  static const barsHeight = IntroListTheme.barsHeight * barPitch / IntroListTheme.barStep;

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
  static Color get endInk => tone(0xFF727272, 0xFF8B9097);
  static const spinnerRadius = 10.0;

  /// The first load's TV, its failure and 重试.
  static const stateText = 14.0;
  static Color get stateInk => BiliColors.secondaryText;
  static const stateGap = 16.0;
  static const retryText = 14.0;
  static const retryHeight = 30.0;
  static const retryPadX = 20.0;
  static const retryRim = 1.0;
}

/// UP主空间's header, its collapsed bar and its tab row (63, 69-73, 75, 77-79), measured in px / 3 from the screen's
/// top with the header unscrolled.
abstract final class SpaceTheme {
  static Color get page => BiliColors.card;

  /// The banner runs under the status bar to 187.67; a space without one draws this light fill in its place.
  static const bannerHeight = 563 / 3;
  static Color get bannerDefault => tone(0xFFF3F2F7, 0xFF1A1B1D);

  /// 〈, 私信, search and ⋮: 30 pt discs of black at 30% centred 7 under the safe area's top, 〈 25 from the left and
  /// the others 109, 67 and 25 from the right. Their glyphs are white over the banner and grey on the white bar.
  static const buttonDrop = 7.0;
  static const button = 30.0;
  static const buttonTarget = 44.0;
  static const buttonFill = Color(0x4D000000);
  static const buttonInk = Color(0xFFFFFFFF);
  static Color get barInk => tone(0xFF61666D, 0xFFA2A7AE);
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
  static Color get bar => tone(0xFFFFFFFF, 0xFF17181A);
  static const barFade = Duration(milliseconds: 150);

  /// The bar's centred pill (73, 77): a 30 tall tint with the 26 pt face 2 in from its left, + 关注 8.33 after it and
  /// 13 clear of the text's ink on the right.
  static const pillHeight = 30.0;
  static const pillFace = 26.0;
  static const pillFaceInset = 2.0;
  static const pillFaceGap = 25 / 3;
  static const pillPadRight = 12.0;
  static Color get pillFill => tone(0xFFFFECF1, 0xFF2F1A22);
  static Color get pillInk => BiliColors.pink;
  static Color get pillFollowedFill => tone(0xFFF1F2F3, 0xFF2F3134);
  static Color get pillFollowedInk => BiliColors.secondaryText;
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
  static Color get faceRingInk => tone(0xFFFFFFFF, 0xFF17181A);
  static const faceBadge = 24.0;

  /// 粉丝 | 关注 | 获赞: three equal columns from 153.5 to 9.5 short of the right edge with 1 pt rules between them,
  /// the count's ink centred 202.5 down and the label's 220.5.
  static const statsLeft = 153.5;
  static const statsRight = 9.5;
  static const countCentre = 202.5;
  static const countLine = 18.0;
  static const countText = 14.0;
  static Color get countInk => BiliColors.text;
  static const labelCentre = 220.5;
  static const labelLine = 14.0;
  static const labelText = 11.0;
  static Color get labelInk => BiliColors.secondaryText;
  static const statsRuleTop = 607 / 3;
  static const statsRule = 16.0;
  static const statsRuleWidth = 1.0;
  static Color get statsRuleInk => BiliColors.divider;

  /// The 关注 row, 30 tall at 232.67 from 156 to 12 short of the right edge: + 关注 pink across what 充电 leaves;
  /// followed, 已关注 (grey) and ▽ (30 square) 2 after it (70). 充电 (83 wide, outlined, 4 before the rest) shows
  /// whenever the uploader takes it (78, 79).
  static const followTop = 698 / 3;
  static const followHeight = 30.0;
  static const followLeft = 156.0;
  static const followRight = 12.0;
  static const followRadius = 4.0;
  static const followText = 14.0;
  static Color get followFill => BiliColors.pink;
  static const followInk = Color(0xFFFFFFFF);
  static const followPlus = 34 / 3;
  static const followPlusStroke = 1.0;
  static const followPlusGap = 13 / 3;

  /// Each label sits a little right of its button's middle: + 关注 and 已关注 by 0.67, 充电 by 2.33 (63, 70).
  static const followShift = 2 / 3;
  static const chargeShift = 7 / 3;
  static Color get followedFill => BiliColors.divider;
  static Color get followedInk => BiliColors.secondaryText;
  static const followedListWidth = 12.0;
  static const followedListHeight = 26 / 3;
  static const followedListStroke = 0.9;
  static const followedListGap = 11 / 3;
  static const chargeWidth = 83.0;
  static const chargeGap = 4.0;
  static const chargeBorder = 1.0;
  static Color get chargeInk => BiliColors.pink;
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
  static Color get nameInk => tone(0xFF2F3238, 0xFFD0D3D7);
  static Color get nameVipInk => BiliColors.pink;
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
  static Color get levelInk => tone(0xFFFFFFFF, 0xFF17181A);

  /// bilibili UP主认证's line takes the bio's place and moves the rest down 30 (78): a 22 tall grey pill with the
  /// verification's 16 pt disc 5 in, its bolt 0.44 of the disc wide and 0.62 tall.
  static const officialBlock = 30.0;
  static const officialCentre = 18.5;
  static const officialHeight = 22.0;
  static Color get officialFill => tone(0xFFF1F2F3, 0xFF1E2022);
  static const officialDisc = 16.0;
  static const officialBoltWidth = officialDisc * 0.44;
  static const officialBoltHeight = officialDisc * 0.62;
  static const officialBolt = Color(0xFFFFFFFF);
  static const officialDiscInset = 5.0;
  static const officialTextGap = 6.0;
  static const officialPadRight = 8.0;
  static const officialText = 12.0;
  static Color get officialInk => tone(0xFF61666D, 0xFFA2A7AE);

  /// The bio stops short of 详情 even when 详情 is on the line above (69, 78).
  static const bioGap = 41 / 6;
  static const bioBox = 21.0;
  static const bioText = 12.0;
  static Color get bioInk => BiliColors.secondaryText;
  static const bioRight = 40.0;
  static const detailText = 12.0;
  static Color get detailInk => BiliColors.link;

  /// IP属地 and the like on one row, 11.33 apart: a 10.33 × 8.67 IP box 1 in, the text's ink 3.33 after it; a link
  /// ends with ›.
  static const tagGap = 41 / 6;
  static const tagBox = 15.0;
  static const tagText = 10.0;
  static Color get tagInk => tone(0xFF61666D, 0xFFA2A7AE);
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

  /// 小店 and 充电: 40 tall grey cards, side by side 8 apart when there are two (78), the icon 10 in (小店's bag 12 ×
  /// 10.5), the title 12 pt and the note 11 pt, its ink ending 9 from the right.
  static const entriesGap = 12.0;
  static const entryHeight = 40.0;
  static const entrySpacing = 8.0;
  static const entryRadius = 4.5;
  static Color get entryFill => tone(0xFFF6F7F8, 0xFF1E2022);
  static const entryPad = 10.0;
  static const entryPadRight = 25 / 3;
  static const entryIcon = 12.0;
  static const entryShopHeight = 10.5;
  static const entryBoltWidth = 25 / 3;
  static const entryBoltHeight = 13.0;
  static const entryIconGap = 13 / 3;
  static const entryText = 12.0;
  static const entryTextDrop = 2 / 3;
  static Color get entryInk => BiliColors.text;
  static const entryNoteText = 11.0;
  static Color get entryNoteInk => tone(0xFF61666D, 0xFFA2A7AE);
  static Color get entryIconInk => tone(0xFFFFC200, 0xFFCC9B00);
  static const bottomGap = 16.0;

  /// The tab row: 39.5 between 0.5 pt hairlines. Its labels sit in equal cells across the width and 4 beyond each
  /// edge (63's five, 78's four, 69's three); the shown one pink over a 14 × 2 bar 4 above the lower hairline.
  static const tabsHairline = 0.5;
  static const tabsBody = 39.5;
  static const tabsHeight = tabsHairline * 2 + tabsBody;
  static Color get tabsHairlineInk => BiliColors.divider;
  static const tabsSpread = 4.0;
  static const tabText = 16.0;
  static const tabLine = 22.0;
  static Color get tabInk => tone(0xFF61666D, 0xFFA2A7AE);
  static Color get tabSelected => BiliColors.pink;
  static const indicatorWidth = 14.0;
  static const indicatorHeight = 2.0;
  static const indicatorBottom = 4.0;

  /// 已关注's sheet (71): rows 50 tall, the second and third with a 0.5 pt rule along their top from 20 in, a 5 pt
  /// gap, then 取消 in a 56 tall row with 14 under it, over the page dimmed by half.
  static const sheetDim = Color(0x80000000);
  static Color get sheetFill => tone(0xFFFFFFFF, 0xFF1E2022);
  static const sheetShadow = Color(0x1F000000);
  static const sheetShadowBlur = 12.0;
  static const sheetRow = 50.0;
  static const sheetRule = 0.5;
  static Color get sheetRuleInk => tone(0xFFAEB3B9, 0xFF2F3134);
  static const sheetInset = 20.0;
  static const sheetText = 14.0;
  static Color get sheetInk => BiliColors.text;
  static const sheetGap = 5.0;
  static Color get sheetGapFill => tone(0xFFE3E5E7, 0xFF0A0B0C);
  static const sheetCancel = 56.0;
  static const sheetCancelText = 16.0;
  static const sheetBottom = 14.0;
  static const sheetIn = Duration(milliseconds: 280);
  static const sheetOut = Duration(milliseconds: 220);

  /// Why the space didn't load, with 点击重试 under it, in the middle of the page.
  static const retryText = 14.0;
  static Color get retryInk => BiliColors.secondaryText;
  static Color get retryAction => BiliColors.link;
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
  static Color get chipInk => tone(0xFF61666D, 0xFFA2A7AE);
  static Color get chipChosenInk => BiliColors.pink;
  static Color get chipChosenFill => tone(0xFFFFECF1, 0xFF2F1A22);
  static Color get chipRim => BiliColors.divider;
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
  static Color get playAllGlyphInk => BiliColors.pink;
  static const playAllTextLeft = 40.0;
  static const playAllText = 14.0;
  static Color get playAllInk => BiliColors.text;

  /// ≡ 最新发布: three 12 wide bars 1.33 thick and 4 apart, 3.67 before 12 pt grey words ending 12.33 from the edge.
  static const sortGlyphWidth = 12.0;
  static const sortGlyphBar = 4 / 3;
  static const sortGlyphPitch = 4.0;
  static Color get sortGlyphInk => tone(0xFF999999, 0xFF757A81);
  static const sortGlyphGap = 11 / 3;
  static const sortText = 12.0;
  static Color get sortInk => BiliColors.secondaryText;
  static const sortRight = 37 / 3;

  /// A row (63, 69, 70): 93 with its hairline, the 128 × 72 cover 10 down with a 4 corner, then 10 to a 1 pt hairline
  /// from the gutter to the edge.
  static const rowHeight = 93.0;
  static const rowPadTop = 10.0;
  static const rowPadBottom = 10.0;
  static const hairline = 1.0;
  static Color get hairlineInk => BiliColors.divider;
  static const coverWidth = 128.0;
  static const coverHeight = 72.0;
  static const coverRadius = 4.0;
  static Color get coverPlaceholder => tone(0xFFF1F2F3, 0xFF1E2022);
  static const textGap = 10.0;

  /// Two 14 pt title lines 18 apart, the first's ink 0.67 under the cover's top; they wrap before 428.
  static const titleText = 14.0;
  static const titleLine = 18.0;
  static const titleTop = -1.88;
  static const titleRight = 12.0;
  static Color get titleInk => BiliColors.text;

  /// The date and the counts in 11 pt grey, centred 46.67 and 66 under the cover's top. The ▶ box starts 1 in, the
  /// danmaku box 80 after it whatever the plays' width; each number 3 after its 14 × 12 box.
  static const metaText = 11.0;
  static const metaLine = 14.0;
  static Color get metaInk => BiliColors.secondaryText;
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
  static Color get moreInk => BiliColors.secondaryText;

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
  static Color get badgeFill => BiliColors.pink;
  static const badgeInk = BiliColors.onPink;

  /// Rows scrolled this close to the end ask for the next page.
  static const loadAhead = 360.0;

  /// Under the rows: the next page's small spinner, 已经到底啦~ (76's #727272 14 pt) or the failure, in a 20 line 16
  /// clear of the last hairline. Before the first page: the loading TV, the failure or the end, 40 under the strip.
  static const footerPad = 16.0;
  static const footerLine = 20.0;
  static const spinnerRadius = 10.0;
  static const endText = 14.0;
  static Color get endInk => tone(0xFF727272, 0xFF8B9097);
  static const stateTop = 40.0;
  static const stateText = 14.0;
  static Color get stateInk => BiliColors.secondaryText;
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
  static Color get menuFill => tone(0xFFFFFFFF, 0xFF242628);
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
  static Color get menuInk => BiliColors.text;
  static const menuTextLeft = 44.0;
  static Color get menuIconInk => BiliColors.pink;
  static const menuIconSlot = 24.0;
  static const menuWatchLaterCentre = 80.5 / 3;
  static const menuWatchLaterIcon = 55 / 3;
  static const menuShareCentre = 77 / 3;
  static const menuShareIcon = 59.5 / 3;
  static const menuShareStroke = 1.2;

  /// 分享's icon sits a little above its row's middle (74).
  static const menuShareLift = 2.5 / 3;
}

/// 推荐's ⋮ sheet, the card after 不感兴趣 and the reasons sheet (90, 91, 92).
abstract final class FeedDislikeTheme {
  /// Both sheets (90, 92): the page dimmed by half, the soft-grey sheet with a 12 corner and its grabber 8 down,
  /// white cards 16 in with an 8 corner, 16 between groups and below the last one.
  static const dim = Color(0x80000000);
  static const sheetIn = Duration(milliseconds: 280);
  static const sheetOut = Duration(milliseconds: 220);
  static Color get sheetFill => BiliColors.softGrey;
  static const sheetRadius = 12.0;
  static const grabberTop = 8.0;
  static const grabberWidth = 30.0;
  static const grabberHeight = 3.0;
  static Color get grabberInk => tone(0xFFC9CCD0, 0xFF46494D);
  static const inset = 16.0;
  static const groupGap = 16.0;
  static const sheetBottom = 16.0;
  static Color get cardFill => BiliColors.card;
  static const cardRadius = 8.0;

  /// Dragged down this far, or flung, a sheet closes.
  static const dragClose = 0.25;
  static const flingClose = 700.0;

  /// 90's rows: 52 tall, the icon's middle 26.67 in from the card's edge and the words 44 in, 14 pt; the hairline
  /// between two rows starts under the words.
  static const menuTop = 19.0;
  static const rowHeight = 52.0;
  static const rowIconCentre = 80 / 3;
  static const rowIconBox = 20.0;
  static const watchLaterIcon = 18.0;

  /// 添加至稍后再看's ring sits a little right of the other icons' middle.
  static const watchLaterShift = 1 / 6;
  static const rowTextLeft = 44.0;
  static const rowText = 14.0;
  static Color get ink => BiliColors.text;
  static const hairline = 1 / 3;
  static Color get hairlineInk => BiliColors.divider;

  /// The line drawings' stroke, 90's and 92's.
  static const glyphStroke = 4 / 3;
  static const tileGlyphStroke = 1.5;

  /// 92: 不感兴趣原因 bold 14, its middle 33 below the sheet's top; tiles 4 across from 55 down, 67 tall and 8 apart,
  /// the icon's middle 24 below a tile's top and the label's 51.5, 11 pt grey.
  static const titleCentre = 33.0;
  static const titleText = 14.0;
  static const titleWeight = FontWeight.w600;
  static const tilesTop = 55.0;
  static const tileHeight = 67.0;
  static const tileGap = 8.0;
  static const tileColumns = 4;
  static const tileIconCentre = 24.0;
  static const tileIconBox = 22.0;
  static const tileLabelCentre = 51.5;
  static const tileLabelText = 11.0;
  static Color get tileLabelInk => tone(0xFF61666D, 0xFFA2A7AE);

  /// 91: the cover blurred under a light shade, a white disc 23.33 across with the ✓ cut out of it, 已减少此类内容推荐
  /// white 13 pt and ↶ 撤销 12 pt in white at 60 %; under the cover, 选择不感兴趣原因 › 14 pt in the middle of the white.
  /// The card keeps its top corners only.
  static const coverBlur = 24.0;
  static const coverShade = Color(0x26000000);
  static const checkDisc = 70 / 3;
  static const checkStroke = 5 / 3;

  /// Middles measured from the cover's middle (the ✓ and the words) and from its bottom (撤销).
  static const checkCentre = -21.5;
  static const messageCentre = 6.5;
  static const messageText = 13.0;
  static const messageInk = Color(0xFFFFFFFF);
  static const undoFromBottom = 20.0;
  static const undoText = 12.0;
  static const undoInk = Color(0x99FFFFFF);
  static const undoGlyphWidth = 26 / 3;
  static const undoGlyphHeight = 9.0;
  static const undoGap = 11 / 3;

  /// ↶ 撤销 sits right of the card's middle, and 选择不感兴趣原因 › left of it, 41.83 below the cover (the middle of
  /// 91's taller card).
  static const undoShift = 3.0;
  static const reasonsCentre = 251 / 6;
  static const reasonsShift = -1.5;
  static const undoGlyphStroke = 1.0;
  static const reasonsText = 14.0;
  static const chevronWidth = 14 / 3;
  static const chevronHeight = 28 / 3;
  static const chevronGap = 11 / 3;
  static const chevronStroke = 1.2;

  static const fadeIn = Duration(milliseconds: 220);
}

/// 我的收藏: the folders, a folder, all videos, a row's ⋮ (80-84), measured at 3 px per pt from the screen's top.
abstract final class FavouritesTheme {
  static const textWeight = FontWeight.w400;

  /// The bar under the status bar (80, 81, 83): ‹ as 历史记录's, 44 tall.
  static const barHeight = HistoryTheme.barHeight;
  static const backTarget = HistoryTheme.backTarget;
  static const backTipX = HistoryTheme.backTipX;
  static const backWidth = HistoryTheme.backWidth;

  /// 收藏 and 追更 (80, 83): 16 pt regular centred 35.92 either side of the page's middle (0.25 left of it), 收藏 pink
  /// over a 12 × 2 bar 15 under the bar's middle, 追更 black.
  static const tabText = 16.0;
  static const tabLine = 22.0;
  static const tabHalfSpacing = 215.5 / 6;
  static const tabCentreShift = -0.25;
  static const tabWidth = 64.0;
  static Color get tabInk => BiliColors.text;
  static Color get tabChosenInk => BiliColors.pink;
  static const tabBarWidth = 12.0;
  static const tabBarHeight = 2.0;
  static const tabBarCentreBelow = 15.0;
  static const tabBarRadius = 1.0;

  /// The chips under the bar: 28 tall, 12 below it and 12 in, 8 apart, 13 pt words 8 in from each side; the chosen
  /// one pink on a pink tint, the other #61666D. The band ends at a #F1F2F3 hairline 157.67 down.
  static const chipsBand = 155 / 3;
  static const chipTop = 12.0;
  static const chipLeft = 12.0;
  static const chipHeight = 28.0;
  static const chipGap = 8.0;
  static const chipPadX = 8.0;
  static const chipRadius = 4.0;
  static const chipText = 13.0;
  static const chipLine = 18.0;
  static Color get chipInk => tone(0xFF61666D, 0xFFA2A7AE);
  static Color get chipChosenInk => BiliColors.pink;
  static Color get chipChosenFill => SpaceVideosTheme.chipChosenFill;
  static const headerHairline = 1 / 3;
  static Color get headerHairlineInk => BiliColors.pageGrey;

  /// The chip row's glyphs, #61666D with 1.33 lines in 40 wide slots ending 2 from the edge (centres 418, 378, 338):
  /// 🔍 15.33 × 15, + 14, the layout's two stacked boxes 15.33 × 16, 83's list 15.33 × 13.67.
  static const toolSlot = 40.0;
  static const toolRight = 2.0;
  static const toolCentreDrop = -0.25;
  static Color get toolInk => tone(0xFF61666D, 0xFFA2A7AE);
  static const toolStroke = 4 / 3;
  static const toolSearch = 46 / 3;
  static const toolPlus = 14.0;
  static const toolLayoutWidth = 46 / 3;
  static const toolLayoutHeight = 16.0;
  static const toolListWidth = 46 / 3;
  static const toolListHeight = 41 / 3;

  /// The folders (80) on the page's grey: white cards 12 in, 8 under the hairline and 8 apart, with a 12 corner.
  static Color get page => BiliColors.softGrey;
  static const listTop = 8.0;
  static const cardInset = 12.0;
  static const cardGap = 8.0;
  static const cardRadius = 12.0;
  static Color get cardFill => BiliColors.card;
  static const cardPad = 12.0;

  /// The title, 16 pt medium, its middle 27 under the card's top; the count 12 pt grey, a lock 12 × 13 and a dot
  /// before it on a private folder, and the › 6.67 × 12 in #C9CCD0 16.67 from the card's right.
  static const cardTitleCentre = 27.0;
  static const cardTitleText = 16.0;
  static const cardTitleLine = 22.0;
  static const cardTitleWeight = FontWeight.w500;
  static Color get cardTitleInk => BiliColors.text;
  static const cardCountText = 12.0;
  static Color get cardCountInk => BiliColors.secondaryText;
  static const chevronWidth = 20 / 3;
  static const chevronHeight = 12.0;
  static const chevronRight = 50 / 3;
  static Color get chevronInk => tone(0xFFC9CCD0, 0xFF46494D);
  static const chevronStroke = 1.2;
  static const chevronGap = 23 / 3;
  static const lockWidth = 12.0;
  static const lockHeight = 13.0;
  static const lockStroke = 1.1;
  static const lockGap = 22 / 3;
  static const dotSize = 5 / 3;
  static const dotGap = 17 / 3;

  /// Three covers 128 × 72, 4 apart with a 6 corner, 50 under the card's top; grey where there's no video. Under
  /// them each title in 12 pt, 5.33 in, its middle 17.83 below; a card ends 16 under the covers, or 41 with titles.
  static const tilesTop = 50.0;
  static const tileWidth = 128.0;
  static const tileHeight = 72.0;
  static const tileGap = 4.0;
  static const tileRadius = 6.0;
  static Color get tileEmpty => tone(0xFFF1F2F3, 0xFF1E2022);
  static const tileTitleText = 12.0;
  static const tileTitleLine = 17.0;
  static const tileTitleInset = 16 / 3;
  static const tileTitleCentre = 53.5 / 3;
  static Color get tileTitleInk => BiliColors.text;
  static const cardBottom = 16.0;
  static const cardBottomTitled = 41.0;

  /// + 新建收藏夹: a 34 tall pill 58 under the last card, a 1 pt #E3E5E7 rim; + 11.33 then 12 pt grey words.
  static const newGap = 58.0;
  static const newHeight = 34.0;
  static const newPadLeft = 40 / 3;
  static const newPadRight = 34 / 3;
  static const newRim = 1.0;
  static Color get newRimInk => BiliColors.divider;
  static const newPlus = 34 / 3;
  static const newPlusStroke = 1.1;
  static const newPlusGap = 4.0;
  static const newText = 12.0;
  static const newLine = 17.0;
  static Color get newInk => BiliColors.secondaryText;
  static const newBottom = 40.0;

  /// A folder's page (81): the bar's 🔍 18, the multi-select list 18.67 × 16.33 and ⋮'s 3.33 dots 6.67 apart in
  /// #484C52, centred 141, 87 and 32.67 from the right.
  static Color get folderBarInk => tone(0xFF484C53, 0xFFB9BDC2);
  static const folderBarStroke = 1.5;
  static const folderSearchRight = 141.0;
  static const folderSelectRight = 87.0;
  static const folderMoreRight = 98 / 3;
  static const folderToolDrop = -0.5;
  static const folderToolSlot = 44.0;
  static const folderSearch = 18.0;
  static const folderSelectWidth = 56 / 3;
  static const folderSelectHeight = 49 / 3;
  static const folderMoreDot = 10 / 3;
  static const folderMorePitch = 20 / 3;

  /// Under the bar: the title in 18 pt regular, its middle 27 below the bar; 创建者 and the count in 12 pt grey,
  /// their middles 60.5 and 78.83 below; 20 in. The rows start 102 below the bar.
  static const folderInset = 20.0;
  static const folderTitleText = 18.0;
  static const folderTitleLine = 25.0;
  static const folderTitleCentre = 27.0;
  static const folderMetaText = 12.0;
  static const folderMetaLine = 18.0;
  static Color get folderMetaInk => BiliColors.secondaryText;
  static const folderOwnerCentre = 60.5;
  static const folderCountCentre = 236.5 / 3;
  static const folderHeader = 102.0;

  /// 点赞, 收藏 and 分享: glyphs centred 132, 82 and 32 from the right and 57.33 below the bar, 10 pt grey words
  /// 80.17 below; 收藏's folder is lighter.
  static const folderActionRights = [132.0, 82.0, 32.0];
  static const folderActionWidth = 50.0;
  static const folderActionGlyphCentre = 172 / 3;
  static const folderActionLabelCentre = 239 / 3;
  static const folderActionText = 10.0;
  static const folderActionLine = 14.0;
  static const folderAddStroke = 1.1;
  static const folderAddDrop = 2 / 3;
  static Color get folderActionInk => tone(0xFF797F87, 0xFF8B9097);
  static Color get folderActionFaint => tone(0xFFAEB3B9, 0xFF5E6267);
  static Color get folderActionLabelInk => BiliColors.secondaryText;
  /// The thumb's and the arrow's ink widths; the icons are drawn by `ActionIcon`, which sizes by its square.
  static const folderLikeInk = 52 / 3;
  static const folderShareInk = 50 / 3;
  static const folderAddWidth = 50 / 3;
  static const folderAddHeight = 14.0;

  /// A video row (81, 83), 历史记录's: 100 tall, the 136 × 76 cover 12 down, a hairline under every row but the
  /// last; the title in two 14 pt lines; the UP and the counts in 12 pt grey, the danmaku's glyph 10 after the plays.
  static const rowHeight = HistoryTheme.rowHeight;
  static const rowPadTop = HistoryTheme.rowPadTop;
  static const gutter = HistoryTheme.gutter;
  static const coverWidth = HistoryTheme.coverWidth;
  static const coverHeight = HistoryTheme.coverHeight;
  static const coverRadius = HistoryTheme.coverRadius;
  static Color get coverEmpty => tone(0xFFF1F2F3, 0xFF1E2022);
  static const textGap = HistoryTheme.textGap;
  static const hairline = HistoryTheme.hairline;
  static Color get divider => HistoryTheme.divider;
  static const rowTitleText = HistoryTheme.rowTitleText;
  static const rowTitleLine = HistoryTheme.rowTitleLine;
  static const rowTitleTop = HistoryTheme.rowTitleTop;
  static const titleRight = HistoryTheme.titleRight;
  static Color get rowTitleInk => BiliColors.text;
  static const metaText = HistoryTheme.metaText;
  static const metaLine = HistoryTheme.metaLine;
  static const metaGap = HistoryTheme.metaGap + 0.5;
  static const metaBottom = HistoryTheme.metaBottom;
  static Color get metaInk => HistoryTheme.meta;
  static const glyphBox = HistoryTheme.glyphBox;
  static const glyphGap = HistoryTheme.glyphGap;
  static const countGlyphWidth = BiliMetrics.endCountIconWidth;
  static const countGlyphHeight = BiliMetrics.endCountIconHeight;
  static const countGap = 10.0;

  /// On the counts' line (81, 83) the digits sit a third of a point higher than the UP's name, the glyphs 0.67.
  static const countLift = 1 / 3;
  static const countGlyphLift = 2 / 3;
  static const moreCentreRight = HistoryTheme.moreCentreRight;
  static const moreTarget = HistoryTheme.moreTarget;

  /// The length on the cover, and the pink line of how much was watched (83's, #FA6496).
  static const pillFont = HistoryTheme.pillText;
  static const pillHeight = HistoryTheme.pillHeight;
  static const pillPadX = HistoryTheme.pillPadX;
  static const pillRight = 4.0;
  static const pillBottom = HistoryTheme.pillBottom;
  static const pillRadius = HistoryTheme.pillRadius;
  static const pillFill = HistoryTheme.pillFill;
  static const pillInk = HistoryTheme.pillInk;
  static const progressHeight = HistoryTheme.progressHeight;
  static const progressRadius = 1.0;
  static Color get progress => tone(0xFFFA6496, 0xFFD44E7D);

  /// Under the last row (84): 仅展示本App中可查看的稿件 in 12 pt #C9CCD0, its middle 40.5 below the row.
  static const endText = 12.0;
  static Color get endInk => tone(0xFFC9CCD0, 0xFF46494D);
  static const endLine = 17.0;
  static const endTop = 94 / 3;
  static const endBottom = 95 / 3;

  /// Loading more, a failure and the page's states, as 历史记录's.
  static const footerPad = HistoryTheme.footerPad;
  static const footerText = HistoryTheme.footerText;
  static Color get footerInk => HistoryTheme.footerInk;
  static const spinnerRadius = HistoryTheme.spinnerRadius;
  static const stateText = HistoryTheme.stateText;
  static const stateGap = HistoryTheme.stateGap;
  static Color get stateInk => HistoryTheme.stateInk;
  static const loginText = HistoryTheme.loginText;
  static const loginHeight = HistoryTheme.loginHeight;
  static const loginPadX = HistoryTheme.loginPadX;
  static const retryText = HistoryTheme.retryText;
  static const retryPadX = HistoryTheme.retryPadX;
  static const retryHeight = HistoryTheme.retryHeight;
  static const buttonWeight = HistoryTheme.buttonWeight;

  /// Rows scrolled this close to the end ask for the next page.
  static const loadAhead = 360.0;

  /// ⋮'s sheet (82), 历史记录's (48) without its row of other apps: 取消收藏's star, struck through, 26 × 25 and 29
  /// under the sheet's top, its words' ink 70.67 under it; then the band and 取消.
  static const sheetDim = HistoryTheme.sheetDim;
  static const sheetIn = HistoryTheme.sheetIn;
  static const sheetOut = HistoryTheme.sheetOut;
  static Color get sheetFill => HistoryTheme.sheetFill;
  static const sheetItemCentre = HistoryTheme.sheetItemCentre;
  static const sheetItemWidth = HistoryTheme.sheetItemWidth;
  static const sheetRemoveHeight = HistoryTheme.sheetDeleteHeight;
  static const sheetStarTop = 29.0;
  static const sheetStarWidth = 26.0;
  static const sheetStarHeight = 25.0;
  static const sheetStarStroke = 1.4;
  static const sheetLabelTop = 227 / 3;
  static const sheetLabelText = HistoryTheme.sheetLabelText;
  static Color get sheetRemoveInk => HistoryTheme.sheetDeleteInk;
  static const sheetBand = HistoryTheme.sheetBand;
  static Color get sheetBandFill => HistoryTheme.sheetBandFill;
  static const sheetCancelHeight = HistoryTheme.sheetCancelHeight;
  static const sheetCancelText = HistoryTheme.sheetCancelText;
  static Color get sheetCancelInk => HistoryTheme.sheetCancelInk;

  /// The layout toggle in 99's list: two rows of a box 7 wide and two bars, the upper one long, 16 × 15.33.
  static const toolLayoutListWidth = 16.0;
  static const toolLayoutListHeight = 46 / 3;

  /// 99's list: a white card per folder, 92 tall with 80's insets; its cover 120 × 66, 13 down, grey when empty; the
  /// title (80's) and the count 142 in, their middles 22.33 and 71.83 down (a private folder's count 0.67 higher, by
  /// its lock).
  static const rowCardHeight = 92.0;
  static const rowCoverTop = 13.0;
  static const rowCoverWidth = 120.0;
  static const rowCoverHeight = 66.0;
  static const rowTextLeft = 142.0;
  static const rowTitleCentre = 67 / 3;
  static const rowCountCentre = 215.5 / 3;
  static const rowPrivateCountLift = 2 / 3;
  static const rowLockInset = 2.0;
  static const rowTitleGap = 8.0;

  /// ▶ 播放: a 52 × 24 pill 12 from the card's right, centred; a rounded ▶ 8.67 × 9.33, 7.67 in and 3.67 before 12 pt
  /// words, #61666D on #F6F7F8. An empty folder's is pale.
  static const playWidth = 52.0;
  static const playHeight = 24.0;
  static const playRight = 12.0;
  static const playPadLeft = 23 / 3;
  static const playGlyphWidth = 26 / 3;
  static const playGlyphHeight = 28 / 3;
  static const playGap = 11 / 3;
  static const playText = 12.0;
  static const playLine = 17.0;
  static Color get playFill => tone(0xFFF6F7F8, 0xFF1E2022);
  static Color get playInk => tone(0xFF61666D, 0xFFA2A7AE);
  static Color get playFillOff => tone(0xFFF9FBFC, 0xFF212325);
  static Color get playInkOff => tone(0xFFAFB2B6, 0xFF5E6267);
  static Color get playGlyphOff => tone(0xFFD5D6D8, 0xFF46494D);

  /// 创建 (100): the bar's 创建 20 pt bold and centred, 完成 20 pt ending 20 from the edge, grey (#484C53) until there
  /// is a name; white groups on #F1F2F3, 10 apart and 10 under the bar: 封面 64 tall, 名称 44, 简介 144, 公开 44.
  static const newTitleText = 20.0;
  static const newTitleLine = 28.0;
  static const newTitleWeight = FontWeight.w600;

  /// The stand-ins centre Chinese ink on the line's middle; 100's bar words and labels sit a point higher.
  static const formTextLift = 1.0;
  static const newDoneText = 20.0;
  static const newDoneRight = 20.0;
  static const newDoneTarget = 64.0;
  static Color get newDoneOffInk => tone(0xFF484C53, 0xFFB9BDC2);

  /// Not in 100 (its name is empty): Bilibili's pink, a guess.
  static Color get newDoneInk => BiliColors.pink;
  static Color get newPage => BiliColors.pageGrey;
  static Color get newGroupFill => BiliColors.card;
  static const newGroupGap = 10.0;

  /// 简介's group starts a third of a point lower than the others' gap would put it.
  static const newIntroGap = 31 / 3;
  static const newCoverHeight = 64.0;
  static const newRowHeight = 44.0;
  static const newIntroHeight = 144.0;

  /// Labels 14 pt, 12 in; the fields from 88, 12 short of the edge, their placeholders #AEB3B9. 名称's * is #D0021B.
  /// 简介's label sits with its middle 20.5 under the group's top, its field's first line 22.67.
  static const formText = 14.0;
  static const formLine = 20.0;
  static Color get formInk => BiliColors.text;
  static Color get newHintInk => tone(0xFFAEB3B9, 0xFF5E6267);
  static Color get newRequiredInk => tone(0xFFD0021B, 0xFFE18281);
  static const newLabelLeft = 12.0;
  static const newFieldLeft = 88.0;
  static const newFieldRight = 12.0;
  static const newIntroLabelCentre = 20.5;
  static const newIntroFieldCentre = 68 / 3;
  static const newIntroBottom = 12.0;
  static const newTitleMax = 20;
  static const newIntroMax = 200;

  /// 封面's ›, 80's chevron in #999999; a picked cover's 64 × 36 thumbnail 8 before it.
  static Color get newChevronInk => tone(0xFF999999, 0xFF757A81);
  static const newThumbWidth = 64.0;
  static const newThumbHeight = 36.0;
  static const newThumbRadius = 4.0;
  static const newThumbGap = 8.0;
  static const newThumbBusy = Color(0x66FFFFFF);

  /// 公开's switch, the system's 51 × 31 in #FB7299, 10 from the edge (its 59 × 39 box 6).
  static Color get newSwitchOn => tone(0xFFFB7299, 0xFFD44E7D);
  static const newSwitchRight = 6.0;

  /// 封面's sheet (101), the system's: the page dimmed 20%; 8 in, 从相册选择 and 拍照 57 tall on #EFEFEF with a
  /// #B1B1B2 hairline, then 8 apart 取消 alone on white, bold, with 14 corners and the home bar's 34 under it; 23 pt
  /// #D16585 words.
  static const coverSheetDim = Color(0x33000000);
  static const coverSheetMargin = 8.0;
  static const coverSheetRow = 57.0;
  static const coverSheetGap = 8.0;
  static const coverSheetRadius = 14.0;
  static Color get coverSheetFill => tone(0xFFEFEFEF, 0xFF252527);
  static Color get coverSheetCancelFill => tone(0xFFFFFFFF, 0xFF2C2C2E);
  static const coverSheetHairline = 1 / 3;
  static Color get coverSheetHairlineInk => tone(0xFFB1B1B2, 0xFF3D3D40);
  static const coverSheetText = 23.0;
  static const coverSheetLine = 28.0;
  static const coverSheetTextDrop = 2 / 3;
  static Color get coverSheetInk => tone(0xFFD16585, 0xFFD44E7D);
  static const coverSheetCancelWeight = FontWeight.w600;
}

/// 稍后再看: the list and its empty page (85, 86).
abstract final class WatchLaterTheme {
  static const gutter = 12.0;
  static Color get ink => BiliColors.text;
  static Color get grey => tone(0xFF61666D, 0xFFA2A7AE);

  /// Greyed while nothing can be done (85, and the strip in edit mode, 95).
  static Color get greyOff => tone(0xFFC0C2C5, 0xFF46494D);
  static Color get pinkOff => tone(0xFFFFC2D6, 0xFF76304B);

  /// The title bar (85, 86): ‹ #61666D, its tip 25.96 in and its ends 8.35 above and below; 稍后再看 17 pt bold and
  /// centred; 管理 (取消管理 in edit mode, 95) 14 pt, its words ending 16.67 from the edge.
  static const barHeight = 44.0;
  static const backTarget = 44.0;
  static const backTipX = 25.96;
  static const backEndX = 33.96;
  static const backHalfHeight = 8.35;
  static const backStroke = 1.45;
  static const titleText = 17.0;
  static const titleWeight = FontWeight.w600;
  static const manageText = 14.0;
  static const manageRight = 50 / 3;

  /// The stand-ins sit 稍后再看 0.5 high and the strip's words 0.5 low against 86.
  static const titleDrop = 0.5;
  static const stripTextLift = 0.5;
  static const chipChosenWeight = FontWeight.w500;

  /// 历史记录's UP glyph sits 0.5 lower in its line than 86's.
  static const upGlyphLift = 0.5;

  /// The strip under the bar, 52 tall and ending in a 0.5 hairline, the list 2/3 under the hairline's top. The chips are
  /// 25.67 tall, 13.33 down, 8 apart, 13 pt words 8 in from each side; the chosen one pink on a pink tint (paler in
  /// edit mode, 95). Its line is 26.17 down the strip.
  static const stripHeight = 52.0;
  static const stripCentre = 157 / 6;
  static const stripHairline = 0.5;
  static const listGap = 2 / 3;
  static Color get hairlineInk => BiliColors.divider;
  static const chipTop = 40 / 3;
  static const chipHeight = 77 / 3;
  static const chipGap = 8.0;
  static const chipPadX = 8.0;
  static const chipRadius = 3.0;
  static const chipText = 13.0;
  static Color get chipChosenFill => tone(0xFFFFECF1, 0xFF2F1A22);
  static Color get chipChosenFillOff => tone(0xFFFFF7F9, 0xFF26161C);

  /// ≡↑ 最近添加: three bars and a half-headed arrow, 12.67 × 9.67 from 268.33, 4 before 13 pt words; then 23.33 to
  /// ▶ 播放全部, an 11.33 × 12 rounded triangle 6.3 before its words, which end 12.67 from the edge. The stand-in's
  /// Chinese runs about 0.2 a glyph wider, so the gaps here are a little shorter to keep each piece's middle.
  static const sortGlyphWidth = 38 / 3;
  static const sortGlyphHeight = 29 / 3;
  static const sortGlyphStroke = 1.0;
  static const sortGlyphGap = 3.5;
  static const sortText = 13.0;
  static const sortToPlay = 21.5;
  static const playGlyphWidth = 34 / 3;
  static const playGlyphHeight = 12.0;
  static const playGlyphRound = 1.6;
  static const playGlyphGap = 6.3;
  static const playText = 13.0;
  static const playRight = 37 / 3;

  /// A row (86): 98 tall, the 139 × 78 cover 10 down with a 6 corner; text 10 after it. In edit mode (95) everything
  /// moves 34 right for the circle and the title runs to 12 from the edge; out of it the title stops 28 short, so
  /// 86's line breaks where it does.
  static const rowHeight = 98.0;
  static const rowPadTop = 10.0;
  static const coverWidth = 139.0;
  static const coverHeight = 78.0;
  static const coverRadius = 6.0;
  static Color get coverPlaceholder => tone(0xFFF1F2F3, 0xFF1E2022);
  static const textGap = 10.0;
  static const editShift = 34.0;
  static const editMotion = Duration(milliseconds: 220);

  /// Two 14 pt lines 21.33 apart, the first's middle 8.5 under the cover's top.
  static const titleLineText = 14.0;
  static const titleLine = 64 / 3;
  static const titleTop = -2.5;
  static const titleRight = 28.0;
  static const titleRightEditing = 12.0;

  /// UP and the counts in 12 pt grey, centred 52 and 70 under the cover's top; each glyph 1 in, 13.33 × 11.33, its
  /// words 3.33 after its box; the danmaku glyph 11.33 after the plays.
  static const metaText = 12.0;
  static const metaLine = 16.0;
  static Color get metaInk => BiliColors.secondaryText;
  static const upCentre = 52.0;
  static const countsCentre = 70.0;
  static const metaInset = 1.0;
  static const glyphBox = 41 / 3;
  static const countGlyphWidth = 40 / 3;
  static const countGlyphHeight = 34 / 3;
  static const glyphGap = 10 / 3;
  static const countsGap = 12.0;

  /// ⋮ on the counts' line, centred 20 from the edge: 2.67 dots 4.33 apart.
  static const moreCentreRight = 20.0;
  static const moreTarget = 44.0;
  static const moreDot = 8 / 3;
  static const morePitch = 13 / 3;
  static Color get moreInk => tone(0xFFC9CCD0, 0xFF46494D);

  /// watched / total on the cover, 10 pt white with no pill, its digits ending 8 from the right and 7.33 above the
  /// bottom.
  static const progressText = 10.0;
  static const progressRight = 22 / 3;
  static const progressBottom = 4.9;
  static const progressInk = BiliColors.onCover;
  static const progressLineHeight = 1.2;
  static const progressShadow = Color(0x66000000);
  static const progressShadowBlur = 2.0;

  /// The edit-mode circle (95, 96): 21.33 across, centred 23 in; a hairline grey ring, or pink with a white ✓.
  static const circleCentreX = 23.0;
  static const circleSize = 64 / 3;
  static const circleStroke = 1.0;
  static Color get circleInk => tone(0xFFC9CCD0, 0xFF46494D);
  static Color get circleChosen => BiliColors.pink;
  static const checkInk = BiliColors.onPink;
  static const checkStroke = 1.2;

  /// 仅展示本App中可查看的稿件 under the last row, 12 pt, centred 37.2 below it.
  static const noteTop = 27.2;
  static const noteLine = 20.0;
  static const noteText = 12.0;
  static Color get noteInk => tone(0xFFC9CCD0, 0xFF46494D);
  static const loadAhead = 360.0;
  static const spinnerRadius = 10.0;

  /// The empty page (85): the grey TV, its box 120 × 100 from 160 across and 267.33 under the list's top, and
  /// 暂无稍后再看视频哦 14 pt, centred 406.83 under it.
  static const emptyArtTop = 802 / 3;
  static const emptyArtLeft = 160.0;
  static const emptyArtWidth = 120.0;
  static const emptyArtHeight = 100.0;
  static const emptyTextCentre = 1220.5 / 3;
  static const emptyText = 14.0;
  static Color get emptyInk => BiliColors.secondaryText;
  static Color get artBody => tone(0xFFEBEDEF, 0xFF232527);
  static Color get artShade => tone(0xFFDADCDF, 0xFF2F3134);

  /// Logged out and failed: the words and pink buttons 历史记录 uses.
  static const stateText = HistoryTheme.stateText;
  static const stateGap = HistoryTheme.stateGap;
  static Color get stateInk => HistoryTheme.stateInk;
  static const buttonText = HistoryTheme.loginText;
  static const buttonHeight = HistoryTheme.loginHeight;
  static const buttonPadX = HistoryTheme.loginPadX;
  static const buttonWeight = HistoryTheme.buttonWeight;

  /// 管理's and ⋮'s sheets (93, 94): the page dimmed by 32 % black; a #F6F7F8 sheet with a 12 corner, its grabber 30 × 3
  /// 8 down; one white group 19 down, 16 in from each side, 12 corner, 24 above the home indicator's inset. Rows
  /// 53.44 tall: the 20 pt glyph centred 42 across, 18 pt words from 60, a 0.5 hairline from 60 between rows.
  static const sheetDim = Color(0x52000000);
  static const sheetIn = Duration(milliseconds: 280);
  static const sheetOut = Duration(milliseconds: 220);
  static Color get sheetFill => tone(0xFFF6F7F8, 0xFF202123);
  static const sheetRadius = 12.0;
  static const grabberTop = 8.0;
  static const grabberWidth = 30.0;
  static const grabberHeight = 3.0;
  static Color get grabberInk => tone(0xFFC5C6C6, 0xFF4D4D4F);
  static const groupTop = 19.0;
  static const groupInset = 16.0;
  static const groupRadius = 12.0;
  static const groupBottom = 24.0;
  static Color get groupFill => tone(0xFFFFFFFF, 0xFF242628);
  static const actionRowHeight = 481 / 9;
  static const actionGlyphCentre = 42.0;
  static const actionGlyphSize = 20.0;
  static const actionGlyphStroke = 0.95;
  static const actionTextLeft = 60.0;
  static const actionText = 18.0;
  static const actionWeight = FontWeight.w500;
  static const actionHairline = 0.5;
  static Color get actionHairlineInk => tone(0xFFF1F2F3, 0xFF2F3134);
  static const actionPressed = Color(0x0A000000);
  static const actionIdle = BiliColors.chromeShadeClear;

  /// 复制到 / 移动到's sheet (97, 98): white, 554.67 tall; the 📁 16 × 15 at 12, 24.67 down; 选择收藏夹 22 pt from 34 and
  /// + 新建收藏夹 20 pt grey ending 12 from the edge, centred 32.33 down. The folders from 56.17 down, 61 a row: the
  /// name 20 pt centred 17.33 down (16.83 here: the stand-in sits it 0.5 low), 公开 · N个内容 17 pt grey centred 46.67
  /// down, and a 0.5 hairline 12 in from each side atop every row after the first.
  static const folderSheetHeight = 1664 / 3;
  static Color get folderSheetFill => tone(0xFFFFFFFF, 0xFF1E2022);
  static Color get folderGrabberInk => tone(0xFFC9CCD0, 0xFF46494D);
  static const folderHeaderCentre = 97 / 3;
  static const folderIconLeft = 12.0;
  static const folderIconTop = 74 / 3;
  static const folderIconWidth = 16.0;
  static const folderIconHeight = 15.0;
  static Color get folderIconInk => tone(0xFFF3C14A, 0xFFCCA23E);
  static const folderTitleLeft = 34.0;
  static const folderTitleText = 22.0;
  static const folderNewText = 20.0;
  static const folderNewRight = 12.0;
  static const plusSize = 34 / 3;
  static const plusStroke = 1.2;
  static const plusGap = 5.5;
  static const folderRowsTop = 337 / 6;
  static const folderRowHeight = 61.0;
  static const folderNameCentre = 50.5 / 3;
  static const folderNameText = 20.0;
  static const folderMetaCentre = 140 / 3;
  static const folderMetaText = 17.0;
  static const folderHairline = 0.5;

  /// The edit-mode bar (95, 96): 48 above the home indicator's inset over a 2/3 hairline, a soft shade 31.33 tall
  /// above it; ○ 全选 at the left, 13 pt; 取消选择 / 删除 / 复制到 / 移动到 at the right, 16 apart and ending 12.67 from
  /// the edge, light grey until something is chosen.
  static const editBarHeight = 48.0;
  static const editBarHairline = 2 / 3;
  static const editShadeHeight = 94 / 3;
  static const editShade = Color(0x1A000000);
  static const editShadeClear = BiliColors.chromeShadeClear;
  static const selectAllLeft = 42.0;
  static const editText = 13.0;
  static const editActionGap = 16.0;
  static const editActionRight = 12.67;
  static Color get editActionOff => tone(0xFFC9CCD0, 0xFF46494D);
}

/// The app token's confirm.
abstract final class AppAuthTheme {
  /// The confirm is 设置's alert (51), coming and going as it does there.
  static const promptIn = SettingsTheme.confirmIn;
  static const promptOut = SettingsTheme.confirmOut;
}

/// The account's own space (108, 115): the tall banner, 编辑资料, the name line's pills, the level's exp bar and the
/// bar scrolled.
abstract final class OwnSpaceTheme {
  /// The banner's bottom edge, measured on 108. The face, the counts and 编辑资料 sit where others' spaces have them
  /// (SpaceTheme), [drop] lower.
  static const bannerHeight = 887 / 3;
  static const drop = bannerHeight - SpaceTheme.bannerHeight;
  static const topBlock = SpaceTheme.topBlock + drop;

  /// The 空间头图's label over the banner's foot: a 40 pt band shading from clear at 270 to 60% black at the right edge;
  /// the title (11 pt) set to end 390.67, its last glyph's ink ending 390 as on 108, over the number ending 389.33,
  /// their middles 27.83 and 11.67 above the banner's foot; then a 1 × 10 rule of 40% white 9 after them, its middle
  /// 20 above the foot, and 👕 (17.33 × 15.33 of 1.33 pt line) centred 418 across and 20.33 above the foot.
  static const labelShade = 40.0;
  static const labelShadeLeft = 270.0;
  static const labelShadeClear = Color(0x00000000);
  static const labelShadeInk = Color(0x99000000);
  static const labelTitleRight = 148 / 3;
  static const labelNumberRight = 152 / 3;
  static const labelTitleText = 11.0;
  static const labelTitleLine = 14.0;
  static const labelTitleRise = 83.5 / 3;
  static const labelSubtitleText = 14.0;
  static const labelSubtitleLine = 17.0;
  static const labelSubtitleRise = 35 / 3;

  /// A collectible's picture before the title (24): 14 square, 3 before the title's box, on its line.
  static const labelBadge = 14.0;
  static const labelBadgeGap = 3.0;

  /// The number's block letters (评论's fan card's): 10 tall, 7.83 wide with 2.1 strokes, 2.5 apart; D's right
  /// corners cut 1.67 (24's CD.013149). A subtitle they can't spell is set in 14 pt bold.
  static const labelNumberHeight = 10.0;
  static const labelNumberWidth = 23.5 / 3;
  static const labelNumberWeight = 2.1;
  static const labelNumberGap = 2.5;
  static const labelNumberChamfer = 5 / 3;
  static const labelInk = Color(0xFFFFFFFF);
  static const labelRuleLeft = 399.0;
  static const labelRule = 1.0;
  static const labelRuleHeight = 10.0;
  static const labelRuleInk = Color(0x66FFFFFF);
  static const labelIconRise = 20.0;
  static const skinRise = 61 / 3;
  static const skinCentre = 418.0;
  static const skinWidth = 52 / 3;
  static const skinHeight = 46 / 3;
  static const skinStroke = 4 / 3;
  static const skinInk = Color(0xFFFFFFFF);
  static const skinTarget = 44.0;

  /// An animated 空间头图's sound button (24, 169): the APK's 24 pt disc drawn 26 across, its middle 417 across and 63
  /// above the banner's foot.
  static const soundSize = 26.0;
  static const soundCentre = 417.0;
  static const soundRise = 63.0;
  static const soundTarget = 44.0;

  /// The face's middle, where others' spaces have it. Under a frame it is a 62 pt circle with no ring and the frame
  /// 评论's 1.75 times it; the 大 is a 20 pt disc in a 2 pt white ring, its middle 25.33 right of the face's and 26.67
  /// below. Without a frame the face and its badge are others' (SpaceTheme.face, faceBadge).
  static const faceCentreX = SpaceTheme.faceLeft + SpaceTheme.face / 2;
  static const faceCentreY = SpaceTheme.faceTop + SpaceTheme.face / 2 + drop;
  static const pendantFace = 62.0;
  static const pendantScale = CommentRowTheme.pendantScale;
  static const vipDisc = 20.0;
  static const vipRing = 2.0;
  static Color get vipRingInk => tone(0xFFFFFFFF, 0xFF17181A);
  static const vipPendantShift = Offset(76 / 3, 80 / 3);

  /// 编辑资料 in place of + 关注: the same box, outlined in 1 pt pink with the label centred.
  static const editTop = SpaceTheme.followTop + drop;
  static const editBorder = 1.0;
  static Color get editInk => BiliColors.pink;
  static Color get editFill => SpaceTheme.page;

  /// After the name: the 大会员 label's picture, 5.33 on; then "+ 成就勋章" and "+ 粉丝勋章", 16 tall stadiums of 1 pt
  /// grey dashes (3 on, 3 off), 6.67 after the label and 6.33 apart, the + (8.67 square) 6.67 in and the 10 pt words
  /// 4.33 after it. The picture's pill fills three quarters of its height, clear above and below, so it is drawn
  /// 19.56 tall for 24's pill of 14.67 × 67.33.
  static const vipLabelGap = 16 / 3;
  static const vipLabelHeight = 44 / 3 * 4 / 3;
  static const vipLabelMaxWidth = 120.0;
  static const pillGap = 20 / 3;
  static const pillSpacing = 19 / 3;
  static const pillHeight = 16.0;
  static const pillBorder = 1.0;
  static const pillDash = 3.0;
  static const pillDashGap = 3.0;
  static Color get pillRim => tone(0xFFC9CCD0, 0xFF46494D);
  static const pillPad = 20 / 3;
  static const pillPlus = 26 / 3;
  static const pillPlusGap = 13 / 3;
  static const pillText = 10.0;
  static Color get pillInk => BiliColors.secondaryText;

  /// The level's row between the name and the bio (37.83 from the name's box to the bio's): the LV badge 10.67 tall
  /// from 13.33, its middle 14.67 down; "14805/28800" in 11 pt grey from 42.33, its line's middle 14.5 down (the
  /// digits' ink 14.83); under them a 2 pt bar 101.67 long from the gutter, 23.67 down, filled in the level's colour
  /// by exp / next.
  static const levelBlock = 227 / 6;
  static const levelLeft = 40 / 3;
  static const levelCentre = 44 / 3;
  static const levelHeight = 32 / 3;
  static const expLeft = 127 / 3;
  static const expCentre = 43.5 / 3;
  static const expText = 11.0;
  static const expLine = 14.0;
  static Color get expInk => BiliColors.secondaryText;
  static const expBarTop = 71 / 3;
  static const expBarWidth = 305 / 3;
  static const expBarHeight = 2.0;
  static Color get expTrack => BiliColors.divider;

  /// Scrolled (115): the bar of others' spaces with the name centred in 17 pt, white with the stock look; under a
  /// skin that dresses second pages, the skin's colours.
  static const barName = 17.0;
  static const barNameWidth = 240.0;
  static Color get bar => SpaceTheme.bar;
  static Color get barInk => SpaceTheme.barInk;

  /// A skin's light text without a colour of its own.
  static const barLightInk = Color(0xFFFFFFFF);
}

/// The own space's tabs: 主页's sections (114, 115), 收藏 (116), 追番 (117) and 投稿's empty page (108), measured in
/// px / 3 from the tab row's lower hairline, where a tab's body starts.
abstract final class OwnSpaceTabsTheme {
  static const gutter = SpaceTheme.gutter;

  /// 主页 and 追番 lie on the page's grey, 收藏 and 投稿 on white; either runs on to the screen's bottom.
  static Color get greyPage => BiliColors.softGrey;
  static Color get whitePage => BiliColors.card;

  /// 主页's section header: its line centred 22 down a 44.5 band, the cards under it, then 16.5 to the next band. The
  /// title and its count 14 pt, the count 9 after the title, the eye-slash 8 after the count (9 after a title with
  /// none); 更多 13 pt with its › 9.17 after it, ending 15 from the edge.
  static const headerHeight = 44.5;
  static const headerCentre = 22.0;
  static const headerLine = 20.0;
  static const sectionBottom = 16.5;
  static const titleText = 14.0;
  static Color get titleInk => BiliColors.text;
  static const countText = 14.0;
  static Color get countInk => BiliColors.secondaryText;
  static const countGap = 9.0;
  static const eyeGap = 8.0;
  static const eyeWidth = 46 / 3;
  static const eyeHeight = 34 / 3;
  static const eyeStroke = 1.0;
  static Color get eyeInk => BiliColors.secondaryText;
  static const moreText = 13.0;
  static Color get moreInk => BiliColors.secondaryText;

  /// 更多's words sit half a point above the header's line, its › on it.
  static const moreLift = 0.5;
  static const moreChevronGap = 55 / 6;
  static const moreChevronWidth = 5.0;
  static const moreChevronHeight = 28 / 3;
  static const moreChevronStroke = 1.1;
  static const moreRight = 15.0;

  /// 收藏's folders and the videos: two white cards a row 10 apart, 173 tall with a 6 corner and a soft shadow, the
  /// cover 126 tall across the top.
  static const pairGap = 10.0;
  static const cardHeight = 173.0;
  static const cardRadius = 6.0;
  static Color get cardFill => BiliColors.card;
  static const cardShadow = Color(0x1B000000);
  static const cardShadowBlur = 2.0;
  static const cardShadowDrop = 1.0;
  static const coverHeight = 126.0;
  static Color get coverEmpty => tone(0xFFF1F2F3, 0xFF1E2022);

  /// Under the cover, 10 in: the title 13 pt, its middle 13.33 below (a video's in up to two lines 18 apart); a
  /// folder's "N个内容 · 公开" 12 pt grey, its middle 34.17 below.
  static const cardPadX = 10.0;
  static const cardTitleText = 13.0;
  static const cardTitleLine = 18.0;
  static Color get cardTitleInk => BiliColors.text;
  static const folderTitleCentre = 40 / 3;
  static const folderCountCentre = 205 / 6;
  static const folderCountText = 12.0;
  static const folderCountLine = 17.0;
  static Color get folderCountInk => BiliColors.secondaryText;
  static const videoTitleCentre = 40 / 3;

  /// A video's cover darkens over its bottom 46 for the counts: ▶ and the danmaku box (13.33 × 11.33) in white,
  /// 7.33 in, the 11 pt counts 3.67 after each box and the next box 9.75 after the plays; the length ending 6.5 from
  /// the right; all on a line centred 12 above the cover's bottom.
  static const shadeHeight = 46.0;
  static const shade = Color(0x8C000000);
  static const statText = 11.0;
  static const statLine = 14.0;
  static const statCentre = 12.0;
  static const statLeft = 22 / 3;
  static const statRight = 6.5;
  static const statIconWidth = 40 / 3;
  static const statIconHeight = 34 / 3;
  static const statIconGap = 11 / 3;
  static const statGroupGap = 9.75;
  static const statInk = BiliColors.onCover;

  /// A folder without a cover: the TV in a lighter grey, 81.67 × 76.33 and centred (114). 116's rows draw it smaller
  /// and darker.
  static Color get tvInk => tone(0xFFF6F7F8, 0xFF2B2C2F);
  static const tvWidth = 245 / 3;
  static const tvHeight = 229 / 3;

  /// The folder's badge: a 20 pt square of black at half with a 2.33 corner, 4 in from the cover's lower right (5 up
  /// on 116's rows); the stacked bars and the ▶ card in white.
  static const stackSize = 20.0;
  static const stackRadius = 7 / 3;
  static const stackFill = Color(0x80000000);
  static const stackInk = Color(0xFFFFFFFF);
  static const stackInset = 4.0;

  /// 追番's posters (114, 117): three a row 12 apart, 130.67 × 175 with a 6 corner, darkening over their bottom 47 to
  /// black at 80%; the title 13 pt and the progress 11 pt in white, 5.33 in, their middles 29.5 and 11.33 above the
  /// bottom, the title cut with … 7 short of the right.
  static const posterWidth = 392 / 3;
  static const posterHeight = 175.0;
  static const posterGap = 12.0;
  static const posterRadius = 6.0;
  static Color get posterEmpty => tone(0xFFF1F2F3, 0xFF1E2022);
  static const posterShadeHeight = 47.0;
  static const posterShade = Color(0xCC000000);
  static const posterInk = BiliColors.onCover;
  static const posterTextLeft = 16 / 3;
  static const posterTextRight = 7.0;
  static const posterTitleText = 13.0;
  static const posterTitleLine = 18.0;
  static const posterTitleCentre = 29.5;
  static const posterProgressText = 11.0;
  static const posterProgressLine = 15.0;
  static const posterProgressCentre = 34 / 3;

  /// 拥有的个性装扮 (115): three cards a row 13 apart, 130 wide with a 6 corner. 115 cuts them off 198 down, the title's
  /// 12 pt ink starting 193.17 down; the 9:16 height, the gradient's 60 and the NO. pill are guesses until a
  /// screenshot shows a card whole.
  static const garbWidth = 130.0;
  static const garbHeight = garbWidth * 16 / 9;
  static const garbGap = 13.0;
  static const garbRadius = 6.0;
  static const garbShadeHeight = 60.0;
  static const garbShade = Color(0xB3000000);
  static const garbInk = BiliColors.onCover;
  static const garbTextLeft = 6.5;
  static const garbTextRight = 6.5;
  static const garbTitleText = 12.0;
  static const garbTitleLine = 17.0;
  static const garbTitleCentre = garbHeight - 198.7;
  static const garbNumberCentre = 14.0;
  static const garbNumberHeight = 14.0;
  static const garbNumberPadX = 4.0;
  static const garbNumberRadius = 2.0;
  static const garbNumberText = 9.0;
  static const garbNumberFill = Color(0x66000000);

  /// The section's cards at most: one row of each.
  static const homeFolders = 2;
  static const homeBangumi = 3;
  static const homeVideos = 2;
  static const homeGarbs = 3;

  /// 收藏 (116): the header 48.33 tall, ^ (12 × 6.33, grey) 14 in, 我创建的收藏夹 14 pt from 36.17 and its count 12
  /// pt grey 8.67 after it; a 1 pt #F6F7F8 band under it and after the last row. Each row 12 under the one before:
  /// the 117 × 73 cover with a 4 corner, the title 14 pt 10 after it, its middle 10 under the cover's top, and the
  /// count 12 pt grey, its middle 64.33 under it.
  static const folderHeaderHeight = 145 / 3;
  static const folderChevronLeft = 14.0;
  static const folderChevronWidth = 12.0;
  static const folderChevronHeight = 19 / 3;
  static const folderChevronStroke = 0.9;
  static Color get folderChevronInk => BiliColors.secondaryText;
  static const folderChevronTurn = Duration(milliseconds: 200);
  static const folderHeaderTitleLeft = 217 / 6;
  static const folderHeaderTitleText = 14.0;
  static const folderHeaderCountText = 12.0;
  static const folderHeaderCountGap = 26 / 3;
  static const folderBand = 1.0;
  static Color get folderBandInk => BiliColors.softGrey;
  static const rowGap = 12.0;
  static const rowCoverWidth = 117.0;
  static const rowCoverHeight = 73.0;
  static const rowCoverRadius = 4.0;
  static const rowTextGap = 10.0;
  static const rowTitleText = 14.0;
  static const rowTitleLine = 20.0;
  static const rowTitleCentre = 10.0;
  static const rowCountText = 12.0;
  static const rowCountLine = 17.0;
  static const rowCountCentre = 193 / 3;
  static Color get rowTvInk => tone(0xFFCCCCCC, 0xFF46494D);
  static const rowTvWidth = 34.0;
  static const rowTvHeight = 33.0;
  static const rowStackBottom = 5.0;

  /// 追番 (117): the posters from 11.33 under the hairline, rows 12 apart; 再怎么找也没有啦 14 pt grey, its middle 21.17
  /// under the last row.
  static const bangumiTop = 34 / 3;
  static const endText = 14.0;
  static const endLine = 20.0;
  static Color get endInk => BiliColors.secondaryText;
  static const endCentre = 127 / 6;
  static const endBottom = 20.0;

  /// 投稿 with no videos (108): a 48 disc of #F5F7F9 centred 63.33 down with the upload glyph (#61666D, 1.2 lines);
  /// 发布第一个视频，领新人福利 16 pt grey, its middle 120.67 down; 我要投稿, a 140 × 44 pill rimmed 1 pt pink with 16
  /// pt pink words, centred 173.33 down; 去创作中心领奖 12 pt link blue and its › 7 after it, centred 225.83 down.
  static const emptyDisc = 48.0;
  static Color get emptyDiscFill => tone(0xFFF6F7F8, 0xFF101011);
  static const emptyDiscCentre = 190 / 3;
  static Color get uploadInk => tone(0xFF61666D, 0xFFA2A7AE);
  static const uploadStroke = 1.2;
  static const uploadSize = 20.0;
  static const emptyText = 16.0;
  static const emptyLine = 22.0;
  static Color get emptyInk => BiliColors.secondaryText;
  static const emptyTextCentre = 362 / 3;
  static const uploadPillWidth = 140.0;
  static const uploadPillHeight = 44.0;
  static const uploadPillRim = 1.0;
  static Color get uploadPillInk => BiliColors.pink;
  static const uploadPillText = 16.0;
  static const uploadPillCentre = 520 / 3;
  static const rewardText = 12.0;
  static const rewardLine = 17.0;
  static Color get rewardInk => BiliColors.link;
  static const rewardCentre = 677.5 / 3;
  static const rewardChevronGap = 7.0;
  static const emptyBottom = 40.0;

  /// The first load's TV, the next page's small spinner and 加载失败，点击重试, as 我的收藏's.
  static const stateTop = 40.0;
  static const footerPad = FavouritesTheme.footerPad;
  static const footerText = FavouritesTheme.footerText;
  static Color get footerInk => FavouritesTheme.footerInk;
  static Color get footerRetryInk => BiliColors.link;
  static const spinnerRadius = FavouritesTheme.spinnerRadius;

  /// Lists scrolled this close to the end ask for the next page.
  static const loadAhead = 360.0;
}

/// The equipped 加载动画 in a refresh, in place of the loading TV (119, measured in px / 3). The picture is drawn whole
/// in the TV's own 60 pt square: Violet's 300 px file draws its chibi 42 × 52 pt there, as the official app does. The
/// refresh holds open the picture's own height ([SkinLoadingAnimation.heightIn]), so a square one opens 60 pt: in the
/// official app's Violet refresh the header ends at 142 pt and the first card starts at 208.33, its 6 pt spacing
/// under 60.33 (an 85.33 pt room, taken from the TV's refresh, left Violet 26 pt too low). A pull arms once the whole
/// picture shows, as the official app's starts playing then (KaiC: Violet plays at a 68 pt pull, ours waited for the
/// TV's 100); let go short of the room, the refresh holds what was pulled.
abstract final class SkinLoadingTheme {
  static const size = LoadingTvTheme.size;

  /// Decoded at most this many pixels a side: the box at the phone's 3×.
  static const decodePixels = 180;

  /// A frame time a file leaves at 0 or 10 ms plays at 100 ms, as browsers play such gifs.
  static const shortestFrame = Duration(milliseconds: 20);
  static const defaultFrame = Duration(milliseconds: 100);
}

/// 首页's header folding its top row away as 推荐 scrolls (121, measured in px / 3).
abstract final class HomeHeaderTheme {
  /// The top row (avatar and search) folds away by its own height: the header ends at 142 pt open, 98 pt folded.
  /// All of it moves up by the fold, the 装扮's pictures with it (folded, the screen's top 20 pt show what 44-64 pt
  /// showed open), so the tab row lands under the status bar and the top row fades as it slides under it.
  static const fold = BiliMetrics.topRowHeight;

  /// 推荐 scrolled this far folds it (the first card at the hairline), and back under it opens it again. In 121 the
  /// fold starts in the first frame that scrolled, 6 pt down.
  static const trigger = BiliMetrics.feedSpacing;

  /// Down the list, a finger dragging it down this far opens it (250: the opening starts 15-25 pt into each held
  /// drag; a flick's momentum opens nothing), and this much scrolled back up folds it again (250: from the first
  /// frame that moved, 9 pt).
  static const reveal = 20.0;
  static const refold = 4.0;

  /// 121's frames fit UIKit's ease-in-out over 0.3 s within 0.11 pt (rms over 20 frames).
  static const duration = Duration(milliseconds: 300);
  static const curve = Curves.easeInOut;

  /// The tab row's magnifier, folded: ink 17 pt square from x 412 and y 71 (9 pt under the tab row's top). Its stroke
  /// is 1.83 pt; the search glyph scaled to this size draws 2.1. It rides in from [searchSlide] to the right with the
  /// fold, unfaded, in a [searchTarget] wide tap box at the row's end. The other tabs' grey on white (01's #61666D);
  /// over a 装扮's picture its colour at 72% (121: #393F35 over #D1E1CA under a black 推荐).
  static const searchSize = 52 / 3;
  static const searchRight = 11.0;
  static const searchTop = 26 / 3;
  static const searchTarget = 44.0;
  static const searchSlide = 36.0;
  static Color get searchInk => tone(0xFF61666D, 0xFFA2A7AE);
  static const skinSearchOpacity = 0.72;
}

/// 推荐's refreshes kept as batches: each refresh's page on top, then 刚刚看到这里，点击刷新, then the cards before it
/// (122, measured in px / 3).
abstract final class FeedBatchTheme {
  /// From the bottom of the cards above to the top of the cards below.
  static const dividerGap = 44.0;

  /// The words and the ⟳ in the app's pink. Both read about rgb(253, 89, 140) at their strongest in the recording,
  /// which takes 12 to 14 off green and blue of a saturated colour: the cards' #FF6633 reason tags read (253, 90, 37).
  static Color get ink => BiliColors.pink;

  /// 11 glyphs from x 138 to 279.67 pt, 13 pt apart.
  static const text = 13.0;

  /// The APK's `ic_promo_index_refresh` at its own 3× size: 44 px, its ink from x 289.33 to 304 pt.
  static const icon = 44 / 3;
  static const iconGap = 28 / 3;

  /// The words and the icon together sit this far right of the screen's middle and [drop] under the gap's: so each
  /// glyph's ink centre and the icon's (296.38, 731.44) land within a pixel of the recording's.
  static const right = 0.5;
  static const drop = 1 / 3;
}

/// 推荐's big card: the official feed's `large_cover_v9`, full width and playing inline (122; KaiC's screenshot of it
/// playing, measured in px / 3).
abstract final class FeedBigCardTheme {
  /// The card spans both columns, inside the feed's side spacing.
  static const spacing = BiliMetrics.feedSpacing;
  static const radius = BiliMetrics.cardRadius;

  /// 6 to 434 pt wide, the video 240.75 pt tall (123, 126).
  static const videoAspect = 16 / 9;

  /// The title band: one line 40.33 pt, two 59.67 (123 and 126), so lines 19.33 apart with 21 above and below them;
  /// the first line's ink 15.33 under the video, a point lower than the strut's middle puts it, so [titleDrop] of the
  /// 21 is above. The ink starts 8.67 in (8 and the glyph's bearing); two-line titles wrap before x 351, 83 pt short of
  /// the card's right.
  static const titleText = BiliMetrics.cardTitleText;
  static const titleLine = 58 / 3;
  static const titlePad = 10.5;
  static const titleDrop = 1.0;
  static const titleInset = BiliMetrics.cardInset;
  static const titleTrailing = 83.0;
  static Color get title => BiliColors.text;

  /// 👍: the APK's `ic_list_inline_dislike` (its ink 52 of 114 px), its ink 16.72 pt square (x 366.43-383.15 in 123
  /// and 126), centred 59.21 pt from the card's right and 1.6 above the band's middle, #61666D; liked, the APK's
  /// `inline_click_to_like` Lottie in pink. The count hangs off its top right: 10 pt grey ("2.8万" 23.3 pt wide, as
  /// 123's), its ink from 3.25 pt left of the thumb's right edge and 3.83 above its top.
  static const likeInk = 16.72;
  static const likeAssetInk = 52 / 114;
  static const likeRight = 59.21;
  static const likeRise = 1.6;
  static Color get like => tone(0xFF61666D, 0xFF9A9EA5);
  static Color get liked => BiliColors.pink;
  static const countText = 10.0;
  static const countOverlap = 3.25;
  static const countTop = 5.43;
  static Color get count => BiliColors.secondaryText;

  /// The Lottie's thumb at rest is 103 px of its 228 px frame at 3×. Both pictures' ink centre sits 0.77 pt above
  /// their box's at this size.
  static const likeLottieInk = 103 / 228;
  static const likeInkRise = 0.77;

  /// The Lottie's 62 frames at 60 fps.
  static const likeMotion = Duration(milliseconds: 1033);

  /// ⋮ centred 12 pt from the card's right, 0.67 under the band's middle: the small card's glyph.
  static const moreRight = 12.0;
  static const moreDrop = 2 / 3;
  static const moreTarget = 32.0;
  static const likeTarget = 40.0;

  /// The counts over the video (12 pt, the small card's icons): 10.67 pt in, centred 16.5 pt above the video's bottom on
  /// the cover (122) and 15 while it plays (123); the duration 9 pt from the right, on the cover only.
  static const statText = 12.0;
  static const statLead = 32 / 3;
  static const statCentre = 16.5;
  static const statCentrePlaying = 15.0;
  static const statIconGap = BiliMetrics.cardStatIconGap;
  static const statGap = BiliMetrics.cardStatGap;
  static const durationTrail = 9.0;

  /// The cover's ▶: the APK's `bili_player_play` at 54.9 pt wide (its body 46.67 pt, 204 of 240 px), at 77% of its
  /// white, centred on the video (122).
  static const playWidth = 46.67 * 240 / 204;
  static const playOpacity = 0.77;

  /// 弹 and the speaker while it plays, centred 17 pt above the video's bottom and 69.9 and 22.8 pt from the card's
  /// right (123, 126). The speaker is the APK's `ic_volumn_inline_switch_off` / `_on` (72 px with its margins) drawn
  /// 22 pt square; 弹 the player's own glyph.
  static const buttonCentre = 17.0;
  static const danmakuRight = 69.9;
  static const speakerRight = 22.8;
  static const speakerSize = 22.0;
  static const buttonTarget = 40.0;

  /// From the second time round (125, 126): the counts are gone and the buttons at half their white, over 0.2 s.
  static const dimmed = 0.5;
  static const dim = Duration(milliseconds: 200);

  /// The played part along the video's bottom edge, 2 pt of pink (124), nothing under the rest.
  static const progress = 2.0;
  static Color get progressInk => BiliColors.pink;

  /// The card's video plays only while at least this much of its box is on screen once a scroll comes to rest (KaiC).
  static const visibleToPlay = 0.5;

  /// Paused this long off screen (or under another page), its player is let go; the card starts again where it was.
  static const releaseAfter = Duration(seconds: 30);

  /// A new card starts only this long after its list comes to rest, and only if it is still the one to play.
  static const startAfterRest = Duration(milliseconds: 300);
}

/// A 动态 card's sizes and colours (127, 128, 135-137, 139), measured in px / 3 from the card's top, which meets the
/// band above it.
abstract final class DynamicCardTheme {
  static Color get fill => BiliColors.card;
  static const gutter = 12.0;

  /// The 10 pt band under every card (127, 135, 139); a space's 动态 draws it in the lighter grey (136).
  static const band = 10.0;
  static Color get bandInk => BiliColors.pageGrey;
  static Color get spaceBandInk => BiliColors.softGrey;

  /// The face: 40 pt, 12 in and 12 down; its verification a 12 pt disc in a 2/3 pt white ring, flush with the face's
  /// lower right (127, 128). 动态's organisation blue is lighter than the video page's.
  static const face = 40.0;
  static const faceTop = 12.0;
  static const badge = 12.0;
  static const badgeRing = 2 / 3;
  static Color get badgePerson => tone(0xFFFFCC00, 0xFFFFCC00);
  static Color get badgeOrganisation => tone(0xFF40C5F1, 0xFF40C5F1);
  static const badgeBolt = Color(0xFFFFFFFF);

  /// The name (15 pt, pink for 大会员) and under it `pubTime · pubAction` (12 pt grey), 60 in, their Chinese ink
  /// centred 23.5 and 42.67 down. The dot is 2 pt, its ink 7 after the time's ink and 6.67 before the action's: 6.5
  /// and 6.17 from the text boxes.
  static const textLeft = 60.0;
  static const nameText = 15.0;
  static const nameWeight = FontWeight.w500;
  static const nameLine = 21.0;
  static const nameCentre = 23.5;
  static Color get nameInk => BiliColors.text;
  static Color get nameVipInk => BiliColors.pink;
  static const timeText = 12.0;
  static const timeLine = 17.0;
  static const timeCentre = 42.67;
  static Color get timeInk => BiliColors.secondaryText;
  static const timeDot = 2.0;
  static const timeDotBefore = 6.5;
  static const timeDotAfter = 6.17;

  /// The name and time stop this far before the fan card, or ⋮'s box when there is none.
  static const nameClearance = 4.0;

  /// With an avatar frame (136) the face is 26 pt about (40, 32), the frame 评论's 1.75 times it about the same middle;
  /// the name and time start at 75.33, the time 1.5 lower; ⋮ rises 5.5 and the fan card 7, and all under the row
  /// drops 6.5.
  static const pendantFace = 26.0;
  static const pendantScale = CommentRowTheme.pendantScale;
  static const pendantCentreX = 40.0;
  static const pendantCentreY = 32.0;
  static const pendantTextLeft = 226 / 3;
  static const pendantTimeDrop = 1.5;
  static const pendantMoreRise = 5.5;
  static const pendantDecorationRise = 7.0;
  static const pendantDrop = 6.5;

  /// The fan card (127, 139): the art fitted to 77.33 pt wide in a 35 tall box from 21 down, ending 42 from the card's
  /// right; its number in the block letters of 评论's fan card, 5.67 tall, 18.33 down, ending 43 from the box's right
  /// (355 on the phone) however many digits it has. A 1 is 4.33 from its stroke to the next digit's, other digits 6.
  static const decorationRight = 42.0;
  static const decorationTop = 21.0;
  static const decorationWidth = 232 / 3;
  static const decorationHeight = 35.0;
  static const decorationNumberRight = 43.0;
  static const decorationNumberTop = 55 / 3;
  static const decorationGlyphWidth = 14 / 3;
  static const decorationGlyphHeight = 17 / 3;
  static const decorationGlyphWeight = 1.15;
  static const decorationGlyphGap = 4 / 3;
  static const decorationOneAdvance = 13 / 3;
  static const decorationNumberInk = Color(0xFF83BF54);

  /// ⋮: the official icon font's `more-vertical-fill`, 3.33 × 16.67 pt, grey, centred 23.83 from the card's right and
  /// 38.17 down; its tap target 44 square.
  static const moreWidth = 10 / 3;
  static const moreHeight = 50 / 3;
  static const moreRight = 23.83;
  static const moreCentre = 38.17;
  static Color get moreInk => BiliColors.secondaryText;
  static const moreTarget = 44.0;

  /// The text: 17 pt, its lines 24 apart (128, 136); a 图文 post's in the 关注 feed 26.78 apart (127, 135), set a little
  /// lower under the face. Topics, links and @names in the link blue; at most four lines, then ... 全文 / 展开.
  static const text = 17.0;
  static const textLine = 24.0;
  static const opusTextLine = 80.33 / 3;
  static Color get textInk => tone(0xFF18191C, 0xFFD0D3D7);
  static Color get linkInk => BiliColors.link;
  static const maxLines = 4;

  /// Where the text's first line box starts, and the body with no text above it (139: the cover 60 down).
  static const textTop = 57.67;
  static const opusTextTop = 59.5;
  static const bodyTop = 60.0;

  /// From the text's last line box to the body under it: 128's cover starts 12.67 under the last line's ink, 127's
  /// pictures and 135's picture 15.5 under it.
  static const bodyGap = 9.33;
  static const opusBodyGap = 10.5;

  /// A post with nothing under its text: its footer this far under the last line box.
  static const footerGap = 6.0;

  /// Emotes in the text: 20 pt (136), a large one 28.
  static const emote = 20.0;
  static const emoteLarge = 28.0;

  /// In 图文's text on 关注 a line holding an emote grows (243: 29 pt under the line before, where the lines are 26.78;
  /// 136's plain pitch doesn't grow): the emote's whole height counts above the baseline, past PingFang's ascent, and
  /// the pitch scales that line as it scales PingFang's own; the emote is drawn up from PingFang's descent (243).
  static const pingFangAscent = 1.06;
  static const pingFangDescent = 0.34;
  static const pingFangLine = 1.4;

  /// The lottery's gift and a video link's ▶ circle, the icon font's, in the link blue (135, 131). The gift's are at
  /// [text]'s size and scale with the text it sits in (29: 14.67 × 15 in the 16 pt repost text).
  static const giftWidth = 47 / 3;
  static const giftHeight = 16.0;
  static const giftBefore = 3.0;
  static const giftAfter = 10 / 3;
  static const videoLinkSide = 49 / 3;
  static const videoLinkBefore = 5 / 3;
  static const videoLinkAfter = 4.0;

  /// The web answer runs @names into the words around them (恭喜@甲@乙等); 29 sets each one 2 pt after a word before
  /// it and a space before a word after it.
  static const mentionLead = 2.0;

  /// In a 图文 post's text on 关注 the space beside a topic is 3.33 pt wider (135 and 29: 28 and 24 px where one
  /// space gives 18 and 15; the post page, 131, and a video post, 128, keep the plain space).
  static const topicGap = 10 / 3;

  /// A repost's block on 关注 (29, 243) where a space's is 136's: the @name's line 9.67 down (its ink 40 px under the
  /// block's top, 56 on 136), the text 10.67 under that line or with none the body 9.33 (243), the text 16 pt at
  /// 图文's pitch for that size (a Han character 47.6 px on, lines 76 px apart; Flutter sets whole points, so 25).
  static const followRepostTop = 29 / 3;
  static const followRepostTextGap = 32 / 3;
  static const followRepostBodyGap = 28 / 3;
  static const followRepostText = 16.0;
  static const followRepostTextLine = 76 / 3;

  /// Its ... 全文 is drawn in Ga7's and Lb7's night values by day too (29); no dark reference shows it, and at night
  /// those are the text's and the link's own.
  static Color get followRepostEllipsisInk => tone(0xFFA2A7AE, 0xFFA2A7AE);
  static Color get followRepostMoreInk => tone(0xFF58B1D4, 0xFF58B1D4);

  /// The pictures: corners of 4 pt; two to four two a row and more three a row, in 119.17 pt cells 1.67 apart (127),
  /// square, or about 3:4 (158.33 tall) for pictures taller than square; one alone at its shape across the width
  /// (135), a tall one two cells wide and at most 3:4. The post page's grid (140) has square third-width cells 6 apart,
  /// two a row for two to four pictures and three a row for more.
  static const pictureRadius = 4.0;
  static const pictureCell = 238.33 / 2;
  static const pictureGap = 5 / 3;
  static const pictureTallest = 475 / 357.5;
  static const pictureWidest = 16 / 9;
  static const detailPictureGap = 6.0;
  static Color get pictureFill => BiliColors.pageGrey;

  /// A long picture: taller than this many times its width (PiliPlus's line; the official one isn't known). Alone, in
  /// a post or a repost, it fills the lone tall frame from its top (29: 240 wide from the gutter, 475:357.5).
  static const longPicture = 2.6;

  /// 长图 on a long picture's bottom right (29): 12 pt white on half black, 18 tall and 4 in at the sides, corners of
  /// 2; 2 from the frame's right. Its bottom is under the bar on 29: 5 is where it sits if the frame is the lone tall
  /// one.
  static const longLabelText = 12.0;
  static const longLabelHeight = 18.0;
  static const longLabelPadding = 4.0;
  static const longLabelRadius = 2.0;
  static const longLabelRight = 2.0;
  static const longLabelBottom = 5.0;
  static const longLabelInk = Color(0xFFFFFFFF);
  static const longLabelFill = Color(0x80000000);

  /// A repost's lone picture (29): its top 22.67 under the middle of the original's last line, where 136's row is 34.
  static const repostPictureTop = 68 / 3;

  /// The video box (128, 139): 16:9 from 12 to 13 short of the right (415 pt on the phone), corners of 4 pt. On its
  /// bottom left the duration in an 18 pt pill of half black 8 in and 6 up, then the plays and danmaku, 12 pt white
  /// centred on the pill; 动态视频 in a #FB7299 pill 8 from the top right; the APK's `ic_upper_tv_play` 42 pt wide,
  /// 11.83 from the right and 7.67 from the bottom.
  static const videoAspect = 16 / 9;
  static const videoTrail = 13.0;
  static const videoRadius = 4.0;
  static const statText = 12.0;
  static const statInk = BiliColors.onCover;
  static const durationLeft = 8.0;
  static const durationBottom = 6.0;
  static const durationHeight = 18.0;
  static const durationPad = 4.5;
  static const durationRadius = 2.0;
  static const durationFill = Color(0x80000000);
  static const statFirstGap = 26 / 3;
  static const statGap = 34 / 3;

  /// PingFang sets digits apart from the Chinese they meet ("37.1 万播放"); Flutter's layout sets them touching.
  static const statHanGap = 2.0;
  static const shadeHeight = 36.0;
  static const shade = Color(0x4D000000);
  static const badgeInset = 8.0;
  static const badgeHeight = 16.0;
  static const badgeText = 10.0;
  static const badgePad = 4.0;
  static const badgeRadius = 8 / 3;
  static const badgeFill = BiliColors.verticalPink;
  static const badgeInk = BiliColors.onPink;
  static const tvWidth = 42.0;
  static const tvRight = 11.83;
  static const tvBottom = 7.67;

  /// The TV's white is about 80% opaque on 128; the APK's art is 70%.
  static const tvAlpha = 0.8;
  static const tvArtAlpha = 0.7;

  /// Playing inline (139): the speaker, the 推荐 card's 24 pt art, 7.33 from the right and 8.67 from the bottom; the
  /// played part a 2 pt pink line along the cover's bottom.
  static const speaker = 24.0;
  static const speakerRight = 22 / 3;
  static const speakerBottom = 26 / 3;
  static const speakerTarget = 44.0;
  static const progress = 2.0;
  static Color get progressInk => BiliColors.pink;

  /// The title under a 投稿视频's box (139): 15 pt, one line, its ink 8 under the cover and the footer 4 under it.
  static const titleText = 15.0;
  static const titleWeight = FontWeight.w500;
  static const titleLine = 21.0;
  static const titleTop = 13 / 3;
  static const titleBottom = 1 / 3;
  static Color get titleInk => BiliColors.text;

  /// A repost's original (136): a grey block across the card, its @name 15 pt link blue on a line from 14 down, + 关注
  /// 13 pt pink 12 from the right; the original's text 17 pt #61666D, its body under it, 10 under the block's bottom.
  static Color get repostFill => BiliColors.pageGrey;
  static const repostTop = 14.0;
  static const repostNameText = 15.0;
  static const repostNameLine = 21.0;
  static const repostTextGap = 7.0;
  static Color get repostTextInk => tone(0xFF61666D, 0xFFA2A7AE);
  static const repostBottom = 10.0;
  static const repostFollowText = 13.0;
  static Color get repostFollowInk => BiliColors.pink;

  /// + 关注's cross 7 pt square, its strokes 1 pt, 4.5 before 关注; the label sits 0.83 under the name's middle.
  static const repostPlus = 7.0;
  static const repostPlusStroke = 1.0;
  static const repostPlusGap = 4.5;
  static const repostFollowDrop = 5 / 6;
  static const repostFollowPad = 8.0;

  /// The block's top, under the repost's own text (136: 14 under its ink).
  static const repostGap = 10.0;

  /// The original's pictures (136): one row 202 pt tall scrolling sideways, each picture at its own shape with corners
  /// of 6, 6 apart, from the block's inset and off its right edge, 22 under the text's last line box.
  static const repostStrip = 202.0;
  static const repostStripGap = 6.0;
  static const repostStripRadius = 6.0;
  static const repostStripTop = 22.0;

  /// On the post page (132) the block's text and body sit 20 in and its @name 24, so the video box is 400 × 225; the
  /// @name's line 1.33 higher than on the list, the box 44 under the block's top, its title's ink 9.33 under the box
  /// and 15.33 over the block's end.
  static const repostDetailInset = 20.0;
  static const repostDetailNameInset = 24.0;
  static const repostDetailTop = 38 / 3;
  static const repostDetailBodyGap = 31 / 3;
  static const repostDetailTitleTop = 6.0;
  static const repostDetailBottom = 35 / 3;

  /// UP主的推荐 (127, 135): the icon font's lock and the 12 pt grey head centred 18.83 under the pictures; 8.33 under
  /// the head's ink the 80 pt #F6F7F8 box, corners of 5 pt: a 64 pt cover 8 in, the name 14 pt and the brief 12 pt
  /// grey 8 after it, the 56 × 24 pink 去看看 (13 pt white) 8 from the right.
  static const goodsHeadLine = 17.0;
  static const goodsHeadText = 12.0;
  static Color get goodsHeadInk => BiliColors.secondaryText;
  static const goodsHeadTop = 11.0;
  static const goodsLockLead = 1.0;
  static const goodsLockWidth = 10.0;
  static const goodsLockGap = 16 / 3;
  static const goodsBoxGap = 14 / 3;
  static const goodsBox = 80.0;
  static Color get goodsFill => BiliColors.softGrey;
  static const goodsRadius = 5.0;
  static const goodsCover = 64.0;
  static const goodsCoverRadius = 2.0;
  static const goodsInset = 8.0;
  static const goodsNameText = 14.0;
  static Color get goodsNameInk => BiliColors.text;
  static const goodsNameCentre = 30.33;
  static const goodsNameLine = 20.0;
  static const goodsBriefText = 12.0;
  static const goodsBriefLine = 17.0;
  static Color get goodsBriefInk => BiliColors.secondaryText;
  static const goodsBriefCentre = 53.33;
  static const goodsButtonWidth = 56.0;
  static const goodsButtonHeight = 24.0;
  static const goodsButtonRadius = 5.0;
  static const goodsButtonText = 13.0;
  static Color get goodsButtonFill => BiliColors.pink;
  static const goodsButtonInk = BiliColors.onPink;

  /// The footer: 48 tall, three equal columns between the gutters, each its icon and count centred 0.67 pt right of
  /// the column's middle; the APK's icons drawn 16.67, 17.33 and 18 pt wide (135), #61666D, centred 23, 24 and 23
  /// down; the count or word 13 pt, its ink 6 to 6.33 after the icon's (135, 136, 139), centred 24 down. Liked, the
  /// filled thumb and its count pink.
  static const footer = 48.0;
  static const footerText = 13.0;
  static Color get footerInk => tone(0xFF61666D, 0xFFA2A7AE);
  static Color get footerLiked => BiliColors.pink;
  static const footerGapToCount = 17 / 3;
  static const footerShift = 2 / 3;
  static const footerCentre = 24.0;
  static const forwardWidth = 50 / 3;
  static const commentWidth = 52 / 3;
  static const likeWidth = 18.0;
  static const forwardCentre = 23.0;
  static const commentCentre = 24.0;
  static const likeCentre = 23.0;

  /// ⋮'s sheet (137): over the page dimmed by half, #F6F7F8 with square corners; rows 50 tall, a hairline (1/3 pt
  /// #E3E5E7) from 20 in under each but the last; the icon font's icons in pink centred about 31 in, the words 14 pt
  /// from 58; a 5 pt #F1F2F3 gap, then 取消 (15 pt) in its own 50 tall row over the home indicator's inset.
  static const sheetDim = Color(0x80000000);
  static Color get sheetFill => tone(0xFFF6F7F8, 0xFF1E2022);
  static const sheetRow = 50.0;
  static const sheetHairline = 1 / 3;
  static const sheetHairlineLeft = 20.0;
  static Color get sheetHairlineInk => BiliColors.divider;
  /// Night: 246 draws them #C64A76, a shade under the palette's pink.
  static Color get sheetIconInk => tone(0xFFFF6699, 0xFFC64A76);
  static const sheetText = 14.0;
  static const sheetTextLeft = 58.0;
  static Color get sheetInk => BiliColors.text;
  static const sheetGap = 5.0;
  static Color get sheetGapFill => BiliColors.pageGrey;
  static const sheetCancelText = 15.0;

  /// Centred in their rows, the labels' ink sits this much higher on 159.
  static const sheetLabelLift = 4 / 3;
  static const sheetCancelLift = 1.0;
  static Color get sheetCancelInk => tone(0xFF484C53, 0xFFB9BDC2);
  static const sheetIn = Duration(milliseconds: 250);
  static const sheetOut = Duration(milliseconds: 200);

  /// The icons' ink widths and centres: 分享 55 px, 取消关注 52, 举报 56; centred 30.67, 32.17 and 30.83 in, and 1 above,
  /// 0.33 below and 0.67 above the row's middle.
  static const sheetShareWidth = 55 / 3;
  static const sheetUnfollowWidth = 52 / 3;
  static const sheetReportWidth = 56 / 3;
  static const sheetShareCentre = 30.67;
  static const sheetUnfollowCentre = 32.17;
  static const sheetReportCentre = 30.83;
  static const sheetShareRise = 1.0;
  static const sheetUnfollowRise = -1 / 3;
  static const sheetReportRise = 2 / 3;

  /// A video post's two rows over 分享 (263): 稍后再看 (`arrow_play_next_line`, 60 px) centred 31.67 in on the row's
  /// middle, 前往关闭自动播放 (`autoplay_off_line`, 59 px) 31.5 in and 0.33 below it.
  static const sheetWatchLaterWidth = 60 / 3;
  static const sheetAutoplayWidth = 59 / 3;
  static const sheetWatchLaterCentre = 31.67;
  static const sheetAutoplayCentre = 31.5;
  static const sheetWatchLaterRise = 0.0;
  static const sheetAutoplayRise = -1 / 3;
}

/// The 关注 tab: header, 全部 / 视频, 最常访问, 我的追番 · 追剧 and the face sheet (127, 128, 139), measured in px / 3.
abstract final class DynamicFeedTheme {
  /// The header ends 88 pt down on the 62 pt status bar: its 44 pt row lies 18 pt up into the status bar, as the
  /// official app lays it under a 44 pt one. 关注 is centred on the row (17 pt, ink 15.33 tall); the APK's `dy_ic_write`
  /// (its ink 18.67 pt square) centred 22.17 pt in from the right. Over a 装扮 both take its colour, the pen at 88% (127
  /// draws it #1F1F1E where the title is #000); without one (no screenshot) a white bar.
  static const barRow = 44.0;
  static const barRise = 18.0;
  static Color get bar => BiliColors.card;
  static const titleText = 17.0;
  static const titleWeight = FontWeight.w500;
  static Color get titleInk => BiliColors.text;
  static const write = 56 / 3;
  static const writeCentreRight = 22.17;
  static const writeOpacity = 0.88;
  static const writeTarget = 44.0;

  /// The pen without a 装扮; dark (243) draws it grey, not in the title's white.
  static Color get writeInk =>
      BiliTheme.dark ? const Color(0xFF9A9EA5) : titleInk.withValues(alpha: writeOpacity);

  /// The white top under the header, 186 pt to the first grey band. 全部 / 视频: two #F6F7F8 halves 26 pt tall, 8 pt
  /// under the header, 12 pt in and 8 apart, 4 pt corners; the chosen one's word pink.
  static const top = 186.0;
  static const switchTop = 8.0;
  static const switchHeight = 26.0;
  static const switchGap = 8.0;
  static Color get switchFill => tone(0xFFF6F7F8, 0xFF1E2022);
  static const switchRadius = 4.0;
  static const switchText = 12.0;
  static Color get switchOn => BiliColors.pink;
  static const switchOnWeight = FontWeight.w500;
  static Color get switchOff => tone(0xFF61666D, 0xFFA2A7AE);

  /// Both sections' titles (最常访问, 我的追番 · 追剧): 14 pt semibold on 20 pt lines, 12 pt in. 最常访问 centred 60.17 pt
  /// under the white top's start (148.17 on 127), 我的追番 · 追剧 22.5 under its section's.
  static const gutter = 12.0;
  static const sectionText = 14.0;
  static const sectionLine = 20.0;
  static const sectionWeight = FontWeight.w600;
  static Color get sectionInk => BiliColors.text;
  static const facesTitleCentre = 60.17;
  static const bangumiTitleCentre = 22.5;

  /// 更多 › after 最常访问 (only on 全部: 128 has none), 全部 › after 我的追番 · 追剧: the › 4.67 × 9.33 pt with its right
  /// edge 17.67 pt in; 更多's ink ends 7 pt before it, 全部's 9.67.
  static const moreText = 12.0;
  static Color get moreInk => BiliColors.secondaryText;
  static const allText = 13.0;
  static Color get allInk => tone(0xFF61666D, 0xFFA2A7AE);
  static const chevronWidth = 14 / 3;
  static const chevronHeight = 28 / 3;
  static const chevronStroke = 1.1;
  static Color get chevronInk => BiliColors.secondaryText;
  static const chevronRight = 17.67;
  static const moreGap = 35 / 6;
  static const allGap = 53 / 6;
  static const moreTarget = 44.0;

  /// The faces: 52 pt circles in a 1 px #F1F2F3 ring, 74 pt apart from a centre 45 pt in, their tops 82 pt under the
  /// white top's start; names 11 pt #484C53 on 14 pt lines, centred under each and wrapping at 60 pt (a six-character
  /// Chinese name breaks after its fifth), the first line's centre 13.17 pt under the face. The pink dot (8 pt in an 11.67 pt white ring) 18 pt right and
  /// down of the face's centre.
  static const facesTop = 82.0;
  static const face = 52.0;
  static const faceRing = 1 / 3;
  static Color get faceRingInk => BiliColors.pageGrey;
  static const facePitch = 74.0;
  static const facesInset = 8.0;
  static const nameWidth = 60.0;
  static const nameText = 11.0;
  static const nameLine = 14.0;
  static Color get nameInk => tone(0xFF484C53, 0xFFB9BDC2);
  static const nameCentre = 79 / 6;
  static const dot = 8.0;
  static const dotRing = 35 / 3;
  static Color get dotInk => BiliColors.pink;
  static const dotOffset = 18.0;

  /// The followed who are live lead the faces (263), in the same 74 pt slots: the face in a 56 pt pink ring (1 pt,
  /// 1 pt clear of it), no dot; a 52 × 16 pink stadium in a 1 pt white rim, centred 21 pt under the face's centre,
  /// holds the APK's `ic_live_comm_live_ing` bars drawn 16 pt square 2 pt in and 1 pt down, then 直播中 10 pt white
  /// straight after them. A 1 × 24 pt line centred on the faces sits 7 pt past the last live slot, 8 before the next.
  static const liveRing = 56.0;
  static const liveRingStroke = 1.0;
  static Color get liveRingInk => BiliColors.pink;
  static const livePillWidth = 52.0;
  static const livePillHeight = 16.0;
  static const livePillRim = 1.0;
  static Color get livePillRimInk => BiliColors.card;
  static Color get livePillFill => BiliColors.pink;
  static const livePillDrop = 21.0;
  static const liveBars = 16.0;
  static const liveBarsLeft = 2.0;
  static const liveBarsDrop = 1.0;
  static const liveText = 10.0;
  static const liveInk = BiliColors.onPink;
  static const liveRuleBefore = 7.0;
  static const liveRuleAfter = 8.0;
  static const liveRuleWidth = 1.0;
  static const liveRuleHeight = 24.0;
  static Color get liveRuleInk => BiliColors.divider;

  /// `N人直播中 · ` before 更多 in the title's grey, 14 pt from 中 to 更 with a 5/3 pt dot centred between them.
  static const liveLeadGap = 14.0;
  static const liveLeadDot = 5 / 3;

  /// The row asks Bilibili for more faces once scrolled within this of its end.
  static const facesAhead = 148.0;

  /// The grey between the top's sections and above the first post; each card draws its own under itself.
  static const band = 10.0;
  static Color get bandFill => BiliColors.pageGrey;

  /// 我的追番 · 追剧 (128): 152 pt from band to band; posters 113 × 70 pt, 6 apart, 4 pt corners, their tops 43 pt under
  /// the section's start; 全N话 10 pt white, 6 pt in, its ink 7.33 pt over the poster's bottom on a shade; the title one
  /// 20 pt line of 14 pt #18191C centred 14.5 pt under the poster.
  static const bangumi = 152.0;
  static const posterTop = 43.0;
  static const posterWidth = 113.0;
  static const posterHeight = 70.0;
  static const posterGap = 6.0;
  static const posterRadius = 4.0;
  static const posterShadeTop = Color(0x00000000);
  static const posterShade = Color(0x66000000);
  static const posterShadeHeight = 28.0;
  static const progressText = 10.0;
  static const progressInk = BiliColors.onCover;
  static const progressLeft = 6.0;
  static const progressBottom = 5.0;
  static const posterTitleText = 14.0;
  static const posterTitleLine = 20.0;
  static Color get posterTitleInk => BiliColors.text;
  static const posterTitleCentre = 14.5;

  /// The page's own states (no screenshot): logged out, empty, failed, and the footer under the posts.
  static const stateText = 15.0;
  static Color get stateInk => BiliColors.secondaryText;
  static const stateGap = 16.0;
  static const stateTop = 96.0;
  static const loginText = 15.0;
  static const loginHeight = 36.0;
  static const loginPadX = 36.0;
  static const retryText = 14.0;
  static const retryHeight = 30.0;
  static const retryPadX = 20.0;
  static const buttonWeight = FontWeight.w500;
  static const footerText = 12.0;
  static Color get footerInk => tone(0xFFC9CCD0, 0xFF46494D);
  static const footerPad = 16.0;
  static const spinnerRadius = 10.0;

  /// 关注 tapped while shown: the list back to the top, then the refresh's TV held open there (首页's own pace).
  static const reloadScroll = Duration(milliseconds: 300);
  static const reloadHeader = Duration(milliseconds: 200);
  static const reloadCollapse = Duration(milliseconds: 100);

  /// An unfollowed account's post leaving (263 at 30 fps): it fades where it lies, over the posts under it as they rise
  /// into its place, both on one curve; 90% done by 190 ms, settled by 380. `linearToEaseOut` over 380 ms follows the
  /// clip's frames within 1.1 pt.
  static const leave = Duration(milliseconds: 380);
  static const leaveCurve = Curves.linearToEaseOut;

  /// The face sheet (139): the page behind frosted to #F2F2F2, the faces row moved up to 16.33 pt under the status bar,
  /// the sheet from 127 pt under it with 8 pt corners, the APK's `dy_ic_indicator_triangle` drawn 15.67 × 8 pt with
  /// its tip under the chosen face; the sheet's head 44 pt with `<name>的动态` 14 pt medium 12 pt in, a 13.33 pt ✕ in
  /// #626262 centred 23 pt in from the right, and a 1 px #E3E5E7 rule.
  static Color get sheetFrost => tone(0xF2F2F2F2, 0xF20A0B0C);
  static const sheetBlur = 20.0;
  static const sheetFacesTop = 16.33;
  static const sheetTop = 127.0;
  static const sheetRadius = 8.0;
  static Color get sheetFill => BiliColors.card;
  static const pointerWidth = 47 / 3;
  static const pointerHeight = 8.0;
  static const sheetHead = 44.0;
  static const sheetTitleText = 14.0;
  static const sheetTitleWeight = FontWeight.w500;
  static Color get sheetTitleInk => BiliColors.text;
  static const closeSize = 40 / 3;
  static const closeStroke = 1.4;
  static Color get closeInk => tone(0xFF626262, 0xFFA2A7AE);
  static const closeCentreRight = 23.0;
  static const closeTarget = 44.0;
  static const sheetRule = 1 / 3;
  static Color get sheetRuleInk => BiliColors.divider;
  static const sheetIn = Duration(milliseconds: 300);
  static const sheetOut = Duration(milliseconds: 220);
  static const sheetCurve = Curves.easeOutCubic;
  static const pointerSlide = Duration(milliseconds: 200);
}

/// A post on its own page (131-134, 140), measured in px / 3 from the status bar's 62 pt down.
abstract final class DynamicPostTheme {
  static Color get page => BiliColors.card;

  /// The bar: 48 under the status bar; ‹, ↗ and ⋮ in #61666D centred 24 down. Once the author block is under it, the
  /// poster's 25 pt face and 13 pt name (in the text's black, never pink) come in with a 2/3 pt hairline just below the
  /// bar's 48, over the tabs pinned there (134: 110-110.67).
  static const barRow = 48.0;
  static Color get barInk => tone(0xFF61666D, 0xFFA2A7AE);
  static const barTarget = 44.0;
  static const barFade = Duration(milliseconds: 150);
  static Color get barRule => BiliColors.divider;
  static const barHairline = 2 / 3;

  /// ‹: its ink 19.33-28.67 × 18 pt with 1.5 pt round strokes.
  static const backTipX = 20.08;
  static const backWidth = 7.83;
  static const backHalfHeight = 8.25;
  static const backStroke = 1.5;

  /// ↗ is the APK's 转发 arrow drawn 20 wide, centred 68 from the right edge and 1 pt above the row's middle.
  static const shareWidth = 20.0;
  static const shareCentreRight = 68.0;
  static const shareRise = 1.0;

  /// ⋮: 10/3 pt dots 20/3 apart, centred 24 from the right edge.
  static const moreCentreRight = 24.0;
  static const moreDot = 10 / 3;
  static const morePitch = 20 / 3;

  static const titleFace = 25.0;
  static const titleFaceLeft = 43.0;
  static const titleGap = 35 / 6;
  static const titleText = 13.0;
  static Color get titleInk => BiliColors.text;
  static const titleRight = 96.0;

  /// The author block, 11.67 under the bar: the 36 pt face 20 in, its verify badge's disc (10.67 across in a 1 pt white
  /// ring) flush with the face's bottom right; the name 15 pt semibold 10 after it, pink for 大会员 (#FB7299, as
  /// comments'), then the time and, for the posts that keep it there (132), IP属地 in 12 pt grey, 17.17 and 15.33
  /// apart. The face centres on the lines beside it, or they on the face when they are shorter. Every height is in
  /// whole pixels, so the hairlines below stay sharp.
  static const gutter = 20.0;
  static const authorTop = 35 / 3;
  static const face = 36.0;
  static const faceGap = 10.0;
  static const badge = 38 / 3;
  static const badgeRing = 1.0;
  static Color get badgeOrganisation => tone(0xFF40C5F1, 0xFF40C5F1);
  static Color get badgePersonal => tone(0xFFFFCC00, 0xFFFFCC00);
  static const badgeBolt = Color(0xFFFFFFFF);
  static const nameText = 15.0;
  static const nameWeight = FontWeight.w600;
  static const nameLine = 20.0;
  static Color get name => BiliColors.text;
  static Color get vipName => CommentRowTheme.vipName;
  static const metaText = 12.0;
  static const metaLine = 43 / 3;
  static const metaGap = 1.0;
  static Color get meta => BiliColors.secondaryText;

  /// The text, 12 under the author block, 17 pt in #2F3238 (a shade lighter than the comments' black) on 29.33 pt lines
  /// (131, 132, 140); the body (pictures, a video, a repost's grey block) 12 under it, and IP属地 12 under that for a
  /// picture or text post (140). 12 more before the tabs.
  static const textGap = 12.0;
  static const text = 17.0;
  static const textLine = 88 / 3;
  static Color get textInk => tone(0xFF2F3238, 0xFFD0D3D7);
  static const bodyGap = 12.0;
  static const endGap = 12.0;

  /// 评论 N / 赞和转发 N: 14 pt in a 40 pt row (its last 2/3 pt the hairline), the first 12 in, 20 between them; the
  /// chosen one pink over a 4/3 pt pink line as wide as its words, standing on the hairline.
  static const tabsHeight = 40.0;
  static const tabText = 14.0;
  static const tabFirst = 12.0;
  static const tabSpacing = 20.0;
  static Color get tabChosen => BiliColors.pink;
  static Color get tabInk => BiliColors.secondaryText;
  static const tabUnderline = 4 / 3;
  static const tabHairline = 2 / 3;
  static Color get tabRule => BiliColors.divider;

  /// The bar at the bottom (131, 132, 140): two 1/3 pt rules (#E3E5E7 over #F1F2F3), then a 44 pt row over the home
  /// indicator. 点我发评论 in a 32 pt grey pill 12 in, ending 37 short of the first count's centre; the counts' centres
  /// 54 apart, the last 37 from the right edge, each icon's ink centred 15.5 down (as 131's lands: 💬 a third of a
  /// point lower, ⭐ a third higher, 👍 0.83 higher) and its 11.5 pt count 33.2 down.
  static Color get bottomRule => BiliColors.divider;
  static Color get bottomRuleSoft => BiliColors.pageGrey;
  static const bottomRuleEach = 1 / 3;
  static const bottomRow = 44.0;
  static const pillHeight = 32.0;
  static const pillLeft = 12.0;
  static const pillPadding = 11.0;
  static const pillToAction = 37.0;
  static Color get pillFill => BiliColors.pageGrey;
  static const pillText = 13.0;
  static Color get pillInk => BiliColors.secondaryText;
  static const actionPitch = 54.0;
  static const lastActionRight = 37.0;
  static const commentIconCentre = 15.83;
  static const starIconCentre = 15.17;
  static const likeIconCentre = 14.67;
  static const actionCountCentre = 33.2;
  static const actionCountText = 11.5;
  static const actionCountLine = 14.0;
  static Color get actionInk => tone(0xFF61666D, 0xFFA2A7AE);
  static Color get actionCountInk => BiliColors.secondaryText;
  static Color get actionLiked => BiliColors.pink;

  /// The APK's 评论, ⭐ and 赞 drawn as wide as 131's ink.
  static const commentIcon = 56 / 3;
  static const starIcon = 18.0;
  static const likeIcon = 58 / 3;

  /// How long 💬's scroll to 评论 takes, and the first load's failure: why, then 重试 as 搜索's.
  static const toComments = Duration(milliseconds: 300);
  static const stateText = SearchResultTheme.stateText;
  static Color get stateInk => SearchResultTheme.stateInk;
  static const stateGap = SearchResultTheme.stateGap;
  static const retryHeight = SearchResultTheme.retryHeight;
  static const retryPadX = SearchResultTheme.retryPadX;
  static const retryRim = SearchResultTheme.retryRim;
  static const retryText = SearchResultTheme.retryText;
  static Color get retryInk => BiliColors.pink;
  static const retryPressedScale = SearchResultTheme.followPressedScale;
  static const retryPressMotion = SearchResultTheme.followPressMotion;
}

/// 我的好友 (163-168). Measured in px / 3; the shots' colours are Display P3, so the pink reads #EA7A99 there. The bar is
/// 我的关注's ([FollowingListTheme]: the skin's second-page colour and the round ‹).
abstract final class FriendsTheme {
  static Color get page => BiliColors.card;

  /// 我的好友: 16 pt regular, its ink centred on the screen and on the bar's row.
  static const titleText = 16.0;
  static const titleLine = 22.0;

  /// 关注 and 粉丝: 14 pt, centred 78 either side of the screen's middle and 22.17 under the bar, in a 39.33 row closed
  /// by a 1/3 #E7E7E7 rule; the chosen pink over a 28 × 2 pink bar whose bottom is 1/3 under the rule's, the other
  /// #505050.
  static const tabRow = 118 / 3;
  static const tabRule = 1 / 3;
  static Color get tabRuleInk => tone(0xFFE7E7E7, 0xFF2F3134);
  static const tabWidth = 156.0;
  static const tabText = 14.0;
  static const tabLine = 20.0;
  static const tabLabelCentre = 133 / 6;
  static Color get tabInk => tone(0xFF505050, 0xFFB9BDC2);
  static Color get tabChosen => BiliColors.pink;
  static const underlineWidth = 28.0;
  static const underlineHeight = 2.0;
  static const underlineBottom = 40.0;
  static const tabMotion = Duration(milliseconds: 300);

  /// 搜索我的关注 (163, 168): 7.33 under the rule, a 30 tall #F4F4F4 stadium 12 in from each side, or ending 64.33 from
  /// the right while 取消 (16 pt pink, centred in that space) shows. The magnifier's ink 12.67 across, centred 15 into
  /// the field, #999999; the words 13 pt from 30 in, the placeholder #C0C0C0; the ⓧ 12.33 across, centred 14.17 from the
  /// field's end.
  static const fieldTop = 22 / 3;
  static const fieldHeight = 30.0;
  static const fieldInset = 12.0;
  static Color get field => tone(0xFFF4F4F4, 0xFF1E2022);
  static const fieldEndSearching = 193 / 3;
  static const magnifier = 38 / 3;
  static const magnifierCentre = 15.0;
  static Color get magnifierInk => tone(0xFF999999, 0xFF757A81);
  static const fieldTextLeft = 30.0;
  static const fieldText = 13.0;
  static const fieldLine = 18.0;
  static Color get fieldInk => BiliColors.text;
  static Color get placeholder => tone(0xFFC0C0C0, 0xFF5E6267);
  static Color get caret => BiliColors.pink;
  static const clear = 37 / 3;
  static const clearCentre = 85 / 6;
  static Color get clearInk => tone(0xFF999999, 0xFF757A81);
  static const cancelText = 16.0;
  static const cancelLine = 22.0;
  static Color get cancelInk => BiliColors.pink;

  /// 我的关注 14人 and the order (163, 164): a 39 tall row under the field. 我的关注 14 pt 12 in, its ink centred 26.17
  /// down, then 14人 13 pt grey on its baseline; at the right 最近关注 or 最近访问 14 pt #61666D ending 12 in, centred
  /// 25 down, after the APK's sort glyph (12.67 × 9.33) 6 before it.
  static const countRow = 39.0;
  static const countCentre = 157 / 6;
  static const countText = 14.0;
  static const countLine = 20.0;
  static Color get countInk => BiliColors.text;
  static const countNumberText = 13.0;
  static Color get countNumberInk => BiliColors.secondaryText;
  static const countGap = 4.0;
  static const sortCentre = 25.0;
  static const sortText = 14.0;
  static const sortLine = 20.0;
  static Color get sortInk => tone(0xFF61666D, 0xFFA2A7AE);
  static const sortGlyphWidth = 38 / 3;
  static const sortGlyphHeight = 28 / 3;
  static const sortGap = 6.0;
  static const sortTarget = 120.0;

  /// A search's rows start 7 under the field (168).
  static const resultsTop = 7.0;

  /// A row (163): 78 tall. The face 48 at 12 in on the row's middle, its bolt a 14 disc ringed 1.5 in white, flush
  /// with the face's right and bottom. The name 14 pt from 72, its ink centred 29.67 down, pink for a 大会员; the sign
  /// 12 pt grey centred 49.67 down; both stop 16 short of the pill (163's ellipses end by 334.67). The pill 72 × 24,
  /// 12 from the right and 21.67 down: #E7E7E7, ≡ (10.67 × 9.33 of ink, 10 in) and 13 pt #999999 words from 25.67
  /// in. A 1/3 divider from 72 to the right edge, 1/3 above the row's bottom.
  static const row = 78.0;
  static const face = 48.0;
  static const faceInset = 12.0;
  static const badge = 14.0;
  static const badgeRing = 1.5;
  static Color get badgePerson => FollowingListTheme.badgePerson;
  static Color get badgeOrganisation => FollowingListTheme.badgeOrganisation;

  /// A 数字藏品 face (163's 哔哩哔哩数字周边, 装扮小姐姐): the APK's `ic_tag_nft` drawn as the bolt's disc and ring,
  /// level with it and centred 16 left of it (37 from the screen's left; 163 measures 36.83), the bolt's ring over its edge.
  static const collectibleRight = 16.0;
  static const textLeft = 72.0;
  static const nameText = 14.0;
  static const nameLine = 20.0;
  static const nameCentre = 89 / 3;
  static Color get name => BiliColors.text;
  static Color get vipName => BiliColors.pink;
  static const signText = 12.0;
  static const signLine = 17.0;
  static const signCentre = 149 / 3;
  static Color get sign => BiliColors.secondaryText;
  static const textGap = 16.0;
  static const pillWidth = 72.0;
  static const pillHeight = 24.0;
  static const pillRight = 12.0;
  static const pillTop = 65 / 3;
  static Color get pillFill => tone(0xFFE7E7E7, 0xFF2F3134);
  static Color get pillInk => tone(0xFF999999, 0xFF757A81);
  static const pillText = 13.0;
  static const pillLine = 18.0;
  static const pillGlyphLeft = 10.0;
  static const pillGlyphWidth = 32 / 3;
  static const pillGlyphHeight = 28 / 3;
  static const pillGlyphStroke = 1.0;
  static const pillTextLeft = 77 / 3;

  /// 关注 again after 取消关注, and 回关 for a fan not followed back: no screenshot, so the same pill pink with white
  /// words.
  static Color get pillActionFill => BiliColors.pink;
  static const pillActionInk = BiliColors.onPink;
  static const rowRule = 1 / 3;
  static Color get rowRuleInk => BiliColors.divider;

  /// An empty list (165): the APK's `ic_page_status_empty` at its own 3× size, 140 square, its top 130.33 under the tab
  /// rule, then 这里还什么都没有呢～ 16 pt grey centred 28.17 under it.
  static const emptyTop = 391 / 3;
  static const emptyPicture = 140.0;
  static const emptyText = 16.0;
  static const emptyLine = 22.0;
  static const emptyTextCentre = 169 / 6;
  static Color get emptyInk => BiliColors.secondaryText;

  /// The sheets dim everything under the bar by 30% (166, 167: white reads 178); the bar stays as it is.
  static const sheetDim = Color(0x4D000000);
  static const sheetIn = Duration(milliseconds: 280);
  static const sheetOut = Duration(milliseconds: 220);
  static Color get sheetFill => tone(0xFFFFFFFF, 0xFF1E2022);

  /// 已关注's sheet (166): a 1/3 #EBEDF0 top, then 设置分组 and 取消关注 49.67 tall with the same rule between, their
  /// pink glyphs centred 21 in (drawn: the APK's differ) and the words 14 pt #323233 from 40, both 26.5 down; an 8
  /// #F8F8F8 gap, the rule, and 取消 16 pt centred in the last 49.33 at the screen's bottom.
  static const actionRow = 149 / 3;
  static const actionCentre = 26.5;
  static const actionRule = 1 / 3;
  static Color get actionRuleInk => tone(0xFFEBEDF0, 0xFF2F3134);
  static const actionGlyphCentre = 21.0;
  static const actionTextLeft = 40.0;
  static const actionText = 14.0;
  static const actionLine = 20.0;
  static Color get actionInk => tone(0xFF323233, 0xFFE7E9EB);
  static Color get actionGlyphInk => BiliColors.pink;
  static const actionGlyphStroke = 0.9;
  static const groupGlyphWidth = 18.0;
  static const groupGlyphHeight = 49 / 3;
  static const unfollowGlyphWidth = 20.0;
  static const unfollowGlyphHeight = 19.0;
  static const actionGap = 8.0;
  static Color get actionGapFill => tone(0xFFF8F8F8, 0xFF0A0B0C);
  static const cancelRow = 148 / 3;
  static const cancelRowText = 16.0;
  static const cancelRowLine = 22.0;

  /// 设置分组 (167): 347 tall at the screen's bottom. Its head centred 33 down: the APK's `ic_attention_group` (its ink
  /// 18.67 wide, so the 66 px file is drawn 20.53 square), centred 22 in and 31.67 down; 设置分组 15 pt #212121 from 38;
  /// ＋新建分组 13 pt #999999 ending 12 in, its ＋ 11.33 across, 2.67 before the words. Each 分组 a 52 tall row from 53:
  /// the name 14 pt #212121 12 in centred 15.67 down, its tip 10 pt #999999 centred 37 down, and a 22 circle ringed
  /// #E7E7E7, 12 from the right on the row's middle (ticked: no screenshot, filled pink with a white ✓). 保存至默认分组
  /// (保存 once any is ticked) 12 pt pink, centred 35.33 above the screen's bottom.
  static const groupSheet = 347.0;
  static const groupHeadCentre = 33.0;
  static const groupIcon = 20.53;
  static const groupIconCentreX = 22.0;
  static const groupIconCentreY = 95 / 3;
  static const groupTitleLeft = 38.0;
  static const groupTitleText = 15.0;
  static const groupTitleLine = 21.0;
  static Color get groupInk => tone(0xFF212121, 0xFFE7E9EB);
  static const newGroupText = 13.0;
  static const newGroupLine = 18.0;
  static Color get newGroupInk => tone(0xFF999999, 0xFF757A81);
  static const plus = 34 / 3;
  static const plusStroke = 1.0;
  static const plusGap = 8 / 3;
  static const groupsTop = 53.0;
  static const groupRow = 52.0;
  static const groupNameCentre = 47 / 3;
  static const groupNameText = 14.0;
  static const groupNameLine = 20.0;
  static const groupTipCentre = 37.0;
  static const groupTipText = 10.0;
  static const groupTipLine = 14.0;
  static Color get groupTipInk => tone(0xFF999999, 0xFF757A81);
  static const tick = 22.0;
  static Color get tickRing => tone(0xFFE7E7E7, 0xFF46494D);
  static const tickRingWidth = 1.0;
  static Color get tickFill => BiliColors.pink;
  static const tickInk = BiliColors.onPink;
  static const tickStroke = 1.5;
  static const saveCentre = 106 / 3;
  static const saveText = 12.0;
  static const saveLine = 17.0;
  static Color get saveInk => BiliColors.pink;
  static const saveTarget = 44.0;
}

/// 我的关注 (129, 130). Measured in px / 3; the shots' colours are Display P3, so the pink reads #ED7098 and the badges'
/// yellow #F7CE45 there.
abstract final class FollowingListTheme {
  /// The bar under the status bar, 54 tall: the skin's `colorSecondPage` with its text colour (KaiC's green, 129), else
  /// white with the page's text (a guess). A 2/3 hairline ends it.
  static const barRow = 54.0;

  /// ‹ and the title centre this far under the status bar, above the row's middle.
  static const rowCentre = 22.0;
  static Color get bar => BiliColors.card;
  static Color get barInk => BiliColors.text;
  static const barLightInk = Color(0xFFFFFFFF);
  static const barHairline = 2 / 3;
  static Color get hairline => BiliColors.divider;

  /// 我的关注: 20 pt semibold, its ink centred on the screen and the bar's row.
  static const titleText = 20.0;
  static const titleWeight = FontWeight.w600;
  static const titleLine = 28.0;
  static const titleDrop = 1 / 3;

  /// ‹ in the round glass button: a 45.33 disc centred 42 in and on the row, the bar's colour lifted by white, a thin
  /// darker rim, white light along its top and bottom edges and a soft shadow; ‹ 7 × 14 with 1.5 strokes, its tip 4
  /// left of the disc's middle (ink 37.33-45.67 by 76.33-91.67).
  static const backDisc = 136 / 3;
  static const backCentreX = 42.0;
  static const backTarget = 52.0;
  /// At night the official glass back button (242, 249) reads #353638 on the dark bar, its light edge faint.
  static Color get backLift => tone(0x4DFFFFFF, 0x21FFFFFF);
  static const backRim = Color(0x40000000);
  static const backRimWidth = 0.5;
  static Color get backGloss => tone(0xCCFFFFFF, 0x33FFFFFF);
  static const backGlossWidth = 1.0;
  static const backShadow = Color(0x0D000000);
  static const backShadowBlur = 10.0;
  static const backShadowDrop = 2.0;
  static const backTip = -4.0;
  static const backWidth = 7.0;
  static const backHalfHeight = 7.0;
  static const backStroke = 1.5;
  static Color get backInk => tone(0xFF000000, 0xFFFFFFFF);

  /// 搜索我的关注: a 30 tall #F1F2F3 stadium 6 under the bar, 12 in from each side, then 5.67 and a 1/3 hairline the
  /// screen's width. The magnifier's ink is 12 square, centred 18 in and 1/3 above the field's middle (搜索's glyph,
  /// whose box is a third wider than its ink, raised half a point); the words, 13 pt, start 6 after it.
  static const searchTop = 6.0 - barHairline;
  static const searchBottom = 17 / 3;
  static const searchRule = 1 / 3;
  static Color get field => tone(0xFFF1F2F3, 0xFF1E2022);
  static const fieldHeight = 30.0;
  static const fieldInset = 12.0;
  static const fieldText = 13.0;
  static const fieldLine = 18.0;
  static Color get fieldInk => BiliColors.text;
  static Color get placeholder => tone(0xFFAEB3B9, 0xFF5E6267);
  static Color get caret => BiliColors.pink;
  static const magnifier = 37 / 3;
  static const magnifierLead = 35 / 3;
  static const magnifierLift = 0.5;
  static Color get magnifierInk => BiliColors.secondaryText;
  static const magnifierGap = 6.0;

  /// The grey ⓧ once there is text (搜索's; no screenshot shows it here).
  static const clear = 40 / 3;
  static Color get clearColor => tone(0xFFC9CCD0, 0xFF46494D);
  static const clearTarget = 36.0;

  /// 排序方式 and the order: a 40 tall row, both 13 pt on its middle; 排序方式 #9499A0 12 in, the order #484C52 ending 8
  /// before ▽ (9.33 × 5 of ink, 1.2 strokes, its right 13.33 from the edge, #61666D). △ while the menu is open.
  static const sortRow = 40.0;
  static const sortText = 13.0;
  static const sortLine = 18.0;
  static const sortDrop = -1 / 3;
  static Color get sortLabel => BiliColors.secondaryText;
  static Color get sortValue => tone(0xFF484C53, 0xFFB9BDC2);
  static const sortGap = 8.0;
  static const sortChevronWidth = 8.13;
  static const sortChevronHeight = 3.6;
  static const sortChevronStroke = 1.2;
  static const sortChevronRight = 40 / 3;
  static Color get sortChevron => tone(0xFF61666D, 0xFFA2A7AE);
  static const sortTarget = 110.0;

  /// The menu (130), from the sort row's bottom: a 2/3 hairline, then three 40 tall rows, 14 pt 12 in, the chosen pink
  /// with ✓ (12.67 × 8.67 of ink, centred 23 from the right and 2/3 under the row's middle); the rest #484C52. A notch
  /// 9 wide and 4.67 tall rises from the hairline 56 from the right, under the order's words, the hairline open
  /// beneath it. Below the menu the page is dimmed by half; a tap there, or anywhere above the menu, closes it.
  static const menuRow = 40.0;
  static const menuText = 14.0;
  static const menuLine = 20.0;
  static const menuDrop = 1.0;
  static Color get menuInk => tone(0xFF484C53, 0xFFB9BDC2);
  static Color get menuChosen => BiliColors.pink;
  static Color get menuFill => tone(0xFFFFFFFF, 0xFF242628);
  static const checkWidth = 11.17;
  static const checkHeight = 7.17;
  static const checkStroke = 1.5;
  static const checkRight = 23.0;
  static const checkDrop = 2 / 3;
  static const notchRight = 56.0;
  static const notchWidth = 9.0;
  static const notchHeight = 14 / 3;
  static const notchRim = 0.5;
  static const dim = BiliColors.sheetDim;
  static const menuMotion = Duration(milliseconds: 150);

  /// A row (129): 60 tall; the face 40 at 12 in on the row's middle, its verified bolt a 12 disc (1 ringed in white)
  /// flush with the face's right and bottom; the name 14 pt from 64, pink for a 大会员; the pink dot for new posts 9
  /// across, centred 17.5 from the right. A 1 pt hairline ends each row, 20 in from both sides.
  static const row = 60.0;
  static const face = 40.0;
  static const faceInset = 12.0;
  static const badge = 12.0;
  static const badgeRing = 1.0;
  static Color get badgePerson => tone(0xFFFFCC00, 0xFFFFCC00);
  static Color get badgeOrganisation => tone(0xFF3EA2F4, 0xFF40C5F1);
  static const nameLeft = 64.0;
  static const nameText = 14.0;
  static const nameLine = 20.0;
  static const nameDrop = 2 / 3;
  static Color get name => BiliColors.text;
  static Color get vipName => BiliColors.pink;
  static const nameGap = 12.0;
  static const dot = 9.0;
  static const dotRight = 17.5;
  static Color get dotInk => BiliColors.pink;
  static const rowRule = 1.0;
  static const rowRuleInset = 20.0;
  static Color get page => BiliColors.card;

  /// Typing waits this long for a pause before 搜索我的关注 asks.
  static const searchPause = Duration(milliseconds: 300);

  /// The next page is asked for this close to the list's end.
  static const loadAhead = 360.0;

  /// The first load's failure: its words 14 pt grey over a pink-ringed 重试, as logged out over 登录 (a guess); the
  /// list's footer 加载失败，点击重试 and the small spinner while a page loads (历史记录's).
  static const stateText = 14.0;
  static Color get stateInk => BiliColors.secondaryText;
  static const stateGap = 16.0;
  static const retryText = 14.0;
  static const retryHeight = 32.0;
  static const retryPadX = 20.0;
  static const retryRim = 0.67;
  static const footerText = 13.0;
  static Color get footerInk => BiliColors.secondaryText;
  static const footerPad = 16.0;
  static const spinnerRadius = 9.0;
}

/// The iPad's 首页 (ipad/01, 02), measured at 2× (pt = px / 2).
abstract final class PadHomeTheme {
  /// 推荐's grid: 375 pt cards sideways and 255 upright, 22 pt from the edges and 12 apart; the first row starts as
  /// far under the hairline as 01's banner does (the banner is left out).
  static const columns = 3;
  static Color get page => BiliColors.card;
  static const margin = 22.0;
  static const gutter = 12.0;
  static const rowGap = 12.0;
  static const firstRow = 18.0;

  /// Bilibili's own pink, as the iPad's selected tab, bar place and 推荐 draw it.
  static Color get pink => tone(0xFFFB7299, 0xFFD44E7D);

  /// The top: one row from the status bar to the hairline, everything centred [rowCentre] under the status bar.
  static const rowHeight = 45.5;
  static const rowCentre = 21.0;
  static const hairline = 0.5;
  static const avatar = 40.0;
  static const avatarLeft = 20.0;

  /// The search entry: a grey stadium from 75 pt, as wide as its word up to [fieldTabGap] short of the tab row.
  static const fieldLeft = 75.0;
  static const fieldHeight = 30.0;
  /// At night the palette's surface grey (Ga1_s), not the page's: the field sits on the card-coloured row.
  static Color get fieldFill => tone(0xFFF1F2F3, 0xFF232527);
  static const fieldGlyph = 13.0;
  static const fieldGlyphLead = 16.5;
  static Color get fieldGlyphInk => tone(0xFF999999, 0xFF757A81);

  /// The dressed field's ink, the day's at night too (see [HomeTabBarTheme.headField]).
  static const headFieldInk = Color(0xFF9499A0);
  static const headFieldGlyphInk = Color(0xFF999999);
  static const fieldTextStart = 35.5;
  static const fieldTextEnd = 17.0;
  static const fieldText = 13.0;
  static Color get fieldInk => BiliColors.secondaryText;
  static const fieldTabGap = 40.0;

  /// 直播 推荐 热门 追番 影视, centred on the screen, 65 pt apart.
  static const tabs = ['直播', '推荐', '热门', '追番', '影视'];
  static const tabText = 16.0;
  static const tabPitch = 65.0;
  static Color get tabInk => tone(0xFF999999, 0xFF757A81);
  static const tabRise = 1.25;

  /// Scan, 历史记录 and 消息, their centres this far from the right edge.
  static const icon = 20.0;
  static Color get iconInk => tone(0xFF757575, 0xFF8B9097);
  static const scanRight = 142.0;
  static const historyRight = 90.0;
  static const messagesRight = 38.0;
  static const iconLine = 1.5;

  /// The bottom bar: 50 pt from its hairline to the home indicator, four 118 pt places centred.
  static const barHeight = 50.0;
  static const barSlot = 118.0;
  static const barIconCentre = 18.25;
  static const barLabelTop = 31.5;
  static const barLabelText = 11.0;
  static Color get barIconInk => tone(0xFF747474, 0xFF8B9097);
  static Color get barLabelInk => tone(0xFF929292, 0xFF757A81);

  /// A 装扮's bar picture is made for a phone: the iPad draws it at the phone's 440 pt width grown by the bars'
  /// heights, centred, so it rises as far as on the phone (a guess: no screenshot of a dressed iPad bar).
  static const barArtWidth = 440 * barHeight / HomeTabBarTheme.height;

  /// A card: the cover's corners, its counts row, then the face, two title lines, the uploader and date, and ⋮.
  static const coverRadius = 4.0;
  static const footer = 87.0;
  static const face = 40.0;
  static const faceTop = 8.0;
  static const titleLeft = 46.0;
  static const titleRight = 39.0;
  static const titleTop = 7.75;
  static const titleText = 14.0;
  static const titleLine = 19.5;
  static const subTop = 51.0;
  static const subText = 13.0;
  static Color get subInk => BiliColors.secondaryText;
  static const bylineDotGap = 2.0;
  static const moreRight = 17.0;
  static const moreCentre = 27.0;
  static const moreDot = 3.0;
  static const morePitch = 5.0;
  static Color get moreInk => tone(0xFF757575, 0xFF8B9097);
  static const moreTarget = 34.0;
  static const tagHeight = 16.0;
  static const tagText = 11.0;
  static const tagPad = 4.0;
  static const tagRadius = 2.0;
  static const tagGap = 4.0;
  static const statText = 11.0;
  static const statIconWidth = 13.0;
  static const statIconHeight = 11.0;
  static const statLead = 10.5;
  static const statIconGap = 6.0;
  static const statGap = 15.0;
  static const statTrail = 11.5;
  static const statCentre = 17.5;
  static const durationGap = 4.0;
  static const shade = 40.0;

  /// The loading card's two grey title bars: the first [skeletonTitleDrop] under the face's top, [skeletonLineGap]
  /// between them.
  static const skeletonTitleDrop = 4.0;
  static const skeletonLineGap = 10.0;

  /// The cover's height on a card [width] wide: 16:9 and a pt and a half (212 sideways, 145 upright).
  static double coverHeight(double width) => (width * 9 / 16 + 1.5).roundToDouble();

  static double cardHeight(double width) => coverHeight(width) + footer;

  /// How wide each of the [columns] cards is in a grid [width] wide: whole points, the rest left at the right.
  static double cardWidth(double width) => ((width - margin * 2 - gutter * (columns - 1)) / columns).floorToDouble();

  static double rightMargin(double width) => width - margin - cardWidth(width) * columns - gutter * (columns - 1);
}

/// The iPad's video page frame: the two columns sideways (ipad/03, 05), one upright (06), the player's shrink to the
/// pink 立即播放 bar (05, 20).
abstract final class PadPageTheme {
  /// 03, 05 and 06 keep the page 32 pt below the screen's top, black above it, past the 24 pt status bar inset.
  static const statusBand = 32.0;

  /// The column's side margins (03, 06).
  static const gutter = 20.0;

  /// Sideways the related column is 437 pt with a 0.5 pt rule to its left and along its top (03); the player's column
  /// takes the rest (756.5 on the 1194 pt screen).
  static const relatedWidth = 437.0;
  static const rule = 0.5;
  static Color get ruleColour => BiliColors.divider;

  /// The paused player shrinks to the pink 立即播放 bar (05): 60 pt, its row centred 33 below its top, ‹ 18 in, ⋮ 21
  /// from the column's right, the APK's `ic_upper_tv_play` made opaque, 22 pt wide, 4.5 pt before 立即播放.
  static const barHeight = 60.0;
  static Color get barFill => BiliColors.pink;
  static const barRowCentre = 33.0;
  static const backLeft = 18.0;
  static const moreRight = 21.0;
  static const playGlyphWidth = 22.0;
  static const playGlyphHeight = 22.0 * 133 / 144;
  static const labelGap = 4.5;
  static const labelText = 16.0;
  static const label = BiliColors.onVideo;

  /// Once the player is the bar and 简介's actions have scrolled under it, a 60 pt strip stays pinned below it (05):
  /// the 40 pt face 20 in, the five actions at a 62 pt pitch from 79.75, 点我发弹幕 at the right; a rule under it.
  static const stripHeight = 60.0;
  static const stripFace = 40.0;
  static const stripFaceLeft = 20.0;

  /// The actions' icons start 10.5 below the strip's top.
  static const stripIconTop = 10.5;
  static const stripActionsLeft = 79.75;
  static const stripActionPitch = 62.0;

  /// The upright tab row (06): 60 pt, no underline and no rule, 简介 20 pt in and 评论 (N) 38 pt after it, both 16 pt.
  static const tabRowHeight = 60.0;
  static const tabText = 16.0;
  static const tabFirstLabel = 20.0;
  static const tabSpacing = 38.0;
  static Color get tabInk => PageTheme.tabText;

  /// 点我发弹幕 (the body's [PadDanmakuCapsule]) sits 20 pt from the right on the tab row and the strip (05, 06).
  static const capsuleRight = 20.0;

  /// The inline 热门评论 header sideways (03): a rule on top, 49.5 pt with its line centred 25.25 down; the title
  /// semibold 16 pt 20 in, the 218 × 30 field 96.5 in (13 pt, 15.5 in, the face 20 pt 7 from its end), then at the
  /// right ⇅ 按热度, a 12 pt rule and 查看 N 条评论 › 19.5 from the column's right, all 14 pt in 61666D.
  static const headerHeight = 49.5;
  static const headerCentre = 25.25;
  static const headerTitleText = 16.0;
  static const headerTitleWeight = FontWeight.w600;
  static Color get headerTitle => BiliColors.text;
  static const headerFieldLeft = 96.5;
  static const headerFieldWidth = 218.0;
  static const headerFieldHeight = 30.0;
  static const headerFieldText = 13.0;
  static const headerFieldPadding = 15.5;
  static Color get headerFieldFill => PageTheme.chipFill;
  static Color get headerFieldInk => BiliColors.secondaryText;
  static const headerFace = 20.0;
  static const headerFaceRight = 7.0;
  static const headerText = 14.0;
  static Color get headerInk => PageTheme.tabText;
  static const headerSortGlyph = 12.0;
  static const headerSortGap = 6.5;
  static const headerRuleHeight = 12.0;
  static const headerRuleGap = 10.0;
  static const headerChevronGap = 5.5;
  static const headerChevronWidth = 5.5;
  static const headerChevronHeight = 9.5;
  static const headerChevronStroke = 1.2;
  static const headerRight = 19.5;

  /// The 发条评论 bar under the sideways column (05): a 0.5 pt rule, then the 32 pt field 6.5 under it and 6.5 above
  /// the screen's bottom, over the home indicator; the field 20 in and 47.75 short of the column's right, its 12 pt
  /// prompt 20 in, the 20 pt face centred 15.75 from its end; ↑ (back to the top) centred 23.5 from the column's right,
  /// 18 × 20 with 1.25 pt strokes.
  static Color get commentRule => tone(0xFFC9CCD0, 0xFF46494D);
  static const commentGap = 6.5;
  static const commentFieldHeight = 32.0;
  static const commentFieldLeft = 20.0;
  static const commentFieldRight = 47.75;
  static Color get commentFieldFill => PageTheme.chipFill;
  static const commentPromptLeft = 20.0;
  static const commentPromptText = 12.0;
  static Color get commentInk => BiliColors.secondaryText;
  static const commentFaceRight = 15.75;
  static const commentTopRight = 23.5;
  static const commentTopWidth = 18.0;
  static const commentTopHeight = 20.0;
  static const commentTopStroke = 1.25;

  /// A guess: no screenshot shows an upright video on the page; KaiC's iPad shows it pillarboxed in full screen (25),
  /// so the box stays 16:9.
  static const uprightLimit = 1 / BiliMetrics.videoAspect;

  /// The player growing into full screen and back (22).
  static const fullScreenGrow = Duration(milliseconds: 300);
  static const fullScreenCurve = Curves.easeInOut;
}

/// The iPad's page body: 简介's sections and the related column (ipad/03, 04, 06).
abstract final class PadBodyTheme {
  /// Everything in 简介's head starts 20 in, the action cells too (03).
  static const gutter = 20.0;

  /// The avatar's top is 10 below the player sideways (03) and below the tab row upright (06).
  static const uploaderTop = 10.0;
  static const avatar = 40.0;
  static const avatarGap = 10.0;
  static const nameText = 14.0;
  static const nameLine = 18.0;
  static const fansText = 12.0;
  static const fansLine = 15.0;

  /// The name's and the counts' centres below the avatar's top.
  static const nameCentre = 10.0;
  static const fansCentre = 29.0;

  /// + 关注 follows the wider of the name and the counts, 21.5 after it: a 72 × 26 card with 4 pt corners.
  static const followGap = 21.5;
  static const followWidth = 72.0;
  static const followHeight = 26.0;
  static const followRadius = 4.0;
  static const followText = 13.0;
  static const followPlus = 9.5;
  static const followPlusStroke = 1.1;
  static const followPlusGap = 5.0;

  /// 点我发弹幕 and the 弹 toggle (03 sideways, 06 in the tab row upright): 158 × 32, 20 from the right edge, the
  /// words 15 in, the toggle's white 39.5 wide with the glyph centred 18.5 from the capsule's end.
  static const capsuleWidth = 158.0;
  static const capsuleHeight = 32.0;
  static const capsuleBorder = 0.5;
  static const capsuleToggle = 39.5;
  static const capsuleToggleOff = 44.0;
  static const capsuleTextLead = 15.0;
  static const capsuleText = 13.0;
  static const capsuleMarkCentre = 18.5;

  /// The words sit 1 lower than centred in the capsule.
  static const capsuleTextDrop = 1.0;

  /// The title's centre below the avatar's bottom: 32.5 sideways, 30.5 upright (03, 06).
  static const titleGap = 32.5;
  static const titleGapUpright = 30.5;
  static const titleText = 18.0;
  static const titleLine = 24.0;

  /// The iPad's title is the name's grey in a medium weight, lighter than the iPhone's.
  static Color get titleInk => IntroTheme.name;

  /// The 活动 capsule sits 1 below the title's centre.
  static const honorHeight = 20.0;
  static const honorDrop = 1.0;
  static const honorPadding = 8.0;
  static const honorText = 12.0;
  static const honorGap = 4.5;

  /// The meta line: 30 under the title's centre, ▶ 1.5 in, 15 × 13 icons 4 before their counts, groups 15.5 apart,
  /// then the BV id and 查看简介 with its 9 × 4.5 chevron 2.5 after it.
  static const metaGap = 30.0;
  static const metaLine = 16.0;
  static const metaText = 12.0;
  static const metaLead = 1.5;
  static const metaIconWidth = 15.0;
  static const metaIconHeight = 13.0;
  static const metaIconGap = 4.0;
  static const metaGroupGap = 15.5;
  static const toggleChevronGap = 2.5;
  static const toggleChevronWidth = 9.0;
  static const toggleChevronHeight = 4.5;

  /// 查看简介 opened (04): the description's 17 pt lines start 8.5 under the meta line, then the plain tags, 26 tall,
  /// 6.5 under the description, 12 apart, their names 13.5 from each end.
  static const descGap = 8.5;
  static const descText = 13.0;
  static const descLine = 17.0;
  static const tagsGap = 6.5;
  static const tagHeight = 26.0;
  static const tagText = 12.0;
  static const tagPadding = 13.5;
  static const tagSpacing = 12.0;
  static Color get tagInk => IntroTheme.name;
  static Color get tagFill => tone(0xFFF1F2F3, 0xFF1E2022);

  /// The actions (03): 70 pt cells from the gutter, a 30 pt icon centred 35.5 under the meta line's centre, its count
  /// centred 26.75 below the icon's in the icons' grey, and the head ending 21.25 under the counts, where 热门评论's
  /// hairline is.
  static const actionCell = 70.0;
  static const actionTopGap = 35.5 - metaLine / 2 - actionIcon / 2;
  static const actionIcon = 30.0;
  static const actionCountLine = 15.0;
  static const actionCountGap = 26.75 - actionIcon / 2 - actionCountLine / 2;
  static const actionCountText = 12.0;
  static Color get actionCount => ActionTheme.icon;
  static const actionsBottom = 21.25 - actionCountLine / 2;
  static const actionRing = 40.0;

  /// The sections that follow (合集, parts, topic chips) keep the iPhone's look at the iPad's gutter.
  static const sectionInset = gutter - BiliMetrics.gutter;

  /// A related row (03, 06): 97 apart, a 138 × 77 cover 10 below the row's top, the text 10.5 right of it. No
  /// hairlines between rows; upright the list opens with one 10 under the head, 10 in from each side.
  static const relatedRowHeight = 97.0;
  static const relatedCoverTop = 10.0;
  static const relatedCoverWidth = 138.0;
  static const relatedCoverHeight = 77.0;
  static const relatedTextGap = 10.5;
  static const relatedTitleLift = 1.5;

  /// The iPad's related titles are medium, where the iPhone's are regular.
  static const relatedTitleWeight = FontWeight.w500;

  /// The first cover sits where the ad's does, 16 under the column's top or the list's hairline.
  static const relatedListTop = 6.0;
  static const relatedHairlineGap = 10.0;
  static const relatedHairlineInset = 10.0;

  /// Sideways the column's rows sit 10 from its edges; upright the page's 20.
  static const relatedColumnGutter = 10.0;
  static const relatedUploaderCentre = 49.75;
  static const relatedCountsCentre = 69.0;
  static const relatedMetaLead = 0.5;
  static const relatedMetaGap = 6.0;
  static const relatedCountSpacing = 12.5;
  static const relatedIconWidth = 14.0;
  static const relatedIconHeight = 12.0;
  static const relatedUpFont = 8.0;
  static const relatedUpRadius = 3.0;

  /// ⋮: three 3 pt dots 1.5 apart, centred 8 inside the gutter on the counts' line.
  static const moreDot = 3.0;
  static const moreDotGap = 1.5;
  static const moreInset = 8.0;

  /// The cover's duration tag (06), 5 in from the corner, a lighter shade than the iPhone's, reads 04:15 as the iPad
  /// writes it.
  static const durationInset = 5.0;
  static const durationHeight = 14.0;
  static const durationPad = 4.5;
  static const durationRadius = 3.0;
  static const durationFill = Color(0x80000000);
}

/// The iPad's controls over the page's player and its end screen (ipad/03, 07, 17).
abstract final class PadInlineControlsTheme {
  /// A control's centre from its edge of the player: back, ⋮ and 全屏 (03: 28.5-29 pt; 07 the same).
  static const edgeCentre = 29.0;

  /// The top row's centre from the player's top, and the bottom row's from its bottom.
  static const topCentre = 29.0;
  static const bottomCentre = 29.0;

  /// From the player's right: the 投屏 TV and 倍速 share a column, the 小窗 icon is left of the TV.
  static const castCentre = 87.0;
  static const floatCentre = 144.25;

  /// The glyphs' ink (03, 07), drawn from the APK's `biliplayer_ic_topbar_floatwindow` and `_tv`.
  static const floatWidth = 24.5;
  static const floatHeight = 19.5;
  static const castWidth = 24.0;
  static const castHeight = 19.33;
  static const backWidth = 9.0;
  static const backHeight = 18.0;
  static const moreDot = 3.0;
  static const moreDotGap = 4.5;

  /// The float window's lines, 1 of its 22-unit viewport at the ink's scale.
  static const floatStroke = 1.17;

  /// ⏮ (the APK's `bili_mini_player_ctrl_play_prev`), its centre from the left, and half white with nothing before.
  static const previousCentre = 29.0;
  static const previousWidth = 11.67;
  static const previousHeight = 13.33;
  static const previousOffOpacity = 0.5;

  static const playCentre = 86.5;
  static const playWidth = 17.0;
  static const playHeight = 20.0;

  /// The bar's left end (the TV's left at 0:00: its centre at 116) and the gap before the time; the time ends 142
  /// from the right, so the bar ends 232.5 from it with 03's time.
  static const barLeft = 107.0;
  static const timeGap = 17.0;
  static const timeRight = 142.0;
  static const timeFont = 12.5;

  static const speedFont = 16.0;
  static const speedWidth = 60.0;
  static const fullScreenGlyph = 16.0;

  /// 章节 · (chapter) ›: 14 pt from 21 pt in, its centre 65.75 above the player's bottom; the chevron 6.5 × 11, 11
  /// after the text.
  static const chapterLeft = 21.0;
  static const chapterCentre = 65.75;
  static const chapterFont = 14.0;
  static const chapterHeight = 24.0;
  static const chevronWidth = 6.5;
  static const chevronHeight = 11.0;
  static const chevronGap = 11.0;
  static const chevronStroke = 1.5;
  static const chapterShadow = 2.0;

  /// The shades behind both rows (07 against 06, the same frame): near black at the edge, gone 96 pt in.
  static const shadeHeight = 96.0;
  static const shade = [
    Color(0xFF000000),
    Color(0xF5000000),
    Color(0xC7000000),
    Color(0x87000000),
    Color(0x42000000),
    Color(0x14000000),
    Color(0x00000000),
  ];
  static const shadeStops = [0.0, 1 / 6, 2 / 6, 3 / 6, 4 / 6, 5 / 6, 1.0];

  /// With the controls hidden, the chapters across the bottom (06): each title 9 pt, centred on its stretch, 10.67
  /// above the bottom, between hairlines 20 pt tall, over a 22 pt shade.
  static const stripFont = 9.0;
  static const stripCentre = 10.67;
  static const stripLine = 0.5;
  static const stripLineHeight = 20.0;
  static const stripLineInk = Color(0x4DFFFFFF);
  static const stripShadeHeight = 22.0;
  static const stripShade = Color(0x9E000000);
  static const stripPad = 4.0;

  /// The end screen (17) on a 756.5 × 425.5 player, its block placed from the player's middle.
  static const endTopCentre = 42.0;
  static const endEdgeCentre = 21.5;
  static const endBackWidth = 9.5;
  static const endCaptionLeft = 51.0;
  static const endCaptionCentre = -34.25;
  static const endCaptionFont = 13.5;
  static const endCoverLeft = 50.0;
  static const endCoverTop = -18.75;
  static const endCoverWidth = 224.0;
  static const endCoverHeight = 126.0;
  static const endCoverRadius = 6.0;
  static const endCoverShadeHeight = 40.0;
  static const endCoverTextInset = 9.0;
  static const endCoverTimeFont = 12.0;
  static const endPlayWidth = 18.5;
  static const endPlayHeight = 21.0;
  static const endInfoGap = 11.0;
  static const endInfoRight = 24.0;
  static const endTitleCentre = 0.75;
  static const endTitleFont = 16.0;
  static const endUploaderCentre = 70.25;
  static const endCountsCentre = 89.25;
  static const endMetaFont = 12.5;
  static const endCountFont = 12.0;
  static const endMetaRow = 16.0;
  static const endMetaGap = 6.0;
  static const endMetaSpacing = 14.0;

  /// 重播 and 分享 on one line, the share text's end 67.5 from the right.
  static const endActionsCentre = -33.75;
  static const endActionsRight = 67.5;
  static const endActionFont = 14.0;
  static const endReplayWidth = 19.5;
  static const endReplayHeight = 21.0;
  static const endReplayGap = 10.0;
  static const endShareInk = 24.0;
  static const endShareGap = 6.7;
  static const endActionSpacing = 37.2;
}

/// The iPad's full screen: top and bottom bars, side buttons, the end screen, the hold, buffering and the seek
/// preview (ipad/08, 14-16, 18, 19, 24). Measured at 2 px per pt on KaiC's
/// iPad Pro 11" sideways (1194 × 834, the status bar's 24 pt above, the home indicator's 20 below); rows are placed
/// from the safe area's edges, columns from the screen's.
abstract final class PadFullScreenTheme {
  /// The shades behind the bars, black at the safe area's edge and clear 100 pt into the top and 108 into the bottom
  /// (18 against 19). 08's bands are the video's letterbox, black either way.
  static const topShade = 100.0;
  static const bottomShade = 108.0;
  static const bottomShadeSolid = 6.0;

  /// The top row: 44 pt tall, centred 28.8 pt under the status bar; ‹ centred 28.3 pt in, the title from 58.8.
  static const topRowTop = 6.8;
  static const backLeft = 6.3;
  static const backWidth = 10.0;
  static const backHeight = 17.3;
  static const titleLeft = 58.8;
  static const titleText = 18.0;
  static const titleGap = 16.0;

  /// The system font's ink sits 1.5 pt higher in its line than 08's title, 1.2 pt for the times' digits, 2 for the
  /// chapter line and 1 for 关注.
  static const titleDrop = 1.5;
  static const timeDrop = 1.2;
  static const chapterDrop = 2.0;
  static const followDrop = 1.0;

  /// 点赞 不喜欢 投币 收藏 充电 分享, 70 pt apart, then ⋮ centred 34 pt from the right edge.
  static const actionSlot = 70.0;
  static const actionsToMore = 13.0;
  static const moreRight = 12.0;
  static const actionIcon = 28.5;
  static const actionStroke = 1.3;

  /// 不喜欢's thumb hangs lower in its box than 08 draws it.
  static const dislikeLift = 2.2;

  /// The superscript like count: its left edge 7.8 pt right of the button's centre, on a baseline 12.4 pt into it.
  static const countText = 10.0;
  static const countLead = 7.8;
  static const countBaseline = 12.4;

  /// N人正在看 centred 83 pt down, its icon under the title's first character, in white where the phone's is 60%.
  static const onlineCentre = 58.0;
  static const onlineHeight = 16.0;
  static const online = Color(0xFFFFFFFF);
  static const onlineIcon = Color(0xEBFFFFFF);

  /// The uploader's chip (18, 24): a 27% black capsule 31.5 pt tall from 16.2 pt in, centred 114 pt down, holding
  /// the 28 pt avatar 1.5 pt in, the plus 11 pt after it, 关注 5.4 pt after that and 15.3 pt of the capsule after it.
  /// No name (24's and 18's chips have none).
  static const chipLeft = 16.2;
  static const chipCentre = 90.0;
  static const chipHeight = 31.5;
  static const chipFill = Color(0x45000000);
  static const chipInset = 1.5;
  static const avatar = 28.0;
  static const plusLead = 11.0;
  static const plus = 10.3;
  static const plusStroke = 1.0;
  static const plusGap = 5.4;
  static const followText = 13.5;
  static const followTrailing = 15.3;

  /// 截图 and the lock in 51.5 pt tiles of 30% black with 9 pt corners, 8.3 pt from the right edge, 16.5 pt apart,
  /// the pair's middle 18.6 pt above the screen's.
  static const tile = 51.5;
  static const tileRadius = 9.0;
  static const tileFill = Color(0x4D000000);
  static const tileRight = 8.3;
  static const tileGap = 16.5;
  static const tilesLift = 18.6;
  static const cameraWidth = 23.5;
  static const cameraHeight = 18.0;
  static const lockWidth = 21.5;
  static const lockHeight = 23.3;

  /// From the safe area's bottom: the bottom row's centre 36 pt up, the bar's 82, the chapter line's 113.4.
  static const rowBottom = 14.0;
  static const rowToBar = 12.0;
  static const barToChapter = 7.4;
  static const chapterBox = 24.0;

  /// 章节 · title › from 23.6 pt in, 15 pt, the chevron 10 pt tall 8 pt after the title.
  static const chapterLeft = 23.6;
  static const chapterText = 15.0;
  static const chapterChevronGap = 8.0;
  static const chapterChevronWidth = 6.0;
  static const chapterChevronHeight = 11.0;
  static const chapterChevronStroke = 1.6;

  /// The bar from 74.5 pt in to 74.5 pt from the right, the TV's travel 83.5 to 1110.5; the times 24 pt in from
  /// either edge, 13 pt.
  static const barInset = 74.5;
  static const timeInset = 24.0;
  static const timeText = 13.0;

  /// The bottom row: ⏮ centred 29.1 pt in, ▶ 92, 弹 157.6, 弹幕设置 221.6; the field from 264 to 287.1 pt from the
  /// right edge; 倍速, 1080P, 小窗 and 退出全屏 centred 240.7, 169.7, 97.5 and 34.2 pt from it.
  static const prevLeft = 7.1;
  static const prevToPlay = 18.9;
  static const playToDanmaku = 21.6;
  static const danmakuToSettings = 20.0;
  static const settingsToField = 20.4;
  static const fieldToSpeed = 23.4;
  static const speedToQuality = 17.5;
  static const qualityToPip = 19.7;
  static const pipToExit = 19.3;
  static const exitRight = 12.2;
  static const textPad = 8.0;
  static const labelText = 15.0;

  /// ⏮ (the APK's `bili_player_ctrl_play_previous`) 13.7 × 14.5 pt, half white with nothing before it; ▶'s ink 23 ×
  /// 26.4, its box larger by what the rounded corners take off.
  static const prevWidth = 13.7;
  static const prevHeight = 14.5;
  static const prevOff = Color(0x80FFFFFF);
  static const playWidth = 25.0;
  static const playHeight = 29.5;
  static const playCorner = 1.6;
  static const playShift = 1.2;
  static const pauseBar = 6.5;
  static const pauseGap = 5.5;

  /// 弹 and 弹幕设置, the phone's TVs drawn 24 × 23.
  static const danmakuWidth = 24.0;
  static const danmakuHeight = 23.0;

  /// 发个友善的弹幕见证当下 in a 29.7 pt field of 30% white with 5 pt corners, 12 pt half-white text 12.4 pt in.
  static const fieldHeight = 29.7;
  static const fieldRadius = 5.0;
  static const fieldFill = Color(0x4DFFFFFF);
  static const fieldInk = Color(0x80FFFFFF);
  static const fieldInset = 12.4;
  static const fieldText = 12.0;

  /// 高码率's tag: centred 14.9 pt above the row's centre, its right end 10.8 pt past 1080P's.
  static const tagRise = 14.9;
  static const tagOverhang = 10.8;

  /// 小窗's ink (the APK's `biliplayer_ic_topbar_floatwindow`, as the page's player draws it) 24.4 × 19.6; 退出全屏's
  /// two brackets 21 pt, the elbows 8.5 pt in from their corners.
  static const pipWidth = 24.4;
  static const pipHeight = 19.6;
  static const exitBox = 21.0;
  static const exitElbow = 8.5;
  static const glyphStroke = 1.3;
  static const offOpacity = 0.5;

  /// 09's strip while the controls are hidden: 19 pt under the video, the played part a grey fading down, under the
  /// inline player's titles (`PadChapterStrip`), whose box ends 22.3 pt down so they centre 11.6 pt under the video.
  static const stripHeight = 19.0;
  static const stripBox = 22.3;
  static const stripPlayed = Color(0x99B4B4B4);

  /// The hold's arrows (15), smaller than the phone's: 16.8 × 10.9 pt, 7.6 pt before the label.
  static const hudArrowWidth = 9.6;
  static const hudArrowHeight = 10.9;
  static const hudArrowStep = 7.2;
  static const hudGap = 7.6;

  /// Recording 24: the frame 144 × 81 (16:9) with 3 pt corners, its bottom 20.2 pt above the bar's middle and its
  /// middle 16 pt left of the TV's; the arrows and the time (13 pt, white) inside, centred 23.8 pt above its bottom;
  /// the chapter's title in an 90% black box 31.5 pt tall with 3.5 pt corners, 4.7 pt above the frame.
  static const previewWidth = 144.0;
  static const previewHeight = 81.0;
  static const previewRadius = 3.0;
  static const previewAboveBar = 20.2;
  static const previewShift = 16.0;
  static const previewEdge = 8.0;
  static const previewTimeText = 13.0;
  static const previewTimeRise = 23.8;
  static const previewArrowGap = 7.8;
  static const previewTitleHeight = 31.5;
  static const previewTitleRadius = 3.5;
  static const previewTitlePad = 12.5;
  static const previewTitleText = 12.0;
  static const previewTitleGap = 4.7;
  static const previewTitleFill = Color(0xE61B1B1B);

  /// The end screen (16): ‹ in the band above the video, the 60 pt avatar ringed 1.5 pt white at 22.2, 82.2; the
  /// name 16 pt from 98.2, its ink centred 92 down; + 关注 (59.5 wide, pink) and 为TA充电 (71.6 wide, outlined) 29.5
  /// pt tall with 2.5 pt corners, 12.5 pt apart from 112.2 down. Text boxes are placed where the stand-in fonts' ink
  /// lands on 16's, which sits about 2 pt above the box's middle.
  static const endDim = Color(0xD9000000);
  static const endBackTop = 20.0;
  static const endHeadTop = 82.2;
  static const endInset = 22.0;
  static const endAvatar = 60.0;
  static const endAvatarRing = 1.5;
  static const endNameLeft = 98.2;
  static const endNameText = 16.0;
  static const endNameCentre = 11.6;
  static const endPillTop = 30.0;
  static const endPillHeight = 29.5;
  static const endPillRadius = 2.5;
  static const endFollowWidth = 59.5;
  static const endChargeWidth = 71.6;
  static const endPillGap = 12.5;
  static const endPillText = 14.0;
  static const endPillPlus = 9.0;
  static const endPillPlusStroke = 1.2;
  static const endPillPlusGap = 5.0;

  /// 重播, a rule, 点赞 不喜欢 投币 收藏 分享 in 70 pt columns, 分享 centred 73 pt from the right edge: the icons
  /// centred 13.8 pt and the 15 pt labels' ink 52.3 below the avatar's top; the rule 56 tall, 57 pt from 重播's
  /// centre.
  static const endActionSlot = 70.0;
  static const endActionsRight = 38.0;
  static const endActionIcon = 28.5;

  /// The phone's replay ring, which scales by its height, drawn about as wide as 16's 21 pt.
  static const endReplayWidth = 21.0;
  static const endReplayHeight = 20.0;
  static const endIconCentre = 13.8;
  static const endLabelCentre = 54.1;
  static const endLabelText = 15.0;
  static const endReplayToRule = 57.0;
  static const endRuleHeight = 56.0;
  static const endRuleTop = 1.8;
  static const endRule = Color(0x26FFFFFF);

  /// 推荐视频 (14 pt from 30.7, centred 186.7 down), then four columns from 22 pt in, 12.5 apart, of 16:10 covers with 4
  /// pt corners from 210 down, a row every 237 pt.
  static const endHeaderLeft = 30.7;
  static const endHeaderCentre = 105.8;
  static const endHeaderText = 14.0;
  static const endGridTop = 23.3;
  static const endColumns = 4;
  static const endCardGap = 12.5;
  static const endRowGap = 22.4;
  static const endCoverAspect = 1.6;
  static const endCoverRadius = 4.0;

  /// On the cover: the counts 10 pt with the icons 9.3 pt in, the duration 9.1 pt from the right, centred 10.8 pt above
  /// its bottom. Under it the title, 14 pt in 16.8 pt lines, 65% white, 7.2 pt down.
  static const endCoverInset = 9.3;
  static const endCoverTrailing = 9.1;
  static const endCountCentre = 10.8;
  static const endCountText = 10.0;
  static const endCountSpacing = 10.7;
  static const endCountIconGap = 4.0;
  static const endTitleTop = 7.2;
  static const endTitleText = 14.0;
  static const endTitleLeading = 1.2;
  static const endTitleInk = Color(0xA6FFFFFF);
}

/// The iPad's player panels (ipad/10-13), measured at 2× (pt = px / 2). In full screen every panel is a hard-edged
/// strip at the right, the same width in points whichever way the iPad is held; the rows inside are the phone's.
abstract final class PadPanelTheme {
  /// 清晰度 and 倍速 (10, 11): a 242 pt strip; ⋮, 弹幕设置 and the panels opened from them (12, 13): 320.
  static const narrowWidth = 242.0;
  static const wideWidth = 320.0;

  /// The video shows through 16% under 清晰度 and ⋮, 12% under 倍速 and 弹幕设置.
  static const shade = Color(0xD6000000);
  static const darkShade = Color(0xE0000000);

  /// 弹幕设置's cards and the side panels' rows end this far before the screen's edge, as the phone's do before its
  /// safe area; ⋮'s cards keep [moreInset] each side, so its four squares sit [moreActionGap] apart.
  static const trailing = 16.0;
  static const moreInset = 12.0;
  static const moreActionGap = 32.0;

  /// 12's first card is 80 pt down, 8 below where the phone's header puts it under the 24 pt status bar.
  static const danmakuTop = 8.0;

  /// 10's rows: 66 pt apart, their block centred [qualityLift] above the screen's middle, the text [qualityLead] in
  /// from the strip and the 大会员 tag ending [qualityTrailing] before the screen's edge.
  static const qualityRow = 66.0;
  static const qualityLift = 12.0;
  static const qualityLead = 43.5;
  static const qualityTrailing = 36.0;
  static const qualityText = 16.0;
  static const qualitySubtitleText = 11.0;
  static const qualityHeaderTop = 14.0;
  static const qualityHeaderGap = 8.0;
  static const qualitySelected = Color(0xFFFB7299);
  static const badgeHeight = 15.0;
  static const badgePad = 6.0;
  static const badgeText = 10.0;
  static const badgeFill = Color(0xFFFB7299);

  /// 11's values: 58 pt apart, centred on the screen and in the strip.
  static const speedRow = 58.0;
  static const speedText = 16.0;
  static const speedSelected = Color(0xFFFF6699);

  /// On the page (no screenshot): the sheets keep the phone's heights in points (shares of its 956) and stay under
  /// the player, in its column.
  static const phoneHeight = 956.0;
}

/// The iPad's danmaku, on the page's player and in full screen (ipad/09, 25).
abstract final class PadDanmakuTheme {
  /// Full screen's text at an elem's fontSize of 25: 09's CJK advances are 43.4 px (9 of them over 391 px) and 25's
  /// lanes 62.6 px apart, which the phone's 1.44 lane spacing and 1 pt outline give at 21.75 pt. Lanes run from the
  /// screen's top edge, 25's six of them filling 25% of the whole 834 pt height, pillarbox included.
  static const fontFullScreen = 21.75;

  /// The landscape screen's width, against which the page's player scales [fontFullScreen]: no screenshot shows
  /// danmaku on the page (03, 07), so they keep full screen's share of a 16:9 picture, as the phone's small player
  /// does (12.5 against 22).
  static const fullScreenWidth = 1194.0;

  /// The style panel's height before a keyboard has been up to measure (the iPad Pro 11"'s, with its suggestions
  /// row); the panel takes the real keyboard's height once it has risen.
  static const landscapePanelHeight = 405.0;
  static const portraitPanelHeight = 320.0;
}

/// 缓存's sheet (141-144, 153, 154) and the portrait ⋮ sheet it opens from (42, 43, differences/22).
abstract final class DownloadSheetTheme {
  /// Both sheets are light grey with white cards; in 竖屏 they stand 573.67 pt tall (43), in the small player they run
  /// from the player's bottom. At night the sheet is Ga12 and the cards and squares Ga11 (258).
  static Color get sheet => tone(0xFFF6F7F8, 0xFF202123);
  static Color get card => BiliColors.dialog;
  static const verticalHeight = 573.67 / 956;
  static const cardRadius = 8.0;
  static const cardInset = 16.0;
  static Color get hairline => BiliColors.divider;
  static Color get grey => tone(0xFF61666D, 0xFFA2A7AE);

  /// ⋮ (42, 43): the squares 35 below the sheet's top (where 42's share icons start; KaiC took that row out), then
  /// the card of rows 51 below them.
  static const tilesTop = 24.0;
  static const tileSize = 48.0;
  static const tileLead = 18.0;
  static const tileGap = 16.0;
  static const tileRadius = 8.0;
  static const tileLabelCentre = 14.67;
  static const tileLabelText = 11.0;
  static const tilesBottom = 51.0;
  static const cardGap = 12.0;
  static const bottom = 12.0;

  /// The icon fonts' glyphs at the ink width 42 measures on each square, drawn in [ink].
  static const tileGlyphWidth = 20.0;
  static const tileGlyphWide = 21.0;
  static Color get ink => BiliColors.text;

  static const rowHeight = 52.0;
  static const rowText = 14.0;
  static const detailText = 12.0;
  static const segmentText = 12.0;
  static const segmentDivider = 12.0;

  /// 循环播放's three cells and 倍速's strip, right-aligned at the row's trailing edge; the strip starts 88 into the
  /// card and fades its first 12 pt, so 0.75 shows only as .75 under 42's 倍速.
  static const loopCell = 88.33;
  static const speedCell = 54.67;
  static const speedStart = 88.0;
  static const speedFade = 12.0;

  /// The switch, off: a light grey track and a white knob with a faint shadow; 258's track at night.
  static Color get trackOff => tone(0xFFE6E6E8, 0xFF5F6065);
  static const knobShadow = Color(0x29000000);
  static const knobShadowBlur = 2.0;

  /// The pages ⋮ opens inside the sheet (定时关闭 ›, 画面尺寸 ›; no screenshot).
  static const pageHeader = 44.0;
  static const pageTitleText = 16.0;
  static const pageBackGlyph = 16.0;

  /// The row icons drawn from 42 and 43 (their ink boxes).
  static const speedGlyphWidth = 16.33;
  static const speedGlyphHeight = 11.0;
  static const timerGlyphWidth = 16.67;
  static const timerGlyphHeight = 17.67;
  static const listenGlyphWidth = 16.0;
  static const listenGlyphHeight = 15.0;
  static const subtitleGlyphWidth = 16.67;
  static const subtitleGlyphHeight = 14.33;
  static const gestureGlyph = 18.33;
  static const qualityGlyph = 16.67;
  static const glyphStroke = 1.2;

  /// 缓存 (141): 画质 and the quality's name on a line 30.2 below the grabber, the list from 52 below it.
  static const headerCentre = 30.2;
  static const listTop = 52.0;
  static const headerText = 14.0;
  static const headerGap = 12.0;
  static const headerChevronGap = 4.0;
  static const headerChevronWidth = 9.33;
  static const headerChevronHeight = 5.0;

  static const rowGap = 12.0;

  /// A video or a part (141, 153): its title on one line in a card 52 tall, the mark in the card's corner.
  static const titleRowHeight = 52.0;
  static const titleRowLead = 14.0;
  static const titleRowTrailing = 5.67;
  static const titleText = 14.0;
  static const titleLine = 20.0;
  static const playingGap = 6.67;
  static Color get playing => BiliColors.pink;
  /// Bilibili's #FB7299, which the night pages keep (255's tick).
  static const playingBars = Color(0xFFFB7299);

  /// A 合集's video (144, 154): the cover 134.67 × 76 with 12 round it, the title two 20 pt lines beside it.
  static const coverRowPad = 12.0;
  static const coverWidth = 134.67;
  static const coverHeight = 76.0;
  static const coverGap = 8.67;

  /// The state's 13 pt circle: an empty ring, the pink progress over it, or 153's green ✓.
  static const mark = 13.0;
  static const markStroke = 2.5;
  static const markInset = 4.0;
  static Color get markTrack => BiliColors.divider;
  static Color get markDone => tone(0xFF2AC864, 0xFF1FA251);
  static const markFailed = BiliColors.failure;

  /// KaiC's sizes: 约 78.4MB left of the mark, on its line.
  static const sizeText = 10.0;
  static const sizeGap = 6.0;

  /// 内容到底啦 (154), centred 40.5 under the last card, 28.5 over the bar.
  static const footerCentre = 40.5;
  static const footerBottom = 28.5;

  /// The bar (141): 缓存全部 | 查看缓存 on a line 28 below its hairline, the space line 62.5 below it; its numbers
  /// are medium and a little larger than the words (their caps 7.67 tall on 141 and 154).
  static const barHeight = 70.0;
  static const barButtonCentre = 28.0;
  static const barButtonText = 16.0;
  static const barDivider = 22.0;
  static const barSpaceCentre = 62.5;
  static const barSpaceText = 10.0;
  static const barSpaceValueText = 10.5;
  static const barSpaceValueWeight = FontWeight.w500;
  static Color get dot => tone(0xFFF85A54, 0xFFD1403E);
  static const dotSize = 6.0;
  static const dotRing = 1.0;
  static const dotLift = 1.0;

  /// 画质's own sheet (142): its card 19 below its top, rows of 52 with the text 16 in.
  static const pickerCardTop = 19.0;
  static const pickerRowLead = 16.0;
  static const pickerBottom = 12.0;
}

/// 离线缓存, 正在缓存, a 合集's page and their search and edit modes (143, 145-151, 155-157), measured at 3 px per pt.
abstract final class OfflineListTheme {
  static Color get page => BiliColors.card;
  static Color get ink => BiliColors.text;
  static Color get grey => tone(0xFF61666D, 0xFFA2A7AE);
  static Color get meta => BiliColors.secondaryText;

  /// The bar, 44 under the status bar: the 装扮's second-page colour and text colour (KaiC's green, 143), else white
  /// with the page's text (a guess, as 我的关注's). No hairline ends it.
  static const barRow = 44.0;
  static Color get bar => BiliColors.card;
  static Color get barInk => BiliColors.text;
  static const barLightInk = Color(0xFFFFFFFF);

  /// The title, 17 pt semibold, centred on the screen and the row.
  static const titleText = 17.0;
  static const titleWeight = FontWeight.w600;
  static const titleLine = 24.0;
  static const titleDrop = 0.0;

  /// ‹: 1.5 strokes, its tip 20.08 in and its ends 27.92 in, 8.25 above and below the row's middle.
  static const backTarget = 44.0;
  static const backTipX = 20.08;
  static const backEndX = 27.92;
  static const backHalfHeight = 8.25;
  static const backStroke = 1.5;

  /// 🔍 and ☰, 36 apart, the last centred 24 from the edge (🔍 takes ☰'s place while nothing is finished, 143).
  static const iconTarget = 36.0;
  static const iconLastCentre = 24.0;

  /// 🔍: an 18 square, its ring 16.67 across with 1.67 strokes, the handle to the corner; centred 0.67 above the row's
  /// middle.
  static const searchBox = 18.0;
  static const searchRingCentre = 25 / 3;
  static const searchRingRadius = 7.5;
  static const searchStroke = 5 / 3;
  static const searchHandleEnd = 17.17;
  static const searchLift = 2 / 3;

  /// ☰ (edit): three 1.5 bars 11.67 long, 6.17 apart; ✓, ○, ✓ before them. 18.67 × 16.33 of ink, centred 0.17 above
  /// the row's middle.
  static const editWidth = 56 / 3;
  static const editHeight = 49 / 3;
  static const editStroke = 1.5;
  static const editPitch = 37 / 6;
  static const editBarLeft = 7.75;
  static const editBarRight = 17.92;
  static const editMarkCentre = 2.83;
  static const editRingRadius = 1.85;
  static const editRingStroke = 1.3;
  static const editLift = 1 / 6;

  /// 完成 (149) and the search's 取消 (151), 14 pt in the bar's ink, ending 16.67 and 12.33 from the edge.
  static const actionText = 14.0;
  static const doneRight = 50 / 3;
  static const cancelRight = 37 / 3;

  /// 搜索已下载的内容 (151): a 28 tall #F1F2F3 stadium from 12 in to 52 from the edge on the row's middle; the grey
  /// magnifier (搜索's) 12 square of ink, 18 in and 0.67 low; the words 14 pt from 30.33 in; 搜索's ⓧ once there is
  /// text (no screenshot).
  static const fieldLeft = 12.0;
  static const fieldRight = 52.0;
  static const fieldHeight = 28.0;
  static Color get field => tone(0xFFF1F2F3, 0xFF1E2022);
  static const fieldText = 14.0;
  static const fieldLine = 20.0;
  static Color get fieldInk => BiliColors.text;
  static Color get fieldHint => BiliColors.sheetHint;
  static Color get caret => BiliColors.pink;
  static const fieldGlyph = 37 / 3;
  static const fieldGlyphCentre = 18.0;
  static const fieldGlyphDrop = 2 / 3;
  static const clearGlyph = 40 / 3;
  static Color get clearInk => tone(0xFFC9CCD0, 0xFF46494D);
  static const clearTarget = 36.0;
  static const fieldTextLeft = 91 / 3;

  /// 正在缓存 and 已缓存视频: a 43 tall block, 16 pt semibold 12 in, its middle 25.33 down.
  static const headerHeight = 43.0;
  static const headerCentre = 76 / 3;
  static const headerText = 16.0;
  static const headerWeight = FontWeight.w600;
  static const headerLeft = 12.0;

  /// A row: 102 tall, the 139 × 78 cover 12 in and 12 down with 6 corners; the words from 159 to 12 from the edge.
  static const row = 102.0;
  static const coverLeft = 12.0;
  static const coverTop = 12.0;
  static const coverWidth = 139.0;
  static const coverHeight = 78.0;
  static const coverRadius = 6.0;
  static Color get coverPlaceholder => tone(0xFFF1F2F3, 0xFF1E2022);
  static const textLeft = 159.0;
  static const textRight = 12.0;

  /// The title, 14 pt in up to two lines 21.33 apart, the first's middle 8.25 under the cover's top; under it the part
  /// or episode, 12 pt #61666D, its middle 28.33 down.
  static const rowTitleText = 14.0;
  static const rowTitleLine = 64 / 3;
  static const rowTitleCentre = 8.25;
  static const subText = 12.0;
  static const subLine = 16.0;
  static const subCentre = 85 / 3;

  /// The state, 12 pt #61666D, its middle 62.83 down; then a 2 tall line from the words' left to 12 from the edge at
  /// the cover's bottom: pink while downloading, #9499A0 otherwise, on #E3E5E7.
  static const stateText = 12.0;
  static const stateLine = 16.0;
  static const stateCentre = 377 / 6;
  static const progressHeight = 2.0;
  static Color get progressTrack => BiliColors.divider;
  static Color get progressActive => BiliColors.pink;
  static Color get progressIdle => BiliColors.secondaryText;

  /// UP and the name, then the size, 12 pt #9499A0, their middles 55.67 and 70.83 down; 大会员专享 · size in pink.
  /// UP is 历史记录's glyph in a 13.67 box 1 in, the name 3.33 after it.
  static const metaText = 12.0;
  static const metaLine = 16.0;
  static const upCentre = 167 / 3;
  static const sizeCentre = 425 / 6;
  static const metaInset = 1.0;
  static const upBox = 41 / 3;
  static const upGap = 10 / 3;
  static const upLift = 0.5;
  static Color get vip => BiliColors.pink;

  /// Between rows a 2/3 hairline from the cover's left to the screen's edge, halfway between the covers.
  static Color get divider => tone(0xFFEAEBED, 0xFF2F3134);
  static const dividerHeight = 2 / 3;

  /// On the cover: the length (or watched / length) 10 pt white in a 15.67 tall pill of black at 0.4, 4 in from the
  /// right and 4.33 up, 3.67 each side of the words; a watched line 2 tall at the bottom, pink on black at 0.6.
  static const pillText = 10.0;
  static const pillHeight = 47 / 3;
  static const pillPadX = 11 / 3;
  static const pillRight = 4.0;
  static const pillBottom = 13 / 3;
  static const pillRadius = 4.0;
  static const pillFill = Color(0x66000000);
  static const pillInk = BiliColors.onCover;
  static const watchedHeight = 2.0;
  static const watchedTrack = Color(0x99000000);
  static Color get watched => BiliColors.pink;

  /// A 合集's cover (155): the pill holds the stack, 10 × 9.17 of ink, and the count 5.67 after it.
  static const stackWidth = 10.0;
  static const stackHeight = 55 / 6;
  static const stackGap = 17 / 3;

  /// 正在缓存's stacked cover (143, 145): a #C9CCD0 card 7 above it, 6 in each side; the cover shaded by half and
  /// N个内容 12 pt white on its middle.
  static Color get stackCard => tone(0xFFC9CCD0, 0xFF46494D);
  static const stackCardRise = 7.0;
  static const stackCardInset = 6.0;
  static const queueShade = BiliColors.coverShade;
  static const queueCountText = 12.0;

  /// 已使用 / 剩余, 12 pt, its middle 19.67 above the home indicator's inset on 离线缓存 and 正在缓存, 22.67 on a
  /// 合集's page (156).
  static const footerText = 12.0;
  static const footerLine = 16.0;
  static const footerHeight = 40.0;
  static const footerCentre = 59 / 3;
  static const folderFooterCentre = 68 / 3;

  /// 正在缓存's strip (146): 56 tall. The pill 12 in and 12 down, 32 tall, #F6F7F8: ❚❚ or ▶ (#61666D) 14 in, 8 wide,
  /// then 14 pt words 6.33 after it and 11.33 before the end. 同时缓存数量：N 14 pt #9499A0, then ⌄ 8.67 × 4.67 with
  /// 1.2 strokes, 9.17 after the words and 13.67 from the edge.
  static const stripHeight = 56.0;
  static const pillTop = 12.0;
  static const pillLeft = 12.0;
  static const allHeight = 32.0;
  static Color get allFill => tone(0xFFF6F7F8, 0xFF1E2022);
  static const allPadLeft = 14.0;
  static const allPadRight = 34 / 3;
  static const allGlyphWidth = 8.0;
  static const allGlyphGap = 19 / 3;
  static const allText = 14.0;
  static Color get allGlyph => tone(0xFF61666D, 0xFFA2A7AE);
  static const pauseBar = 3.0;
  static const pauseHeight = 28 / 3;
  static const playHeight = 9.2;
  static const playRound = 1.2;
  static const countText = 14.0;
  static Color get countInk => BiliColors.secondaryText;
  static const chevronWidth = 26 / 3;
  static const chevronHeight = 14 / 3;
  static const chevronStroke = 1.2;
  static const chevronGap = 9.17;
  static const chevronRight = 41 / 3;

  /// Edit mode (149): the strip goes, rows slide 32 right for a 19.33 circle centred 24 in on the cover's middle, a
  /// 1 pt #61666D ring or pink with a white ✓. At the bottom, 全选 (its circle the same, 14 pt #484C52 from 44) and
  /// 删除 (14 pt #61666D, at half until something is chosen, ending 13 from the edge), their middle 26.08 above the
  /// home indicator's inset.
  static const editShift = 32.0;
  static const editMotion = Duration(milliseconds: 220);
  static const circle = 58 / 3;
  static const circleCentreX = 24.0;
  static const circleStroke = 1.0;
  static Color get circleRing => tone(0xFF61666D, 0xFFA2A7AE);
  static Color get circleChosen => BiliColors.pink;
  static const checkInk = BiliColors.onPink;
  static const checkStroke = 1.4;
  static const editBarHeight = 158 / 3;
  static const editBarCentre = 313 / 12;
  static const editText = 14.0;
  static const selectAllLeft = 44.0;
  static Color get selectAllInk => tone(0xFF484C53, 0xFFB9BDC2);
  static Color get deleteInk => tone(0xFF61666D, 0xFFA2A7AE);
  static const deleteOffOpacity = 0.5;
  static const deleteRight = 13.0;

  /// 确定要删除吗? (150): 280 wide with 8 corners, centred between the status bar and the home indicator's inset, over
  /// black at 0.6; the question 20 pt semibold, 3 above the middle of a 66.33 block, a 2/3 #E3E5E7 rule, 取消 and pink
  /// 确认 20 pt in a 44.33 row, each 4 further out than its half's middle.
  static const confirmWidth = 280.0;
  static const confirmRadius = 8.0;
  static Color get confirmFill => tone(0xFFFFFFFF, 0xFF242628);
  static const confirmDim = Color(0x99000000);
  static const confirmTitleText = 20.0;
  static const confirmTitleWeight = FontWeight.w600;
  static const confirmTitleHeight = 199 / 3;
  static const confirmTitleLift = 3.0;
  static const confirmRule = 2 / 3;
  static Color get confirmRuleInk => BiliColors.divider;
  static const confirmButtonHeight = 133 / 3;
  static const confirmButtonText = 20.0;
  static const confirmButtonSpread = 8.0;
  static Color get confirmCancel => BiliColors.text;
  static Color get confirmAction => BiliColors.pink;
  static Color get confirmPressed => BiliColors.pressedFill;
  static const confirmMotion = Duration(milliseconds: 200);

  /// 同时缓存数量's sheet (147): #F6F7F8 with 12 corners over black at 0.32; a 30 × 3 #C9CCD0 handle 8 down; a white
  /// card 16 in at 19 down with 8 corners, three 52 rows split by 0.5 #E3E5E7 rules 16 in; 14 pt words 16 in, the
  /// chosen pink; (大会员专享) 10 pt white in a 13 tall pink stadium 8.67 after the words, 4.33 each side; 20 under
  /// the card.
  static Color get sheet => tone(0xFFF6F7F8, 0xFF202123);
  static const sheetRadius = 12.0;
  static const sheetDim = Color(0x52000000);
  static const sheetMotion = Duration(milliseconds: 250);
  static const handleWidth = 30.0;
  static const handleHeight = 3.0;
  static const handleTop = 8.0;
  static Color get handle => tone(0xFFC9CCD0, 0xFF4D4D4F);
  static Color get card => tone(0xFFFFFFFF, 0xFF242628);
  static const cardTop = 19.0;
  static const cardInset = 16.0;
  static const cardRadius = 8.0;
  static const cardBottom = 20.0;
  static const optionRow = 52.0;
  static const optionText = 14.0;
  static Color get optionInk => BiliColors.text;
  static Color get optionChosen => BiliColors.pink;
  static const optionInset = 16.0;
  static const optionRule = 0.5;
  static Color get optionRuleInk => BiliColors.divider;
  static const badgeGap = 26 / 3;
  static const badgeHeight = 13.0;
  static const badgeText = 10.0;
  static const badgePadX = 13 / 3;
  static Color get badgeFill => BiliColors.pink;
  static const badgeInk = BiliColors.onPink;

  /// No screenshot: an empty page or search says so in 14 pt #9499A0, 120 under the bar.
  static const emptyText = 14.0;
  static const emptyTop = 120.0;
}

/// A cached video's page under the player (158-161), measured at 3 px per pt.
abstract final class OfflinePageTheme {
  /// 离线缓存 (N个视频) and 点我发弹幕 in a 42 pt band under the player with no hairline, the capsule 30 tall, border
  /// to border, its border one crisp pixel. Its top is 316.67 on 158, 7 under the phone's player, which ends on the
  /// pixel at 309.67; ours ends at 309.5, so the extra sixth keeps the border on a pixel.
  static const headerHeight = 42.0;
  static const capsuleCentre = 22 + 1 / 6;
  static const capsuleHeight = 30.0;
  static const capsuleBorder = 1 / 3;
  static const gutter = 12.0;

  /// 离线缓存 in black, bold, its ink centred 21.2 below the player; (N个视频) in the page's grey after it.
  static const titleText = 16.0;
  static const titleWeight = FontWeight.w600;
  static Color get titleInk => tone(0xFF000000, 0xFFFFFFFF);
  static const titleCentre = 21.17;
  static const countText = 12.0;
  static Color get countInk => BiliColors.secondaryText;
  static const countGap = 4.0;

  /// A row is 100: the 135 × 76 cover 12 down at the gutter, the text 8.5 right of it, a hairline between rows from
  /// the gutter to the right edge (none after the last).
  static const rowHeight = 100.0;
  static const rowPadTop = 12.0;
  static const coverWidth = 135.0;
  static const coverHeight = 76.0;
  static const coverRadius = 6.0;
  static const textGap = 8.5;
  static const hairline = 1 / 3;
  static Color get divider => BiliColors.divider;

  /// The title: 14 pt (158's pink and 160's black alike step 14 a glyph) in two lines 20 apart, its ink from 2 below the
  /// cover's top; the box ends at the gutter, which holds 160's 19 glyphs a line and not a 20th.
  static const rowTitleText = 14.0;
  static const rowTitleLine = 20.0;
  static const rowTitleTop = -4 / 3;
  static const titleRight = gutter;
  static Color get rowTitle => BiliColors.text;
  static Color get playing => BiliColors.pink;

  /// The playing bars before the title (158, 160): three round-ended 2 wide, 4.67 apart, the first centred 1.83 into
  /// the text box, standing on a line 1.33 above the baseline, 4 before the first glyph; they rise and fall while the
  /// video plays.
  static const barsLead = 5 / 6;
  static const barsLift = 4 / 3;
  static const barWidth = 2.0;
  static const barPitch = 14 / 3;
  static const barsWidth = barWidth + 2 * barPitch;
  static const barsHeight = 25 / 3;
  static const barsGap = 29 / 6;
  static const barMin = 3.0;
  static Color get barsInk => tone(0xFFFB7299, 0xFFD44E7D);
  static const barsCycle = Duration(milliseconds: 900);

  /// Heights at rest, as 160 caught them.
  static const barRest = <double>[6, 6, 25 / 3];

  /// The UP line and the size line, their ink centred 53 and 70 below the cover's top: UP and the name in the page's
  /// grey, the size grey or, for a 大会员 quality, 大会员专享 · size in pink.
  static const metaText = 12.0;
  static const metaLine = 16.0;
  static const upCentre = 53.0;
  static const sizeCentre = 70.0;
  static Color get meta => BiliColors.secondaryText;
  static Color get vip => BiliColors.pink;
  static const upBox = 41 / 3;
  static const upGap = 3.3;

  /// ⋮: 2 pt dots 4.33 apart, centred 20 from the right on the size line.
  static const moreCentreRight = 20.0;
  static const moreTarget = 44.0;

  /// The duration on the cover: a 15.33 tall pill of half black, 4 in from the cover's lower right.
  static const pillText = 10.5;
  static const pillHeight = 46 / 3;
  static const pillPadX = 2.0;
  static const pillRight = 4.0;
  static const pillBottom = 4.0;
  static const pillRadius = 2.0;
  static const pillFill = BiliColors.coverShade;
  static const pillInk = BiliColors.onCover;

  /// 仅展示本App中可查看的稿件, its ink centred 29 below the last row.
  static const footerText = 12.0;
  static const footerCentre = 29.0;
  static Color get footerInk => tone(0xFFC9CCD0, 0xFF46494D);
  static const footerBottom = 24.0;

  /// A row's ⋮ sheet (159): the page dimmed by half, a white 查看详情页 row 50 tall with the pink ▷ ring 22 in, a 5 pt
  /// grey band, 取消 55 tall, and the home indicator's inset in the band's grey.
  static const sheetDim = Color(0x80000000);
  static const sheetIn = Duration(milliseconds: 280);
  static const sheetOut = Duration(milliseconds: 220);
  static Color get sheetFill => tone(0xFFFFFFFF, 0xFF1E2022);
  static Color get sheetBand => BiliColors.pageGrey;
  static const sheetRowHeight = 50.0;
  static const sheetBandHeight = 5.0;
  static const sheetCancelHeight = 55.0;
  static const sheetIconLeft = 22.0;
  static const sheetIcon = 21.0;
  static const sheetIconStroke = 1.5;
  static Color get sheetIconInk => BiliColors.pink;
  static const sheetLabelLeft = 60.0;
  static const sheetLabelText = 14.0;
  static const sheetCancelText = 15.0;

  /// Centred in their rows, the labels' ink sits this much higher on 159.
  static const sheetLabelLift = 4 / 3;
  static const sheetCancelLift = 1.0;
  static Color get sheetInk => BiliColors.text;
}

/// What 设置's playback pages (170-174, 178, 179) and 设置's BTR 加速 row (50) add to [SettingsTheme], measured off
/// KaiC's screenshots at 3 px a pt. Their pages don't agree with each other: 首页推荐设置 (170) and the two pickers (178, 179) each have their own
/// insets, row heights and ✓.
abstract final class SettingsListTheme {
  /// A section's grey label and 178's note, 12 pt; a row's grey second line, 13 pt.
  static const labelText = 12.0;
  static Color get label => BiliColors.secondaryText;
  static const subtitleText = 13.0;
  static Color get subtitle => BiliColors.secondaryText;

  /// The box a placed line is centred in: taller than any line on these pages, so its middle is the line's.
  static const lineBand = 48.0;

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

  /// A 20 pt gap with no hairline: over 170's last section, and under 179's bar.
  static const plainGap = 20.0;

  /// The switch (172-174, and 设置's BTR 加速 row, 50): a 124 × 55 px pill ending 23 px from the screen's edge, its
  /// knob a white pill 73 px wide inset 4 px, at the end the switch is set to.
  static const switchWidth = 124 / 3;
  static const switchHeight = 55 / 3;
  static const switchKnobWidth = 73 / 3;
  static const switchBorder = 4 / 3;
  static const switchRight = 23 / 3;
  static Color get switchOn => BiliColors.pink;
  static Color get switchOff => tone(0xFFC5C5C7, 0xFF525357);
  static Color get switchKnob => tone(0xFFFFFFFF, 0xFFD7D9DB);

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

  /// 推送设置 (189, 190): 35 px of grey over its first section, where 设置's is 41. 接收通知总开关's [已开启] is set in
  /// the second line's grey 13 pt after the title, its '[' from 22 px past the title's end and its glyphs' middle
  /// 9.5 px below the title's; the gap and the drop are what put the stand-ins' 已开启 there.
  static const pushTop = 35 / 3;
  static const pushStateGap = 17 / 3;
  static const pushStateDrop = 3.0;

  /// White under a labelled group's last hairline: 189 and 190's groups each end 1 px lower than their rows add up
  /// to, 订阅/预约通知 2 (one is between its second and third rows; ours goes at the end), 关注通知, 其他通知 and the
  /// last none.
  static const pushGroupEnd = 1 / 3;
}

/// 深色设置 (249): its one switch row, 175 px over a 2 px hairline where the playback pages' are 176 over 1.
abstract final class DarkModeTheme {
  static const rowHeight = 175 / 3;
  static const rule = 2 / 3;
}

/// 首页's tab row (204): 直播 推荐 热门 动画 影视, 推荐 and 热门 side by side as pages. Filled by the tab row's builder.
abstract final class HomeTabRowTheme {
  static const tabCount = 5;

  /// The labels' centres 57 pt apart with 热门 on the screen's middle, as both indicators sit (01: 163, 204: 220); each
  /// slot takes taps across its pitch.
  static const pitch = 57.0;

  /// The chosen label is 16 pt semibold, the others 15 pt regular (推荐's ink 30.67 wide chosen, 29 not; 15 tall against
  /// 14), every label's box standing on the same bottom: their ink ends 1/3 pt lower than a shared baseline would put
  /// it. Every label is laid out at the chosen size and the others drawn scaled down about their bottom, so a label
  /// grows as its page slides in and the row keeps its height.
  static const restingScale = 15 / BiliMetrics.tabText;
  static const weight = FontWeight.w400;
  static const chosenWeight = FontWeight.w600;

  /// The others' grey on white (01's #61666D, the folded magnifier's); over a 装扮's picture the skin's colour at 68%,
  /// a little lighter than the magnifier's 72% (204: a black 热门 over the others' #464A44 on #D9E8D3, black at 0.677
  /// to 0.681 by channel).
  static Color get ink => HomeHeaderTheme.searchInk;
  static const skinInkOpacity = 0.68;

  /// A tap on 推荐 or 热门 slides the pages over in UIKit's ease-in-out (no recording of the official one).
  static const pageTurn = Duration(milliseconds: 300);
  static const pageCurve = Curves.easeInOut;
}

/// 首页's 热门 (204, 217). Filled by 热门's builder.
abstract final class HotListTheme {
  static Color get page => BiliColors.card;

  /// A row (204): 114.67 apart, the 167 × 94 cover 10 down and 12 in, and a 0.5 #E3E5E7 line across the whole page 10
  /// under the cover.
  static const rowHeight = 344 / 3;
  static const gutter = 12.0;
  static const coverTop = 10.0;
  static const coverWidth = 167.0;
  static const coverHeight = 94.0;
  static const coverRadius = 11 / 3;
  static Color get coverPlaceholder => tone(0xFFF1F2F3, 0xFF1E2022);
  static const hairlineTop = 114.0;
  static const hairline = 0.5;
  static Color get hairlineInk => BiliColors.divider;

  /// The title: 14 on 21.33 lines, two at most, its first line's ink centred 8.17 under the cover's top, its glyphs
  /// from 189.83 (the stand-ins' bearings put the box 0.67 before that); it wraps before 428.
  static const titleLeft = 189.17;
  static const titleRight = 12.0;
  static const titleTop = -2.6;
  static const titleText = 14.0;
  static const titleLine = 64 / 3;
  static Color get titleInk => BiliColors.text;

  /// The UP and ▷ lines: their 13.33 × 11.33 icons (the APK's, cut to their ink) from 190.33, centred 26.17 and 8.17
  /// above the cover's bottom, the 12 pt grey words' ink 3.67 after the icon.
  static const metaLeft = 571 / 3;
  static const metaIconWidth = 40 / 3;
  static const metaIconHeight = 34 / 3;
  static const metaIconGap = 3.3;
  static const metaText = 12.0;
  static const metaLine = 17.0;
  static Color get metaInk => BiliColors.secondaryText;
  static const upCentreAbove = 26.17;
  static const playsCentreAbove = 8.17;

  /// The UP line's name takes taps from this far above its words, down to half the gap to the ▷ line.
  static const uploaderSlopAbove = 6.0;

  /// ⋮ centred 20.17 from the right edge on the ▷ line (History's dots: 2 wide, 4.33 apart, #C9CCCF).
  static const moreCentreRight = 20.17;
  static const moreTarget = 32.0;

  /// The length on the cover: a 14 tall pill 4 in from its right and bottom, black at 38%.
  static const durationText = 10.0;
  static const durationHeight = 14.0;
  static const durationPadX = 8 / 3;
  static const durationRight = 4.0;
  static const durationBottom = 4.0;
  static const durationRadius = 3.0;
  static const durationFill = Color(0x61000000);
  static const durationInk = BiliColors.onCover;

  /// Rows this close to the end ask for the next page.
  static const loadAhead = rowHeight * 3;

  /// Under the rows: the next page's small spinner, the end or the failure with 重试; before the first page the TV,
  /// the failure or the empty list in the middle.
  static const footerPad = 16.0;
  static const footerLine = 20.0;
  static const spinnerRadius = 10.0;
  static const stateText = 14.0;
  static Color get stateInk => BiliColors.secondaryText;
  static const stateGap = 16.0;
  static const retryText = SearchResultTheme.retryText;
  static const retryHeight = SearchResultTheme.retryHeight;
  static const retryPadX = SearchResultTheme.retryPadX;
  static const retryRim = SearchResultTheme.retryRim;
  static const retryPressedScale = SearchResultTheme.followPressedScale;
  static const retryPressMotion = SearchResultTheme.followPressMotion;

  /// 首页's tap: back to the top, then the refresh's room held open there, as 推荐's.
  static const reloadScroll = HomeTabBarTheme.reloadScroll;
  static const reloadHeader = HomeTabBarTheme.reloadHeader;
  static const reloadCollapse = HomeTabBarTheme.reloadCollapse;

  /// ⋮'s share sheet (217): white with 12 corners over the page dimmed by half, 222 tall above the home indicator; all
  /// its words and glyphs #61666D.
  static const sheetDim = BiliColors.sheetDim;
  static Color get sheetFill => BiliColors.card;
  static const sheetRadius = 12.0;
  static const sheetHeight = 222.0;
  static const sheetIn = SearchResultTheme.sheetIn;
  static const sheetOut = SearchResultTheme.sheetOut;
  static Color get sheetInk => tone(0xFF61666D, 0xFFA2A7AE);

  /// 分享, 19 pt and heavy, 16 in, its ink centred 23.67 down; × (12 square, 1.33 strokes) centred 26.17 from the
  /// right edge on the same line.
  static const sheetTitleText = 19.0;
  static const sheetTitleLine = 26.6;
  static const sheetTitleWeight = FontWeight.w600;
  static const sheetTitleLeft = 16.0;
  static const sheetTitleCentre = 23.67;
  static const closeCentreRight = 26.17;
  static const closeSize = 12.0;
  static const closeStroke = 4 / 3;
  static const closeTarget = 44.0;

  /// The share targets, 66 apart from 12 in: 44 circles 47.33 down, their 12 pt names centred 37 under the circles'
  /// middle. The row runs off the right edge and scrolls sideways.
  static const targetsLeft = 12.0;
  static const targetWidth = 66.0;
  static const targetIcon = 44.0;
  static const targetIconTop = 47.33;
  static const targetLabelBelow = 37.0;
  static const targetText = 12.0;
  static const targetLine = 17.0;

  /// A 1 pt #E3E5E7 rule across the sheet 141.33 down, then 稍后再看's 44 box 154 down under the first target.
  static const ruleTop = 141.33;
  static const rule = 1.0;
  static Color get ruleInk => BiliColors.divider;
  static const laterTop = 154.0;

  /// The brand circles drawn in place of art the APK lacks, sampled on 217.
  /// The brands' own colours stay at night; only X's black circle turns white, its mark black.
  static const facebookFill = Color(0xFF0079F8);
  static Color get xFill => tone(0xFF000000, 0xFFFFFFFF);
  static Color get xMark => tone(0xFFFFFFFF, 0xFF000000);
  static const whatsAppFill = Color(0xFF32DA51);
  static const brandMark = Color(0xFFFFFFFF);
}

/// The bottom bar's 消息 (196, 211, 212) and the tab's badge (211). Filled by 消息's builder.
abstract final class MessageTabTheme {
  static Color get page => BiliColors.card;

  /// The header (196) as 关注's, but its 44 pt row whole under the 62 pt status bar (106 pt down): the 装扮's `head_bg`
  /// cut as 首页's top cuts it, or a white bar (no screenshot). 消息 centred on the row, 17 pt semibold; the APK's broom
  /// (`brush_clear_line`, its ink 18.67 wide) centred 68 in from the right and ⋮ (`more_vertical_fill`) 24 in, both
  /// in the title's ink (#000 over 196's 装扮).
  static const barRow = 44.0;
  static Color get bar => BiliColors.card;
  static const titleText = 17.0;
  static const titleWeight = FontWeight.w600;
  static Color get titleInk => BiliColors.text;

  /// 196's 消息 sits half a point under the row's middle.
  static const titleDrop = 0.5;
  static const broomCentreRight = 68.0;
  static const moreCentreRight = 24.0;
  static const buttonTarget = 40.0;

  /// Without a 装扮 the broom and ⋮ take the title's ink; dark (244) draws them grey, not in the title's white.
  static Color get buttonInk => tone(0xFF18191C, 0xFFA2A7AE);

  /// The three entries (196): 48 pt #F7F9F9 squares with 12 corners, their tops 20 under the header, centred 127.33
  /// apart about the screen's middle, each glyph in its colour centred in its square (the thumb 2/3 higher); the 13 pt
  /// labels' ink centred 13.83 under the squares, their line box a third of a point higher, as the sessions' lines.
  /// The list starts 101.67 under the header.
  static const entryTop = 20.0;
  static const entrySquare = 48.0;
  static const entryRadius = 12.0;
  static Color get entryFill => tone(0xFFF6F7F8, 0xFF1C1F20);
  static const entryPitch = 382 / 3;
  static const entryLabelText = 13.0;
  static const entryLabelLine = 18.0;
  static const entryLabelCentre = 27 / 2;
  static Color get entryLabelInk => BiliColors.text;
  static const entries = 305 / 3;

  /// 回复与@'s bubble and 收到喜欢's thumb are the APK's icon-font glyphs, cut at 3× to their ink widths; 新增粉丝's bust
  /// has no glyph there and is drawn, 21 × 24.67.
  static Color get replyInk => tone(0xFF45D9A7, 0xFF39A080);
  static Color get likeInk => tone(0xFFFF6699, 0xFFD44E7D);
  static const likeRise = 2 / 3;
  static const fansWidth = 21.0;
  static const fansHeight = 74 / 3;
  static Color get fansInk => tone(0xFF40C5F1, 0xFF006996);

  /// A session (196): 71 tall. The 40 pt face 15.67 in, centred; under a pendant frame the face shrinks to 36 and the
  /// frame is 1.75 times that. The name (16 pt, pink for 大会员) and the last message (13 pt grey, one line, cut 58
  /// short of the edge) start 71.33 in, their ink's middles 25.17 and 48.17 under the row's top; the date (10 pt grey)
  /// on the name's middle ends 16.67 from the edge. A 0.5 #E3E5E7 hairline closes the row from the text's left. The
  /// lines' boxes sit a third of a point higher, where the system font draws its ink.
  static const row = 71.0;
  static const face = 40.0;
  static const faceLeft = 47 / 3;
  static const pendantFace = 36.0;
  static const pendantScale = CommentRowTheme.pendantScale;
  static const textLeft = 214 / 3;
  static const nameText = 16.0;
  static const nameLine = 22.0;
  static const nameCentre = 149 / 6;
  static Color get name => BiliColors.text;
  static Color get vipName => BiliColors.pink;
  static const nameGap = 8.0;
  static const lastText = 13.0;
  static const lastLine = 18.0;
  static const lastCentre = 287 / 6;
  static const lastRight = 58.0;
  static Color get last => BiliColors.secondaryText;
  static const dateText = 10.0;
  static const dateLine = 14.0;
  static const dateRight = 50 / 3;
  static Color get date => BiliColors.secondaryText;
  static const hairline = 0.5;
  static Color get hairlineInk => BiliColors.divider;

  /// A face's badge (196): a 12 pt disc in a 1 pt white ring, the disc's edges on the face's right and bottom: the
  /// verify bolt (yellow a person, #40C5F1 an organisation), else 大会员's pink 大. Dark (244) keeps the discs and
  /// their white glyphs as they are; only the ring turns to the page.
  static const badge = 12.0;
  static const badgeRing = 1.0;
  static Color get badgeRim => tone(0xFFFFFFFF, 0xFF17181A);
  static Color get badgePerson => tone(0xFFFFCC00, 0xFFFFCC00);
  static Color get badgeOrganisation => tone(0xFF40C5F1, 0xFF40C5F1);
  static Color get vipFill => tone(0xFFFF6699, 0xFFFF6699);
  static const vipText = 8.0;
  static const vipWeight = FontWeight.w700;
  static const vipInk = BiliColors.onPink;

  /// A notice box's face (196): the pink disc with its white glyph. 服务通知's three squares and diamond (18 pt across)
  /// and 社区中心's bubbles (21.5 × 20.5) are drawn, traced on 196; 系统通知 and 创作助手, in no screenshot, are the
  /// APK's own faces as they are (`ic_im_system_notice`, `ic_im_up_assistant`, white on blue discs).
  static Color get boxFill => tone(0xFFFF6699, 0xFFFF6699);
  static const boxGlyph = BiliColors.onPink;

  /// The page's states (no screenshot): 关注's words and buttons, the empty picture of 我的好友 over them; the TV and
  /// the messages 96 under the entries.
  static const stateTop = 96.0;
  static const emptyPicture = FriendsTheme.emptyPicture;
  static const emptyGap = 12.0;
  static const reloadScroll = Duration(milliseconds: 300);
  static const reloadHeader = Duration(milliseconds: 200);
  static const reloadCollapse = Duration(milliseconds: 100);

  /// The count on a place of the bottom bar (211's 关注): white numbers, 10 pt regular, on a #E13C3C stadium 12 tall
  /// and 13.67 wide for one digit, in a 1 pt white ring; 99+ past 99. Over a 装扮's bar its middle is 44/3 right of
  /// the place's middle and 2.5/3 under the bar's top. The stock bar has no screenshot: there it sits on the glyph's
  /// top right corner, the same distance right and on the glyph's top. The entries and sessions draw the same count
  /// (no screenshot) with its middle on the square's corner and on the face's top right.
  static const count = 12.0;
  static const countRing = 1.0;
  static const countPadX = 3.75;
  static const countText = 10.0;
  static const countWeight = FontWeight.w400;
  static Color get countFill => tone(0xFFE23D3D, 0xFFD9615F);
  static const countInk = Color(0xFFFFFFFF);
  static Color get countRim => tone(0xFFFFFFFF, 0xFF17181A);
  static const countRight = 44 / 3;
  static const countDressedTop = 2.5 / 3;
  static const countStockTop = HomeTabBarTheme.iconCentre - TabIconTheme.size / 2;
  static const countFaceInset = 5.0;

  /// 一键已读's alert (211): 280 wide with 8 corners over black at 0.6, centred; 一键已读 20 pt semibold with its middle
  /// 30.33 down, the question 17 pt #61666D 58.67 down; a 2/3 #E3E5E7 rule 93 down; 取消 and pink 清除 20 pt in a 44
  /// row, each 4 further out than its half's middle.
  static const alertWidth = 280.0;
  static const alertRadius = 8.0;
  static const alertDim = Color(0x99000000);
  /// 255's at night: the dialog's #242628, lighter than the page's card.
  static Color get alertFill => BiliColors.dialog;
  static const alertTitleText = 20.0;
  static const alertTitleWeight = FontWeight.w600;
  static const alertTitleLine = 26.0;
  static const alertTitleCentre = 91 / 3;
  static Color get alertTitle => BiliColors.text;
  static const alertMessageText = 17.0;
  static const alertMessageLine = 22.0;
  static const alertMessageCentre = 176 / 3;
  static Color get alertMessage => tone(0xFF61666D, 0xFFA2A7AE);
  static const alertBody = 93.0;
  /// A title with no message (关注's 确认取消关注?, no reference: KaiC chose this alert over iOS's), centred in its body:
  /// its ink about 26 from the top and from the rule, a little more than 211's words leave (21 above, 27 below).
  static const alertTitleOnlyBody = 70.0;
  static const alertRule = 2 / 3;
  static Color get alertRuleInk => BiliColors.divider;
  static const alertButton = 44.0;
  static const alertButtonText = 20.0;
  static const alertSpread = 8.0;
  static Color get alertCancel => BiliColors.text;
  static Color get alertAction => BiliColors.pink;
  static Color get alertPressed => BiliColors.pressedFill;
  static const alertMotion = Duration(milliseconds: 200);
  static const alertStartScale = 1.1;

  /// ⋮'s sheet (212): #F6F7F8 with 12 corners over black at 0.32, its 30 × 3 #C5C6C6 grabber 8 down; a white card 16
  /// in at 19 down with square corners, eight 52 rows split by 0.5 #E3E5E7 rules from the words' left; the glyphs
  /// (#18191C, the APK's icon font where it has them, else drawn) centred 26 into the card, the 18 pt words and the
  /// rules from 60.33, the words' ink 0.92 under the row's middle; 24 under the card over the home indicator.
  static Color get sheetFill => tone(0xFFF6F7F8, 0xFF202123);
  static const sheetRadius = 12.0;
  static const sheetDim = Color(0x52000000);
  static const sheetIn = Duration(milliseconds: 280);
  static const sheetOut = Duration(milliseconds: 220);
  static const grabberTop = 8.0;
  static const grabberWidth = 30.0;
  static const grabberHeight = 3.0;
  static Color get grabberInk => tone(0xFFC5C6C6, 0xFF4D4D4F);
  static const cardTop = 19.0;
  static const cardInset = 16.0;
  static Color get card => tone(0xFFFFFFFF, 0xFF242628);
  static const cardBottom = 24.0;
  static const sheetRow = 52.0;
  static const sheetRule = 0.5;
  static Color get sheetRuleInk => BiliColors.divider;
  static const sheetGlyphCentre = 26.0;

  /// 212 has 防骚扰和互动人群设置's ink centred 1.5 right of the column and 应援团消息助手's 1 higher than its row's
  /// middle.
  static const sheetHarassmentShift = 1.5;
  static const sheetFanClubRise = 1.0;
  static const sheetTextLeft = 181 / 3 - cardInset;
  static const sheetTextDrop = 1.25;
  static const sheetText = 18.0;
  static Color get sheetInk => BiliColors.text;
  static const sheetPressed = Color(0x0A000000);

  /// A chat's swipe (259): the row slides 148 left over 置顶 on #BBBBC1 and 删除 on #FC2125, each 74 wide and the
  /// row's whole height (over its hairline), the 16 pt white word centred. No dark reference: neither fill is in the
  /// official palette, so both stay at night.
  static const actionWidth = 74.0;
  static const actionTopFill = Color(0xFFBBBBC1);
  static const actionDeleteFill = Color(0xFFFC2125);
  static const actionText = 16.0;
  static const actionLine = 22.0;
  static const actionInk = Color(0xFFFFFFFF);

  /// Let go past half open, or flung faster than this (pt/s), the row opens; flung back, it closes.
  static const swipeFling = 300.0;
  static const swipeSettle = Duration(milliseconds: 250);

  /// A pinned chat (262) on #F6F7F8 across the row; at night Ga0_s, the palette's value for the same grey on a card.
  static Color get pinnedFill => tone(0xFFF6F7F8, 0xFF1E2022);

  /// 261: past the last page, 我可是有底线的_(:3ゝ∠)_ in 12 pt #9499A0, centred, its ink 24.67 under the last row (the
  /// line box a third of a point higher), in a 56 pt foot.
  static const endText = 12.0;
  static const endLine = 17.0;
  static const endCentre = 73 / 3;
  static const endFoot = 56.0;
  static Color get endInk => BiliColors.secondaryText;
}

/// 回复与@, 收到喜欢 and 新增粉丝 (197-199, 213, 214). Filled by their builder.
abstract final class MessageFeedTheme {
  /// 回复与@'s and 收到喜欢's bar (197, 198), 我的关注's: 54 tall under the status bar in the 装扮's second-page colour,
  /// a 2/3 hairline under it; the title 20 pt semibold on the row's middle, ‹ and the gear in round glass discs whose
  /// middles are 42 in from either side. The gear is the APK's `vc_mine_login_settings`, 18.67 × 20.33 of ink.
  static const barRow = FollowingListTheme.barRow;
  static const barHairline = FollowingListTheme.barHairline;
  static Color get hairline => BiliColors.divider;
  static const titleText = 20.0;
  static const titleLine = 28.0;
  static const titleWeight = FontWeight.w600;
  static const buttonCentreX = FollowingListTheme.backCentreX;
  static const buttonTarget = FollowingListTheme.backTarget;
  static const gearWidth = 56 / 3;
  static const gearHeight = 61 / 3;
  static Color get gearInk => FollowingListTheme.backInk;

  /// 新增粉丝's bar (199): white and 44 tall, a 1/3 #E7E7E7 rule 2/3 above its bottom; 新增粉丝 18 pt medium, its
  /// line centred 23 under the status bar; a bare ‹ (9.33 × 18 of ink, 1.5 strokes) centred 23 in and the gear 24 from
  /// the right, both #18191C.
  static const plainBar = 44.0;
  static const plainRuleTop = 130 / 3;
  static const plainRule = 1 / 3;
  static Color get plainRuleInk => tone(0xFFE7E7E7, 0xFF2F3134);
  static const plainTitleText = 18.0;
  static const plainTitleLine = 25.0;
  static const plainTitleWeight = FontWeight.w500;
  static const plainCentre = 23.0;
  static const plainBackCentreX = 23.0;
  static const plainBackWidth = 28 / 3;
  static const plainBackHeight = 18.0;
  static const plainBackStroke = 1.5;
  static const plainGearRight = 24.0;
  static Color get plainInk => BiliColors.text;

  /// 全部 and @我 (197, 213): a 51 row closed by a 1/3 rule, the chips 28 tall and 11.33 down, 全部 42 wide from 12 in,
  /// @我 43 wide 8 after it, 5 corners. 13 pt words on the chip's middle: the chosen pink on #FFECF1, the other #61666D.
  static const chipRow = 51.0;
  static const chipRule = 1 / 3;
  static const chipTop = 34 / 3;
  static const chipHeight = 28.0;
  static const chipLeft = 12.0;
  static const chipGap = 8.0;
  static const chipAllWidth = 42.0;
  static const chipAtWidth = 43.0;
  static const chipRadius = 5.0;
  static const chipText = 13.0;
  static const chipLine = 18.0;
  static Color get chipInk => tone(0xFF61666D, 0xFFA2A7AE);
  static Color get chipChosenInk => BiliColors.pink;
  static Color get chipChosenFill => tone(0xFFFFECF1, 0xFF2F1A22);

  /// A reply (197). The face 40 at 12 in, 15.67 down. From 63 in, three lines: the name 13 pt semibold, the UP tag
  /// and the action 13 pt #61666D, 6 apart (4.33 after the tag), its middle 23.33 down; what they wrote 13 pt #61666D
  /// in up to two lines,
  /// the first's middle 43.5 down (a second makes the row 17 taller); then 25.17 under the last of those the date 12 pt
  /// grey, 13 after it 回复 and
  /// 点赞 (the APK's `ic_bubble_comment_line_v2` and `ic_vector_like`, 13.33 wide, 4 before their 12 pt grey words, the
  /// two 11 apart; a liked thumb `ic_vector_liked` pink). The words stop 64 short of the right. ⋮'s three 2 pt dots
  /// 4.33 apart, centred 66 from the right on the date's line. The row ends 24 under the date's middle with a 2/3
  /// rule the screen's width. With the UP tag (19 × 12, 2 corners, 9.5 pt UP, on the name's line) the three lines come
  /// 3.33 lower and the row is as much taller; the face stays.
  static const face = 40.0;
  static const faceLeft = 12.0;
  static const replyFaceTop = 47 / 3;
  static const textLeft = 63.0;
  static const textRight = 64.0;
  static const nameCentre = 70 / 3;
  static const nameText = 13.0;
  static const nameLine = 18.0;
  static const nameWeight = FontWeight.w600;
  static Color get name => BiliColors.text;
  static Color get actionInk => tone(0xFF61666D, 0xFFA2A7AE);
  static const nameGap = 6.0;
  static const upExtra = 10 / 3;
  static const upWidth = 19.0;
  static const upHeight = 12.0;
  static const upRadius = 2.0;
  static const upText = 9.5;
  static Color get upFill => BiliColors.pink;
  static const upInk = BiliColors.onPink;
  static const upGap = 13 / 3;
  static const bodyCentre = 87 / 2;
  static const bodyText = 13.0;
  static const bodyLine = 17.0;
  static Color get bodyInk => tone(0xFF61666D, 0xFFA2A7AE);
  static const bodyLines = 2;
  static const dateGap = 151 / 6;
  static const dateText = 12.0;
  static const dateLine = 17.0;
  static Color get dateInk => BiliColors.secondaryText;
  static const dateBox = 30.0;

  /// The date's and 回复's words sit 2/3 above the line's middle, where the glyphs and ⋮ are.
  static const dateLift = 2 / 3;
  static const actionsGap = 13.0;
  static const glyph = 40 / 3;
  static const replyGlyphHeight = 13.0;
  static const glyphGap = 4.0;
  static const actionGap = 11.0;
  static Color get likedInk => BiliColors.pink;
  static const moreRight = 66.0;
  static const moreDot = 2.0;
  static const moreSpacing = 13 / 3;
  static Color get moreInk => BiliColors.secondaryText;
  static const moreTarget = 44.0;
  static const rowBottom = 24.0;
  static const rowRule = 2 / 3;
  static Color get rowRuleInk => BiliColors.divider;

  /// The right column (197, 198): what was replied to or liked, 10 pt grey in up to three 12 pt lines, 41 wide ending
  /// 11.17 from the right (its words' ink from 388.33-388.67 to about 427 on both); on 回复与@ its top 17.67 down, on
  /// 收到喜欢 centred 1 above the row's middle. A picture where there are no words: no screenshot, so a 40 square with 4
  /// corners in the same place.
  static const sideWidth = 41.0;
  static const sideRight = 67 / 6;
  static const sideTop = 53 / 3;
  static const likeSideRise = 1.0;
  static const sideText = 10.0;
  static const sideLine = 12.0;
  static const sideLines = 3;
  static Color get sideInk => BiliColors.secondaryText;
  static const sidePicture = 40.0;
  static const sidePictureRadius = 4.0;

  /// A like (198): one face 40 at 12 in, 16 down; two as a pair of 30s, the older at 12 in and 15.33 down, the newer 8
  /// right of it and 8 lower over a 1.5 white ring. The names 13 pt semibold with a whole-width 13 pt grey 、 between,
  /// 3.33 after the first name and 1 before the second (the second's ink starts 18.33-18.67 after the first's ends on
  /// all three of 198's pairs; a name starting with a combining ゚ draws it over the 、's corner), and, 6 after, the
  /// rest 13 pt #61666D, the line's middle 22.83 down; the date's 48.67 down, and the row ends as a reply's.
  static const likeNameCentre = 137 / 6;
  static const likeCommaBefore = 10 / 3;
  static const likeCommaAfter = 1.0;
  static const likeFaceTop = 16.0;
  static const pairFace = 30.0;
  static const pairTop = 46 / 3;
  static const pairShift = 8.0;
  static const pairRing = 1.5;
  static const likeDateCentre = 146 / 3;

  /// An empty list: the APK's `ic_page_status_empty` (我的好友's) 140 square, then 这里还什么都没有呢～ 14 pt grey. 213's
  /// grey page has the picture 220 under the chips and the words' middle 154.33 under its top (收到喜欢's, with no
  /// screenshot, the same under the bar); 199's white page 140 under the bar and 149.83.
  static Color get emptyFill => BiliColors.pageGrey;
  static const emptyPicture = 140.0;
  static const emptyText = 14.0;
  static const emptyLine = 20.0;
  static Color get emptyInk => BiliColors.secondaryText;
  static const emptyTop = 220.0;
  static const emptyTextCentre = 463 / 3;
  static const fansEmptyTop = 140.0;
  static const fansEmptyTextCentre = 899 / 6;

  /// A row's ⋮ sheet (214), over a 50% dim on everything: #F6F7F8 with 8 corners, a 30 × 3 grabber 8 down, then 19
  /// down a white card 16 in from each side with 8 corners. 不再通知 and 删除 52 tall, a 1/3 rule between from 44 into
  /// the card; their glyphs centred 26 in (a drawn bell 15.33 × 16.67, the APK's `biligame_vector_trash_delete_line`
  /// 16.33 square) and the words 14 pt from 44 in. 12 under the card, then the home indicator's room.
  static const sheetDim = BiliColors.sheetDim;
  static Color get sheetFill => tone(0xFFF6F7F8, 0xFF202123);
  static const sheetRadius = 8.0;
  static const grabberTop = 8.0;
  static const grabberWidth = 30.0;
  static const grabberHeight = 3.0;
  static Color get grabberInk => tone(0xFFC9CCD0, 0xFF4D4D4F);
  static const cardTop = 19.0;
  static const cardInset = 16.0;
  static const cardRadius = 8.0;
  static Color get cardFill => tone(0xFFFFFFFF, 0xFF242628);
  static const cardBottom = 12.0;
  static const sheetRow = 52.0;
  static const sheetRule = 1 / 3;
  static Color get sheetRuleInk => BiliColors.divider;
  static const sheetGlyphCentre = 26.0;
  static const sheetTextLeft = 44.0;
  static const sheetText = 14.0;
  static const sheetLine = 20.0;
  static Color get sheetInk => BiliColors.text;
  static const bellWidth = 46 / 3;
  static const bellHeight = 50 / 3;
  static const bellStroke = 1.25;
  static const deleteGlyph = 49 / 3;
  static const sheetIn = Duration(milliseconds: 280);
  static const sheetOut = Duration(milliseconds: 220);

  /// The first load's failure and the account's state, the footer's spinner and 加载失败，点击重试 (我的关注's); the next
  /// page is asked within a screen of the end.
  static const footerPad = FollowingListTheme.footerPad;
  static const footerText = FollowingListTheme.footerText;
  static Color get footerInk => FollowingListTheme.footerInk;
  static const spinnerRadius = FollowingListTheme.spinnerRadius;

  static Color get page => BiliColors.card;
}

/// A chat and the notice boxes (200-203, 218, 219). Filled by the chats' builder.
abstract final class MessageChatTheme {
  /// 200-203 behind the bar and the list.
  static Color get page => BiliColors.softGrey;
  static Color get text => BiliColors.text;
  static Color get grey => BiliColors.secondaryText;

  /// A card's body and values, and the bar's glyphs.
  static Color get dim => tone(0xFF61666D, 0xFFA2A7AE);
  static Color get link => BiliColors.link;
  static Color get card => BiliColors.card;
  static Color get hairline => BiliColors.divider;

  /// The title row under the status bar: ‹ with 1.5 pt round strokes, its ink 19.33-28.67 × 18 pt (as 离线缓存's);
  /// the name 17 pt semibold, centred; the gear's ink 19.33 × 21.33 pt centred 24 pt from the right.
  static const barRow = 44.0;
  static const titleText = 17.0;
  static const titleWeight = FontWeight.w600;
  static const titleSide = 64.0;
  static const backTarget = 44.0;
  static const backTipX = 20.08;
  static const backEndX = 27.92;
  static const backHalfHeight = 8.25;
  static const backStroke = 1.5;
  static const gearWidth = 58 / 3;
  static const gearHeight = 64 / 3;
  static const gearCentreRight = 24.0;

  /// 202's bar: a white 46 pt card 12 pt in, 5 pt under the title row, split by a 1 × 24 pt rule. Each half centres
  /// its glyph and words: 不接受推送 14 pt over 通知正常接收 12 pt grey, 11 pt after the bell; 加关注 14 pt, 9 pt after
  /// its head.
  static const settingsMargin = 12.0;
  static const settingsTop = 5.0;
  static const settingsBottom = 5.0;
  static const settingsHeight = 46.0;
  static const settingsRadius = 10.0;
  static const settingsRule = 1.0;
  static const settingsRuleHeight = 24.0;

  /// Each half's glyph and words sit this much right of the half's middle.
  static const settingsNudge = 5 / 3;

  static const pushGlyphWidth = 46 / 3;
  static const pushGlyphHeight = 51 / 3;
  static const pushGap = 11.0;
  static const pushTitle = 14.0;
  static const pushSubtitle = 12.0;
  static const pushLine = 52 / 3;
  static const followGlyphWidth = 46 / 3;
  static const followGlyphHeight = 49 / 3;
  static const followGap = 9.0;
  static const followText = 14.0;

  /// The list: 14.67 pt from the bar to the first time line's box, rows 15 apart, cards 16, a time line's 17 pt box 22
  /// under the row before and 15 over the row after, and 9 pt under the last row. A tip's lines are 13.5 pt, which sets
  /// 202's tip 30.25 under its time line.
  static const listTop = 14.67;
  static const listBottom = 9.0;
  static const rowGap = 15.0;
  static const cardGap = 16.0;
  static const timeGap = 22.0;
  static const timeText = 12.0;
  static const timeLine = 17.0;
  static const tipText = 12.0;
  static const tipLine = 13.5;

  /// Older messages are asked for this far before the list's top shows, and load under a small spinner there.
  static const olderAhead = 200.0;
  static const olderRow = 44.0;

  /// A message: the face 40 pt, 12 pt from the screen's edge and 11 pt from the bubble. The bubble's 16 pt lines are
  /// 19 apart, 12 pt in, and wrap before 276; its corners are 10 pt but for the one by the face, 2.
  static const face = 40.0;
  static const side = 12.0;
  static const faceGap = 11.0;
  static const bubbleText = 16.0;
  static const bubbleLine = 19.0;
  static const bubblePadding = 12.0;
  static const bubbleTop = 8.5;
  static const bubbleBottom = 23 / 3;
  static const bubbleMaxText = 276.0;
  static const bubbleRadius = 10.0;
  static const bubbleNear = 2.0;
  static Color get theirs => BiliColors.card;
  static Color get yours => tone(0xFFBFEDFA, 0xFF082D40);

  /// Emotes 4/3 of the text's size, as in comments; 200's 网页链接 after the link's 12.67 pt chain, 1.6 pt either side
  /// and its top level with the words' ink.
  static const emote = bubbleText * 4 / 3;
  static const linkGlyph = 38 / 3;
  static const linkGlyphGap = 1.6;
  static const linkGlyphDrop = 17 / 6;

  /// 203's 此条消息为自动回复: 11 pt grey, under a 0.5 pt rule 10 pt below the text's ink, the bubble ending 29.67 pt
  /// under the rule.
  static const autoReplyGap = 7.5;
  static const autoReplyRule = 0.5;
  static Color get autoReplyRuleInk => tone(0xFFE7E8E8, 0xFF2F3134);
  static const autoReplyText = 11.0;
  static const autoReplyLine = 15.0;
  static const autoReplyBottom = 20 / 3;

  /// The account's face as 202 draws it: under a pendant the face is 32 pt in its 56 pt frame, and 大会员's 12 pt
  /// disc in a white ring 5/3 pt in from the face's right and 2 up from its bottom.
  static const pendantFace = 32.0;
  static const pendantFrame = 56.0;
  static const vipDisc = 12.0;
  static const vipRing = 2 / 3;
  static const vipRight = 5 / 3;
  static const vipBottom = 2.0;
  static Color get vipRingInk => tone(0xFFFFFFFF, 0xFF17181A);

  /// A picture message, fitted into 200 × 200 pt with the bubble's corners; one whose size the message doesn't give is
  /// a 120 pt square.
  static const pictureSide = 200.0;
  static const pictureUnsized = 120.0;
  static Color get pictureFill => BiliColors.pageGrey;

  /// 200 and 201's cards, 16 pt apart: 20 pt in, 10 pt corners, 12 pt inside. The 16 pt semibold title's ink 14.33 pt
  /// under the top; the body 13 pt dim, its ink 28.33 under the title's and its lines 19 apart; the fields 13 pt, 17
  /// under the body's ink and 27.67 apart, the value 12 pt after the label or 68.33 in; a 0.5 pt rule 16 under them,
  /// then each link row 40.67 pt with its 14 pt words and a 6 × 12 pt › 5 pt in from the right.
  static const cardMargin = 20.0;
  static const cardRadius = 10.0;
  static const cardInset = 12.0;
  static const cardTitle = 16.0;
  static const cardTitleWeight = FontWeight.w600;
  static const cardTitleLine = 22.0;
  static const cardTop = 32 / 3;
  static const cardBody = 13.0;
  static const cardBodyLine = 19.0;
  static const cardBodyGap = 20 / 3;
  static const cardFieldGap = 31 / 3;
  static const fieldPitch = 83 / 3;
  static const fieldLine = 19.0;
  static const fieldLabelWidth = 56.33;
  static const fieldValueGap = 12.0;
  static const cardRuleGap = 37 / 3;
  static const cardBottom = 13.0;
  static const cardRule = 0.5;
  static const linkRow = 122 / 3;
  static const linkText = 14.0;
  static const chevronWidth = 6.0;
  static const chevronHeight = 12.0;
  static const chevronRight = 5.0;
  static const chevronStroke = 1.1;

  /// The composer (202, 218): 52 pt over the home indicator or the keyboard, the field #F1F2F3 from 46 to 394, 36 pt
  /// tall in its middle, 14 pt words 12 pt in; the picture's and the face's 20 pt glyphs 14 pt from the edges.
  static const composerHeight = 52.0;
  static const fieldInset = 46.0;
  static const fieldHeight = 36.0;
  static Color get fieldFill => BiliColors.pageGrey;
  static const fieldPadding = 12.0;
  static const fieldTextTop = 7.5;
  static const fieldText = 14.0;
  static const fieldMaxLines = 4;
  static const toolInset = 14.0;
  static const toolWidth = 20.0;
  static const pictureGlyphHeight = 17.0;
  static const emoteGlyphHeight = 20.0;
  static const keyboardGlyphHeight = 17.0;
  static Color get keyboardInk => BiliColors.pink;

  /// The field's caret, 1 × 16.67 pt and square, on the line's middle (219).
  static Color get cursor => BiliColors.pink;
  static const caretWidth = 1.0;
  static const caretHeight = 50 / 3;

  /// 219's emote panel under the composer, 372 pt with the home indicator's strip: the page's grey, a 1/3 pt lighter
  /// line 1/3 under its top and a 30 × 3 pt grab handle 8.67 under it. Eight emotes of 30 pt to a row, centred 52 pt
  /// apart from 38 in, rows 48 pt apart from 47.67 under the top, with no headings. A package of large emotes or of
  /// 颜文字 (not in 219) is laid out as the comments' panel lays it.
  static const emotePanel = 372.0;
  static Color get panelFill => BiliColors.pageGrey;
  static const panelLineTop = 1 / 3;
  static const panelLine = 1 / 3;
  static Color get panelLineInk => tone(0xFFF6F7F8, 0xFF101011);
  static const handleTop = 26 / 3;
  static const handleWidth = 30.0;
  static const handleHeight = 3.0;
  static Color get handleInk => tone(0xFFC1C2C2, 0xFF4D4D4F);
  static const gridSide = 12.0;
  static const gridTop = 71 / 3;
  static const columns = 8;
  static const row = 48.0;
  static const emoteSide = 30.0;
  static const largeColumns = ComposerTheme.largeColumns;
  static const largeRow = ComposerTheme.largeRow;
  static const largeEmote = ComposerTheme.largeEmote;
  static const textColumns = ComposerTheme.textColumns;
  static const textRow = ComposerTheme.textRow;
  static const kaomojiText = ComposerTheme.kaomojiFont;
  static const kaomojiPad = ComposerTheme.kaomojiPad;
  static const panelSpinnerRadius = ComposerTheme.spinnerRadius;

  /// The panel's 44 pt white bar in 50 pt slots: ⚙ (19.33 pt tall), 🔍 and 🕒 (16.67) in [dim], the pink ★
  /// (18.67 × 18, its ink 2/3 above the slot's middle), then the packages' 28 pt icons or a 颜文字's first face in
  /// 9 pt grey; the slot shown is on [panelFill]. 🔍's NEW is a 29.33 × 14 pt pink tag 19.67 into its slot and 5 under
  /// the bar's top, its 10 pt white letters centred.
  static Color get bar => BiliColors.card;
  static const barHeight = 44.0;
  static const barSlot = 50.0;
  static Color get barSelected => panelFill;
  static const barGearWidth = 52 / 3;
  static const barGearHeight = 58 / 3;
  static const barGlyph = 50 / 3;
  static const barStarWidth = 56 / 3;
  static const barStarHeight = 18.0;
  static const barStarLift = 2 / 3;
  static Color get barStar => BiliColors.pink;
  static const packageIcon = ComposerTheme.tabIcon;
  static const kaomojiTabText = ComposerTheme.kaomojiTabFont;
  static const kaomojiTabPad = ComposerTheme.kaomojiTabPad;
  static Color get kaomojiTab => ComposerTheme.kaomojiTab;
  static const newLeft = 59 / 3;
  static const newTop = 5.0;
  static const newWidth = 88 / 3;
  static const newHeight = 14.0;
  static const newRadius = 2.0;
  static Color get newFill => BiliColors.pink;
  static const newInk = BiliColors.onPink;
  static const newText = 10.0;
}

/// 消息设置 and its pickers (188, 195, 215, 216). Filled by 消息设置's builder.
abstract final class MessageSettingsTheme {
  static Color get page => BiliColors.pageGrey;

  /// The bar, 44 under the status bar: the 装扮's second-page colour and text colour (KaiC's green, 188), else white
  /// with the page's text. Its title is 17 pt semibold, centred on the screen, its glyphs' middle 0.4 below the row's;
  /// ‹ as 离线缓存's: 1.5 strokes, its tip 20.08 in and its ends 27.92 in, 8.25 above and below the row's middle.
  static const barRow = 44.0;
  static Color get bar => BiliColors.card;
  static Color get barInk => BiliColors.text;
  static const barLightInk = Color(0xFFFFFFFF);
  static const titleText = 17.0;
  static const titleWeight = FontWeight.w600;
  static const titleLine = 24.0;
  static const titleDrop = 0.4;
  static const backTarget = 44.0;
  static const backTipX = 20.08;
  static const backEndX = 27.92;
  static const backHalfHeight = 8.25;
  static const backStroke = 1.5;

  /// 10 pt of grey over the first rows; a labelled group's 91 px, its 12 pt grey label 12 in with its middle 17
  /// down. No hairline at either edge of a group.
  static const top = 10.0;
  static const labelHeight = 91 / 3;
  static const labelCentre = 17.0;
  static const labelInset = 12.0;
  static const labelText = 12.0;
  static Color get label => BiliColors.secondaryText;

  /// Rows, white: 153 px, 206 with a 13 pt grey second line; titles 16 pt, both lines 16 in. The title's middle is
  /// 25.83 down, the second line's 45; the value and › sit 25.67 down a one-line row, the ✓ 25.5, and the value, ›
  /// and switch on a two-line row's middle.
  static Color get row => BiliColors.card;
  static const rowHeight = 51.0;
  static const tallHeight = 206 / 3;
  static const titleCentre = 25.83;
  static const subtitleCentre = 45.0;
  static const trailingCentre = 25.67;
  static const checkCentre = 25.5;
  static const rowInset = 16.0;
  static const rowTitleText = 16.0;
  static Color get rowTitle => BiliColors.text;
  static const subtitleText = 13.0;
  static Color get subtitle => BiliColors.secondaryText;

  /// Between two rows of a group, 2 px of the page's grey, the upper one a hairline from 12 in.
  static const rule = 2 / 3;
  static const hairline = 1 / 3;
  static const hairlineInset = 12.0;
  static Color get hairlineColor => BiliColors.divider;

  /// The value, 13 pt grey, its ink 7.33 before ›'s; › 20 × 35 px of ink, a little heavier than 设置's, ending 62 px
  /// from the edge.
  static const valueText = 13.0;
  static Color get value => BiliColors.secondaryText;
  static const valueGap = 7.0;
  static const chevronWidth = 20 / 3;
  static const chevronHeight = 35 / 3;
  static const chevronStroke = 0.95;
  static const chevronRight = 62 / 3;
  static Color get chevron => BiliColors.secondaryText;

  /// 188's switch: a 48 × 30 pill ending 16 from the edge, its knob a white 24 circle 3 inside it; pink on, and off
  /// the grey of 设置's (188 shows none off).
  static const switchWidth = 48.0;
  static const switchHeight = 30.0;
  static const switchKnob = 24.0;
  static const switchRight = 16.0;
  static Color get switchOn => BiliColors.pink;
  static Color get switchOff => SettingsListTheme.switchOff;
  static Color get switchKnobFill => tone(0xFFFFFFFF, 0xFFD7D9DB);
  static const switchMotion = SettingsTheme.switchMotion;

  /// A picker's chosen row (215, 216, 195): its words pink and semibold, the ✓ 12.67 × 8.33 of ink with a 1 pt
  /// stroke, ending 53 px from the edge.
  static Color get chosen => BiliColors.pink;
  static const chosenWeight = FontWeight.w600;
  static const checkEnd = 53 / 3;
  static const checkShort = 4.33;
  static const checkLong = 7.33;
  static const checkStroke = 1.0;
}

/// 首页's 直播 page (205) and 206.
abstract final class LiveTabTheme {
  static Color get page => BiliColors.pageGrey;
  static Color get card => BiliColors.card;
  static const radius = 4.0;
  static Color get coverPlaceholder => tone(0xFFF1F2F3, 0xFF1E2022);
  static Color get text => BiliColors.text;
  static Color get secondary => BiliColors.secondaryText;
  static const onCover = BiliColors.onCover;

  /// The carousel (205, 225): 5.33 under the header, each card 28 in from the screen's sides (384 on the phone), a
  /// 216 tall 16:9 video over a 38 band. Its neighbours peek 9.33 beyond it at 90%, scaled about their middles.
  static const carouselTop = 16 / 3;
  static const carouselSide = 28.0;
  static const carouselGap = 28 / 3;
  static const neighbourScale = 0.9;
  static const carouselBand = 38.0;
  static const carouselTurn = Duration(milliseconds: 300);

  /// The anchor over the video's top left: a 30 face in a 1 white ring 9 in and 8.67 down, the 12 pt white name 8.33
  /// after it.
  static const faceLeft = 9.0;
  static const faceTop = 26 / 3;
  static const face = 30.0;
  static const faceRing = 1.0;
  static const faceRingInk = Color(0xFFFFFFFF);
  static const nameGap = 25 / 3;
  static const nameText = 12.0;

  /// The name stops short of 直播中.
  static const anchorRight = 72.0;

  /// 直播中 at the top right, 8 in and 8.67 down: an 18 tall #FF6699 tag with 3 corners, the white bars (the APK's
  /// gif, its 16 square box) 4 in, then 10 pt words.
  static const liveTagRight = 8.0;
  static const liveTagTop = 26 / 3;
  static const liveTagHeight = 18.0;
  static const liveTagRadius = 3.0;
  static Color get liveTagFill => BiliColors.pink;
  static const liveTagText = 10.0;
  static const liveTagBarsLead = 4.0;
  static const liveTagBarsBox = 16.0;

  /// The bars' ink starts this far into their box.
  static const barsInk = 3.0;
  static const liveTagTextLead = 1.0;
  static const liveTagTrail = 5.0;

  /// 弹 and the speaker as 推荐's big card's, centred 69.33 and 21.17 from the video's right and 19.5 over its bottom.
  static const danmakuRight = 208 / 3;
  static const speakerRight = 63.5 / 3;
  static const buttonCentre = 19.5;
  static const buttonTarget = 40.0;
  static const speakerSize = 22.0;

  /// The band: the 14 pt title 10 in, its middle on the band's; 更多直播 / 查看榜单 a 72 × 24 stadium with a 1 #FF6699
  /// rim and 13 pt words, 10 from the right. With a rank, the chip (18 tall, 101 for 人气榜TOP·2: bold 12 pt #5B7086
  /// on #E2E7F0 in a 1/3 #A7BBD2 rim, laurels at both ends) then the 12 pt grey value 9 after it.
  static const bandInset = 10.0;
  static const titleText = 14.0;
  static const bandButtonWidth = 72.0;
  static const bandButtonHeight = 24.0;
  static const bandButtonRim = 1.0;
  static const bandButtonText = 13.0;
  static Color get bandButtonInk => BiliColors.pink;
  static const rankChipHeight = 18.0;
  static const rankChipRadius = 4.0;
  static const rankChipPad = 8.0;
  static Color get rankChipFill => tone(0xFFE2E7F0, 0xFF36393F);
  static Color get rankChipRim => tone(0xFFA7BBD2, 0xFF8C99AA);
  static Color get rankChipInk => tone(0xFF5B7086, 0xFFC8CED6);
  static const rankChipText = 12.0;
  static const rankLeaf = 4.0;
  static const rankValueGap = 9.0;
  static const rankValueText = 12.0;

  /// 我的关注 (205): a white box 5 under the carousel, 5 in, 139 tall with 4 corners. Its line: 我的关注 14 pt semibold 12
  /// in, ink centred 18.33 down; N in #FB7299 and 人正在直播 12 pt grey 5 after; the grey bars 7 after; 查看全部 12 pt
  /// grey and a 4.67 × 9 ›, 6 apart, 12 from the right.
  static const sectionGap = 5.0;
  static const sectionSide = 5.0;
  static const sectionInset = 12.0;
  static const sectionLineCentre = 55 / 3;
  static const sectionTitleText = 14.0;
  static const sectionTitleWeight = FontWeight.w600;
  static const sectionCountText = 12.0;
  static Color get sectionCount => tone(0xFFFB7299, 0xFFD44E7D);
  static const sectionCountGap = 5.0;
  static const sectionBarsGap = 7.0;
  static Color get sectionBars => tone(0xFF999999, 0xFF757A81);
  static const sectionAllText = 12.0;
  static const chevronWidth = 14 / 3;
  static const chevronHeight = 9.0;
  static const chevronStroke = 1.2;
  static const chevronGap = 6.0;
  static Color get chevronInk => tone(0xFF999999, 0xFF757A81);

  /// Its room: a box 39 down, 12 in, 88 tall under a 1/3 #E3E5E7 rim: the 156 wide cover at its left, a 36 face 18.33
  /// after the cover, then 12.33 on the 14 pt name over the 12 pt grey title.
  static const stripTop = 39.0;
  static const stripHeight = 88.0;
  static const stripBottom = 12.0;
  static const stripRim = 1 / 3;
  static Color get stripRimInk => BiliColors.divider;
  static const stripCoverWidth = 156.0;
  static const stripFace = 36.0;
  static const stripFaceLead = 55 / 3;
  static const stripTextLead = 37 / 3;
  static const stripNameText = 14.0;
  static const stripTitleText = 12.0;
  static const stripLineGap = 4.0;

  /// The area tabs: a 42 row, 14 pt words, the first 9.5 in and the rest 24.67 apart, 推荐 semibold in the page's ink,
  /// the others grey. From 336 the page's grey covers them at 85% to 95%, under the picture (16.33 tall at its own
  /// shape, 17 wide) and ⊞ (16) icons in #61666D, their centres 31 apart, the last's 25 from the right.
  static const areaRow = 42.0;
  static const areaText = 14.0;
  static const areaLead = 9.5;
  static const areaGap = 74 / 3;
  static const areaChosenWeight = FontWeight.w600;
  static const areaFadeFrom = 336.0;
  static const areaFadeEdge = 10.0;
  static const areaFadeNear = 0.85;
  static const areaFadeFar = 0.95;
  static Color get areaIconInk => tone(0xFF61666D, 0xFFA2A7AE);
  static const areaCoverIcon = 49 / 3;
  static const areaGridIcon = 16.0;
  static const areaGridRight = 25.0;
  static const areaIconPitch = 31.0;
  static const areaIconTarget = 30.0;
  static const areaReveal = Duration(milliseconds: 250);

  /// The two-column cards: 5 from the left, 5 apart and 6 from the right (212 wide on the phone), 4 corners; a 4:3
  /// cover over a 50 band. On the cover a tag at the top left, the corner picture 20 tall at the top right, and 13.33
  /// over its bottom the 10 pt 👁 (14 wide) and 👍 (13.33) counts 9 in, 5.67 after each icon, 10.67 between, the area 9
  /// from the right. In the band a 32 face 8 in and centred, the 14 pt title and the 12 pt name 44 in, ⋮ (#C4C4C4,
  /// 2.67 dots 3.33 apart) 10 from the right on the name's line.
  static const gridSide = 5.0;
  static const gridSideRight = 6.0;
  static const gridGap = 5.0;
  static const gridCoverAspect = 4 / 3;
  static const gridBand = 50.0;
  static const cornerHeight = 20.0;
  static const statCentre = 40 / 3;
  static const statLead = 9.0;
  static const statText = 10.0;
  static const statIconGap = 17 / 3;
  static const statGap = 32 / 3;
  static const statTrail = 9.0;
  static const watchedIcon = 14.0;
  static const likedIcon = 40 / 3;
  static const gridFace = 32.0;
  static const gridFaceLead = 8.0;
  static const gridTextLead = 44.0;
  static const gridTextTrail = 24.0;
  static const gridTitleText = 14.0;
  static const gridNameText = 12.0;
  static const gridLineGap = 3.0;
  static const moreRight = 10.0;
  static const moreDot = 8 / 3;
  static const morePitch = 10 / 3;
  static Color get moreInk => tone(0xFFC4C4C4, 0xFF46494D);
  static const moreTarget = 32.0;

  /// The shade under the cover's counts.
  static const shadeHeight = BiliMetrics.coverShadeHeight;

  /// The verify bolt: 12 on a 32 face (11.67 on 206's 36), its ring white, at the face's bottom right.
  static const gridBadge = 12.0;
  static const stripBadge = 38 / 3;
  static const badgeRing = 1.0;

  /// A cover's tag: 20 tall, 6 at its bottom right, the picture (24 × 21) poking 1 out of the cover's top left, the
  /// 12 pt white words 4 after it and 9 before the end, on the answer's colours or #FB7299 → #B0306A.
  static const tagHeight = 20.0;
  static const tagRadius = 6.0;
  static const tagIconWidth = 24.0;
  static const tagIconHeight = 21.0;
  static const tagText = 12.0;
  static const tagTextLead = 4.0;
  static const tagTextTrail = 9.0;
  static const tagFill = [Color(0xFFFB7299), Color(0xFFB0306A)];

  /// The following room's cover counts: 12 pt, the area 8.67 in, 👁 (16.33 wide) and its count 12 from the right.
  static const coverStatText = 12.0;
  static const coverStatLead = 26 / 3;
  static const coverStatTrail = 12.0;
  static const coverWatchedIcon = 49 / 3;
  static const coverStatCentre = 12.0;

  /// 206: the following bar's look, the 16 pt title and the 14 pt 全…注 20.67 from the right, ‹ (8.33 × 15.33, 1.5
  /// strokes) centred 22.33 in; then the cards straight under the bar, 5.33 in, 207.67 wide, the cover 129 over a
  /// 58.67 band: a 36 face 8.67 in and centred, the 14 pt name and the 12 pt grey title 52 in.
  static Color get followingPage => tone(0xFFF4F4F4, 0xFF0A0B0C);
  static const followingTitleText = 16.0;
  static const followingActionText = 14.0;
  static const followingActionRight = 62 / 3;
  static const followingBackCentre = 67 / 3;
  static const followingBackWidth = 25 / 3;
  static const followingBackHeight = 46 / 3;
  static const followingBackStroke = 1.5;
  static const followingBackTarget = 44.0;
  static const followingSide = 16 / 3;
  static const followingGap = 14.0;
  static const followingCoverAspect = 623 / 387;
  static const followingBand = 176 / 3;
  static const followingFace = 36.0;
  static const followingFaceLead = 26 / 3;
  static const followingTextLead = 52.0;

  /// Rows this close to the end ask for the next page; the footer and states as 热门's.
  static const loadAhead = 600.0;
  static const footerPad = 16.0;
  static const footerLine = 20.0;
  static const spinnerRadius = 10.0;
  static const stateText = 14.0;
  static const stateGap = 16.0;
  static const retryText = HotListTheme.retryText;
  static const retryHeight = HotListTheme.retryHeight;
  static const retryPadX = HotListTheme.retryPadX;
  static const retryRim = HotListTheme.retryRim;
  static const reloadScroll = HomeTabBarTheme.reloadScroll;
  static const reloadHeader = HomeTabBarTheme.reloadHeader;
  static const reloadCollapse = HomeTabBarTheme.reloadCollapse;

  /// A paused card's stream is loaded again on return after this, so it plays live rather than from where it stopped.
  static const resumeReloadAfter = Duration(seconds: 10);
}

/// A room's header, chat, bottom bar, 醒目留言 and sheets in portrait (207, 208, 221, 224, 228, 229), measured in
/// px / 3. Heights count from the safe area's top (62 on the Pro Max) unless they say otherwise.
///
/// The room is dark in both modes: 248 (深色模式) matches 207 to a level or two everywhere but the + capsule, so its
/// colours stay (关注 too, still #FF6699) and only [plusFill] takes the palette's night value.
abstract final class LiveRoomTheme {
  /// The official app draws each room's own picture behind the page; the room's answers carry none, so one dark tone
  /// stands in for 207's navy.
  static const page = Color(0xFF050A19);

  /// Every translucent box on the page (the header's capsules, the chips, the chat's rows and cards): white at 8%.
  static const glass = Color(0x14FFFFFF);
  static const ink = Color(0xFFFFFFFF);

  /// The chat's names without a colour of their own.
  static const nameBlue = Color(0xFFAEEBFF);

  /// ‹: its ink 8.67 wide and 14.67 tall from 16.33 on the capsule's middle, a 2 pt round stroke; the path is the ink
  /// less the stroke.
  static const backTipX = 52 / 3;
  static const backWidth = 20 / 3;
  static const backHeight = 38 / 3;
  static const backStroke = 2.0;
  static const backTarget = 37.0;

  /// The anchor capsule: 36 tall, 7 under the safe area, from 37.83; the face 30 across 3 in; the name and the 点赞 line
  /// from 6 after the face; 关注 26 × 40, 5 from the capsule's end.
  static const headerTop = 7.0;
  static const capsuleLeft = 113.5 / 3;
  static const capsuleHeight = 36.0;
  static const faceInset = 3.0;
  static const face = 30.0;
  static const nameGap = 6.0;
  static const nameText = 12.0;
  static const nameLine = 15.0;

  /// The name's line centred 6.33 above the capsule's middle, the 点赞 line's 8.83 below it.
  static const nameCentre = -6.33;
  static const likesText = 9.0;
  static const likesLine = 12.0;
  static const likesCentre = 53 / 6;
  static const likesInk = Color(0xE6FFFFFF);
  static const capsuleEnd = 5.0;

  /// Followed, 关注 goes and the capsule ends this far after the longer of the two lines (no screenshot shows it).
  static const capsuleEndBare = 12.0;
  static const nameMax = 112.0;
  static const followWidth = 40.0;
  static const followHeight = 26.0;

  /// 6 from the name's ink, less the glyph's own side.
  static const followGap = 5.5;
  static const followText = 12.0;
  static const pink = Color(0xFFFF6699);

  /// The verified disc on the face's lower right: 9.33 across in a 1 pt white ring.
  static const verifyDisc = 28 / 3;
  static const verifyRing = 1.0;
  static const verifyPerson = Color(0xFFFFC62E);
  static const verifyOrganisation = Color(0xFF3EA2F4);
  static const verifyRingInk = Color(0xFFFFFFFF);

  /// The three top faces: 23.67 across in a 1 pt ring (gold, silver, bronze), 18.67 apart, the first's left 327.33
  /// from the screen's left, the leftmost on top; the count capsule 22.67 tall under them, from the last face's middle
  /// to 12.17 from the right, its number 11 pt 4 after the last face's ink.
  static const topFace = 71 / 3;
  static const topFaceStep = 56 / 3;
  static const topFaceRing = 1.0;
  static const topFaceRings = [Color(0xFFFFD700), Color(0xFFC0C0C0), Color(0xFFCD7F32)];
  static const countHeight = 68 / 3;
  static const countRight = 36.5 / 3;
  static const countText = 11.0;
  static const countGap = 11 / 3;
  static const countPadRight = 8.5;

  /// The chips row: 21.67 tall, 52 under the safe area, from 11.83, 3.83 apart; 12 pt words 8.33 and 9 in from the
  /// ends. 更多直播 runs on to the screen's right edge, its › 5 × 9.33 ending 6.67 before it.
  static const chipsTop = 52.0;
  static const chipHeight = 65 / 3;
  static const chipLeft = 35.5 / 3;
  static const chipGap = 11.5 / 3;
  static const chipPadLeft = 25 / 3;
  static const chipPad = 9.0;
  static const moreRoomsEnd = 20 / 3;
  static const chipText = 12.0;
  static const chipChevronWidth = 5.0;
  static const chipChevronHeight = 28 / 3;
  static const chipChevronGap = 4.0;
  static const chipChevronStroke = 1.5;

  /// The player box: the screen's width at 16:9, 137.83 under the safe area (207: on the 440 pt screen it ends 1342 px
  /// down, under the 62 pt safe area, the header, the rank chips and the event row).
  static const boxTop = 413.5 / 3;

  /// 醒目留言's strip: 6.67 under the box, its pills 27.67 tall and 7.33 apart from 12; in each the face 23.67 across 2
  /// in, the battery 9 × 13 5 after it, the amount 13 pt 4 after that, 10 to the pill's end.
  static const stripGap = 20 / 3;
  static const stripHeight = 83 / 3;
  static const pillGap = 22 / 3;
  static const pillFace = 71 / 3;
  static const pillFaceInset = 2.0;
  static const pillBatteryWidth = 9.0;
  static const pillBatteryHeight = 13.0;
  static const pillBatteryGap = 5.0;
  static const pillAmountGap = 4.0;
  static const pillAmountText = 13.0;
  static const pillPadRight = 10.0;
  static const batteryInk = Color(0xFFFDE369);
  static const batteryBolt = Color(0xFFFFFFFF);

  /// What a pill's colour is darkened by where its time has run out.
  static const pillSpent = 0.47;
  static const superChatFallback = Color(0xFF2A60B2);
  static const superChatHeaderFallback = Color(0xFFEDF5FF);

  /// The chat: from the box (or the strip) down to 15 above the bottom bar, 12 to 330 across; a 40 pt fade at its top.
  static const chatLeft = 12.0;
  static const chatRight = 330.0;
  static const chatBottomGap = 15.0;
  static const chatFade = 40.0;
  static const rowGap = 10 / 3;

  /// A row: a capsule at least 24.67 tall (rows 28 apart), 14 pt words on 20 pt lines 6.33 in, the chips 16 (荣耀) and
  /// 15 (medal) tall, 3.67 apart, the name 4.67 after them.
  static const rowMinHeight = 74 / 3;
  static const rowPadX = 19 / 3;
  static const rowText = 14.0;
  static const rowLine = 20.0;
  static const rowChipGap = 11 / 3;
  static const rowNameGap = 14 / 3;
  static const tipInk = Color(0xFFF394AE);
  static const emoteInline = 20.0;
  static const emoteBig = 56.0;

  /// 系统提示's card: 14 pt on 18 pt lines, 2.83 above and below, 12.67 corners (iOS squeezes its full-width
  /// punctuation, so its lines hold a character more than ours); the room card (77.67 tall in 207) its title 14 pt on
  /// an 18.33 line 3.33 under its top, its announcement 12 pt on 18 pt lines and the live time 12 pt on 16, 5 above
  /// the bottom.
  static const cardRadius = 38 / 3;
  static const cardPadY = 2.83;
  static const cardLine = 18.0;
  static const roomPadTop = 10 / 3;
  static const roomTitleLine = 55 / 3;
  static const roomTextSize = 12.0;
  static const roomTimeLine = 16.0;
  static const roomPadBottom = 5.0;
  static const roomTimeInk = Color(0xFFCCCCCC);

  /// A 醒目留言 row (228): a 1 pt border, 6 pt corners, the header band 24 with the medal 8 in and the 电池 5.33 from
  /// the end, the message band 14 pt on a 25.67 band 10 in.
  static const scRowBorder = 1.0;
  static const scRowRadius = 6.0;
  static const scRowHeader = 24.0;
  static const scRowBody = 77 / 3;
  static const scRowHeaderPad = 8.0;
  static const scRowPriceRight = 16 / 3;
  static const scRowBodyPad = 10.0;
  static const scHeaderInk = Color(0xFF333333);

  /// The card over the chat (228): 8 in from both sides, 14 under the strip, its 1 pt border opaque; the header band
  /// 49.67 with the framed face's middle 25.83 in and 26.17 down (the face 27 across), the name 14 pt centred 15.67 down
  /// and 58.33 from the screen's left, the price 37.17 down; ⋮ (three 3.33 dots 5.67 apart, #757575) centred 15 down
  /// 11.33 from the end; the message band 26 tall, 14 pt 10.67 in.
  static const cardSide = 8.0;
  static const cardBelowStrip = 14.0;
  static const cardHeader = 149 / 3;
  static const cardBody = 26.0;
  static const cardCorner = 8.0;
  static const cardFaceX = 25.83;
  static const cardFaceY = 26.17;
  static const cardFace = 27.0;
  static const cardNameX = 175 / 3;
  static const cardNameCentre = 15.67;
  static const cardPriceCentre = 223 / 6;
  static const cardMore = 24.0;
  static const cardMoreCentre = 15.0;
  static const cardMoreRight = 34 / 3;
  static const cardMoreDot = 10 / 3;
  static const cardMoreStep = 17 / 3;
  static const cardMoreInk = Color(0xFF757575);
  static const cardBodyPad = 32 / 3;

  /// The card's bands and the chat's 醒目留言 rows let 20% of what is under them through (228: the body's orange reads
  /// 0.8 of the strip's over the dimmed chat, and the header lets the chat's words through as much).
  static const cardAlpha = 0.8;

  /// The page under the card, and the card under 229's sheet: black at 50%.
  static const dim = Color(0x80000000);

  /// 229: rows 48 tall from the sheet's top (12 pt grey 管理本条醒目留言, 14 pt 举报) 20.67 in, an 8 pt band, then
  /// 取消 16 pt centred in 56 over the home indicator.
  static const actionFill = Color(0xFF1F2022);
  static const actionBand = Color(0xFF0F1011);
  static const actionRow = 48.0;
  static const actionBandHeight = 8.0;
  static const actionCancel = 56.0;
  static const actionLeft = 62 / 3;
  static const actionRadius = 12.0;
  static const actionManageText = 12.0;
  static const actionManageInk = Color(0xFF999999);
  static const actionText = 14.0;
  static const actionCancelText = 16.0;

  /// The bottom bar (207, 224): 36 tall, its bottom on the home indicator's inset; ⋯ 36 across from 12 (three 4 pt
  /// dots 7.83 apart); the input from 56 to 330, 弹幕支持下～ 14 pt 10.67 in, the emote face 24 across 7 from its end;
  /// the gift's 36 circle at 337, its art filling it (the box 22.67 wide), the 6 pt dot from 367 and 2 down; the +
  /// capsule 48 wide to 12 from the right, the face 28 across 4 in, the + 9.33 of ink centred 36 in.
  static const barHeight = 36.0;
  static const barLeft = 12.0;
  static const barCircle = 36.0;
  static const barCircleFill = Color(0x24FFFFFF);
  static const barDot = 4.0;
  static const barDotStep = 23.5 / 3;
  static const inputLeft = 56.0;
  static const inputRight = 330.0;
  static const inputFill = Color(0x38FFFFFF);
  static const inputText = 14.0;
  static const inputPad = 32 / 3;
  static const inputInk = Color(0xFFFFFFFF);
  static const emoteFace = 24.0;
  static const emoteFaceFill = Color(0xFFC4C5C8);
  static const emoteFaceInk = Color(0xFF393D43);
  static const emoteFaceEnd = 7.0;
  static const giftLeft = 337.0;
  static const giftArt = 36.0;
  static const giftDot = 6.0;
  static const giftDotTop = 2.0;
  static const giftDotInk = Color(0xFFFA5A57);
  static const plusRight = 12.0;
  static const plusWidth = 48.0;
  static Color get plusFill => tone(0xFFE84B85, 0xFFDC6D94);
  static const plusFace = 28.0;
  static const plusFaceInset = 4.0;
  static const plusCentre = 36.0;
  static const plusArm = 23 / 3;
  static const plusStroke = 5 / 3;

  /// 221: from 662 on the screen to the bottom; 分享 14 pt centred 20.17 down 12.67 in; the targets in 64 wide slots from
  /// 12, their 44 circles centred 63.67 down and their 12 pt names 102 down; a 1 pt #333 line 130 down; the settings'
  /// circles centred 172.67 down, names 210 down.
  static const sheetFill = Color(0xFF110F1A);
  static const sheetTitleText = 14.0;
  static const sheetTitleCentre = 20.17;
  static const sheetTitleLeft = 12.67;
  static const sheetSlot = 64.0;
  static const sheetSlotsLeft = 12.0;
  static const sheetCircle = 44.0;
  static const sheetShareCentre = 63.67;
  static const sheetShareLabel = 102.0;
  static const sheetRuleTop = 130.0;
  static const sheetRule = 1.0;
  static const sheetRuleInk = Color(0xFF333333);
  static const sheetMoreCentre = 172.67;
  static const sheetMoreLabel = 210.0;
  static const sheetLabelText = 12.0;
  static const sheetLabelLine = 16.0;
  static const sheetLabelInk = Color(0xFFE6E6E6);
  static const sheetMoreFill = Color(0xFF323232);
  static const sheetHeight = 294.0;
  static const sheetDotInk = Color(0xFFFF4D4F);
  static const sheetDot = 6.0;

  /// 助TA必火's flame is the APK's 48 px art drawn 28.67 across (its ink 20.67 × 24.67); 消费管理's and 色觉优化's
  /// line icons are drawn on 26 (the shield's ink 19.33 × 23.33).
  static const boostIcon = 86 / 3;
  static const lineIcon = 26.0;
  static const glyphStroke = 1.6;

  /// 荣耀等级's chip (207, 208, 230): 36 × 16 whatever the level, the badge 6 in and centred down, the level bold 10.5
  /// centred 25 in. A badge per ten levels (208's 4-7, 12-17, 25, 31; 230's 24-29 and 36): the plain V, a diamond
  /// over it, the V winged, a star over it; each 10 wide but the plain one, at the heights below.
  static const wealthWidth = 36.0;
  static const wealthHeight = 16.0;
  static const wealthPadLeft = 6.0;
  static const wealthTextCentre = 25.0;
  static const wealthBadgeWidths = [26 / 3, 10.0, 10.0, 10.0];
  static const wealthBadgeHeights = [8.0, 29 / 3, 28 / 3, 11.0];
  static const wealthText = 10.5;

  /// On the chat's dark: 1-10, 11-30 and from 31 (208); on 高能榜's white sheet (230, 232) one pale blue.
  static const wealthFills = [Color(0xFF3F547B), Color(0xFF3A5387), Color(0xFF35508F)];
  static const wealthLightFill = Color(0xFF97B2E3);
  static const wealthVTop = Color(0xFFE2F0FF);
  static const wealthVBottom = Color(0xFF9DB8EC);
  static const wealthVShade = Color(0xFF7FA0E0);

  /// A medal chip: 15 tall, 9 pt bold words 4.33 / 3.67 from its ends, the level 2 after the name; the guard's anchor
  /// 17 across over its left end.
  static const medalHeight = 15.0;
  static const medalText = 9.0;
  static const medalPadLeft = 13 / 3;
  static const medalPadRight = 11 / 3;
  static const medalLevelGap = 2.0;
  static const medalFill = Color(0xFF2E759E);
  static const medalUnlit = Color(0xFF8C8C8C);
  static const medalGuard = 17.0;

  /// A guard frame's hole is 0.7 of the frame's width (the APK's 200 px frames, 140 px hole).
  static const guardFrameScale = 1 / 0.7;

  /// A frame from the server, drawn around the face.
  static const serverFrameScale = 1.4;
}

/// The live player's box and full screen (209, 210, 222), measured in px / 3 off KaiC's iPhone.
abstract final class LivePlayerTheme {
  /// 弹 and the full-screen button at the box's bottom right (207, 208): 32 pt discs of grey over the picture, their
  /// 20 pt icons centred; the full-screen one 8.33 from the right edge, 弹 16.33 before it, both 8 above the bottom.
  static const boxButton = 32.0;
  static const boxButtonFill = Color(0x6B525252);
  static const boxButtonIcon = 20.0;
  static const boxButtonRight = 25 / 3;
  static const boxButtonBottom = 8.0;
  static const boxButtonGap = 49 / 3;

  /// 208's 已开启弹幕: 8.67 under the box, centred, 42.67 tall on the toast's black.
  static const boxToastTop = 26 / 3;
  static const boxToastHeight = 128 / 3;
  static const boxToastInset = 44 / 3;
  static const boxToastRadius = 6.0;
  static const boxToastText = 15.0;
  static const toastFill = BiliColors.toastFill;

  /// 210's notes at full screen's bottom left: 切换中，请稍候 over 已成功切换至…, each 36 tall on 70% black, 4.33 apart,
  /// the last one 79.33 above the bottom edge, 10 inside the safe area.
  static const noteLeft = 10.0;
  static const noteBottom = 238 / 3;
  static const noteHeight = 36.0;
  static const noteGap = 13 / 3;
  static const noteInset = 10.0;
  static const noteRadius = 4.0;
  static const noteText = 14.0;
  static const noteFill = Color(0xB3000000);
  static const noteShown = Duration(seconds: 3);

  /// 209: the top row's middle 45 down; ‹ 9 × 14.67 centred 20.83 inside the safe area.
  static const topRowCentre = 45.0;
  static const backCentre = 62.5 / 3;
  static const backWidth = 9.0;
  static const backHeight = 44 / 3;

  /// The anchor's capsule: 36 tall from 38 inside the safe area, the face 30 inset 3, the name 11.67 and 点赞 9.33
  /// after a 6.33 gap, their middles 13 and 27.67 down the capsule, the pink 关注 40 × 26 6 after the longer of
  /// them and 5 from the capsule's end, its words 12 pt and 1.83 below the pill's middle.
  static const anchorLeft = 38.0;
  static const anchorHeight = 36.0;
  static const anchorFace = 30.0;
  static const anchorFaceInset = 3.0;
  static const anchorTextGap = 19 / 3;
  static const anchorName = 35 / 3;
  static const anchorLikes = 28 / 3;
  static const anchorNameCentre = 13.0;
  static const anchorLikesCentre = 83 / 3;
  static const followGap = 6.0;
  static const followWidth = 40.0;
  static const followHeight = 26.0;
  static const followText = 12.0;
  static const followTextDrop = 11 / 6;
  static const followEnd = 5.0;

  /// The capsules, chips and discs over the picture: dark grey at 60%, read off 235 (about 50 over the black edge, a
  /// third of the way down from the video behind). White tints vanished over a bright picture.
  static const capsuleFill = Color(0x99404040);

  /// While the controls show, black shades the top and bottom edges: 72% at the top fading out 170 pt down, 70% at
  /// the bottom fading out 130 pt up (KaiC's pair of one stream with the controls and without, its HUD measured).
  static const topShade = 170.0;
  static const topShadeInk = Color(0xB8000000);
  static const bottomShade = 130.0;
  static const bottomShadeInk = Color(0xB3000000);

  /// The 在线榜's three faces 23.33 across, each 20 after the one before and over the next, ringed 1 pt in gold, silver
  /// and bronze; the count after them on a capsule that starts under the last face, 11 pt.
  static const rankFace = 70 / 3;
  static const rankFaceStep = 20.0;
  static const rankFaceRing = 1.0;
  static const rankFaceRings = [Color(0xFFF8D848), Color(0xFFC9D2DA), Color(0xFFC28242)];
  static const countHeight = 24.0;
  static const countLead = 4.33;
  static const countTrail = 10.0;
  static const countText = 11.0;

  /// The count's capsule ends 95.67 inside the safe area's right edge.
  static const countRight = 287 / 3;

  /// The right end of the top row: ↗ centred 66 and ⋮ 24 inside the safe area, both on 44 targets; ⋮'s dots 3.17
  /// across, 6.5 apart.
  static const shareCentre = 66.0;
  static const shareIcon = 24.0;
  static const moreCentre = 24.0;
  static const moreDot = 19 / 6;
  static const moreDotGap = 10 / 3;

  /// The rank chips under the anchor and 更多直播 › on the right: 24 tall about 76 down, 12 pt words padded 8.33,
  /// the chips 4.67 apart from 12.33 inside the safe area.
  static const chipCentre = 76.0;
  static const chipHeight = 24.0;
  static const chipLeft = 37 / 3;
  static const chipInset = 25 / 3;
  static const chipGap = 14 / 3;
  static const chipText = 12.0;
  static const moreLiveChevronWidth = 4.0;
  static const moreLiveChevronHeight = 8.0;
  static const moreLiveChevronGap = 6.0;

  /// The anchor's name and 点赞 give way past this width; a followed room's capsule ends 12.67 after them.
  static const anchorTextMax = 160.0;
  static const anchorFollowedEnd = 38 / 3;

  /// The 🔓 on the left: a 36.67 square, corners 8, centred 18.67 inside the safe area at mid-height, 22 over the
  /// black edge (235).
  static const lockBox = 110 / 3;
  static const lockRadius = 8.0;
  static const lockCentre = 56 / 3;
  static const lockFill = Color(0x66383838);

  /// The bottom row 385 down (55 above the bottom edge): ⏸ ⟳ 弹 at 24 pt centred 24, 71.67 and 120.33 inside the safe
  /// area, the quality's 13.67 pt name from 157.33, then 209's last icon (the APK's watch_movies) centred 233.5.
  static const bottomRowCentre = 55.0;
  static const bottomIcon = 24.0;
  static const playCentre = 24.0;
  static const refreshCentre = 215 / 3;
  static const danmakuCentre = 361 / 3;
  static const qualityLeft = 472 / 3;
  static const qualityText = 41 / 3;
  static const watchCentre = 233.5;

  /// 235, 弹 on: 弹幕设置 (24 pt) 48 after 弹, the quality and the last icon 48 further on; over the quality's end a
  /// 22.67 × 11.67 原画 badge, its middle 18 above the row's, a 0.67 pt line of 60% white round 7.5 pt words.
  static const danmakuOnShift = 48.0;
  static const badgeWidth = 68 / 3;
  static const badgeHeight = 35 / 3;
  static const badgeRise = 18.0;
  static const badgeLine = 2 / 3;
  static const badgeLineInk = Color(0x99FFFFFF);
  static const badgeText = 7.5;

  /// 235's 弹幕 capsule, 弹 on: 36 tall from 321.67 inside the safe area's left to 147.33 inside its right, on the
  /// capsules' fill; the input's 译 (white) 18 × 20 from 13.67 in, a 1 × 14 line of 30% white 10.33 after it, 14 pt
  /// 80% white 弹幕支持下～ 8.67 after that; the wink face 24 across, 6.67 from the end.
  static const sendLeft = 965 / 3;
  static const sendRight = 442 / 3;
  static const sendHeight = 36.0;
  static const sendTranslateLeft = 41 / 3;
  static const sendDividerGap = 31 / 3;
  static const sendDivider = 1.0;
  static const sendDividerHeight = 14.0;
  static const sendDividerInk = Color(0x4DFFFFFF);
  static const sendTextGap = 26 / 3;
  static const sendText = 14.0;
  static const sendInk = Color(0xCCFFFFFF);
  static const sendFace = 24.0;
  static const sendFaceEnd = 20 / 3;

  /// 人气 before the gift, 弹 on: a disc as the gift's, centred 43 before it, its sticker 21.67 × 18 (drawn: neither the
  /// APK nor PiliPlus has it) a pink tile tilted back, white words on it.
  static const popularityStep = 43.0;
  static const popularityWidth = 65 / 3;
  static const popularityHeight = 18.0;
  static const popularityTilt = -0.14;
  static const popularityTop = Color(0xFFFFC2D4);
  static const popularityBottom = Color(0xFFF2648F);
  static const popularityEdge = Color(0xFFE24C7A);
  static const popularityText = 10.0;

  /// The gift and the anchor's pink + at the bottom right, their middles 55.33 above the bottom edge: the gift's 35.67
  /// pt disc centred 74.17 inside the safe area's right edge, its art 22.67 wide (the APK's 108 px picture drawn 36
  /// across) and portrait's red dot, 6 across, at its top right; the + capsule 48 × 35.67 ending at the edge, the face
  /// 24 inset 4, the + 9.33 across in 1.33 strokes centred 12 from the end.
  static const giftDisc = 107 / 3;
  static const giftIcon = 36.0;
  static const giftCentre = 445 / 6;
  static const giftRowCentre = 166 / 3;
  static const giftFill = capsuleFill;
  static const giftDot = 6.0;
  static const giftDotTop = 5 / 3;
  static Color get giftDotInk => LiveRoomTheme.giftDotInk;
  static const plusWidth = 48.0;
  static const plusHeight = 107 / 3;
  static Color get plusFill => LiveRoomTheme.plusFill;
  static const plusFace = 24.0;
  static const plusFaceInset = 4.0;
  static const plusStroke = 4 / 3;
  static const plusArm = 4.0;
  static const plusCentreFromEnd = 12.0;

  /// The controls show at first and on a tap, and hide 5 s after the last touch.
  static const chromeHide = Duration(seconds: 5);
  static const chromeFade = Duration(milliseconds: 220);

  /// A picture over the dimmed cover for 直播已结束 and the retry.
  static const endedDim = Color(0x99000000);
  static const endedText = 15.0;
  static const retryText = 14.0;
  static const retryWidth = 88.0;
  static const retryHeight = 32.0;

  /// 210, 222 and 232: a panel on the right 375 wide; the picture shrinks into the room left of it, from 34 to 6 short
  /// of the panel, centred down the screen.
  static const sideWidth = 375.0;
  static const sidePictureLeft = 34.0;
  static const sidePictureGap = 6.0;
  static const sideSlide = Duration(milliseconds: 250);

  /// 210: #202123 with 画质增强 14 pt 40 down, its grey note, the switch 42 × 18.67 ending 20 from the right; the rows
  /// #242628, 50 tall from 70 down, 10 apart, 16 from the panel's sides, their 14 pt names 16 in, the current one pink.
  static const qualityFill = Color(0xFF202123);
  static const qualityTitleCentre = 40.0;
  static const qualityTitleRow = 24.0;
  static const qualityTitle = 14.0;
  static const qualityNote = Color(0xFF8E8E93);
  static const qualitySide = 16.0;
  static const qualityTop = 70.0;
  static const qualityRow = 50.0;
  static const qualityRowGap = 10.0;
  static const qualityRowFill = Color(0xFF242628);
  static const qualityRowRadius = 2.0;
  static const qualityRowInset = 16.0;
  static const qualityRowText = 14.0;
  static const switchWidth = 125 / 3;
  static const switchHeight = 56 / 3;
  static const switchKnobWidth = 24.0;
  static const switchKnobInset = 1.0;
  static const switchRight = 20.0;
  static const switchOn = LiveRoomTheme.pink;

  /// Portrait's 画质 sheet: no screenshot shows it, so it takes 221's sheet (#110F1A, 分享's title 13 in and
  /// 20 down) with 210's rows.
  static const sheetFill = Color(0xF2110F1A);
  static const sheetRadius = 12.0;
  static const sheetTitleLeft = 13.0;
  static const sheetTitleTop = 10.0;
  static const sheetTitleHeight = 20.0;
  static const sheetTitle = 15.0;
  static const sheetBottom = 16.0;

  /// 222: #18191C with a grid of 42 pt discs (#2F3032), four to a row 79 apart and 98 down, the first centred 49.67
  /// in and 42.83 down; the words 12 pt, their middle 35.17 under the disc's. 助TA必火's red dot, 6 across in a 1 pt
  /// white ring, sits 19 right of and above its disc's middle.
  static const moreFill = Color(0xFF18191C);
  static const moreDisc = 42.0;
  static const moreDiscFill = Color(0xFF2F3032);
  static const moreIcon = 44.0;
  static const moreColourIcon = 22.0;
  static const moreColumns = 4;
  static const moreColumn = 79.0;
  static const moreRow = 98.0;
  static const moreFirstX = 149 / 3;
  static const moreFirstY = 128.5 / 3;
  static const moreLabelDrop = 211 / 6;
  static const moreLabel = 12.0;
  static const moreBadge = 6.0;
  static const moreBadgeRing = 1.0;
  static const moreBadgeOffset = 19.0;
  static const moreBadgeInk = Color(0xFFF85A54);

  /// The flame (助TA必火) and the shield (消费管理), drawn: the APK has neither; strokes 1.33 on the disc's 42 grid.
  static const drawnStroke = 4 / 3;
}

/// The 弹幕 inputs and emote panel (223, 226, 227).
///
/// 226: a #12101A panel with 12 pt top corners sits on the keyboard, 84 pt tall: the field #292831 from 12 to 358, 28
/// pt tall 8 under the panel's top, 13 pt words 10.67 in; 发送 58 × 28 pt, 12 from the edge, 14 pt white words on the
/// pink, at 40% while the field is empty. Under them a 48 pt band: emotes of 28 pt centred 40 apart from 26, fading
/// out before the three glyphs (译 18 × 20, the face 20, A 18.67), each centred in a 48 pt cell ending at the edge,
/// #C0C0C0 (the face pink while the panel shows). 醒目留言's pill sits 4 pt above the panel, 32 pt tall from 12 to 104.
abstract final class LiveSendTheme {
  static const panelFill = Color(0xFF12101A);
  static const panelRadius = 12.0;

  static const fieldTop = 8.0;
  static const fieldHeight = 28.0;
  static const fieldSide = 12.0;
  static const fieldFill = Color(0xFF292831);
  static const fieldPadding = 32 / 3;
  static const fieldText = 13.0;
  static const fieldInk = Color(0xFFFFFFFF);
  static const placeholder = Color(0xFF999999);

  /// The caret in 223: pink, 2 × 15.33 pt.
  static const cursor = LiveRoomTheme.pink;
  static const caretWidth = 2.0;
  static const caretHeight = 46 / 3;

  /// The field stops taking characters here, as Bilibili's danmaku limit.
  static const maxLength = 40;

  static const sendWidth = 58.0;
  static const sendGap = 12.0;
  static const sendFill = LiveRoomTheme.pink;
  static const sendFillEmpty = Color(0x66FF6699);
  static const sendText = 14.0;
  static const sendInk = Color(0xFFFFFFFF);

  /// The band under the field over the keyboard (226), and its 40 pt over the emote panel (227).
  static const bandHeight = 48.0;
  static const bandHeightPanel = 40.0;
  static const emoteSize = 28.0;
  static const emoteStep = 40.0;
  static const emoteLeft = 12.0;
  static const emoteFade = 48.0;

  /// How many emotes the band holds: the recently used first, then the first package's.
  static const recentCount = 20;

  static const glyphCell = 48.0;
  static const glyph = Color(0xFFC0C0C0);
  static const glyphOn = LiveRoomTheme.pink;
  static const translateWidth = 18.0;
  static const translateHeight = 20.0;
  static const faceSize = 20.0;
  static const faceStroke = 4 / 3;
  static const faceEyeX = 11 / 3;
  static const faceEyeY = 8.3 / 3;
  static const faceEyeRadius = 1.1;
  static const faceMouthTop = 0.7;
  static const faceMouthRadius = 2.5;
  static const styleSize = 56 / 3;

  /// 醒目留言's pill: #17181E with a 0.67 pt white 20% line, the 18 × 16.67 pt SC mark 13 in, 12 pt #E5E5E5 words
  /// 5.33 after it.
  static const pillHeight = 32.0;
  static const pillGap = 4.0;
  static const pillLeft = 12.0;
  static const pillLeftLandscape = 44.0;
  static const pillFill = Color(0xFF17181E);
  static const pillLine = Color(0x33FFFFFF);
  static const pillLineWidth = 2 / 3;
  // Inside the line, which the decoration adds to the padding.
  static const pillPadLeft = 13.0 - pillLineWidth;
  static const pillPadRight = 28 / 3 - pillLineWidth;
  static const pillMarkWidth = 18.0;
  static const pillMarkHeight = 50 / 3;
  static const pillMarkBody = 41 / 3;
  static const pillMarkRadius = 3.5;
  static const pillMarkTop = Color(0xFFBE5FFE);
  static const pillMarkBottom = Color(0xFF8B10FE);
  static const pillMarkText = 9.5;
  static const pillMarkInk = Color(0xFFFFFFFF);
  static const pillTextGap = 16 / 3;
  static const pillText = 12.0;
  static const pillInk = Color(0xFFE5E5E5);

  /// 223: the same panel across the top of the keyboard, the field from 106 pt in to 6 before three glyph cells
  /// (centred 696.67, 732, 768), 6 more to 发送, which ends 106 from the right edge; the emotes from 74 in, fading 66
  /// from the right. 醒目留言's pill 44 in.
  static const landscapeSide = 106.0;
  static const landscapeGlyphCell = 322 / 9;
  static const landscapeGlyphGap = 6.0;
  static const landscapeSendGap = 6.0;
  static const landscapeEmoteLeft = 74.0;
  static const landscapeEmoteRight = 66.0;

  /// 227's panel in the keyboard's place, 356 pt from the band down: 全部表情 (12 pt #C9CCD0, 16 in) in a 25 pt row,
  /// emotes of 32 pt in 52 × 50 cells from 12 in, eight to a row; ⌫ a #29272F key 53.33 × 34.33 pt, 10 from the
  /// right and 20 above the packages bar, its glyph 20.33 × 14.67 with a 1 pt line; the bar #29272F, cells 50 × 44
  /// with 24 pt icons, the chosen one in the panel's colour, 21 pt under them.
  static const emotePanelHeight = 356.0;

  /// 237: full screen's panel 232 tall (from 208 down to the screen's end), its fill across the whole width but the
  /// rest inside the safe area: sixteen emotes to a row sharing it less 12 at each side, the bar 20 above the bottom.
  static const emotePanelLandscape = 232.0;
  static const columnsLandscape = 16;
  static const barBottomLandscape = 20.0;
  static const headerHeight = 25.0;
  static const headerLeft = 16.0;
  static const headerText = 12.0;
  static const headerInk = Color(0xFFC9CCD0);
  static const gridSide = 12.0;
  static const gridCellWidth = 52.0;
  static const gridCellHeight = 50.0;
  static const gridEmote = 32.0;
  static const columns = 8;
  static const deleteWidth = 160 / 3;
  static const deleteHeight = 103 / 3;
  static const deleteRight = 10.0;
  static const deleteBottom = 20.0;
  static const deleteRadius = 4.0;
  static const deleteFill = Color(0xFF29272F);
  static const deleteGlyphWidth = 61 / 3;
  static const deleteGlyphHeight = 44 / 3;
  static const deleteGlyphStroke = 1.0;
  static const deleteInk = Color(0xFFFFFFFF);
  static const barFill = Color(0xFF29272F);
  static const barCellWidth = 50.0;
  static const barCellHeight = 44.0;
  static const barIcon = 24.0;
  static const barBottom = 21.0;
  static const empty = Color(0xFF999999);
  static const emptyText = 13.0;
}

/// 高能榜 (230-233).
abstract final class LiveRankTheme {
  /// Upright, a sheet over the screen's lower 70% (its top 286.67 down on 956) under 12 pt corners; in full screen a
  /// 375 pt panel at the right, square, the whole height. The room stays undimmed beside it.
  static const sheetShare = 0.7;
  static const sheetRadius = 12.0;
  static const panelWidth = 375.0;
  static const slideIn = Duration(milliseconds: 250);

  /// The tab row, 50 tall: 14 pt labels, their middles 19.67 down, 房间观众's 100 from the left edge and 大航海's
  /// 100 from the right; the chosen one's 80 × 3 underline 37 down.
  static const tabsHeight = 50.0;
  static const tabText = 14.0;
  static const tabCentre = 19.67;
  static const tabInset = 100.0;
  static const underlineWidth = 80.0;
  static const underlineHeight = 3.0;
  static const underlineTop = 37.0;
  static const tabSwitch = Duration(milliseconds: 250);

  /// 房间观众 on white, its label and underline #FB7299, 大航海's #7F7F7F; 大航海 on its purple, label and underline
  /// cream, 房间观众's a lilac grey. The purple runs from #302458 at the top to #1B162A near the bottom (231, 233).
  ///
  /// In 深色模式 房间观众 follows the app's dark surfaces (no screenshot shows it); 大航海's purple is its own and stays.
  static Color get audiencePage => BiliColors.card;
  static const audienceChosen = BiliColors.verticalPink;
  static Color get audienceOther => tone(0xFF7F7F7F, 0xFF8B9097);
  static const guardChosen = Color(0xFFF5E2BA);
  static const guardOther = Color(0xFF918AAB);
  static const guardTop = Color(0xFF302458);
  static const guardBottom = Color(0xFF1B162A);
  static const guardBottomStop = 0.87;

  /// Rows, 65 tall, both tabs: 36 pt faces; names 14 pt medium, their middle 11.75 above the row's; under them, the
  /// chips. 1-3 get the APK's 24 × 16 tags (榜1-3, 大航海's italic numerals), the rest plain numbers in that column.
  static const rowHeight = 65.0;
  static const rankWidth = 24.0;
  static const rankHeight = 16.0;
  static const faceSize = 36.0;
  static const nameText = 14.0;
  static const nameWeight = FontWeight.w500;
  static const nameLine = 20.0;
  static const nameCentre = -11.75;
  static const chipsHeight = 16.0;
  static const chipGap = 16 / 3;

  /// Load the next page with less than two rows left below.
  static const loadAhead = 130.0;

  /// 房间观众 (230, 232): the 在线榜 pill 12 in at the top, 21 tall with 10 either side, its 12 pt pink on a pink tint
  /// and 3.33 corners; the 12 pt grey line 31 down (25 tall), ⓘ 13 pt after it, 贡献值 and its 11.33 pt ⇌ 14.33 from
  /// the right; rows from 56 down.
  static const pillLeft = 12.0;
  static const pillHeight = 21.0;
  static const pillPadX = 10.0;
  static const pillRadius = 10 / 3;
  static const pillText = 12.0;
  static Color get pillFill => tone(0xFFFFECF1, 0xFF2F1A22);
  static Color get pillInk => BiliColors.pink;
  static const infoTop = 31.0;
  static const infoHeight = 25.0;
  static const infoText = 12.0;
  static const audienceInfoLeft = 12.0;
  static Color get audienceInfoInk => BiliColors.secondaryText;
  static const helpGap = 16 / 3;
  static const helpSize = 13.0;
  static const exchangeSize = 34 / 3;
  static const exchangeGap = 2.0;
  static const edgeRight = 43 / 3;
  static const audienceListTop = 56.0;

  /// 房间观众's row: the tag or #999999 12 pt number 14.33 in, the face 52 in, the name and chips 107.33 in (chips'
  /// middle 11.33 below the row's), the 12 pt grey 贡献值 15 from the right.
  static const audienceRankLeft = 43 / 3;
  static const audienceRankText = 12.0;
  static Color get audienceRankInk => tone(0xFF999999, 0xFF757A81);
  static const audienceFaceLeft = 52.0;
  static const audienceNameLeft = 322 / 3;
  static Color get audienceNameInk => BiliColors.text;
  static const audienceChipsCentre = 34 / 3;
  static const scoreText = 12.0;
  static Color get scoreInk => BiliColors.secondaryText;
  static const scoreRight = 15.0;
  static const scoreGap = 12.0;

  /// The viewer's own row under a 1 pt #F1F2F3 rule, 56 tall over the home indicator: - or the rank, the face, 贡献值 N
  /// and 快来投喂吧～ in 10 pt grey (middles 9.83 above and 9.17 below the row's), and the 56 × 24 pink 去投喂 with 12 pt
  /// white words, 14.33 from the right.
  static const ownRule = 1.0;
  static Color get ownRuleInk => tone(0xFFF1F2F3, 0xFF2F3134);
  static const ownHeight = 56.0;
  static const ownText = 10.0;
  static Color get ownInk => BiliColors.secondaryText;
  static const ownLine = 14.0;
  static const ownTopCentre = -9.83;
  static const ownBottomCentre = 9.17;
  static Color get ownRankInk => BiliColors.secondaryText;
  static const feedWidth = 56.0;
  static const feedHeight = 24.0;
  static const feedText = 12.0;
  static Color get feedFill => BiliColors.pink;
  static const feedInk = BiliColors.onPink;

  /// 大航海 (231, 233): a panel 12 in from each side under a 1 pt cream rim at 24% and 8 pt corners, a lilac wash
  /// fading down; inside, 14 from its edges, the 25 pt segmented tabs 15.67 down (6 apart, 8 pt corners, 12 pt words:
  /// the chosen one lighter and semibold), 上周TOP1's 50 pt card 17.33 under them, the 12 pt line 10.33 under that.
  static const panelInset = 12.0;
  static const panelRadius = 8.0;
  static const panelRim = Color(0x3DF5E2BA);
  static const panelRimWidth = 1.0;
  static const panelWashTop = Color(0x1A8F7BFF);
  static const panelWashBottom = Color(0x058F7BFF);
  static const guardContentInset = 26.0;
  static const segmentsTop = 47 / 3;
  static const segmentHeight = 25.0;
  static const segmentGap = 6.0;
  static const segmentRadius = 8.0;
  static const segmentText = 12.0;
  static const segmentChosenFill = Color(0xFF5B5487);
  static const segmentChosenInk = Color(0xFFDCCAFF);
  static const segmentChosenWeight = FontWeight.w600;
  static const segmentFill = Color(0xFF463D6D);
  static const segmentInk = Color(0xFF9B8DC5);
  static const cardGap = 52 / 3;
  static const cardHeight = 50.0;
  static const cardRadius = 8.0;
  static const cardTop = Color(0xFF42376C);
  static const cardBottom = Color(0xFF362B5B);
  static const cardFace = 24.0;
  static const cardFaceGap = 20.0;
  static const cardTitleText = 13.0;
  static const cardTitleWeight = FontWeight.w600;
  static const cardTitleInk = Color(0xFFE5D9FF);
  static const cardNameText = 14.0;
  static const cardNameInk = Color(0xFFC9CCD0);
  static const guardInfoGap = 31 / 3;
  static const guardInfoInk = Color(0xFFC9CCD0);
  static const guardHelpInk = Color(0xFF9499A0);

  /// 大航海's row: the numeral's column centred 32.5 in (14 pt grey past 3), the framed face's middle 81.83 in, name
  /// (white) and medal 122 in, the medal's middle 8.17 below the row's.
  static const guardRankLeft = 20.5;
  static const guardRankText = 14.0;
  static const guardRankInk = Color(0xFF9499A0);
  static const guardFaceLeft = 63.83;
  static const guardNameLeft = 122.0;
  static const guardNameInk = Color(0xFFFFFFFF);
  static const guardChipsCentre = 49 / 6;

  /// The bar over the panel's foot, 80 tall whatever the safe area, #2A243E under a 1 pt #605D67 rim with 12 pt
  /// corners; its row's middle 25 down. 千舰 (the room's badge, server art drawn here as words: 15 pt heavy cream over
  /// a soft violet glow) 17 in, the 12 pt cream prompt 73.67 in, and 立即上船: 30 tall, 14.33 from the right, a cream
  /// gradient, the APK's anchor 22 pt tall 8 in, 14 pt brown words 2 after it and 9 from the end.
  static const barHeight = 80.0;
  static const barRow = 50.0;
  static const barRadius = 12.0;
  static const barFill = Color(0xFF2A243E);
  static const barRim = Color(0xFF605D67);
  static const barRimWidth = 1.0;
  static const badgeLeft = 17.0;
  static const badgeText = 15.0;
  static const badgeWeight = FontWeight.w800;
  static const badgeTop = Color(0xFFFDF0D7);
  static const badgeBottom = Color(0xFFF1DCAA);
  static const badgeGlow = Color(0x804B4178);
  static const badgeGlowWidth = 48.0;
  static const badgeGlowHeight = 36.0;
  static const promptLeft = 221 / 3;
  static const promptLeftBare = 17.0;
  static const promptText = 12.0;
  static const promptInk = Color(0xFFF5E2BA);
  static const boardHeight = 30.0;
  static const boardStart = Color(0xFFFEF8E9);
  static const boardEnd = Color(0xFFF5E2BB);
  static const boardAnchor = 22.0;
  static const boardAnchorLeft = 8.0;
  static const boardAnchorGap = 2.0;
  static const boardText = 14.0;
  static const boardInk = Color(0xFF604041);
  static const boardPadRight = 9.0;

  /// A failed list's words and 重试, the next page's spinner and the empty list, as 热门's.
  static const stateText = HotListTheme.stateText;
  static Color get stateInk => HotListTheme.stateInk;
  static const stateGap = HotListTheme.stateGap;
  static const retryHeight = HotListTheme.retryHeight;
  static const retryPadX = HotListTheme.retryPadX;
  static const retryText = HotListTheme.retryText;
  static const retryRim = HotListTheme.retryRim;
  static Color get retryInk => BiliColors.pink;
  static const footerPad = HotListTheme.footerPad;
  static const footerLine = HotListTheme.footerLine;
  static const spinnerRadius = HotListTheme.spinnerRadius;
}
