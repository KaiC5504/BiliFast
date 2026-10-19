import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app/app_environment.dart';
import '../app/app_scope.dart';
import '../app/swipe_back_route.dart';
import '../app/zoom_back_route.dart';
import '../playback/playback_controller.dart';
import '../shared/paste_button.dart';
import '../shared/remote_image.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import '../video/video_route.dart';
import 'avatar_page.dart';
import 'feed_card.dart';
import 'feed_model.dart';
import 'recent_store.dart';

/// 首页 (01, port of HomeView.swift): the avatar and the link field, the 推荐 tab and its feed. A pasted link opens
/// its video page; the avatar opens its page (49), with 设置, the shortcuts and the last of 最近打开.
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.developerPage, this.initialLink});

  /// Builds the developer page (dev builds), passed on to 设置 through the avatar's page; null leaves 开发者 out.
  final WidgetBuilder? developerPage;

  /// Opened as if pasted once home is up (`--play=<BV or link>` on the PC).
  final String? initialLink;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late AppServices _services;
  FeedModel? _feed;
  final _link = TextEditingController();
  final _focus = FocusNode();
  String _lastText = '';
  bool _opening = false;

  /// Whether the feed on screen was fetched logged in; null until the first account check has answered.
  bool? _feedSignedIn;

  AppEnvironment get _environment => _services.environment;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_feed != null) return;
    _services = AppScope.of(context);
    final feed = FeedModel(client: _environment.client);
    _feed = feed;
    unawaited(feed.refresh());
    _environment.addListener(_accountChanged);
    _accountChanged();
    final link = widget.initialLink;
    if (link != null) WidgetsBinding.instance.addPostFrameCallback((_) => _open(link));
  }

  @override
  void dispose() {
    _environment.removeListener(_accountChanged);
    _feed?.dispose();
    _link.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Logging in or out changes what 推荐 recommends; the first check at launch does not.
  void _accountChanged() {
    final bool signedIn;
    switch (_environment.account) {
      case AccountUnknown():
        return;
      case LoggedIn():
        signedIn = true;
      case LoggedOut() || LoginExpired():
        signedIn = false;
    }
    final previous = _feedSignedIn;
    _feedSignedIn = signedIn;
    if (previous != null && previous != signedIn) unawaited(_refreshFeed());
  }

  /// A refresh that fails with cards on screen keeps them and says why in a toast.
  Future<void> _refreshFeed() async {
    final failure = await _feed?.refresh();
    if (failure != null && mounted) showToast(context, failure);
  }

  /// Back on home from a pushed page, an account check that failed is tried again, as Swift's HomeView.task did on
  /// every return; one still running is left to answer.
  Future<void> _visit(Future<void> pushed) async {
    await pushed;
    if (mounted && _environment.account is AccountUnknown && _environment.accountCheckFailed) {
      await _environment.refreshAccount();
    }
  }

  void _openAvatarPage() {
    final page = SwipeBackPageRoute<void>(builder: (_) => AvatarPage(developerPage: widget.developerPage));
    unawaited(_visit(Navigator.of(context).push(page)));
  }

  void _textChanged(String text) {
    final grew = text.length - _lastText.length;
    _lastText = text;
    // A paste lands as one big change; typing adds a character at a time.
    if (grew > 1 && LinkParser.parse(text) != null) {
      _focus.unfocus();
      unawaited(_open(text));
    }
  }

  void _pasted(String text) {
    if (!mounted) return;
    if (text.isEmpty) {
      showToast(context, '剪贴板里没有链接');
      return;
    }
    unawaited(_open(text));
  }

  Future<void> _open(String text) async {
    if (_opening) return;
    final link = LinkParser.parse(text);
    if (link == null) {
      showToast(context, BiliError.invalidLink.userMessage);
      return;
    }
    setState(() => _opening = true);
    try {
      VideoDetail? resolved;
      final (view, pageNumber) = await resolveVideoLink(_environment.client, link, onDetail: (d) => resolved = d);
      if (!mounted) return;
      Logger.shared.info(LogCategory.ui, 'open', {'bvid': view.bvid, 'pages': view.pages.length});
      // Handed to the page so its open asks for nothing again and keeps the 合集.
      final detail = resolved?.bvid == view.bvid ? resolved : null;
      final match = view.pages.where((page) => page.page == pageNumber).firstOrNull;
      if (match != null) {
        _go(view, match, detail);
      } else if (view.pages.length > 1) {
        // The spinner would otherwise wait behind the sheet for as long as it is up.
        setState(() => _opening = false);
        await _choosePart(view, detail);
      } else if (view.pages.firstOrNull case final first?) {
        _go(view, first, detail);
      } else {
        showToast(context, '该视频没有可播放的分P');
      }
      _link.clear();
      _lastText = '';
    } catch (error) {
      Logger.shared.warn(LogCategory.ui, 'open failed', {'error': '$error'});
      if (mounted) showToast(context, requestFailureMessage(error, fallback: '打开视频失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _choosePart(VideoView view, VideoDetail? detail) async {
    final page = await showCupertinoModalPopup<VideoPage>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('选择分P'),
        message: Text(view.title),
        actions: [
          for (final page in view.pages)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(context).pop(page),
              child: Text('P${page.page} ${page.part}', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
      ),
    );
    if (page != null && mounted) _go(view, page, detail);
  }

  void _go(VideoView view, VideoPage page, VideoDetail? detail) {
    _services.recents.add(
      RecentVideo(
        bvid: view.bvid,
        cid: page.cid,
        title: view.title,
        part: page.part,
        page: page.page,
        pageCount: view.pages.length,
        cover: detail?.cover,
        duration: page.duration,
      ),
    );
    final route = VideoRoute(bvid: view.bvid, cid: page.cid, title: view.title, view: view, detail: detail);
    unawaited(_visit(openVideoPage(context, route)));
  }

  void _openCard(FeedCard card, ZoomSource source) => unawaited(
    _visit(
      openVideoPage(context, VideoRoute(bvid: card.bvid, title: card.title, cover: card.cover, zoomSource: source)),
    ),
  );

  /// Logged out it goes to the login page and sends nothing; an account still being checked tries, and goes there
  /// only if Bilibili answers that it needs a login.
  Future<void> _watchLater(FeedCard card) async {
    if (_environment.account case LoggedOut() || LoginExpired()) {
      await _services.loginGate.request(context);
      return;
    }
    try {
      await _environment.client.addToWatchLater(aid: card.aid);
      if (mounted) showToast(context, '已添加至稍后再看');
    } catch (error) {
      if (error is BiliError && error.needsLogin) {
        if (mounted) await _services.loginGate.request(context);
        return;
      }
      Logger.shared.warn(LogCategory.ui, 'watch later failed', {'error': '$error'});
      if (mounted) showToast(context, requestFailureMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: BiliColors.pageGrey,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Column(
              children: [
                ColoredBox(
                  color: BiliColors.card,
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        ListenableBuilder(
                          listenable: _environment,
                          builder: (context, _) => _TopRow(
                            link: _link,
                            focus: _focus,
                            face: _environment.face,
                            opening: _opening,
                            onAvatar: _openAvatarPage,
                            onChanged: _textChanged,
                            onSubmit: _open,
                            onPaste: _pasted,
                          ),
                        ),
                        const _RecommendTab(),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 0.5, thickness: 0.5, color: BiliColors.divider),
                Expanded(
                  child: _FeedGrid(feed: _feed!, onOpen: _openCard, onWatchLater: _watchLater, onRefresh: _refreshFeed),
                ),
              ],
            ),
            IgnorePointer(
              child: Center(
                child: _Presence(
                  visible: _opening,
                  duration: still ? Duration.zero : const Duration(milliseconds: 220),
                  reverseDuration: still ? Duration.zero : const Duration(milliseconds: 180),
                  builder: (context, animation) => ScaleTransition(
                    scale: Tween(begin: 0.85, end: 1.0).animate(animation),
                    child: FadeTransition(
                      opacity: animation,
                      child: Container(
                        key: const ValueKey('opening'),
                        padding: const EdgeInsets.all(BiliMetrics.openingPadding),
                        decoration: BoxDecoration(
                          color: BiliColors.toastFill,
                          borderRadius: BorderRadius.circular(BiliMetrics.toastRadius),
                        ),
                        child: const CupertinoActivityIndicator(
                          radius: BiliMetrics.openingSpinner / 2,
                          color: BiliColors.panelText,
                        ),
                      ),
                    ),
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

/// Builds its child only while [visible] or animating out, so nothing in it (a spinner above all) keeps ticking once
/// it has gone.
class _Presence extends StatefulWidget {
  const _Presence({
    required this.visible,
    required this.duration,
    this.reverseDuration,
    required this.builder,
  });

  final bool visible;
  final Duration duration;
  final Duration? reverseDuration;
  final Widget Function(BuildContext context, Animation<double> animation) builder;

  @override
  State<_Presence> createState() => _PresenceState();
}

class _PresenceState extends State<_Presence> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    reverseDuration: widget.reverseDuration,
    value: widget.visible ? 1 : 0,
  )..addStatusListener(_statusChanged);
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );

  void _statusChanged(AnimationStatus status) {
    if (status.isDismissed && mounted) setState(() {});
  }

  @override
  void didUpdateWidget(_Presence oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller
      ..duration = widget.duration
      ..reverseDuration = widget.reverseDuration;
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        unawaited(_controller.forward());
      } else {
        unawaited(_controller.reverse());
      }
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _controller.isDismissed ? const SizedBox.shrink() : widget.builder(context, _curved);
}

/// The account's avatar; a grey head until the account has a face.
class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.face, required this.size});

  final String? face;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = face;
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: url != null && url.isNotEmpty
            ? RemoteImage.avatar(url)
            : ColoredBox(
                color: BiliColors.pageGrey,
                child: Icon(Icons.person, size: size * 0.55, color: BiliColors.divider),
              ),
      ),
    );
  }
}

/// The avatar and the rounded link field (01's search field).
class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.link,
    required this.focus,
    required this.face,
    required this.opening,
    required this.onAvatar,
    required this.onChanged,
    required this.onSubmit,
    required this.onPaste,
  });

  final TextEditingController link;
  final FocusNode focus;
  final String? face;
  final bool opening;
  final VoidCallback onAvatar;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmit;
  final ValueChanged<String> onPaste;

  /// iOS's own edit menu: its Paste reads the clipboard without the "Allow Paste" alert that Flutter's toolbar
  /// brings up.
  static Widget _editMenu(BuildContext context, EditableTextState state) => SystemContextMenu.isSupported(context)
      ? SystemContextMenu.editableText(editableTextState: state)
      : AdaptiveTextSelectionToolbar.editableText(editableTextState: state);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: BiliMetrics.topRowHeight,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.topRowMargin),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: '账号',
            child: GestureDetector(
              key: const ValueKey('home-avatar'),
              onTap: onAvatar,
              child: _AccountAvatar(face: face, size: BiliMetrics.homeAvatar),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: focus.requestFocus,
              child: Container(
                height: BiliMetrics.linkFieldHeight,
                padding: const EdgeInsets.only(left: 12, right: 2),
                decoration: ShapeDecoration(
                  shape: StadiumBorder(side: BorderSide(color: BiliColors.secondaryText, width: 0.67)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: BiliMetrics.linkFieldIcon, color: BiliColors.secondaryText),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('home-link'),
                        controller: link,
                        focusNode: focus,
                        enabled: !opening,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.go,
                        contextMenuBuilder: _editMenu,
                        onChanged: onChanged,
                        onSubmitted: onSubmit,
                        style: const TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.text),
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: '粘贴链接或BV号',
                          hintStyle: TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.secondaryText),
                        ),
                      ),
                    ),
                    ListenableBuilder(
                      listenable: link,
                      builder: (context, _) => link.text.isEmpty
                          ? PasteButton(key: const ValueKey('home-paste'), enabled: !opening, onText: onPaste)
                          : IconButton(
                              key: const ValueKey('home-clear'),
                              onPressed: () {
                                link.clear();
                                onChanged('');
                              },
                              tooltip: '清空',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.cancel,
                                size: BiliMetrics.linkClearIcon,
                                color: BiliColors.divider,
                              ),
                            ),
                    ),
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

/// 01's tab row, with only 推荐 and that one selected.
class _RecommendTab extends StatelessWidget {
  const _RecommendTab();

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    selected: true,
    child: Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Column(
        children: [
          const Text(
            '推荐',
            style: TextStyle(fontSize: BiliMetrics.tabText, fontWeight: FontWeight.w600, color: BiliColors.pink),
          ),
          const SizedBox(height: 5),
          Container(
            width: BiliMetrics.tabIndicatorWidth,
            height: BiliMetrics.tabIndicatorHeight,
            decoration: BoxDecoration(color: BiliColors.pink, borderRadius: BorderRadius.circular(2)),
          ),
        ],
      ),
    ),
  );
}

class _FeedGrid extends StatefulWidget {
  const _FeedGrid({required this.feed, required this.onOpen, required this.onWatchLater, required this.onRefresh});

  final FeedModel feed;
  final void Function(FeedCard card, ZoomSource source) onOpen;
  final void Function(FeedCard card) onWatchLater;
  final Future<void> Function() onRefresh;

  @override
  State<_FeedGrid> createState() => _FeedGridState();
}

class _FeedGridState extends State<_FeedGrid> {
  static const _skeletons = 6;

  /// The next page is asked for once fewer than this many rows of cards are left below the screen.
  static const _rowsAhead = 2;

  /// Cards appearing in the same frame come in this far apart, the later ones all at the last step.
  static const _staggerStep = Duration(milliseconds: 45);
  static const _staggerSteps = 6;

  final _scroll = ScrollController();

  /// Cards that have made their entrance; one rebuilt or scrolled back into view just shows.
  final _entered = <String>{};
  int _batch = 0;
  double _rowExtent = 0;

  @override
  void initState() {
    super.initState();
    widget.feed.addListener(_feedChanged);
  }

  @override
  void didUpdateWidget(_FeedGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.feed, widget.feed)) {
      oldWidget.feed.removeListener(_feedChanged);
      widget.feed.addListener(_feedChanged);
    }
  }

  @override
  void dispose() {
    widget.feed.removeListener(_feedChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _feedChanged() {
    setState(() {});
    // A page too short to scroll leaves the end on screen with no scrolling to notice it; look once it is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _loadMoreNearEnd(_scroll.position);
    });
  }

  bool _scrolled(ScrollNotification notification) {
    if (notification.depth == 0) _loadMoreNearEnd(notification.metrics);
    return false;
  }

  void _loadMoreNearEnd(ScrollMetrics metrics) {
    if (!widget.feed.canLoadMore || !metrics.hasContentDimensions) return;
    if (metrics.extentAfter >= _rowExtent * _rowsAhead) return;
    // A scroll notification can come mid-layout, where the feed's change must not rebuild anything yet.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.feed.canLoadMore) unawaited(widget.feed.loadMore());
      });
    } else {
      unawaited(widget.feed.loadMore());
    }
  }

  Duration _nextStagger() {
    if (_batch == 0) WidgetsBinding.instance.addPostFrameCallback((_) => _batch = 0);
    return _staggerStep * math.min(_batch++, _staggerSteps);
  }

  @override
  Widget build(BuildContext context) {
    final feed = widget.feed;
    final scaler = MediaQuery.textScalerOf(context);
    final still = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = BiliMetrics.feedSpacing;
        final width = (constraints.maxWidth - spacing * 3) / 2;
        final extent = FeedCardSize.height(width, scaler);
        _rowExtent = extent + spacing;
        final grid = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          mainAxisExtent: extent,
        );
        final cards = feed.cards;
        final loadingFirst = cards.isEmpty && (feed.loading || feed.error == null);
        return AnimatedSwitcher(
          duration: still ? Duration.zero : const Duration(milliseconds: 320),
          layoutBuilder: (current, previous) =>
              Stack(fit: StackFit.expand, children: [...previous, ?current]),
          child: loadingFirst
              ? CustomScrollView(
                  key: const ValueKey('feed-skeleton'),
                  physics: const NeverScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.all(spacing),
                      sliver: SliverGrid(
                        gridDelegate: grid,
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => const FeedCardSkeleton(),
                          childCount: _skeletons,
                        ),
                      ),
                    ),
                  ],
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: _scrolled,
                  child: CustomScrollView(
                    key: const ValueKey('feed'),
                    controller: _scroll,
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    slivers: [
                      CupertinoSliverRefreshControl(onRefresh: widget.onRefresh),
                      if (cards.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: _RetryMessage(
                              message: feed.error ?? FeedModel.emptyMessage,
                              messageKey: const ValueKey('feed-error'),
                              onRetry: feed.retry,
                            ),
                          ),
                        )
                      else ...[
                        SliverPadding(
                          padding: const EdgeInsets.all(spacing),
                          sliver: SliverGrid(
                            gridDelegate: grid,
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final card = cards[index];
                                final enter = !still && _entered.add(card.bvid);
                                return _Entrance(
                                  key: ValueKey('feed-card-${card.bvid}'),
                                  delay: enter ? _nextStagger() : null,
                                  child: FeedCardView(
                                    card: card,
                                    onOpen: (source) => widget.onOpen(card, source),
                                    onWatchLater: () => widget.onWatchLater(card),
                                  ),
                                );
                              },
                              childCount: cards.length,
                              findChildIndexCallback: (key) {
                                if (key is! ValueKey<String>) return null;
                                final index = cards.indexWhere((card) => 'feed-card-${card.bvid}' == key.value);
                                return index < 0 ? null : index;
                              },
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(child: _Footer(feed: feed)),
                      ],
                    ],
                  ),
                ),
        );
      },
    );
  }
}

/// A card's first appearance: after [delay] it fades in and rises into place. Without a delay it just shows, as it
/// does when rebuilt or scrolled back into view.
class _Entrance extends StatefulWidget {
  const _Entrance({super.key, required this.delay, required this.child});

  final Duration? delay;
  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> with SingleTickerProviderStateMixin {
  static const _rise = Duration(milliseconds: 380);

  AnimationController? _controller;
  CurvedAnimation? _curve;
  Animation<Offset>? _offset;

  @override
  void initState() {
    super.initState();
    final delay = widget.delay;
    if (delay == null) return;
    final total = delay + _rise;
    final controller = AnimationController(vsync: this, duration: total);
    final curve = CurvedAnimation(
      parent: controller,
      curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: Curves.easeOutCubic),
    );
    _controller = controller;
    _curve = curve;
    _offset = Tween(begin: const Offset(0, BiliMetrics.cardRise), end: Offset.zero).animate(curve);
    unawaited(controller.forward());
  }

  @override
  void dispose() {
    _curve?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = _curve;
    final offset = _offset;
    if (curve == null || offset == null) return widget.child;
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(position: offset, child: widget.child),
    );
  }
}

/// Under the cards: the spinner while the next page loads, or why it didn't with 重试.
class _Footer extends StatelessWidget {
  const _Footer({required this.feed});

  final FeedModel feed;

  @override
  Widget build(BuildContext context) {
    final error = feed.error;
    return Padding(
      padding: const EdgeInsets.only(top: BiliMetrics.rowGap, bottom: BiliMetrics.sectionGap + BiliMetrics.rowGap),
      child: Center(
        child: error != null
            ? _RetryMessage(message: error, messageKey: const ValueKey('feed-error'), onRetry: feed.retry)
            : feed.exhausted
            ? _RetryMessage(message: FeedModel.endMessage, messageKey: const ValueKey('feed-end'), onRetry: feed.retry)
            : SizedBox.square(
                dimension: BiliMetrics.feedSpinnerRadius * 2,
                child: feed.loading
                    ? const CupertinoActivityIndicator(
                        key: ValueKey('feed-more'),
                        radius: BiliMetrics.feedSpinnerRadius,
                      )
                    : null,
              ),
      ),
    );
  }
}

class _RetryMessage extends StatelessWidget {
  const _RetryMessage({required this.message, required this.messageKey, required this.onRetry});

  final String message;
  final Key messageKey;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(BiliMetrics.sectionGap),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          key: messageKey,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.secondaryText),
        ),
        const SizedBox(height: BiliMetrics.rowGap),
        CupertinoButton(
          key: const ValueKey('feed-retry'),
          onPressed: onRetry,
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(BiliMetrics.pillHeight),
          child: Container(
            height: BiliMetrics.pillHeight,
            padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.sectionGap),
            alignment: Alignment.center,
            decoration: const ShapeDecoration(
              shape: StadiumBorder(side: BorderSide(color: BiliColors.pink)),
            ),
            child: const Text(
              '重试',
              style: TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.pink),
            ),
          ),
        ),
      ],
    ),
  );
}
