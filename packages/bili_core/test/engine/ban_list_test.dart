import 'package:bili_core/src/engine/ban_list.dart';
import 'package:test/test.dart';

String _url(String node, String file) => 'https://$node.bilivideo.com/upgcxcode/$file.m4s?deadline=1';

void main() {
  test('two silent failures ban the node', () {
    final bans = BanList();
    expect(bans.record(_url('a', 'f1'), receivedBytes: 0), isFalse);
    expect(bans.record(_url('a', 'f1'), receivedBytes: 0), isTrue);
    expect(bans.allows(_url('a', 'f2')), isFalse);
    expect(bans.bannedNodes(), ['a.bilivideo.com']);
  });

  // Two Akamai requests lost their connection 2 ms apart and banned the fastest node for the rest of the video
  // (phone, 2026-10-17).
  test('connections lost at the same moment are one strike', () {
    final bans = BanList();
    final a = _url('a', 'f1');
    final b = _url('b', 'f1');
    bans
      ..record(a, receivedBytes: 0, lostAt: 1000)
      ..record(a, receivedBytes: 0, lostAt: 1002)
      ..record(b, receivedBytes: 0, lostAt: 1100);
    expect(bans.allows(a), isTrue);
    expect(bans.allows(b), isTrue, reason: "lost at the same moment as a's");
    bans.record(a, receivedBytes: 0, lostAt: 1600);
    expect(bans.allows(a), isFalse, reason: "the next round's loss is a second event");
    expect(bans.allows(b), isTrue);
  });

  test('the moment does not stretch while losses keep coming', () {
    final bans = BanList();
    final a = _url('a', 'f1');
    for (var lostAt = 1000.0; lostAt <= 1300; lostAt += 100) {
      bans.record(a, receivedBytes: 0, lostAt: lostAt);
    }
    expect(bans.allows(a), isFalse, reason: 'losses at 1000 and 1300 ms are two moments');
  });

  test('partial transfers are not strikes', () {
    final bans = BanList()
      ..record(_url('a', 'f1'), receivedBytes: 10)
      ..record(_url('a', 'f1'), receivedBytes: 10);
    expect(bans.allows(_url('a', 'f1')), isTrue);
  });

  test('a refusal by a good node blames the address', () {
    final bans = BanList()
      ..success(_url('a', 'f1'))
      ..record(_url('a', 'f2'), receivedBytes: 0, status: 403)
      ..record(_url('a', 'f2'), receivedBytes: 0, status: 403);
    expect(bans.allows(_url('b', 'f2')), isFalse);
    expect(bans.allows(_url('a', 'f1')), isTrue);
  });

  test('a refusal of a good address by a good node blames only the pair', () {
    final kinds = <BanKind>[];
    final bans = BanList()..onBan = (_, _, kind) => kinds.add(kind);
    bans
      ..success(_url('a', 'f1'))
      ..success(_url('b', 'f2'))
      ..record(_url('a', 'f2'), receivedBytes: 0, status: 403)
      ..record(_url('a', 'f2'), receivedBytes: 0, status: 403);
    expect(bans.allows(_url('a', 'f2')), isFalse);
    expect(bans.allows(_url('b', 'f2')), isTrue);
    expect(bans.allows(_url('a', 'f1')), isTrue);
    expect(kinds, [BanKind.pair]);
  });

  test('a success lifts a ban caused by silent failures', () {
    final bans = BanList()
      ..record(_url('a', 'f1'), receivedBytes: 0)
      ..record(_url('a', 'f1'), receivedBytes: 0);
    expect(bans.allowsNode(_url('a', 'f2')), isFalse);
    bans.success(_url('a', 'f2'));
    expect(bans.allowsNode(_url('a', 'f2')), isTrue);
    expect(bans.allows(_url('a', 'f1')), isTrue);
    expect(bans.bannedNodes(), isEmpty);
  });

  test('a success keeps an address ban from refusals', () {
    final bans = BanList()
      ..success(_url('a', 'f1'))
      ..record(_url('a', 'f2'), receivedBytes: 0, status: 403)
      ..record(_url('a', 'f2'), receivedBytes: 0, status: 403);
    expect(bans.allowsAddress(_url('b', 'f2')), isFalse);
    bans.success(_url('a', 'f3'));
    expect(bans.allowsAddress(_url('b', 'f2')), isFalse);
    expect(bans.allows(_url('a', 'f2')), isFalse);
    expect(bans.allows(_url('a', 'f3')), isTrue);
  });

  test('a re-ban after healing is reported again', () {
    final reported = <String>[];
    final bans = BanList()
      ..onBan = (node, _, kind) {
        if (kind == BanKind.node) reported.add(node);
      };
    bans
      ..record(_url('a', 'f1'), receivedBytes: 0)
      ..record(_url('a', 'f1'), receivedBytes: 0)
      ..success(_url('a', 'f1'))
      ..record(_url('a', 'f1'), receivedBytes: 0);
    expect(bans.allowsNode(_url('a', 'f1')), isTrue);
    bans.record(_url('a', 'f1'), receivedBytes: 0);
    expect(bans.allowsNode(_url('a', 'f1')), isFalse);
    expect(reported, ['a.bilivideo.com', 'a.bilivideo.com']);
  });

  test('a refusal counts against nobody until something delivers', () {
    final bans = BanList()
      ..record(_url('a', 'f1'), receivedBytes: 0, status: 403)
      ..record(_url('a', 'f1'), receivedBytes: 0, status: 403);
    expect(bans.allows(_url('a', 'f1')), isTrue);
    bans.success(_url('b', 'f1'));
    expect(bans.allows(_url('a', 'f1')), isFalse);
    bans.reset();
    expect(bans.allows(_url('a', 'f1')), isTrue);
  });

  test('a refusal by a node that has not delivered drops only the pair', () {
    final reports = <String>[];
    final bans = BanList()..onBan = (node, strikes, kind) => reports.add('$node $strikes ${kind.name}');
    bans
      ..record(_url('a', 'f1'), receivedBytes: 0, status: 403)
      ..success(_url('b', 'f1'))
      ..record(_url('a', 'f1'), receivedBytes: 0, status: 403);
    expect(bans.allows(_url('a', 'f1')), isFalse);
    expect(bans.allowsNode(_url('a', 'f2')), isTrue);
    expect(bans.allows(_url('a', 'f2')), isTrue);
    expect(bans.allowsAddress(_url('b', 'f1')), isTrue);
    expect(reports, ['a.bilivideo.com 2 pair'], reason: 'the pair is reported against the refusing node');
    bans.success(_url('a', 'f2'));
    expect(bans.allows(_url('a', 'f1')), isFalse);
    expect(bans.allows(_url('a', 'f2')), isTrue);
  });

  // One list serves both tracks, and a new signature is a new address: the video and audio files, before
  // and after a refresh, are four addresses Akamai refuses with `os=cosovbv` while it serves `os=akam`.
  test('refusing many served addresses never bans the node', () {
    String akamai(String file, String os, {int deadline = 9}) =>
        'https://upos-hz-mirrorakam.akamaized.net/upgcxcode/$file.m4s?deadline=$deadline&os=$os';
    String mirror(String file, String os, {int deadline = 9}) =>
        akamai(file, os, deadline: deadline).replaceAll('upos-hz-mirrorakam.akamaized.net', 'b.bilivideo.com');
    final bans = BanList();
    for (final deadline in [9, 99]) {
      for (final file in ['video', 'audio']) {
        bans
          ..success(mirror(file, 'cosovbv', deadline: deadline))
          ..record(akamai(file, 'cosovbv', deadline: deadline), receivedBytes: 0, status: 403)
          ..record(akamai(file, 'cosovbv', deadline: deadline), receivedBytes: 0, status: 403);
        expect(bans.allows(akamai(file, 'cosovbv', deadline: deadline)), isFalse);
      }
    }
    expect(bans.allowsNode(akamai('video', 'akam')), isTrue);
    expect(bans.allows(akamai('video', 'akam')), isTrue);
    expect(bans.allows(akamai('audio', 'akam')), isTrue);
    expect(bans.bannedNodes(), isEmpty);
  });
}
