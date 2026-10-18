import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_environment.dart';
import '../app/app_scope.dart';
import '../app/swipe_back_route.dart';
import '../playback/playback_controller.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import '../video/video_route.dart';
import 'avatar_menu.dart';
import 'feed_card.dart';
import 'feed_model.dart';
import 'recent_store.dart';
import 'recents_page.dart';

/// 首页 (01, port of HomeView.swift): the avatar and the link field, the 推荐 tab and its feed. A pasted link opens
/// its video page; the avatar drops down the account, 最近打开 and, in dev builds, 开发者.
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.developerPage, this.initialLink});

  /// Builds the developer page (dev builds); null leaves 开发者 out of the menu.
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
  bool _menuOpen = false;

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
    if (previous != null && previous != signedIn) unawaited(_feed?.refresh());
  }

  void _toggleMenu() => setState(() => _menuOpen = !_menuOpen);

  void _closeMenu() {
    if (_menuOpen) setState(() => _menuOpen = false);
  }

  void _menuSelected(AvatarMenuItem item) {
    _closeMenu();
    switch (item) {
      case AvatarMenuItem.recents:
        unawaited(Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => const RecentsPage())));
      case AvatarMenuItem.developer:
        final page = widget.developerPage;
        if (page != null) unawaited(Navigator.of(context).push(SwipeBackPageRoute<void>(builder: page)));
      case AvatarMenuItem.history:
        break;
    }
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

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) showToast(context, '剪贴板里没有链接');
      return;
    }
    await _open(text);
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
      final (view, pageNumber) = await resolveVideoLink(_environment.client, link);
      if (!mounted) return;
      Logger.shared.info(LogCategory.ui, 'open', {'bvid': view.bvid, 'pages': view.pages.length});
      final match = view.pages.where((page) => page.page == pageNumber).firstOrNull;
      if (match != null) {
        _go(view, match);
      } else if (view.pages.length > 1) {
        await _choosePart(view);
      } else if (view.pages.firstOrNull case final first?) {
        _go(view, first);
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

  Future<void> _choosePart(VideoView view) async {
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
    if (page != null && mounted) _go(view, page);
  }

  void _go(VideoView view, VideoPage page) {
    _services.recents.add(
      RecentVideo(
        bvid: view.bvid,
        cid: page.cid,
        title: view.title,
        part: page.part,
        page: page.page,
        pageCount: view.pages.length,
      ),
    );
    unawaited(openVideoPage(context, VideoRoute(bvid: view.bvid, cid: page.cid, title: view.title)));
  }

  void _openCard(FeedCard card) =>
      unawaited(openVideoPage(context, VideoRoute(bvid: card.bvid, title: card.title, cover: card.cover)));

  Future<void> _watchLater(FeedCard card) async {
    try {
      await _environment.client.addToWatchLater(aid: card.aid);
      if (mounted) showToast(context, '已添加至稍后再看');
    } catch (error) {
      Logger.shared.warn(LogCategory.ui, 'watch later failed', {'error': '$error'});
      if (mounted) showToast(context, requestFailureMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
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
                            onAvatar: _toggleMenu,
                            onChanged: _textChanged,
                            onSubmit: _open,
                            onPaste: _paste,
                          ),
                        ),
                        const _RecommendTab(),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 0.5, thickness: 0.5, color: BiliColors.divider),
                Expanded(
                  child: _FeedGrid(feed: _feed!, onOpen: _openCard, onWatchLater: _watchLater),
                ),
              ],
            ),
            // The menu drops from the avatar over a dimmed page; a tap outside closes it.
            IgnorePointer(
              ignoring: !_menuOpen,
              child: AnimatedOpacity(
                opacity: _menuOpen ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: GestureDetector(
                  key: const ValueKey('menu-scrim'),
                  onTap: _closeMenu,
                  child: const ColoredBox(color: BiliColors.scrim, child: SizedBox.expand()),
                ),
              ),
            ),
            Positioned(
              left: BiliMetrics.topRowMargin,
              top: top + BiliMetrics.topRowHeight + 2,
              child: IgnorePointer(
                ignoring: !_menuOpen,
                child: AnimatedScale(
                  scale: _menuOpen ? 1 : 0.6,
                  alignment: Alignment.topLeft,
                  duration: const Duration(milliseconds: 240),
                  curve: _menuOpen ? Curves.easeOutBack : Curves.easeIn,
                  child: AnimatedOpacity(
                    opacity: _menuOpen ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: ListenableBuilder(
                      listenable: _environment,
                      builder: (context, _) => AvatarMenu(
                        environment: _environment,
                        developer: widget.developerPage != null,
                        onSelect: _menuSelected,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: Center(
                child: AnimatedScale(
                  scale: _opening ? 1 : 0.85,
                  duration: const Duration(milliseconds: 220),
                  child: AnimatedOpacity(
                    opacity: _opening ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Container(
                      key: const ValueKey('opening'),
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: BiliColors.toastFill,
                        borderRadius: BorderRadius.circular(BiliMetrics.toastRadius),
                      ),
                      child: const SizedBox.square(
                        dimension: 32,
                        child: CircularProgressIndicator(strokeWidth: 3, color: BiliColors.panelText),
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
  final VoidCallback onPaste;

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
              child: AccountAvatar(face: face, size: BiliMetrics.homeAvatar),
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
                    const Icon(Icons.search, size: 17, color: BiliColors.secondaryText),
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
                          ? IconButton(
                              key: const ValueKey('home-paste'),
                              onPressed: opening ? null : onPaste,
                              tooltip: '粘贴',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.content_paste_rounded, size: 18, color: BiliColors.pink),
                            )
                          : IconButton(
                              key: const ValueKey('home-clear'),
                              onPressed: () {
                                link.clear();
                                onChanged('');
                              },
                              tooltip: '清空',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.cancel, size: 18, color: BiliColors.divider),
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

class _FeedGrid extends StatelessWidget {
  const _FeedGrid({required this.feed, required this.onOpen, required this.onWatchLater});

  final FeedModel feed;
  final void Function(FeedCard card) onOpen;
  final void Function(FeedCard card) onWatchLater;

  static const _skeletons = 6;

  /// Asks for the next page after this frame: asking while building would rebuild mid-build.
  void _loadMoreSoon() => WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(feed.loadMore()));

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return ListenableBuilder(
      listenable: feed,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          const spacing = BiliMetrics.feedSpacing;
          final width = (constraints.maxWidth - spacing * 3) / 2;
          final grid = SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            mainAxisExtent: FeedCardSize.height(width, scaler),
          );
          final cards = feed.cards;
          final error = feed.error;
          return CustomScrollView(
            key: const ValueKey('feed'),
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              CupertinoSliverRefreshControl(onRefresh: feed.refresh),
              if (cards.isEmpty && error != null && !feed.loading)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: _RetryMessage(message: error, onRetry: feed.refresh),
                  ),
                )
              else if (cards.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.all(spacing),
                  sliver: SliverGrid(
                    gridDelegate: grid,
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => const FeedCardSkeleton(),
                      childCount: _skeletons,
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
                        // Starts the next page a few cards before the end, so scrolling rarely waits.
                        if (index >= cards.length - 4 && error == null) _loadMoreSoon();
                        final card = cards[index];
                        return FeedCardView(
                          key: ValueKey('feed-card-${card.bvid}'),
                          card: card,
                          onOpen: () => onOpen(card),
                          onWatchLater: () => onWatchLater(card),
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
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: BiliMetrics.rowGap, bottom: 24),
                    child: Center(
                      child: error != null
                          ? _RetryMessage(message: error, onRetry: feed.loadMore)
                          : _FooterLoader(onShown: _loadMoreSoon),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The spinner under the last cards; also asks for the next page by itself, in case the last cards were already on
/// screen when the page before added nothing.
class _FooterLoader extends StatefulWidget {
  const _FooterLoader({required this.onShown});

  final VoidCallback onShown;

  @override
  State<_FooterLoader> createState() => _FooterLoaderState();
}

class _FooterLoaderState extends State<_FooterLoader> {
  @override
  void initState() {
    super.initState();
    widget.onShown();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 22,
    child: CircularProgressIndicator(strokeWidth: 2, color: BiliColors.secondaryText),
  );
}

class _RetryMessage extends StatelessWidget {
  const _RetryMessage({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(BiliMetrics.sectionGap),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          key: const ValueKey('feed-error'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.secondaryText),
        ),
        const SizedBox(height: BiliMetrics.rowGap),
        OutlinedButton(
          key: const ValueKey('feed-retry'),
          onPressed: onRetry,
          style: OutlinedButton.styleFrom(
            foregroundColor: BiliColors.pink,
            side: const BorderSide(color: BiliColors.pink),
          ),
          child: const Text('重试'),
        ),
      ],
    ),
  );
}
