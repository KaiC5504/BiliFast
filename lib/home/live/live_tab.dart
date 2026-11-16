import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_environment.dart';
import '../../app/app_scope.dart';
import '../../app/zoom_back_route.dart';
import '../../live/live_api.dart';
import '../../live/live_entry.dart';
import '../../live/live_routes.dart';
import '../../shared/loading_tv.dart';
import '../../shared/release_refresh.dart';
import '../../shared/theme.dart';
import '../../shared/toast.dart';
import '../feed_inline_player.dart';
import '../feed_model.dart' show FeedModel;
import 'live_cards.dart';
import 'live_carousel.dart';
import 'live_tab_model.dart';

/// 首页's 直播 page (205): the carousel, 我的关注's strip, the area tabs and their cards. [active] while it holds the
/// screen and 首页 is shown (the carousel plays only then); [scrollOffset] folds the header as 推荐's does; [reloads]
/// fires on 首页's tap.
class LiveTab extends StatefulWidget {
  const LiveTab({super.key, required this.active, required this.scrollOffset, this.reloads, this.api});

  final bool active;
  final ValueNotifier<double> scrollOffset;
  final Listenable? reloads;

  /// Tests' calls; the app's otherwise.
  final LiveApi? api;

  static const emptyMessage = '暂时没有直播';

  @override
  State<LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<LiveTab> with SkinRefreshRoom, AutomaticKeepAliveClientMixin {
  LiveTabModel? _model;
  late LiveApi _api;
  late AppServices _services;
  final _scroll = ScrollController();
  late final _host = FeedInlineHost(viewport: _area, pip: _services.pipKeeper, autoplay: InlineAutoplay.home);

  /// 首页's tap holds the refresh's space open at the top until it's done; [_reloadRoom] keeps it built while closing.
  bool _reloadHeader = false;
  bool _reloadRoom = false;

  /// 首页's tap is taking the list back to the top, where the header's fold already went.
  bool _toTop = false;
  bool _checkQueued = false;

  /// Whether the account was logged in when last heard; null before it was known.
  bool? _loggedIn;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.reloads?.addListener(_reload);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_model != null) return;
    _services = AppScope.of(context);
    _api = widget.api ?? _services.liveApi;
    _model = LiveTabModel(api: _api)..addListener(_modelChanged);
    _services.environment.addListener(_accountChanged);
    _loggedIn = _signedIn;
    if (widget.active) _model!.start();
  }

  @override
  void didUpdateWidget(LiveTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.reloads, widget.reloads)) {
      oldWidget.reloads?.removeListener(_reload);
      widget.reloads?.addListener(_reload);
    }
    if (widget.active && !oldWidget.active) _model!.start();
  }

  @override
  void dispose() {
    widget.reloads?.removeListener(_reload);
    _services.environment.removeListener(_accountChanged);
    _host.dispose();
    _model?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool? get _signedIn => switch (_services.environment.account) {
    AccountUnknown() => null,
    LoggedIn() => true,
    LoggedOut() || LoginExpired() => false,
  };

  bool _loggedInNow() => _signedIn ?? false;

  /// Logging in or out changes 我的关注 and what the feed recommends; the first check at launch does not.
  void _accountChanged() {
    final now = _signedIn;
    if (now == null) return;
    final before = _loggedIn;
    _loggedIn = now;
    if (before != null && before != now && _model!.started) unawaited(_refreshed(_model!.refresh()));
    if (mounted) setState(() {});
  }

  void _modelChanged() {
    if (!mounted) return;
    setState(() {});
    _host.settleSoon();
    // A page too short to scroll leaves the end on screen with no scrolling to notice it.
    _checkAfterFrame();
  }

  /// The page's area on screen, for the carousel's half-shown rule.
  Rect? _area() {
    final box = mounted ? context.findRenderObject() : null;
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final area = box.localToGlobal(Offset.zero) & box.size;
    final inset = MediaQuery.paddingOf(context).bottom;
    return Rect.fromLTRB(area.left, area.top, area.right, math.max(area.top, area.bottom - inset));
  }

  ValueListenable<bool>? _scrolling() => _scroll.hasClients ? _scroll.position.isScrollingNotifier : null;

  Future<void> _pull() => _refreshed(_model!.refresh());

  Future<void> _refreshed(Future<String?> refresh) async {
    final failure = await refresh;
    if (failure != null && mounted) showToast(context, failure);
  }

  /// 首页 tapped while 直播 shows, as 推荐's: back to the top, then the refresh's space held open there until it is
  /// done. Nothing more while a refresh or the first page is out.
  Future<void> _reload() async {
    final model = _model!;
    if (!model.started) {
      model.start();
      return;
    }
    if (_reloadHeader || model.refreshing || model.loadingFirst) return;
    final refresh = model.refresh();
    if (!model.fed || !_scroll.hasClients) {
      await _refreshed(refresh);
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(0);
    } else {
      _toTop = true;
      widget.scrollOffset.value = 0;
      try {
        await _scroll.animateTo(0, duration: LiveTabTheme.reloadScroll, curve: Curves.easeOut);
      } finally {
        _toTop = false;
      }
      // A finger can stop the scroll short of the top.
      if (mounted && _scroll.hasClients) widget.scrollOffset.value = math.max(0, _scroll.position.pixels);
    }
    if (!mounted) return;
    setState(() => _reloadHeader = _reloadRoom = true);
    await _refreshed(refresh);
    if (mounted) setState(() => _reloadHeader = false);
  }

  bool _scrolled(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    // Only what the list really scrolls: a bounce past either end folds nothing.
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    if (!_toTop) {
      widget.scrollOffset.value = metrics.hasContentDimensions
          ? metrics.pixels.clamp(metrics.minScrollExtent, metrics.maxScrollExtent)
          : metrics.pixels;
    }
    _loadMoreNearEnd();
    // Only once the list has come to rest: the carousel scrolled half off plays on until the finger lets go.
    if (notification is ScrollEndNotification) _host.settleSoon();
    return false;
  }

  void _checkAfterFrame() {
    if (_checkQueued) return;
    _checkQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      if (mounted) _loadMoreNearEnd();
    });
  }

  void _loadMoreNearEnd() {
    final model = _model!;
    if (!model.canLoadMore || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions || position.extentAfter >= LiveTabTheme.loadAhead) return;
    // A scroll notification can come mid-layout, where the model's change must not rebuild anything yet.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      _checkAfterFrame();
    } else {
      unawaited(model.loadMore());
    }
  }

  void _open(LiveCard card, ZoomSource source) =>
      unawaited(openLiveRoom(context, LiveRoomEntry.fromCard(card), source: source));

  void _soon() => showToast(context, '暂未开放');

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final model = _model!;
    // A route over 首页 (a page, a sheet) or another place shown stills the carousel; the app leaving, its host.
    final shown = _host.shown = widget.active && (ModalRoute.isCurrentOf(context) ?? true);
    return ColoredBox(
      color: LiveTabTheme.page,
      // Out of sight the 直播中 gifs stop decoding frames (an Image listens to its stream only while tickers run).
      child: TickerMode(
        enabled: shown,
        // Never shown yet: nothing to draw, and no TV ticking out of sight.
        child: model.started ? _list(context, model) : const SizedBox.expand(),
      ),
    );
  }

  Widget _list(BuildContext context, LiveTabModel model) {
    // Under a dressed bar the list runs to the screen's bottom; its end stays above the bar's row.
    final inset = MediaQuery.paddingOf(context).bottom;
    final still = MediaQuery.disableAnimationsOf(context);
    final room = refreshRoom;
    final width = MediaQuery.sizeOf(context).width;
    final following = model.following;
    final showFollowing = following.isNotEmpty && _loggedIn != false;
    return NotificationListener<ScrollNotification>(
      onNotification: _scrolled,
      child: CustomScrollView(
        key: const ValueKey('live-list'),
        controller: _scroll,
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // While 首页's tap holds its room open, a pull draws and opens nothing: that refresh is already showing.
          ReleaseRefreshControl(
            refreshTriggerPullDistance: refreshTrigger,
            refreshIndicatorExtent: room,
            builder: _reloadHeader ? null : loadingTvRefreshIndicator,
            onRefresh: _reloadHeader ? null : _pull,
          ),
          SliverToBoxAdapter(
            child: AnimatedContainer(
              duration: still
                  ? Duration.zero
                  : _reloadHeader
                  ? LiveTabTheme.reloadHeader
                  : LiveTabTheme.reloadCollapse,
              curve: Curves.easeInOut,
              height: _reloadHeader ? room : 0,
              onEnd: () {
                if (!_reloadHeader && mounted) setState(() => _reloadRoom = false);
              },
              child: _reloadRoom
                  ? ClipRect(
                      child: OverflowBox(
                        key: const ValueKey('live-reload'),
                        alignment: Alignment.bottomCenter,
                        minHeight: room,
                        maxHeight: room,
                        child: Center(child: RefreshLoading(room: room)),
                      ),
                    )
                  : null,
            ),
          ),
          if (!model.fed || _empty(model))
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.only(bottom: inset),
                child: Center(child: _state(model)),
              ),
            )
          else ...[
            if (model.bigCards.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.only(top: LiveTabTheme.carouselTop),
                sliver: SliverToBoxAdapter(
                  child: LiveCarousel(
                    cards: model.bigCards,
                    host: _host,
                    api: _api,
                    loggedIn: _loggedInNow,
                    scrolling: _scrolling,
                    onOpen: _open,
                  ),
                ),
              ),
            if (showFollowing)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  LiveTabTheme.sectionSide,
                  LiveTabTheme.sectionGap,
                  LiveTabTheme.sectionSide,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: _FollowingSection(
                    card: following.first,
                    total: math.max(model.followingTotal, following.length),
                    onAll: () => unawaited(openLiveFollowing(context)),
                    onOpen: (source) => _open(following.first, source),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: _AreaTabs(areas: model.areas, selected: model.selected, onSelect: model.select, onIcon: _soon),
            ),
            ..._cards(model, width),
            SliverToBoxAdapter(child: SizedBox(height: inset)),
          ],
        ],
      ),
    );
  }

  bool _empty(LiveTabModel model) =>
      model.bigCards.isEmpty &&
      model.following.isEmpty &&
      model.cards.isEmpty &&
      model.selected.isRecommend &&
      model.exhausted;

  List<Widget> _cards(LiveTabModel model, double width) {
    final cards = model.cards;
    if (cards.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: LiveTabTheme.stateGap * 4),
            child: Center(child: _areaState(model)),
          ),
        ),
      ];
    }
    final column = (width - LiveTabTheme.gridSide - LiveTabTheme.gridSideRight - LiveTabTheme.gridGap) / 2;
    return [
      SliverPadding(
        padding: const EdgeInsets.only(left: LiveTabTheme.gridSide, right: LiveTabTheme.gridSideRight),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: LiveTabTheme.gridGap,
            crossAxisSpacing: LiveTabTheme.gridGap,
            mainAxisExtent: LiveGridCard.height(column),
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final card = cards[index];
            return LiveGridCard(
              key: ValueKey('live-grid-${card.roomId}'),
              card: card,
              onOpen: (source) => _open(card, source),
              onMore: _soon,
            );
          }, childCount: cards.length),
        ),
      ),
      SliverToBoxAdapter(child: _footer(model)),
    ];
  }

  Widget _state(LiveTabModel model) {
    if (model.error case final error? when !model.loadingFirst) {
      return _Failure(message: error, onRetry: () => unawaited(model.retry()));
    }
    if (model.fed) return const _Words(LiveTab.emptyMessage, key: ValueKey('live-empty'));
    return const LoadingTvState(key: ValueKey('live-loading'));
  }

  /// The area chosen before its first page: the TV, the failure or nothing in it.
  Widget _areaState(LiveTabModel model) {
    if (model.listError case final error?) {
      return _Failure(message: error, onRetry: () => unawaited(model.retry()));
    }
    if (model.areaLoading) return const LoadingTvState(key: ValueKey('live-area-loading'));
    return const _Words(LiveTab.emptyMessage, key: ValueKey('live-area-empty'));
  }

  Widget _footer(LiveTabModel model) {
    final error = model.listError;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LiveTabTheme.footerPad),
      child: Center(
        child: error != null
            ? _Failure(message: error, onRetry: () => unawaited(model.retry()))
            : model.loadingMore
            ? const SizedBox(
                height: LiveTabTheme.footerLine,
                child: CupertinoActivityIndicator(
                  key: ValueKey('live-more-spinner'),
                  radius: LiveTabTheme.spinnerRadius,
                ),
              )
            : model.exhausted
            ? const _Words(FeedModel.endMessage, key: ValueKey('live-end'))
            : const SizedBox(height: LiveTabTheme.footerLine),
      ),
    );
  }
}

/// 我的关注 N人正在直播 with 查看全部, over the first followed room live.
class _FollowingSection extends StatelessWidget {
  const _FollowingSection({required this.card, required this.total, required this.onAll, required this.onOpen});

  final LiveCard card;
  final int total;
  final VoidCallback onAll;
  final void Function(ZoomSource source) onOpen;

  @override
  Widget build(BuildContext context) {
    final count = liveStyle(LiveTabTheme.sectionCountText, LiveTabTheme.secondary);
    return Container(
      key: const ValueKey('live-following'),
      decoration: BoxDecoration(color: LiveTabTheme.card, borderRadius: BorderRadius.circular(LiveTabTheme.radius)),
      padding: const EdgeInsets.fromLTRB(
        LiveTabTheme.sectionInset,
        0,
        LiveTabTheme.sectionInset,
        LiveTabTheme.stripBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: LiveTabTheme.stripTop,
            child: Align(
              alignment: const Alignment(0, -1 + 2 * LiveTabTheme.sectionLineCentre / LiveTabTheme.stripTop),
              child: Row(
                children: [
                  Text(
                    '我的关注',
                    style: liveStyle(
                      LiveTabTheme.sectionTitleText,
                      LiveTabTheme.text,
                      weight: LiveTabTheme.sectionTitleWeight,
                    ),
                  ),
                  const SizedBox(width: LiveTabTheme.sectionCountGap),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$total',
                          style: count.copyWith(color: LiveTabTheme.sectionCount),
                        ),
                        const TextSpan(text: '人正在直播'),
                      ],
                    ),
                    key: const ValueKey('live-following-count'),
                    style: count,
                  ),
                  const SizedBox(width: LiveTabTheme.sectionBarsGap - LiveTabTheme.barsInk),
                  const LiveBars(color: LiveTabTheme.sectionBars),
                  const Spacer(),
                  Semantics(
                    button: true,
                    label: '查看全部',
                    onTap: onAll,
                    excludeSemantics: true,
                    child: GestureDetector(
                      key: const ValueKey('live-following-all'),
                      behavior: HitTestBehavior.opaque,
                      onTap: onAll,
                      child: Row(
                        children: [
                          Text('查看全部', style: liveStyle(LiveTabTheme.sectionAllText, LiveTabTheme.secondary)),
                          const SizedBox(width: LiveTabTheme.chevronGap),
                          const SizedBox(
                            width: LiveTabTheme.chevronWidth,
                            height: LiveTabTheme.chevronHeight,
                            child: CustomPaint(painter: LiveChevronPainter()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ZoomSourceBox(
            builder: (context, source) => Semantics(
              button: true,
              label: '${card.uname}，${card.title}',
              onTap: () => onOpen(source),
              excludeSemantics: true,
              child: GestureDetector(
                key: ValueKey('live-following-room-${card.roomId}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onOpen(source),
                child: Container(
                  height: LiveTabTheme.stripHeight,
                  foregroundDecoration: BoxDecoration(
                    border: Border.all(color: LiveTabTheme.stripRimInk, width: LiveTabTheme.stripRim),
                    borderRadius: BorderRadius.circular(LiveTabTheme.radius),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(LiveTabTheme.radius),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: LiveTabTheme.stripCoverWidth,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              LiveCover(card: card),
                              const LiveCoverShade(),
                              LiveCoverCounts(card: card),
                              if (card.badge case final badge?)
                                Positioned(left: 0, top: 0, child: LiveCoverTag(badge: badge)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: LiveRoomLines(
                            card: card,
                            face: LiveTabTheme.stripFace,
                            faceLead: LiveTabTheme.stripFaceLead,
                            textLead: LiveTabTheme.stripTextLead,
                            badge: LiveTabTheme.stripBadge,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The area tabs: 推荐 and the feed's areas, sideways; the picture and ⊞ at the right over the fading row. A tab
/// chosen half under the fade or past the left edge slides fully into the clear part.
class _AreaTabs extends StatefulWidget {
  const _AreaTabs({required this.areas, required this.selected, required this.onSelect, required this.onIcon});

  final List<LiveArea> areas;
  final LiveArea selected;
  final ValueChanged<LiveArea> onSelect;
  final VoidCallback onIcon;

  @override
  State<_AreaTabs> createState() => _AreaTabsState();
}

class _AreaTabsState extends State<_AreaTabs> {
  final _row = ScrollController();
  double _fadeFrom = LiveTabTheme.areaFadeFrom;

  @override
  void dispose() {
    _row.dispose();
    super.dispose();
  }

  void _choose(LiveArea area, BuildContext tab) {
    widget.onSelect(area);
    // Measured once drawn chosen: the semibold words are wider.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && tab.mounted) _reveal(tab);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _reveal(BuildContext tab) {
    final box = tab.findRenderObject();
    final strip = context.findRenderObject();
    if (box is! RenderBox || strip is! RenderBox || !box.attached || !_row.hasClients) return;
    final left = box.localToGlobal(Offset.zero, ancestor: strip).dx;
    // The tab's box carries the gap after its words; only the words need to clear the fade.
    final right = left + box.size.width - LiveTabTheme.areaGap;
    final shift = right > _fadeFrom
        ? right - _fadeFrom
        : left < LiveTabTheme.areaLead
        ? left - LiveTabTheme.areaLead
        : 0.0;
    if (shift == 0) return;
    final position = _row.position;
    final target = (position.pixels + shift).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (MediaQuery.disableAnimationsOf(context)) {
      _row.jumpTo(target);
    } else {
      unawaited(_row.animateTo(target, duration: LiveTabTheme.areaReveal, curve: Curves.easeOut));
    }
  }

  @override
  Widget build(BuildContext context) {
    const iconsWidth = LiveTabTheme.areaGridRight + LiveTabTheme.areaIconPitch + LiveTabTheme.areaIconTarget / 2;
    final selected = widget.selected;
    return SizedBox(
      key: const ValueKey('live-areas'),
      height: LiveTabTheme.areaRow,
      child: LayoutBuilder(
        builder: (context, box) {
          final fadeFrom = _fadeFrom = math.min(LiveTabTheme.areaFadeFrom, box.maxWidth - iconsWidth);
          final fadeWidth = box.maxWidth - fadeFrom;
          return Stack(
            children: [
              ListView(
                key: const ValueKey('live-area-row'),
                controller: _row,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.only(left: LiveTabTheme.areaLead, right: fadeWidth),
                children: [
                  for (final area in widget.areas)
                    _AreaTab(
                      area: area,
                      chosen: area.id == selected.id && area.parentId == selected.parentId,
                      onTap: (tab) => _choose(area, tab),
                    ),
                ],
              ),
              Positioned(
                left: fadeFrom,
                top: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          LiveTabTheme.page.withValues(alpha: 0),
                          LiveTabTheme.page.withValues(alpha: LiveTabTheme.areaFadeNear),
                          LiveTabTheme.page.withValues(alpha: LiveTabTheme.areaFadeFar),
                        ],
                        stops: [0, LiveTabTheme.areaFadeEdge / fadeWidth, 1],
                      ),
                    ),
                  ),
                ),
              ),
              _icon(
                key: const ValueKey('live-area-cover'),
                label: '切换封面',
                right: LiveTabTheme.areaGridRight + LiveTabTheme.areaIconPitch,
                asset: LiveArt.coverSwitch,
                height: LiveTabTheme.areaCoverIcon,
              ),
              _icon(
                key: const ValueKey('live-area-all'),
                label: '全部分区',
                right: LiveTabTheme.areaGridRight,
                asset: LiveArt.areas,
                width: LiveTabTheme.areaGridIcon,
                height: LiveTabTheme.areaGridIcon,
              ),
            ],
          );
        },
      ),
    );
  }

  /// An icon centred [right] from the row's right.
  Widget _icon({
    required Key key,
    required String label,
    required double right,
    required String asset,
    required double height,
    double? width,
  }) => Positioned(
    right: right - LiveTabTheme.areaIconTarget / 2,
    top: 0,
    bottom: 0,
    width: LiveTabTheme.areaIconTarget,
    child: Semantics(
      button: true,
      label: label,
      onTap: widget.onIcon,
      excludeSemantics: true,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: widget.onIcon,
        child: Center(
          child: Image.asset(asset, width: width, height: height, fit: BoxFit.contain, excludeFromSemantics: true),
        ),
      ),
    ),
  );
}

class _AreaTab extends StatelessWidget {
  const _AreaTab({required this.area, required this.chosen, required this.onTap});

  final LiveArea area;
  final bool chosen;
  final ValueChanged<BuildContext> onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: chosen,
    label: area.name,
    onTap: () => onTap(context),
    excludeSemantics: true,
    child: GestureDetector(
      key: ValueKey('live-area-${area.id}-${area.parentId}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(context),
      child: Padding(
        padding: const EdgeInsets.only(right: LiveTabTheme.areaGap),
        child: Center(
          child: Text(
            area.name,
            maxLines: 1,
            style: liveStyle(
              LiveTabTheme.areaText,
              chosen ? LiveTabTheme.text : LiveTabTheme.secondary,
              weight: chosen ? LiveTabTheme.areaChosenWeight : FontWeight.w400,
            ),
          ),
        ),
      ),
    ),
  );
}

class _Words extends StatelessWidget {
  const _Words(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = liveStyle(LiveTabTheme.stateText, LiveTabTheme.secondary);
    return Text(text, maxLines: 1, style: style, strutStyle: BiliFonts.strut(style));
  }
}

/// Why the list stopped, and 重试.
class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        message,
        key: const ValueKey('live-error'),
        textAlign: TextAlign.center,
        style: liveStyle(LiveTabTheme.stateText, LiveTabTheme.secondary),
      ),
      const SizedBox(height: LiveTabTheme.stateGap),
      Semantics(
        button: true,
        label: '重试',
        onTap: onRetry,
        excludeSemantics: true,
        child: GestureDetector(
          key: const ValueKey('live-retry'),
          behavior: HitTestBehavior.opaque,
          onTap: onRetry,
          child: Container(
            height: LiveTabTheme.retryHeight,
            padding: const EdgeInsets.symmetric(horizontal: LiveTabTheme.retryPadX),
            alignment: Alignment.center,
            decoration: const ShapeDecoration(
              shape: StadiumBorder(
                side: BorderSide(color: BiliColors.pink, width: LiveTabTheme.retryRim),
              ),
            ),
            child: Text('重试', style: liveStyle(LiveTabTheme.retryText, BiliColors.pink)),
          ),
        ),
      ),
    ],
  );
}
