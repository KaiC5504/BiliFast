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

  /// The stats overlay.
  static const statsFont = 10.0;
  static const statsPadding = 6.0;
  static const statsRadius = 6.0;
  static const statsLineGap = 2.0;
  static const statsDot = 5.0;
  static const statsDotGap = 4.0;

  /// 首页 (BiliNative `FeedMetrics`, measured on screen 01 at 3 px per point).
  static const feedSpacing = 6.0;
  static const coverAspect = 4 / 3;
  static const cardInset = 8.0;
  static const cardTitleText = 14.0;
  static const cardFooterText = 12.0;
  static const cardTagText = 11.0;
  static const cardTagHeight = 16.0;
  static const cardStatText = 11.0;
  static const cardStatIcon = 13.0;
  static const coverShadeHeight = 36.0;
  static const topRowHeight = 44.0;
  static const topRowMargin = 15.0;
  static const homeAvatar = 38.0;
  static const linkFieldHeight = 34.0;
  static const tabText = 16.0;
  static const tabIndicatorWidth = 18.0;
  static const tabIndicatorHeight = 3.0;
  static const menuWidth = 248.0;
  static const menuRowHeight = 46.0;
  static const menuAvatar = 40.0;
  static const menuRadius = 12.0;
  static const toastRadius = 16.0;

  /// How far a pressed card shrinks.
  static const pressedScale = 0.97;

  /// Danmaku text at the normal size (25); an elem's own size scales it.
  static const danmakuFont = 17.0;
  static const danmakuFontFullScreen = 22.0;
  static const danmakuOutline = 1.0;
  static const danmakuPad = 1.0;
  static const danmakuOwnPadX = 5.0;
  static const danmakuOwnPadY = 1.5;
  static const danmakuOwnRadius = 3.0;
}
