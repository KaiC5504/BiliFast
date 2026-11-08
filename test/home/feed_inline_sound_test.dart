import 'package:bilifast/home/feed_inline_player.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

// The notifier takes 大卡默认声音 on its first read, so nothing else in this file may read it first.
void main() {
  test('the big cards start with 大卡默认声音 as launched; a change waits for the next launch; reset keeps muted', () {
    final launched = PlayerPrefs.shared;
    addTearDown(() => PlayerPrefs.shared = launched);
    PlayerPrefs.shared = PlayerPrefs.memory()..bigCardSound = true;
    expect(FeedInlineChoices.sound.value, isTrue);

    PlayerPrefs.shared.bigCardSound = false;
    expect(FeedInlineChoices.sound.value, isTrue, reason: '重启后生效');

    FeedInlineChoices.reset();
    expect(FeedInlineChoices.sound.value, isFalse);
    expect(FeedInlineChoices.danmaku.value, isTrue);
  });
}
