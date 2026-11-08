import 'package:bilifast/settings/autoplay_policy.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

/// Memory prefs in [PlayerPrefs.shared] and a fixed network in [AutoplayPolicy.shared] for one test, the shared ones
/// put back after it. Returns the prefs, to set 自动播放设置's choices on.
PlayerPrefs autoplayRules({bool cellular = false}) {
  final prefs = PlayerPrefs.shared;
  final policy = AutoplayPolicy.shared;
  addTearDown(() {
    PlayerPrefs.shared = prefs;
    AutoplayPolicy.shared = policy;
  });
  AutoplayPolicy.shared = AutoplayPolicy.fixed(onCellular: cellular);
  return PlayerPrefs.shared = PlayerPrefs.memory();
}

/// The phone moving between Wi-Fi and mobile data mid-test.
void onCellular(bool cellular) => AutoplayPolicy.shared = AutoplayPolicy.fixed(onCellular: cellular);
