import 'app_signer.dart';

/// The iPhone identity's fixed labels, the same for every install: the app version and store channel its calls were
/// read from, and that phone's model and screen.
abstract final class IphoneLabels {
  static const build = '91800100';
  static const version = '9.18.0';
  static const channel = 'pink_overseas';
  static const model = 'iPhone 17 Pro Max';
  static const osVersion = '27.2';

  /// The feed's `player_extra_content`: the screen in pixels.
  static const screen = '{"short_edge":"1320","long_edge":"2868"}';
}

/// Which official app a call is made as: its signing pair and the labels sent with every call. A token only works
/// with the pair that issued it, so every `AppToken` keeps the identity of its login.
enum OfficialIdentity {
  /// The Android app 8.43.0 on the HD pair (PiliPlus's): every install's identity before 1.3.0 (12).
  android,

  /// The iPhone app 9.18.0, as its own requests go out (docs/reference/official-iphone-calls.md).
  iphone;

  /// A stored token's identity; one stored before identities existed is the Android app's.
  static OfficialIdentity named(String? name) => name == iphone.name ? iphone : android;

  AppSigner get signer => switch (this) {
    android => AppSigner.android,
    iphone => AppSigner.iphone,
  };
}
