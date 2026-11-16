import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/form_factor.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/notify/notify_host.dart';
import 'package:bilifast/notify/notify_taps.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';

class _Host implements NotifyHost {
  NotifyRoute? launch;
  List<NotifyTrip> trips = const [];
  final subscribed = <void Function(NotifyRoute route)?>[];
  int launchTakes = 0;
  int tripTakes = 0;

  void tap(NotifyRoute route) => subscribed.last!(route);

  @override
  bool get available => true;

  @override
  Future<NotifyKinds> kinds() async => NotifyKinds.none;

  @override
  Future<void> setKinds(NotifyKinds kinds) async {}

  @override
  Future<NotifyPermission> permission() async => NotifyPermission.allowed;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> backgroundRefreshAllowed() async => true;

  @override
  Future<NotifyRoute?> takeLaunchRoute() async {
    launchTakes += 1;
    final route = launch;
    launch = null;
    return route;
  }

  @override
  Future<List<NotifyTrip>> takeTrips() async {
    tripTakes += 1;
    return trips;
  }

  @override
  set onTap(void Function(NotifyRoute route)? callback) => subscribed.add(callback);
}

/// Stands in for the video page, which needs a player.
class _Video extends StatelessWidget {
  const _Video(this.route);

  final VideoRoute route;

  @override
  Widget build(BuildContext context) => SizedBox.expand(key: ValueKey('video-${route.bvid}'));
}

class _Pages extends NotifyPages {
  final videos = <(String, VideoRoute)>[];
  final posts = <(String, bool)>[];
  int likes = 0;

  /// Stands in for 收到喜欢, which asks the account's likes.
  @override
  Future<void> openLikes(BuildContext context) {
    likes += 1;
    return Navigator.of(context)
        .push(SwipeBackPageRoute<void>(builder: (_) => const SizedBox.expand(key: ValueKey('likes'))));
  }

  @override
  Future<void> openVideo(BuildContext context, VideoRoute route) {
    videos.add(('open', route));
    return Navigator.of(context)
        .push(SwipeBackPageRoute<void>(builder: (_) => _Video(route), settings: VideoRoute.pageSettings));
  }

  @override
  Future<void> replaceVideo(BuildContext context, VideoRoute route) {
    videos.add(('replace', route));
    return replaceVideoPage(context, route, page: _Video.new);
  }

  @override
  Future<void> openPost(BuildContext context, {required String id, required bool toComments}) async =>
      posts.add((id, toComments));
}

void main() {
  late _Host host;
  late _Pages pages;
  late MemorySink events;
  late Logger logger;
  late CannedHttp http;
  late GlobalKey<NavigatorState> navigator;
  late AppServices services;

  setUp(() {
    host = _Host();
    pages = _Pages();
    events = MemorySink();
    logger = Logger(session: 'test')..add(events);
    http = Canned.http();
    navigator = GlobalKey<NavigatorState>();
  });

  NotifyTaps taps({Duration accountWait = const Duration(seconds: 10), DateTime Function()? now}) =>
      NotifyTaps(host: host, navigator: navigator, logger: logger, pages: pages, accountWait: accountWait, now: now);

  /// The app's navigator over 首页; [fake] reads logged in at once, otherwise the account waits on nav's answer.
  Future<AppEnvironment> mount(WidgetTester tester, {bool fake = true, CookieLoad? cookies}) async {
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(cookies ?? const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    if (fake) environment.useFakeAccount();
    final playback = AppPlayback(() => Completer<PlaybackController>().future);
    addTearDown(playback.dispose);
    services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      navigator: navigator,
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: services.navigator,
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const SizedBox.expand(key: ValueKey('home')),
      ),
    );
    return environment;
  }

  Iterable<Map<String, Object>> logged(String message) => [
    for (final event in events.events)
      if (event.msg == message) {for (final MapEntry(:key, :value) in event.f.entries) key: value.toJson()},
  ];

  testWidgets('the launch route opens once the first page is up', (tester) async {
    host.launch = const NotifyVideo(bvid: 'BV1launch');
    taps().start();
    expect(host.launchTakes, 0, reason: 'nothing is asked before the app has a page');
    await mount(tester);
    await tester.pumpAndSettle();
    expect(host.launchTakes, 1);
    expect(host.subscribed, hasLength(1));
    expect(pages.videos.single.$1, 'open');
    expect(pages.videos.single.$2.bvid, 'BV1launch');
    expect(pages.videos.single.$2.comment, isNull);
    expect(find.byKey(const ValueKey('video-BV1launch')), findsOneWidget);
    expect(logged('notify open'), [
      {'kind': 'video'},
    ]);
  });

  testWidgets('a cold start\'s route waits for the launch\'s account check', (tester) async {
    final gate = Completer<void>();
    http.gates[Canned.navPath] = gate;
    host.launch = const NotifyVideo(bvid: 'BV1launch');
    taps().start();
    final environment = await mount(tester, fake: false);
    unawaited(environment.refreshAccount());
    await tester.pumpAndSettle();
    expect(pages.videos, isEmpty);
    gate.complete();
    await tester.pumpAndSettle();
    expect(environment.account, isA<LoggedIn>());
    expect(pages.videos.single.$2.bvid, 'BV1launch');
    expect(http.to(Canned.navPath), hasLength(1), reason: 'the tap waits on the launch\'s check, asking nothing');
  });

  testWidgets('an account check that never answers opens nothing', (tester) async {
    http.gates[Canned.navPath] = Completer<void>();
    host.launch = const NotifyVideo(bvid: 'BV1launch');
    taps(accountWait: const Duration(seconds: 2)).start();
    await mount(tester, fake: false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(pages.videos, isEmpty);
    expect(logged('notify not opened'), [
      {'kind': 'video', 'reason': 'account unknown'},
    ]);
  });

  testWidgets('a tap while running opens the video page on the reply\'s thread', (tester) async {
    taps().start();
    await mount(tester);
    await tester.pumpAndSettle();
    host.tap(const NotifyVideo(bvid: 'BV1reply', commentRoot: 500, comment: 700));
    await tester.pumpAndSettle();
    final (how, route) = pages.videos.single;
    expect(how, 'open');
    expect(route.bvid, 'BV1reply');
    expect(route.comment?.root, 500);
    expect(route.comment?.reply, 700);
    expect(find.byKey(const ValueKey('video-BV1reply')), findsOneWidget);
    expect(logged('notify open'), [
      {'kind': 'comment'},
    ]);
  });

  testWidgets('a video page on top is replaced, as video pages never stack', (tester) async {
    taps().start();
    await mount(tester);
    await tester.pumpAndSettle();
    host.tap(const NotifyVideo(bvid: 'BV1first'));
    await tester.pumpAndSettle();
    host.tap(const NotifyVideo(bvid: 'BV1second', commentRoot: 1));
    await tester.pumpAndSettle();
    expect([for (final (how, route) in pages.videos) '$how ${route.bvid}'], ['open BV1first', 'replace BV1second']);
    expect(find.byKey(const ValueKey('video-BV1first'), skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('video-BV1second')), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home')), findsOneWidget);
  });

  testWidgets('two taps in one frame leave one video page, the second', (tester) async {
    taps().start();
    await mount(tester);
    await tester.pumpAndSettle();
    host.tap(const NotifyVideo(bvid: 'BV1first'));
    host.tap(const NotifyVideo(bvid: 'BV1second'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video-BV1first'), skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('video-BV1second')), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home')), findsOneWidget);
    expect(navigator.currentState!.canPop(), isFalse);
  });

  testWidgets('a dialog over the video page closes, and the new page replaces the old', (tester) async {
    taps().start();
    await mount(tester);
    await tester.pumpAndSettle();
    host.tap(const NotifyVideo(bvid: 'BV1first'));
    await tester.pumpAndSettle();
    var closed = false;
    unawaited(
      showDialog<void>(
        context: tester.element(find.byKey(const ValueKey('video-BV1first'))),
        builder: (_) => const Center(child: Text('dialog')),
      ).then((_) => closed = true),
    );
    await tester.pumpAndSettle();
    host.tap(const NotifyVideo(bvid: 'BV1second'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect([for (final (how, route) in pages.videos) '$how ${route.bvid}'], ['open BV1first', 'replace BV1second']);
    expect(find.text('dialog'), findsNothing);
    expect(find.byKey(const ValueKey('video-BV1first'), skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('video-BV1second')), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home')), findsOneWidget);
  });

  testWidgets('a page over the video page stays, with the new video page over it', (tester) async {
    taps().start();
    await mount(tester);
    await tester.pumpAndSettle();
    host.tap(const NotifyVideo(bvid: 'BV1first'));
    await tester.pumpAndSettle();
    unawaited(
      navigator.currentState!.push(
        SwipeBackPageRoute<void>(builder: (_) => const SizedBox.expand(key: ValueKey('space'))),
      ),
    );
    await tester.pumpAndSettle();
    host.tap(const NotifyVideo(bvid: 'BV1second'));
    await tester.pumpAndSettle();
    expect([for (final (how, route) in pages.videos) '$how ${route.bvid}'], ['open BV1first', 'open BV1second']);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('space')), findsOneWidget);
  });

  testWidgets('a tap over the login page waits for it to leave, then replaces the video page under it', (tester) async {
    taps().start();
    await mount(tester);
    await tester.pumpAndSettle();
    host.tap(const NotifyVideo(bvid: 'BV1first'));
    await tester.pumpAndSettle();
    final login = MaterialPageRoute<bool>(
      settings: LoginPageGate.routeSettings,
      builder: (_) => const SizedBox.expand(key: ValueKey('login')),
    );
    bool? answer;
    unawaited(navigator.currentState!.push(login).then((value) => answer = value));
    await tester.pumpAndSettle();
    host.tap(const NotifyVideo(bvid: 'BV1second'));
    await tester.pumpAndSettle();
    expect([for (final (how, route) in pages.videos) '$how ${route.bvid}'], ['open BV1first']);
    navigator.currentState!.removeRoute(login, true);
    await tester.pumpAndSettle();
    expect(answer, isTrue);
    expect([for (final (how, route) in pages.videos) '$how ${route.bvid}'], ['open BV1first', 'replace BV1second']);
    expect(find.byKey(const ValueKey('video-BV1first'), skipOffstage: false), findsNothing);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home')), findsOneWidget);
  });

  testWidgets('a post\'s route opens the post', (tester) async {
    taps().start();
    await mount(tester);
    await tester.pumpAndSettle();
    host.tap(const NotifyDynamicPost(id: '987', toComments: true));
    host.tap(const NotifyDynamicPost(id: '654'));
    await tester.pumpAndSettle();
    expect(pages.posts, [('987', true), ('654', false)]);
    expect(pages.videos, isEmpty);
    expect(logged('notify open'), [
      {'kind': 'post'},
      {'kind': 'post'},
    ]);
  });

  testWidgets('a like\'s route opens 收到喜欢 over the page on top, sheets closed first', (tester) async {
    taps().start();
    await mount(tester);
    await tester.pumpAndSettle();
    host.tap(const NotifyVideo(bvid: 'BV1first'));
    await tester.pumpAndSettle();
    var closed = false;
    unawaited(
      showDialog<void>(
        context: tester.element(find.byKey(const ValueKey('video-BV1first'))),
        builder: (_) => const Center(child: Text('dialog')),
      ).then((_) => closed = true),
    );
    await tester.pumpAndSettle();
    host.tap(const NotifyLikes());
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(pages.likes, 1);
    expect(find.byKey(const ValueKey('likes')), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video-BV1first')), findsOneWidget, reason: 'the page under it stays');
    expect(logged('notify open'), [
      {'kind': 'video'},
      {'kind': 'likes'},
    ]);
  });

  testWidgets('a 私信\'s route goes back to the shell and asks it to show 消息', (tester) async {
    taps().start();
    await mount(tester);
    await tester.pumpAndSettle();
    var shows = 0;
    services.messages.showRequests.addListener(() => shows += 1);
    host.tap(const NotifyVideo(bvid: 'BV1first'));
    await tester.pumpAndSettle();
    unawaited(
      navigator.currentState!.push(
        SwipeBackPageRoute<void>(builder: (_) => const SizedBox.expand(key: ValueKey('space'))),
      ),
    );
    await tester.pumpAndSettle();
    host.tap(const NotifyMessages());
    await tester.pumpAndSettle();
    expect(shows, 1);
    expect(find.byKey(const ValueKey('home')), findsOneWidget);
    expect(navigator.currentState!.canPop(), isFalse);
    expect(logged('notify open').last, {'kind': 'messages'});
  });

  testWidgets("on the iPad, which has no 消息, a like's or a 私信's route opens nothing and closes nothing", (
    tester,
  ) async {
    FormFactor.device = FormFactor.pad;
    addTearDown(() => FormFactor.device = FormFactor.phone);
    taps().start();
    await mount(tester);
    await tester.pumpAndSettle();
    var shows = 0;
    services.messages.showRequests.addListener(() => shows += 1);
    host.tap(const NotifyVideo(bvid: 'BV1first'));
    await tester.pumpAndSettle();
    host.tap(const NotifyLikes());
    await tester.pumpAndSettle();
    host.tap(const NotifyMessages());
    await tester.pumpAndSettle();
    expect(pages.likes, 0);
    expect(shows, 0);
    expect(find.byKey(const ValueKey('video-BV1first')), findsOneWidget, reason: 'the video page stays');
    expect(logged('notify open'), [
      {'kind': 'video'},
      {'kind': 'likes'},
      {'kind': 'messages'},
    ]);
  });

  testWidgets('logged out, a like\'s or a 私信\'s route opens nothing', (tester) async {
    http = Canned.http(loggedIn: false);
    host.launch = const NotifyLikes();
    taps().start();
    final environment = await mount(tester, fake: false, cookies: const NoStoredCookies());
    var shows = 0;
    services.messages.showRequests.addListener(() => shows += 1);
    await tester.pumpAndSettle();
    expect(environment.account, isA<LoggedOut>());
    host.tap(const NotifyMessages());
    await tester.pumpAndSettle();
    expect(pages.likes, 0);
    expect(shows, 0);
    expect(logged('notify not opened'), [
      {'kind': 'likes', 'reason': 'logged out'},
      {'kind': 'messages', 'reason': 'logged out'},
    ]);
  });

  testWidgets('the app\'s route opens nothing', (tester) async {
    taps().start();
    await mount(tester);
    await tester.pumpAndSettle();
    host.tap(const NotifyApp());
    await tester.pumpAndSettle();
    expect(pages.videos, isEmpty);
    expect(pages.posts, isEmpty);
    expect(find.byKey(const ValueKey('home')), findsOneWidget);
    expect(logged('notify open'), [
      {'kind': 'app'},
    ]);
  });

  testWidgets('logged out, a tap opens nothing', (tester) async {
    http = Canned.http(loggedIn: false);
    host.launch = const NotifyVideo(bvid: 'BV1launch');
    taps().start();
    final environment = await mount(tester, fake: false, cookies: const NoStoredCookies());
    await tester.pumpAndSettle();
    expect(environment.account, isA<LoggedOut>());
    host.tap(const NotifyDynamicPost(id: '987'));
    await tester.pumpAndSettle();
    expect(pages.videos, isEmpty);
    expect(pages.posts, isEmpty);
    expect(logged('notify open'), isEmpty);
    expect(logged('notify not opened'), [
      {'kind': 'video', 'reason': 'logged out'},
      {'kind': 'post', 'reason': 'logged out'},
    ]);
  });

  testWidgets('each trip is logged with its outcome, counts and age only', (tester) async {
    final now = DateTime(2026, 11, 16, 12);
    host.trips = [
      NotifyTrip(at: now.subtract(const Duration(minutes: 95)), outcome: 'posted', calls: 3, posted: 2),
      NotifyTrip(at: now.subtract(const Duration(seconds: 30)), outcome: 'nothing new', calls: 1, posted: 0),
    ];
    taps(now: () => now).start();
    await mount(tester);
    await tester.pumpAndSettle();
    expect(host.tripTakes, 1);
    expect(logged('notify trip'), [
      {'outcome': 'posted', 'calls': 3, 'posted': 2, 'ageMinutes': 95},
      {'outcome': 'nothing new', 'calls': 1, 'posted': 0, 'ageMinutes': 0},
    ]);
  });

  testWidgets('start twice subscribes and asks once', (tester) async {
    host.launch = const NotifyVideo(bvid: 'BV1launch');
    final notify = taps();
    notify.start();
    notify.start();
    await mount(tester);
    await tester.pumpAndSettle();
    notify.start();
    await tester.pumpAndSettle();
    expect(host.subscribed, hasLength(1));
    expect(host.launchTakes, 1);
    expect(host.tripTakes, 1);
    expect(pages.videos, hasLength(1));
  });
}
