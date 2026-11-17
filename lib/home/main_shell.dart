import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_scope.dart';
import '../app/form_factor.dart';
import '../dynamic/follow_tab/face_sheet.dart';
import '../dynamic/follow_tab/follow_badge.dart';
import '../dynamic/follow_tab/follow_tab_page.dart';
import '../me/me_page.dart';
import '../message/message_model.dart';
import '../message/message_page.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import '../settings/icon_notice.dart';
import '../sideload/sideload_prompts.dart';
import '../skin/skin.dart';
import '../skin/skin_model.dart';
import 'home_page.dart';
import 'home_tab_bar.dart';

/// The bottom bar's places: 首页, 关注, 消息 and 我的 kept alive side by side, the bar under them (01, 02, 127). A bar dressed
/// by the equipped 装扮 lies over the pages' bottom instead, so they show behind its picture (109, 110). 关注's face
/// sheet lies over everything, the bar included (139), and a sideloaded install's launch alert over that. 消息's
/// counts start with the shell; their total is the bar's badge (211), and a tapped 私信 notification shows 消息. 关注's
/// count (238) starts with it too, and isn't drawn while 关注 shows. The iPad has no 消息 and no count on 动态.
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.developerPage, this.initialLink, @visibleForTesting this.skin});

  final WidgetBuilder? developerPage;

  /// Passed to 首页 (`--play=` on the PC).
  final String? initialLink;

  /// The equipped 装扮 in place of [AppServices.skin], for 首页, the bar and 我的 alike.
  final SkinModel? skin;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final _reloads = _Reloads();
  final _followReloads = _Reloads();
  final _followCountReloads = _Reloads();
  final _messageReloads = _Reloads();
  final _faceSheet = FaceSheetController();
  HomeTab _tab = HomeTab.home;
  MessageModel? _messages;
  FollowBadge? _followBadge;

  /// What the bar's counts follow: 消息's, and on the phone 关注's.
  late Listenable _counts;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_messages != null) return;
    final services = AppScope.of(context);
    final messages = _messages = services.messages;
    _counts = messages;
    // The iPad's bar has no 消息 and no count on 动态: nothing asks for either, and a tapped 私信 notification only
    // opens the app.
    if (FormFactor.of(context).isPad) return;
    messages
      ..start()
      ..showRequests.addListener(_showMessages);
    final followBadge = _followBadge = services.followBadge;
    followBadge.start();
    _counts = Listenable.merge([messages, followBadge]);
  }

  @override
  void dispose() {
    _messages?.showRequests.removeListener(_showMessages);
    _reloads.dispose();
    _followReloads.dispose();
    _followCountReloads.dispose();
    _messageReloads.dispose();
    _faceSheet.dispose();
    super.dispose();
  }

  /// Already on 消息, the page checks again by itself.
  void _showMessages() {
    if (!mounted) return;
    _faceSheet.close();
    if (_tab != HomeTab.messages) setState(() => _tab = HomeTab.messages);
  }

  /// 首页 again on 首页 refreshes 推荐, and 关注 again on 关注 its list, closing the face sheet first (a guess: no
  /// recording); coming back from another place only shows it, where it was. 关注 opened over its count also clears
  /// the count and refreshes its list.
  void _tapped(HomeTab tab) {
    switch (tab) {
      case HomeTab.home when _tab == HomeTab.home:
        _reloads.request();
      case HomeTab.follow when _tab == HomeTab.follow:
        _faceSheet.close();
        _followReloads.request();
      case HomeTab.messages when _tab == HomeTab.messages:
        _messageReloads.request();
      case HomeTab.home || HomeTab.follow || HomeTab.messages || HomeTab.mine:
        if (tab == _tab) return;
        _faceSheet.close();
        if (tab == HomeTab.follow && (_followBadge?.count ?? 0) > 0) {
          _followBadge!.clear();
          _followCountReloads.request();
        }
        setState(() => _tab = tab);
      case HomeTab.post:
        showToast(context, '暂未开放');
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Skin?>(
    valueListenable: widget.skin ?? AppScope.of(context).skin,
    builder: (context, skin, _) => _build(context, skin),
  );

  Widget _build(BuildContext context, Skin? skin) {
    final mine = _tab == HomeTab.mine;
    final follow = _tab == HomeTab.follow;
    final messages = _tab == HomeTab.messages;
    final media = MediaQuery.of(context);
    final dressed = HomeTabBar.dresses(skin);
    final bar = HomeTabBar.heightOf(context) + media.padding.bottom;
    // Under a dressed bar the pages run to the screen's bottom, inset by the stock bar, so lists end above its row
    // and scroll on behind its picture.
    final pages = dressed
        ? media.copyWith(
            padding: media.padding.copyWith(bottom: bar),
            viewPadding: media.viewPadding.copyWith(bottom: bar),
          )
        : media.removePadding(removeBottom: true);
    return Material(
      color: HomeTabBarTheme.bar,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: dressed ? 0 : bar,
            child: MediaQuery(
              data: pages,
              child: IndexedStack(
                index: switch (_tab) {
                  HomeTab.home || HomeTab.post => 0,
                  HomeTab.follow => 1,
                  HomeTab.messages => 2,
                  HomeTab.mine => 3,
                },
                sizing: StackFit.expand,
                children: [
                  _Place(
                    shown: _tab == HomeTab.home,
                    child: HomePage(
                      developerPage: widget.developerPage,
                      initialLink: widget.initialLink,
                      reloads: _reloads,
                      skin: skin,
                    ),
                  ),
                  _Place(
                    shown: follow,
                    child: FollowTabPage(
                      active: follow,
                      faceSheet: _faceSheet,
                      reloads: _followReloads,
                      countReloads: _followCountReloads,
                      skin: skin,
                    ),
                  ),
                  _Place(
                    shown: messages,
                    child: MessagePage(active: messages, skin: skin, reloads: _messageReloads),
                  ),
                  _Place(
                    shown: mine,
                    child: AnnotatedRegion<SystemUiOverlayStyle>(
                      value: SystemUiOverlayStyle.dark,
                      child: MePage(active: mine, developerPage: widget.developerPage, skin: widget.skin),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ListenableBuilder(
              listenable: _counts,
              builder: (context, _) => HomeTabBar(
                selected: _tab,
                onTap: _tapped,
                onPartition: () => showToast(context, '暂未开放'),
                skin: skin,
                messageBadge: _messages!.badge,
                followBadge: follow ? 0 : _followBadge?.count ?? 0,
              ),
            ),
          ),
          Positioned.fill(child: FaceSheetLayer(controller: _faceSheet)),
          Positioned.fill(child: SideloadPrompts(model: AppScope.of(context).sideload)),
          IconNoticePrompt(notice: AppScope.of(context).iconNotice, host: AppScope.of(context).appIcons),
        ],
      ),
    );
  }
}

/// A place kept alive while hidden: still, and out of Hero flights, which an [IndexedStack] doesn't stop. Otherwise a
/// hidden 推荐 cover flies over 我的 to or from a pushed page holding the same tag (a space row's `cover-<bvid>`).
class _Place extends StatelessWidget {
  const _Place({required this.shown, required this.child});

  final bool shown;
  final Widget child;

  @override
  Widget build(BuildContext context) => TickerMode(
    enabled: shown,
    child: HeroMode(enabled: shown, child: child),
  );
}

class _Reloads extends ChangeNotifier {
  void request() => notifyListeners();
}
