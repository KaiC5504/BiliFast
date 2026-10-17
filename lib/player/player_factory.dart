import 'dart:io';

import 'bili_player.dart';
import 'ios_player.dart';
import 'unsupported_player.dart';
import 'windows_player.dart';

Future<BiliPlayer> createPlayer() async {
  if (Platform.isIOS) return IosPlayer.create();
  if (Platform.isWindows) return WindowsPlayer.create();
  return UnsupportedPlayer();
}
