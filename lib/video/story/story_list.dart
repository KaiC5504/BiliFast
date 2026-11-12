import 'dart:async';
import 'dart:collection';

import 'package:bili_core/api.dart'
    show BiliAPIError, BiliHTTPError, BiliNetworkError, PlaySource, StoryItem, VideoCard;
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import 'story_feed.dart';

/// A page of the official feed (`BiliClient.storyFeed`).
typedef StoryPageCall =
    Future<List<StoryItem>> Function({
      required int aid,
      required int cid,
      required int page,
      required PlaySource entry,
      String? trackId,
    });

/// A video's related list (`BiliClient.related`).
typedef RelatedCall = Future<List<VideoCard>> Function(String bvid);

/// What the feed needs of the page it plays on. It notifies whenever what it plays may have changed; the feed that
/// takes it disposes it.
abstract class StoryHost extends ChangeNotifier {
  /// The video the page has open now.
  String get bvid;

  /// The video playing as 竖屏's first entry ([PagePlayback.storyEntry]); null before its details are in.
  StoryEntry? get playing;

  /// [bvid]'s related list where the page has it loaded already, else null.
  List<VideoCard>? loadedRelated(String bvid);

  /// Opens [entry] on the page: the video 竖屏 was [entered] on as the user's own open, any other as a video swiped
  /// to.
  void open(StoryEntry entry, {required bool entered});

  /// Risk control answered one of 竖屏's calls: nothing more is asked while the page lives, by this feed or the next.
  bool get halted;
  void halt();
}

/// 竖屏's feed: the entered video, then the official feed's pages while [official] is given (an iPhone token, and
/// reports allowed), else the entered video's related list and then the last entry's. More is asked once the index is
/// within [ahead] of the end, one call at a time. A call that fails or adds nothing waits for the user's next move or
/// [wantMore]; an official one that fails, or an official page with no items, hands over to the related lists for
/// good; a related list Bilibili refused (a removed video) is not asked again; risk control (-352, -412, HTTP 412)
/// stops asking for the page's life ([StoryHost.halt]). A video the page opens that the feed didn't (自动连播 or 选集
/// while the feed is kept through landscape) starts the feed over from it.
class StoryList extends StoryFeed {
  StoryList({required StoryHost host, this._official, required this._related, Logger? logger})
    : _host = host,
      _logger = logger ?? Logger.shared,
      _enteredBvid = host.bvid {
    host.addListener(_hostChanged);
    _hostChanged();
  }

  /// The official app asks for the next page once the user is within three videos of the end.
  static const ahead = 3;

  final StoryHost _host;
  StoryPageCall? _official;
  final RelatedCall _related;
  final Logger _logger;
  String _enteredBvid;

  /// Where 竖屏 was entered from; every entry's reports name it, after a start over too.
  PlaySource? _entrySource;
  final List<StoryEntry> _entries = [];
  final Set<String> _listed = {};
  final Set<String> _relatedAsked = {};
  int _index = 0;
  bool _loading = false;
  bool _stalled = false;
  bool _disposed = false;
  bool _waitLogged = false;
  int _page = 1;
  int _relatedPage = 0;

  /// Counts the starts over: an answer to a call made before the last one is dropped.
  int _round = 0;

  @override
  List<StoryEntry> get entries => _view;
  late final _view = UnmodifiableListView(_entries);

  @override
  int get index => _index;

  @override
  bool get loading => _loading;

  /// Whether the official feed still supplies the entries.
  bool get official => _official != null;

  /// The details of the entered video arrive, or its part changes while it plays as the first entry, or the page
  /// opened a video of its own.
  void _hostChanged() {
    if (_disposed) return;
    final bvid = _host.bvid;
    if (bvid != (current?.bvid ?? _enteredBvid)) _restart(bvid);
    if (_index != 0 || bvid != _enteredBvid) return;
    final playing = _host.playing;
    if (playing == null || playing.bvid != _enteredBvid) return;
    final known = _entries.firstOrNull;
    if (known != null && (known.cid == playing.cid || playing.cid == null)) return;
    final own = playing.source;
    final source = PlaySource.story(
      entry: _entrySource ??= own,
      entered: true,
      trackId: own.trackId,
      flowData: own.flowData,
    );
    final entered = _withSource(playing, source);
    if (known == null) {
      _entries.add(entered);
      _listed.add(entered.bvid);
    } else {
      _entries[0] = entered;
    }
    notifyListeners();
    _askIfNear();
  }

  /// Back to one entry, [bvid], as if 竖屏 had been entered on it, its feed asked again from the start.
  void _restart(String bvid) {
    _round++;
    _enteredBvid = bvid;
    _entries.clear();
    _listed.clear();
    _relatedAsked.clear();
    _index = 0;
    _loading = false;
    _stalled = false;
    _waitLogged = false;
    _page = 1;
    _logger.info(LogCategory.api, 'story feed restarted');
    notifyListeners();
  }

  @override
  bool moveNext() {
    final next = this.next;
    if (_disposed || next == null) return false;
    _index++;
    _host.open(next, entered: false);
    notifyListeners();
    _userMoved();
    return true;
  }

  @override
  bool movePrevious() {
    final previous = this.previous;
    if (_disposed || previous == null) return false;
    _index--;
    _host.open(previous, entered: _index == 0);
    notifyListeners();
    _userMoved();
    return true;
  }

  @override
  void wantMore() {
    if (_disposed) return;
    _userMoved();
  }

  void _userMoved() {
    _stalled = false;
    _askIfNear();
  }

  void _askIfNear() {
    if (_disposed || _loading || _stalled || _host.halted || _entries.isEmpty) return;
    if (_entries.length - 1 - _index > ahead) return;
    if (_official case final official?) {
      _askOfficial(official);
    } else {
      _askRelated();
    }
  }

  void _askOfficial(StoryPageCall call) {
    final entered = _entries.first;
    final cid = entered.cid;
    // The feed is asked by the entered video's aid and part; the part's arrival asks it.
    if (cid == null || entered.aid == 0) {
      if (!_waitLogged) _logger.debug(LogCategory.api, 'story feed waits for the part');
      _waitLogged = true;
      return;
    }
    final source = _entrySource!;
    final page = _page;
    unawaited(
      _ask('official', page, () async {
        final items = await call(aid: entered.aid, cid: cid, page: page, entry: source, trackId: source.trackId);
        return [
          for (final item in items)
            StoryEntry.fromItem(
              item,
              source: PlaySource.story(
                entry: source,
                entered: false,
                trackId: item.trackId,
                flowData: item.flowData,
              ),
            ),
        ];
      }),
    );
  }

  void _askRelated() {
    final first = _entries.first.bvid;
    final bvid = _relatedAsked.contains(first)
        ? _entries.reversed.map((entry) => entry.bvid).where((bvid) => !_relatedAsked.contains(bvid)).firstOrNull
        : first;
    if (bvid == null) return;
    _relatedAsked.add(bvid);
    final source = PlaySource.story(entry: _entrySource!, entered: false);
    List<StoryEntry> entriesOf(List<VideoCard> cards) => [
      for (final card in cards) StoryEntry.fromCard(card, source: source),
    ];
    final page = ++_relatedPage;
    final loaded = _host.loadedRelated(bvid);
    if (loaded != null) {
      _answered('related', page, entriesOf(loaded), loaded: true);
      return;
    }
    final round = _round;
    unawaited(
      _ask('related', page, () async {
        try {
          return entriesOf(await _related(bvid));
        } catch (error) {
          // Unanswered, its list may be asked again at the user's next move; refused, the next move asks another
          // entry's, or a removed video would be asked for on every swipe.
          if (_transient(error) && round == _round) _relatedAsked.remove(bvid);
          rethrow;
        }
      }),
    );
  }

  static bool _transient(Object error) => switch (error) {
    BiliNetworkError() => true,
    BiliHTTPError(:final status) => status >= 500,
    _ => false,
  };

  Future<void> _ask(String kind, int page, Future<List<StoryEntry>> Function() call) async {
    final round = _round;
    _loading = true;
    notifyListeners();
    final List<StoryEntry> fresh;
    try {
      fresh = await call();
    } catch (error) {
      if (!_disposed && round == _round) _failed(kind, page, error);
      return;
    }
    if (!_disposed && round == _round) _answered(kind, page, fresh);
  }

  void _answered(String kind, int page, List<StoryEntry> fresh, {bool loaded = false}) {
    _loading = false;
    var kept = 0;
    for (final entry in fresh) {
      if (!_listed.add(entry.bvid)) continue;
      _entries.add(entry);
      kept++;
    }
    final official = kind == 'official';
    final handover = official && fresh.isEmpty;
    _logger.info(LogCategory.api, 'story feed', {
      'source': kind,
      'page': page,
      'kept': kept,
      'dropped': fresh.length - kept,
      if (loaded) 'loaded': true,
      if (handover) 'handover': 'empty',
    });
    if (official) _page = page + 1;
    if (handover) {
      _official = null;
    } else if (kept == 0) {
      _stalled = true;
    }
    notifyListeners();
    _askIfNear();
  }

  void _failed(String kind, int page, Object error) {
    _loading = false;
    final code = switch (error) {
      BiliAPIError(:final code) => code,
      BiliHTTPError(:final status) => status,
      _ => null,
    };
    final stopped = switch (error) {
      BiliAPIError(code: -352 || -412) || BiliHTTPError(status: 412) => true,
      _ => false,
    };
    if (stopped) _host.halt();
    final official = kind == 'official';
    _logger.warn(LogCategory.api, 'story feed', {
      'source': kind,
      'page': page,
      'error': '${error.runtimeType}',
      'code': ?code,
      if (stopped) 'stopped': true,
      if (official && !stopped) 'handover': 'failed',
    });
    if (official) {
      _official = null;
    } else {
      _stalled = true;
    }
    notifyListeners();
    _askIfNear();
  }

  @override
  void dispose() {
    _disposed = true;
    _host
      ..removeListener(_hostChanged)
      ..dispose();
    super.dispose();
  }
}

StoryEntry _withSource(StoryEntry entry, PlaySource source) => StoryEntry(
  bvid: entry.bvid,
  aid: entry.aid,
  cid: entry.cid,
  title: entry.title,
  cover: entry.cover,
  firstFrame: entry.firstFrame,
  duration: entry.duration,
  width: entry.width,
  height: entry.height,
  ownerMid: entry.ownerMid,
  ownerName: entry.ownerName,
  ownerFace: entry.ownerFace,
  ownerFans: entry.ownerFans,
  following: entry.following,
  views: entry.views,
  likes: entry.likes,
  replies: entry.replies,
  coins: entry.coins,
  favourites: entry.favourites,
  shares: entry.shares,
  danmaku: entry.danmaku,
  seasonTitle: entry.seasonTitle,
  seasonIndex: entry.seasonIndex,
  seasonTotal: entry.seasonTotal,
  source: source,
);
