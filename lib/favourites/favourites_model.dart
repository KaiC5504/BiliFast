import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/logic.dart' show CountFormat;
import 'package:flutter/foundation.dart';

import '../home/feed_model.dart' show requestFailureMessage;
import '../video/video_route.dart';
import 'favourites_api.dart';

/// One row of a folder (81) or of 视频 (83), whichever list it came from.
@immutable
final class FavouriteRow {
  const FavouriteRow({
    required this.aid,
    required this.bvid,
    required this.title,
    this.cover = '',
    this.length = '',
    this.progress = 0,
    this.ownerName = '',
    this.plays = '',
    this.danmaku = '',
    this.cid,
  });

  /// A folder's video: the web list gives no progress, so no pink line.
  factory FavouriteRow.fromFolder(FavVideo video) => FavouriteRow(
    aid: video.aid,
    bvid: video.bvid,
    title: video.title,
    cover: video.cover,
    length: video.duration > 0 ? FavouriteFormat.clock(video.duration) : '',
    ownerName: video.ownerName,
    plays: CountFormat.short(video.play),
    danmaku: CountFormat.short(video.danmaku),
  );

  factory FavouriteRow.fromTab(FavTabVideo video) => FavouriteRow(
    aid: video.aid,
    bvid: video.bvid,
    title: video.title,
    cover: video.cover,
    length: video.progressText,
    progress: video.progress / 100,
    ownerName: video.ownerName,
    plays: video.plays,
    danmaku: video.danmaku,
    cid: video.cid == 0 ? null : video.cid,
  );

  final int aid;
  final String bvid;
  final String title;
  final String cover;

  /// What the cover's corner says: the length, as 00:11.
  final String length;

  /// How much of the pink line under the cover is filled, 0-1.
  final double progress;
  final String ownerName;
  final String plays;
  final String danmaku;
  final int? cid;

  /// Without a start the page resumes where Bilibili saw the account stop, as 历史记录's rows do.
  VideoRoute get route => VideoRoute(bvid: bvid, cid: cid, title: title, cover: cover.isEmpty ? null : cover);
}

abstract final class FavouriteFormat {
  /// 00:11 and 03:40, 01:02:03 past an hour (81).
  static String clock(int seconds) {
    String two(int n) => n < 10 ? '0$n' : '$n';
    final total = seconds < 0 ? 0 : seconds;
    final h = total ~/ 3600, m = total % 3600 ~/ 60, s = total % 60;
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  /// 0个内容 on a card (80), 8 个内容 under a folder's title (81).
  static String cardCount(int count) => '$count个内容';
  static String folderCount(int count) => '$count 个内容';

  /// A folder's page on the web, for 分享.
  static Uri folderLink(int folderId) => Uri.parse('https://www.bilibili.com/medialist/detail/ml$folderId');
}

/// A list of [FavouriteRow]s paged by cursors of type [C]: a folder's (81) or 视频 (83). It loads one page at a time,
/// and removing a row is optimistic, the row coming back where it was if the server refuses.
abstract class FavouriteRowsModel<C extends Object> extends ChangeNotifier {
  FavouriteRowsModel({required this.isLoggedIn, Logger? logger}) : _logger = logger ?? Logger.shared;

  static const removeFailed = '取消收藏失败，请稍后重试';

  /// Pages in a row that may add nothing (every row already listed) before a load more stops asking.
  static const _emptyPagesAllowed = 3;

  final bool Function() isLoggedIn;
  final Logger _logger;

  List<FavouriteRow> _rows = const [];
  bool _loading = false;
  bool _refreshing = false;
  String? _error;
  bool _isEnd = false;
  bool _needsLogin = false;
  C? _cursor;

  /// Rows removed here: a page still in flight must not bring one back.
  final Set<int> _removed = {};

  /// Bumped by a reload, so a load more still running cannot append to the new list.
  int _generation = 0;
  bool _disposed = false;

  List<FavouriteRow> get rows => _rows;
  bool get loading => _loading;

  /// A pull to refresh is running; the rows already shown stay until it answers.
  bool get refreshing => _refreshing;

  /// Why the next page (or, with no rows, the first) failed; nothing asks again until [loadMore].
  String? get error => _error;
  bool get isEnd => _isEnd;

  /// Logged out, or Bilibili answered -101.
  bool get needsLogin => _needsLogin;
  bool get canLoadMore => !_loading && !_isEnd && !_needsLogin && _error == null;

  /// The page after [cursor] (null for the first): its rows and the cursor after it, null at the end.
  @protected
  Future<(List<FavouriteRow>, C?)> fetch(C? cursor);

  @protected
  Future<void> removeOnServer(FavouriteRow row);

  /// The list's name in the log.
  @protected
  String get logName;

  /// A row left the list (true) or came back (false).
  @protected
  void rowCountChanged(int by) {}

  /// The first page, unless logged out (then the page asks for a login without asking Bilibili).
  Future<void> start() async {
    if (!isLoggedIn()) {
      _needsLogin = true;
      notify();
      return;
    }
    await loadMore();
  }

  Future<void> loadMore() async {
    if (_loading || _isEnd || _needsLogin) return;
    _error = null;
    await _load(replacing: false);
  }

  /// Starts over, as on pull to refresh and after logging in. The rows shown stay until the first page answers; a
  /// failure then keeps them and comes back as words for a toast (null otherwise).
  Future<String?> reload() async {
    _generation++;
    _needsLogin = false;
    _error = null;
    _refreshing = _rows.isNotEmpty;
    return _load(replacing: true);
  }

  Future<String?> _load({required bool replacing}) async {
    final mine = _generation;
    _loading = true;
    notify();
    var next = replacing ? null : _cursor;
    var kept = replacing ? <FavouriteRow>[] : [..._rows];
    var end = false;
    try {
      for (var attempt = 0; attempt < _emptyPagesAllowed; attempt++) {
        final (page, after) = await fetch(next);
        if (mine != _generation || _disposed) return null;
        final seen = {for (final row in kept) row.aid, ..._removed};
        final fresh = [
          for (final row in page)
            if (seen.add(row.aid)) row,
        ];
        kept = [...kept, ...fresh];
        next = after;
        end = after == null || page.isEmpty;
        if (fresh.isNotEmpty || end) break;
      }
      _rows = kept;
      _cursor = next;
      _isEnd = end;
      _error = null;
      return null;
    } on BiliError catch (error) {
      if (mine != _generation || _disposed) return null;
      if (error.needsLogin) {
        _loggedOut();
        return null;
      }
      return _failed(error, replacing: replacing);
    } catch (error) {
      if (mine != _generation || _disposed) return null;
      return _failed(error, replacing: replacing);
    } finally {
      if (mine == _generation && !_disposed) {
        _loading = false;
        _refreshing = false;
        notify();
      }
    }
  }

  void _loggedOut() {
    _needsLogin = true;
    _rows = const [];
    _cursor = null;
    _isEnd = false;
  }

  String? _failed(Object error, {required bool replacing}) {
    _logger.warn(LogCategory.ui, '$logName failed', {'error': '$error'});
    final message = requestFailureMessage(error);
    if (replacing && _rows.isNotEmpty) return message;
    _error = message;
    return null;
  }

  /// Takes [row] off at once and removes it on the server; if that fails it comes back where it was and the words
  /// for a toast are returned (null on success). A -101 instead turns the page to its login state.
  Future<String?> remove(FavouriteRow row) async {
    final index = _rows.indexWhere((kept) => kept.aid == row.aid);
    if (index < 0) return null;
    final before = _rows;
    _rows = [..._rows]..removeAt(index);
    _removed.add(row.aid);
    rowCountChanged(-1);
    notify();
    try {
      await removeOnServer(row);
      return null;
    } catch (error) {
      _logger.warn(LogCategory.ui, '$logName remove failed', {'error': '$error'});
      _removed.remove(row.aid);
      if (_disposed) return removeFailed;
      if (error is BiliError && error.needsLogin) {
        _generation++;
        _loading = false;
        _refreshing = false;
        _loggedOut();
        notify();
        return null;
      }
      if (!_rows.any((kept) => kept.aid == row.aid)) {
        // Rows may have come meanwhile; it goes back after the row that was before it.
        final previous = index == 0 ? null : before[index - 1].aid;
        final at = previous == null ? 0 : _rows.indexWhere((kept) => kept.aid == previous) + 1;
        _rows = [..._rows]..insert(at.clamp(0, _rows.length), row);
        rowCountChanged(1);
        notify();
      }
      return removeFailed;
    }
  }

  @protected
  void notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// A folder's videos (81), 20 to a page; [info] starts as the card's and follows the server's and each removal.
class FolderVideosModel extends FavouriteRowsModel<int> {
  FolderVideosModel({
    required this.api,
    required FavFolder folder,
    required super.isLoggedIn,
    this.onRemoved,
    this.pageSize = 20,
    super.logger,
  }) : _info = FavFolderInfo(id: folder.id, title: folder.title, count: folder.count, isPrivate: folder.isPrivate);

  final FavouritesApi api;

  /// Told when a video has left the folder for good, so the folder list can follow.
  final void Function(int aid)? onRemoved;
  final int pageSize;
  FavFolderInfo _info;

  FavFolderInfo get info => _info;

  @override
  String get logName => 'favourites folder';

  @override
  Future<(List<FavouriteRow>, int?)> fetch(int? cursor) async {
    final page = cursor ?? 1;
    final answer = await api.folderVideos(folderId: _info.id, page: page, pageSize: pageSize);
    if (answer.info case final info?) {
      _info = page == 1 ? info : info.withCount(_info.count);
    }
    return ([for (final video in answer.videos) FavouriteRow.fromFolder(video)], answer.hasMore ? page + 1 : null);
  }

  @override
  void rowCountChanged(int by) => _info = _info.withCount((_info.count + by).clamp(0, 1 << 31));

  @override
  Future<void> removeOnServer(FavouriteRow row) async {
    await api.removeFromFolder(folderId: _info.id, aid: row.aid);
    onRemoved?.call(row.aid);
  }
}

/// 视频 (83, 84): every favourite once, newest first; its tab id is asked once, on the first page.
class AllVideosModel extends FavouriteRowsModel<FavTabCursor> {
  AllVideosModel({required this.api, required super.isLoggedIn, this.onRemoved, super.logger});

  final FavouritesApi api;

  /// Told when a video has left every folder.
  final void Function(int aid)? onRemoved;
  int? _tabId;

  @override
  String get logName => 'favourites videos';

  @override
  Future<(List<FavouriteRow>, FavTabCursor?)> fetch(FavTabCursor? cursor) async {
    final tab = _tabId ??= await api.videosTab();
    if (tab == null) throw StateError('no 视频 tab');
    final page = await api.allVideos(tabId: tab, after: cursor);
    return ([for (final item in page.items) FavouriteRow.fromTab(item)], page.hasMore ? page.next : null);
  }

  @override
  Future<void> removeOnServer(FavouriteRow row) async {
    await api.removeEverywhere(aid: row.aid);
    onRemoved?.call(row.aid);
  }
}

/// A folder card's covers: still to ask, asking, the first three, or failed (grey tiles, never asked again).
sealed class FolderPreview {
  const FolderPreview();
}

final class PreviewLoading extends FolderPreview {
  const PreviewLoading();
}

final class PreviewReady extends FolderPreview {
  const PreviewReady(this.videos);

  final List<FavVideo> videos;
}

final class PreviewFailed extends FolderPreview {
  const PreviewFailed();
}

/// 收藏夹 (80): the account's folders in one call, then each card's first three covers, one call at a time and only
/// for the cards on screen.
class FavouriteFoldersModel extends ChangeNotifier {
  FavouriteFoldersModel({required this.api, required this.mid, required this.isLoggedIn, Logger? logger})
    : _logger = logger ?? Logger.shared;

  static const previewSize = 3;

  final FavouritesApi api;
  final int? Function() mid;
  final bool Function() isLoggedIn;
  final Logger _logger;

  List<FavFolder> _folders = const [];
  bool _loading = false;
  bool _loaded = false;
  bool _refreshing = false;
  String? _error;
  bool _needsLogin = false;
  final Map<int, FolderPreview> _previews = {};

  /// Cards on screen waiting for their covers, in the order they asked.
  final List<FavFolder> _queue = [];
  bool _previewing = false;
  int _generation = 0;
  bool _disposed = false;

  List<FavFolder> get folders => _folders;
  bool get loading => _loading;
  bool get loaded => _loaded;
  bool get refreshing => _refreshing;
  String? get error => _error;
  bool get needsLogin => _needsLogin;

  /// Null until the card has asked.
  FolderPreview? preview(int folderId) => _previews[folderId];

  Future<void> start() async {
    if (!isLoggedIn() || mid() == null) {
      _needsLogin = true;
      _notify();
      return;
    }
    await _load();
  }

  /// Pull to refresh, the retry and a login: the folders again, and the covers as cards show. A failure with
  /// folders shown keeps them and returns the words for a toast.
  Future<String?> reload() async {
    _needsLogin = false;
    _error = null;
    _refreshing = _folders.isNotEmpty;
    return _load();
  }

  Future<String?> _load() async {
    final mine = ++_generation;
    final account = mid();
    if (account == null) {
      _needsLogin = true;
      _refreshing = false;
      _notify();
      return null;
    }
    _loading = true;
    _notify();
    try {
      final folders = await api.folders(mid: account);
      if (mine != _generation || _disposed) return null;
      _folders = folders;
      _loaded = true;
      _previews.clear();
      _queue.clear();
      _error = null;
      return null;
    } on BiliError catch (error) {
      if (mine != _generation || _disposed) return null;
      if (error.needsLogin) {
        _needsLogin = true;
        _folders = const [];
        _loaded = false;
        return null;
      }
      return _failed(error);
    } catch (error) {
      if (mine != _generation || _disposed) return null;
      return _failed(error);
    } finally {
      if (mine == _generation && !_disposed) {
        _loading = false;
        _refreshing = false;
        _notify();
      }
    }
  }

  String? _failed(Object error) {
    _logger.warn(LogCategory.ui, 'favourites folders failed', {'error': '$error'});
    final message = requestFailureMessage(error);
    if (_folders.isNotEmpty) return message;
    _error = message;
    return null;
  }

  /// A card came on screen: its covers are asked after those already waiting. An empty folder asks nothing.
  void wantPreview(FavFolder folder) {
    if (_disposed || _previews.containsKey(folder.id) || _queue.any((waiting) => waiting.id == folder.id)) return;
    if (folder.count == 0) {
      _previews[folder.id] = const PreviewReady([]);
      return;
    }
    _queue.add(folder);
    unawaited(_nextPreview());
  }

  /// A card left the screen before its turn.
  void dropPreview(int folderId) => _queue.removeWhere((waiting) => waiting.id == folderId);

  Future<void> _nextPreview() async {
    if (_previewing || _queue.isEmpty || _disposed) return;
    _previewing = true;
    final folder = _queue.removeAt(0);
    final mine = _generation;
    _previews[folder.id] = const PreviewLoading();
    _notify();
    try {
      final page = await api.folderVideos(folderId: folder.id, page: 1, pageSize: previewSize);
      if (mine == _generation) _previews[folder.id] = PreviewReady(page.videos.take(previewSize).toList());
    } catch (error) {
      _logger.warn(LogCategory.ui, 'favourites preview failed', {'error': '$error'});
      if (mine == _generation) _previews[folder.id] = const PreviewFailed();
    } finally {
      _previewing = false;
      _notify();
    }
    unawaited(_nextPreview());
  }

  /// The folder [folderId] lost [aid] (its page's 取消收藏): one fewer, and its cover gone.
  void removedFrom(int folderId, int aid) {
    _folders = [
      for (final folder in _folders)
        folder.id == folderId
            ? FavFolder(
                id: folder.id,
                title: folder.title,
                count: folder.count > 0 ? folder.count - 1 : 0,
                isPrivate: folder.isPrivate,
                contains: folder.contains,
                isDefault: folder.isDefault,
              )
            : folder,
    ];
    _dropCover(aid, onlyIn: folderId);
    _notify();
  }

  /// [aid] left every folder (视频's 取消收藏): its covers go, and the counts are asked again when the list next shows.
  void removedEverywhere(int aid) {
    _dropCover(aid);
    _stale = true;
    _notify();
  }

  bool _stale = false;

  /// Whether the counts may be out of date since a removal from 视频.
  bool get stale => _stale;

  /// Asks the folders again if [stale], keeping the covers.
  Future<void> refreshIfStale() async {
    if (!_stale) return;
    _stale = false;
    final covers = Map.of(_previews);
    await reload();
    for (final MapEntry(:key, :value) in covers.entries) {
      if (value is PreviewReady) _previews.putIfAbsent(key, () => value);
    }
    _notify();
  }

  void _dropCover(int aid, {int? onlyIn}) {
    for (final MapEntry(:key, :value) in _previews.entries.toList()) {
      if (onlyIn != null && key != onlyIn) continue;
      if (value is PreviewReady && value.videos.any((video) => video.aid == aid)) {
        _previews[key] = PreviewReady([
          for (final video in value.videos)
            if (video.aid != aid) video,
        ]);
      }
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
