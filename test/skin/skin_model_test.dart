import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/skin/fake_skin_api.dart';
import 'package:bilifast/skin/skin.dart';
import 'package:bilifast/skin/skin_model.dart';
import 'package:bilifast/skin/skin_package.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The account half [SkinModel] follows: the test sets the account and counts the logins.
class _Environment extends ChangeNotifier implements AppEnvironment {
  _Environment(this._account);

  Account _account;

  @override
  Account get account => _account;

  set account(Account value) {
    _account = value;
    notifyListeners();
  }

  @override
  final _Logins logins = _Logins();

  /// How many listeners were added, so a model can be shown to listen to nothing before it starts.
  int listening = 0;

  @override
  void addListener(VoidCallback listener) {
    listening++;
    super.addListener(listener);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Logins extends ValueNotifier<int> {
  _Logins() : super(0);

  int listening = 0;

  @override
  void addListener(VoidCallback listener) {
    listening++;
    super.addListener(listener);
  }
}

/// A stand-in as other pages' tests make one: a fixed value, a refresh that asks nothing.
class _FixedSkinModel extends SkinModel {
  _FixedSkinModel(this._skin, {required super.environment}) : super(api: FakeSkinApi(), folder: null);

  Skin? _skin;
  int refreshes = 0;

  @override
  Skin? get value => _skin;

  set skin(Skin? skin) {
    _skin = skin;
    notifyListeners();
  }

  @override
  Future<void> refresh() async => refreshes++;
}

/// A transport error whose words end with the request's URL, as dart:io's do.
class _TransportError implements Exception {
  @override
  String toString() => 'HttpException: Connection closed, uri = https://i0.hdslb.com/bfs/garb/secret.zip';
}

const loggedIn = LoggedIn(name: 'test', vip: false);
const packageUrl = 'https://i0.hdslb.com/bfs/garb/zip/7.zip';
const colors = SkinColors(color: 0xFFFFFFFF, lightText: true, tailColor: 0xFF101010, tailColorSelected: 0xFFFF0000);

Uint8List zipOf(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final MapEntry(key: name, value: bytes) in entries.entries) {
    archive.add(ArchiveFile.bytes(name, bytes));
  }
  return ZipEncoder().encodeBytes(archive);
}

/// A package with every picture role, its bytes telling [ver] apart.
Uint8List packageFor(int ver) => zipOf({
  'head_bg.png': [1, ver],
  'head_tab_bg.png': [2, ver],
  'head_myself_bg.png': [3, ver],
  'tail_bg.webp': [4, ver],
  for (final tab in SkinNames.tabs) ...{
    'tail_icon_$tab.png': [5, ver],
    'tail_icon_selected_$tab.svga': [6, ver],
  },
});

SkinEquip equipFor(List<int> package, {int id = 7, int ver = 1, String url = packageUrl, String? md5Text}) => SkinEquip(
  id: id,
  name: 'skin $id',
  ver: ver,
  packageUrl: url,
  packageMd5: md5Text ?? md5.convert(package).toString(),
  colors: colors,
);

String nameOf(FileSystemEntity entity) => entity.path.split(RegExp(r'[\\/]')).last;

void main() {
  late Directory folder;
  late MemorySink sink;
  late Logger logger;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('skin_model_test');
    addTearDown(() => folder.delete(recursive: true));
    sink = MemorySink();
    logger = Logger(session: 'test')..add(sink);
  });

  ({SkinModel model, _Environment environment}) make(FakeSkinApi api, {Account account = loggedIn, bool keep = true}) {
    final environment = _Environment(account);
    final model = SkinModel(api: api, environment: environment, folder: keep ? folder.path : null, logger: logger);
    addTearDown(() async {
      model.dispose();
      await model.settle();
    });
    return (model: model, environment: environment);
  }

  FakeSkinApi apiWith(int ver, {int id = 7}) {
    final package = packageFor(ver);
    return FakeSkinApi(
      equip: equipFor(package, id: id, ver: ver),
      package: package,
    );
  }

  /// Starts [model] and lets the check it starts finish.
  Future<void> settle(SkinModel model) async {
    await model.start();
    await model.refresh();
  }

  Iterable<LogEvent> logged(String message) => sink.events.where((event) => event.msg == message);

  String allLogText() => sink.events.map((event) => event.encode()).join('\n');

  /// The unpacked folders of [id]'s version [ver], one per package.
  List<Directory> versionFolders(int id, int ver) {
    final skin = Directory('${folder.path}/$id');
    if (!skin.existsSync()) return const [];
    return skin.listSync().whereType<Directory>().where((each) => nameOf(each).startsWith('$ver-')).toList();
  }

  bool versionExists(int id, int ver) => versionFolders(id, ver).isNotEmpty;

  test('logged in, it downloads, checks and unpacks the package and shows it', () async {
    final api = apiWith(1);
    final (:model, environment: _) = make(api);
    var notified = 0;
    model.addListener(() => notified++);
    await settle(model);

    final skin = model.value!;
    expect(api.calls, ['equipped', 'download']);
    expect(skin.equip.id, 7);
    expect(skin.headBg!.readAsBytesSync(), [1, 1]);
    expect(skin.headMyself!.path, endsWith('head_myself_bg.png'));
    expect(skin.tailIcons, hasLength(5));
    expect(skin.tailIconsSelected.every((icon) => icon.animated), isTrue);
    expect(skin.themesBar, isTrue);
    expect(notified, 1);
    expect(versionExists(7, 1), isTrue);
    expect(File('${folder.path}/current.json').existsSync(), isTrue);
  });

  test('a launch shows the cached skin at once, before the check answers', () async {
    await settle(make(apiWith(1)).model);

    final api = apiWith(1);
    final hold = api.holds['equipped'] = Completer<void>();
    final (:model, environment: _) = make(api);
    await model.start();
    expect(model.value, isNotNull, reason: 'shown from the cache while the check is out:\n${allLogText()}');
    expect(model.value!.equip.ver, 1);
    expect(model.value!.equip.colors.tailColorSelected, colors.tailColorSelected);
    expect(model.value!.tailIcons, hasLength(5));
    expect(logged('skin').last.f['from'], const LogString('cache'));
    await pumpEventQueue();
    expect(api.calls, ['equipped']);

    hold.complete();
    await model.refresh();
    expect(api.calls, ['equipped'], reason: 'the same version is on disk already');
  });

  test('an unknown account shows the cache and waits; logged in, it asks', () async {
    await settle(make(apiWith(1)).model);

    final api = apiWith(1);
    final (:model, :environment) = make(api, account: const AccountUnknown());
    await model.start();
    expect(model.value, isNotNull);
    await pumpEventQueue();
    expect(api.calls, isEmpty);

    environment.account = loggedIn;
    await model.refresh();
    expect(api.calls, ['equipped']);
  });

  test('a launch already logged out starts stock, the cache unread into view', () async {
    await settle(make(apiWith(1)).model);

    final api = apiWith(1);
    final (:model, environment: _) = make(api, account: const LoggedOut());
    await model.start();
    await pumpEventQueue();
    expect(model.value, isNull);
    expect(api.calls, isEmpty);
  });

  test('every login asks again; a login from logged out asks once', () async {
    final api = apiWith(1);
    final (:model, :environment) = make(api);
    await settle(model);
    expect(api.calls, ['equipped', 'download']);

    environment.logins.value++;
    await model.refresh();
    expect(api.calls, ['equipped', 'download', 'equipped']);

    environment.account = const LoggedOut();
    environment.account = const AccountUnknown();
    environment.account = loggedIn;
    environment.logins.value++;
    await model.refresh();
    expect(api.calls, ['equipped', 'download', 'equipped', 'equipped']);
    expect(model.value, isNotNull);
  });

  test('logging out shows stock and keeps the files; the next launch starts stock, a login reuses them', () async {
    final api = apiWith(1);
    final (:model, :environment) = make(api);
    await settle(model);

    environment.account = const LoggedOut();
    expect(model.value, isNull);
    await model.settle();
    expect(versionExists(7, 1), isTrue, reason: 'the files stay');

    final next = make(apiWith(1), account: const AccountUnknown());
    await next.model.start();
    expect(next.model.value, isNull, reason: 'a logged-out launch never flashes the old account\'s skin');

    environment.account = loggedIn;
    await model.refresh();
    expect(model.value, isNotNull);
    expect(api.calls, ['equipped', 'download', 'equipped'], reason: 'unpacked already, nothing downloaded');
  });

  test('a login Bilibili no longer accepts shows stock too', () async {
    final (:model, :environment) = make(apiWith(1));
    await settle(model);
    environment.account = const LoginExpired();
    expect(model.value, isNull);
  });

  test('an answer for the account before a logout never shows', () async {
    final api = apiWith(1);
    final hold = api.holds['equipped'] = Completer<void>();
    final (:model, :environment) = make(api);
    await model.start();
    final check = model.refresh();
    await pumpEventQueue();
    environment.account = const LoggedOut();
    hold.complete();
    await check;
    expect(model.value, isNull);
    expect(api.calls, ['equipped'], reason: 'nothing downloaded for an account that left');
  });

  test('nothing equipped: stock, remembered for the next launch, the unpacked versions deleted', () async {
    final api = apiWith(1);
    final (:model, environment: _) = make(api);
    await settle(model);

    api.equip = null;
    await model.refresh();
    expect(model.value, isNull);
    expect(Directory('${folder.path}/7').existsSync(), isFalse);
    expect(logged('skin stays stock').last.f['reason'], const LogString('none equipped'));

    final next = make(FakeSkinApi(), account: const AccountUnknown());
    await next.model.start();
    expect(next.model.value, isNull);
  });

  test('without the app token it keeps what is shown and says so once', () async {
    final api = apiWith(1);
    final (:model, environment: _) = make(api);
    await settle(model);
    final shown = model.value;

    api.failures['equipped'] = BiliError.noAppToken;
    await model.refresh();
    await model.refresh();
    expect(model.value, same(shown));
    expect(sink.events.where((event) => event.msg.contains('app token')), hasLength(1));
  });

  test('a failed check or download keeps what is shown, and the log never carries the URL', () async {
    final api = apiWith(1);
    final (:model, environment: _) = make(api);
    await settle(model);
    final shown = model.value;

    api.failures['equipped'] = const BiliError.network('SocketException');
    await model.refresh();
    expect(model.value, same(shown));
    expect(logged('skin check failed, keeping what is shown'), hasLength(1));

    api.failures.remove('equipped');
    final newer = packageFor(2);
    api
      ..equip = equipFor(newer, ver: 2)
      ..package = newer
      ..failures['download'] = _TransportError();
    await model.refresh();
    expect(model.value, same(shown));
    expect(logged('skin not installed, keeping what is shown').single.f['error'], const LogString('_TransportError'));
    expect(allLogText(), isNot(contains('hdslb')));
    expect(allLogText(), isNot(contains('secret')));
    expect(versionExists(7, 1), isTrue);
    expect(versionExists(7, 2), isFalse);
  });

  test('a package whose md5 does not match is refused and nothing is unpacked', () async {
    final package = packageFor(1);
    final api = FakeSkinApi(
      equip: equipFor(package, md5Text: md5.convert([0]).toString()),
      package: package,
    );
    final (:model, environment: _) = make(api);
    await settle(model);
    expect(model.value, isNull);
    expect(api.calls, ['equipped', 'download']);
    expect(logged('skin not installed, keeping what is shown').single.f['error'], const LogString('md5 mismatch'));
    expect(Directory('${folder.path}/7').existsSync() && Directory('${folder.path}/7').listSync().isNotEmpty, isFalse);
  });

  test('an md5 in capitals matches', () async {
    final package = packageFor(1);
    final api = FakeSkinApi(
      equip: equipFor(package, md5Text: md5.convert(package).toString().toUpperCase()),
      package: package,
    );
    final (:model, environment: _) = make(api);
    await settle(model);
    expect(model.value, isNotNull);
  });

  test('a version unpacked already is reused without a download', () async {
    await settle(make(apiWith(1)).model);
    File('${folder.path}/current.json').deleteSync();

    final api = apiWith(1);
    final (:model, environment: _) = make(api);
    await settle(model);
    expect(model.value, isNotNull);
    expect(api.calls, ['equipped']);
    expect(logged('skin').last.f['from'], const LogString('unpacked'));
  });

  test('a half-written version is unpacked again', () async {
    await settle(make(apiWith(1)).model);
    File('${folder.path}/current.json').deleteSync();
    File('${versionFolders(7, 1).single.path}/.skin.json').deleteSync();

    final api = apiWith(1);
    final (:model, environment: _) = make(api);
    await settle(model);
    expect(model.value, isNotNull);
    expect(api.calls, ['equipped', 'download']);
  });

  test('a new version replaces the old, whose files are deleted', () async {
    final api = apiWith(1);
    final (:model, environment: _) = make(api);
    await settle(model);

    final newer = packageFor(2);
    api
      ..equip = equipFor(newer, ver: 2)
      ..package = newer;
    await model.refresh();
    expect(model.value!.equip.ver, 2);
    expect(model.value!.headBg!.readAsBytesSync(), [1, 2]);
    expect(versionExists(7, 1), isFalse);
    expect(versionExists(7, 2), isTrue);

    final other = packageFor(3);
    api
      ..equip = equipFor(other, id: 8, ver: 3)
      ..package = other;
    await model.refresh();
    expect(model.value!.equip.id, 8);
    expect(folder.listSync().map(nameOf).toSet(), {'8', 'current.json'});
  });

  test('a package changed under the same version unpacks beside the shown one, which then goes', () async {
    final api = apiWith(1);
    final (:model, environment: _) = make(api);
    await settle(model);
    final before = model.value!.headBg!.path;

    final changed = zipOf({
      'head_bg.png': [9, 9],
    });
    api
      ..equip = equipFor(changed)
      ..package = changed;
    await model.refresh();
    expect(model.value!.headBg!.readAsBytesSync(), [9, 9]);
    expect(model.value!.headBg!.path, isNot(before));
    expect(File(before).existsSync(), isFalse);
    expect(versionFolders(7, 1), hasLength(1));
  });

  test('a changed colour on the same version shows without a download', () async {
    final api = apiWith(1);
    final (:model, environment: _) = make(api);
    await settle(model);
    final package = api.package;
    api.equip = SkinEquip(
      id: 7,
      name: 'skin 7',
      ver: 1,
      packageUrl: packageUrl,
      packageMd5: md5.convert(package).toString(),
      colors: const SkinColors(color: 0xFF00FF00),
    );
    await model.refresh();
    expect(model.value!.equip.colors.color, 0xFF00FF00);
    expect(api.calls, ['equipped', 'download', 'equipped']);
  });

  test('a package off Bilibili\'s CDN, or over plain http, is never downloaded', () async {
    for (final url in ['https://example.com/7.zip', 'http://i0.hdslb.com/7.zip']) {
      final package = packageFor(1);
      final api = FakeSkinApi(
        equip: equipFor(package, url: url),
        package: package,
      );
      final (:model, environment: _) = make(api, keep: false);
      await settle(model);
      expect(model.value, isNull, reason: url);
      expect(api.calls, ['equipped'], reason: url);
    }
    expect(
      logged('skin not installed, keeping what is shown').map((event) => event.f['error']),
      everyElement(const LogString('package host not allowed')),
    );
  });

  test('a download past 40 MB is refused', () async {
    final api = apiWith(1)..package = Uint8List(SkinLimits.packageBytes + 1);
    final (:model, environment: _) = make(api);
    await settle(model);
    expect(model.value, isNull);
    expect(logged('skin not installed, keeping what is shown').single.f['error'], const LogString('package too large'));
  });

  test('a second refresh while one is out joins it', () async {
    final api = apiWith(1);
    final hold = api.holds['equipped'] = Completer<void>();
    final (:model, environment: _) = make(api, account: const AccountUnknown());
    await model.start();
    final first = model.refresh();
    final second = model.refresh();
    expect(identical(first, second), isTrue);
    hold.complete();
    await Future.wait([first, second]);
    expect(api.calls, ['equipped', 'download']);
  });

  test('the log names the skin, its colours and every file with extension and size, once', () async {
    final (:model, :environment) = make(apiWith(1));
    await settle(model);
    environment.logins.value++;
    await model.refresh();

    final event = logged('skin').single;
    expect(event.f['id'], const LogInt(7));
    expect(event.f['ver'], const LogInt(1));
    expect(event.f['name'], const LogString('skin 7'));
    expect(event.f['primaryOnly'], const LogBool(false));
    expect(event.f['lightText'], const LogBool(true));
    expect(event.f['tailColorSelected'], const LogString('#ffff0000'));
    expect(event.f['bar'], const LogString('themed'));
    final files = (event.f['files']! as LogString).value;
    expect(files, contains('head_bg png 2'));
    expect(files, contains('tail_bg webp 2'));
    expect(files, contains('tail_icon_selected_main svga 2'));
    expect(allLogText(), isNot(contains('hdslb')));
  });

  test('made, it listens to nothing and asks nothing until start', () async {
    final api = apiWith(1);
    final (:model, :environment) = make(api);
    await pumpEventQueue();
    expect(environment.listening, 0);
    expect(environment.logins.listening, 0);
    expect(api.calls, isEmpty);
    expect(model.value, isNull);

    await settle(model);
    expect(environment.listening, 1);
    expect(environment.logins.listening, 1);
  });

  test('a subclass can stand in with its own value and refresh', () async {
    final environment = _Environment(loggedIn);
    final model = _FixedSkinModel(null, environment: environment);
    addTearDown(model.dispose);
    var notified = 0;
    model.addListener(() => notified++);
    final skin = Skin(equip: equipFor(const [1]));
    model.skin = skin;
    await model.refresh();
    expect(model.value, same(skin));
    expect(notified, 1);
    expect(model.refreshes, 1);
    expect(environment.listening, 0);
  });

  test('refresh never throws, even when nothing can be written', () async {
    final blocked = File('${folder.path}/blocked')..writeAsStringSync('a file where the folder should be');
    final api = apiWith(1);
    final environment = _Environment(loggedIn);
    final model = SkinModel(api: api, environment: environment, folder: blocked.path, logger: logger);
    addTearDown(model.dispose);
    await model.start();
    await expectLater(model.refresh(), completes);
    expect(model.value, isNull);

    api.equip = null;
    await expectLater(model.refresh(), completes);
    expect(model.value, isNull);
  });

  test('a cache that can\'t be read starts stock', () async {
    File('${folder.path}/current.json').writeAsStringSync('{not json');
    final (:model, environment: _) = make(FakeSkinApi(), account: const AccountUnknown());
    await model.start();
    expect(model.value, isNull);
    expect(logged('skin stays stock').single.f['reason'], const LogString('cache unreadable'));

    File('${folder.path}/current.json').writeAsStringSync(
      jsonEncode({
        'equip': {'id': 7},
      }),
    );
    final next = make(FakeSkinApi(), account: const AccountUnknown());
    await next.model.start();
    expect(next.model.value, isNull);
  });

  test('the demo package resolves every picture role but the video, at the official sizes', () async {
    final api = FakeSkinApi.demo();
    final (:model, environment: _) = make(api);
    await settle(model);

    final skin = model.value!;
    expect(api.calls, ['equipped', 'download']);
    expect(skin.equip.colors.lightText, isTrue);
    expect(skin.themesBar, isTrue);
    expect(skin.tailIcons, hasLength(5));
    expect(skin.tailIconsSelected, hasLength(5));
    expect(skin.pubButton, isNotNull);
    expect(skin.pubButtonSelected, isNotNull);
    expect(skin.headMyselfVideo, isNull);
    expect(pngSize(skin.headBg!), (1320, 430));
    expect(pngSize(skin.headTabBg!), (1320, 132));
    expect(pngSize(skin.headMyself!), (1320, 1000));
    expect(pngSize(skin.tailBg!), (1320, 300));
    for (final icon in [...skin.tailIcons, ...skin.tailIconsSelected, skin.pubButton!, skin.pubButtonSelected!]) {
      expect(pngSize(icon.file), (180, 135));
    }
  });
}

/// Width and height from a PNG's header.
(int, int) pngSize(File file) {
  final bytes = file.readAsBytesSync();
  expect(bytes.sublist(1, 4), ascii.encode('PNG'));
  final header = ByteData.sublistView(bytes, 16, 24);
  return (header.getUint32(0), header.getUint32(4));
}
