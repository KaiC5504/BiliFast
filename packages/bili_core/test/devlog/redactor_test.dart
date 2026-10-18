import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

void main() {
  test('secret fields are redacted', () {
    final out = Redactor.fields({'SESSDATA': 'abc', 'Cookie': 'x=y', 'node': 'upos-sz-mirrorcosov.bilivideo.com'});
    expect(out['SESSDATA'], const LogString('[redacted]'));
    expect(out['Cookie'], const LogString('[redacted]'));
    expect(out['node'], const LogString('upos-sz-mirrorcosov.bilivideo.com'));
  });

  test('signed URL keeps host, path and deadline', () {
    const url = 'https://upos-sz-mirrorcosov.bilivideo.com/upgcxcode/12/34/567/567-1-100050.m4s?e=ig8euxZM&uipk=5'
        '&deadline=1760000000&gen=playurlv2&os=cosovbv&upsig=deadbeef&mid=99887766';
    expect(
      Redactor.text('GET $url done'),
      'GET https://upos-sz-mirrorcosov.bilivideo.com/upgcxcode/12/34/567/567-1-100050.m4s?deadline=1760000000 done',
    );
  });

  test('cookie pairs in free text', () {
    expect(
      Redactor.text('Cookie: SESSDATA=abc%2C123; bili_jct=ff00; buvid3=keep'),
      'Cookie: SESSDATA=[redacted]; bili_jct=[redacted]; buvid3=[redacted]',
    );
  });

  test('authorization header in free text', () {
    expect(Redactor.text('Authorization: Bearer TOPSECRET'), 'Authorization: [redacted]');
    expect(Redactor.text('sent authorization: Basic dXNlcjpwdw== ok'), 'sent authorization: [redacted]');
    expect(Redactor.text('AUTHORIZATION: rawtoken123'), 'AUTHORIZATION: [redacted]');
    expect(Redactor.text('{"Authorization":"Bearer abc"}'), '{"Authorization":"[redacted]"}');
  });

  test('cookie and Set-Cookie headers keep names only', () {
    expect(Redactor.text('Cookie: foo=bar; buvid3=keep'), 'Cookie: foo=[redacted]; buvid3=[redacted]');
    expect(
      Redactor.text('Set-Cookie: SESSDATA=abc; Path=/; HttpOnly; Secure'),
      'Set-Cookie: SESSDATA=[redacted]; Path=[redacted]; HttpOnly; Secure',
    );
    expect(Redactor.text('set-cookie: sid=zzz'), 'set-cookie: sid=[redacted]');
  });

  test('secret field keys are matched loosely and case-insensitively', () {
    final out = Redactor.fields({
      'X-CSRF-Token': 't',
      'csrf_token': 't',
      'Set-Cookie': 'a=b',
      'AUTHORIZATION': 'Bearer x',
      'Access_Key': 'k',
      'bili_jct': 'j',
      'ok': 'fine',
    });
    for (final key in ['X-CSRF-Token', 'csrf_token', 'Set-Cookie', 'AUTHORIZATION', 'Access_Key', 'bili_jct']) {
      expect(out[key], const LogString('[redacted]'), reason: key);
    }
    expect(out['ok'], const LogString('fine'));
  });

  test('mid and DedeUserID fields are hashed', () {
    final out = Redactor.fields({'mid': 99887766, 'DedeUserID': '99887766', 'Mid': const LogString('mid:abcd1234')});
    expect(out['mid'], LogString(Redactor.mid(99887766)));
    expect(out['DedeUserID'], LogString(Redactor.mid(99887766)));
    expect(out['Mid'], const LogString('mid:abcd1234'));
    expect(out.toString(), isNot(contains('99887766')));
  });

  test('CSRF pairs anywhere in free text', () {
    expect(Redactor.text('x-csrf-token=abc bili_jct=ff'), 'x-csrf-token=[redacted] bili_jct=[redacted]');
    expect(Redactor.text('body csrf_token=abc&csrf=def end'), 'body csrf_token=[redacted]&csrf=[redacted] end');
    expect(Redactor.text('X-CSRF-Token: abc123'), 'X-CSRF-Token: [redacted]');
  });

  test('URL regex keeps trailing punctuation', () {
    const signed = 'https://h.bilivideo.com/p/a.m4s?deadline=1&upsig=S';
    const kept = 'https://h.bilivideo.com/p/a.m4s?deadline=1';
    expect(Redactor.text('($signed), then $signed.'), '($kept), then $kept.');
    expect(Redactor.text('a $signed; b $signed"c'), 'a $kept; b $kept"c');
  });

  test('named secrets in colon, JSON and dictionary forms', () {
    const cases = [
      (r'{"SESSDATA":"abc123","bili_jct":"ff00"}', r'{"SESSDATA":"[redacted]","bili_jct":"[redacted]"}'),
      (r'["SESSDATA": "abc123"]', r'["SESSDATA": "[redacted]"]'),
      (
        '<NSHTTPCookie version:0 name:SESSDATA value:abc123 domain:.bilibili.com>',
        '<NSHTTPCookie version:0 name:SESSDATA value:[redacted] domain:.bilibili.com>',
      ),
      (r'{"name":"SESSDATA","value":"abc123"}', r'{"name":"SESSDATA","value":"[redacted]"}'),
      ('access_token=zzz refresh_token: qqq', 'access_token=[redacted] refresh_token: [redacted]'),
      ('password=hunter2', 'password=[redacted]'),
      (r'{"password":"hunter 2","ok":"fine"}', r'{"password":"[redacted]","ok":"fine"}'),
      (r'{\"SESSDATA\":\"abc\"}', r'{\"SESSDATA\":\"[redacted]\"}'),
      ('DedeUserID__ckMd5: 0a1b2c', 'DedeUserID__ckMd5: [redacted]'),
    ];
    for (final (input, expected) in cases) {
      expect(Redactor.text(input), expected, reason: input);
    }
  });

  test('bare bearer token', () {
    expect(Redactor.text('Bearer eyJhbGciOi.abc.def'), 'Bearer [redacted]');
    expect(Redactor.text('got bearer abcdefgh12 back'), 'got bearer [redacted] back');
  });

  test('JSON-escaped URL is shortened like any other', () {
    expect(
      Redactor.text(r'https:\/\/upos-sz.bilivideo.com\/a.m4s?deadline=1&upsig=SECRET'),
      'https://upos-sz.bilivideo.com/a.m4s?deadline=1',
    );
    expect(
      Redactor.text('https://upos-sz.bilivideo.com/a.m4s?deadline=1&upsig=SECRET'),
      'https://upos-sz.bilivideo.com/a.m4s?deadline=1',
    );
  });

  test('benign text is left alone', () {
    const text = 'tokens: 5 speed=10 node=upos-sz buvid3 name:foo value:bar';
    expect(Redactor.text(text), text);
  });

  test('field keys containing secret fragments are redacted', () {
    const keys = [
      'my_SESSDATA',
      'userCookie',
      'AuthorizationHeader',
      'api_token',
      'Password',
      'bili_jct2',
      'x-access_key',
      'refresh_token',
      'DedeUserID__ckMd5',
    ];
    final out = Redactor.fields({for (final key in keys) key: 'v'});
    for (final key in keys) {
      expect(out[key], const LogString('[redacted]'), reason: key);
    }
  });

  test('regex prefixes are bounded against long input', () {
    final long = 'a-' * 20000;
    final watch = Stopwatch()..start();
    Redactor.text('${long}csrf');
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('unparseable URL never keeps its query', () {
    expect(Redactor.url('not a url?upsig=S#f'), 'not a url');
  });

  test('URL without deadline loses its query', () {
    expect(Redactor.text('https://api.bilibili.com/x?csrf=abc&access_key=zzz#f'), 'https://api.bilibili.com/x');
  });

  test('sign is redacted but words containing sign are not', () {
    final line = Redactor.text('appkey=k&sign=abc123&design=ok');
    expect(line, isNot(contains('abc123')));
    expect(line, contains('design=ok'));
    expect(Redactor.text('Sign: abc'), 'Sign: [redacted]');
    expect(Redactor.text('resign=1 assign=2'), 'resign=1 assign=2');
    final out = Redactor.fields({'sign': 'abc', 'Sign': 'abc', 'design': 'keep'});
    expect(out['sign'], const LogString('[redacted]'));
    expect(out['Sign'], const LogString('[redacted]'));
    expect(out['design'], const LogString('keep'));
  });

  test('signed URL query is dropped wholesale', () {
    expect(Redactor.text('https://app.bilibili.com/x?appkey=k&sign=abc123&design=ok'), 'https://app.bilibili.com/x');
  });

  test('protocol-relative signed URL keeps host, path and deadline', () {
    const url = '//upos-sz-mirrorcos.bilivideo.com/upgcxcode/12/34/567/567-1-100050.m4s?e=ig8euxZM&uipk=5'
        '&deadline=1760000000&gen=playurlv2&os=cosbv&auth_key=1760000000-0-0-deadbeef&mid=99887766';
    const kept = '//upos-sz-mirrorcos.bilivideo.com/upgcxcode/12/34/567/567-1-100050.m4s?deadline=1760000000';
    expect(Redactor.text('GET $url done'), 'GET $kept done');
    expect(Redactor.text('url=$url'), 'url=$kept');
    expect(Redactor.url(url), kept);
  });

  test('protocol-relative URLs in JSON and prose lose their query', () {
    expect(
      Redactor.text(
        r'{"baseUrl":"//upos-sz.bilivideo.com/a.m4s?auth_key=SECRET",'
        r'"backupUrl":["\/\/upos-hz.bilivideo.com\/a.m4s?upsig=SECRET&deadline=1"]}',
      ),
      r'{"baseUrl":"//upos-sz.bilivideo.com/a.m4s","backupUrl":["//upos-hz.bilivideo.com/a.m4s?deadline=1"]}',
    );
    expect(
      Redactor.text('(//h.bilivideo.com/p/a.m4s?auth_key=S), then //h.bilivideo.com/p?x#f.'),
      '(//h.bilivideo.com/p/a.m4s), then //h.bilivideo.com/p.',
    );
  });

  test('double slashes that are not protocol-relative URLs are left alone', () {
    const text = 'a//b?c=1 10//2?x=y // note';
    expect(Redactor.text(text), text);
  });

  test('signed media URL secrets are redacted as pairs and fields; uparams only names them', () {
    expect(
      Redactor.text('auth_key=1760000000-0-0-abc upsig=deadbeef&hdnts=exp=1760000000~acl=/*~hmac=ff00'),
      'auth_key=[redacted] upsig=[redacted]&hdnts=[redacted]',
    );
    expect(Redactor.text(r'{"auth_key":"1760000000-0-0-abc"}'), r'{"auth_key":"[redacted]"}');
    const names = 'uparams=e,uipk,nbs,deadline,gen,os,oi,trid,mid,platform';
    expect(Redactor.text(names), names);
    final out = Redactor.fields({'auth_key': 'a', 'upsig': 'u', 'hdnts': 'h', 'uparams': 'e,deadline'});
    for (final key in ['auth_key', 'upsig', 'hdnts']) {
      expect(out[key], const LogString('[redacted]'), reason: key);
    }
    expect(out['uparams'], const LogString('e,deadline'));
  });

  test('mid hash', () {
    expect(Redactor.mid(12345), Redactor.mid(12345));
    expect(Redactor.mid(12345), isNot(contains('12345')));
    expect(Redactor.mid(12345), startsWith('mid:'));
  });

  // Not in the Swift suite: pins the FNV-1a output so Dart and Swift hash a mid the same way.
  test('mid hash matches the Swift FNV-1a values', () {
    expect(Redactor.mid(12345), 'mid:e575e888');
    expect(Redactor.mid(99887766), 'mid:1d271581');
    expect(Redactor.mid(0), 'mid:af63ad4c');
  });
}
