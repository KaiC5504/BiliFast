import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:bili_core/api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app/app_environment.dart';
import '../app/app_scope.dart';
import '../dynamic/following/following_glyphs.dart' show FollowingBackPainter;
import '../dynamic/following/following_page.dart' show FollowingBarLook, followingStyle;
import '../search/search_glyphs.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import '../skin/skin.dart';
import '../space/space_route.dart';
import '../space/uploader_tap.dart';
import 'fake_friends_api.dart';
import 'friends_api.dart';
import 'friends_model.dart';
import 'friends_route.dart';
import 'friends_rows.dart';
import 'friends_sheets.dart';

String orderLabel(FollowingOrder order) => order == FollowingOrder.mostVisited ? '最近访问' : '最近关注';

/// 我的好友 (163-168): the bar, 关注 and 粉丝 side by side under their tab row. 关注 has 搜索我的关注, the count and
/// the order (a tap swaps 最近关注 and 最近访问), and the followings; 粉丝 the fans, asked once its tab shows. A row
/// opens the person's space; a grey pill brings up 166's sheet (设置分组 → 167, 取消关注), a pink one follows.
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key, this.initialTab = FriendsTab.following, this.api, this.skin});

  final FriendsTab initialTab;

  /// The client's by default; the demo fake in a `--fake-account` run.
  final FriendsApi? api;
  final ValueListenable<Skin?>? skin;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  FriendsModel? _modelOrNull;
  FriendsApi? _api;
  AppEnvironment? _environment;
  late final _pager = PageController(initialPage: widget.initialTab.index);
  late FriendsTab _tab = widget.initialTab;
  final _field = TextEditingController();
  final _focus = FocusNode();
  final _followingScroll = ScrollController();
  final _resultsScroll = ScrollController();
  final _fansScroll = ScrollController();

  /// Who 166's sheet and 167's are up for.
  final _followedSheet = ValueNotifier<RelationUser?>(null);
  final _groupSheet = ValueNotifier<RelationUser?>(null);
  late final _sheets = Listenable.merge([_followedSheet, _groupSheet]);

  FriendsModel get _model => _modelOrNull!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_modelOrNull != null) return;
    final services = AppScope.of(context);
    final environment = _environment = services.environment..addListener(_accountChanged);
    final api = _api =
        widget.api ?? (environment.fake ? FakeFriendsApi.demo() : ClientFriendsApi(environment.client));
    _modelOrNull = FriendsModel(
      api: api,
      mid: () => environment.mid,
      book: services.follows,
      toast: _toast,
      requestLogin: () => unawaited(_login()),
      searchPause: FollowingListTheme.searchPause,
    )..start();
    if (_tab == FriendsTab.fans) _model.showFans();
    _focus.addListener(_focusChanged);
    // A launch check that failed is tried again, as 首页 does on coming back.
    if (environment.account is AccountUnknown && environment.accountCheckFailed) _checkAccount();
  }

  @override
  void dispose() {
    _environment?.removeListener(_accountChanged);
    _modelOrNull?.dispose();
    _pager.dispose();
    _field.dispose();
    _focus.dispose();
    _followingScroll.dispose();
    _resultsScroll.dispose();
    _fansScroll.dispose();
    _followedSheet.dispose();
    _groupSheet.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (mounted) showToast(context, message);
  }

  void _back() => unawaited(Navigator.of(context).maybePop());

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  bool get _loggedOut => switch (_environment!.account) {
    LoggedOut() || LoginExpired() => true,
    LoggedIn() || AccountUnknown() => false,
  };

  /// The account known starts the lists; logging out empties them and puts the sheets away.
  void _accountChanged() {
    if (!mounted) return;
    if (_loggedOut) {
      _model.signOut();
      _closeSheets();
    } else {
      _model.start();
    }
    setState(() {});
  }

  void _checkAccount() => unawaited(_environment!.refreshAccount());

  Future<void> _login() async {
    final loggedIn = await AppScope.of(context).loginGate.request(context);
    if (loggedIn && mounted) _model.loggedIn();
  }

  /// In place of the tabs' content: logged out or a login expired under a list, a 登录 through the login gate; an
  /// account check that failed, its 重试.
  Widget? _accountState() {
    if (_loggedOut || _model.needsLogin) {
      return FriendsMessage(
        key: const ValueKey('friends-logged-out'),
        message: '登录后查看我的好友',
        action: '登录',
        actionKey: const ValueKey('friends-login'),
        onAction: () => unawaited(_login()),
      );
    }
    final environment = _environment!;
    if (environment.account is AccountUnknown && environment.accountCheckFailed && environment.mid == null) {
      return FriendsMessage(
        key: const ValueKey('friends-account-failed'),
        message: environment.accountLabel,
        action: '重试',
        actionKey: const ValueKey('friends-account-retry'),
        onAction: _checkAccount,
      );
    }
    return null;
  }

  void _select(FriendsTab tab) {
    if (!_pager.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pager.jumpToPage(tab.index);
    } else {
      unawaited(_pager.animateToPage(tab.index, duration: FriendsTheme.tabMotion, curve: Curves.easeOutCubic));
    }
  }

  void _pageChanged(int index) {
    final tab = FriendsTab.values[index];
    if (tab == _tab) return;
    setState(() => _tab = tab);
    if (tab == FriendsTab.fans) {
      _focus.unfocus();
      _model.showFans();
    }
  }

  bool get _cancelShown => _focus.hasFocus || _field.text.isNotEmpty;

  void _textChanged(String text) {
    setState(() {});
    _model.textChanged(text);
  }

  void _clear() {
    _field.clear();
    _textChanged('');
  }

  /// 取消 (168): the search goes, the field empties and the keyboard leaves.
  void _cancelSearch() {
    _field.clear();
    _model.textChanged('');
    _focus.unfocus();
    setState(() {});
  }

  void _open(RelationUser user) {
    _focus.unfocus();
    final person = user.user;
    unawaited(openSpace(context, UploaderRef(mid: person.mid, name: person.name, face: person.face)));
  }

  void _pill(RelationUser user) {
    _focus.unfocus();
    if (_model.isFollowing(user)) {
      _followedSheet.value = user;
    } else {
      unawaited(_model.setFollowing(user, on: true));
    }
  }

  bool get _sheetOpen => _followedSheet.value != null || _groupSheet.value != null;

  void _closeSheets() {
    _followedSheet.value = null;
    _groupSheet.value = null;
  }

  bool _scrolled(FriendsTab tab, ScrollNotification notification) {
    if (notification.depth == 0 && notification.metrics.axis == Axis.vertical) {
      _loadMoreNearEnd(tab, notification.metrics);
    }
    return false;
  }

  void _loadMoreNearEnd(FriendsTab tab, ScrollMetrics metrics) {
    if (!_model.lane(tab).canLoadMore || !metrics.hasContentDimensions) return;
    if (metrics.extentAfter >= FollowingListTheme.loadAhead) return;
    // A scroll notification can come mid-layout, where the model's change must not rebuild anything yet.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _model.loadMore(tab);
      });
    } else {
      _model.loadMore(tab);
    }
  }

  ScrollController _scrollOf(FriendsTab tab) => switch (tab) {
    FriendsTab.fans => _fansScroll,
    FriendsTab.following => _model.searching ? _resultsScroll : _followingScroll,
  };

  /// A page too short to scroll sends no notification, so after each answer the shown list checks whether its end
  /// shows.
  void _checkShortList() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scroll = _scrollOf(_tab);
      if (scroll.hasClients && scroll.position.hasContentDimensions) _loadMoreNearEnd(_tab, scroll.position);
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin ?? AppScope.of(context).skin;
    return ValueListenableBuilder<Skin?>(
      valueListenable: skin,
      builder: (context, skin, _) => _page(FollowingBarLook.of(skin)),
    );
  }

  Widget _page(FollowingBarLook look) {
    final top = MediaQuery.paddingOf(context).top;
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: _sheets,
      builder: (context, _) => PopScope(
        canPop: !_sheetOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _closeSheets();
        },
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: look.lightStatus ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          child: Scaffold(
            backgroundColor: FriendsTheme.page,
            resizeToAvoidBottomInset: false,
            body: DefaultTextStyle(
              style: followingStyle(FriendsTheme.nameText, FriendsTheme.name),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Bar(look: look, onBack: _back),
                      _TabRow(pager: _pager, selected: _tab, onSelect: _select),
                      Expanded(
                        child: MediaQuery.removePadding(
                          context: context,
                          removeTop: true,
                          child: ListenableBuilder(
                            listenable: Listenable.merge([_model, services.follows]),
                            builder: (context, _) {
                              _checkShortList();
                              return _accountState() ?? _tabs();
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: top + FollowingListTheme.barRow,
                    bottom: 0,
                    child: Stack(
                      children: [
                        FriendsSheetLayer(
                          open: _followedSheet,
                          name: 'sheet',
                          builder: (context, user, close) => FollowedSheet(
                            onGroups: () {
                              close();
                              _groupSheet.value = user;
                            },
                            onUnfollow: () {
                              close();
                              unawaited(_model.setFollowing(user, on: false));
                            },
                            onCancel: close,
                          ),
                        ),
                        FriendsSheetLayer(
                          open: _groupSheet,
                          name: 'groups',
                          builder: (context, user, close) => GroupSheet(
                            api: _api!,
                            mid: user.mid,
                            groups: _model.groups,
                            onNewGroup: () => _toast('暂未开放'),
                            onSaved: (sent) {
                              close();
                              if (sent) _toast('设置成功');
                            },
                            onFailed: _toast,
                            onLogin: () {
                              close();
                              unawaited(_login());
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  // The PopScope holds while a sheet is up, which turns the route's edge swipe off: this takes the
                  // same edge and puts the sheet away instead.
                  if (_sheetOpen)
                    Positioned(
                      key: const ValueKey('friends-sheet-edge'),
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: math.max(BiliMetrics.swipeBackEdge, MediaQuery.paddingOf(context).left),
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragEnd: (details) {
                          if ((details.primaryVelocity ?? 0) >= 0) _closeSheets();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabs() => PageView(
    key: const ValueKey('friends-pager'),
    controller: _pager,
    // No bounce past either tab, as the video page's pager.
    physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
    onPageChanged: _pageChanged,
    children: [
      _KeepAlive(child: _followingTab()),
      _KeepAlive(
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) => _scrolled(FriendsTab.fans, notification),
          child: FriendsLane(
            key: const ValueKey('friends-fans'),
            lane: _model.fans,
            tab: FriendsTab.fans,
            model: _model,
            scroll: _fansScroll,
            emptyTop: FriendsTheme.emptyTop,
            onRetry: () => _model.retry(FriendsTab.fans),
            onOpen: _open,
            onPill: _pill,
          ),
        ),
      ),
    ],
  );

  Widget _followingTab() {
    final searching = _model.searching;
    const fieldBottom = FriendsTheme.fieldTop + FriendsTheme.fieldHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: FriendsTheme.fieldTop),
        _SearchField(
          field: _field,
          focus: _focus,
          cancelShown: _cancelShown,
          onChanged: _textChanged,
          onSubmit: _model.submit,
          onClear: _clear,
          onCancel: _cancelSearch,
        ),
        if (searching)
          const SizedBox(height: FriendsTheme.resultsTop)
        else
          _CountRow(
            total: _model.following.loaded ? _model.following.total : null,
            order: _model.order,
            onToggle: () {
              if (_followingScroll.hasClients) _followingScroll.jumpTo(0);
              _model.toggleOrder();
            },
          ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) => _scrolled(FriendsTab.following, notification),
            child: Stack(
              children: [
                Offstage(
                  offstage: searching,
                  child: TickerMode(
                    enabled: !searching,
                    child: FriendsLane(
                      key: const ValueKey('friends-following'),
                      lane: _model.following,
                      tab: FriendsTab.following,
                      model: _model,
                      scroll: _followingScroll,
                      emptyTop: FriendsTheme.emptyTop - fieldBottom - FriendsTheme.countRow,
                      onRetry: () => _model.retry(FriendsTab.following),
                      onOpen: _open,
                      onPill: _pill,
                    ),
                  ),
                ),
                if (searching)
                  FriendsLane(
                    key: const ValueKey('friends-results'),
                    lane: _model.results,
                    tab: FriendsTab.following,
                    model: _model,
                    scroll: _resultsScroll,
                    emptyTop: FriendsTheme.emptyTop - fieldBottom - FriendsTheme.resultsTop,
                    onRetry: () => _model.retry(FriendsTab.following),
                    onOpen: _open,
                    onPill: _pill,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.look, required this.onBack});

  final FollowingBarLook look;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    const half = FollowingListTheme.backTarget / 2;
    final title = followingStyle(FriendsTheme.titleText, look.ink, line: FriendsTheme.titleLine);
    return ColoredBox(
      key: const ValueKey('friends-bar'),
      color: look.fill,
      child: SizedBox(
        height: top + FollowingListTheme.barRow,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: top,
              height: FollowingListTheme.rowCentre * 2,
              child: Center(child: friendsLine('我的好友', title, key: const ValueKey('friends-title'))),
            ),
            Positioned(
              left: FollowingListTheme.backCentreX - half,
              top: top + FollowingListTheme.rowCentre - half,
              width: FollowingListTheme.backTarget,
              height: FollowingListTheme.backTarget,
              child: Semantics(
                button: true,
                label: '返回',
                onTap: onBack,
                excludeSemantics: true,
                child: GestureDetector(
                  key: const ValueKey('friends-back'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onBack,
                  child: CustomPaint(painter: FollowingBackPainter(fill: look.fill)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 关注 and 粉丝 with the pink bar under the chosen one; through a swipe the bar follows the finger and the pink goes
/// to the nearer tab.
class _TabRow extends StatelessWidget {
  const _TabRow({required this.pager, required this.selected, required this.onSelect});

  final PageController pager;
  final FriendsTab selected;
  final ValueChanged<FriendsTab> onSelect;

  static const _labels = {FriendsTab.following: '关注', FriendsTab.fans: '粉丝'};

  double _position() {
    if (pager.hasClients && pager.position.hasContentDimensions) return pager.page ?? selected.index.toDouble();
    return selected.index.toDouble();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: FriendsTheme.tabRow + FriendsTheme.tabRule,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final middle = constraints.maxWidth / 2;
        double centreOf(FriendsTab tab) => middle + (tab.index - 0.5) * FriendsTheme.tabWidth;
        return ListenableBuilder(
          listenable: pager,
          builder: (context, _) {
            final position = _position().clamp(0.0, 1.0);
            final nearer = FriendsTab.values[position.round()];
            final underline = lerpDouble(centreOf(FriendsTab.following), centreOf(FriendsTab.fans), position)!;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (final tab in FriendsTab.values)
                  Positioned(
                    left: centreOf(tab) - FriendsTheme.tabWidth / 2,
                    width: FriendsTheme.tabWidth,
                    top: 0,
                    height: FriendsTheme.tabRow,
                    child: Semantics(
                      button: true,
                      selected: tab == selected,
                      label: _labels[tab],
                      onTap: () => onSelect(tab),
                      excludeSemantics: true,
                      child: GestureDetector(
                        key: ValueKey('friends-tab-${tab.name}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelect(tab),
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: FriendsTheme.tabLabelCentre - FriendsTheme.tabLine / 2,
                              height: FriendsTheme.tabLine,
                              child: Center(
                                child: friendsLine(
                                  _labels[tab]!,
                                  followingStyle(
                                    FriendsTheme.tabText,
                                    tab == nearer ? FriendsTheme.tabChosen : FriendsTheme.tabInk,
                                    line: FriendsTheme.tabLine,
                                  ),
                                  key: ValueKey('friends-tab-label-${tab.name}'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const Positioned(
                  left: 0,
                  right: 0,
                  top: FriendsTheme.tabRow,
                  height: FriendsTheme.tabRule,
                  child: ColoredBox(color: FriendsTheme.tabRuleInk),
                ),
                Positioned(
                  key: const ValueKey('friends-underline'),
                  left: underline - FriendsTheme.underlineWidth / 2,
                  top: FriendsTheme.underlineBottom - FriendsTheme.underlineHeight,
                  width: FriendsTheme.underlineWidth,
                  height: FriendsTheme.underlineHeight,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: FriendsTheme.tabChosen,
                      borderRadius: BorderRadius.all(Radius.circular(FriendsTheme.underlineHeight / 2)),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    ),
  );
}

/// 搜索我的关注 (163), and while it is in use (168) 取消 beside it and ⓧ once it has text.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.field,
    required this.focus,
    required this.cancelShown,
    required this.onChanged,
    required this.onSubmit,
    required this.onClear,
    required this.onCancel,
  });

  final TextEditingController field;
  final FocusNode focus;
  final bool cancelShown;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onClear;
  final VoidCallback onCancel;

  /// iOS's own edit menu: its Paste reads the clipboard without the "Allow Paste" alert that Flutter's toolbar
  /// brings up.
  static Widget _editMenu(BuildContext context, EditableTextState state) => SystemContextMenu.isSupported(context)
      ? SystemContextMenu.editableText(editableTextState: state)
      : AdaptiveTextSelectionToolbar.editableText(editableTextState: state);

  @override
  Widget build(BuildContext context) {
    final text = followingStyle(FriendsTheme.fieldText, FriendsTheme.fieldInk, line: FriendsTheme.fieldLine);
    final hint = text.copyWith(color: FriendsTheme.placeholder);
    const clearBox = FriendsTheme.clearCentre * 2;
    return SizedBox(
      height: FriendsTheme.fieldHeight,
      child: Stack(
        children: [
          Positioned(
            left: FriendsTheme.fieldInset,
            right: cancelShown ? FriendsTheme.fieldEndSearching : FriendsTheme.fieldInset,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: focus.requestFocus,
              child: DecoratedBox(
                key: const ValueKey('friends-search'),
                decoration: const ShapeDecoration(color: FriendsTheme.field, shape: StadiumBorder()),
                child: Stack(
                  children: [
                    const Positioned(
                      left: FriendsTheme.magnifierCentre - FriendsTheme.magnifier / 2,
                      width: FriendsTheme.magnifier,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: SearchGlyphIcon(
                          SearchGlyph.magnifier,
                          size: FriendsTheme.magnifier,
                          color: FriendsTheme.magnifierInk,
                        ),
                      ),
                    ),
                    Positioned(
                      left: FriendsTheme.fieldTextLeft,
                      right: clearBox,
                      top: 0,
                      bottom: 0,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextField(
                          key: const ValueKey('friends-search-field'),
                          controller: field,
                          focusNode: focus,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.search,
                          contextMenuBuilder: _editMenu,
                          cursorColor: FriendsTheme.caret,
                          onChanged: onChanged,
                          onSubmitted: (_) => onSubmit(),
                          style: text,
                          strutStyle: BiliFonts.strut(text),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            // As the decorator would draw hintText, with the strut it can't be given.
                            hint: Text(
                              '搜索我的关注',
                              style: hint,
                              strutStyle: BiliFonts.strut(hint),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (field.text.isNotEmpty)
                      Positioned(
                        right: 0,
                        width: clearBox,
                        top: 0,
                        bottom: 0,
                        child: Semantics(
                          button: true,
                          label: '清空',
                          onTap: onClear,
                          excludeSemantics: true,
                          child: GestureDetector(
                            key: const ValueKey('friends-search-clear'),
                            behavior: HitTestBehavior.opaque,
                            onTap: onClear,
                            child: const Center(
                              child: SearchGlyphIcon(
                                SearchGlyph.clear,
                                size: FriendsTheme.clear,
                                color: FriendsTheme.clearInk,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (cancelShown)
            Positioned(
              right: 0,
              width: FriendsTheme.fieldEndSearching,
              top: 0,
              bottom: 0,
              child: Semantics(
                button: true,
                label: '取消',
                onTap: onCancel,
                excludeSemantics: true,
                child: GestureDetector(
                  key: const ValueKey('friends-search-cancel'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onCancel,
                  child: Center(
                    child: friendsLine(
                      '取消',
                      followingStyle(FriendsTheme.cancelText, FriendsTheme.cancelInk, line: FriendsTheme.cancelLine),
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

/// 我的关注 N人 and, at the right, the order: a tap swaps 最近关注 and 最近访问 (163, 164).
class _CountRow extends StatelessWidget {
  const _CountRow({required this.total, required this.order, required this.onToggle});

  /// Null until the list's first page answers.
  final int? total;
  final FollowingOrder order;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final label = followingStyle(FriendsTheme.countText, FriendsTheme.countInk, line: FriendsTheme.countLine);
    final number = followingStyle(
      FriendsTheme.countNumberText,
      FriendsTheme.countNumberInk,
      line: FriendsTheme.countLine,
    );
    final sort = followingStyle(FriendsTheme.sortText, FriendsTheme.sortInk, line: FriendsTheme.sortLine);
    final total = this.total;
    return SizedBox(
      height: FriendsTheme.countRow,
      child: Stack(
        children: [
          Positioned(
            left: FriendsTheme.fieldInset,
            right: FriendsTheme.sortTarget,
            top: FriendsTheme.countCentre - FriendsTheme.countLine / 2,
            height: FriendsTheme.countLine,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('我的关注', style: label, strutStyle: BiliFonts.strut(label)),
                if (total != null) ...[
                  const SizedBox(width: FriendsTheme.countGap),
                  Text(
                    '$total人',
                    key: const ValueKey('friends-count'),
                    style: number,
                    strutStyle: BiliFonts.strut(number),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: FriendsTheme.sortTarget,
            child: Semantics(
              button: true,
              label: '排序方式，${orderLabel(order)}',
              onTap: onToggle,
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey('friends-sort'),
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                child: Stack(
                  children: [
                    Positioned(
                      right: FriendsTheme.fieldInset,
                      top: FriendsTheme.sortCentre - FriendsTheme.sortLine / 2,
                      height: FriendsTheme.sortLine,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/images/friends/list_sort_line.png',
                            width: FriendsTheme.sortGlyphWidth,
                            height: FriendsTheme.sortGlyphHeight,
                            color: FriendsTheme.sortInk,
                          ),
                          const SizedBox(width: FriendsTheme.sortGap),
                          friendsLine(orderLabel(order), sort, key: const ValueKey('friends-sort-label')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
