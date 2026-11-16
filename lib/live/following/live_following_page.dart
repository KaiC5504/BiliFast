import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../../app/zoom_back_route.dart';
import '../../dynamic/following/following_page.dart' show FollowingBarLook;
import '../../home/live/live_cards.dart';
import '../../shared/loading_tv.dart';
import '../../shared/release_refresh.dart';
import '../../shared/theme.dart';
import '../../shared/toast.dart';
import '../../skin/skin.dart';
import '../live_api.dart';
import '../live_entry.dart';
import '../live_routes.dart';
import 'live_following_model.dart';

/// 206: the followed rooms that are live, two to a row.
class LiveFollowingPage extends StatefulWidget {
  const LiveFollowingPage({super.key, this.api});

  /// Tests' calls; the app's otherwise.
  final LiveApi? api;

  static const emptyMessage = '暂时没有正在直播的主播';

  @override
  State<LiveFollowingPage> createState() => _LiveFollowingPageState();
}

class _LiveFollowingPageState extends State<LiveFollowingPage> with SkinRefreshRoom {
  LiveFollowingModel? _model;
  final _scroll = ScrollController();
  bool _checkQueued = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_model != null) return;
    final api = widget.api ?? AppScope.of(context).liveApi;
    _model = LiveFollowingModel(api: api)
      ..addListener(_changed)
      ..start();
  }

  @override
  void dispose() {
    _model?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _checkAfterFrame();
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
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      _checkAfterFrame();
    } else {
      unawaited(model.loadMore());
    }
  }

  bool _scrolled(ScrollNotification notification) {
    if (notification.depth == 0) _loadMoreNearEnd();
    return false;
  }

  Future<void> _pull() async {
    final failure = await _model!.refresh();
    if (failure != null && mounted) showToast(context, failure);
  }

  void _open(LiveCard card, ZoomSource source) =>
      unawaited(openLiveRoom(context, LiveRoomEntry.fromCard(card), source: source));

  void _back() => unawaited(Navigator.of(context).maybePop());

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Skin?>(
    valueListenable: AppScope.of(context).skin,
    builder: (context, skin, _) => _page(context, FollowingBarLook.of(skin)),
  );

  Widget _page(BuildContext context, FollowingBarLook look) {
    final model = _model!;
    final inset = MediaQuery.paddingOf(context).bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: look.lightStatus ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: ColoredBox(
        color: LiveTabTheme.followingPage,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Bar(look: look, title: model.answered ? '${model.total}人正在直播' : '', onBack: _back),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _scrolled,
                  child: CustomScrollView(
                    key: const ValueKey('live-following-list'),
                    controller: _scroll,
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    slivers: [
                      ReleaseRefreshControl(
                        refreshTriggerPullDistance: refreshTrigger,
                        refreshIndicatorExtent: refreshRoom,
                        onRefresh: _pull,
                      ),
                      if (model.cards.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding: EdgeInsets.only(bottom: inset),
                            child: Center(child: _state(model)),
                          ),
                        )
                      else ...[
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: LiveTabTheme.followingSide),
                          sliver: SliverLayoutBuilder(
                            builder: (context, constraints) {
                              final column = (constraints.crossAxisExtent - LiveTabTheme.followingGap) / 2;
                              return SliverGrid(
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: LiveTabTheme.followingGap,
                                  crossAxisSpacing: LiveTabTheme.followingGap,
                                  mainAxisExtent: LiveFollowedCard.height(column),
                                ),
                                delegate: SliverChildBuilderDelegate((context, index) {
                                  final card = model.cards[index];
                                  return LiveFollowedCard(
                                    key: ValueKey('live-following-card-${card.roomId}'),
                                    card: card,
                                    onOpen: (source) => _open(card, source),
                                  );
                                }, childCount: model.cards.length),
                              );
                            },
                          ),
                        ),
                        SliverToBoxAdapter(child: _footer(model)),
                        SliverToBoxAdapter(child: SizedBox(height: inset)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _state(LiveFollowingModel model) {
    if (model.error case final error? when !model.loadingFirst) {
      return _Failure(message: error, onRetry: () => unawaited(model.retry()));
    }
    if (model.answered && !model.loadingFirst) {
      return _Words(LiveFollowingPage.emptyMessage, key: const ValueKey('live-following-empty'));
    }
    return const LoadingTvState(key: ValueKey('live-following-loading'));
  }

  Widget _footer(LiveFollowingModel model) {
    final error = model.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LiveTabTheme.footerPad),
      child: Center(
        child: error != null
            ? _Failure(message: error, onRetry: () => unawaited(model.retry()))
            : model.loadingMore
            ? const SizedBox(
                height: LiveTabTheme.footerLine,
                child: CupertinoActivityIndicator(
                  key: ValueKey('live-following-more'),
                  radius: LiveTabTheme.spinnerRadius,
                ),
              )
            // 206 draws nothing under the last card once the list has ended.
            : const SizedBox(height: LiveTabTheme.footerLine),
      ),
    );
  }
}

/// The bar in the following pages' look: ‹, the title in the middle and 全…注 at the right.
class _Bar extends StatelessWidget {
  const _Bar({required this.look, required this.title, required this.onBack});

  final FollowingBarLook look;
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    const half = LiveTabTheme.followingBackTarget / 2;
    return ColoredBox(
      key: const ValueKey('live-following-bar'),
      color: look.fill,
      child: SizedBox(
        height: top + FollowingListTheme.barRow,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: top,
              height: FollowingListTheme.rowCentre * 2,
              child: Center(
                child: liveLine(
                  title,
                  liveStyle(LiveTabTheme.followingTitleText, look.ink),
                  key: const ValueKey('live-following-title'),
                ),
              ),
            ),
            Positioned(
              left: LiveTabTheme.followingBackCentre - half,
              top: top + FollowingListTheme.rowCentre - half,
              width: LiveTabTheme.followingBackTarget,
              height: LiveTabTheme.followingBackTarget,
              child: Semantics(
                button: true,
                label: '返回',
                onTap: onBack,
                excludeSemantics: true,
                child: GestureDetector(
                  key: const ValueKey('live-following-back'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onBack,
                  child: Center(
                    child: SizedBox(
                      width: LiveTabTheme.followingBackWidth,
                      height: LiveTabTheme.followingBackHeight,
                      child: CustomPaint(painter: LiveChevronPainter(color: look.ink, left: true)),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: LiveTabTheme.followingActionRight - LiveTabTheme.sectionInset,
              top: top + FollowingListTheme.rowCentre - half,
              height: LiveTabTheme.followingBackTarget,
              child: Semantics(
                button: true,
                label: '全部关注',
                onTap: () => showToast(context, '暂未开放'),
                excludeSemantics: true,
                child: GestureDetector(
                  key: const ValueKey('live-following-filter'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showToast(context, '暂未开放'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: LiveTabTheme.sectionInset),
                    child: Center(child: Text('全…注', style: liveStyle(LiveTabTheme.followingActionText, look.ink))),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
        key: const ValueKey('live-following-error'),
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
          key: const ValueKey('live-following-retry'),
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
