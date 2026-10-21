import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../search/results/video_row.dart' show searchLogReason;
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

  /// Bumped by every tap, by the end of every run of calls and by every change made elsewhere, so a card answer asked
  /// before one of them is dropped.
  int _generation = 0;

  /// Null until the card answers; logged out it is false.
  bool? get following => _following;

  bool get busy => _busy;

  /// Asks the web card once; a failure leaves [following] unknown, which draws as not following.
  Future<void> load() async {
    if (!_isLoggedIn()) {
      _set(false);
      return;
    }
    final generation = _generation;
    try {
      final card = await _api.uploaderCard(mid: mid);
      if (!_busy && generation == _generation) _set(card.following);
    } catch (error) {
      _logger.warn(LogCategory.api, 'space follow state failed', {'error': searchLogReason(error)});
    }
  }

  /// After a login: what was said logged out is no longer known, so a tap before the card answers asks it first
  /// rather than sending a follow the account may already have.
  Future<void> reload() {
    if (!_busy && _following != null) {
      _following = null;
      _notify();
    }
    return load();
  }

  /// Follows or unfollows. Logged out, it asks for the login instead. Asks no question: callers confirm an unfollow
  /// first. With [following] unknown it asks the card before sending anything. A tap while a call is out shows at once
  /// and goes out when that call returns, if it still differs from what Bilibili took; one call at a time.
  Future<void> toggle() async {
    if (!_isLoggedIn()) {
      _requestLogin();
      return;
    }
    _generation += 1;
    final next = !(_following ?? false);
    if (_busy) {
      _set(next);
      return;
    }
    var taken = _following;
    _busy = true;
    _set(next);
    try {
      taken ??= (await _api.uploaderCard(mid: mid)).following;
      while (_following != taken) {
        final on = _following!;
        await _api.follow(mid: mid, on: on);
        taken = on;
        _book.changed(mid, following: on);
        // A change of mind still to send would make this one's toast wrong a moment later.
        if (_following == on) _say(on ? '关注成功' : '取消关注成功');
      }
    } catch (error) {
      _following = taken;
      _logger.warn(LogCategory.api, taken == null ? 'space follow state failed' : 'space follow failed', {
        'error': searchLogReason(error),
      });
      if (error is BiliError && error.needsLogin) {
        if (!_disposed) _requestLogin();
      } else {
        _say(ActionsModel.failureMessage(error));
      }
    } finally {
      _busy = false;
      _generation += 1;
      _notify();
    }
  }

  void _bookChanged() {
    final change = _book.last;
    if (change == null || change.mid != mid || _busy) return;
    _generation += 1;
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
