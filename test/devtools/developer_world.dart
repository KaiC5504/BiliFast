import 'dart:async';

import 'package:bili_core/api.dart' show OfficialIdentity;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/app_auth.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/devtools/developer_page.dart';
import 'package:bilifast/devtools/log_files.dart';
import 'package:bilifast/devtools/log_forwarder.dart';
import 'package:bilifast/devtools/log_server_discovery.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/offline/disk/background_trials.dart';
import 'package:bilifast/offline/fake_offline_library.dart';
import 'package:bilifast/offline/offline_library.dart';
import 'package:bilifast/playback/codec_memory.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/playback/shared_engine.dart';
import 'package:bilifast/speedtest/speed_test_runner.dart';
import 'package:bilifast/video/history_outbox.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';
import '../support/look_alike.dart';

const bv = 'BV1GJ411x7h7';

/// Stands in for PlayerStage, so the page is checked without the player's own UI.
Widget stageStandIn(BuildContext context, PlaybackController controller) =>
    const SizedBox.expand(key: ValueKey('stage'));

final class FakeLogFiles implements LogFiles {
  String? path;
  Object? failure;
  int exports = 0;
  int clears = 0;

  /// Thrown by every clear.
  Object? clearFailure;

  /// What the next exports answer once it completes, in place of [path].
  Future<String?>? pending;

  @override
  Future<void> clear() async {
    clears += 1;
    if (clearFailure case final failure?) throw failure;
  }

  @override
  Future<String?> export() async {
    exports += 1;
    if (failure case final failure?) throw failure;
    return pending ?? path;
  }
}

final class FakeDiscovery implements LogServerDiscovery {
  final controller = StreamController<List<LogServerEndpoint>>.broadcast(sync: true);

  @override
  Stream<List<LogServerEndpoint>> browse() => controller.stream;
}

/// A forwarder that sends nowhere, disposed with the test.
LogForwarder quietLogs({LogServerDiscovery discovery = const NoLogServerDiscovery()}) {
  final logs = LogForwarder(
    logger: Logger(session: 'test'),
    discovery: discovery,
    poster: (endpoint) => (body) async {},
    initialTarget: '',
  );
  addTearDown(logs.dispose);
  return logs;
}

/// The watch reports a test says are waiting.
final class HeldOutbox extends HistoryOutbox {
  HeldOutbox(this.held) : super.memory();

  final List<PendingReport> held;

  @override
  List<PendingReport> get reports => held;
}

/// Counts what 开发者 asks of the token.
class StubAppAuth extends ChangeNotifier implements AppAuth {
  StubAppAuth({this.expiresAt, this.issuedTo = OfficialIdentity.iphone});

  @override
  DateTime? expiresAt;

  /// The app its token is issued to, held or yet to be asked for.
  final OfficialIdentity issuedTo;

  @override
  OfficialIdentity? get identity => authorized ? issuedTo : null;

  int requests = 0;
  int reauthorizations = 0;

  @override
  bool get authorized => expiresAt != null;

  @override
  Future<void> start() async {}

  @override
  Future<bool> request(BuildContext context) async {
    requests += 1;
    expiresAt = DateTime.now().add(const Duration(days: 180, hours: 12));
    notifyListeners();
    return true;
  }

  @override
  Future<bool> reauthorize(BuildContext context) async {
    reauthorizations += 1;
    return true;
  }
}

final class TrialLibrary extends FakeOfflineLibrary {
  TrialLibrary(this.trials);

  @override
  final BackgroundTrials trials;
}

BackgroundTrip trip(BackgroundArm arm, {required double seconds, required int megabytes}) => BackgroundTrip(
  arm: arm,
  at: DateTime(2026, 11, 1, 21),
  seconds: seconds,
  gainedBytes: megabytes << 20,
  wastedBytes: 0,
  allDone: false,
);

/// 开发者 as 设置 opens it: the app's players on a [shared] engine of fakes (each start a new [FakePlayer]; the
/// engines started are in [engines]), the canned account, and the page pushed over a blank home so it can be left.
final class DeveloperWorld {
  DeveloperWorld({this.offline, this.historyOutbox, this.device});

  final OfflineLibrary? offline;
  final HistoryOutbox? historyOutbox;
  final PlayerDevice? device;

  final http = Canned.http();
  final time = ManualClock(10000);
  final logger = Logger(session: 'test');
  final navigator = GlobalKey<NavigatorState>();
  final logFiles = FakeLogFiles();
  final codecMemory = CodecMemory();
  final engines = <FakeEngine>[];
  final players = <FakePlayer>[];
  final controllers = <PlaybackController>[];

  /// Holds each player's start until the test completes it.
  Completer<void>? startGate;
  late final AppEnvironment environment;
  late final SharedEngine shared = SharedEngine(() async {
    final engine = FakeEngine();
    engines.add(engine);
    return engine;
  }, logger: logger);
  late final AppPlayback playback;
  late final AppServices services;

  /// Thrown by the next player's start.
  Object? startError;

  Future<PlaybackController> _start() async {
    await startGate?.future;
    if (startError case final error?) {
      startError = null;
      throw error;
    }
    final player = FakePlayer();
    players.add(player);
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    final controller = PlaybackController(
      client: environment.client,
      engine: await shared.lease(),
      startEngine: shared.lease,
      player: player,
      clock: time.clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
    controllers.add(controller);
    return controller;
  }

  /// Shows a blank home, runs [before], then pushes the page; [height] tall at one pixel a point, so every row is
  /// built, or as KaiC's iPhone with [phone].
  Future<void> show(
    WidgetTester tester, {
    double height = 2400,
    LogForwarder? logs,
    SpeedTestHooks? hooks,
    AppAuth? appAuth,
    PlayerPrefs? prefs,
    ShareFile? shareFile,
    String version = '1.3.0 (7)',
    FutureOr<void> Function()? before,
    bool phone = false,
    ThemeData? theme,
  }) async {
    if (phone) {
      showAsPhone(tester);
    } else {
      tester.view
        ..physicalSize = Size(440, height)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    await prepare(logs: logs);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        navigatorKey: navigator,
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('shot'),
          child: AppScope(services: services, child: child!),
        ),
        home: const SizedBox(),
      ),
    );
    await before?.call();
    _page = () => DeveloperPage(
      startPlayback: playback.create,
      releasePlayback: playback.release,
      logs: logs,
      speedTestHooks: hooks ?? appSpeedTestHooksOn(shared),
      stageBuilder: stageStandIn,
      shareFile: shareFile ?? (path, origin) async {},
      prefs: prefs ?? PlayerPrefs.memory(logger: logger),
      appAuth: appAuth,
      version: version,
    );
    await push(tester);
  }

  late DeveloperPage Function() _page;

  /// Opens the page again, as [show] made it.
  Future<void> push(WidgetTester tester) async {
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => _page())));
    await frames(tester);
  }

  /// The services alone, for tests that pump the page themselves.
  Future<void> prepare({LogForwarder? logs}) async {
    environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    playback = AppPlayback(_start, engine: shared, codecMemory: codecMemory, logger: logger);
    addTearDown(() {
      for (final controller in controllers) {
        playback.release(controller);
      }
      playback.dispose();
    });
    services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      device: device,
      offline: offline,
      historyOutbox: historyOutbox,
      logFiles: logFiles,
      logs: logs,
    );
  }

  void pop() => navigator.currentState!.pop();
}

Future<void> frames(WidgetTester tester, [int count = 10]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Scrolls [finder] into view and taps it.
Future<void> press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}
