import 'package:bili_core/engine.dart';
import 'package:test/test.dart';

void main() {
  test('toJson names every field once, and no overrides keep the config', () {
    const config = RipperConfig(seekBurst: true, prefetchVideoMaxBytes: 7, hurryPieceBytes: 192 * 1024);
    // A field missing from toJson or _fromJson would be reset to its default by every override.
    expect(config.toJson(), hasLength(38));
    final same = config.withOverrides(const {});
    expect(same.rejected, isEmpty);
    expect(same.config.toJson(), config.toJson());
  });

  test('overrides set fields by name and type', () {
    final result = const RipperConfig().withOverrides({
      'hurryKeepsOffSlow': true,
      'firstByteTimeoutMs': 4000,
      'seekBurstBytes': 1024,
      'prefetchVideoMaxBytes': 99,
      'hurryPieceBytes': 196608,
    });
    expect(result.rejected, isEmpty);
    expect(result.config.hurryKeepsOffSlow, isTrue);
    expect(result.config.firstByteTimeoutMs, 4000.0);
    expect(result.config.seekBurstBytes, 1024);
    expect(result.config.prefetchVideoMaxBytes, 99);
    expect(result.config.hurryPieceBytes, 196608);
  });

  test('null clears only nullable fields', () {
    final result = const RipperConfig(fixedConcurrency: 8).withOverrides({'fixedConcurrency': null, 'hurry': null});
    expect(result.config.fixedConcurrency, isNull);
    expect(result.config.hurry, isTrue);
    expect(result.rejected, ['hurry']);
  });

  test('unknown names and wrong types are rejected and change nothing', () {
    final result = const RipperConfig().withOverrides({
      'noSuchKnob': true,
      'seekBurst': 'yes',
      'minChunkBytes': 1.5,
      'hurryAheadSeconds': false,
    });
    expect(result.rejected, ['noSuchKnob', 'seekBurst', 'minChunkBytes', 'hurryAheadSeconds']);
    expect(result.config.toJson(), const RipperConfig().toJson());
  });

  test('negative numbers, and zero where it would stall every read, are rejected', () {
    final result = const RipperConfig().withOverrides({
      'pieceRounds': 0,
      'fixedConcurrency': 0,
      'hurryHedgeMinMs': -1,
      'keepBehindBytes': 0,
      'hurryPieceBytes': 0,
    });
    expect(result.rejected, ['pieceRounds', 'fixedConcurrency', 'hurryHedgeMinMs', 'hurryPieceBytes']);
    expect(result.config.keepBehindBytes, 0);
  });
}
