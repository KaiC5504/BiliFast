import 'package:bili_core/devlog.dart';
import 'package:bilifast/video/pip_keeper.dart';
import 'package:flutter_test/flutter_test.dart';

/// A page's playback as the keeper sees it, its picture in picture set by hand.
final class FakeKept implements KeptPlayback {
  FakeKept(this.bvid);

  @override
  final String bvid;

  @override
  bool pipActive = false;

  bool pushes = true;
  final calls = <String>[];

  @override
  void keep() => calls.add('keep');

  @override
  void returned() => calls.add('returned');

  @override
  void close() => calls.add('close');

  @override
  bool pushPage() {
    calls.add('push');
    return pushes;
  }
}

/// BiliNative's PiPKeeper rules (VideoPageModelTests): one video at a time, a popped page kept while the small window
/// plays it, the restore button bringing it back, ✕ and another video releasing it.
void main() {
  late MemorySink logs;
  late PipKeeper keeper;
  late FakeKept first;
  late FakeKept second;

  setUp(() {
    logs = MemorySink();
    keeper = PipKeeper(logger: Logger(session: 'test')..add(logs));
    first = FakeKept('BV1first');
    second = FakeKept('BV1second');
  });

  List<String> logged() => [for (final event in logs.events) '${event.msg} ${event.f['bvid']?.toJson()}'];

  test('a page popped without picture in picture closes; one popped in it is kept', () {
    keeper.pageRemoved(first);
    expect(first.calls, ['close']);
    expect(keeper.kept, isNull);

    second.pipActive = true;
    keeper.pageRemoved(second);
    expect(second.calls, ['keep']);
    expect(keeper.kept, same(second));
    keeper.pageRemoved(second);
    expect(second.calls, ['keep'], reason: 'kept once');
    expect(logged(), ['pip kept BV1second']);
  });

  test('a newer page popped in picture in picture releases the one kept before', () {
    first.pipActive = true;
    keeper
      ..pipStarted(first)
      ..pageRemoved(first);
    second.pipActive = true;
    keeper
      ..pipStarted(second)
      ..pageRemoved(second);
    expect(first.calls, ['keep', 'close']);
    expect(keeper.kept, same(second));
  });

  test('item 36: a page that opens releases the kept one first, and may play', () {
    first.pipActive = true;
    keeper
      ..pipStarted(first)
      ..pageRemoved(first);
    expect(keeper.pageShown(second, opened: true), isTrue);
    expect(first.calls, ['keep', 'close']);
    expect(keeper.kept, isNull);
    expect(logged(), ['pip kept BV1first', 'pip released BV1first']);
  });

  test('item 39: a page shown again by going back stays paused beside the small window until it plays', () {
    first.pipActive = true;
    keeper
      ..pipStarted(first)
      ..pageRemoved(first);
    expect(keeper.pageShown(second, opened: false), isFalse);
    expect(first.calls, ['keep']);

    keeper.willPlay(first);
    expect(first.calls, ['keep'], reason: 'the kept playback playing on (自动连播, 单集循环) releases nothing');
    keeper.willPlay(second);
    expect(first.calls, ['keep', 'close']);
    expect(keeper.pageShown(second, opened: false), isTrue);
  });

  test('going back can show the page below before the popped page in the small window is reported removed', () {
    first.pipActive = true;
    keeper.pipStarted(first);
    expect(keeper.pageShown(second, opened: false), isFalse, reason: 'it would resume beside the small window');
    keeper.pageRemoved(first);
    expect(keeper.kept, same(first));
    expect(keeper.pageShown(first, opened: false), isTrue, reason: 'the page in the small window itself may resume');
  });

  test('items 34 and 35: ✕ releases at once; the restore button pushes the page, which takes it back', () {
    expect(keeper.restore(first), isFalse, reason: 'nothing to restore before it is kept');
    first.pipActive = true;
    keeper
      ..pipStarted(first)
      ..pageRemoved(first);
    expect(keeper.restore(second), isFalse);
    expect(second.calls, isEmpty);

    expect(keeper.restore(first), isTrue);
    expect(keeper.restoring, same(first));
    expect(keeper.pageShown(first, opened: true), isTrue);
    expect(keeper.kept, isNull);
    expect(keeper.restoring, isNull);
    first.pipActive = false;
    keeper.pipStopped(first);
    expect(first.calls, ['keep', 'push', 'returned'], reason: 'the restored page keeps playing inline');
    expect(logged(), ['pip kept BV1first', 'pip restored BV1first']);

    second.pipActive = true;
    keeper
      ..pipStarted(second)
      ..pageRemoved(second);
    second.pipActive = false;
    keeper.pipStopped(second);
    expect(second.calls, ['keep', 'close'], reason: '✕');
    expect(keeper.kept, isNull);
  });

  test('a restore with nothing to push it is no restore', () {
    first
      ..pipActive = true
      ..pushes = false;
    keeper.pageRemoved(first);
    expect(keeper.restore(first), isFalse);
    expect(keeper.restoring, isNull);
  });

  testWidgets('the small window closing for a restore waits 1 s for the page, then releases it', (tester) async {
    first.pipActive = true;
    keeper
      ..pipStarted(first)
      ..pageRemoved(first)
      ..restore(first);
    first.pipActive = false;
    keeper.pipStopped(first);
    await tester.pump(const Duration(milliseconds: 900));
    expect(first.calls, ['keep', 'push'], reason: 'a restore gets a moment to show the page');
    await tester.pump(const Duration(milliseconds: 200));
    expect(first.calls, ['keep', 'push', 'close']);
    expect(keeper.kept, isNull);

    second.pipActive = true;
    keeper
      ..pipStarted(second)
      ..pageRemoved(second)
      ..restore(second);
    second.pipActive = false;
    keeper.pipStopped(second);
    await tester.pump(const Duration(milliseconds: 500));
    expect(keeper.pageShown(second, opened: true), isTrue, reason: 'the page arrived late, within the wait');
    await tester.pump(const Duration(seconds: 1));
    expect(second.calls, ['keep', 'push', 'returned']);
  });
}
