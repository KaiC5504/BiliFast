import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../../home/feed_model.dart' show feedLogFields, requestFailureMessage;
import '../live_api.dart';
import '../room/live_room_model.dart';

/// One of 高能榜's lists, a page at a time: one call out at a time, a page that adds no row ends it, and a failure
/// waits for 重试, so nothing loops against the website. [first] is the first page's answer as it came.
class RankFeed<P> extends ChangeNotifier {
  RankFeed({
    required this.name,
    required this._load,
    required List<LiveRankEntry> Function(P answer) entries,
    required bool Function(P answer) hasMore,
    Logger? logger,
  }) : _entriesOf = entries,
       _hasMoreOf = hasMore,
       _logger = logger ?? Logger.shared;

  /// For the log: `audience`, or the 大航海 tab's name.
  final String name;
  final Future<P> Function(int page) _load;
  final List<LiveRankEntry> Function(P answer) _entriesOf;
  final bool Function(P answer) _hasMoreOf;
  final Logger _logger;

  List<LiveRankEntry> get entries => _entries;
  List<LiveRankEntry> _entries = const [];

  P? get first => _first;
  P? _first;

  bool get started => _started;
  bool _started = false;

  int _page = 0;
  bool _hasMore = true;
  Future<void>? _out;

  /// Why the last call failed, until 重试; null while every call went through.
  String? get error => _error;
  String? _error;

  bool get loadingFirst => _out != null && _page == 0;
  bool get loadingMore => _out != null && _page > 0;
  bool get exhausted => _started && !_hasMore && _out == null && _error == null;
  bool get canLoadMore => _page > 0 && _hasMore && _error == null && _out == null;

  bool _disposed = false;

  /// Asks the first page, once.
  void start() {
    if (_started) return;
    _started = true;
    _fetch(1);
  }

  void loadMore() {
    if (canLoadMore) _fetch(_page + 1);
  }

  /// Asks again the page that failed.
  void retry() {
    if (!_started || _out != null || _error == null) return;
    _error = null;
    _fetch(_page + 1);
  }

  void _fetch(int page) {
    _out = _run(page);
    _notify();
  }

  Future<void> _run(int page) async {
    try {
      final answer = await _load(page);
      if (_disposed) return;
      final known = {for (final entry in _entries) entry.user.uid};
      final fresh = [
        for (final entry in _entriesOf(answer))
          if (entry.user.uid == 0 || known.add(entry.user.uid)) entry,
      ];
      if (page == 1) _first = answer;
      _entries = [..._entries, ...fresh];
      _page = page;
      // A page past the first that adds nobody would be asked again and again.
      _hasMore = _hasMoreOf(answer) && (fresh.isNotEmpty || page == 1);
    } catch (error) {
      if (_disposed) return;
      _logger.warn(LogCategory.ui, 'live rank failed', {...feedLogFields(error), 'list': name, 'page': page});
      _error = requestFailureMessage(error);
    } finally {
      if (!_disposed) {
        _out = null;
        _notify();
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

/// 高能榜's lists for one opening of the sheet: 房间观众's 在线榜 and 大航海's 周榜, 月榜 and 陪伴榜. 在线榜 and 周榜 are
/// asked when the anchor is known (周榜's answer names 大航海's count in the tab title); 月榜 and 陪伴榜 when first shown.
class LiveRankModel extends ChangeNotifier {
  LiveRankModel({required this.room, Logger? logger}) : _logger = logger ?? Logger.shared {
    audience = RankFeed<LiveRankPage>(
      name: 'audience',
      load: (page) => _api.rank(room.roomId, anchorUid: _uid!, page: page),
      entries: (answer) => answer.entries,
      hasMore: (answer) => answer.hasMore,
      logger: _logger,
    );
    guards = {
      for (final tab in LiveGuardTab.values)
        tab: RankFeed<LiveGuardPage>(
          name: tab.name,
          load: (page) => _api.guards(room.roomId, anchorUid: _uid!, tab: tab, page: page),
          entries: (answer) => answer.entries,
          hasMore: (answer) => answer.hasMore,
          logger: _logger,
        ),
    };
    for (final feed in guards.values) {
      feed.addListener(_guardsChanged);
    }
  }

  final LiveRoomModel room;
  final Logger _logger;

  LiveApi get _api => room.api;

  late final RankFeed<LiveRankPage> audience;
  late final Map<LiveGuardTab, RankFeed<LiveGuardPage>> guards;

  /// 大航海's count, from the first 大航海 answer; null until it lands.
  int? get guardTotal => _guardTotal;
  int? _guardTotal;

  int? _uid;
  final _wanted = <LiveGuardTab>{LiveGuardTab.weekly};
  bool _opened = false;

  /// The anchor's uid: the room's info, else its play info, else the card's; null while none is known.
  static int? anchorOf(LiveRoomModel room) {
    for (final uid in [room.info?.uid, room.play?.uid, room.entry.uid]) {
      if (uid != null && uid > 0) return uid;
    }
    return null;
  }

  /// Asks 在线榜 and 周榜, at once or as soon as the room knows its anchor.
  void open() {
    if (_opened) return;
    _opened = true;
    if (!_resolve()) room.addListener(_roomChanged);
  }

  /// 大航海's [tab] is on screen: its list is asked the first time.
  void show(LiveGuardTab tab) {
    _wanted.add(tab);
    if (_uid != null) guards[tab]!.start();
  }

  bool _resolve() {
    final uid = anchorOf(room);
    if (uid == null) return false;
    _uid = uid;
    audience.start();
    for (final tab in _wanted) {
      guards[tab]!.start();
    }
    return true;
  }

  void _roomChanged() {
    if (_resolve()) room.removeListener(_roomChanged);
  }

  /// The first 大航海 answer to land names the count; 周榜's, unless it failed.
  void _guardsChanged() {
    if (_guardTotal != null) return;
    for (final feed in guards.values) {
      if (feed.first case final answer?) {
        _guardTotal = answer.total;
        notifyListeners();
        return;
      }
    }
  }

  @override
  void dispose() {
    room.removeListener(_roomChanged);
    for (final feed in guards.values) {
      feed.removeListener(_guardsChanged);
    }
    audience.dispose();
    for (final feed in guards.values) {
      feed.dispose();
    }
    super.dispose();
  }
}
