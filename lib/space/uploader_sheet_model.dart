import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../home/feed_model.dart' show requestFailureMessage;
import 'space_api.dart';

/// What the uploader sheet shows of one uploader: the space's counts, and their videos newest first, a page at a time.
/// One call for the videos at a time; a failed page waits for 重试, and a page that adds nothing ends the list, so
/// nothing loops against the account.
class UploaderSheetModel extends ChangeNotifier {
  UploaderSheetModel({required this.mid, required this._api, Logger? logger}) : _logger = logger ?? Logger.shared;

  final int mid;
  final SpaceApi _api;
  final Logger _logger;

  SpaceProfile? _profile;
  bool _askingProfile = false;
  List<SpaceVideo> _videos = const [];
  final _seen = <String>{};
  String? _next;
  bool _hasMore = true;
  bool _loaded = false;
  bool _loading = false;
  String? _error;
  bool _disposed = false;

  /// Null until the space answers (or if it never does: the counts then stay away).
  SpaceProfile? get profile => _profile;

  List<SpaceVideo> get videos => _videos;

  /// The first page is in.
  bool get hasLoaded => _loaded;
  bool get loading => _loading;

  /// Why the last page couldn't load; null otherwise.
  String? get error => _error;
  bool get isEnd => _loaded && !_hasMore;
  bool get canLoadMore => _loaded && _hasMore && !_loading && _error == null;

  /// The counts and the first page.
  Future<void> start() {
    unawaited(_loadProfile());
    return loadMore();
  }

  Future<void> loadMore() async {
    if (_loading || _disposed || (_loaded && !_hasMore)) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      final page = await _api.videos(mid, order: SpaceOrder.latest, next: _next);
      if (_disposed) return;
      final fresh = [
        for (final video in page.items)
          if (_seen.add(video.bvid)) video,
      ];
      _videos = [..._videos, ...fresh];
      _next = page.next;
      _hasMore = page.hasMore && page.next != null && fresh.isNotEmpty;
      _loaded = true;
    } catch (error) {
      if (_disposed) return;
      _logger.warn(LogCategory.api, 'uploader sheet videos failed', {'error': _describe(error)});
      _error = requestFailureMessage(error);
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// 重试: the page that failed, and the counts if they never came.
  Future<void> retry() {
    unawaited(_loadProfile());
    return loadMore();
  }

  Future<void> _loadProfile() async {
    if (_profile != null || _askingProfile || _disposed) return;
    _askingProfile = true;
    try {
      final profile = await _api.profile(mid);
      if (_disposed) return;
      _profile = profile;
      _notify();
    } catch (error) {
      _logger.warn(LogCategory.api, 'uploader sheet profile failed', {'error': _describe(error)});
    } finally {
      _askingProfile = false;
    }
  }

  /// A transport error's text can carry the signed address; Bilibili's own errors carry only their code.
  static String _describe(Object error) => error is BiliError ? '$error' : '${error.runtimeType}';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
