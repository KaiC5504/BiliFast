import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/video/link_opener.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';

/// Canned's video has two parts: P1 第一集 (cid 137649199) and P2 第二集 (cid 137649200).
const _video = 'BV1GJ411x7h7';

void main() {
  late CannedHttp http;
  late RecentStore recents;
  late List<VideoRoute> opened;
  late LinkOpener opener;
  late BuildContext context;

  setUp(() {
    http = Canned.http();
    opened = [];
    opener = LinkOpener(
      openPage: (context, route) async {
        opened.add(route);
      },
    );
  });

  Future<void> show(WidgetTester tester) async {
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    final playback = AppPlayback(() => Completer<PlaybackController>().future);
    addTearDown(playback.dispose);
    recents = await RecentStore.load(null, logger: logger);
    final services = AppServices(environment: environment, playback: playback, recents: recents);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScope(services: services, child: child!),
        home: Builder(
          builder: (inner) {
            context = inner;
            return const SizedBox.expand();
          },
        ),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('a link naming no part of several asks which; P2 opens P2 and 最近打开 records page 2 of 2', (tester) async {
    await show(tester);
    final open = opener.open(context, _video);
    await settle(tester);
    expect(find.text('选择分P'), findsOneWidget);
    expect(opener.busy.value, isFalse, reason: 'no spinner behind the sheet');

    await tester.tap(find.text('P2 第二集'));
    await settle(tester);
    expect(await open, isTrue);
    expect(opened.single.bvid, _video);
    expect(opened.single.cid, 137649200);
    final recent = recents.items.single;
    expect(recent.cid, 137649200);
    expect(recent.page, 2);
    expect(recent.pageCount, 2);
    expect(recent.part, '第二集');
    expect(opener.busy.value, isFalse);
    opener.dispose();
  });

  testWidgets('取消 opens nothing, records nothing and leaves no spinner', (tester) async {
    await show(tester);
    final open = opener.open(context, _video);
    await settle(tester);
    await tester.tap(find.text('取消'));
    await settle(tester);
    expect(await open, isTrue, reason: 'the link was taken');
    expect(find.text('选择分P'), findsNothing);
    expect(opened, isEmpty);
    expect(recents.items, isEmpty);
    expect(opener.busy.value, isFalse);
    opener.dispose();
  });

  testWidgets('disposed while the link resolves, the opener writes nothing after', (tester) async {
    await show(tester);
    http.gates[Canned.signedViewPath] = Completer<void>();
    final open = opener.open(context, '$_video?p=2');
    await tester.pump();
    expect(opener.busy.value, isTrue);
    opener.dispose();
    await tester.pumpWidget(const SizedBox());
    http.gates[Canned.signedViewPath]!.complete();
    await settle(tester);
    expect(await open, isTrue);
    expect(opened, isEmpty, reason: 'the page that asked has gone');
  });

  testWidgets("a failed open logs the error's kind, never the pasted link", (tester) async {
    final sink = MemorySink();
    Logger.shared.add(sink);
    addTearDown(() => Logger.shared.remove(sink));
    await show(tester);
    const pasted = 'https://www.bilibili.com/video/BV1GJ411x7h7?share_source=private123';
    http.errors[Canned.signedViewPath] = Exception('ClientException: failed, uri=$pasted');
    http.errors[Canned.viewPath] = Exception('ClientException: failed, uri=$pasted');
    expect(await opener.open(context, pasted), isTrue);
    await tester.pump();
    final failed = sink.events.where((event) => event.msg == 'open failed').single;
    expect('${failed.f['error']}', contains('BiliNetworkError'));
    expect('${failed.f}', isNot(contains('private123')));
    expect('${failed.f}', isNot(contains('bilibili.com')));
    await settle(tester);
    await tester.pump(const Duration(seconds: 3));
    opener.dispose();
  });
}
