import 'package:bili_core/devlog.dart';
import 'package:bilifast/settings/autoplay_policy.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PlayerPrefs prefs;
  AutoplayPolicy policy({required bool cellular}) =>
      AutoplayPolicy(prefs: () => prefs, onCellular: () async => cellular)..onCellularForTest = cellular;

  setUp(() => prefs = PlayerPrefs.memory());

  test('everything plays by itself by default, on Wi-Fi and on mobile data', () {
    for (final cellular in [false, true]) {
      final rules = policy(cellular: cellular);
      expect((rules.detail, rules.home, rules.list), (true, true, true));
    }
  });

  test('流量网络下自动播放 off holds everything on mobile data only', () {
    prefs.cellularAutoplay = false;
    final wifi = policy(cellular: false);
    final cellular = policy(cellular: true);
    expect((wifi.detail, wifi.home, wifi.list), (true, true, true));
    expect((cellular.detail, cellular.home, cellular.list), (false, false, false));
  });

  test('仅 Wi-Fi plays on Wi-Fi alone, 关闭 never', () {
    prefs
      ..homeAutoplay = AutoplayChoice.wifiOnly
      ..listAutoplay = AutoplayChoice.off;
    expect((policy(cellular: false).home, policy(cellular: true).home), (true, false));
    expect((policy(cellular: false).list, policy(cellular: true).list), (false, false));
  });

  test('详情页直接播放 off opens every page paused', () {
    prefs.detailAutoplay = false;
    expect((policy(cellular: false).detail, policy(cellular: true).detail), (false, false));
  });

  test('refresh takes the network the host reports', () async {
    var cellular = true;
    final rules = AutoplayPolicy(prefs: () => prefs, onCellular: () async => cellular);
    await rules.refresh();
    expect(rules.onCellular, isTrue);
    cellular = false;
    await rules.refresh();
    expect(rules.onCellular, isFalse);
  });

  group('before the network is known', () {
    AutoplayPolicy unknown() => AutoplayPolicy(prefs: () => prefs, onCellular: () async => throw StateError('no'));

    test('仅 Wi-Fi holds; 默认 plays, and so does the page, unless 流量网络下自动播放 is off', () async {
      prefs.homeAutoplay = AutoplayChoice.wifiOnly;
      final rules = unknown();
      expect(rules.onCellular, isNull);
      expect((rules.home, rules.list, rules.detail), (false, true, true));
      await rules.refresh();
      expect(rules.onCellular, isNull, reason: 'a failed ask with no answer yet');
      expect((rules.home, rules.list, rules.detail), (false, true, true));
      prefs.cellularAutoplay = false;
      expect((rules.home, rules.list, rules.detail), (false, false, false));
    });

    test('a failed ask after an answer keeps the answer', () async {
      var fails = false;
      final rules = AutoplayPolicy(prefs: () => prefs, onCellular: () async => fails ? throw StateError('no') : false);
      await rules.refresh();
      fails = true;
      await rules.refresh();
      expect(rules.onCellular, isFalse);
    });

    test('a fixed network is known from the start', () {
      expect(AutoplayPolicy.fixed().onCellular, isFalse);
      expect(AutoplayPolicy.fixed(onCellular: true).onCellular, isTrue);
    });
  });

  test('a new reading notifies; the same one again does not', () async {
    var cellular = false;
    final rules = AutoplayPolicy(prefs: () => prefs, onCellular: () async => cellular);
    var heard = 0;
    rules.addListener(() => heard++);
    await rules.refresh();
    expect(heard, 1, reason: 'unknown to Wi-Fi');
    await rules.refresh();
    expect(heard, 1);
    cellular = true;
    await rules.refresh();
    expect(heard, 2);
  });

  test('the network is asked again as the app comes back, from inactive on', () async {
    var asks = 0;
    final rules = AutoplayPolicy(
      prefs: () => prefs,
      onCellular: () async {
        asks++;
        return false;
      },
    );
    rules.didChangeAppLifecycleState(AppLifecycleState.hidden);
    expect(asks, 0);
    rules.didChangeAppLifecycleState(AppLifecycleState.inactive);
    rules.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(asks, 2);
  });

  test('a failed ask logs the error\'s type only', () async {
    final logs = MemorySink();
    final rules = AutoplayPolicy(
      prefs: () => prefs,
      onCellular: () async => throw PlatformException(code: 'x', message: 'https://example.invalid/secret'),
      logger: Logger(session: 'test')..add(logs),
    );
    await rules.refresh();
    final event = logs.events.single;
    expect(event.msg, 'autoplay network unknown');
    expect(event.f, {'error': const LogString('PlatformException')});
  });

  test('the new choices survive the file', () {
    prefs
      ..cellularAutoplay = false
      ..detailAutoplay = false
      ..detailFullScreen = true
      ..homeAutoplay = AutoplayChoice.off
      ..listAutoplay = AutoplayChoice.wifiOnly
      ..bigCardSound = true
      ..verticalFullScreen = false
      ..autoPip = false;
    final json = prefs.toJson();
    expect(json['homeAutoplay'], 'off');
    expect(json['listAutoplay'], 'wifiOnly');
    expect(PlayerPrefs.memory().toJson().keys, isNot(contains('homeAutoplay')));
  });
}
