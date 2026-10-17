import 'package:bili_core/api.dart';
import 'package:test/test.dart';

void main() {
  test('full video URL with page', () {
    expect(LinkParser.parse('https://www.bilibili.com/video/BV1GJ411x7h7?p=2&spm_id_from=333.1007'),
        const VideoLink.bvid('BV1GJ411x7h7', page: 2));
  });

  test('bare ids', () {
    expect(LinkParser.parse('BV1GJ411x7h7'), const VideoLink.bvid('BV1GJ411x7h7'));
    expect(LinkParser.parse('av170001'), const VideoLink.aid(170001));
    expect(LinkParser.parse('https://m.bilibili.com/video/av170001'), const VideoLink.aid(170001));
  });

  test('text shared from the official app', () {
    const shared = '【拥有NPC剧情、CG动画、GalGame的MC整合包『化龍』1.4正式版发布-哔哩哔哩】 https://b23.tv/xyZ123a 快来看看吧！';
    expect(LinkParser.parse(shared), VideoLink.short(Uri.parse('https://b23.tv/xyZ123a')));
    expect(LinkParser.parse('看看这个 https://bili2233.cn/AbC9'), VideoLink.short(Uri.parse('https://bili2233.cn/AbC9')));
    expect(LinkParser.parse('  \nBV1GJ411x7h7\n '), const VideoLink.bvid('BV1GJ411x7h7'));
  });

  test('share text with query and full-width neighbours', () {
    const withQuery = '【标题】 https://b23.tv/AbCd123?share_source=copy 复制此链接，打开哔哩哔哩';
    expect(LinkParser.parse(withQuery), VideoLink.short(Uri.parse('https://b23.tv/AbCd123')));

    const touching = '【标题】https://b23.tv/AbCd123，快来看！';
    expect(LinkParser.parse(touching), VideoLink.short(Uri.parse('https://b23.tv/AbCd123')));

    const bracketed = '「看这个https://www.bilibili.com/video/BV1GJ411x7h7?p=3」';
    expect(LinkParser.parse(bracketed), const VideoLink.bvid('BV1GJ411x7h7', page: 3));

    expect(LinkParser.parse('推荐：av170001，不错'), const VideoLink.aid(170001));
  });

  test('rejects non-links', () {
    expect(LinkParser.parse('hello'), isNull);
    expect(LinkParser.parse('BV1GJ411x7h'), isNull);
    expect(LinkParser.parse('travel tips'), isNull);
  });
}
