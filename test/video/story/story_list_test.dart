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

  final Map<String, List<VideoCard>> loaded = {};
  final List<StoryEntry> opened = [];
  bool disposed = false;

  void changed() => notifyListeners();

  @override
  List<VideoCard>? loadedRelated(String bvid) => loaded[bvid];

  @override
  void open(StoryEntry entry) {
    opened.add(entry);
    bvid = entry.bvid;
    playing = null;
    notifyListeners();
  }

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
  late int notified;

  setUp(() {
    host = FakeHost(playing: enteredEntry());
    logs = MemorySink();
    logger = Logger(session: 'test')..add(logs);
    officialAsks = [];
    officialAnswers = [];
    relatedAsks = [];
    relatedAnswers = [];
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

  StoryList make({bool useOfficial = true}) {
    final feed = StoryList(host: host, official: useOfficial ? official : null, related: related, logger: logger)
      ..addListener(() => notified++);
    addTearDown(() {
      if (!host.disposed) feed.dispose();
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
    test('is the first entry, reporting as story-single from where it was entered', () {
      final feed = make();
      expect(bvids(feed), [entered]);
      expect(feed.index, 0);
      expect(feed.current!.cid, 11);
      final source = feed.current!.source;
      expect(source.spmid, PlaySource.verticalPage);
      expect(source.fromSpmid, 'tm.recommend.0.0');
      expect(source.from, 'default-value');
      expect(source.historySource, 'story-single');
      expect(source.trackId, isNull, reason: 'the entry card\'s track data was its first play\'s');
      expect(feed.next, isNull);
      expect(feed.previous, isNull);
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

    test('a page that adds nothing new waits for the user\'s next move', () async {
      final feed = make();
      await answerOfficial([item(entered)]);
      expect(officialAsks, hasLength(1));
      expect(feed.loading, isFalse);
      expect(feed.moveNext(), isFalse);
      expect(officialAsks, hasLength(2));
      expect(officialAsks.last.page, 2);
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
      expect(feedLines().first, {'source': 'official', 'page': 1, 'error': 'BiliNetworkError'});
      expect(officialAsks, hasLength(1));
    });

    test('no token any more (the client refuses): the related lists', () async {
      make();
      officialAnswers.last.completeError(BiliError.noAppToken);
      await pumpEventQueue();
      expect(relatedAsks, [entered]);
    });

    test('a page with no videos at all: the related lists carry on', () async {
      final feed = make();
      await answerOfficial([item(entered), item('BV1a')]);
      expect(officialAsks, hasLength(2));
      await answerOfficial([]);
      expect(feed.official, isFalse);
      expect(relatedAsks, [entered]);
    });

    for (final (name, error) in [
      ('-352', const BiliAPIError(code: -352, message: '')),
      ('-412', const BiliAPIError(code: -412, message: '')),
      ('HTTP 412', const BiliHTTPError(412)),
    ]) {
      test('risk control ($name) stops asking for the feed\'s life', () async {
        final feed = make();
        officialAnswers.last.completeError(error);
        await pumpEventQueue();
        expect(relatedAsks, isEmpty);
        expect(feed.moveNext(), isFalse);
        expect(feed.moveNext(), isFalse);
        expect(officialAsks, hasLength(1));
        expect(relatedAsks, isEmpty);
        expect(feedLines().single, containsPair('stopped', true));
        expect(feedLines().single['code'], error is BiliHTTPError ? 412 : (error as BiliAPIError).code);
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

    test('a failed call is not retried until the user moves', () async {
      final feed = make(useOfficial: false);
      relatedAnswers.last.completeError(const BiliHTTPError(500));
      await pumpEventQueue();
      expect(feed.loading, isFalse);
      expect(relatedAsks, [entered]);
      host.changed();
      expect(relatedAsks, [entered], reason: 'the page changing is not a move');
      expect(feed.moveNext(), isFalse);
      expect(feed.index, 0);
      expect(host.opened, isEmpty);
      expect(relatedAsks, [entered, entered], reason: 'that list was never answered');
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
      expect(feed.movePrevious(), isFalse);
      expect(feed.index, 0);
      expect(host.opened, hasLength(2));
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
    const allowed = {'source', 'page', 'kept', 'dropped', 'error', 'code', 'stopped', 'loaded'};
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
