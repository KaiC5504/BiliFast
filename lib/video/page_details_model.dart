import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../home/feed_model.dart' show requestFailureMessage;
import 'actions/actions_model.dart';
import 'actions/video_actions.dart';
import 'page_api.dart';
import 'page_details.dart';
import 'page_session.dart' show PeriodicTimer;
import 'player_session.dart';

/// The page body's side loads (BiliNative `VideoPageModel.swift`'s): for each video the session plays, new actions,
/// the relation and the uploader's card; for each part its tags; N人正在看 while active. Each shows as it lands, a late
/// answer for an earlier video or part is dropped, and a failure keeps what was there.
class VideoPageDetailsModel extends ChangeNotifier implements PageDetails {
  /// [accountChanges] hears logins, after which the actions ask for this account's relation again.
  VideoPageDetailsModel({
    required this._session,
    required this._api,
    required this._isLoggedIn,
    required this._accountMid,
    required this._requestLogin,
    required this._toast,
    this._dislikeAvailable = false,
    PeriodicTimer? periodic,
    Logger? logger,
    this._accountChanges,
  })  : _periodic = periodic ?? _systemPeriodic,
        _logger = logger ?? Logger.shared {
    _loggedIn = _isLoggedIn();
    _session.addListener(_sessionChanged);
    _accountChanges?.addListener(_accountChanged);
    _sessionChanged();
  }

  static const onlineInterval = Duration(seconds: 30);

  static Timer _systemPeriodic(Duration period, void Function() tick) => Timer.periodic(period, (_) => tick());

  final PlayerSession _session;
  final PageApi _api;
  final bool Function() _isLoggedIn;
  final int? Function() _accountMid;
  final VoidCallback _requestLogin;
  final void Function(String message) _toast;
  final bool _dislikeAvailable;
  final PeriodicTimer _periodic;
  final Logger _logger;
  final Listenable? _accountChanges;

  ActionsModel? _actions;
  UploaderCard? _uploader;
  List<VideoTag> _tags = const [];
  final ValueNotifier<String?> _online = ValueNotifier(null);

  /// The video the actions are for and the part the tags and N人正在看 are for.
  VideoDetail? _detail;
  int? _cid;

  /// Bumped for every new video and every new part, so an answer for an earlier one is dropped.
  int _video = 0;
  int _part = 0;
  Timer? _poll;

  /// The part an N人正在看 ask is out for: a slow answer doesn't get a second ask piled on.
  int? _asking;
  bool _active = true;
  bool _loggedIn = false;

  /// A login while covered: the relation is asked again once the page shows.
  bool _relationStale = false;
  bool _disposed = false;

  @override
  VideoActions? get actions => _actions;

  @override
  UploaderCard? get uploader => _uploader;

  @override
  List<VideoTag> get tags => _tags;

  @override
  ValueListenable<String?> get online => _online;

  @override
  set active(bool value) {
    if (_disposed || value == _active) return;
    _active = value;
    if (!value) {
      _stopPoll();
      return;
    }
    final actions = _actions;
    _sessionChanged();
    if (_poll == null) _startPoll();
    if (_relationStale) {
      _relationStale = false;
      // A video that only just arrived had its relation asked for with it.
      if (identical(actions, _actions)) unawaited(actions?.refreshRelation());
    }
  }

  /// A covered page's session can be looking at the newer page's video on the shared player, so only an active page
  /// follows it. A part switch empties the session's detail for a moment; the actions stay until a new video's
  /// detail comes.
  void _sessionChanged() {
    if (_disposed || !_active) return;
    final detail = _session.detail;
    if (detail != null && detail.bvid != _detail?.bvid) _newVideo(detail);
    final known = _detail;
    final video = _session.video;
    final part = _session.part;
    if (known == null || video == null || part == null || video.bvid != known.bvid) return;
    if (part.cid != _cid) _newPart(known, part.cid);
  }

  void _newVideo(VideoDetail detail) {
    _actions?.dispose();
    _video += 1;
    _detail = detail;
    _cid = null;
    _part += 1;
    _stopPoll();
    _uploader = null;
    _tags = const [];
    _online.value = null;
    _actions = ActionsModel(
      api: _api,
      detail: detail,
      isLoggedIn: _isLoggedIn,
      accountMid: _accountMid,
      requestLogin: _requestLogin,
      toast: _toast,
      dislikeAvailable: _dislikeAvailable,
      logger: _logger,
    );
    notifyListeners();
    unawaited(_loadUploader(detail));
    if (_isLoggedIn()) unawaited(_loadRelation(detail));
  }

  void _newPart(VideoDetail detail, int cid) {
    _cid = cid;
    _part += 1;
    unawaited(_loadTags(detail, cid));
    _startPoll();
  }

  Future<void> _loadRelation(VideoDetail detail) async {
    final video = _video;
    try {
      final relation = await _api.relation(aid: detail.aid, bvid: detail.bvid);
      if (_disposed || video != _video) return;
      _actions?.apply(relation);
    } catch (error) {
      _logger.warn(LogCategory.api, 'relation failed', {'bvid': detail.bvid, 'error': '$error'});
    }
  }

  Future<void> _loadUploader(VideoDetail detail) async {
    final video = _video;
    try {
      final card = await _api.uploaderCard(mid: detail.owner.mid);
      if (_disposed || video != _video) return;
      _uploader = card;
      _actions?.applyUploader(card);
      notifyListeners();
    } catch (error) {
      _logger.warn(LogCategory.api, 'uploader card failed', {'bvid': detail.bvid, 'error': '$error'});
    }
  }

  Future<void> _loadTags(VideoDetail detail, int cid) async {
    final part = _part;
    try {
      final tags = await _api.tags(bvid: detail.bvid, cid: cid);
      if (_disposed || part != _part) return;
      _tags = tags;
      notifyListeners();
    } catch (error) {
      _logger.warn(LogCategory.api, 'tags failed', {'bvid': detail.bvid, 'cid': cid, 'error': '$error'});
    }
  }

  /// Asks at once, then every [onlineInterval]; only while active and the part is known.
  void _startPoll() {
    _stopPoll();
    if (_disposed || !_active || _detail == null || _cid == null) return;
    unawaited(_askOnline());
    _poll = _periodic(onlineInterval, () => unawaited(_askOnline()));
  }

  void _stopPoll() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _askOnline() async {
    final detail = _detail;
    final cid = _cid;
    final part = _part;
    if (_disposed || !_active || detail == null || cid == null || _asking == part) return;
    _asking = part;
    try {
      final count = await _api.onlineCount(aid: detail.aid, bvid: detail.bvid, cid: cid);
      if (_disposed || part != _part) return;
      _online.value = count;
    } catch (error) {
      _logger.warn(LogCategory.api, 'online count failed', {'cid': cid, 'error': '$error'});
    } finally {
      if (_asking == part) _asking = null;
    }
  }

  void _accountChanged() {
    final loggedIn = _isLoggedIn();
    if (_disposed || loggedIn == _loggedIn) return;
    _loggedIn = loggedIn;
    if (!loggedIn) return;
    if (_active) {
      unawaited(_actions?.refreshRelation());
    } else {
      _relationStale = true;
    }
  }

  @override
  Future<ActionResult> watchLater(VideoCard card) async {
    if (!_isLoggedIn()) {
      _requestLogin();
      return const ActionResult('请先登录', ok: false);
    }
    try {
      await _api.addToWatchLater(aid: card.aid);
      return const ActionResult('已添加至稍后再看', ok: true);
    } catch (error) {
      _logger.warn(LogCategory.api, 'watch later failed', {'error': '$error'});
      if (error is BiliError && error.needsLogin && !_disposed) _requestLogin();
      return ActionResult(requestFailureMessage(error), ok: false);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopPoll();
    _session.removeListener(_sessionChanged);
    _accountChanges?.removeListener(_accountChanged);
    _actions?.dispose();
    _online.dispose();
    super.dispose();
  }
}
