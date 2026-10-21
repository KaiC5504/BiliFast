import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app/app_environment.dart' show LoggedIn;
import '../app/app_scope.dart';
import '../shared/loading_tv.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import 'space_bar.dart';
import 'space_follow.dart';
import 'space_header.dart';
import 'space_header_tabs.dart';
import 'space_unfollow_sheet.dart';
import 'space_videos.dart';
import 'uploader_tap.dart';

/// UP主空间 (63, 69-75, 77): the header over 投稿, collapsing to a white bar with the tab row pinned under it.
class SpacePage extends StatefulWidget {
  const SpacePage({super.key, required this.uploader});

  final UploaderRef uploader;

  @override
  State<SpacePage> createState() => _SpacePageState();
}

class _SpacePageState extends State<SpacePage> {
  static const _soon = '暂未开放';

  final _scroll = ScrollController();
  final _sheet = ValueNotifier(false);

  SpaceProfile? _profile;
  bool _failed = false;
  SpaceFollow? _follow;
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scrolled);
    _sheet.addListener(_sheetChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_follow != null) return;
    final services = AppScope.of(context);
    final environment = services.environment;
    _follow = SpaceFollow(
      mid: widget.uploader.mid,
      api: services.pageApi,
      book: services.follows,
      isLoggedIn: () => environment.account is LoggedIn,
      requestLogin: () => unawaited(services.loginGate.request(context)),
      toast: (message) => showToast(context, message),
    )..addListener(_followChanged);
    unawaited(_follow!.load());
    unawaited(_load());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _sheet.dispose();
    _follow?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = AppScope.of(context).spaceApi;
    if (_failed) setState(() => _failed = false);
    try {
      final profile = await api.profile(widget.uploader.mid);
      if (mounted) setState(() => _profile = profile);
    } catch (error) {
      Logger.shared.warn(LogCategory.api, 'space failed', {'error': _reason(error)});
      if (mounted) setState(() => _failed = true);
    }
  }

  static String _reason(Object error) => switch (error) {
    BiliHTTPError(:final status) => 'http $status',
    BiliAPIError(:final code) => 'api $code',
    _ => '${error.runtimeType}',
  };

  void _followChanged() {
    if (mounted) setState(() {});
  }

  void _sheetChanged() {
    if (mounted) setState(() {});
  }

  /// The bar comes in once the name's line has passed under the status bar (77).
  void _scrolled() {
    if (!_scroll.hasClients) return;
    final top = MediaQuery.paddingOf(context).top;
    final collapsed = _scroll.offset >= SpaceHeader.nameCentre - top;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  void _soonToast() => showToast(context, _soon);

  void _back() => unawaited(Navigator.of(context).maybePop());

  bool get _following => _follow?.following ?? false;

  void _tapFollow() {
    if (_following) {
      _sheet.value = true;
    } else {
      unawaited(_follow!.toggle());
    }
  }

  void _unfollow() => unawaited(_follow!.toggle());

  void _tapTab(SpaceTab tab) {
    if (tab.kind != SpaceTabKind.contribute) _soonToast();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    // Light over a picture banner, as 72; dark over the default banner (63) and the white bar.
    final darkStatus = profile == null || _collapsed || (profile.banner?.isEmpty ?? true);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: darkStatus ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: PopScope<Object?>(
        canPop: !_sheet.value,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _sheet.value = false;
        },
        // Pushed on a plain route with no Material above it, text would otherwise take the app's fallback style.
        child: DefaultTextStyle(
          style: spaceStyle(SpaceTheme.bioText, BiliColors.text),
          child: ColoredBox(
            color: SpaceTheme.page,
            child: Stack(
              children: [
                Positioned.fill(child: profile == null ? _waiting() : _space(profile)),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: profile == null
                      ? SpaceBar(
                          collapsed: true,
                          face: widget.uploader.face,
                          name: widget.uploader.name ?? '',
                          onBack: _back,
                          onSoon: _soonToast,
                        )
                      : SpaceBar(
                          collapsed: _collapsed,
                          face: profile.face.isEmpty ? widget.uploader.face : profile.face,
                          following: _following,
                          onFollow: _tapFollow,
                          onBack: _back,
                          onSoon: _soonToast,
                        ),
                ),
                Positioned.fill(
                  child: SpaceUnfollowSheet(open: _sheet, onUnfollow: _unfollow, onSoon: _soonToast),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _waiting() {
    final top = MediaQuery.paddingOf(context).top + SpaceTheme.barRow;
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Center(
        child: _failed
            ? Semantics(
                button: true,
                label: '加载失败，点击重试',
                excludeSemantics: true,
                child: GestureDetector(
                  key: const ValueKey('space-retry'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => unawaited(_load()),
                  child: Padding(
                    padding: const EdgeInsets.all(SpaceTheme.gutter),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '加载失败，', style: spaceStyle(SpaceTheme.retryText, SpaceTheme.retryInk)),
                          TextSpan(text: '点击重试', style: spaceStyle(SpaceTheme.retryText, SpaceTheme.retryAction)),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : const LoadingTvState(key: ValueKey('space-loading')),
      ),
    );
  }

  Widget _space(SpaceProfile profile) {
    final top = MediaQuery.paddingOf(context).top;
    final barHeight = top + SpaceTheme.barRow;
    final headerHeight = SpaceHeader.heightOf(profile);
    final following = _following;
    return CustomScrollView(
      controller: _scroll,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _HeaderDelegate(
            min: barHeight,
            max: headerHeight,
            builder: (stretch) => SpaceHeader(
              profile: profile,
              following: following,
              stretch: stretch,
              onFollow: _tapFollow,
              onFollowed: _tapFollow,
              onSoon: _soonToast,
            ),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _TabsDelegate(SpaceTabRow(tabs: SpaceTabRow.of(profile), onTap: _tapTab)),
        ),
        SpaceVideosSliver(profile: profile, api: AppScope.of(context).spaceApi),
        // However short 投稿 is, the header can still scroll away and the tabs pin under the bar.
        SliverLayoutBuilder(
          builder: (context, constraints) => SliverToBoxAdapter(
            child: SizedBox(
              height: math.max(
                0,
                constraints.viewportMainAxisExtent + headerHeight - barHeight - constraints.precedingScrollExtent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The header, shrinking from its full height to the bar's and stretching its banner past it when pulled down.
class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate({required this.min, required this.max, required this.builder});

  final double min;
  final double max;
  final Widget Function(double stretch) builder;

  @override
  double get minExtent => min;

  @override
  double get maxExtent => max;

  @override
  OverScrollHeaderStretchConfiguration get stretchConfiguration => OverScrollHeaderStretchConfiguration();

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => LayoutBuilder(
    builder: (context, constraints) {
      final extent = constraints.maxHeight;
      if (extent >= max) return SizedBox(height: extent, child: builder(extent - max));
      return SizedBox(
        height: extent,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.bottomCenter,
            minHeight: max,
            maxHeight: max,
            child: builder(0),
          ),
        ),
      );
    },
  );

  @override
  bool shouldRebuild(_HeaderDelegate oldDelegate) => true;
}

class _TabsDelegate extends SliverPersistentHeaderDelegate {
  const _TabsDelegate(this.row);

  final Widget row;

  @override
  double get minExtent => SpaceTheme.tabsHeight;

  @override
  double get maxExtent => SpaceTheme.tabsHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => row;

  @override
  bool shouldRebuild(_TabsDelegate oldDelegate) => true;
}
