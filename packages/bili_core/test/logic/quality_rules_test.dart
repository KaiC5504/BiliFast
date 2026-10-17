import 'package:bili_core/logic.dart';
import 'package:test/test.dart';

void main() {
  test('needs VIP from 112', () {
    expect(QualityRules.needsVip(80), isFalse);
    expect(QualityRules.needsVip(111), isFalse);
    expect(QualityRules.needsVip(112), isTrue);
    expect(QualityRules.needsVip(127), isTrue);
  });

  test('auto quality respects VIP', () {
    expect(QualityRules.auto(offered: [120, 116, 80, 64], isVip: false), 80);
    expect(QualityRules.auto(offered: [120, 80], isVip: true), 120);
  });

  test('auto quality picks the highest whatever the order', () {
    expect(QualityRules.auto(offered: [32, 80, 64, 116], isVip: false), 80);
    expect(QualityRules.auto(offered: [32, 80, 64, 116], isVip: true), 116);
  });

  test('auto quality is null when nothing is playable', () {
    expect(QualityRules.auto(offered: [], isVip: true), isNull);
    expect(QualityRules.auto(offered: [120, 116], isVip: false), isNull);
  });
}
