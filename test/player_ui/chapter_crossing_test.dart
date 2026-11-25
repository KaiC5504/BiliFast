import 'dart:async';

import 'package:bili_core/api.dart' show Chapter;
import 'package:bilifast/player_ui/chapter_crossing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _chapters = [
  Chapter(from: 0, to: 30, title: '开场'),
  Chapter(from: 30, to: 70, title: '正片'),
  Chapter(from: 70, to: 100, title: '结尾'),
];

void main() {
  test('moving past a start crosses it, forward and back', () {
    expect(ChapterCrossing.crossed(_chapters, 25, 35), isTrue);
    expect(ChapterCrossing.crossed(_chapters, 35, 25), isTrue);
    expect(ChapterCrossing.crossed(_chapters, 65, 75), isTrue);
    expect(ChapterCrossing.crossed(_chapters, 75, 65), isTrue);
  });

  test('several starts in one move are one crossing', () {
    expect(ChapterCrossing.crossed(_chapters, 10, 90), isTrue);
    expect(ChapterCrossing.crossed(_chapters, 90, 10), isTrue);
  });

  test('moving inside one chapter, or not at all, crosses nothing', () {
    expect(ChapterCrossing.crossed(_chapters, 35, 65), isFalse);
    expect(ChapterCrossing.crossed(_chapters, 65, 35), isFalse);
    expect(ChapterCrossing.crossed(_chapters, 40, 40), isFalse);
    expect(ChapterCrossing.crossed(_chapters, 30, 30), isFalse);
  });

  test('a position on a start is past it: arriving crosses, leaving forward does not, leaving back does', () {
    expect(ChapterCrossing.crossed(_chapters, 25, 30), isTrue);
    expect(ChapterCrossing.crossed(_chapters, 30, 35), isFalse);
    expect(ChapterCrossing.crossed(_chapters, 35, 30), isFalse);
    expect(ChapterCrossing.crossed(_chapters, 30, 25), isTrue);
  });

  test("the first chapter's start is the bar's own, never a dot", () {
    expect(ChapterCrossing.crossed(_chapters, 0, 20), isFalse);
    expect(ChapterCrossing.crossed(_chapters, 20, 0), isFalse);
    expect(ChapterCrossing.crossed(const [Chapter(from: 5, to: 100, title: '')], 0, 20), isFalse);
  });

  test('no chapters, or a position not yet known, cross nothing', () {
    expect(ChapterCrossing.crossed(const [], 0, 100), isFalse);
    expect(ChapterCrossing.crossed(_chapters, double.nan, 50), isFalse);
    expect(ChapterCrossing.crossed(_chapters, 10, double.infinity), isFalse);
  });

  group('one drag, a point of slack (0.5 s a point here)', () {
    late ChapterTicker ticker;
    setUp(() => ticker = ChapterTicker());
    bool move(double from, double to) => ticker.moved(_chapters, from, to, secondsPerPoint: 0.5);

    test('jitter across a dot ticks once', () {
      expect(move(25, 30.1), isTrue);
      expect(move(30.1, 29.9), isFalse);
      expect(move(29.9, 30.1), isFalse);
      expect(move(30.1, 29.8), isFalse);
      expect(move(29.8, 35), isFalse, reason: 'going on past it is the same crossing');
      expect(move(35, 25), isTrue, reason: 'left behind, it ticks when crossed again');
    });

    test('stopped on a dot, going back ticks as it leaves the point around it', () {
      expect(move(25, 30.2), isTrue);
      expect(move(30.2, 29.9), isFalse);
      expect(move(29.9, 29.6), isFalse);
      expect(move(29.6, 29.4), isTrue);
      expect(move(29.4, 29), isFalse);
    });

    test('one tick a move however many dots, holding the one nearest where it ends', () {
      expect(move(10, 70.2), isTrue);
      expect(move(70.2, 69.9), isFalse);
      expect(move(69.9, 50), isTrue);
      expect(move(50, 29.9), isTrue);
    });

    test('a new drag forgets the held dot', () {
      expect(move(25, 30.1), isTrue);
      ticker.reset();
      expect(move(30.1, 29.9), isTrue);
    });

    test('nothing for a position not yet known, nor without chapters', () {
      expect(move(double.nan, 50), isFalse);
      expect(ticker.moved(const [], 0, 100, secondsPerPoint: 0.5), isFalse);
    });
  });

  group('the tick', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    Future<List<Object>> tickCaught() async {
      final errors = <Object>[];
      await runZonedGuarded(() async {
        ChapterCrossing.tick();
        await pumpEventQueue();
      }, (error, _) => errors.add(error));
      return errors;
    }

    test('is the selection click', () async {
      final calls = <Object?>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call.arguments);
        return null;
      });
      expect(await tickCaught(), isEmpty);
      expect(calls, ['HapticFeedbackType.selectionClick']);
    });

    test("is quiet where the platform has no haptics (Windows), and lets any other failure through", () async {
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => throw MissingPluginException());
      expect(await tickCaught(), isEmpty);
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => throw PlatformException(code: 'x'));
      expect(await tickCaught(), [isA<PlatformException>()]);
    });
  });
}
