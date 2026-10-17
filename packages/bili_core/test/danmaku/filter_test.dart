import 'dart:convert';

import 'package:bili_core/danmaku.dart';
import 'package:test/test.dart';

import 'helpers.dart';

List<String> shown(
  List<DanmakuElem> elems, [
  DanmakuFilterOptions options = const DanmakuFilterOptions(),
  List<BlockRule> rules = const [],
  String? own,
]) => [for (final d in DanmakuFilter.apply(elems, options: options, rules: rules, ownHash: own)) d.text];

void main() {
  test('midHash matches CRC-32', () {
    expect(MidHash.of(12345), 'cbf53a1c'); // zlib.crc32(b"12345")
    expect(MidHash.of(7), '6abf4a82');
  });

  test('midHash has no leading zeros', () {
    for (var uid = 0; uid < 2000; uid++) {
      final hash = MidHash.of(uid);
      expect(hash.startsWith('0'), isFalse, reason: 'uid $uid gave $hash');
    }
  });

  test('modes 7, 8 and 9 are always dropped', () {
    final elems = [for (var m = 1; m <= 9; m++) makeElem('m$m', at: m, mode: m)];
    expect(shown(elems), ['m1', 'm2', 'm3', 'm4', 'm5', 'm6']);
  });

  test('type and colour blocks', () {
    final elems = [
      makeElem('scroll', at: 1, mode: 1),
      makeElem('reverse', at: 2, mode: 6),
      makeElem('bottom', at: 3, mode: 4),
      makeElem('top', at: 4, mode: 5),
      makeElem('red', at: 5, mode: 1, color: 0xFF0000),
      makeElem('gradient', at: 6, mode: 1, colorful: 60001),
    ];
    expect(shown(elems), ['scroll', 'reverse', 'bottom', 'top', 'red', 'gradient']);
    expect(shown(elems, const DanmakuFilterOptions(blockScroll: true)), ['bottom', 'top']);
    expect(shown(elems, const DanmakuFilterOptions(blockFixed: true)), ['scroll', 'reverse', 'red', 'gradient']);
    expect(shown(elems, const DanmakuFilterOptions(hideBottom: true)), ['scroll', 'reverse', 'top', 'red', 'gradient']);
    expect(shown(elems, const DanmakuFilterOptions(blockColored: true)), ['scroll', 'reverse', 'bottom', 'top']);
    expect(shown(elems, const DanmakuFilterOptions(blockAdvanced: true)), [
      'scroll',
      'reverse',
      'bottom',
      'top',
      'red',
      'gradient',
    ]);
  });

  test('rules: keyword, regex, user, and own exempt', () {
    final elems = [
      makeElem('剧透警告', at: 1),
      makeElem('Spoiler ahead', at: 2),
      makeElem('路人甲', at: 3, midHash: 'deadbeef'),
      makeElem('普通弹幕', at: 4, midHash: '11111111'),
      makeElem('我也剧透', at: 5, midHash: 'aaaa0001'),
    ];
    const rules = [
      BlockRule(id: 1, kind: BlockRuleKind.keyword, filter: '剧透'),
      BlockRule(id: 2, kind: BlockRuleKind.regex, filter: '/spoil.*/'),
      BlockRule(id: 3, kind: BlockRuleKind.user, filter: 'deadbeef'),
      BlockRule(id: 4, kind: BlockRuleKind.regex, filter: '([unclosed'),
    ];
    const defaults = DanmakuFilterOptions();
    expect(shown(elems, defaults, rules), ['普通弹幕']);
    expect(shown(elems, defaults, rules, 'aaaa0001'), ['普通弹幕', '我也剧透']);
    expect(shown(elems, const DanmakuFilterOptions(applyRules: false), rules).length, 5);
    final result = DanmakuFilter.apply(elems, options: defaults, rules: rules, ownHash: 'aaaa0001');
    expect(result.map((d) => d.isOwn), [false, true]);
  });

  test('regex without slashes and empty rules are handled', () {
    final elems = [makeElem('abc', at: 1), makeElem('xyz', at: 2)];
    const rules = [
      BlockRule(id: 1, kind: BlockRuleKind.regex, filter: '^A'),
      BlockRule(id: 2, kind: BlockRuleKind.keyword, filter: ''),
    ];
    expect(shown(elems, const DanmakuFilterOptions(), rules), ['xyz']);
  });

  test('empty regex blocks nothing', () {
    final elems = [makeElem('abc', at: 1), makeElem('xyz', at: 2)];
    expect(
      shown(elems, const DanmakuFilterOptions(), const [BlockRule(id: 1, kind: BlockRuleKind.regex, filter: '//')]),
      ['abc', 'xyz'],
    );
  });

  test('dedupe merges within ten seconds and blockCount drops merged', () {
    final elems = [makeElem('哈哈', at: 1000), makeElem('哈哈', at: 5000), makeElem('哈哈', at: 12000)];
    expect(shown(elems, const DanmakuFilterOptions(dedupe: true)), ['哈哈 ×2', '哈哈']);
    expect(shown(elems, const DanmakuFilterOptions(blockCount: true, dedupe: true)), ['哈哈']);
    expect(shown(elems, const DanmakuFilterOptions(blockCount: true)), ['哈哈']);
    expect(shown(elems), ['哈哈', '哈哈', '哈哈']);
  });

  test('dedupe keeps the first one\'s time and counts all', () {
    final elems = [
      makeElem('666', at: 2000),
      makeElem('666', at: 4000),
      makeElem('666', at: 9000),
      makeElem('别的', at: 3000),
    ];
    final result = DanmakuFilter.apply(
      elems,
      options: const DanmakuFilterOptions(dedupe: true),
      rules: const [],
      ownHash: null,
    );
    expect(result.map((d) => d.text), ['666 ×3', '别的']);
    expect(result.map((d) => d.elem.progressMs), [2000, 3000]);
  });

  test('unsorted input comes out sorted and merges regardless', () {
    final elems = [makeElem('b', at: 3000), makeElem('a', at: 1000), makeElem('a', at: 2000)];
    final result = DanmakuFilter.apply(
      elems,
      options: const DanmakuFilterOptions(dedupe: true),
      rules: const [],
      ownHash: null,
    );
    expect(result.map((d) => d.text), ['a ×2', 'b']);
  });

  test('own danmaku is never merged away', () {
    final elems = [makeElem('哈哈', at: 1000, midHash: 'other'), makeElem('哈哈', at: 2000, midHash: 'mine')];
    final result = DanmakuFilter.apply(
      elems,
      options: const DanmakuFilterOptions(blockCount: true, dedupe: true),
      rules: const [],
      ownHash: 'mine',
    );
    expect(result.map((d) => d.text), ['哈哈', '哈哈']);
    expect(result.map((d) => d.isOwn), [false, true]);
  });

  test('options decode from older settings with missing keys', () {
    final decoded = DanmakuFilterOptions.fromJson(jsonDecode('{"dedupe":true}') as Map<String, Object?>);
    expect(decoded, const DanmakuFilterOptions(dedupe: true));
    expect(decoded.applyRules, isTrue);
    final encoded = jsonEncode(const DanmakuFilterOptions(blockFixed: true, applyRules: false).toJson());
    final round = DanmakuFilterOptions.fromJson(jsonDecode(encoded) as Map<String, Object?>);
    expect(round, const DanmakuFilterOptions(blockFixed: true, applyRules: false));
  });
}
