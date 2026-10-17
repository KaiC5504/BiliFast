import 'dart:io';

import 'bili_player.dart';
import 'ios_player.dart';
import 'unsupported_player.dart';
import 'windows_player.dart';

Future<BiliPlayer> createPlayer() async {
  if (Platform.isIOS) return IosPlayer.create();
  // `--dart-define=MUTE=true` for test runs on the PC: they must make no sound.
  if (Platform.isWindows) return WindowsPlayer.create(muted: const bool.fromEnvironment('MUTE'));
  return UnsupportedPlayer();
}
