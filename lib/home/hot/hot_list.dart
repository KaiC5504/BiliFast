import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../../player_ui/end_screen_portrait.dart' show ShareLink, shareThroughSystem;
import '../../search/results/video_row.dart' show searchStyle;
import '../../shared/loading_tv.dart';
import '../../shared/release_refresh.dart';
import '../../shared/theme.dart';
import '../../shared/toast.dart';
import '../../video/video_route.dart';
import '../feed_model.dart' show FeedModel;
import 'hot_api.dart';
import 'hot_model.dart';
import 'hot_row.dart';
import 'hot_share_sheet.dart';

/// 首页's 热门 (204): the website's popular list, pulled to refresh and loaded on as it nears the end.
class HotList extends StatefulWidget {
  const HotList({
    super.key,
    required this.active,
    required this.scrollOffset,
    this.reloads,
    this.api,
    this.share = shareThroughSystem,
    this.openVideo,
    this.now = DateTime.now,
  });

  /// The page is on screen: the list loads the first time it is.
  final bool active;

  /// How far the list is scrolled, which folds 首页's header as 推荐's does.
  final ValueNotifier<double> scrollOffset;

  /// 首页 tapped again while 热门 shows: back to the top and refreshed.
  final Listenable? reloads;

  /// Tests pass their own; otherwise the demo under `--fake-account`, else the website's.
  final HotApi? api;

  /// Hands a row's link to the system share sheet; tests record it instead.
  final ShareLink share;

  /// Opens a row's video; [openVideoPage] unless a test watches it instead.
  final void Function(BuildContext context, VideoRoute route)? openVideo;

  /// What the rows' dates count back from.
  final DateTime Function() now;

  static const emptyMessage = '暂时没有热门视频';

  @override
  State<HotList> createState() => _HotListState();
}

class _HotListState extends State<HotList> with SkinRefreshRoom, AutomaticKeepAliveClientMixin {
  HotModel? _model;
  final _scroll = ScrollController();

  /// 首页's tap holds the refresh's room open at the top until it's done; [_reloadRoom] keeps it built while closing.
  bool _reloadHeader = false;
  bool _reloadRoom = false;

  /// 首页's tap is taking the list back to the top, where the header's fold already went.
  bool _toTop = false;

  bool _checkQueued = false;

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
    final environment = AppScope.of(context).environment;
    final api = widget.api ?? (environment.fake ? FakeHotApi.demo() : ClientHotApi(environment.client));
    _model = HotModel(api: api)..addListener(_modelChanged);
    if (widget.active) _model!.start();
  }

  @override
  void didUpdateWidget(HotList oldWidget) {
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
    _model?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _modelChanged() {
    if (!mounted) return;
    setState(() {});
    // A page too short to scroll leaves the end on screen with no scrolling to notice it.
    _checkAfterFrame();
  }

  Future<void> _pull() async {
    final failure = await _model!.refresh();
    if (failure != null && mounted) showToast(context, failure);
  }

  /// 首页 tapped while 热门 shows, as 推荐's: back to the top, then the refresh's room held open there until it is
  /// done. Nothing more while a refresh or the first page is out; with nothing shown the list's own state stands for
  /// it.
  Future<void> _reload() async {
    final model = _model!;
    if (!model.started) {
      model.start();
      return;
    }
    if (_reloadHeader || model.refreshing || model.loadingFirst) return;
    final refresh = model.refresh();
    if (model.videos.isEmpty || !_scroll.hasClients) {
      await _refreshed(refresh);
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(0);
    } else {
      _toTop = true;
      widget.scrollOffset.value = 0;
      try {
        await _scroll.animateTo(0, duration: HotListTheme.reloadScroll, curve: Curves.easeOut);
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

  Future<void> _refreshed(Future<String?> refresh) async {
    final failure = await refresh;
    if (failure != null && mounted) showToast(context, failure);
  }

  bool _scrolled(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    // Only what the list really scrolls: a bounce past either end folds nothing.
    final metrics = notification.metrics;
    if (!_toTop) {
      widget.scrollOffset.value = metrics.hasContentDimensions
          ? metrics.pixels.clamp(metrics.minScrollExtent, metrics.maxScrollExtent)
          : metrics.pixels;
    }
    _loadMoreNearEnd();
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
    if (!position.hasContentDimensions || position.extentAfter >= HotListTheme.loadAhead) return;
    // A scroll notification can come mid-layout, where the model's change must not rebuild anything yet.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      _checkAfterFrame();
    } else {
      unawaited(model.loadMore());
    }
  }

  void _open(PopularVideo video) {
    final card = video.card;
    final route = VideoRoute(
      bvid: card.bvid,
      cidHint: card.cid > 0 ? card.cid : null,
      title: card.title,
      cover: card.cover.isEmpty ? null : card.cover,
    );
    final open = widget.openVideo;
    if (open != null) {
      open(context, route);
    } else {
      unawaited(openVideoPage(context, route));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final model = _model!;
    return ColoredBox(
      color: HotListTheme.page,
      // Never shown yet: nothing to draw, and no TV ticking out of sight.
      child: model.started ? _list(context, model) : const SizedBox.expand(),
    );
  }

  Widget _list(BuildContext context, HotModel model) {
    final videos = model.videos;
    // Under a dressed bar the list runs to the screen's bottom; its end stays above the bar's row.
    final inset = MediaQuery.paddingOf(context).bottom;
    final still = MediaQuery.disableAnimationsOf(context);
    final room = refreshRoom;
    final now = widget.now();
    return NotificationListener<ScrollNotification>(
      onNotification: _scrolled,
      child: CustomScrollView(
        key: const ValueKey('hot-list'),
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
                  ? HotListTheme.reloadHeader
                  : HotListTheme.reloadCollapse,
              curve: Curves.easeInOut,
              height: _reloadHeader ? room : 0,
              onEnd: () {
                if (!_reloadHeader && mounted) setState(() => _reloadRoom = false);
              },
              child: _reloadRoom
                  ? ClipRect(
                      child: OverflowBox(
                        key: const ValueKey('hot-reload'),
                        alignment: Alignment.bottomCenter,
                        minHeight: room,
                        maxHeight: room,
                        child: Center(child: RefreshLoading(room: room)),
                      ),
                    )
                  : null,
            ),
          ),
          if (videos.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.only(bottom: inset),
                child: Center(child: _state(model)),
              ),
            )
          else ...[
            SliverFixedExtentList.builder(
              itemExtent: HotRow.height,
              itemCount: videos.length,
              itemBuilder: (_, index) {
                final video = videos[index];
                return HotRow(
                  key: ValueKey('hot-${video.card.bvid}'),
                  video: video,
                  now: now,
                  onOpen: () => _open(video),
                  onMore: () => unawaited(showHotShareSheet(context, video, share: widget.share)),
                );
              },
            ),
            SliverToBoxAdapter(child: _footer(model)),
            SliverToBoxAdapter(child: SizedBox(height: inset)),
          ],
        ],
      ),
    );
  }

  Widget _state(HotModel model) {
    if (model.error case final error? when !model.loadingFirst) {
      return _Failure(message: error, onRetry: () => unawaited(model.retry()));
    }
    if (model.exhausted) return _Words(HotList.emptyMessage, key: const ValueKey('hot-empty'));
    return const LoadingTvState(key: ValueKey('hot-loading'));
  }

  Widget _footer(HotModel model) {
    final error = model.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HotListTheme.footerPad),
      child: Center(
        child: error != null
            ? _Failure(message: error, onRetry: () => unawaited(model.retry()))
            : model.loadingMore
            ? const SizedBox(
                height: HotListTheme.footerLine,
                child: CupertinoActivityIndicator(
                  key: ValueKey('hot-more-spinner'),
                  radius: HotListTheme.spinnerRadius,
                ),
              )
            : model.exhausted
            ? const _Words(FeedModel.endMessage, key: ValueKey('hot-end'))
            : const SizedBox(height: HotListTheme.footerLine),
      ),
    );
  }
}

class _Words extends StatelessWidget {
  const _Words(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = searchStyle(HotListTheme.stateText, HotListTheme.stateInk, line: HotListTheme.footerLine);
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
        key: const ValueKey('hot-error'),
        textAlign: TextAlign.center,
        style: searchStyle(HotListTheme.stateText, HotListTheme.stateInk),
      ),
      const SizedBox(height: HotListTheme.stateGap),
      _RetryPill(onTap: onRetry),
    ],
  );
}

/// 重试's pink-rimmed pill, as 搜索's; it shrinks while pressed.
class _RetryPill extends StatefulWidget {
  const _RetryPill({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_RetryPill> createState() => _RetryPillState();
}

class _RetryPillState extends State<_RetryPill> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '重试',
    onTap: widget.onTap,
    excludeSemantics: true,
    child: GestureDetector(
      key: const ValueKey('hot-retry'),
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(true),
      onTapUp: (_) => _press(false),
      onTapCancel: () => _press(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? HotListTheme.retryPressedScale : 1,
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : HotListTheme.retryPressMotion,
        curve: Curves.easeOut,
        child: Container(
          height: HotListTheme.retryHeight,
          padding: const EdgeInsets.symmetric(horizontal: HotListTheme.retryPadX),
          alignment: Alignment.center,
          decoration: const ShapeDecoration(
            shape: StadiumBorder(
              side: BorderSide(color: BiliColors.pink, width: HotListTheme.retryRim),
            ),
          ),
          child: Text('重试', style: searchStyle(HotListTheme.retryText, BiliColors.pink)),
        ),
      ),
    ),
  );
}
