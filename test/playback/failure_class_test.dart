import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a format refusal is a format failure whatever the domain', () {
    expect(classifyFailure(const PlayerFailed('x', domain: 'NSURLErrorDomain', formatRejected: true)),
        ItemFailure.format);
  });

  test('an NSURLErrorDomain error is a network failure', () {
    expect(classifyFailure(const PlayerFailed('x', domain: 'NSURLErrorDomain', code: -1009)), ItemFailure.network);
  });

  test("an HTTP status from AVPlayer's error log is a network failure", () {
    expect(classifyFailure(const PlayerFailed('x', domain: 'CoreMediaErrorDomain', code: 403)), ItemFailure.network);
    expect(classifyFailure(const PlayerFailed('x', domain: 'CoreMediaErrorDomain', code: 503)), ItemFailure.network);
  });

  test('anything else is unknown', () {
    expect(classifyFailure(const PlayerFailed('x', domain: 'AVFoundationErrorDomain', code: -11800)),
        ItemFailure.unknown);
    expect(classifyFailure(const PlayerFailed('x')), ItemFailure.unknown);
  });
}
