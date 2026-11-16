import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_environment.dart';
import '../../app/app_scope.dart';
import '../../friends/friends_rows.dart' show FriendsMessage;
import '../../shared/toast.dart';
import '../../video/video_route.dart';
import '../message_routes.dart';
import 'feed_lane.dart';
import 'feed_sheet.dart';
import 'feed_targets.dart';

/// What the three pages share: the account (its lists start once it is known and again after a login; logged out
/// they offer 登录), toasts, opening what a row points at, the gear, and the ⋮ sheet's two calls.
mixin FeedPageState<T extends StatefulWidget> on State<T> {
  AppServices? _services;
  int _logins = 0;
  bool _wasLoggedIn = false;
  bool _askingLogin = false;

  AppServices get services => _services!;
  AppEnvironment get environment => services.environment;

  /// The page's lists, reset for another account.
  List<FeedLane<Object?>> get lanes;

  FeedOpeners get opens;

  /// The count opening the page clears in 消息; none on 新增粉丝.
  NoticeFeed? get openedFeed => null;

  /// Starts what shows once the account is known; called again when it turns logged in and after a login.
  void startLists();

  /// Once, with [services] in reach.
  void servicesReady() {}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    final services = _services = AppScope.of(context);
    _logins = services.environment.logins.value;
    _wasLoggedIn = services.environment.account is LoggedIn;
    services.environment.addListener(_accountChanged);
    services.environment.logins.addListener(_loggedIn);
    servicesReady();
    if (openedFeed case final feed?) {
      // 消息's badges listen to the count from outside this route, which is being built now.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) services.messages.feedOpened(feed);
      });
    }
    if (!loggedOut) startLists();
  }

  @override
  void dispose() {
    _services?.environment.removeListener(_accountChanged);
    _services?.environment.logins.removeListener(_loggedIn);
    super.dispose();
  }

  bool get loggedOut => switch (environment.account) {
    LoggedOut() || LoginExpired() => true,
    LoggedIn() || AccountUnknown() => false,
  };

  /// The environment speaks on every account check (each return to the app): only the turn to logged in starts the
  /// lists, so a list that failed waits for 重试 or a pull rather than asking again unpressed.
  void _accountChanged() {
    if (!mounted) return;
    setState(() {});
    final loggedIn = environment.account is LoggedIn;
    final arrived = loggedIn && !_wasLoggedIn;
    _wasLoggedIn = loggedIn;
    if (arrived) startLists();
  }

  /// A login, perhaps of another account: every list starts again.
  void _loggedIn() {
    final logins = environment.logins.value;
    if (logins == _logins || !mounted) return;
    _logins = logins;
    for (final lane in lanes) {
      lane.reset();
    }
    startLists();
  }

  void toast(String message) {
    if (mounted) showToast(context, message);
  }

  /// Every logged-out press comes here: the login page, unless the account is still being checked and turns out
  /// logged in. Nothing pressed is sent afterwards.
  Future<void> login() async {
    if (_askingLogin || !mounted) return;
    _askingLogin = true;
    try {
      if (environment.account is AccountUnknown) {
        await environment.refreshAccount();
        if (!mounted) return;
        switch (environment.account) {
          case LoggedIn():
            return;
          case AccountUnknown():
            toast('账号确认失败，请稍后重试');
            return;
          case LoggedOut() || LoginExpired():
            break;
        }
      }
      final loggedIn = await services.loginGate.request(context);
      if (!loggedIn || !mounted) return;
      for (final lane in lanes) {
        if (lane.needsLogin) lane.reset();
      }
      startLists();
    } finally {
      _askingLogin = false;
    }
  }

  /// A press that needs the account: true when it reads logged in, else the press goes to [login] instead.
  bool canAct() {
    if (environment.account is LoggedIn) return true;
    unawaited(login());
    return false;
  }

  /// The gear: [kind]'s 消息提醒, which are the account's.
  void openSettings(NoticeSettingKind kind) {
    if (canAct()) unawaited(openNoticePicker(context, kind));
  }

  /// In place of a list: 登录 while logged out or after a list answered -101.
  Widget? accountState(FeedLane<Object?> lane) {
    if (!loggedOut && !lane.needsLogin) return null;
    return FriendsMessage(
      key: const ValueKey('feed-logged-out'),
      message: '登录后查看消息',
      action: '登录',
      actionKey: const ValueKey('feed-login'),
      onAction: () => unawaited(login()),
    );
  }

  void open(FeedTarget target) {
    switch (target) {
      case FeedVideo(:final bvid, :final comment):
        unawaited(opens.openVideo(context, VideoRoute(bvid: bvid, comment: comment)));
      case FeedPost(:final id, :final toComments):
        unawaited(opens.openPost(context, id: id, toComments: toComments));
      case FeedNowhere():
        toast('暂未开放');
    }
  }

  /// 不再通知 (214).
  Future<void> mute(FeedSheetTarget target) async {
    if (!canAct()) return;
    try {
      await services.messageApi.muteNotice(target.feed, target.id);
      muted(target);
      toast('设置成功');
    } catch (error) {
      _failed('mute', error);
    }
  }

  /// 删除 (214): the row goes once Bilibili agrees.
  Future<void> delete(FeedSheetTarget target, FeedLane<Object?> lane) async {
    if (!canAct()) return;
    try {
      await services.messageApi.deleteNotice(target.feed, target.id);
      lane.remove(target.id);
      toast('删除成功');
    } catch (error) {
      _failed('delete', error);
    }
  }

  /// A row muted with 不再通知.
  void muted(FeedSheetTarget target) {}

  void _failed(String action, Object error) {
    Logger.shared.warn(LogCategory.api, 'message feed $action failed', {'error': feedLogReason(error)});
    if (error is BiliError && error.needsLogin) {
      unawaited(login());
    } else {
      toast(failureMessage(error));
    }
  }

  /// Bilibili's own words for a refusal it explains, else the network's.
  static String failureMessage(Object error) {
    if (error case BiliAPIError(:final code, :final message) when message.isNotEmpty && code > 0) return message;
    if (error is BiliError && error is! BiliNetworkError) return error.userMessage;
    return '网络连接失败，请稍后再试';
  }
}
