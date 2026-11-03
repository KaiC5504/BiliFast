import 'dart:async';

import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/sideload/fake_sideload.dart';
import 'package:bilifast/sideload/sideload_links.dart';
import 'package:bilifast/sideload/sideload_model.dart';
import 'package:bilifast/sideload/sideload_prompts.dart';
import 'package:bilifast/sideload/sideload_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Takes the reminder after [delay], as iOS may.
final class _SlowHost implements ReminderHost {
  _SlowHost(this.delay);

  final Duration delay;
  var schedules = 0;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> schedule(DateTime at, String title, String body) async {
    schedules++;
    await Future<void>.delayed(delay);
    return true;
  }

  @override
  Future<void> cancel() async {}
}

/// Answers [release] after [delay]; null is GitHub failing.
final class _SlowFeed implements ReleaseFeed {
  _SlowFeed(this.delay, this.release);

  final Duration delay;
  final ReleaseInfo? release;
  var asked = 0;

  @override
  Future<ReleaseInfo?> latest() async {
    asked++;
    await Future<void>.delayed(delay);
    return release;
  }
}

final _newer = ReleaseInfo(version: '1.3.0', build: 9, page: Uri.parse(releasesPage));

/// The real model under the shell's launch alert: its start's timing against the alert's choice.
void main() {
  final now = DateTime(2026, 11, 4, 9);
  final releaseTitle = find.text('有新版本 1.3.0 (9)');
  final reminderTitle = find.text('签名到期前提醒你？');
  final alert = find.byKey(const ValueKey('settings-confirm'));

  SideloadModel real({required ReminderHost host, required ReleaseFeed feed, required SideloadStore store}) =>
      SideloadModel(
        source: FixedSignature(SignatureInfo(expires: now.add(const Duration(days: 6)).toUtc())),
        feed: feed,
        reminders: host,
        store: store,
        version: '1.3.0',
        build: '8',
        now: () => now,
      );

  Future<SideloadStore> reminderOn() async {
    final store = SideloadStore.memory();
    await store.load();
    store
      ..reminderAnswered = true
      ..reminderOn = true;
    return store;
  }

  Future<void> mount(WidgetTester tester, SideloadModel model) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [pageRoutes],
        home: Stack(
          children: [
            const Center(child: Text('shell')),
            Positioned.fill(
              child: SideloadPrompts(model: model, openLink: (_) async => true, canOpenLink: (_) async => false),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> run(WidgetTester tester, Duration total) async {
    for (var t = Duration.zero; t < total; t += const Duration(milliseconds: 50)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('reminder on and iOS slow to take it: the release still has its alert', (tester) async {
    final host = _SlowHost(const Duration(milliseconds: 800));
    final model = real(
      host: host,
      feed: _SlowFeed(const Duration(milliseconds: 100), _newer),
      store: await reminderOn(),
    );
    final started = model.start();
    await mount(tester, model);
    await run(tester, const Duration(seconds: 3));
    await started;
    expect(host.schedules, 1);
    expect(model.shouldAnnounceRelease, isTrue);
    expect(releaseTitle, findsOneWidget);
  });

  testWidgets('reminder on and iOS quick: the release has its alert', (tester) async {
    final model = real(
      host: _SlowHost(const Duration(milliseconds: 20)),
      feed: _SlowFeed(const Duration(milliseconds: 100), _newer),
      store: await reminderOn(),
    );
    final started = model.start();
    await mount(tester, model);
    await run(tester, const Duration(seconds: 3));
    await started;
    expect(releaseTitle, findsOneWidget);
  });

  testWidgets('GitHub slow and the reminder unanswered: the release beats the question, and nothing comes after', (
    tester,
  ) async {
    final model = real(
      host: _SlowHost(Duration.zero),
      feed: _SlowFeed(const Duration(seconds: 4), _newer),
      store: SideloadStore.memory(),
    );
    final started = model.start();
    await mount(tester, model);
    await run(tester, const Duration(seconds: 6));
    await started;
    expect(releaseTitle, findsOneWidget);
    expect(reminderTitle, findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings-confirm-稍后')));
    await tester.pumpAndSettle();
    final again = model.checkNow();
    await run(tester, const Duration(seconds: 6));
    await again;
    expect(alert, findsNothing);

    await tester.pumpWidget(const SizedBox());
    await mount(tester, model);
    await run(tester, const Duration(seconds: 2));
    expect(alert, findsNothing, reason: 'one alert a launch, the shell built again or not');
  });

  testWidgets('GitHub failing: the reminder question once the check gives up', (tester) async {
    final model = real(
      host: _SlowHost(Duration.zero),
      feed: _SlowFeed(const Duration(seconds: 1), null),
      store: SideloadStore.memory(),
    );
    final started = model.start();
    await mount(tester, model);
    await tester.pump(const Duration(milliseconds: 900));
    expect(alert, findsNothing);
    await run(tester, const Duration(seconds: 2));
    await started;
    expect(reminderTitle, findsOneWidget);
  });

  testWidgets('the shell built after start finished: the release still has its alert', (tester) async {
    final model = real(
      host: _SlowHost(Duration.zero),
      feed: _SlowFeed(Duration.zero, _newer),
      store: SideloadStore.memory(),
    );
    await tester.runAsync(model.start);
    await mount(tester, model);
    await run(tester, const Duration(seconds: 2));
    expect(releaseTitle, findsOneWidget);
  });

  testWidgets('a popup over the shell holds the alert until it closes', (tester) async {
    final model = real(
      host: _SlowHost(Duration.zero),
      feed: _SlowFeed(const Duration(milliseconds: 100), _newer),
      store: SideloadStore.memory(),
    );
    final started = model.start();
    await mount(tester, model);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.push(RawDialogRoute<void>(pageBuilder: (_, _, _) => const Center(child: Text('sheet')))));
    await run(tester, const Duration(seconds: 2));
    await started;
    expect(releaseTitle, findsNothing);

    navigator.pop();
    await run(tester, const Duration(seconds: 2));
    expect(releaseTitle, findsOneWidget);
  });

  testWidgets('an install that isn\'t sideloaded shows nothing', (tester) async {
    final model = SideloadModel.none();
    final started = model.start();
    await mount(tester, model);
    await run(tester, const Duration(seconds: 2));
    await started;
    expect(alert, findsNothing);
  });
}
