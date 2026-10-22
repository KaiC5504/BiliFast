import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_scope.dart';
import '../app/swipe_back_route.dart';
import '../favourites/favourites_page.dart';
import '../history/watch_history_page.dart';
import '../home/shortcut_glyphs.dart';
import '../settings/settings_page.dart';
import '../shared/release_refresh.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import '../space/space_route.dart';
import '../space/uploader_tap.dart';
import '../watch_later/watch_later_page.dart';
import 'me_glyphs.dart';
import 'me_header.dart';
import 'me_model.dart';

Future<bool> _openOutside(Uri link) => launchUrl(link, mode: LaunchMode.externalApplication);

/// 我的, the bottom bar's Me page (87, 106, 107), apart from the avatar's page (49).
class MePage extends StatefulWidget {
  const MePage({
    super.key,
    required this.active,
    this.developerPage,
    @visibleForTesting this.model,
    @visibleForTesting this.openLink = _openOutside,
  });

  /// Whether 我的 is the bar's current tab; turning true is a showing ([MeModel.shown]).
  final bool active;

  /// Passed on to 设置 (更多服务's row), null leaves 开发者 out.
  final WidgetBuilder? developerPage;

  /// The model to show in place of one made from [AppScope]; the page leaves it undisposed.
  final MeModel? model;

  /// Opens the 会员 centre outside the app; false when nothing could.
  final Future<bool> Function(Uri link) openLink;

  static final vipCentre = Uri.parse('https://big.bilibili.com/mobile/home');

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  MeModel? _model;
  bool _owned = false;

  MeModel get _me => _model!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_model != null) return;
    final given = widget.model;
    if (given != null) {
      _model = given;
    } else {
      final services = AppScope.of(context);
      _model = MeModel(api: services.meApi, environment: services.environment);
      _owned = true;
    }
    if (widget.active) _me.shown();
  }

  @override
  void didUpdateWidget(MePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _me.shown();
  }

  @override
  void dispose() {
    if (_owned) _model?.dispose();
    super.dispose();
  }

  void _soon() => showToast(context, '即将推出');

  void _push(WidgetBuilder builder) =>
      unawaited(Navigator.of(context).push(SwipeBackPageRoute<void>(builder: builder)));

  void _openSpace() {
    if (_me.view case MeShown(:final profile)) {
      unawaited(openSpace(context, UploaderRef(mid: profile.mid, name: profile.name, face: profile.face)));
    }
  }

  void _login() => unawaited(AppScope.of(context).loginGate.request(context));

  Future<void> _openVipCentre() async {
    final opened = await widget.openLink(MePage.vipCentre);
    if (!opened && mounted) showToast(context, '无法打开链接');
  }

  Future<void> _refresh() async {
    final message = await _me.refresh();
    if (message != null && mounted) showToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final actions = MeActions(
      openSpace: _openSpace,
      login: _login,
      soon: _soon,
      openVipCentre: () => unawaited(_openVipCentre()),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Material(
        color: MeTheme.background,
        child: ListenableBuilder(
          listenable: _me,
          builder: (context, _) {
            final view = _me.view;
            return Column(
              children: [
                SizedBox(height: top),
                Stack(
                  children: [
                    MeHeader(view: view, actions: actions),
                    _TopRow(onTap: _soon),
                  ],
                ),
                Expanded(
                  child: _List(onRefresh: _refresh, onSoon: _soon, push: _push, developerPage: widget.developerPage),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 投屏, 扫一扫, 装扮 and 夜间模式, none built yet.
class _TopRow extends StatelessWidget {
  const _TopRow({required this.onTap});

  final VoidCallback onTap;

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
                  child: CustomPaint(size: const Size.square(MeTheme.topGlyphBox), painter: MeTopGlyphPainter(glyph)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What scrolls under the 会员 card, cut at its bottom edge: the pull, the four shortcuts and 更多服务.
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
          height: MeTheme.shortcutHeight,
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
                top: MeTheme.shortcutIconCentre - AvatarPageTheme.shortcutIconBox / 2,
                child: CustomPaint(
                  size: const Size.square(AvatarPageTheme.shortcutIconBox),
                  painter: ShortcutPainter(glyph, color: MeTheme.shortcutGlyph),
                ),
              ),
              Positioned(
                top: 0,
                height: MeTheme.shortcutLabelCentre * 2,
                child: Center(
                  child: Text(
                    label,
                    maxLines: 1,
                    // CupertinoButton's own text style would drop the page's fallback to PingFang.
                    style: TextStyle(
                      fontFamily: BiliFonts.family,
                      fontFamilyFallback: BiliFonts.fallback,
                      fontSize: MeTheme.shortcutText,
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
