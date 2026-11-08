import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/danmaku.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../playback/danmaku_feed.dart';
import '../video/page_api.dart';
import 'block_rule_store.dart';
import 'danmaku_settings_store.dart';
import 'mask/mask_feed.dart';
import 'send/danmaku_send_model.dart';

/// The video and part a danmaku goes to.
typedef DanmakuTarget = ({String bvid, int cid});

/// Makes a part's 人像防挡 feed ([createMaskFeed]; tests pass their own).
typedef MaskFeedFactory = MaskFeed Function(DanmakuMaskInfo info, {required MaskFetch fetch, Logger? logger});

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
    this.maskInfo,
    this.maskFetch,
    this._maskFeeds = createMaskFeed,
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
    settings.addListener(_followMask);
    maskInfo?.addListener(_followMask);
    _followMask();
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

  /// The part's 人像防挡 mask, as the page's session learns it ([PlayerSession.danmakuMask]); null on pages without
  /// one (offline).
  final ValueListenable<DanmakuMaskInfo?>? maskInfo;

  /// How [mask] reads the mask file.
  final MaskFetch? maskFetch;

  /// 人像防挡's feed for the part playing, while 人像防挡 is on and the part has a mask.
  ValueListenable<MaskFeed?> get mask => _mask;
  final _mask = ValueNotifier<MaskFeed?>(null);
  final MaskFeedFactory _maskFeeds;
  DanmakuMaskInfo? _maskFor;

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

  /// The page's login, for whatever on the page needs the account: the danmaku list's 👍, 添加屏蔽词.
  void requestLogin() {
    if (!_disposed) _requestLogin();
  }

  /// Posts a danmaku at the playhead and shows it at once: the message to show, empty when the login was asked for
  /// instead, or null once it went out. Only null clears the draft, so it is still there after a login.
  Future<String?> send(String text, DanmakuStyle style) async {
    if (!loggedIn) {
      requestLogin();
      return '';
    }
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
      if (error.needsLogin) {
        requestLogin();
        return '';
      }
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
    _rulesRetry?.cancel();
    _rulesRetry = Timer(rulesRetryDelay, () {
      if (!_disposed && loggedIn) unawaited(rules.refresh());
    });
  }

  void _applyFilter() => _feed.setFilter(settings.value.filter, rules.rules);

  /// One feed per mask while 人像防挡 is on. [mask] lets go of the old feed before it is disposed, so nothing draws
  /// from a disposed one.
  void _followMask() {
    final fetch = maskFetch;
    final info = settings.value.peopleShield && fetch != null ? maskInfo?.value : null;
    final current = _maskFor;
    if (identical(info, current) || (info != null && current != null && _sameMask(info, current))) return;
    _maskFor = info;
    final old = _mask.value;
    _mask.value = info == null ? null : _maskFeeds(info, fetch: fetch!, logger: _logger);
    old?.dispose();
    if (info != null) _logger.info(LogCategory.player, 'danmaku mask', {'cid': info.cid, 'fps': info.fps});
  }

  /// The same file asked for again (the part's player info read once more): its feed carries on.
  static bool _sameMask(DanmakuMaskInfo a, DanmakuMaskInfo b) => a.cid == b.cid && a.time == b.time && a.url == b.url;

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

  /// After a login from the page. The account may have been logged in all along with cookies Bilibili stopped
  /// taking, so this doesn't wait for the account to change; the store's 10-minute cache and its one ask in flight
  /// keep it from asking twice.
  void refreshAccount() {
    if (_disposed) return;
    _feed.ownMid = _accountMid();
    _wasLoggedIn = loggedIn;
    if (loggedIn) unawaited(_refreshRules());
  }

  @override
  void dispose() {
    _disposed = true;
    _accountChanges?.removeListener(_accountChanged);
    _rulesRetry?.cancel();
    settings.removeListener(_applyFilter);
    rules.removeListener(_applyFilter);
    _feed.removeListener(_feedChanged);
    settings.removeListener(_followMask);
    maskInfo?.removeListener(_followMask);
    final feed = _mask.value;
    _mask.value = null;
    feed?.dispose();
    _mask.dispose();
    sendOpen.dispose();
    sender.dispose();
    super.dispose();
  }
}
