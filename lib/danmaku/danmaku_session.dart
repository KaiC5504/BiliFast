import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/danmaku.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../playback/danmaku_feed.dart';
import '../video/page_api.dart';
import 'block_rule_store.dart';
import 'danmaku_settings_store.dart';
import 'send/danmaku_send_model.dart';

/// The video and part a danmaku goes to.
typedef DanmakuTarget = ({String bvid, int cid});

/// One page's danmaku, as every piece of it reaches them (BiliNative `DanmakuController` and `DanmakuSendModel`'s
/// page side): the settings and 屏蔽词 applied to the feed, the send bar, sending, and 当前弹幕列表's actions.
class DanmakuSession extends ChangeNotifier {
  DanmakuSession({
    required this._feed,
    required this.settings,
    required this.rules,
    required this.api,
    required this._target,
    required this._position,
    required this._isLoggedIn,
    required this._isVip,
    required this._accountMid,
    required this._requestLogin,
    this._accountChanges,
    Logger? logger,
  }) : _logger = logger ?? Logger.shared {
    sender = DanmakuSendModel(send);
    _feed.ownMid = _accountMid();
    _wasLoggedIn = loggedIn;
    _accountChanges?.addListener(_accountChanged);
    _applyFilter();
    _closed = _feed.closed;
    settings.addListener(_applyFilter);
    rules.addListener(_applyFilter);
    _feed.addListener(_feedChanged);
    if (loggedIn) unawaited(_refreshRules());
  }

  /// How long after a failed page-open refresh of the 屏蔽词 it is tried once more.
  static const rulesRetryDelay = Duration(seconds: 15);

  final DanmakuFeed _feed;
  final DanmakuSettingsStore settings;
  final BlockRuleStore rules;
  final PageApi api;
  final DanmakuTarget? Function() _target;
  final double Function() _position;
  final bool Function() _isLoggedIn;
  final bool Function() _isVip;
  final int Function() _accountMid;
  final VoidCallback _requestLogin;

  /// Fires when the account may have changed; a page opened before the launch's account check answered learns the
  /// account here.
  final Listenable? _accountChanges;
  final Logger _logger;
  bool _wasLoggedIn = false;
  bool _closed = false;
  bool _disposed = false;
  Timer? _rulesRetry;

  /// The send bar's draft, kept while the bar is closed.
  late final DanmakuSendModel sender;

  /// The send bar is up.
  final ValueNotifier<bool> sendOpen = ValueNotifier(false);

  bool get loggedIn => _isLoggedIn();

  bool get isVip => _isVip();

  DanmakuTarget? get target => _target();

  /// The uploader closed danmaku for this video: the fields read UP主已关闭弹幕 and nothing sends.
  bool get closed => _feed.closed;

  /// Opens the send bar; logged out it asks for the login instead.
  void openSend() {
    if (!loggedIn) {
      _requestLogin();
      return;
    }
    sendOpen.value = true;
  }

  void closeSend() => sendOpen.value = false;

  static const needLogin = '请先登录';

  /// Posts a danmaku at the playhead and shows it at once: the message to show, or null once it went out. A login
  /// problem comes back as a message too, so the bar stays up with the draft rather than closing as if it went.
  Future<String?> send(String text, DanmakuStyle style) async {
    if (!loggedIn) return needLogin;
    final message = text.trim();
    if (message.isEmpty) return null;
    if (closed) return 'UP主已关闭弹幕';
    if (style.gradient && !isVip) return '开通大会员后可使用';
    final target = this.target;
    if (target == null) return '视频还没有加载好';
    final draft = DanmakuDraft(
      cid: target.cid,
      bvid: target.bvid,
      text: message,
      mode: style.position.mode,
      fontSize: style.size.fontSize,
      color: style.gradient ? 0xFFFFFF : style.color,
      gradient: style.gradient,
      progressMs: (_position() * 1000).round(),
    );
    final int dmid;
    try {
      dmid = await api.postDanmaku(draft);
    } on BiliError catch (error) {
      _logger.warn(LogCategory.api, 'danmaku post failed', {'error': '$error'});
      if (error.needsLogin) return needLogin;
      // Bilibili words its refusals for the user (frequency, banned words, level); they're shown word for word.
      if (error case BiliAPIError(:final message) when message.isNotEmpty) return message;
      return '发送失败，请检查网络后重试';
    } catch (error) {
      _logger.warn(LogCategory.api, 'danmaku post failed', {'error': '${error.runtimeType}'});
      return '发送失败，请检查网络后重试';
    }
    _feed.addOwn(draft, dmid: dmid);
    return null;
  }

  /// 当前弹幕列表: what has shown up to the playhead, latest last.
  List<DanmakuElem> recent() => _feed.recent((_position() * 1000).round());

  /// 当前弹幕列表's 屏蔽弹幕.
  void hide(DanmakuElem elem) => _feed.hide(elem);

  /// Failing, the account's 屏蔽词 would be off until the next page, so it is tried once more.
  Future<void> _refreshRules() async {
    final failure = await rules.refresh();
    if (failure == null || _disposed || !loggedIn) return;
    _rulesRetry = Timer(rulesRetryDelay, () {
      if (loggedIn) unawaited(rules.refresh());
    });
  }

  void _applyFilter() => _feed.setFilter(settings.value.filter, rules.rules);

  void _feedChanged() {
    if (_feed.closed == _closed) return;
    _closed = _feed.closed;
    notifyListeners();
  }

  void _accountChanged() {
    _feed.ownMid = _accountMid();
    final now = loggedIn;
    if (now && !_wasLoggedIn) unawaited(_refreshRules());
    _wasLoggedIn = now;
  }

  @override
  void dispose() {
    _disposed = true;
    _accountChanges?.removeListener(_accountChanged);
    _rulesRetry?.cancel();
    settings.removeListener(_applyFilter);
    rules.removeListener(_applyFilter);
    _feed.removeListener(_feedChanged);
    sendOpen.dispose();
    sender.dispose();
    super.dispose();
  }
}
