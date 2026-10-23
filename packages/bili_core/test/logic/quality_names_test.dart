import 'package:bili_core/logic.dart';
import 'package:test/test.dart';

void main() {
  test("full names are the official app's, not the server's", () {
    expect(QualityNames.full(qn: 125, serverText: '真彩 HDR'), 'HDR 真彩');
    expect(QualityNames.full(qn: 120, serverText: '超清 4K'), '4K 超高清');
    expect(QualityNames.full(qn: 116, serverText: '高清 1080P60'), '1080P 60帧');
    expect(QualityNames.full(qn: 112, serverText: '高码率 1080P+'), '1080P 高码率');
    expect(QualityNames.full(qn: 80, serverText: '高清 1080P'), '1080P 高清');
    expect(QualityNames.full(qn: 64, serverText: '高清 720P'), '720P 准高清');
    expect(QualityNames.full(qn: 32, serverText: '清晰 480P'), '480P 标清');
  });

  test("full falls back to the server's text, then the number", () {
    expect(QualityNames.full(qn: 999, serverText: '未知'), '未知');
    expect(QualityNames.full(qn: 999, serverText: null), '999');
  });

  test('short names for the player button', () {
    expect(QualityNames.short(qn: 120, serverText: '超清 4K'), '4K');
    expect(QualityNames.short(qn: 32, serverText: null), '480P');
    expect(QualityNames.short(qn: 126, serverText: null), '杜比视界');
  });

  test('60 fps shows as the plain name under a 60帧 tag, as the official button does', () {
    expect(QualityNames.short(qn: 116, serverText: '高清 1080P60'), '1080P');
    expect(QualityNames.tag(116), '60帧');
    expect(QualityNames.short(qn: 74, serverText: null), '720P');
    expect(QualityNames.tag(74), '60帧');
    expect(QualityNames.short(qn: 112, serverText: null), '1080P');
    expect(QualityNames.tag(112), '高码率');
    expect(QualityNames.tag(80), isNull);
    expect(QualityNames.tag(120), isNull);
  });

  test("short falls back to the last word of the server's text, then a placeholder", () {
    expect(QualityNames.short(qn: 999, serverText: '高清 900P'), '900P');
    expect(QualityNames.short(qn: 999, serverText: null), '清晰度');
  });

  test('every full name has a short name', () {
    for (final qn in [127, 126, 125, 120, 116, 112, 80, 74, 64, 32, 16]) {
      expect(QualityNames.short(qn: qn, serverText: null), isNot('清晰度'), reason: 'qn $qn');
      expect(QualityNames.full(qn: qn, serverText: null), isNot('$qn'), reason: 'qn $qn');
    }
  });
}
