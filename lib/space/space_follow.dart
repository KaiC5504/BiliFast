import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../video/actions/actions_model.dart' show ActionsModel;
import '../video/page_api.dart';
import 'follow_book.dart';

/// 关注 for one uploader on the sheet and the space: what the web card says, changed at once on a tap, given back
/// when Bilibili refuses, and passed to every page through [FollowBook].
class SpaceFollow extends ChangeNotifier {
  SpaceFollow({
    required this.mid,
    required this._api,
    required this._book,
    required this._isLoggedIn,
    required this._requestLogin,
    required this._toast,
    this._following,
    Logger? logger,
  }) : _logger = logger ?? Logger.shared {
    _book.addListener(_bookChanged);
  }

  final int mid;
  final PageApi _api;
  final FollowBook _book;
  final bool Function() _isLoggedIn;
  final VoidCallback _requestLogin;
  final void Function(String message) _toast;
  final Logger _logger;

  bool? _following;
  bool _busy = false;
  bool _disposed = false;

  /// Null until the card answers; logged out it is false.
  bool? get following => _following;

  bool get busy => _busy;

  /// Asks the web card once; a failure leaves [following] unknown, which draws as not following.
  Future<void> load() async {
    if (!_isLoggedIn()) {
      _set(false);
      return;
    }
    try {
      final card = await _api.uploaderCard(mid: mid);
      if (!_busy) _set(card.following);
    } catch (error) {
      _logger.warn(LogCategory.api, 'space follow state failed', {'error': '$error'});
    }
  }

  /// Follows or unfollows. Logged out, it asks for the login instead. Unfollowing asks no question here: the space's
  /// 取消关注 sheet is the confirm.
  Future<void> toggle() async {
    if (!_isLoggedIn()) {
      _requestLogin();
      return;
    }
    if (_busy) return;
    final on = !(_following ?? false);
    final before = _following;
    _busy = true;
    _set(on);
    try {
      await _api.follow(mid: mid, on: on);
      _book.changed(mid, following: on);
      _say(on ? '关注成功' : '取消关注成功');
    } catch (error) {
      _following = before;
      _logger.warn(LogCategory.api, 'space follow failed', {'error': '$error'});
      if (error is BiliError && error.needsLogin) {
        if (!_disposed) _requestLogin();
      } else {
        _say(ActionsModel.failureMessage(error));
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _bookChanged() {
    final change = _book.last;
    if (change == null || change.mid != mid || _busy) return;
    _set(change.following);
  }

  void _set(bool value) {
    if (_following == value) return;
    _following = value;
    _notify();
  }

  void _say(String message) {
    if (!_disposed) _toast(message);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _book.removeListener(_bookChanged);
    super.dispose();
  }
}
