import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../../home/feed_model.dart' show requestFailureMessage;
import '../page_api.dart';
import 'actions_model.dart';
import 'video_actions.dart';

/// The account's folders for one video (BiliNative `FavouriteSheet.swift`'s model): which hold it now, which the user
/// has ticked, and folders made here. It starts loading when made.
class FavouritesModel extends ChangeNotifier implements FavouriteFolders {
  FavouritesModel({required this._api, required this._aid, required this._mid, required this._actions, Logger? logger})
    : _logger = logger ?? Logger.shared {
    unawaited(reload());
  }

  final PageApi _api;
  final int _aid;
  final int? Function() _mid;
  final VideoActions _actions;
  final Logger _logger;

  bool _loading = true;
  String? _error;
  List<FavFolder> _folders = const [];
  Set<int> _ticked = {};

  /// The folders that held the video when the list loaded.
  Set<int> _original = {};

  /// 新建收藏夹 works while the list loads or after it failed, and a list that lands later must keep these, ticked as
  /// the user left them.
  final List<FavFolder> _created = [];
  Future<String?>? _creating;

  /// A reload replaces an older load's answer.
  int _generation = 0;
  bool _disposed = false;

  @override
  bool get loading => _loading;

  @override
  String? get error => _error;

  @override
  List<FavFolder> get folders => List.unmodifiable(_folders);

  @override
  bool isTicked(int folderId) => _ticked.contains(folderId);

  /// What [commit] sends: the folders to add the video to and to take it out of, in list order.
  ({List<int> add, List<int> remove}) get change {
    final order = [for (final folder in _folders) folder.id];
    return (
      add: [
        for (final id in order)
          if (_ticked.contains(id) && !_original.contains(id)) id,
      ],
      remove: [
        for (final id in order)
          if (_original.contains(id) && !_ticked.contains(id)) id,
      ],
    );
  }

  @override
  Future<void> reload() async {
    final mine = ++_generation;
    _loading = true;
    _error = null;
    _notify();
    final mid = _mid();
    if (mid == null) {
      _loading = false;
      _error = '请先登录';
      _notify();
      return;
    }
    try {
      final list = [...await _api.favouriteFolders(mid: mid, aid: _aid)];
      if (_disposed || mine != _generation) return;
      final listed = {for (final folder in list) folder.id};
      for (final folder in _created) {
        if (!listed.contains(folder.id)) list.insert(_afterDefault(list), folder);
      }
      final made = {for (final folder in _created) folder.id};
      _folders = list;
      _original = {
        for (final folder in list)
          if (folder.contains && !made.contains(folder.id)) folder.id,
      };
      _ticked = _original.union(_ticked.intersection(made));
    } catch (error) {
      if (_disposed || mine != _generation) return;
      _logger.warn(LogCategory.api, 'favourite folders failed', {'error': '$error'});
      _error = requestFailureMessage(error);
    }
    _loading = false;
    _notify();
  }

  @override
  void toggle(int folderId) {
    if (!_ticked.remove(folderId)) _ticked.add(folderId);
    _notify();
  }

  /// Lists the new folder after the default one and ticks it. A second tap while one is being made answers with the
  /// first's outcome rather than making two.
  @override
  Future<String?> create(String title, {required bool isPrivate}) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return Future.value('请输入收藏夹名称');
    return _creating ??= _create(trimmed, isPrivate).whenComplete(() => _creating = null);
  }

  Future<String?> _create(String title, bool isPrivate) async {
    try {
      final folder = await _api.createFolder(title: title, isPrivate: isPrivate);
      if (_disposed) return null;
      _folders = [..._folders]..insert(_afterDefault(_folders), folder);
      _created.add(folder);
      _ticked.add(folder.id);
      _notify();
      return null;
    } catch (error) {
      _logger.warn(LogCategory.api, 'create folder failed', {'error': '$error'});
      return ActionsModel.failureMessage(error);
    }
  }

  static int _afterDefault(List<FavFolder> folders) {
    final index = folders.indexWhere((folder) => !folder.isDefault);
    return index < 0 ? folders.length : index;
  }

  @override
  Future<void> commit() {
    final change = this.change;
    if (change.add.isEmpty && change.remove.isEmpty) return Future.value();
    final inAny = _folders.any((folder) => _ticked.contains(folder.id));
    return _actions.applyFavourites(add: change.add, remove: change.remove, inAnyFolder: inAny);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
