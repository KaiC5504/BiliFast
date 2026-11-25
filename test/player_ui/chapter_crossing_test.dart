import 'package:bili_core/api.dart' show Chapter;
import 'package:bilifast/player_ui/chapter_crossing.dart';
import 'package:flutter_test/flutter_test.dart';

const _chapters = [
  Chapter(from: 0, to: 30, title: '开场'),
  Chapter(from: 30, to: 70, title: '正片'),
  Chapter(from: 70, to: 100, title: '结尾'),
];

void main() {
  test('moving past a start crosses it, forward and back', () {
    expect(ChapterCrossing.crossed(_chapters, 25, 35), isTrue);
    expect(ChapterCrossing.crossed(_chapters, 35, 25), isTrue);
    expect(ChapterCrossing.crossed(_chapters, 65, 75), isTrue);
    expect(ChapterCrossing.crossed(_chapters, 75, 65), isTrue);
  });

  test('several starts in one move are one crossing', () {
    expect(ChapterCrossing.crossed(_chapters, 10, 90), isTrue);
    expect(ChapterCrossing.crossed(_chapters, 90, 10), isTrue);
  });

  test('moving inside one chapter, or not at all, crosses nothing', () {
    expect(ChapterCrossing.crossed(_chapters, 35, 65), isFalse);
    expect(ChapterCrossing.crossed(_chapters, 65, 35), isFalse);
    expect(ChapterCrossing.crossed(_chapters, 40, 40), isFalse);
    expect(ChapterCrossing.crossed(_chapters, 30, 30), isFalse);
  });

  test('a position on a start is past it: arriving crosses, leaving forward does not, leaving back does', () {
    expect(ChapterCrossing.crossed(_chapters, 25, 30), isTrue);
    expect(ChapterCrossing.crossed(_chapters, 30, 35), isFalse);
    expect(ChapterCrossing.crossed(_chapters, 35, 30), isFalse);
    expect(ChapterCrossing.crossed(_chapters, 30, 25), isTrue);
  });

  test("the first chapter's start is the bar's own, never a dot", () {
    expect(ChapterCrossing.crossed(_chapters, 0, 20), isFalse);
    expect(ChapterCrossing.crossed(_chapters, 20, 0), isFalse);
    expect(ChapterCrossing.crossed(const [Chapter(from: 5, to: 100, title: '')], 0, 20), isFalse);
  });

  test('no chapters, or a position not yet known, cross nothing', () {
    expect(ChapterCrossing.crossed(const [], 0, 100), isFalse);
    expect(ChapterCrossing.crossed(_chapters, double.nan, 50), isFalse);
    expect(ChapterCrossing.crossed(_chapters, 10, double.infinity), isFalse);
  });
}
