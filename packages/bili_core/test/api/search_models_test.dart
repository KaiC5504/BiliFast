import 'package:bili_core/api.dart';
import 'package:test/test.dart';

const plain = HighlightRun.new;
HighlightRun marked(String text) => HighlightRun(text, highlighted: true);

Map<String, Object?> videoRow(Map<String, Object?> fields) => {'type': 'video', 'bvid': 'BV1Te4y1s7zZ', ...fields};

void main() {
  group('HighlightedText.parse', () {
    test('splits on the keyword marks', () {
      final text = HighlightedText.parse('前<em class="keyword">星星</em>中<em class="keyword">月亮</em>后');
      expect(text.runs, [plain('前'), marked('星星'), plain('中'), marked('月亮'), plain('后')]);
      expect(text.text, '前星星中月亮后');
    });

    test('accepts any em, including the suggestions\' marks and a bare one', () {
      expect(HighlightedText.parse('<em class="suggest_high_light">kiwi</em>jam').runs, [marked('kiwi'), plain('jam')]);
      expect(HighlightedText.parse('a<em>b</em>c').runs, [plain('a'), marked('b'), plain('c')]);
      expect(HighlightedText.parse("<EM CLASS='keyword'>大</EM>写").runs, [marked('大'), plain('写')]);
    });

    test('drops other tags and merges what they split', () {
      expect(HighlightedText.parse('一<b>二</b><br/>三<font color="red">四</font>').runs, [plain('一二三四')]);
      expect(HighlightedText.parse('<em class="keyword">星</em><em class="keyword">星</em><i></i>!').runs, [
        marked('星星'),
        plain('!'),
      ]);
      expect(HighlightedText.parse('<em class="keyword">一<b>二</b></em>').runs, [marked('一二')]);
    });

    test('drops empty runs', () {
      expect(HighlightedText.parse('<em class="keyword"></em>标题').runs, [plain('标题')]);
      expect(HighlightedText.parse('').runs, isEmpty);
      expect(HighlightedText.parse('<em class="keyword"></em>').text, '');
    });

    test('decodes entities, named and numeric, in both kinds of run', () {
      final text = HighlightedText.parse(
        '&amp; &lt;b&gt; &quot;q&quot; &#39;s&apos; a&nbsp;b &#20013; &#x6587;&#X41; <em class="keyword">&amp;</em>',
      );
      expect(text.runs, [plain('& <b> "q" \'s\' a b 中 文A '), marked('&')]);
    });

    test('leaves unknown or invalid entities and stray brackets as written', () {
      expect(HighlightedText.parse('&copy; &#xD800; &#0; & &amp').text, '&copy; &#xD800; &#0; & &amp');
      expect(HighlightedText.parse('1<2 且 3>2, <3').text, '1<2 且 3>2, <3');
      expect(HighlightedText.parse('&lt;em&gt;不是标记&lt;/em&gt;').runs, [plain('<em>不是标记</em>')]);
    });

    test('counts nested marks and ignores a stray close', () {
      expect(HighlightedText.parse('</em>a<em>b<em>c</em>d</em>e').runs, [plain('a'), marked('bcd'), plain('e')]);
      expect(HighlightedText.parse('a<em/>b').runs, [plain('ab')]);
      expect(HighlightedText.parse('a<em>b').runs, [plain('a'), marked('b')]);
    });

    test('compares by value', () {
      expect(HighlightedText.parse('a<em>b</em>'), HighlightedText([plain('a'), marked('b')]));
      expect(HighlightedText.parse('a<em>b</em>').hashCode, HighlightedText([plain('a'), marked('b')]).hashCode);
      expect(HighlightedText.parse('ab'), isNot(HighlightedText([plain('a'), marked('b')])));
    });
  });

  group('HighlightedText.marking', () {
    test('marks every occurrence whatever its case', () {
      expect(HighlightedText.marking('kiwijam联动', 'KIWI').runs, [marked('kiwi'), plain('jam联动')]);
      expect(HighlightedText.marking('Kiwi and kIWI', 'kiwi').runs, [marked('Kiwi'), plain(' and '), marked('kIWI')]);
      expect(HighlightedText.marking('联动', '联动').runs, [marked('联动')]);
    });

    test('trims the term, takes it literally, and leaves text without it plain', () {
      expect(HighlightedText.marking('c++教程', ' C++ ').runs, [marked('c++'), plain('教程')]);
      expect(HighlightedText.marking('a.b', '.').runs, [plain('a'), marked('.'), plain('b')]);
      expect(HighlightedText.marking('无关的词', 'kiwi').runs, [plain('无关的词')]);
      expect(HighlightedText.marking('无关的词', '  ').runs, [plain('无关的词')]);
    });
  });

  group('SearchVideo', () {
    test('reads durations as seconds, minutes not wrapped into hours', () {
      int seconds(Object? duration) => SearchVideo.fromJson(videoRow({'duration': duration})).duration;
      expect(seconds('3:7'), 187);
      expect(seconds('13:14'), 794);
      expect(seconds('1:02:03'), 3723);
      expect(seconds('1234:56'), 1234 * 60 + 56);
      expect(seconds('0:00'), 0);
      expect(seconds(129), 129);
      expect(seconds(129.0), 129);
      expect(seconds(''), 0);
      expect(seconds(null), 0);
      expect(seconds('live'), 0);
      expect(seconds('1:-2'), 0);
    });

    test('makes covers https', () {
      String cover(String? pic) => SearchVideo.fromJson(videoRow({'pic': pic})).cover;
      expect(cover('//i0.hdslb.com/bfs/archive/a.jpg'), 'https://i0.hdslb.com/bfs/archive/a.jpg');
      expect(cover('http://i0.hdslb.com/bfs/archive/a.jpg'), 'https://i0.hdslb.com/bfs/archive/a.jpg');
      expect(cover('https://i0.hdslb.com/bfs/archive/a.jpg'), 'https://i0.hdslb.com/bfs/archive/a.jpg');
      expect(cover(''), '');
      expect(cover(null), '');
    });

    test('reads pubdate as local time, 0 or missing as none', () {
      DateTime? published(Object? pubdate) => SearchVideo.fromJson(videoRow({'pubdate': pubdate})).published;
      final date = published(1760000000)!;
      expect(date, DateTime.fromMillisecondsSinceEpoch(1760000000 * 1000));
      expect(date.isUtc, isFalse);
      expect(published(0), isNull);
      expect(published(null), isNull);
    });

    test('reads counts as numbers or strings', () {
      final row = SearchVideo.fromJson(videoRow({'play': '1234', 'video_review': 56}));
      expect(row.play, 1234);
      expect(row.danmaku, 56);
      final other = SearchVideo.fromJson(videoRow({'play': 7, 'danmaku': '8'}));
      expect(other.play, 7);
      expect(other.danmaku, 8);
      expect(SearchVideo.fromJson(videoRow({'play': '--'})).play, 0);
    });

    test('reads the aid from id when aid is missing', () {
      expect(SearchVideo.fromJson(videoRow({'id': 42})).aid, 42);
      expect(SearchVideo.fromJson(videoRow({'aid': 7, 'id': 42})).aid, 7);
    });

    test('refuses rows that are not videos or have no bvid', () {
      expect(() => SearchVideo.fromJson(videoRow({'type': 'live_room'})), throwsA(isA<DecodeError>()));
      expect(() => SearchVideo.fromJson(videoRow({'type': 'ketang'})), throwsA(isA<DecodeError>()));
      expect(() => SearchVideo.fromJson({'type': 'video', 'bvid': ''}), throwsA(isA<DecodeError>()));
      expect(() => SearchVideo.fromJson({'type': 'video'}), throwsA(isA<DecodeError>()));
      expect(() => SearchVideo.fromJson('row'), throwsA(isA<DecodeError>()));
      expect(SearchVideo.fromJson({'bvid': 'BV1Te4y1s7zZ'}).bvid, 'BV1Te4y1s7zZ', reason: 'no type is a video');
    });
  });

  group('SearchUser', () {
    Map<String, Object?> userRow(Map<String, Object?> fields) => {'mid': 1, 'uname': '名字', ...fields};

    test('maps verification: 0 and 1 kept, anything else none', () {
      int? type(Object? verify) => SearchUser.fromJson(userRow({'official_verify': verify})).officialType;
      expect(type({'type': 0, 'desc': '个人'}), 0);
      expect(type({'type': 1, 'desc': '机构'}), 1);
      expect(type({'type': 127, 'desc': ''}), isNull);
      expect(type({'type': -1, 'desc': ''}), isNull);
      expect(type({'desc': ''}), isNull);
      expect(type(null), isNull);
      expect(
        SearchUser.fromJson(
          userRow({
            'official_verify': {'type': 0, 'desc': '个人'},
          }),
        ).officialDesc,
        '个人',
      );
      expect(SearchUser.fromJson(userRow({})).officialDesc, '');
    });

    test('makes faces https and reads following', () {
      expect(SearchUser.fromJson(userRow({'upic': '//i0.hdslb.com/f.jpg'})).face, 'https://i0.hdslb.com/f.jpg');
      expect(SearchUser.fromJson(userRow({'is_atten': 1})).following, isTrue);
      expect(SearchUser.fromJson(userRow({'is_atten': 0})).following, isFalse);
      expect(SearchUser.fromJson(userRow({})).following, isFalse);
    });

    test('refuses a row without a mid', () {
      expect(() => SearchUser.fromJson({'uname': '名字'}), throwsA(isA<DecodeError>()));
      expect(() => SearchUser.fromJson({'mid': 0}), throwsA(isA<DecodeError>()));
    });
  });

  group('words', () {
    test('a hot word falls back to its keyword and makes its badge https', () {
      expect(
        HotWord.fromJson({'keyword': '词', 'icon': 'http://i0.hdslb.com/b.png'}),
        const HotWord(keyword: '词', showName: '词', icon: 'https://i0.hdslb.com/b.png'),
      );
      expect(HotWord.fromJson({'keyword': '词', 'icon': ''}).icon, isNull);
      expect(HotWord.fromJson({'keyword': '词', 'icon': 3}).icon, isNull);
      expect(() => HotWord.fromJson({'show_name': '词'}), throwsA(isA<DecodeError>()));
      expect(() => HotWord.fromJson({'keyword': 5}), throwsA(isA<DecodeError>()));
    });

    test('a discovery word falls back to its keyword', () {
      expect(DiscoveryWord.fromJson({'keyword': '词'}), const DiscoveryWord(keyword: '词', showName: '词'));
      expect(DiscoveryWord.fromJson({'keyword': '词', 'show_name': '展示'}).showName, '展示');
      expect(() => DiscoveryWord.fromJson({'keyword': ''}), throwsA(isA<DecodeError>()));
    });

    test("a discovery word's suffix is its recommend reason without the dot, else its pub time", () {
      String suffix(Map<String, Object?> fields) => DiscoveryWord.fromJson({'keyword': '词', ...fields}).suffix;
      expect(suffix({'recommend_reason': '·昨天更新'}), '昨天更新');
      expect(suffix({'recommend_reason': '昨天更新', 'pub_time': '3天前'}), '昨天更新');
      expect(suffix({'recommend_reason': '·', 'pub_time': '3天前'}), '3天前');
      expect(suffix({'recommend_reason': '', 'pub_time': ''}), '');
      expect(suffix({}), '');
      expect(
        DiscoveryWord.fromJson({'keyword': '词', 'recommend_reason': '·新'}),
        isNot(DiscoveryWord.fromJson({'keyword': '词'})),
        reason: 'the suffix is part of equality',
      );
    });

    test('a suggestion takes its keyword from value, else term', () {
      expect(SearchSuggestion.fromJson({'value': 'kiwi', 'name': 'kiwi'}, 'K').keyword, 'kiwi');
      expect(SearchSuggestion.fromJson({'term': 'kiwi'}, 'K').keyword, 'kiwi');
      expect(SearchSuggestion.fromJson({'term': 'kiwi'}, 'K').text.runs, [marked('k'), plain('iwi')]);
      expect(() => SearchSuggestion.fromJson({'value': ' '}, 's'), throwsA(isA<DecodeError>()));
    });
  });

  test('a page has more until its last', () {
    expect(const SearchPage<int>(items: [1], page: 1, pages: 2).hasMore, isTrue);
    expect(const SearchPage<int>(items: [1], page: 2, pages: 2).hasMore, isFalse);
  });
}
