import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/live.dart';
import 'package:flutter/foundation.dart';

import '../live_api.dart';
import '../live_entry.dart';
import 'live_chat_item.dart';

enum LiveRoomState {
  /// The first calls are out.
  loading,

  /// The room is live. [LiveRoomModel.play]'s url can still be null when the answer offered no stream.
  live,

  /// The room wasn't live when opened, or ended while watched (PREPARING).
  ended,

  /// The play info failed; [LiveRoomModel.retry] asks again.
  failed,
}

/// A write that needs the account, asked while logged out: the page opens the login gate.
final class LiveNotLoggedIn implements Exception {
  const LiveNotLoggedIn();

  @override
  String toString() => 'LiveNotLoggedIn';
}

/// One open room: its info, stream, chat, 醒目留言 and counts, the danmaku socket's life, sending and 点赞.
/// Every page and widget of the room reads it; the player plays [play]'s stream.
class LiveRoomModel extends ChangeNotifier {
  LiveRoomModel({
    required this.api,
    required this.entry,
    required this.loggedIn,
    DateTime Function()? now,
    this.viewer,
    this.inline = false,
    Logger? logger,
  }) : now = now ?? DateTime.now,
       _logger = logger ?? Logger.shared;

  /// 系统提示's text, first in every room's chat (207).
  static const systemNotice =
      '系统提示：哔哩哔哩直播内容及互动评论须严格遵守直播规范，严禁传播违法违规、低俗血暴、吸烟酗酒、造谣诈骗等不良有害信息。'
      '如有违规，平台将对违规直播间或账号进行相应的处罚！注意理性打赏，严禁未成年人直播或打赏。'
      '请勿轻信各类招聘征婚、代练代抽、刷钻、购买礼包码、游戏币等广告信息，且如主播在推广商品中诱导私下交易，请谨慎判断，以免上当受骗。';

  static const likeTip = '试试双击点赞，让主播被更多人看到吧～';

  static const maxRows = 500;
  static const _trimRows = 100;
  static const _tipAfter = Duration(seconds: 30);
  static const _hideGrace = Duration(seconds: 1);
  static const _likeGather = Duration(milliseconds: 800);
  static const _echoWindow = Duration(seconds: 10);

  final LiveApi api;
  final LiveRoomEntry entry;
  final bool Function() loggedIn;
  final DateTime Function() now;

  /// The account as its own rows show it. Without it those rows have no name, and the socket's echo of a send is told
  /// by its text alone.
  final LiveUser Function()? viewer;

  /// 首页's carousel card: it shows only the stream and its flying danmaku, so it asks the play info alone (no info,
  /// history or 醒目留言) and doesn't put the room in 历史记录 (`roomEntryAction`).
  final bool inline;
  final Logger _logger;

  LiveRoomState _state = LiveRoomState.loading;
  LiveRoomState get state => _state;

  int? _roomId;

  /// The real room id once the play info answers, else the entry's.
  int get roomId => _roomId ?? entry.roomId;

  LiveRoomInfo? _info;
  LiveRoomInfo? get info => _info;

  LivePlayInfo? _play;
  LivePlayInfo? get play => _play;

  /// The anchor's uid: the info's, else the play info's, else the card's.
  int get anchorUid {
    for (final uid in [_info?.uid, _play?.uid]) {
      if (uid != null && uid != 0) return uid;
    }
    return entry.uid;
  }

  String? _changedTitle;

  /// As the socket last changed it (ROOM_CHANGE), else the info's, else the card's.
  String get title {
    for (final title in [_changedTitle, _info?.title]) {
      if (title != null && title.isNotEmpty) return title;
    }
    return entry.title;
  }

  int _likeCount = 0;

  /// The 点赞 total under the anchor's name, following the socket.
  int get likeCount => _likeCount;

  int _onlineCount = 0;

  /// The number after the header's three faces, following the socket.
  int get onlineCount => _onlineCount;

  List<String> _topFaces = const [];
  List<String> get topFaces => _topFaces;

  String _watchedText = '';

  /// The 看过 words (9.1万人看过), following the socket.
  String get watchedText => _watchedText;

  bool _following = false;
  bool get following => _following;

  /// The chat, oldest first, at most 500 rows.
  ValueListenable<List<LiveChatItem>> get chat => _chat;
  final _chat = ValueNotifier<List<LiveChatItem>>(const []);

  /// The 醒目留言 still showing, for the strip under the video, newest first.
  ValueListenable<List<LiveSuperChat>> get superChats => _superChats;
  final _superChats = ValueNotifier<List<LiveSuperChat>>(const []);

  /// Each danmaku as it arrives (the socket's and this phone's own), for the danmaku over the video.
  Stream<LiveChatMessage> get flying => _flying.stream;
  final _flying = StreamController<LiveChatMessage>.broadcast();

  bool _disposed = false;
  Future<void>? _starting;
  Future<void>? _retrying;
  bool _cardAdded = false;
  bool _entered = false;
  Timer? _tipTimer;
  Timer? _expiryTimer;

  bool _shown = true;
  LiveChannel? _channel;
  Future<LiveChannel>? _channelAsk;
  StreamSubscription<LiveEvent>? _events;
  bool _socketOn = false;

  /// Moves on with every open and close, so a channel that answers after its page went away isn't started.
  int _socketGeneration = 0;
  Timer? _graceTimer;

  Future<void>? _streamAsk;
  int? _streamAskQn;

  int _likeClicks = 0;
  Timer? _likeTimer;
  bool _followBusy = false;
  int _ownCount = 0;

  /// Own sends whose echo from the socket is still expected.
  final _echoes = <({LiveChatMessage message, DateTime at})>[];

  /// Asks the info, the play info, the history and the 醒目留言 together, once; then opens the socket while
  /// [setShown] says shown.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    final id = entry.roomId;
    if (inline) {
      final play = await _try('play info', () => api.playInfo(id));
      if (_disposed) return;
      if (play != null) {
        _takePlay(play);
      } else {
        _state = LiveRoomState.failed;
      }
      _notify();
      return;
    }
    _tipTimer = Timer(_tipAfter, _addTip);
    final (info, play, history, superChats) = await (
      _try('room info', () => api.roomInfo(id)),
      _try('play info', () => api.playInfo(id)),
      _try('history', () => api.history(id)),
      _try('super chats', () => api.superChats(id)),
    ).wait;
    if (_disposed) return;
    if (info != null) _takeInfo(info);
    _append([
      const LiveChatNotice(systemNotice),
      for (final message in history ?? const <LiveChatMessage>[]) LiveChatDanmaku(message),
    ]);
    _setSuperChats([...?superChats]..sort((a, b) => b.start.compareTo(a.start)));
    if (play != null) {
      _takePlay(play);
    } else {
      _state = LiveRoomState.failed;
    }
    _logger.info(LogCategory.app, 'live room', {'room': roomId, 'state': _state.name});
    _notify();
  }

  /// Asks the play info again after it failed (and the info, if that failed too).
  Future<void> retry() {
    if (_state != LiveRoomState.failed) return _retrying ?? Future.value();
    return _retrying ??= _retry().whenComplete(() => _retrying = null);
  }

  Future<void> _retry() async {
    _state = LiveRoomState.loading;
    _notify();
    final known = _info;
    final (info, play) = await (
      known == null && !inline ? _try('room info', () => api.roomInfo(entry.roomId)) : Future.value(known),
      _try('play info', () => api.playInfo(entry.roomId)),
    ).wait;
    if (_disposed) return;
    if (known == null && info != null) _takeInfo(info);
    if (play != null) {
      _takePlay(play);
    } else {
      _state = LiveRoomState.failed;
    }
    _notify();
  }

  /// The page is on screen (true) or covered / the app away (false): the socket closes away and comes back on return.
  void setShown(bool shown) {
    _shown = shown;
    _syncSocket();
  }

  /// Asks the play info again at [qn]; [play] follows. One call at a time; a failure throws (the caller toasts it).
  Future<void> setQuality(int qn) {
    if (_streamAsk == null && qn == _play?.currentQn) return Future.value();
    return _askStream(qn);
  }

  /// ⟳: asks the play info again at the current quality.
  Future<void> refreshStream() {
    if (_state == LiveRoomState.failed) return retry();
    if (_state == LiveRoomState.loading) return _retrying ?? _starting ?? Future.value();
    return _askStream(_streamAsk != null ? _streamAskQn : _currentQn);
  }

  /// Sends [text]; the row shows at once, a failure takes it back and throws (the caller toasts it). Logged out, it
  /// throws [LiveNotLoggedIn].
  Future<void> send(String text) async {
    if (!loggedIn()) throw const LiveNotLoggedIn();
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _sendOwn(_ownMessage(text: trimmed), () => api.send(roomId, trimmed));
  }

  Future<void> sendEmote(LiveEmote emote) async {
    if (!loggedIn()) throw const LiveNotLoggedIn();
    await _sendOwn(_ownMessage(text: emote.text, bigEmote: emote), () => api.sendEmote(roomId, emote));
  }

  /// A double tap's 点赞; taps are gathered and sent as one. Logged out, it throws [LiveNotLoggedIn].
  void like() {
    if (!loggedIn()) throw const LiveNotLoggedIn();
    _likeClicks++;
    _likeCount++;
    _likeTimer?.cancel();
    _likeTimer = Timer(_likeGather, () => unawaited(_sendLikes()));
    _notify();
  }

  /// 关注 at once, back as it was if the call fails (which throws). Logged out, it throws [LiveNotLoggedIn].
  Future<void> setFollowing(bool on) async {
    if (!loggedIn()) throw const LiveNotLoggedIn();
    if (_followBusy || _following == on) return;
    _followBusy = true;
    _following = on;
    _notify();
    try {
      await api.follow(anchorUid, on: on);
    } catch (error) {
      _logger.warn(LogCategory.api, 'live follow failed', {'error': _reason(error)});
      if (!_disposed) {
        _following = !on;
        _notify();
      }
      rethrow;
    } finally {
      _followBusy = false;
    }
  }

  @override
  void dispose() {
    _likeTimer?.cancel();
    if (_likeClicks > 0) unawaited(_sendLikes());
    _disposed = true;
    _tipTimer?.cancel();
    _expiryTimer?.cancel();
    _graceTimer?.cancel();
    _socketGeneration++;
    unawaited(_events?.cancel());
    if (_channel case final channel?) unawaited(_closeChannel(channel));
    unawaited(_flying.close());
    _chat.dispose();
    _superChats.dispose();
    super.dispose();
  }

  Future<T?> _try<T>(String what, Future<T> Function() call) async {
    try {
      return await call();
    } catch (error) {
      _logger.warn(LogCategory.api, 'live $what failed', {'room': roomId, 'error': _reason(error)});
      return null;
    }
  }

  void _takeInfo(LiveRoomInfo info) {
    _info = info;
    _likeCount = math.max(_likeCount, info.likeCount);
    _onlineCount = info.onlineCount;
    _topFaces = List.unmodifiable(info.topFaces);
    _watchedText = info.watchedText;
    _following = info.following;
  }

  void _takePlay(LivePlayInfo play) {
    _play = play;
    if (play.roomId != 0) _roomId = play.roomId;
    _state = play.status == LiveStatus.live ? LiveRoomState.live : LiveRoomState.ended;
    if (!_cardAdded) {
      _cardAdded = true;
      _append([LiveChatRoomCard(title: title, description: _info?.description ?? '', liveTime: play.liveTime)]);
    }
    if (!inline && !_entered && loggedIn()) {
      _entered = true;
      unawaited(_try('enter', () => api.enter(roomId)));
    }
    _syncSocket();
  }

  int? get _currentQn {
    final qn = _play?.currentQn ?? 0;
    return qn == 0 ? null : qn;
  }

  Future<void> _askStream(int? qn) {
    final running = _streamAsk;
    if (running != null && _streamAskQn == qn) return running;
    late final Future<void> ask;
    ask = _stream(qn, after: running).whenComplete(() {
      if (identical(_streamAsk, ask)) {
        _streamAsk = null;
        _streamAskQn = null;
      }
    });
    _streamAsk = ask;
    _streamAskQn = qn;
    return ask;
  }

  Future<void> _stream(int? qn, {Future<void>? after}) async {
    if (after != null) {
      try {
        await after;
      } catch (_) {
        // That call's caller has its failure.
      }
    }
    if (_disposed) return;
    try {
      final play = await api.playInfo(roomId, qn: qn);
      if (_disposed) return;
      _takePlay(play);
      _notify();
    } catch (error) {
      _logger.warn(LogCategory.api, 'live play info failed', {'room': roomId, 'error': _reason(error)});
      rethrow;
    }
  }

  // The socket stays up through an end (PREPARING), so the room hears LIVE when it comes back.
  bool get _wantsSocket => _shown && !_disposed && (_state == LiveRoomState.live || _channel != null);

  void _syncSocket() {
    if (_disposed) return;
    if (_wantsSocket) {
      _graceTimer?.cancel();
      _graceTimer = null;
      if (!_socketOn) unawaited(_openSocket());
    } else if (_socketOn) {
      _graceTimer ??= Timer(_hideGrace, () {
        _graceTimer = null;
        _closeSocket();
      });
    }
  }

  Future<void> _openSocket() async {
    _socketOn = true;
    final generation = ++_socketGeneration;
    final channel = await _ensureChannel();
    if (generation != _socketGeneration || _disposed) return;
    if (channel == null) {
      _socketOn = false;
      return;
    }
    try {
      await channel.start();
    } catch (error) {
      _logger.warn(LogCategory.api, 'live socket start failed', {'room': roomId, 'error': _reason(error)});
    }
  }

  void _closeSocket() {
    if (!_socketOn) return;
    _socketOn = false;
    _socketGeneration++;
    if (_channel case final channel?) unawaited(_closeChannel(channel));
  }

  Future<void> _closeChannel(LiveChannel channel) async {
    try {
      await channel.close();
    } catch (error) {
      _logger.warn(LogCategory.api, 'live socket close failed', {'error': _reason(error)});
    }
  }

  /// The room's channel, asked once and kept between hide and show (its token with it).
  Future<LiveChannel?> _ensureChannel() async {
    if (_channel case final channel?) return channel;
    try {
      final channel = await (_channelAsk ??= api.channel(roomId));
      if (_disposed) return null;
      if (_channel == null) {
        _channel = channel;
        _events = channel.events.listen(_onEvent);
      }
      return _channel;
    } catch (error) {
      _channelAsk = null;
      _logger.warn(LogCategory.api, 'live socket info failed', {'room': roomId, 'error': _reason(error)});
      return null;
    }
  }

  void _onEvent(LiveEvent event) {
    if (_disposed) return;
    switch (event) {
      case LiveDanmakuEvent(:final message):
        if (_isEcho(message)) return;
        _append([LiveChatDanmaku(message)]);
        _flying.add(message);
      case LiveSuperChatEvent(:final superChat):
        if (_superChats.value.any((item) => item.id == superChat.id)) return;
        _append([LiveChatSuperChat(superChat)]);
        _setSuperChats([superChat, ..._superChats.value]);
      case LiveSuperChatDeletedEvent(:final ids):
        _setSuperChats(_superChats.value.where((item) => !ids.contains(item.id)));
      case LiveWatchedEvent(:final text):
        if (text == _watchedText) return;
        _watchedText = text;
        _notify();
      case LiveOnlineCountEvent(:final count):
        if (count == _onlineCount) return;
        _onlineCount = count;
        _notify();
      case LiveTopFacesEvent(:final faces):
        if (listEquals(faces, _topFaces)) return;
        _topFaces = List.unmodifiable(faces);
        _notify();
      case LiveLikeCountEvent(:final count):
        // Taps not yet counted by the server would otherwise flicker back.
        if (count <= _likeCount) return;
        _likeCount = count;
        _notify();
      case LiveInteractEvent(:final kind, :final user):
        if (kind == LiveInteraction.entered && !_isViewer(user.uid)) return;
        _append([LiveChatInteraction(kind, user)]);
      case LiveRoomChangedEvent(:final title, :final areaName):
        final next = title.isEmpty ? this.title : title;
        final info = _info;
        final areaChanged = info != null && areaName.isNotEmpty && areaName != info.areaName;
        if (next == this.title && !areaChanged) return;
        _changedTitle = next;
        if (info != null) _info = _retitled(info, next, areaName);
        _notify();
      case LiveStatusEvent(live: false):
        if (_state != LiveRoomState.live) return;
        _state = LiveRoomState.ended;
        _logger.info(LogCategory.app, 'live room ended', {'room': roomId});
        _notify();
      case LiveStatusEvent(live: true):
        if (_state != LiveRoomState.ended) return;
        unawaited(_askStream(_currentQn).catchError((Object _) {}));
    }
  }

  static LiveRoomInfo _retitled(LiveRoomInfo info, String title, String areaName) => LiveRoomInfo(
    roomId: info.roomId,
    uid: info.uid,
    title: title,
    cover: info.cover,
    anchorName: info.anchorName,
    anchorFace: info.anchorFace,
    anchorFrame: info.anchorFrame,
    verify: info.verify,
    description: info.description,
    areaName: areaName.isEmpty ? info.areaName : areaName,
    likeCount: info.likeCount,
    watchedText: info.watchedText,
    onlineCount: info.onlineCount,
    topFaces: info.topFaces,
    rankChips: info.rankChips,
    following: info.following,
  );

  int get _viewerUid => viewer?.call().uid ?? 0;

  bool _isViewer(int uid) {
    final viewerUid = _viewerUid;
    return viewerUid != 0 && uid == viewerUid;
  }

  LiveChatMessage _ownMessage({required String text, LiveEmote? bigEmote}) => LiveChatMessage(
    id: 'own-${++_ownCount}',
    user: viewer?.call() ?? const LiveUser(uid: 0, name: ''),
    text: text,
    time: now(),
    bigEmote: bigEmote,
  );

  Future<void> _sendOwn(LiveChatMessage message, Future<void> Function() call) async {
    final row = LiveChatDanmaku(message, own: true);
    final echo = (message: message, at: message.time);
    _echoes.add(echo);
    _append([row]);
    _flying.add(message);
    try {
      await call();
    } catch (error) {
      _logger.warn(LogCategory.api, 'live send failed', {'room': roomId, 'error': _reason(error)});
      if (!_disposed) {
        _echoes.remove(echo);
        _chat.value = List.unmodifiable(_chat.value.where((item) => !identical(item, row)));
      }
      rethrow;
    }
  }

  bool _isEcho(LiveChatMessage message) {
    final viewerUid = _viewerUid;
    if (viewerUid != 0 && message.user.uid != viewerUid) return false;
    final since = now().subtract(_echoWindow);
    _echoes.removeWhere((echo) => echo.at.isBefore(since));
    final index = _echoes.indexWhere((echo) => _sameSend(echo.message, message));
    if (index < 0) return false;
    _echoes.removeAt(index);
    return true;
  }

  static bool _sameSend(LiveChatMessage sent, LiveChatMessage echo) {
    final emote = sent.bigEmote;
    if (emote == null) return echo.bigEmote == null && echo.text == sent.text;
    final echoed = echo.bigEmote;
    if (echoed == null) return echo.text == emote.text;
    return (emote.unique.isNotEmpty && echoed.unique == emote.unique) || echoed.text == emote.text;
  }

  Future<void> _sendLikes() async {
    _likeTimer = null;
    final clicks = _likeClicks;
    if (clicks == 0) return;
    _likeClicks = 0;
    try {
      await api.like(roomId, anchorUid: anchorUid, clicks: clicks);
    } catch (error) {
      _logger.warn(LogCategory.api, 'live like failed', {'room': roomId, 'clicks': clicks, 'error': _reason(error)});
      if (_disposed) return;
      _likeCount = math.max(0, _likeCount - clicks);
      _notify();
    }
  }

  void _addTip() {
    _tipTimer = null;
    if (_state == LiveRoomState.live) _append([const LiveChatTip(likeTip)]);
  }

  void _append(Iterable<LiveChatItem> rows) {
    if (_disposed) return;
    var next = [..._chat.value, ...rows];
    while (next.length > maxRows) {
      next = next.sublist(_trimRows);
    }
    _chat.value = List.unmodifiable(next);
  }

  /// Keeps those still showing, and one timer for the next to end.
  void _setSuperChats(Iterable<LiveSuperChat> superChats) {
    if (_disposed) return;
    final at = now();
    final showing = [
      for (final item in superChats)
        if (item.end.isAfter(at)) item,
    ];
    if (!listEquals(showing, _superChats.value)) _superChats.value = List.unmodifiable(showing);
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (showing.isEmpty) return;
    final next = showing.map((item) => item.end).reduce((a, b) => a.isBefore(b) ? a : b);
    _expiryTimer = Timer(next.difference(at), () => _setSuperChats(_superChats.value));
  }

  static String _reason(Object error) => switch (error) {
    BiliAPIError(:final code) => 'api $code',
    BiliHTTPError(:final status) => 'http $status',
    _ => '${error.runtimeType}',
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
