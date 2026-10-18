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

  /// Danmaku outlines: very dark text gets the light one, or it would vanish inside it.
  static const danmakuOutline = Color(0xD9000000);
  static const danmakuOutlineLight = Color(0xD9FFFFFF);
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

  /// The family every style names; null is the system's, which on the iPhone is SF with PingFang SC, as the official
  /// app draws.
  static String? family = miSans;

  /// The layout nudges that line MiSans up with the official app's PingFang apply only while MiSans is on.
  static bool get nudged => family == miSans;

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

  /// 弹幕设置 and the 3 pt before the danmaku field.
  static const chromeSettingsRoom = 52.0;
  static const chromeSpeedGap = 14.0;
  static const chromeQualityGap = 23.0;
  static const chromeEpisodesGap = 15.0;
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
  static const landscapeEndActionText = 13.0;
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

  /// 设置 and its pages, as iOS grouped lists.
  static const settingsRowHeight = 50.0;
  static const settingsSectionGap = 10.0;
  static const settingsValueText = 14.0;
  static const settingsValueWidth = 200.0;
  static const settingsChevron = 20.0;
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

  /// Danmaku text at the normal size (25); an elem's own size scales it.
  static const danmakuFont = 17.0;
  static const danmakuFontFullScreen = 22.0;
  static const danmakuOutline = 1.0;
  static const danmakuPad = 1.0;
  static const danmakuOwnPadX = 5.0;
  static const danmakuOwnPadY = 1.5;
  static const danmakuOwnRadius = 3.0;
}

/// The tab row under the player (简介 / 评论 N, the 弹 toggle and 点我发弹幕) and the 简介 page's spacing (03, 18).
abstract final class PageTheme {
  static const tabRowHeight = 44.0;
}

/// The uploader row and the title block (03, 18).
abstract final class IntroTheme {
  static const uploaderTop = 13.0;
}

/// 合集, the part strip, the topic and BGM chips and the related rows (03, 18).
abstract final class IntroListTheme {
  /// 03 and 18 put 18 pt between the action labels, the 合集 card, the chips and the related list's first hairline.
  /// The action row's box ends 3.33 below its labels' ink, so each section owns this much above it and
  /// [sectionBottom] below, and two sections meet 18 apart.
  static const sectionTop = 46 / 3;
  static const sectionBottom = 8 / 3;

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

  /// Three round-ended bars, the first full height, the other two 60% of it, 4.33 apart.
  static const barsWidth = 21 / 2;
  static const barsHeight = 34 / 3;
  static const barWidth = 11 / 6;
  static const barShortShare = 20 / 34;

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

  /// The topic and BGM capsules (03, 18): 26 tall, 7.3 apart; the name stops at 80 and scrolls by once.
  static const chipHeight = 26.0;
  static const chipLead = 10.0;
  static const chipTrailing = 34 / 3;
  static const chipGap = 22 / 3;
  static const chipText = 12.0;
  static const chipIconGap = 5.5;
  static const chipChevronGap = 4.5;
  static const chipTextMax = 80.0;
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
  static const rowHeight = 70.0;
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

  /// The alert grows to its size from this as it fades in.
  static const alertStartScale = 1.08;
}

/// Landscape's top actions, uploader and 关注 (04), and its end screen's actions (27), measured at 3 px per pt.
abstract final class LandscapeActionTheme {
  /// The glyphs' ink is 20 pt on both screens, 0.84 of the icon's box.
  static const iconSize = 24.0;

  /// After each 44 pt button, the last one's before ⋮.
  static const buttonGap = 8.0;

  /// The superscript count: its left edge this far right of its button's centre, its digits' tops 5 pt into the
  /// button.
  static const countText = 9.5;
  static const countLead = 6.7;
  static const countTop = 5.5;

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

  /// 27's 充电 and 关注 pills under the uploader's name, level with the avatar's bottom.
  static const pillWidth = 88.0;
  static const pillHeight = 30.0;
  static const pillGap = 8.0;
  static const pillBorder = 1.0;
  static const pillText = 14.0;
  static const boltWidth = 7.2;
  static const boltHeight = 11.6;
  static const boltGap = 7.6;

  /// Padding before ⚡ 充电, which 27 sets half this right of its pill's centre.
  static const chargeShift = 4.0;
  static const pillPlus = 9.0;
  static const pillPlusStroke = 1.2;
  static const pillPlusGap = 5.0;

  /// 已关注's pill, as BiliNative's end screen draws it.
  static const followedPill = Color(0x38FFFFFF);

  /// How far an action's icon swells as it turns on.
  static const pop = 1.28;
}

/// 竖屏's action column, uploader, 粉丝 and 关注 (09), and the 选集 sheet's share circle and 收藏 (19).
abstract final class VerticalActionTheme {
  static const iconSize = 36.0;
}
