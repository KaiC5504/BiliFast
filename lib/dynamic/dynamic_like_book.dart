import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import 'dynamic_api.dart';

/// How a 👍 went: [LikeNeedsLogin] goes to the login gate (a -101 can come while the app still thinks it is logged
/// in), [LikeFailed] to a toast.
sealed class LikeOutcome {
  const LikeOutcome();
}

final class LikeDone extends LikeOutcome {
  const LikeDone();
}

final class LikeNeedsLogin extends LikeOutcome {
  const LikeNeedsLogin();
}

final class LikeFailed extends LikeOutcome {
  const LikeFailed(this.message);

  final String message;
}

/// Every 👍 on a post, wherever it was pressed, so a feed card, the face sheet, a space's 动态 and the post page agree.
/// Optimistic: the change shows at once and is rolled back if Bilibili refuses it.
class DynamicLikeBook extends ChangeNotifier {
  DynamicLikeBook({required this._api, Logger? logger}) : _logger = logger ?? Logger.shared;

  final DynamicApi _api;
  final Logger _logger;
  final _states = <String, ({bool liked, int count})>{};
  final _sending = <String>{};

  /// [stat] with this run's 👍 applied.
  DynamicStat stat(String id, DynamicStat stat) {
    final state = _states[id];
    return state == null ? stat : stat.copyWith(liked: state.liked, like: state.count);
  }

  /// Turns the 👍 over; one already out for [id] is [LikeDone] at once.
  Future<LikeOutcome> toggle(String id, DynamicStat from) async {
    if (!_sending.add(id)) return const LikeDone();
    final before = stat(id, from);
    final on = !before.liked;
    _states[id] = (liked: on, count: (before.like + (on ? 1 : -1)).clamp(0, 1 << 31));
    notifyListeners();
    try {
      await _api.like(id, on: on);
      return const LikeDone();
    } on Object catch (error) {
      _states[id] = (liked: before.liked, count: before.like);
      notifyListeners();
      _logger.warn(LogCategory.api, 'dynamic like failed', {'error': '${error.runtimeType}'});
      if (error is BiliError && error.needsLogin) return const LikeNeedsLogin();
      return LikeFailed(error is BiliError ? error.userMessage : '操作失败');
    } finally {
      _sending.remove(id);
    }
  }

  /// Another account's 👍 aren't this one's.
  void clear() {
    if (_states.isEmpty) return;
    _states.clear();
    notifyListeners();
  }
}
