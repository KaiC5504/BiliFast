import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/video/story/story_feed.dart';
import 'package:bilifast/video/story/story_list.dart';
import 'package:flutter_test/flutter_test.dart';

const entered = 'BV1entered00';
const recommended = PlaySource(fromSpmid: 'tm.recommend.0.0', from: '7', trackId: 'TRACK.E', flowData: '{"e":1}');

StoryEntry enteredEntry({int? cid = 11}) => StoryEntry(
  bvid: entered,
  aid: 100,
  cid: cid,
  title: '进入的视频',
  cover: 'cover',
  ownerMid: 1,
  ownerName: 'UP',
  source: recommended,
);

StoryItem item(String bvid, {String? track, String? flow}) => StoryItem(
  aid: bvid.hashCode,
  bvid: bvid,
  cid: 7,
  title: bvid,
  cover: 'c',
  duration: 30,
  width: 1080,
  height: 1920,
  ownerMid: 2,
  ownerName: 'O',
  trackId: track ?? 'T.$bvid',
  flowData: flow,
);

VideoCard card(String bvid, {int cid = 0}) => VideoCard(
  aid: 1,
  bvid: bvid,
  cid: cid,
  title: bvid,
  cover: 'c',
  duration: 30,
  ownerMid: 2,
  ownerName: 'O',
  views: 0,
  danmaku: 0,
  likes: 0,
);

final class FakeHost extends StoryHost {
  FakeHost({this.playing});

  @override
  String bvid = entered;

  @override
  StoryEntry? playing;

  @override
  bool halted = false;

  @override
  String? framed;

  @override
  bool comfortable = false;

  final Map<String, List<VideoCard>> loaded = {};
  final List<StoryEntry> opened = [];
  final List<bool> openedEntered = [];
  final List<VideoDetail?> openedWith = [];
  final List<(StoryEntry, VideoDetail)> warms = [];
  int warmDrops = 0;

  /// Thrown by the next warms, as the playurl call's error.
  Object? warmError;
  bool disposed = false;

  void changed() => notifyListeners();

  /// The page opening a video of its own (自动连播, 选集).
  void plays(String other, {StoryEntry? details}) {
    bvid = other;
    playing = details;
    notifyListeners();
  }

  @override
  List<VideoCard>? loadedRelated(String bvid) => loaded[bvid];

  @override
  void open(StoryEntry entry, {required bool entered, VideoDetail? detail}) {
    opened.add(entry);
    openedEntered.add(entered);
    openedWith.add(detail);
    bvid = entry.bvid;
    playing = null;
    framed = null;
    comfortable = false;
    notifyListeners();
  }

  @override
  void halt() => halted = true;

  /// Holds the page's player from warming, as a covered page does: no warm starts.
  bool warmRefused = false;

  /// Holds the next warms until the test completes it.
  Completer<void>? warmGate;

  @override
  Future<void>? warm(StoryEntry entry, VideoDetail detail) {
    if (warmRefused) return null;
    warms.add((entry, detail));
    return () async {
      await warmGate?.future;
      if (warmError case final error?) throw error;
    }();
  }

  @override
  void dropWarm() => warmDrops++;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

typedef OfficialAsk = ({int aid, int cid, int page, PlaySource entry, String? trackId});

/// 竖屏's list: the entered video first, the official feed's pages or the related lists after it, asked near the end
/// one call at a time, and the source each entry's plays report.
void main() {
  late FakeHost host;
  late MemorySink logs;
  late Logger logger;
  late List<OfficialAsk> officialAsks;
  late List<Completer<List<StoryItem>>> officialAnswers;
  late List<String> relatedAsks;
  late List<Completer<List<VideoCard>>> relatedAnswers;
  late List<String> detailAsks;
  late List<Completer<VideoDetail>> detailAnswers;
  late int notified;

  setUp(() {
    host = FakeHost(playing: enteredEntry());
    logs = MemorySink();
    logger = Logger(session: 'test')..add(logs);
    officialAsks = [];
    officialAnswers = [];
    relatedAsks = [];
    relatedAnswers = [];
    detailAsks = [];
    detailAnswers = [];
    notified = 0;
  });

  Future<List<StoryItem>> official({
    required int aid,
    required int cid,
    required int page,
    required PlaySource entry,
    String? trackId,
  }) {
    officialAsks.add((aid: aid, cid: cid, page: page, entry: entry, trackId: trackId));
    final answer = Completer<List<StoryItem>>();
    officialAnswers.add(answer);
    return answer.future;
  }

  Future<List<VideoCard>> related(String bvid) {
    relatedAsks.add(bvid);
    final answer = Completer<List<VideoCard>>();
    relatedAnswers.add(answer);
    return answer.future;
  }

  Future<VideoDetail> detail(String bvid) {
    detailAsks.add(bvid);
    final answer = Completer<VideoDetail>();
    detailAnswers.add(answer);
    return answer.future;
  }

  StoryList make({bool useOfficial = true, bool ahead = false, bool warms = false}) {
    final on = host;
    final feed = StoryList(
      host: on,
      official: useOfficial ? official : null,
      related: related,
      detail: ahead ? detail : null,
      warmsNext: warms,
      logger: logger,
    )..addListener(() => notified++);
    addTearDown(() {
      if (!on.disposed) feed.dispose();
    });
    return feed;
  }

  List<String> bvids(StoryFeed feed) => [for (final entry in feed.entries) entry.bvid];

  List<Map<String, Object>> feedLines() => [
    for (final event in logs.events)
      if (event.msg == 'story feed') {for (final MapEntry(:key, :value) in event.f.entries) key: value.toJson()},
  ];

  Future<void> answerOfficial(List<StoryItem> items) async {
    officialAnswers.last.complete(items);
    await pumpEventQueue();
  }

  Future<void> answerRelated(List<VideoCard> cards) async {
    relatedAnswers.last.complete(cards);
    await pumpEventQueue();
  }

  group('the entered video', () {
    test('is the first entry, reporting as story-single from where it was entered, with its own track data', () {
      final feed = make();
      expect(bvids(feed), [entered]);
      expect(feed.index, 0);
      expect(feed.current!.cid, 11);
      final source = feed.current!.source;
      expect(source.spmid, PlaySource.verticalPage);
      expect(source.fromSpmid, 'tm.recommend.0.0');
      expect(source.from, 'default-value');
      expect(source.historySource, 'story-single');
      expect(source.trackId, 'TRACK.E');
      expect(source.flowData, '{"e":1}');
      expect(feed.next, isNull);
      expect(feed.previous, isNull);
    });

    test('a missing part is waited for with one debug line, however often the page changes meanwhile', () {
      host.playing = enteredEntry(cid: null);
      make();
      host.changed();
      host.changed();
      expect(officialAsks, isEmpty);
      expect(logs.events.where((event) => event.msg == 'story feed waits for the part'), hasLength(1));
    });

    test('filled in once its details arrive, with a notification; nothing is asked before', () async {
      host.playing = null;
      final feed = make();
      expect(feed.entries, isEmpty);
      expect(feed.current, isNull);
      expect(officialAsks, isEmpty);
      host
        ..playing = enteredEntry()
        ..changed();
      expect(bvids(feed), [entered]);
      expect(notified, greaterThan(0));
      expect(officialAsks, hasLength(1));
    });

    test('the official feed waits for its part; its part changing while it plays updates the entry', () async {
      host.playing = enteredEntry(cid: null);
      final feed = make();
      expect(bvids(feed), [entered]);
      expect(officialAsks, isEmpty);
      host
        ..playing = enteredEntry(cid: 12)
        ..changed();
      expect(feed.current!.cid, 12);
      expect(officialAsks.single.cid, 12);
    });

    test('another video\'s details on the page are not taken for it', () {
      host.playing = null;
      final feed = make();
      host
        ..playing = const StoryEntry(
          bvid: 'BV1other0000',
          title: '',
          cover: '',
          ownerMid: 0,
          ownerName: '',
          source: PlaySource.unknown,
          cid: 99,
        )
        ..changed();
      expect(feed.entries, isEmpty);
      host
        ..playing = enteredEntry()
        ..changed();
      expect(bvids(feed), [entered]);
      expect(feed.current!.cid, 11);
    });
  });

  group('the official feed', () {
    test('page 1 names the entered video and its card\'s track id; the entered video in it is skipped', () async {
      final feed = make();
      expect(feed.loading, isTrue);
      final ask = officialAsks.single;
      expect((ask.aid, ask.cid, ask.page, ask.trackId), (100, 11, 1, 'TRACK.E'));
      expect(identical(ask.entry, recommended), isTrue);
      await answerOfficial([item(entered), item('BV1a'), item('BV1b', flow: '{"f":2}')]);
      expect(officialAsks.last.page, 2, reason: 'two ahead: the next page is asked at once');
      expect(bvids(feed), [entered, 'BV1a', 'BV1b']);
      final b = feed.entries[2].source;
      expect(b.spmid, PlaySource.verticalPage);
      expect(b.from, 'default-value');
      expect(b.fromSpmid, 'tm.recommend.0.0');
      expect(b.trackId, 'T.BV1b');
      expect(b.flowData, '{"f":2}');
      expect(b.historySource, 'story-series');
      expect(feed.entries[1].source.flowData, isNull);
      expect(feed.entries[1].upright, isTrue);
    });

    test('more is asked once the index is within three of the end, the same track id on every page', () async {
      final feed = make();
      await answerOfficial([item(entered), for (var i = 1; i <= 5; i++) item('BV1p1n$i')]);
      expect(officialAsks, hasLength(1), reason: 'five ahead');
      expect(feed.moveNext(), isTrue);
      expect(officialAsks, hasLength(1), reason: 'four ahead');
      expect(feed.moveNext(), isTrue);
      expect(officialAsks, hasLength(2), reason: 'three ahead');
      expect((officialAsks.last.page, officialAsks.last.trackId), (2, 'TRACK.E'));
      expect(feed.moveNext(), isTrue);
      expect(officialAsks, hasLength(2), reason: 'one call out at a time');
      await answerOfficial([item('BV1p2n1'), item('BV1p1n5')]);
      expect(bvids(feed).skip(6), ['BV1p2n1']);
      expect(feedLines().last, {'source': 'official', 'page': 2, 'kept': 1, 'dropped': 1});
      expect(officialAsks, hasLength(3), reason: 'still within three: the next page follows');
      expect(officialAsks.last.page, 3);
    });

    test('a page that adds nothing new waits until the user swipes on past the end: one call each time', () async {
      final feed = make();
      await answerOfficial([item(entered)]);
      expect(officialAsks, hasLength(1));
      expect(feed.loading, isFalse);
      expect(feed.moveNext(), isFalse);
      expect(officialAsks, hasLength(1), reason: 'a refused move asks nothing; the pager says so with wantMore');
      feed.wantMore();
      expect(officialAsks, hasLength(2));
      expect(officialAsks.last.page, 2);
      feed.wantMore();
      expect(officialAsks, hasLength(2), reason: 'one call out at a time');
      await answerOfficial([item(entered)]);
      expect(officialAsks, hasLength(2), reason: 'nothing new again: it waits');
      feed.wantMore();
      expect(officialAsks, hasLength(3));
      expect(officialAsks.last.page, 3);
    });

    test('a failed call hands over to the entered video\'s related list for good', () async {
      final feed = make();
      officialAnswers.last.completeError(const BiliNetworkError('SocketException'));
      await pumpEventQueue();
      expect(relatedAsks, [entered]);
      expect(feed.official, isFalse);
      await answerRelated([card('BV1r1'), card('BV1r2', cid: 5)]);
      expect(bvids(feed), [entered, 'BV1r1', 'BV1r2']);
      expect(feed.entries[1].cid, isNull);
      expect(feed.entries[2].cid, 5);
      final source = feed.entries[1].source;
      expect(source.historySource, 'story-series');
      expect(source.spmid, PlaySource.verticalPage);
      expect(source.trackId, isNull);
      expect(source.flowData, isNull);
      expect(feedLines().first, {'source': 'official', 'page': 1, 'error': 'BiliNetworkError', 'handover': 'failed'});
      expect(officialAsks, hasLength(1));
    });

    test('no token any more (the client refuses): the related lists', () async {
      make();
      officialAnswers.last.completeError(BiliError.noAppToken);
      await pumpEventQueue();
      expect(relatedAsks, [entered]);
    });

    test('a page with no videos at all: the related lists carry on, and the log says why', () async {
      final feed = make();
      await answerOfficial([item(entered), item('BV1a')]);
      expect(officialAsks, hasLength(2));
      await answerOfficial([]);
      expect(feed.official, isFalse);
      expect(relatedAsks, [entered]);
      expect(feedLines()[1], {'source': 'official', 'page': 2, 'kept': 0, 'dropped': 0, 'handover': 'empty'});
    });

    for (final (name, error) in [
      ('-352', const BiliAPIError(code: -352, message: '')),
      ('-412', const BiliAPIError(code: -412, message: '')),
      ('HTTP 412', const BiliHTTPError(412)),
    ]) {
      test('risk control ($name) stops asking for the page\'s life, the next feed on it too', () async {
        final feed = make();
        officialAnswers.last.completeError(error);
        await pumpEventQueue();
        expect(host.halted, isTrue);
        expect(relatedAsks, isEmpty);
        expect(feed.moveNext(), isFalse);
        feed
          ..wantMore()
          ..wantMore();
        expect(officialAsks, hasLength(1));
        expect(relatedAsks, isEmpty);
        expect(feedLines().single, containsPair('stopped', true));
        expect(feedLines().single.containsKey('handover'), isFalse);
        expect(feedLines().single['code'], error is BiliHTTPError ? 412 : (error as BiliAPIError).code);

        host = FakeHost(playing: enteredEntry())..halted = true;
        final again = make();
        again.wantMore();
        expect(bvids(again), [entered]);
        expect(officialAsks, hasLength(1));
        expect(relatedAsks, isEmpty);
      });
    }
  });

  group('the related lists', () {
    test('the page\'s loaded list is taken without a call; then the last entry\'s, skipping what is listed', () async {
      host.loaded[entered] = [card('BV1r1'), card('BV1r2')];
      final feed = make(useOfficial: false);
      expect(relatedAsks, ['BV1r2'], reason: 'the entered video\'s list was loaded: the last entry\'s is next');
      expect(feedLines().first, {'source': 'related', 'page': 1, 'kept': 2, 'dropped': 0, 'loaded': true});
      await answerRelated([card(entered), card('BV1r1'), card('BV1r3')]);
      expect(bvids(feed), [entered, 'BV1r1', 'BV1r2', 'BV1r3']);
      expect(feedLines().last, {'source': 'related', 'page': 2, 'kept': 1, 'dropped': 2});
      expect(relatedAsks, ['BV1r2', 'BV1r3'], reason: 'still within three of the end');
    });

    test('without a loaded list the entered video\'s is asked', () async {
      final feed = make(useOfficial: false);
      expect(relatedAsks, [entered]);
      expect(feed.loading, isTrue);
    });

    for (final (name, error) in [
      ('HTTP 500', const BiliHTTPError(500)),
      ('no network', const BiliNetworkError('SocketException')),
    ]) {
      test('a call that failed in passing ($name) is asked again only when the user swipes on past the end', () async {
        final feed = make(useOfficial: false);
        relatedAnswers.last.completeError(error);
        await pumpEventQueue();
        expect(feed.loading, isFalse);
        expect(relatedAsks, [entered]);
        host.changed();
        expect(relatedAsks, [entered], reason: 'the page changing is not a move');
        expect(feed.moveNext(), isFalse);
        expect(feed.index, 0);
        expect(host.opened, isEmpty);
        expect(relatedAsks, [entered]);
        feed.wantMore();
        expect(relatedAsks, [entered, entered], reason: 'that list was never answered');
      });
    }

    test('a list Bilibili refused (a removed video) is never asked again; the next swipe asks another entry\'s',
        () async {
      final feed = make(useOfficial: false);
      relatedAnswers.last.completeError(const BiliAPIError(code: -404, message: ''));
      await pumpEventQueue();
      feed
        ..wantMore()
        ..wantMore();
      expect(relatedAsks, [entered], reason: 'no other entry to ask by');
      expect(feedLines().single, {'source': 'related', 'page': 1, 'error': 'BiliAPIError', 'code': -404});

      host
        ..playing = enteredEntry(cid: 12)
        ..changed();
      expect(relatedAsks, [entered], reason: 'the entered video\'s part changing asks nothing of a stalled feed');
    });

    test('a refused list among others: the move after it asks the next entry\'s', () async {
      final feed = make(useOfficial: false);
      await answerRelated([card('BV1r1'), card('BV1r2')]);
      expect(relatedAsks, [entered, 'BV1r2']);
      relatedAnswers.last.completeError(const BiliAPIError(code: 62002, message: ''));
      await pumpEventQueue();
      expect(relatedAsks, hasLength(2), reason: 'waits for a move');
      expect(feed.moveNext(), isTrue);
      expect(relatedAsks, [entered, 'BV1r2', 'BV1r1']);
      relatedAnswers.last.completeError(const BiliAPIError(code: -404, message: ''));
      await pumpEventQueue();
      expect(feed.moveNext(), isTrue);
      feed.wantMore();
      expect(relatedAsks, hasLength(3), reason: 'every listed video\'s list was asked');
    });

    test('a list that adds nothing waits for a move, and each video\'s list is asked once', () async {
      final feed = make(useOfficial: false);
      await answerRelated([card('BV1r1')]);
      expect(relatedAsks, [entered, 'BV1r1']);
      await answerRelated([card(entered)]);
      expect(relatedAsks, hasLength(2));
      expect(feed.moveNext(), isTrue);
      expect(relatedAsks, hasLength(2), reason: 'every listed video\'s list was asked');
    });
  });

  group('moving', () {
    test('opens the neighbour on the page as a video swiped to; false and nothing changed with none', () async {
      final feed = make(useOfficial: false);
      expect(feed.movePrevious(), isFalse);
      await answerRelated([card('BV1r1'), card('BV1r2')]);
      final before = notified;
      expect(feed.moveNext(), isTrue);
      expect(feed.index, 1);
      expect(notified, greaterThan(before));
      expect(host.opened.single.bvid, 'BV1r1');
      expect(feed.current!.bvid, 'BV1r1');
      expect(feed.previous!.bvid, entered);

      expect(feed.movePrevious(), isTrue);
      expect(feed.index, 0);
      final back = host.opened.last;
      expect(back.bvid, entered);
      expect(back.cid, 11);
      expect(back.source.historySource, 'story-single');
      expect(back.source.trackId, 'TRACK.E');
      expect(feed.movePrevious(), isFalse);
      expect(feed.index, 0);
      expect(host.opened, hasLength(2));
      expect(host.openedEntered, [false, true], reason: 'the entered video opens as the user\'s own, auto_play 0');
    });

    test('a video swiped back to that is not the entered one opens as swiped to', () async {
      final feed = make(useOfficial: false);
      await answerRelated([card('BV1r1'), card('BV1r2')]);
      feed
        ..moveNext()
        ..moveNext()
        ..movePrevious();
      expect(host.opened.map((entry) => entry.bvid), ['BV1r1', 'BV1r2', 'BV1r1']);
      expect(host.openedEntered, [false, false, false]);
    });

    test('swiped back to the first entry, it keeps its 竖屏 source as its details come in again', () async {
      final feed = make(useOfficial: false);
      await answerRelated([card('BV1r1')]);
      feed
        ..moveNext()
        ..movePrevious();
      host
        ..playing = enteredEntry()
        ..changed();
      expect(feed.current!.source.historySource, 'story-single');
      expect(bvids(feed).first, entered);
    });
  });

  group('a video the page opened itself', () {
    StoryEntry other({int cid = 21, PlaySource source = PlaySource.unknown}) => StoryEntry(
      bvid: 'BV1autonext0',
      aid: 200,
      cid: cid,
      title: '自动连播的',
      cover: 'cover',
      ownerMid: 3,
      ownerName: 'UP3',
      source: source,
    );

    test('starts the feed over from it: one entry, its own feed asked from page 1, where 竖屏 was entered from kept',
        () async {
      final feed = make();
      await answerOfficial([item(entered), item('BV1a'), item('BV1b')]);
      feed.moveNext();
      expect(officialAsks, hasLength(2));
      final before = notified;

      const trackOfIt = PlaySource(fromSpmid: 'united.player-video-detail.relatedvideo.0', trackId: 'T.auto');
      host.plays('BV1autonext0');
      expect(feed.entries, isEmpty, reason: 'its details are not in yet');
      expect(feed.current, isNull);
      expect(feed.index, 0);
      expect(notified, greaterThan(before));
      host
        ..playing = other(source: trackOfIt)
        ..changed();
      expect(bvids(feed), ['BV1autonext0']);
      expect(feed.previous, isNull);
      final source = feed.current!.source;
      expect(source.historySource, 'story-single');
      expect(source.fromSpmid, 'tm.recommend.0.0');
      expect(source.trackId, 'T.auto');
      expect(officialAsks, hasLength(3));
      final ask = officialAsks.last;
      expect((ask.aid, ask.cid, ask.page, ask.trackId), (200, 21, 1, 'TRACK.E'));
      expect(identical(ask.entry, recommended), isTrue);

      officialAnswers[1].complete([item('BV1old')]);
      await pumpEventQueue();
      expect(bvids(feed), ['BV1autonext0'], reason: 'an answer asked before the start over is dropped');
      expect(feed.loading, isTrue, reason: 'the new page 1 is still out');
      await answerOfficial([item('BV1autonext0'), item('BV1c')]);
      expect(bvids(feed), ['BV1autonext0', 'BV1c']);
      expect(officialAsks.last.page, 2);
      expect(logs.events.where((event) => event.msg == 'story feed restarted'), hasLength(1));
    });

    test('with its details in already, at once; the related lists are asked from it', () async {
      final feed = make(useOfficial: false);
      await answerRelated([card('BV1r1')]);
      expect(relatedAsks, [entered, 'BV1r1']);
      host.plays('BV1autonext0', details: other());
      expect(bvids(feed), ['BV1autonext0']);
      expect(relatedAsks, [entered, 'BV1r1', 'BV1autonext0']);
      relatedAnswers[1].complete([card('BV1old')]);
      await pumpEventQueue();
      expect(bvids(feed), ['BV1autonext0']);
      await answerRelated([card(entered), card('BV1r1')]);
      expect(bvids(feed), ['BV1autonext0', entered, 'BV1r1'], reason: 'the old entries are new to it');
    });

    test('a video the feed opened itself is no start over, whatever details the page has meanwhile', () async {
      final feed = make(useOfficial: false);
      await answerRelated([card('BV1r1')]);
      feed.moveNext();
      host
        ..playing = other()
        ..changed();
      expect(bvids(feed), [entered, 'BV1r1']);
      expect(feed.index, 1);
      expect(logs.events.where((event) => event.msg == 'story feed restarted'), isEmpty);
    });
  });

  group("the next video's details, asked ahead", () {
    VideoDetail details(String bvid, {String? redirect}) =>
        VideoDetail.fromJson({'bvid': bvid, 'aid': 1, 'redirect_url': ?redirect});

    Future<void> answerDetail(int at, VideoDetail answer) async {
      detailAnswers[at].complete(answer);
      await pumpEventQueue();
    }

    List<Map<String, Object>> lines(String msg) => [
      for (final event in logs.events)
        if (event.msg == msg) {for (final MapEntry(:key, :value) in event.f.entries) key: value.toJson()},
    ];

    test('once for each video settled on, the next one only, kept while a neighbour and handed to its open', () async {
      final feed = make(useOfficial: false, ahead: true);
      expect(detailAsks, isEmpty, reason: 'no next video known yet');
      await answerRelated([card('BV1r1'), card('BV1r2'), card('BV1r3')]);
      expect(detailAsks, ['BV1r1']);
      host.changed();
      feed.wantMore();
      expect(detailAsks, ['BV1r1'], reason: 'one call for the video settled on');
      final first = details('BV1r1');
      await answerDetail(0, first);
      expect(lines('story detail ahead').single.keys, ['ms']);

      expect(feed.moveNext(), isTrue);
      expect(identical(host.openedWith.single, first), isTrue);
      expect(detailAsks, ['BV1r1', 'BV1r2']);
      feed.wantMore();
      expect(detailAsks, hasLength(2));

      expect(feed.moveNext(), isTrue);
      expect(host.openedWith.last, isNull, reason: 'moved on before the answer: the open asks for itself');
      expect(detailAsks, ['BV1r1', 'BV1r2', 'BV1r3']);
      await answerDetail(1, details('BV1r2'));

      expect(feed.movePrevious(), isTrue);
      expect(identical(host.openedWith.last, first), isTrue, reason: 'the video before is still a neighbour');
      expect(detailAsks, hasLength(3), reason: 'the next one is in hand');
      expect(feed.moveNext(), isTrue);
      expect(host.openedWith.last?.bvid, 'BV1r2');
    });

    test('none while the feed is halted; risk control on the ask halts it', () async {
      final halted = make(useOfficial: false, ahead: true);
      host.halted = true;
      await answerRelated([card('BV1r1'), card('BV1r2')]);
      expect(halted.next?.bvid, 'BV1r1');
      expect(halted.moveNext(), isTrue);
      expect(detailAsks, isEmpty);
      expect(host.openedWith.single, isNull);

      host = FakeHost(playing: enteredEntry())..loaded[entered] = [card('BV1r1'), card('BV1r2')];
      final feed = make(useOfficial: false, ahead: true);
      expect(detailAsks, ['BV1r1']);
      detailAnswers.last.completeError(const BiliAPIError(code: -352, message: ''));
      await pumpEventQueue();
      expect(host.halted, isTrue);
      expect(lines('story detail ahead').single, {'error': 'BiliAPIError', 'code': -352, 'stopped': true});
      expect(feed.moveNext(), isTrue);
      expect(host.openedWith.single, isNull);
      expect(detailAsks, hasLength(1));
    });

    test('risk control on an ask answered after a start over or the end of 竖屏 still halts the page', () async {
      host.loaded[entered] = [card('BV1r1')];
      make(useOfficial: false, ahead: true);
      expect(detailAsks, ['BV1r1']);
      host.plays('BV1autonext0');
      detailAnswers.last.completeError(const BiliAPIError(code: -352, message: ''));
      await pumpEventQueue();
      expect(host.halted, isTrue);
      expect(lines('story detail ahead'), isEmpty);

      host = FakeHost(playing: enteredEntry())..loaded[entered] = [card('BV1r1')];
      final feed = make(useOfficial: false, ahead: true);
      expect(detailAsks, hasLength(2));
      feed.dispose();
      detailAnswers.last.completeError(const BiliHTTPError(412));
      await pumpEventQueue();
      expect(host.halted, isTrue);

      host = FakeHost(playing: enteredEntry());
      final asked = relatedAsks.length;
      final related = make(useOfficial: false);
      expect(relatedAsks, hasLength(asked + 1));
      related.dispose();
      relatedAnswers.last.completeError(const BiliAPIError(code: -412, message: ''));
      await pumpEventQueue();
      expect(host.halted, isTrue);
    });

    test("another video's answer, or a video that redirects, is not handed on", () async {
      host.loaded[entered] = [card('BV1r1'), card('BV1r2')];
      final feed = make(useOfficial: false, ahead: true);
      await answerDetail(0, details('BV1other0000'));
      expect(lines('story detail ahead').single, containsPair('dropped', true));
      feed.moveNext();
      expect(host.openedWith.single, isNull);
      await answerDetail(1, details('BV1r2', redirect: 'https://www.bilibili.com/bangumi/play/ep1'));
      feed.moveNext();
      expect(host.openedWith.last, isNull);
    });

    test('a start over or the end of 竖屏 drops what was asked', () async {
      host.loaded[entered] = [card('BV1r1')];
      final feed = make(useOfficial: false, ahead: true);
      expect(detailAsks, ['BV1r1']);
      host.plays('BV1autonext0');
      await answerDetail(0, details('BV1r1'));
      expect(lines('story detail ahead'), isEmpty, reason: 'asked before the start over');
      host
        ..playing = const StoryEntry(
          bvid: 'BV1autonext0',
          aid: 200,
          cid: 21,
          title: '',
          cover: '',
          ownerMid: 3,
          ownerName: '',
          source: PlaySource.unknown,
        )
        ..changed();
      await answerRelated([card('BV1r1')]);
      expect(detailAsks, ['BV1r1', 'BV1r1'], reason: 'asked again for the new start');
      feed.dispose();
      await answerDetail(1, details('BV1r1'));
      expect(lines('story detail ahead'), isEmpty);
    });

    test('each arrival logs the time from the move to its first frame and whether its details were in, no ids',
        () async {
      host.loaded[entered] = [card('BV1r1'), card('BV1r2')];
      final feed = make(useOfficial: false, ahead: true);
      await answerDetail(0, details('BV1r1'));
      feed.moveNext();
      host
        ..framed = entered
        ..changed();
      expect(lines('story arrival'), isEmpty, reason: "the last video's frame doesn't count");
      host
        ..framed = 'BV1r1'
        ..changed()
        ..changed();
      expect(lines('story arrival').single.keys.toSet(), {'ms', 'prefetched'});
      expect(lines('story arrival').single['ms'], isA<int>());
      expect(lines('story arrival').single['prefetched'], isTrue);

      feed.moveNext();
      host
        ..framed = 'BV1r2'
        ..changed();
      expect(lines('story arrival').last['prefetched'], isFalse, reason: 'moved before its answer');
      expect(lines('story arrival'), hasLength(2));
      for (final line in [...lines('story arrival'), ...lines('story detail ahead')]) {
        for (final value in line.values) {
          expect('$value', isNot(contains('BV1')));
        }
      }
    });
  });

  group('the next video loaded ahead', () {
    VideoDetail details(String bvid) => VideoDetail.fromJson({'bvid': bvid, 'aid': 1});

    Future<void> answerDetail(int at, VideoDetail answer) async {
      detailAnswers[at].complete(answer);
      await pumpEventQueue();
    }

    void plays(String bvid, {bool comfortable = true}) => host
      ..framed = bvid
      ..comfortable = comfortable
      ..changed();

    List<String> warmed() => [for (final (entry, _) in host.warms) entry.bvid];

    test('once for each video settled on: after its first frame, with enough held ahead and the next details in hand',
        () async {
      host.loaded[entered] = [card('BV1r1'), card('BV1r2'), card('BV1r3')];
      final feed = make(useOfficial: false, ahead: true, warms: true);
      final first = details('BV1r1');
      await answerDetail(0, first);
      expect(host.warms, isEmpty, reason: 'the entered video has not shown its first frame');
      plays(entered, comfortable: false);
      expect(host.warms, isEmpty, reason: 'not enough of it held ahead');
      plays(entered);
      expect(warmed(), ['BV1r1']);
      expect(identical(host.warms.single.$2, first), isTrue, reason: 'with the details asked ahead');
      host.changed();
      feed.wantMore();
      expect(warmed(), ['BV1r1'], reason: 'once for the video settled on');

      expect(feed.moveNext(), isTrue);
      expect(identical(host.openedWith.single, first), isTrue);
      plays('BV1r1');
      expect(warmed(), ['BV1r1'], reason: 'the next details are not in yet');
      await answerDetail(1, details('BV1r2'));
      expect(warmed(), ['BV1r1', 'BV1r2'], reason: 'their answer loads it');

      expect(feed.movePrevious(), isTrue);
      plays(entered);
      expect(warmed(), ['BV1r1', 'BV1r2', 'BV1r1'], reason: 'swiped back, the next one again, never the one before');
    });

    test('none while halted', () async {
      host.loaded[entered] = [card('BV1r1')];
      make(useOfficial: false, ahead: true, warms: true);
      await answerDetail(0, details('BV1r1'));
      host.halted = true;
      plays(entered);
      expect(host.warms, isEmpty);
    });

    test('risk control on its playurl call halts the feed; any other failure only loses the head start', () async {
      host
        ..loaded[entered] = [card('BV1r1'), card('BV1r2')]
        ..warmError = const BiliNetworkError('offline');
      final feed = make(useOfficial: false, ahead: true, warms: true);
      await answerDetail(0, details('BV1r1'));
      plays(entered);
      await pumpEventQueue();
      expect(warmed(), ['BV1r1']);
      expect(host.halted, isFalse);

      host.warmError = const BiliAPIError(code: -352, message: '');
      feed.moveNext();
      await answerDetail(1, details('BV1r2'));
      plays('BV1r1');
      await pumpEventQueue();
      expect(warmed(), ['BV1r1', 'BV1r2']);
      expect(host.halted, isTrue);
      final halted = logs.events.singleWhere((event) => event.msg == 'story feed halted');
      expect({for (final MapEntry(:key, :value) in halted.f.entries) key: value.toJson()}, {'by': 'warm', 'code': -352});
    });

    test('a warm the page could not start (covered) leaves the slot: asked again once it can, still once', () async {
      host
        ..loaded[entered] = [card('BV1r1')]
        ..warmRefused = true;
      make(useOfficial: false, ahead: true, warms: true);
      await answerDetail(0, details('BV1r1'));
      plays(entered);
      expect(host.warms, isEmpty);
      host.warmRefused = false;
      host.changed();
      expect(warmed(), ['BV1r1']);
      host.changed();
      expect(warmed(), ['BV1r1']);
    });

    test('risk control on a warm answered after 竖屏 ended or the feed started over still halts the page', () async {
      host
        ..loaded[entered] = [card('BV1r1')]
        ..warmGate = Completer<void>()
        ..warmError = const BiliHTTPError(412);
      final feed = make(useOfficial: false, ahead: true, warms: true);
      await answerDetail(0, details('BV1r1'));
      plays(entered);
      expect(warmed(), ['BV1r1']);
      feed.dispose();
      host.warmGate!.complete();
      await pumpEventQueue();
      expect(host.halted, isTrue);
      expect(logs.events.where((event) => event.msg == 'story feed halted'), isEmpty);

      host = FakeHost(playing: enteredEntry())
        ..loaded[entered] = [card('BV1r1')]
        ..warmGate = Completer<void>()
        ..warmError = const BiliAPIError(code: -412, message: '');
      make(useOfficial: false, ahead: true, warms: true);
      await answerDetail(1, details('BV1r1'));
      plays(entered);
      host.plays('BV1autonext0');
      host.warmGate!.complete();
      await pumpEventQueue();
      expect(host.halted, isTrue);
    });

    test('let go when the feed starts over and when 竖屏 ends', () async {
      host.loaded[entered] = [card('BV1r1')];
      final feed = make(useOfficial: false, ahead: true, warms: true);
      await answerDetail(0, details('BV1r1'));
      plays(entered);
      expect(warmed(), ['BV1r1']);
      host.plays('BV1autonext0');
      expect(host.warmDrops, 1);
      feed.dispose();
      expect(host.warmDrops, 2);
    });

    test('nothing is loaded ahead without warmsNext (Windows)', () async {
      host.loaded[entered] = [card('BV1r1')];
      make(useOfficial: false, ahead: true);
      await answerDetail(0, details('BV1r1'));
      plays(entered);
      expect(host.warms, isEmpty);
    });
  });

  test('disposed, a pending answer is dropped and the page is let go', () async {
    final feed = make();
    feed.dispose();
    expect(host.disposed, isTrue);
    await answerOfficial([item(entered), item('BV1a')]);
    expect(feed.entries, [isA<StoryEntry>()]);
    expect(relatedAsks, isEmpty);
    expect(feedLines(), isEmpty);
  });

  test('the log names the source, page and counts, never a video or track data', () async {
    final feed = make();
    await answerOfficial([item(entered), item('BV1a', flow: '{"secret":1}')]);
    feed.moveNext();
    const allowed = {'source', 'page', 'kept', 'dropped', 'error', 'code', 'stopped', 'loaded', 'handover'};
    expect(feedLines(), isNotEmpty);
    for (final line in feedLines()) {
      expect(line.keys.toSet().difference(allowed), isEmpty);
      for (final value in line.values) {
        expect('$value', isNot(contains('BV1')));
        expect('$value', isNot(contains('T.')));
      }
    }
  });
}
