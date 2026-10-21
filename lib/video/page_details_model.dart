import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../home/feed_model.dart' show requestFailureMessage;
import '../space/follow_book.dart';
import 'actions/actions_model.dart';
import 'actions/video_actions.dart';
import 'page_api.dart';
import 'page_details.dart';
import 'page_session.dart' show PeriodicTimer;
import 'player_session.dart';

/// The page body's side loads (BiliNative `VideoPageModel.swift`'s): for each video the session plays, new actions,
/// the relation and the uploader's card; for each part its tags; N人正在看 while active and the app is in the
/// foreground. Each shows as it lands, a late answer for an earlier video or part is dropped, and a failure keeps what
/// was there. A failed relation is asked again the next time the page shows or the app comes back, since without it
/// the actions show defaults as the account's state.
class VideoPageDetailsModel extends ChangeNotifier with WidgetsBindingObserver implements PageDetails {
  /// [accountChanges] hears the account change and [logins] each login made from the page; after either the relation
  /// is asked again for this account. [appAuthorized] and [requestAppAuth] are the app token's, for 不喜欢.
  VideoPageDetailsModel({
    required this._session,
    required this._api,
    required this._isLoggedIn,
    required this._accountMid,
    required this._requestLogin,
    required this._toast,
    this._appAuthorized,
    this._requestAppAuth,
    this._follows,
    PeriodicTimer? periodic,
    Logger? logger,
    this._accountChanges,
    this._logins,
  })  : _periodic = periodic ?? _systemPeriodic,
        _logger = logger ?? Logger.shared {
    _loggedIn = _isLoggedIn();
    _background = _inBackground(WidgetsBinding.instance.lifecycleState);
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_sessionChanged);
    _accountChanges?.addListener(_accountChanged);
    _logins?.addListener(_loginMade);
    _sessionChanged();
  }

  static const onlineInterval = Duration(seconds: 30);

  static Timer _systemPeriodic(Duration period, void Function() tick) => Timer.periodic(period, (_) => tick());

  /// Picture in picture counts: the app is in the background with the page out of sight.
  static bool _inBackground(AppLifecycleState? state) =>
      state == AppLifecycleState.hidden || state == AppLifecycleState.paused;

  final PlayerSession _session;
  final PageApi _api;
  final bool Function() _isLoggedIn;
  final int? Function() _accountMid;
  final VoidCallback _requestLogin;
  final void Function(String message) _toast;
  final bool Function()? _appAuthorized;
  final Future<bool> Function()? _requestAppAuth;
  final FollowBook? _follows;
  final PeriodicTimer _periodic;
  final Logger _logger;
  final Listenable? _accountChanges;
  final Listenable? _logins;

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
  bool _background = false;
  bool _loggedIn = false;

  /// A relation ask for the current video still to make once the page shows and the app is in the foreground: one
  /// that failed, or a login's while the page was covered.
  _RelationAsk? _owed;

  /// The video a login's relation ask is out for, so the account's change and the page's word of the same login ask
  /// once.
  int? _resetting;
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
    _sessionChanged();
    _wake();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final background = _inBackground(state);
    if (_disposed || background == _background) return;
    _background = background;
    if (background) {
      _stopPoll();
    } else {
      _wake();
    }
  }

  /// Shown again, or back in the foreground: N人正在看 asks at once and polls on, and an owed relation is asked for.
  void _wake() {
    if (!_active || _background) return;
    if (_poll == null) _startPoll();
    final owed = _owed;
    final detail = _detail;
    _owed = null;
    if (owed != null && detail != null) unawaited(_loadRelation(detail, owed));
  }

  /// Only an active page follows its session; it catches up when shown again. A part switch empties the session's
  /// detail for a moment; the actions stay until a new video's detail comes.
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
    _owed = null;
    _actions = ActionsModel(
      api: _api,
      detail: detail,
      isLoggedIn: _isLoggedIn,
      accountMid: _accountMid,
      requestLogin: _requestLogin,
      toast: _toast,
      appAuthorized: _appAuthorized,
      requestAppAuth: _requestAppAuth,
      follows: _follows,
      logger: _logger,
    );
    notifyListeners();
    unawaited(_loadUploader(detail));
    unawaited(_loadRelation(detail, _RelationAsk.fill));
  }

  void _newPart(VideoDetail detail, int cid) {
    _cid = cid;
    _part += 1;
    unawaited(_loadTags(detail, cid));
    _startPoll();
  }

  /// Logged out there is nothing to ask. A failure is owed until the page next shows or the app comes back, once each
  /// time, so nothing loops against the API.
  Future<void> _loadRelation(VideoDetail detail, _RelationAsk ask) async {
    if (!_isLoggedIn()) return;
    final video = _video;
    final asked = _actions?.answerStamp;
    if (ask == _RelationAsk.reset) _resetting = video;
    try {
      final relation = await _api.relation(aid: detail.aid, bvid: detail.bvid);
      if (_disposed || video != _video) return;
      switch (ask) {
        case _RelationAsk.fill:
          _actions?.apply(relation, asked: asked);
        case _RelationAsk.reset:
          _actions?.reset(relation, asked: asked);
      }
    } catch (error) {
      _logger.warn(LogCategory.api, 'relation failed', {'bvid': detail.bvid, 'error': '$error'});
      if (_disposed || video != _video) return;
      if (_owed != _RelationAsk.reset) _owed = ask;
    } finally {
      if (_resetting == video && ask == _RelationAsk.reset) _resetting = null;
    }
  }

  Future<void> _loadUploader(VideoDetail detail) async {
    final video = _video;
    final asked = _actions?.answerStamp;
    try {
      final card = await _api.uploaderCard(mid: detail.owner.mid);
      if (_disposed || video != _video) return;
      _uploader = card;
      _actions?.applyUploader(card, asked: asked);
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

  /// Asks at once, then every [onlineInterval]; only while active, in the foreground, and the part is known.
  void _startPoll() {
    _stopPoll();
    if (_disposed || !_active || _background || _detail == null || _cid == null) return;
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
    if (_disposed || !_active || _background || detail == null || cid == null || _asking == part) return;
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
    if (loggedIn) _askAfterLogin();
  }

  /// The account may have looked logged in all along, with cookies Bilibili stopped taking, so a login from the page
  /// asks again whatever the account did.
  void _loginMade() {
    if (_disposed) return;
    _loggedIn = _isLoggedIn();
    if (_loggedIn) _askAfterLogin();
  }

  void _askAfterLogin() {
    if (!_active) {
      _owed = _RelationAsk.reset;
    } else if (_detail case final detail? when _resetting != _video) {
      unawaited(_loadRelation(detail, _RelationAsk.reset));
    }
  }

  @override
  Future<ActionResult> watchLater(VideoCard card) async {
    if (!_isLoggedIn()) {
      _requestLogin();
      // The login request says so itself.
      return const ActionResult('', ok: false);
    }
    try {
      await _api.addToWatchLater(aid: card.aid);
      return const ActionResult('已添加至稍后再看', ok: true);
    } catch (error) {
      _logger.warn(LogCategory.api, 'watch later failed', {'error': '$error'});
      if (error is BiliError && error.needsLogin) {
        // The login prompt has the words.
        if (!_disposed) _requestLogin();
        return const ActionResult('', ok: false);
      }
      return ActionResult(requestFailureMessage(error), ok: false);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopPoll();
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_sessionChanged);
    _accountChanges?.removeListener(_accountChanged);
    _logins?.removeListener(_loginMade);
    _actions?.dispose();
    _online.dispose();
    super.dispose();
  }
}

/// [fill]: the video's own ask, which fills in what wasn't tapped. [reset]: a login's, which shows the account's
/// state whatever was tapped before.
enum _RelationAsk { fill, reset }
