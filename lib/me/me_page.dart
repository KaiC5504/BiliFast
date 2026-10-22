import 'dart:async';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_environment.dart';
import '../app/app_scope.dart';
import '../app/swipe_back_route.dart';
import '../favourites/favourites_page.dart';
import '../history/watch_history_page.dart';
import '../home/shortcut_glyphs.dart';
import '../settings/settings_page.dart';
import '../shared/release_refresh.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import '../skin/skin.dart';
import '../skin/skin_model.dart';
import '../skin/skin_video.dart';
import '../space/space_route.dart';
import '../space/uploader_tap.dart';
import '../watch_later/watch_later_page.dart';
import 'me_glyphs.dart';
import 'me_header.dart';
import 'me_model.dart';
import 'official_link.dart';

Future<bool> _openOutside(Uri link) => launchUrl(link, mode: LaunchMode.externalApplication);

/// 我的, the bottom bar's Me page (02, 87, 106, 107), apart from the avatar's page (49).
class MePage extends StatefulWidget {
  const MePage({
    super.key,
    required this.active,
    this.developerPage,
    @visibleForTesting this.model,
    @visibleForTesting this.skin,
    @visibleForTesting this.openLink = _openOutside,
    @visibleForTesting this.canOpenLink = canLaunchUrl,
  });

  /// Whether 我的 is the bar's current tab; turning true is a showing ([MeModel.shown]).
  final bool active;

  /// Passed on to 设置 (更多服务's row), null leaves 开发者 out.
  final WidgetBuilder? developerPage;

  /// The model to show in place of one made from [AppScope]; the page leaves it undisposed.
  final MeModel? model;

  /// The equipped 装扮 in place of [AppServices.skin].
  final SkinModel? skin;

  /// Opens a link outside the app, the official app's first; false (or a throw) when it couldn't.
  final Future<bool> Function(Uri link) openLink;

  /// Whether a link's app is there; asked before the official app's link except on iOS.
  final Future<bool> Function(Uri link) canOpenLink;

  static final vipCentre = Uri.parse('https://big.bilibili.com/mobile/home');

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  MeModel? _model;
  bool _owned = false;
  late AppEnvironment _environment;
  late MeView _lastView;

  /// Pulls still out; each toasts its own answer, so a failure landing meanwhile isn't toasted twice.
  int _pulls = 0;

  /// The header has been drawn once, so a card coming after that fades in.
  bool _headerDrawn = false;

  late SkinModel _skin;

  /// The 装扮's picture once it has decoded. Only then does the header take the skin's colours, so a picture that
  /// fails leaves 87's look rather than white text on the white page.
  File? _pictureReady;

  MeModel get _me => _model!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _environment = AppScope.of(context).environment;
    if (_model != null) return;
    _skin = widget.skin ?? AppScope.of(context).skin;
    _skin.addListener(_skinChanged);
    _skinChanged();
    final given = widget.model;
    if (given != null) {
      _model = given;
    } else {
      _model = MeModel(api: AppScope.of(context).meApi, environment: _environment);
      _owned = true;
    }
    _lastView = _me.view;
    _me.addListener(_viewChanged);
    if (widget.active) _me.shown();
  }

  @override
  void didUpdateWidget(MePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _me.shown();
  }

  @override
  void dispose() {
    _skin.removeListener(_skinChanged);
    _model?.removeListener(_viewChanged);
    if (_owned) _model?.dispose();
    super.dispose();
  }

  void _skinChanged() {
    final picture = _skin.value?.headMyself;
    if (picture == null || picture.path == _pictureReady?.path) return;
    var failed = false;
    unawaited(
      precacheImage(
        FileImage(picture),
        context,
        onError: (error, _) {
          failed = true;
          Logger.shared.error(LogCategory.ui, 'skin picture failed', {'error': '${error.runtimeType}'});
        },
      ).then((_) {
        if (failed || !mounted || _skin.value?.headMyself?.path != picture.path) return;
        setState(() => _pictureReady = picture);
      }),
    );
  }

  /// The skin 我的 wears now: none logged out, nor before its picture is ready. A video comes only over its picture,
  /// which stands in until the video draws.
  Skin? _dress(MeView view) {
    final skin = _skin.value;
    if (skin == null || view is MeLoggedOut) return null;
    final picture = skin.headMyself;
    return picture != null && picture.path == _pictureReady?.path ? skin : null;
  }

  /// There is no screenshot of a failed header, so a first load that fails says why in a toast, once. Not while
  /// 我的 is hidden (a login loads it behind 首页); showing it again retries, and that failure toasts.
  void _viewChanged() {
    final view = _me.view;
    final was = _lastView;
    _lastView = view;
    if (view is MeFailed && was is! MeFailed && _pulls == 0 && widget.active && mounted) {
      showToast(context, view.message);
    }
  }

  void _soon() => showToast(context, '即将推出');

  void _push(WidgetBuilder builder) =>
      unawaited(_visit(Navigator.of(context).push(SwipeBackPageRoute<void>(builder: builder))));

  /// Back from a pushed page, a launch check that failed is tried again, as 首页 does.
  Future<void> _visit(Future<void> pushed) async {
    await pushed;
    if (mounted && _environment.account is AccountUnknown && _environment.accountCheckFailed) {
      await _environment.refreshAccount();
    }
  }

  void _openSpace() {
    if (_me.view case MeShown(:final profile) when (profile.mid ?? 0) > 0) {
      final ref = UploaderRef(mid: profile.mid!, name: profile.name, face: profile.face);
      unawaited(_visit(openSpace(context, ref)));
    }
  }

  void _login() => unawaited(AppScope.of(context).loginGate.request(context));

  Future<void> _openVipCentre() async {
    final opened = await openInOfficialApp(
      MePage.vipCentre,
      open: widget.openLink,
      canOpen: widget.canOpenLink,
    );
    if (!opened && mounted) showToast(context, '无法打开链接');
  }

  Future<void> _refresh() async {
    unawaited(_skin.refresh());
    _pulls++;
    final String? message;
    try {
      message = await _me.refresh();
    } finally {
      _pulls--;
    }
    if (message != null && mounted) showToast(context, message);
  }

  /// A 大会员 known from the launch's check keeps the card's room until the profile answers.
  bool _reserveCard(MeView view) =>
      (view is MeLoading || view is MeFailed) &&
      switch (_environment.account) {
        LoggedIn(:final vip) => vip,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final actions = MeActions(
      openSpace: _openSpace,
      login: _login,
      soon: _soon,
      openVipCentre: () => unawaited(_openVipCentre()),
    );
    return Material(
      color: MeTheme.background,
      child: ListenableBuilder(
        listenable: Listenable.merge([_me, _environment, _skin]),
        builder: (context, _) {
          final view = _me.view;
          final skin = _dress(view);
          final picture = skin?.headMyself;
          final ink = skin == null ? null : skin.color ?? (skin.lightText ? MeTheme.skinLightInk : null);
          final reduceMotion = MediaQuery.disableAnimationsOf(context);
          final animate = _headerDrawn && !reduceMotion;
          _headerDrawn = true;
          final header = Stack(
            children: [
              MeHeader(view: view, actions: actions, reserveCard: _reserveCard(view), animate: animate, ink: ink),
              _TopRow(onTap: _soon, color: ink ?? MeTheme.topGlyph),
            ],
          );
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: skin != null && skin.lightText ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
            child: Column(
              children: [
                Stack(
                  children: [
                    if (skin != null && picture != null)
                      Positioned.fill(
                        child: _SkinPicture(skin: skin, picture: picture),
                      ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: top),
                        // AnimatedSize can't take a zero duration, so Reduce Motion leaves it out.
                        if (reduceMotion)
                          header
                        else
                          AnimatedSize(
                            duration: MeTheme.cardFade,
                            curve: MeTheme.cardFadeCurve,
                            alignment: Alignment.topCenter,
                            child: header,
                          ),
                        const SizedBox(height: MeTheme.listCut),
                      ],
                    ),
                  ],
                ),
                Expanded(
                  child: _List(onRefresh: _refresh, onSoon: _soon, push: _push, developerPage: widget.developerPage),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 109's picture (or its video, the picture standing in until it plays) from the screen's top to the list's: as
/// wide as the screen and cut at the bottom, a short wide one filling the height instead and cut at both sides, as
/// the official Android app draws `head_myself_squared_bg` and `head_myself_bg`.
class _SkinPicture extends StatelessWidget {
  const _SkinPicture({required this.skin, required this.picture});

  final Skin skin;
  final File picture;

  @override
  Widget build(BuildContext context) {
    final still = Image.file(
      picture,
      key: const ValueKey('me-skin-picture'),
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      gaplessPlayback: true,
      excludeFromSemantics: true,
    );
    final video = skin.headMyselfVideo;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (video == null)
            still
          else
            SkinVideo(file: video, loop: skin.equip.colors.headMyselfVideoLoop, placeholder: still),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: MeTheme.skinFade,
            child: DecoratedBox(
              key: ValueKey('me-skin-fade'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: MeTheme.skinFadeColors,
                  stops: MeTheme.skinFadeStops,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 投屏, 扫一扫, 装扮 and 夜间模式, none built yet.
class _TopRow extends StatelessWidget {
  const _TopRow({required this.onTap, required this.color});

  final VoidCallback onTap;
  final Color color;

  static const _glyphs = [
    (MeTopGlyph.cast, 'me-cast', '投屏'),
    (MeTopGlyph.scan, 'me-scan', '扫一扫'),
    (MeTopGlyph.outfit, 'me-outfit', '装扮'),
    (MeTopGlyph.night, 'me-night', '夜间模式'),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return SizedBox(
      height: MeTheme.topTapHeight,
      width: width,
      child: Stack(
        children: [
          for (final (index, (glyph, key, label)) in _glyphs.indexed)
            Positioned(
              left:
                  width -
                  MeTheme.topLastFromRight -
                  MeTheme.topPitch * (_glyphs.length - 1 - index) -
                  MeTheme.topPitch / 2,
              top: MeTheme.topCentre - MeTheme.topTapHeight / 2,
              width: MeTheme.topPitch,
              height: MeTheme.topTapHeight,
              child: MeTap(
                key: ValueKey(key),
                label: label,
                onTap: onTap,
                child: Center(
                  child: CustomPaint(
                    size: const Size.square(MeTheme.topGlyphBox),
                    painter: MeTopGlyphPainter(glyph, color: color),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What scrolls under the header, cut 8 pt under it: the pull, the four shortcuts and 更多服务.
class _List extends StatelessWidget {
  const _List({required this.onRefresh, required this.onSoon, required this.push, required this.developerPage});

  final Future<void> Function() onRefresh;
  final VoidCallback onSoon;
  final void Function(WidgetBuilder builder) push;
  final WidgetBuilder? developerPage;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    key: const ValueKey('me-list'),
    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
    slivers: [
      ReleaseRefreshControl(onRefresh: onRefresh),
      SliverToBoxAdapter(
        child: SizedBox(
          height: MeTheme.shortcutHeight - MeTheme.listCut,
          child: Row(
            children: [
              _Shortcut(key: const ValueKey('me-offline'), label: '离线缓存', glyph: ShortcutGlyph.offline, onTap: onSoon),
              _Shortcut(
                key: const ValueKey('me-history'),
                label: '历史记录',
                glyph: ShortcutGlyph.history,
                onTap: () => push((_) => const WatchHistoryPage()),
              ),
              _Shortcut(
                key: const ValueKey('me-favourites'),
                label: '我的收藏',
                glyph: ShortcutGlyph.star,
                onTap: () => push((_) => const FavouritesPage()),
              ),
              _Shortcut(
                key: const ValueKey('me-later'),
                label: '稍后再看',
                glyph: ShortcutGlyph.later,
                onTap: () => push((_) => const WatchLaterPage()),
              ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: MeTheme.serviceFirstCentre - MeTheme.shortcutHeight - MeTheme.serviceRow / 2,
          child: Stack(
            children: [
              Positioned(
                left: BiliMetrics.gutter,
                top: MeTheme.servicesTitleCentre - MeTheme.shortcutHeight - MeTheme.serviceRow / 4,
                height: MeTheme.serviceRow / 2,
                child: Center(
                  child: Text(
                    '更多服务',
                    style: TextStyle(
                      fontFamily: BiliFonts.family,
                      fontSize: MeTheme.servicesTitleText,
                      fontWeight: MeTheme.servicesTitleWeight,
                      color: MeTheme.servicesTitle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      SliverList.list(
        children: [
          _ServiceRow(key: const ValueKey('me-support'), label: '联系客服', glyph: MeServiceGlyph.support, onTap: onSoon),
          _ServiceRow(key: const ValueKey('me-listen'), label: '听视频', glyph: MeServiceGlyph.listen, onTap: onSoon),
          _ServiceRow(
            key: const ValueKey('me-settings'),
            label: '设置',
            glyph: MeServiceGlyph.settings,
            onTap: () => push((_) => SettingsPage(developerPage: developerPage)),
          ),
        ],
      ),
      const SliverToBoxAdapter(child: SizedBox(height: MeTheme.bottomPad)),
      // A themed bar lays its art over the page and leaves its height here (0 under the stock bar).
      SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom)),
    ],
  );
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({super.key, required this.label, required this.glyph, required this.onTap});

  final String label;
  final ShortcutGlyph glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: CupertinoButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        child: SizedBox.expand(
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                top: MeTheme.shortcutIconCentre - MeTheme.listCut - AvatarPageTheme.shortcutIconBox / 2,
                child: CustomPaint(
                  size: const Size.square(AvatarPageTheme.shortcutIconBox),
                  painter: ShortcutPainter(glyph, color: MeTheme.shortcutGlyph),
                ),
              ),
              Positioned(
                top: MeTheme.shortcutLabelCentre - MeTheme.listCut - MeTheme.lineBox / 2,
                height: MeTheme.lineBox,
                child: Center(
                  child: Text(
                    label,
                    maxLines: 1,
                    // CupertinoButton's own text style would drop the page's fallback to PingFang and track by -0.41.
                    style: TextStyle(
                      fontFamily: BiliFonts.family,
                      fontFamilyFallback: BiliFonts.fallback,
                      fontSize: MeTheme.shortcutText,
                      letterSpacing: 0,
                      color: MeTheme.shortcutLabel,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// One of 更多服务's rows: the pink glyph, the title and ›.
class _ServiceRow extends StatelessWidget {
  const _ServiceRow({super.key, required this.label, required this.glyph, required this.onTap});

  final String label;
  final MeServiceGlyph glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MeTap(
    label: label,
    onTap: onTap,
    feedback: MeTapFeedback.highlight,
    child: SizedBox(
      height: MeTheme.serviceRow,
      child: Stack(
        children: [
          Positioned(
            left: MeTheme.serviceGlyphCentre - MeTheme.serviceGlyphBox / 2,
            top: (MeTheme.serviceRow - MeTheme.serviceGlyphBox) / 2,
            child: CustomPaint(size: const Size.square(MeTheme.serviceGlyphBox), painter: MeServiceGlyphPainter(glyph)),
          ),
          Positioned(
            left: MeTheme.serviceTextLeft,
            top: 0,
            bottom: 0,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: BiliFonts.family,
                  fontSize: MeTheme.serviceText,
                  color: MeTheme.serviceLabel,
                ),
              ),
            ),
          ),
          Positioned(
            right: MeTheme.spaceRight,
            top: (MeTheme.serviceRow - MeTheme.chevronHeight) / 2,
            child: const CustomPaint(
              size: Size(MeTheme.chevronWidth, MeTheme.chevronHeight),
              painter: MeChevronPainter(color: MeTheme.serviceChevron, stroke: MeTheme.chevronStroke),
            ),
          ),
        ],
      ),
    ),
  );
}
