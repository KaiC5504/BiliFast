import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the controls start shown and toggle', () {
    final chrome = ChromeState();
    addTearDown(chrome.dispose);
    var notified = 0;
    chrome.addListener(() => notified++);
    expect(chrome.visible, isTrue);
    chrome.toggle();
    expect(chrome.visible, isFalse);
    chrome.toggle();
    expect(chrome.visible, isTrue);
    chrome.show();
    expect(notified, 2, reason: 'showing shown controls changes nothing');
  });

  test('with auto-hide on, shown controls hide after the delay, and each show restarts it', () {
    fakeAsync((async) {
      final chrome = ChromeState();
      chrome.autoHide = true;
      async.elapse(const Duration(milliseconds: 2900));
      expect(chrome.visible, isTrue);
      chrome.show();
      async.elapse(const Duration(milliseconds: 2900));
      expect(chrome.visible, isTrue);
      async.elapse(const Duration(milliseconds: 200));
      expect(chrome.visible, isFalse);
      chrome.dispose();
    });
  });

  test('turning auto-hide off keeps the controls up; hidden controls start no timer', () {
    fakeAsync((async) {
      final chrome = ChromeState();
      chrome.autoHide = true;
      async.elapse(const Duration(seconds: 2));
      chrome.autoHide = false;
      async.elapse(const Duration(seconds: 5));
      expect(chrome.visible, isTrue);

      chrome.hide();
      chrome.autoHide = true;
      expect(async.pendingTimers, isEmpty);
      chrome.show();
      async.elapse(const Duration(seconds: 3));
      expect(chrome.visible, isFalse);
      chrome.dispose();
    });
  });

  test('hiding cancels the timer, so a later show gets the full delay', () {
    fakeAsync((async) {
      final chrome = ChromeState()..autoHide = true;
      async.elapse(const Duration(seconds: 2));
      chrome.hide();
      chrome.show();
      async.elapse(const Duration(milliseconds: 2500));
      expect(chrome.visible, isTrue);
      chrome.dispose();
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('the HUD holds one value, compared by what it shows', () {
    final chrome = ChromeState();
    addTearDown(chrome.dispose);
    var notified = 0;
    chrome.hud.addListener(() => notified++);
    chrome.showHud(const SeekHud(target: 10, duration: 60));
    chrome.showHud(const SeekHud(target: 10, duration: 60));
    expect(notified, 1);
    chrome.showHud(const SeekHud(target: 11, duration: 60));
    chrome.showHud(const LevelHud(LevelKind.volume, 0.5));
    expect(chrome.hud.value, const LevelHud(LevelKind.volume, 0.5));
    expect(const LevelHud(LevelKind.volume, 0.5), isNot(const LevelHud(LevelKind.brightness, 0.5)));
    chrome.showHud(null);
    expect(chrome.hud.value, isNull);
    expect(notified, 4);
    expect(chrome.visible, isTrue, reason: 'the HUD is apart from the controls');
  });
}
