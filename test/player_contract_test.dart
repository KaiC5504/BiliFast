import 'package:bilifast/player/unsupported_player.dart';

import 'support/fake_player.dart';
import 'support/player_contract.dart';

void main() {
  playerContract('FakePlayer', () async => FakePlayer());
  playerContract('UnsupportedPlayer', () async => UnsupportedPlayer());
}
