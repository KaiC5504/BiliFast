import 'package:bili_core/logic.dart';
import 'package:test/test.dart';

void main() {
  double start(int lastPlayTimeMs, int lastPlayCid, int cid, double duration) =>
      ResumePoint.start(lastPlayTimeMs: lastPlayTimeMs, lastPlayCid: lastPlayCid, cid: cid, duration: duration);

  test('resume ignores other parts, the end and finished', () {
    expect(start(65000, 1, 1, 200), 65);
    expect(start(65000, 2, 1, 200), 0);
    expect(start(196000, 1, 1, 200), 0);
    expect(start(-1, 1, 1, 200), 0);
  });

  test('resume needs more than five seconds left', () {
    expect(start(195000, 1, 1, 200), 0);
    expect(start(194000, 1, 1, 200), 194);
    expect(start(0, 1, 1, 200), 0);
    expect(start(65000, 1, 1, 0), 0);
  });

  test('resume keeps fractional seconds', () {
    expect(start(65500, 1, 1, 200), 65.5);
  });
}
