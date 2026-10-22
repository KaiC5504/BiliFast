import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bili_core/api.dart';
import 'package:bilifast/skin/skin.dart';
import 'package:bilifast/skin/skin_api.dart';
import 'package:bilifast/skin/skin_package.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List zipOf(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final MapEntry(key: name, value: bytes) in entries.entries) {
    archive.add(ArchiveFile.bytes(name, bytes));
  }
  // Without a time every entry is stamped now, so the same package built a second later has another md5.
  return ZipEncoder().encodeBytes(archive, modified: DateTime(2026, 10, 22));
}

String md5Of(List<int> bytes) => md5.convert(bytes).toString();

const _equip = SkinEquip(id: 7, name: 'test', ver: 1, packageUrl: '', packageMd5: '');

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('skin_package_test');
    addTearDown(() => root.delete(recursive: true));
  });

  String folder([String name = 'out']) => '${root.path}/$name';

  Future<List<SkinFile>> unpackAndList(Map<String, List<int>> entries) async {
    final zip = zipOf(entries);
    await unpackSkinPackage(zip, md5: md5Of(zip), folder: folder());
    return listSkinFiles(Directory(folder()));
  }

  group('the package host', () {
    test('is https on hdslb.com, biliimg.com or bilibili.com, subdomains included', () {
      for (final url in [
        'https://i0.hdslb.com/bfs/garb/zip/a.zip',
        'https://hdslb.com/a.zip',
        'https://i1.biliimg.com/a.zip',
        'https://www.bilibili.com/a.zip',
        'https://I0.HDSLB.COM/a.zip',
        'https://i0.hdslb.com:443/a.zip',
      ]) {
        expect(isSkinPackageUrl(Uri.parse(url)), isTrue, reason: url);
      }
    });

    test('refuses plain http, look-alike hosts, other ports and user info', () {
      for (final url in [
        'http://i0.hdslb.com/a.zip',
        'https://evilhdslb.com/a.zip',
        'https://hdslb.com.example.com/a.zip',
        'https://example.com/i0.hdslb.com/a.zip',
        'https://i0.hdslb.com:8443/a.zip',
        'https://user@i0.hdslb.com/a.zip',
        'file:///i0.hdslb.com/a.zip',
        'https:///a.zip',
      ]) {
        expect(isSkinPackageUrl(Uri.parse(url)), isFalse, reason: url);
      }
    });

    test('a refused host is never asked: no client is made', () async {
      var clients = 0;
      final api = ClientSkinApi(
        BiliClient(transport: _NoTransport(), cookies: CookieJar({})),
        http: () {
          clients++;
          throw StateError('no network in tests');
        },
      );
      await expectLater(
        api.download(Uri.parse('https://example.com/a.zip')),
        throwsA(
          isA<SkinPackageError>().having(
            (error) => error.reason,
            'reason',
            'package host not allowed: https://example.com',
          ),
        ),
      );
      expect(clients, 0);
    });

    test('a refusal names the scheme and host, and a port given, but no path, query or user info', () {
      String reason(String url) => SkinPackageError.hostNotAllowed(Uri.parse(url)).reason;
      expect(reason('http://i0.hdslb.com/bfs/garb/a.zip?sign=secret'), 'package host not allowed: http://i0.hdslb.com');
      expect(reason('https://i0.hdslb.com:8443/a.zip'), 'package host not allowed: https://i0.hdslb.com:8443');
      expect(
        reason('https://user:secret@i0.hdslb.com/a.zip'),
        'package host not allowed: https://i0.hdslb.com with user info',
      );
      expect(reason('file:///i0.hdslb.com/a.zip'), 'package host not allowed: file://');
      expect(reason('https://${'a' * 100}.com/a.zip'), 'package host not allowed: https://${'a' * 80}…');
    });
  });

  group('the download', () {
    test('is capped at 40 MB, entries at 20 MB', () {
      expect(SkinLimits.packageBytes, 40 * 1024 * 1024);
      expect(SkinLimits.entryBytes, 20 * 1024 * 1024);
    });

    test('a declared length past the cap is refused before reading', () async {
      var listened = false;
      final body = Stream<List<int>>.multi((controller) => listened = true);
      await expectLater(readCapped(body, declaredLength: 11, cap: 10), throwsA(isA<SkinPackageError>()));
      expect(listened, isFalse);
    });

    test('a body that grows past the cap stops there, whatever it declared', () async {
      var cancelled = false;
      final controller = StreamController<List<int>>(onCancel: () => cancelled = true);
      final read = readCapped(controller.stream, cap: 10);
      controller
        ..add(List.filled(6, 1))
        ..add(List.filled(6, 2));
      await expectLater(read, throwsA(isA<SkinPackageError>()));
      expect(cancelled, isTrue);
    });

    test('within the cap, the bytes in order', () async {
      final body = Stream<List<int>>.fromIterable([
        [1, 2],
        [3],
        [4, 5],
      ]);
      expect(await readCapped(body, cap: 5), [1, 2, 3, 4, 5]);
    });

    test('goes plain, with the browser\'s user agent, and follows a redirect to another CDN host', () async {
      final client = _Client({
        'https://i0.hdslb.com/a.zip': const _Answer(302, location: 'https://i1.hdslb.com/b.zip'),
        'https://i1.hdslb.com/b.zip': const _Answer(200, body: [1, 2, 3]),
      });
      expect(await downloadSkinPackage(Uri.parse('https://i0.hdslb.com/a.zip'), client: () => client), [1, 2, 3]);
      expect(client.asked, ['https://i0.hdslb.com/a.zip', 'https://i1.hdslb.com/b.zip']);
      expect(client.requests.every((request) => !request.followRedirects && request.headersTouched == 0), isTrue);
      expect(client.userAgent, BiliClient.userAgent);
      expect(client.closed, isTrue);
    });

    test('a redirect off the allowed hosts is never followed', () async {
      final client = _Client({'https://i0.hdslb.com/a.zip': const _Answer(302, location: 'https://example.com/a.zip')});
      await expectLater(
        downloadSkinPackage(Uri.parse('https://i0.hdslb.com/a.zip'), client: () => client),
        throwsA(
          isA<SkinPackageError>().having(
            (error) => error.reason,
            'reason',
            'package host not allowed: https://example.com',
          ),
        ),
      );
      expect(client.asked, ['https://i0.hdslb.com/a.zip']);
      expect(client.closed, isTrue);
    });

    test('an answer other than 200, or redirects without end, are refused for the run', () async {
      final missing = _Client({'https://i0.hdslb.com/a.zip': const _Answer(404)});
      await expectLater(
        downloadSkinPackage(Uri.parse('https://i0.hdslb.com/a.zip'), client: () => missing),
        throwsA(
          isA<SkinPackageError>()
              .having((error) => error.reason, 'reason', 'download answered 404')
              .having((error) => error.passing, 'passing', isFalse),
        ),
      );

      final loop = _Client({'https://i0.hdslb.com/a.zip': const _Answer(301, location: '/a.zip')});
      await expectLater(
        downloadSkinPackage(Uri.parse('https://i0.hdslb.com/a.zip'), client: () => loop),
        throwsA(isA<SkinPackageError>().having((error) => error.reason, 'reason', 'too many redirects')),
      );
      expect(loop.asked, hasLength(4));
    });

    test('a download that never ends times out, which may pass', () async {
      final client = _Client({'https://i0.hdslb.com/a.zip': const _Answer(200, endless: true)});
      await expectLater(
        downloadSkinPackage(
          Uri.parse('https://i0.hdslb.com/a.zip'),
          client: () => client,
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(
          isA<SkinPackageError>()
              .having((error) => error.reason, 'reason', 'download timed out')
              .having((error) => error.passing, 'passing', isTrue),
        ),
      );
      expect(client.closed, isTrue);
    });
  });

  group('unpacking', () {
    test('checks the md5 in either case before writing anything', () async {
      final zip = zipOf({
        'head_bg.png': [1, 2, 3],
      });
      await expectLater(
        unpackSkinPackage(zip, md5: md5Of([9]), folder: folder()),
        throwsA(isA<SkinPackageError>().having((error) => error.reason, 'reason', 'md5 mismatch')),
      );
      expect(Directory(folder()).existsSync(), isFalse);

      final unpacked = await unpackSkinPackage(zip, md5: md5Of(zip).toUpperCase(), folder: folder());
      expect(unpacked.written, ['head_bg.png']);
      expect(File('${folder()}/head_bg.png').readAsBytesSync(), [1, 2, 3]);
    });

    test('writes only flat names: paths, parents, drives, hidden names and links are skipped', () async {
      final zip = zipOf({
        '../escape.png': [1],
        '../../escape2.png': [1],
        'dir/nested.png': [1],
        '/absolute.png': [1],
        r'C:\windows.png': [1],
        r'back\slash.png': [1],
        'c:drive.png': [1],
        '..': [1],
        '.hidden': [1],
        '.skin.json': [1],
        'tail_bg.webp': [2],
      });
      final unpacked = await unpackSkinPackage(zip, md5: md5Of(zip), folder: folder());
      expect(unpacked.written, ['tail_bg.webp']);
      expect(unpacked.skipped, hasLength(10));
      expect(root.listSync().map((entity) => entity.path.split(RegExp(r'[\\/]')).last), ['out']);
      expect(Directory(folder()).listSync().map((entity) => entity.path.split(RegExp(r'[\\/]')).last), [
        'tail_bg.webp',
      ]);
    });

    test('skips an entry past the entry cap, and refuses a package past the unpacked cap', () async {
      final zip = zipOf({'head_bg.png': List.filled(100, 1), 'tail_bg.png': List.filled(101, 2)});
      final unpacked = await unpackSkinPackage(zip, md5: md5Of(zip), folder: folder(), entryBytes: 100);
      expect(unpacked.written, ['head_bg.png']);
      expect(unpacked.skipped, ['tail_bg.png: too large']);

      await expectLater(
        unpackSkinPackage(zip, md5: md5Of(zip), folder: folder('second'), unpackedBytes: 150),
        throwsA(isA<SkinPackageError>().having((error) => error.reason, 'reason', 'package unpacks too large')),
      );
    });

    test('a download that is not a zip is refused', () async {
      final bytes = Uint8List.fromList(List.filled(64, 7));
      await expectLater(
        unpackSkinPackage(bytes, md5: md5Of(bytes), folder: folder()),
        throwsA(isA<SkinPackageError>().having((error) => error.reason, 'reason', 'not a zip')),
      );
    });
  });

  group('resolving', () {
    test('finds each role by its name without the extension, among the kinds it can draw', () async {
      final skipped = <String>[];
      final skin = resolveSkin(
        _equip,
        await unpackAndList({
          'head_bg.webp': [1],
          'head_tab_bg.jpg': [1],
          'head_myself_mp4_bg.mp4': [1],
          'tail_bg.png': [1],
          for (final tab in SkinNames.tabs) ...{
            'tail_icon_$tab.png': [1],
            'tail_icon_selected_$tab.svga': [1],
          },
          'tail_icon_pub_btn_bg.png': [1],
          'tail_icon_selected_pub_btn_bg.jpeg': [1],
          'something_else.png': [1],
        }),
        skipped: skipped,
      );
      expect(skipped, isEmpty);
      expect(skin.headBg!.path, endsWith('head_bg.webp'));
      expect(skin.headTabBg!.path, endsWith('head_tab_bg.jpg'));
      expect(skin.headMyselfVideo!.path, endsWith('head_myself_mp4_bg.mp4'));
      expect(skin.tailBg!.path, endsWith('tail_bg.png'));
      expect(skin.tailIcons.map((icon) => icon.file.path.split(RegExp(r'[\\/]')).last), [
        'tail_icon_main.png',
        'tail_icon_channel.png',
        'tail_icon_dynamic.png',
        'tail_icon_shop.png',
        'tail_icon_myself.png',
      ]);
      expect(skin.tailIcons.every((icon) => !icon.animated), isTrue);
      expect(skin.tailIconsSelected, hasLength(5));
      expect(skin.tailIconsSelected.every((icon) => icon.animated), isTrue, reason: '.svga plays');
      expect(skin.pubButton!.animated, isFalse);
      expect(skin.pubButtonSelected!.file.path, endsWith('tail_icon_selected_pub_btn_bg.jpeg'));
      expect(skin.files.keys, contains('something_else'));
      expect(skin.headMyself, isNull);
    });

    test('gives pictures to picture roles, svga only to the selected icons, mp4 or mov to the video', () async {
      final skipped = <String>[];
      final skin = resolveSkin(
        _equip,
        await unpackAndList({
          'head_bg.gif': [1],
          'head_bg.png': [1],
          'head_tab_bg.svga': [1],
          'head_myself_squared_bg.mp4': [1],
          'head_myself_bg.WEBP': [1],
          'head_myself_mp4_bg.png': [1],
          'head_myself_mp4_bg.MOV': [1],
          'tail_bg.svga': [1],
          for (final tab in SkinNames.tabs) ...{
            'tail_icon_$tab.svga': [1],
            'tail_icon_selected_$tab.webp': [1],
          },
          'tail_icon_pub_btn_bg.svga': [1],
          'tail_icon_selected_pub_btn_bg.svga': [1],
        }),
        skipped: skipped,
      );
      expect(skin.headBg!.path, endsWith('head_bg.png'));
      expect(skin.headTabBg, isNull);
      expect(skin.headMyself!.path, endsWith('head_myself_bg.WEBP'), reason: 'the squared one is a video');
      expect(skin.headMyselfVideo!.path, endsWith('head_myself_mp4_bg.MOV'));
      expect(skin.tailBg, isNull);
      expect(skin.tailIcons, isEmpty, reason: 'still icons only');
      expect(skin.tailIconsSelected, hasLength(5));
      expect(skin.tailIconsSelected.every((icon) => !icon.animated), isTrue);
      expect(skin.pubButton, isNull);
      expect(skin.pubButtonSelected, isNull);
      expect(
        skipped,
        unorderedEquals([
          'head_bg.gif: not a picture',
          'head_tab_bg.svga: not a picture',
          'head_myself_squared_bg.mp4: not a picture',
          'head_myself_mp4_bg.png: not a video',
          'tail_bg.svga: not a picture',
          for (final tab in SkinNames.tabs) 'tail_icon_$tab.svga: not a picture',
          'tail_icon_pub_btn_bg.svga: not a picture',
          'tail_icon_selected_pub_btn_bg.svga: not a picture',
        ]),
      );

      final selectedVideo = resolveSkin(_equip, [
        for (final tab in SkinNames.tabs) SkinFile(File('${folder()}/tail_icon_selected_$tab.mp4'), 1),
      ], skipped: skipped..clear());
      expect(selectedVideo.tailIconsSelected, isEmpty);
      expect(skipped.first, 'tail_icon_selected_main.mp4: not a picture or svga');
    });

    test('takes head_myself_squared_bg over head_myself_bg, and head_myself_bg alone', () async {
      final both = resolveSkin(
        _equip,
        await unpackAndList({
          'head_myself_bg.png': [1],
          'head_myself_squared_bg.webp': [2],
        }),
      );
      expect(both.headMyself!.path, endsWith('head_myself_squared_bg.webp'));

      final alone = resolveSkin(_equip, [SkinFile(File('${folder()}/head_myself_bg.png'), 1)]);
      expect(alone.headMyself!.path, endsWith('head_myself_bg.png'));
    });

    test('two files sharing a name: the first in name order', () async {
      final skin = resolveSkin(
        _equip,
        await unpackAndList({
          'head_bg.webp': [1],
          'head_bg.png': [2],
        }),
      );
      expect(skin.headBg!.path, endsWith('head_bg.png'));
    });

    test('an icon set missing one of its five, or a missing tail colour, leaves the bar stock', () async {
      final files = await unpackAndList({
        'tail_bg.png': [1],
        for (final tab in SkinNames.tabs) 'tail_icon_$tab.png': [1],
        for (final tab in SkinNames.tabs.skip(1)) 'tail_icon_selected_$tab.png': [1],
      });
      const colors = SkinColors(tailColor: 0xFF000001, tailColorSelected: 0xFF000002);
      const equip = SkinEquip(id: 7, name: 'test', ver: 1, packageUrl: '', packageMd5: '', colors: colors);
      final skin = resolveSkin(equip, files);
      expect(skin.tailIcons, hasLength(5));
      expect(skin.tailIconsSelected, isEmpty);
      expect(skin.themesBar, isFalse);
      expect(skinBarGaps(skin), ['selected tail icons']);

      File('${folder()}/tail_icon_selected_main.png').writeAsBytesSync([1]);
      final whole = resolveSkin(equip, await listSkinFiles(Directory(folder())));
      expect(whole.themesBar, isTrue);
      expect(skinBarGaps(whole), isEmpty);
      expect(skinBarGaps(resolveSkin(_equip, await listSkinFiles(Directory(folder())))), [
        'tail color',
        'selected tail color',
      ]);
    });

    test('the bar\'s gaps name a missing tail_bg and a set short of five, whatever the colours', () {
      const colors = SkinColors(tailColor: 0xFF000001, tailColorSelected: 0xFF000002);
      const equip = SkinEquip(id: 7, name: 'test', ver: 1, packageUrl: '', packageMd5: '', colors: colors);
      final icon = SkinIcon(File('${folder()}/icon.png'));
      final five = List.filled(SkinNames.tabs.length, icon);
      expect(skinBarGaps(Skin(equip: equip, tailIcons: five, tailIconsSelected: five)), ['tail bg']);
      expect(
        skinBarGaps(
          Skin(
            equip: equip,
            tailBg: File('${folder()}/tail_bg.png'),
            tailIcons: five.sublist(1),
            tailIconsSelected: [icon],
          ),
        ),
        ['tail icons', 'selected tail icons'],
      );
      expect(skinBarGaps(Skin(equip: _equip)), [
        'tail bg',
        'tail icons',
        'selected tail icons',
        'tail color',
        'selected tail color',
      ]);
    });

    test('the folder listing leaves the bookkeeping out and gives sizes', () async {
      Directory(folder()).createSync();
      File('${folder()}/.skin.json').writeAsStringSync('{}');
      File('${folder()}/tail_bg.png').writeAsBytesSync([1, 2, 3, 4]);
      final files = await listSkinFiles(Directory(folder()));
      expect(files.map((file) => (file.name, file.stem, file.extension, file.size)), [
        ('tail_bg.png', 'tail_bg', 'png', 4),
      ]);
    });
  });
}

class _Answer {
  const _Answer(this.status, {this.location, this.body = const [], this.endless = false});

  final int status;
  final String? location;
  final List<int> body;

  /// The body never finishes.
  final bool endless;
}

/// dart:io's client with made-up answers by URL; nothing leaves the machine.
class _Client implements HttpClient {
  _Client(this.answers);

  final Map<String, _Answer> answers;
  final asked = <String>[];
  final requests = <_Request>[];
  bool closed = false;

  @override
  Duration? connectionTimeout;

  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    asked.add('$url');
    final request = _Request(answers['$url'] ?? (throw StateError('no answer for $url')));
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.answer);

  final _Answer answer;
  int headersTouched = 0;

  @override
  bool followRedirects = true;

  @override
  HttpHeaders get headers {
    headersTouched++;
    return _Headers(null);
  }

  @override
  Future<HttpClientResponse> close() async => _Response(answer);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.answer);

  final _Answer answer;

  @override
  int get statusCode => answer.status;

  @override
  bool get isRedirect => const [301, 302, 303, 307, 308].contains(answer.status);

  @override
  int get contentLength => answer.endless ? -1 : answer.body.length;

  @override
  HttpHeaders get headers => _Headers(answer.location);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final body = answer.endless ? StreamController<List<int>>().stream : Stream.value(answer.body);
    return body.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  _Headers(this.location);

  final String? location;

  @override
  String? value(String name) => name == HttpHeaders.locationHeader ? location : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoTransport implements HTTPTransport {
  @override
  Future<HTTPResponse> send(HTTPRequest request) => throw StateError('no network in tests');
}
