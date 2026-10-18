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

  /// Behind and over the video.
  static const videoBackground = Color(0xFF000000);
  static const onVideo = Color(0xFFFFFFFF);
  static const statsFill = Color(0x8C000000);
  static const statsBorder = Color(0x1FFFFFFF);

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
  static const badgeText = Color(0xE6FFFFFF);

  /// 26's video never gets brighter than 41 of 255 under its dim.
  static const endDim = Color(0xD6000000);
  static const endButton = Color(0x33FFFFFF);
  static const endCaption = Color(0xB3FFFFFF);
  static const endMeta = Color(0x99FFFFFF);
  static const endPlayGlyph = Color(0xF2FFFFFF);
  static const endCoverShade = Color(0x8C000000);

  /// Danmaku outlines: very dark text gets the light one, or it would vanish inside it.
  static const danmakuOutline = Color(0xD9000000);
  static const danmakuOutlineLight = Color(0xD9FFFFFF);
  static const danmakuOwnBox = Color(0xFFFFFFFF);

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

/// MiSans (Xiaomi, free for apps that credit it; see README) on every platform, as Kazumi does: one font draws all the
/// Chinese, where the platform fallback mixes Japanese and Chinese fonts on Windows. The zh-Hans locale makes any
/// character MiSans lacks fall back to a Chinese font.
abstract final class BiliFonts {
  static const family = 'MiSans';
  static const locale = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN');
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

  /// The video page's player box, its back arrow and the loading spinner's radius (twice it is [chromeIcon]).
  static const videoAspect = 16 / 9;
  static const videoBackIcon = 20.0;
  static const videoBackShadow = 6.0;
  static const videoSpinnerRadius = 14.0;

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
  static const badgePadding = 3.5;
  static const badgeBorderWidth = 0.7;
  static const badgeOffsetX = 12.0;
  static const badgeOffsetY = -16.0;
  static const endInset = 12.0;
  static const endCaptionFont = 12.0;
  static const endCaptionGap = 3.8;
  static const endCoverWidth = 128.0;
  static const endCoverHeight = 72.0;
  static const endCoverRadius = 5.0;
  static const endCoverGap = 11.0;
  static const endCoverShadeHeight = 30.0;
  static const endCoverTextInset = 7.0;
  static const endCoverTextBottom = 5.0;
  static const endCoverTimeFont = 12.0;
  static const endPlayGlyphWidth = 18.7;
  static const endPlayGlyphHeight = 22.0;
  static const endTitleFont = 14.0;

  /// The uploader and counts rows sit at fixed heights inside the cover's 72.
  static const endUploaderTop = 40.0;
  static const endCountsTop = 58.0;
  static const endMetaRow = 12.0;
  static const endMetaFont = 10.0;
  static const endMetaIcon = 16.0;
  static const endMetaGap = 4.5;
  static const endMetaSpacing = 12.0;
  static const endUpWidth = 13.3;
  static const endUpHeight = 11.3;
  static const endUpFont = 7.5;
  static const endUpRadius = 2.5;
  static const endUpBorder = 1.0;
  static const endButtonFont = 14.0;
  static const endButtonWidth = 66.5;
  static const endButtonHeight = 30.0;
  static const endButtonTrailing = 18.0;
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
  static const pasteControl = 28.0;
  static const linkFieldIcon = 17.0;
  static const linkClearIcon = 18.0;
  static const tabText = 16.0;
  static const tabIndicatorWidth = 18.0;
  static const tabIndicatorHeight = 3.0;
  static const menuWidth = 248.0;
  static const menuRowHeight = 46.0;
  static const menuAvatar = 40.0;
  static const menuRadius = 12.0;
  static const menuIconBox = 24.0;
  static const menuIcon = 20.0;
  static const menuSpinnerRadius = 9.0;
  static const vipBadgeHeight = 16.0;
  static const vipBadgeText = 10.0;
  static const toastRadius = 16.0;
  static const openingPadding = 28.0;
  static const openingSpinner = 32.0;
  static const recentsTile = 40.0;
  static const recentsTileRadius = 10.0;
  static const recentsTileIcon = 26.0;

  /// The menus' frosted glass.
  static const glassBlur = 24.0;
  static const glassHairline = 0.5;
  static const glassShadowBlur = 24.0;
  static const glassShadowDrop = 8.0;

  /// Danmaku text at the normal size (25); an elem's own size scales it.
  static const danmakuFont = 17.0;
  static const danmakuFontFullScreen = 22.0;
  static const danmakuOutline = 1.0;
  static const danmakuPad = 1.0;
  static const danmakuOwnPadX = 5.0;
  static const danmakuOwnPadY = 1.5;
  static const danmakuOwnRadius = 3.0;
}
