import 'package:bilifast/settings/autoplay_policy.dart';
import 'package:bilifast/video/player_prefs.dart';
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
