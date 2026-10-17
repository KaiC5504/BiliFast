import 'package:bili_core/api.dart';
import 'package:test/test.dart';

const doge = EmoteRef(url: 'u', size: 1);

List<RichRun> runs(
  String message, {
  Map<String, EmoteRef> emotes = const {},
  Map<String, int> mentions = const {},
  Map<String, LinkRef> links = const {},
}) =>
    RichText.runs(message, emotes: emotes, mentions: mentions, links: links);

void main() {
  test('runs split emotes, mentions, links, videos and timestamps', () {
    final found = RichText.runs('看[doge]@小明 BV1GJ411x7h7 在03:15这里',
        emotes: {'[doge]': const EmoteRef(url: 'u', size: 1)}, mentions: {'小明': 42}, links: {});
    expect(found, const [
      RichRun.text('看'),
      RichRun.emote(token: '[doge]', url: 'u', size: 1),
      RichRun.mention(name: '小明', mid: 42),
      RichRun.text(' '),
      RichRun.video(id: 'BV1GJ411x7h7'),
      RichRun.text(' 在'),
      RichRun.timestamp(label: '03:15', seconds: 195),
      RichRun.text('这里'),
    ]);
  });

  test('runs keep emoji and unknown tokens', () {
    expect(
        RichText.runs('😀[未知]😀[doge][doge]',
            emotes: {'[doge]': const EmoteRef(url: 'u', size: 1)}, mentions: {}, links: {}),
        const [
          RichRun.text('😀[未知]😀'),
          RichRun.emote(token: '[doge]', url: 'u', size: 1),
          RichRun.emote(token: '[doge]', url: 'u', size: 1),
        ]);
  });

  test('plain and empty messages', () {
    expect(runs('没有任何标记'), const [RichRun.text('没有任何标记')]);
    expect(runs(''), isEmpty);
    expect(runs('[doge]', emotes: {'[doge]': doge}), const [RichRun.emote(token: '[doge]', url: 'u', size: 1)]);
  });

  test('emote size is carried', () {
    expect(runs('[大]', emotes: {'[大]': const EmoteRef(url: 'big', size: 2)}),
        const [RichRun.emote(token: '[大]', url: 'big', size: 2)]);
  });

  test('the longest mention wins at one position', () {
    final found = runs('@小明明 和 @小明', mentions: {'小明': 1, '小明明': 2});
    expect(found, const [
      RichRun.mention(name: '小明明', mid: 2),
      RichRun.text(' 和 '),
      RichRun.mention(name: '小明', mid: 1),
    ]);
  });

  test('a mention without the at sign stays text', () {
    expect(runs('小明 来了', mentions: {'小明': 1}), const [RichRun.text('小明 来了')]);
  });

  test('each link key is replaced once', () {
    final links = {'rick叔': const LinkRef(title: 'rick叔', url: 'https://search.bilibili.com/all?keyword=rick')};
    final found = runs('rick叔的歌，rick叔真好', links: links);
    expect(found, const [
      RichRun.link(title: 'rick叔', url: 'https://search.bilibili.com/all?keyword=rick'),
      RichRun.text('的歌，rick叔真好'),
    ]);
  });

  test('link keys beat video ids and emotes beat links', () {
    final links = {'BV1GJ411x7h7': const LinkRef(title: '某个视频', url: 'https://www.bilibili.com/video/BV1GJ411x7h7')};
    expect(runs('看 BV1GJ411x7h7 和 BV1AB411c7mD', links: links), const [
      RichRun.text('看 '),
      RichRun.link(title: '某个视频', url: 'https://www.bilibili.com/video/BV1GJ411x7h7'),
      RichRun.text(' 和 '),
      RichRun.video(id: 'BV1AB411c7mD'),
    ]);
    expect(runs('[doge]', emotes: {'[doge]': doge}, links: {'[doge]': const LinkRef(title: 't', url: 'x')}),
        const [RichRun.emote(token: '[doge]', url: 'u', size: 1)]);
  });

  test('video ids', () {
    expect(runs('av170001和BV1GJ411x7h7。'), const [
      RichRun.video(id: 'av170001'),
      RichRun.text('和'),
      RichRun.video(id: 'BV1GJ411x7h7'),
      RichRun.text('。'),
    ]);
    expect(runs('BV1GJ411'), const [RichRun.text('BV1GJ411')]);
    expect(runs('av 123 和 avatar'), const [RichRun.text('av 123 和 avatar')]);
    expect(runs('BV1GJ411x7h!'), const [RichRun.text('BV1GJ411x7h!')]);
    expect(runs('lav12'), const [RichRun.text('lav12')]);
  });

  test('timestamps', () {
    expect(runs('1:05:09开始'), const [RichRun.timestamp(label: '1:05:09', seconds: 3909), RichRun.text('开始')]);
    expect(runs('看12：30'), const [RichRun.text('看'), RichRun.timestamp(label: '12：30', seconds: 750)]);
    expect(runs('00:00'), const [RichRun.timestamp(label: '00:00', seconds: 0)]);
    expect(runs('03:15 03:20'), const [
      RichRun.timestamp(label: '03:15', seconds: 195),
      RichRun.text(' '),
      RichRun.timestamp(label: '03:20', seconds: 200),
    ]);
  });

  test('numbers that are not timestamps stay text', () {
    expect(runs('比例3:2'), const [RichRun.text('比例3:2')]);
    expect(runs('1920:1080'), const [RichRun.text('1920:1080')]);
    expect(runs('2024:15'), const [RichRun.text('2024:15')]);
    expect(runs('03:156'), const [RichRun.text('03:156')]);
    expect(runs('10:30:456'), const [RichRun.timestamp(label: '10:30', seconds: 630), RichRun.text(':456')]);
    expect(runs('1:99'), const [RichRun.text('1:99')]);
  });

  test('splitting never cuts a character', () {
    // 1️⃣ is a digit plus two combining scalars, so it is one character that is not the digit 1.
    expect(runs('1\u{FE0F}\u{20E3}2:30'),
        const [RichRun.text('1\u{FE0F}\u{20E3}'), RichRun.timestamp(label: '2:30', seconds: 150)]);
    // A combining accent after the closing bracket makes the last character something other than "]".
    const accented = '[doge]\u{301}';
    expect(runs(accented, emotes: {'[doge]': doge}), const [RichRun.text(accented)]);
    expect(runs('👨‍👩‍👧@小明', mentions: {'小明': 1}), const [RichRun.text('👨‍👩‍👧'), RichRun.mention(name: '小明', mid: 1)]);
  });

  test('text around every kind is merged when nothing matches between', () {
    expect(runs('a[未知]b@没人c', emotes: {'[doge]': doge}, mentions: {'小明': 1}), const [RichRun.text('a[未知]b@没人c')]);
  });
}
