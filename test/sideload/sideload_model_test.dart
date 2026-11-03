import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/sideload/fake_sideload.dart';
import 'package:bilifast/sideload/sideload_links.dart';
import 'package:bilifast/sideload/sideload_model.dart';
import 'package:bilifast/sideload/sideload_store.dart';
import 'package:flutter_test/flutter_test.dart';

ReleaseInfo release(String version, int build) =>
    ReleaseInfo(version: version, build: build, page: Uri.parse(releasesPage));

/// Answers only when the test says so, counting the asks.
final class HeldFeed implements ReleaseFeed {
  var asked = 0;
  Completer<ReleaseInfo?> _answer = Completer();

  @override
  Future<ReleaseInfo?> latest() {
    asked++;
    _answer = Completer();
    return _answer.future;
  }

  void answer(ReleaseInfo? release) => _answer.complete(release);
}

final class FailingFeed implements ReleaseFeed {
  @override
  Future<ReleaseInfo?> latest() async => throw StateError('secret address');
}

void main() {
  // Local times, so the calendar day is the same on any machine.
  var now = DateTime(2026, 11, 4, 9);
  late MemorySink logs;
  late Logger logger;
  late FakeReminderHost host;
  late SideloadStore store;

  setUp(() {
    now = DateTime(2026, 11, 4, 9);
    logs = MemorySink();
    logger = Logger(session: 'test')..add(logs);
    host = FakeReminderHost();
    store = SideloadStore.memory(logger: logger);
  });

  SideloadModel model({
    Duration? left = const Duration(days: 6, hours: 3),
    ReleaseFeed? feed,
    String? version = '1.3.0',
    String? build = '7',
  }) => SideloadModel(
    source: FixedSignature(left == null ? null : SignatureInfo(expires: now.add(left).toUtc())),
    feed: feed ?? FixedReleaseFeed(null),
    reminders: host,
    store: store,
    version: version,
    build: build,
    now: () => now,
    logger: logger,
  );

  List<String> messages() => [for (final event in logs.events) event.msg];

  group('not sideloaded', () {
    test('none() stays empty and asks nothing', () async {
      final none = SideloadModel.none();
      await none.start();
      await none.checkNow();
      await none.answerReminder(true);
      await none.setReminder(true);
      expect(none.sideloaded, isFalse);
      expect(none.signature, isNull);
      expect(none.daysLeft, isNull);
      expect(none.newer, isNull);
      expect(none.reminderOn, isFalse);
      expect(none.shouldAskReminder, isFalse);
      expect(none.shouldWarnExpiry, isFalse);
      expect(none.shouldAnnounceRelease, isFalse);
    });

    test('without a profile, no release is asked and no reminder set, even when the answers say on', () async {
      store.reminderOn = true;
      final feed = FixedReleaseFeed(release('9.0.0', 1));
      final unsigned = model(left: null, feed: feed);
      await unsigned.start();
      await unsigned.checkNow();
      expect(feed.asked, 0);
      expect(host.schedules, isEmpty);
      expect(unsigned.reminderOn, isFalse);
      expect(logs.events.single.msg, 'sideload');
      expect(logs.events.single.f['sideloaded']?.toJson(), false);
    });
  });

  group('days left', () {
    test('whole days, rounded down, never below 0', () async {
      Future<int?> daysFor(Duration left) async {
        final sideload = model(left: left);
        await sideload.start();
        return sideload.daysLeft;
      }

      expect(await daysFor(const Duration(hours: 30)), 1);
      expect(await daysFor(const Duration(hours: 10)), 0);
      expect(await daysFor(const Duration(days: 7)), 7);
      expect(await daysFor(const Duration(hours: -5)), 0);
      expect(await daysFor(const Duration(days: -3)), 0);
    });

    test('follow the clock', () async {
      final sideload = model(left: const Duration(days: 3, hours: 1));
      await sideload.start();
      expect(sideload.daysLeft, 3);
      now = now.add(const Duration(hours: 2));
      expect(sideload.daysLeft, 2);
    });
  });

  group('newer', () {
    bool newer(ReleaseInfo offered, {String? version = '1.3.0', int? build = 7}) =>
        SideloadModel.isNewer(offered, version: version, build: build);

    test('the version by its numbers, then the build', () {
      expect(newer(release('1.3.0', 8)), isTrue);
      expect(newer(release('1.3.0', 7)), isFalse);
      expect(newer(release('1.3.0', 6)), isFalse);
      expect(newer(release('1.3.1', 1)), isTrue);
      expect(newer(release('1.4.0', 1)), isTrue);
      expect(newer(release('2.0.0', 1)), isTrue);
      expect(newer(release('1.2.9', 99)), isFalse);
      expect(newer(release('1.10.0', 1), version: '1.9.0'), isTrue);
      expect(newer(release('1.3', 8)), isTrue);
      expect(newer(release('1.3.0.1', 1)), isTrue);
    });

    test('an unknown or unreadable version never has a newer release; an unknown build only a higher version', () {
      expect(newer(release('9.0.0', 1), version: null), isFalse);
      expect(newer(release('9.0.0', 1), version: '1.3.0-beta'), isFalse);
      expect(newer(release('1.x', 1)), isFalse);
      expect(newer(release('1.3.0', 99), build: null), isFalse);
      expect(newer(release('1.3.1', 1), build: null), isTrue);
    });

    test("the model shows the feed's release only when it is newer than this build", () async {
      final same = model(feed: FixedReleaseFeed(release('1.3.0', 7)));
      await same.start();
      expect(same.newer, isNull);

      final ahead = model(feed: FixedReleaseFeed(release('1.3.0', 8)));
      await ahead.start();
      expect(ahead.newer?.build, 8);

      final unknown = model(feed: FixedReleaseFeed(release('1.3.0', 8)), version: null, build: null);
      await unknown.start();
      expect(unknown.newer, isNull);
    });
  });

  group('asking for releases', () {
    test('start asks once, however often it is called', () async {
      final feed = FixedReleaseFeed(release('1.3.0', 8));
      final sideload = model(feed: feed);
      await Future.wait([sideload.start(), sideload.start()]);
      await sideload.start();
      expect(feed.asked, 1);
    });

    test('checkNow asks once more, never while an ask is running, and checking shows it', () async {
      final feed = HeldFeed();
      final sideload = model(feed: feed);
      var notified = 0;
      sideload.addListener(() => notified++);

      final started = sideload.start();
      await pumpEventQueue();
      expect(feed.asked, 1);
      expect(sideload.checking, isTrue);

      final tapped = sideload.checkNow();
      await pumpEventQueue();
      expect(feed.asked, 1);

      feed.answer(release('1.3.0', 8));
      await Future.wait([started, tapped]);
      expect(sideload.checking, isFalse);
      expect(sideload.newer?.build, 8);
      expect(notified, greaterThanOrEqualTo(3));

      final again = sideload.checkNow();
      await pumpEventQueue();
      expect(feed.asked, 2);
      feed.answer(null);
      await again;
      expect(sideload.newer?.build, 8, reason: 'a failed check keeps what an earlier one found');
      expect(feed.asked, 2);
    });

    test('a failing feed is nothing, logged by type only', () async {
      final sideload = model(feed: FailingFeed());
      await sideload.start();
      expect(sideload.newer, isNull);
      expect(sideload.checking, isFalse);
      expect(logs.events.map((event) => event.encode()).join(), isNot(contains('secret')));
    });

    test('logs a sideload line with the days left and whether a release is newer', () async {
      final sideload = model(left: const Duration(days: 2, hours: 1), feed: FixedReleaseFeed(release('1.3.0', 8)));
      await sideload.start();
      final line = logs.events.singleWhere((event) => event.msg == 'sideload');
      expect(line.f.map((key, value) => MapEntry(key, value.toJson())), {
        'daysLeft': 2,
        'newer': true,
        'answered': true,
        'via': 'launch',
      });
    });
  });

  group('the reminder', () {
    test('asked on the first sideloaded launch only, until answered', () async {
      final sideload = model();
      expect(sideload.shouldAskReminder, isFalse, reason: 'not read yet');
      await sideload.start();
      expect(sideload.shouldAskReminder, isTrue);
      await sideload.answerReminder(false);
      expect(sideload.shouldAskReminder, isFalse);
      final relaunched = model();
      await relaunched.start();
      expect(relaunched.shouldAskReminder, isFalse);
    });

    test('yes: iOS is asked, and the reminder set for a day before the expiry with its texts', () async {
      final sideload = model(left: const Duration(days: 6, hours: 3));
      await sideload.start();
      await sideload.answerReminder(true);
      expect(host.permissionAsks, 1);
      expect(sideload.reminderOn, isTrue);
      expect(store.reminderOn, isTrue);
      final scheduled = host.schedules.single;
      expect(scheduled.at, sideload.signature!.expires.subtract(const Duration(hours: 24)));
      expect(scheduled.title, 'BiliFast 签名明天到期');
      expect(scheduled.body, '记得在 SideStore 或电脑上重新签名，过期后会打不开。已经续签过可以忽略。');

      await sideload.answerReminder(true);
      expect(host.permissionAsks, 1, reason: 'never asked again');
    });

    test('yes but iOS refuses: off, nothing set, and never asked again', () async {
      host.grants = false;
      final sideload = model();
      await sideload.start();
      await sideload.answerReminder(true);
      expect(sideload.reminderOn, isFalse);
      expect(host.schedules, isEmpty);
      expect(sideload.shouldAskReminder, isFalse);
    });

    test('no: nothing asked of iOS, never asked again', () async {
      final sideload = model();
      await sideload.start();
      await sideload.answerReminder(false);
      expect(host.permissionAsks, 0);
      expect(sideload.reminderOn, isFalse);
      expect(store.reminderAnswered, isTrue);
    });

    test('on, every launch sets it again from the profile it reads', () async {
      store
        ..reminderAnswered = true
        ..reminderOn = true;
      final sideload = model(left: const Duration(days: 7));
      await sideload.start();
      expect(host.schedules.single.at, now.add(const Duration(days: 6)).toUtc());
      expect(host.permissionAsks, 0);
    });

    test('nothing is set when the day before has passed', () async {
      store.reminderOn = true;
      final sideload = model(left: const Duration(hours: 20));
      await sideload.start();
      expect(host.schedules, isEmpty);
      await sideload.setReminder(false);
      await sideload.setReminder(true);
      expect(sideload.reminderOn, isTrue);
      expect(host.schedules, isEmpty);
    });

    test("设置's switch: on asks iOS then sets it, off cancels", () async {
      final sideload = model();
      await sideload.start();
      var notified = 0;
      sideload.addListener(() => notified++);

      await sideload.setReminder(true);
      expect(sideload.reminderOn, isTrue);
      expect(host.permissionAsks, 1);
      expect(host.schedules, hasLength(1));
      expect(sideload.shouldAskReminder, isFalse, reason: 'the switch counts as an answer');

      await sideload.setReminder(false);
      expect(sideload.reminderOn, isFalse);
      expect(host.cancels, 1);
      expect(notified, greaterThanOrEqualTo(2));

      host.grants = false;
      await sideload.setReminder(true);
      expect(sideload.reminderOn, isFalse);
      expect(host.schedules, hasLength(1));
    });

    test('a failing host leaves it off, logged by type', () async {
      final sideload = SideloadModel(
        source: FixedSignature(SignatureInfo(expires: now.add(const Duration(days: 5)))),
        feed: FixedReleaseFeed(null),
        reminders: _ThrowingHost(),
        store: store,
        now: () => now,
        logger: logger,
      );
      await sideload.start();
      await sideload.answerReminder(true);
      expect(sideload.reminderOn, isFalse);
      expect(messages(), contains('sideload reminder failed'));
      expect(logs.events.map((event) => event.encode()).join(), isNot(contains('denied by test')));
    });
  });

  group('the expiry alert', () {
    test('two days or less, once a calendar day', () async {
      final far = model(left: const Duration(days: 3, hours: 1));
      await far.start();
      expect(far.shouldWarnExpiry, isFalse);

      final near = model(left: const Duration(days: 2, hours: 20));
      await near.start();
      expect(near.shouldWarnExpiry, isTrue);
      near.expiryWarned();
      expect(near.shouldWarnExpiry, isFalse);

      now = DateTime(2026, 11, 4, 23, 59);
      expect(near.shouldWarnExpiry, isFalse);
      now = DateTime(2026, 11, 5, 0, 1);
      expect(near.shouldWarnExpiry, isTrue);
    });

    test('an expired signature is still warned about', () async {
      final lapsed = model(left: const Duration(hours: -3));
      await lapsed.start();
      expect(lapsed.daysLeft, 0);
      expect(lapsed.shouldWarnExpiry, isTrue);
    });
  });

  group('the release alert', () {
    test('once per release', () async {
      final feed = HeldFeed();
      final sideload = model(feed: feed);
      final started = sideload.start();
      await pumpEventQueue();
      feed.answer(release('1.3.0', 8));
      await started;
      expect(sideload.shouldAnnounceRelease, isTrue);
      sideload.releaseAnnounced();
      expect(sideload.shouldAnnounceRelease, isFalse);
      expect(store.announced, '1.3.0-8');

      final again = sideload.checkNow();
      await pumpEventQueue();
      feed.answer(release('1.3.0', 9));
      await again;
      expect(sideload.shouldAnnounceRelease, isTrue);
    });

    test('nothing to announce without a newer release', () async {
      final sideload = model(feed: FixedReleaseFeed(release('1.3.0', 7)));
      await sideload.start();
      sideload.releaseAnnounced();
      expect(sideload.shouldAnnounceRelease, isFalse);
      expect(store.announced, isNull);
    });
  });

  test('a model disposed while it reads stays quiet', () async {
    final feed = HeldFeed();
    final sideload = model(feed: feed);
    final started = sideload.start();
    await pumpEventQueue();
    sideload.dispose();
    feed.answer(release('1.3.0', 8));
    await started;
  });

  group('fakeSideloadModel', () {
    test('lapses tomorrow with a newer release, asks the reminder and grants it, touching nothing real', () async {
      final fakeHost = FakeReminderHost();
      final fake = fakeSideloadModel(reminders: fakeHost, now: () => now);
      await fake.start();
      expect(fake.sideloaded, isTrue);
      expect(fake.daysLeft, 1);
      expect(fake.shouldWarnExpiry, isTrue);
      expect(fake.newer?.version, '1.3.0');
      expect(fake.newer?.build, 99);
      expect(fake.newer?.page, Uri.parse(releasesPage));
      expect(fake.shouldAnnounceRelease, isTrue);
      expect(fake.shouldAskReminder, isTrue);

      await fake.answerReminder(true);
      expect(fake.reminderOn, isTrue);
      expect(fakeHost.schedules.single.at, now.add(const Duration(hours: 5)));

      await fake.checkNow();
      expect(fake.checking, isFalse);
    });

    test('with no arguments, as --fake-sideload builds it', () async {
      final fake = fakeSideloadModel();
      await fake.start();
      expect(fake.sideloaded, isTrue);
      expect(fake.newer, isNotNull);
    });
  });
}

final class _ThrowingHost implements ReminderHost {
  @override
  Future<bool> requestPermission() async => throw StateError('denied by test');

  @override
  Future<void> schedule(DateTime at, String title, String body) async => throw StateError('denied by test');

  @override
  Future<void> cancel() async => throw StateError('denied by test');
}
