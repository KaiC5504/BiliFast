import 'package:bili_core/danmaku.dart';
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
// Contracts stub: slice 5's feed agent writes the parts marked so.
class DanmakuSession extends ChangeNotifier {
  DanmakuSession({
    required this._feed,
    required this.settings,
    required this.rules,
    required this.api,
    required this._target,
    required double Function() position,
    required this._isLoggedIn,
    required this._isVip,
    required int Function() accountMid,
    required this._toast,
    required this._requestLogin,
  }) {
    sender = DanmakuSendModel(send);
  }

  final DanmakuFeed _feed;
  final DanmakuSettingsStore settings;
  final BlockRuleStore rules;
  final PageApi api;
  final DanmakuTarget? Function() _target;
  final bool Function() _isLoggedIn;
  final bool Function() _isVip;
  // ignore: unused_field
  final void Function(String message) _toast;
  final VoidCallback _requestLogin;

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

  /// Posts a danmaku at the playhead and shows it at once: the message to show, or null once it went out.
  // Contracts stub.
  Future<String?> send(String text, DanmakuStyle style) async => '发弹幕将在下个版本推出';

  /// 当前弹幕列表: what has shown up to the playhead, latest last.
  // Contracts stub.
  List<DanmakuElem> recent() => const [];

  /// 当前弹幕列表's 屏蔽弹幕.
  // Contracts stub.
  void hide(DanmakuElem elem) {}

  @override
  void dispose() {
    sendOpen.dispose();
    sender.dispose();
    super.dispose();
  }
}
