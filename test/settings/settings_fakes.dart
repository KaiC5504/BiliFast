import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/devtools/log_files.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/codec_memory.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../playback/fakes.dart';
import '../support/fake_player.dart';

/// The account half 设置 reads, without a keychain or a network: the state is set by the test, and [logout] records
/// the call and ends logged out, as the real one does.
class FakeEnvironment extends ChangeNotifier implements AppEnvironment {
  FakeEnvironment(this._account);

  Account _account;
  int logouts = 0;
  int refreshes = 0;

  @override
  bool accountCheckFailed = false;

  /// Thrown by the next [logout].
  Object? logoutError;

  @override
  Account get account => _account;

  @override
  ValueListenable<int> get logins => _logins;
  final _logins = ValueNotifier<int>(0);

  set account(Account value) {
    _account = value;
    notifyListeners();
  }

  @override
  String get accountLabel => switch (_account) {
    LoggedIn(:final name) => name,
    LoggedOut() => '未登录',
    LoginExpired() => '登录已失效',
    AccountUnknown() => accountCheckFailed ? '账号确认失败' : '正在确认账号…',
  };

  @override
  Future<bool> refreshAccount() async {
    refreshes += 1;
    return false;
  }

  @override
  Future<void> logout() async {
    logouts += 1;
    final error = logoutError;
    if (error != null) {
      logoutError = null;
      throw error;
    }
    account = const LoggedOut();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLoginGate implements LoginGate {
  int requests = 0;

  @override
  Future<bool> request(BuildContext context) async {
    requests += 1;
    return false;
  }
}

class FakeLogFiles implements LogFiles {
  int clears = 0;

  @override
  Future<void> clear() async => clears += 1;

  @override
  Future<String?> export() async => null;
}

/// 设置's world: a shared controller on [engine] with its codec [memory], an empty 最近打开 and the fakes above. The
/// controller is ready unless a [startGate] holds its start until the test completes it.
class SettingsWorld {
  SettingsWorld._(this.services, this.environment, this.gate, this.logFiles, this.engine, this.memory, this.controller);

  static Future<SettingsWorld> create({Account account = const LoggedOut(), Completer<void>? startGate}) async {
    final environment = FakeEnvironment(account);
    final gate = FakeLoginGate();
    final logFiles = FakeLogFiles();
    final engine = FakeEngine();
    final memory = CodecMemory();
    final logger = Logger(session: 'test');
    final controller = PlaybackController(
      client: BiliClient(transport: CannedHttp(), cookies: CookieJar(), logger: logger),
      engine: engine,
      player: FakePlayer(),
      codecMemory: memory,
      startTimer: FakeTimers().start,
      logger: logger,
    );
    final playback = AppPlayback(() async {
      await startGate?.future;
      return controller;
    });
    if (startGate == null) await playback.obtain();
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null),
      fonts: FontStore.memory(logger: logger),
      pageApi: FakePageApi(),
      loginGate: gate,
      logFiles: logFiles,
    );
    return SettingsWorld._(services, environment, gate, logFiles, engine, memory, controller);
  }

  final AppServices services;
  final FakeEnvironment environment;
  final FakeLoginGate gate;
  final FakeLogFiles logFiles;
  final FakeEngine engine;
  final CodecMemory memory;
  final PlaybackController controller;

  void dispose() {
    services.playback.dispose();
    controller.dispose();
  }
}

const sampleRecent = RecentVideo(bvid: 'BV1GJ411x7h7', cid: 1, title: '一个视频', part: '', page: 1, pageCount: 1);
