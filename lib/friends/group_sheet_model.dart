import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../home/feed_model.dart' show requestFailureMessage;
import '../search/results/video_row.dart' show searchLogReason;
import '../video/actions/actions_model.dart' show ActionsModel;
import 'friends_api.dart';

/// 设置分组 for one person (167): the account's 分组 (默认分组 left out: it is where nothing ticked goes), which of them
/// hold the person, ticks changed on the sheet, and the save.
class GroupSheetModel extends ChangeNotifier {
  GroupSheetModel({
    required this._api,
    required this.mid,
    required this._groups,
    Logger? logger,
  }) : _logger = logger ?? Logger.shared;

  final FriendsApi _api;
  final int mid;

  /// The account's 分组, which the page asks once.
  final Future<List<RelationTag>> Function() _groups;
  final Logger _logger;

  List<RelationTag>? _shown;
  Set<int> _was = const {};
  Set<int> _chosen = {};
  String? _error;
  bool _saving = false;
  bool _disposed = false;

  /// Null until both answers are in.
  List<RelationTag>? get groups => _shown;
  Set<int> get chosen => _chosen;
  String? get error => _error;
  bool get saving => _saving;

  /// Nothing ticked: the save puts the person back in 默认分组 (保存至默认分组).
  bool get toDefault => _chosen.isEmpty;

  /// The ticks differ from what Bilibili has, so a save sends them.
  bool get changed => _shown != null && !setEquals(_chosen, _was);

  Future<void> load() async {
    if (_disposed) return;
    _error = null;
    _shown = null;
    _notify();
    try {
      final groups = await _groups();
      final current = await _api.tagsOf(mid);
      if (_disposed) return;
      _shown = [
        for (final group in groups)
          if (group.id != RelationTag.defaultGroup) group,
      ];
      _was = {...current};
      _chosen = {...current};
    } catch (error) {
      if (_disposed) return;
      _logger.warn(LogCategory.api, 'friends groups failed', {'error': searchLogReason(error)});
      _error = requestFailureMessage(error);
    }
    _notify();
  }

  void toggle(int id) {
    if (_disposed || _shown == null || _saving) return;
    _chosen = _chosen.contains(id) ? ({..._chosen}..remove(id)) : {..._chosen, id};
    _notify();
  }

  /// Sends the ticks, and only when [changed]. Null when saved (or nothing to save), else what to tell the user.
  Future<String?> save() async {
    if (_disposed || _saving || !changed) return null;
    _saving = true;
    _notify();
    try {
      await _api.setTags(mid, _chosen);
      _was = {..._chosen};
      return null;
    } catch (error) {
      _logger.warn(LogCategory.api, 'friends groups save failed', {'error': searchLogReason(error)});
      return ActionsModel.failureMessage(error);
    } finally {
      _saving = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
