import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bili_core/api.dart';
import 'package:crypto/crypto.dart';

import 'skin.dart';

/// What a 装扮 package may take. The official packages are a few MB; the caps keep a bad answer off the disk.
abstract final class SkinLimits {
  static const packageBytes = 40 * 1024 * 1024;
  static const entryBytes = 20 * 1024 * 1024;
  static const unpackedBytes = 100 * 1024 * 1024;
  static const connectTimeout = Duration(seconds: 15);
  static const downloadTimeout = Duration(seconds: 90);
}

/// The package's file names, without their extensions (png, webp, jpg, svga or mp4 vary by skin), as the official
/// app looks them up.
abstract final class SkinNames {
  static const headBg = 'head_bg';
  static const headTabBg = 'head_tab_bg';
  static const headMyselfSquared = 'head_myself_squared_bg';
  static const headMyself = 'head_myself_bg';
  static const headMyselfVideo = 'head_myself_mp4_bg';
  static const tailBg = 'tail_bg';
  static const pubButton = 'tail_icon_pub_btn_bg';
  static const pubButtonSelected = 'tail_icon_selected_pub_btn_bg';

  /// The bar's places in the package's order.
  static const tabs = ['main', 'channel', 'dynamic', 'shop', 'myself'];

  static List<String> get tailIcons => [for (final tab in tabs) 'tail_icon_$tab'];
  static List<String> get tailIconsSelected => [for (final tab in tabs) 'tail_icon_selected_$tab'];
}

/// Why a package was refused or couldn't be used. Never carries the package's URL.
final class SkinPackageError implements Exception {
  const SkinPackageError(this.reason);

  final String reason;

  @override
  String toString() => 'SkinPackageError($reason)';
}

const _cdnDomains = ['hdslb.com', 'biliimg.com', 'bilibili.com'];

/// Only https to Bilibili's CDN hosts on the standard port: the package URL comes from an answer, and a redirect
/// is held to the same rule.
bool isSkinPackageUrl(Uri url) {
  if (url.scheme != 'https' || url.userInfo.isNotEmpty || url.port != 443) return false;
  final host = url.host.toLowerCase();
  return _cdnDomains.any((domain) => host == domain || host.endsWith('.$domain'));
}

/// The package over a plain dart:io client: no cookies, no token, the browser's user agent. Redirects are followed
/// by hand so each hop passes [isSkinPackageUrl]; [client] is for tests.
Future<Uint8List> downloadSkinPackage(
  Uri url, {
  HttpClient Function() client = HttpClient.new,
  Duration timeout = SkinLimits.downloadTimeout,
}) async {
  if (!isSkinPackageUrl(url)) throw const SkinPackageError('package host not allowed');
  final http = client()
    ..connectionTimeout = SkinLimits.connectTimeout
    ..userAgent = BiliClient.userAgent;
  try {
    final fetched = _fetch(http, url);
    return await fetched.timeout(timeout, onTimeout: () => throw const SkinPackageError('download timed out'));
  } finally {
    http.close(force: true);
  }
}

Future<Uint8List> _fetch(HttpClient http, Uri url) async {
  var next = url;
  for (var hop = 0; hop < 4; hop++) {
    if (!isSkinPackageUrl(next)) throw const SkinPackageError('package host not allowed');
    final request = await http.getUrl(next);
    request.followRedirects = false;
    final response = await request.close();
    if (response.isRedirect) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null) throw const SkinPackageError('redirect without a location');
      next = next.resolve(location);
      continue;
    }
    if (response.statusCode != HttpStatus.ok) throw SkinPackageError('download answered ${response.statusCode}');
    return readCapped(response, declaredLength: response.contentLength);
  }
  throw const SkinPackageError('too many redirects');
}

/// [body] whole, refused past [cap] bytes whether or not the server declared its length.
Future<Uint8List> readCapped(
  Stream<List<int>> body, {
  int declaredLength = -1,
  int cap = SkinLimits.packageBytes,
}) async {
  if (declaredLength > cap) throw const SkinPackageError('package too large');
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in body) {
    bytes.add(chunk);
    if (bytes.length > cap) throw const SkinPackageError('package too large');
  }
  return bytes.takeBytes();
}

/// What [unpackSkinPackage] wrote, and what it left out with the reason (`name: reason`).
final class SkinUnpacked {
  const SkinUnpacked({required this.written, required this.skipped});

  final List<String> written;
  final List<String> skipped;
}

/// Checks [zip] against [md5] (either case), then writes its entries flat into [folder], made if missing. An entry
/// with a path, a parent, a drive or a leading dot, a link, one past [entryBytes] or one that can't be read is
/// skipped; past [unpackedBytes] in all, a wrong md5 or no zip at all throws [SkinPackageError]. Runs on its own
/// isolate, since inflating a large package would hold up frames.
Future<SkinUnpacked> unpackSkinPackage(
  Uint8List zip, {
  required String md5,
  required String folder,
  int entryBytes = SkinLimits.entryBytes,
  int unpackedBytes = SkinLimits.unpackedBytes,
}) => Isolate.run(() => _unpack(zip, md5, folder, entryBytes, unpackedBytes));

SkinUnpacked _unpack(Uint8List zip, String expectedMd5, String folder, int entryBytes, int unpackedBytes) {
  if (md5.convert(zip).toString() != expectedMd5.trim().toLowerCase()) throw const SkinPackageError('md5 mismatch');
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zip);
  } on Exception {
    throw const SkinPackageError('not a zip');
  }
  // The decoder reads anything without an end record as an empty archive.
  if (archive.isEmpty) throw const SkinPackageError('not a zip');
  Directory(folder).createSync(recursive: true);
  final written = <String>[];
  final skipped = <String>[];
  var total = 0;
  for (final entry in archive) {
    if (!entry.isFile) continue;
    final name = entry.name;
    final refusal = entry.isSymbolicLink ? 'link' : _nameRefusal(name);
    if (refusal != null) {
      skipped.add('${_shown(name)}: $refusal');
      continue;
    }
    if (entry.size > entryBytes) {
      skipped.add('$name: too large');
      continue;
    }
    final Uint8List bytes;
    try {
      // The archive stops inflating at the declared size, so an entry that lies about it fails here.
      bytes = entry.readBytes() ?? Uint8List(0);
    } on Exception {
      skipped.add('$name: unreadable');
      continue;
    } finally {
      entry.closeSync();
    }
    total += bytes.length;
    if (total > unpackedBytes) throw const SkinPackageError('package unpacks too large');
    File('$folder/$name').writeAsBytesSync(bytes, flush: true);
    written.add(name);
  }
  return SkinUnpacked(written: written, skipped: skipped);
}

String? _nameRefusal(String name) {
  if (name.isEmpty) return 'no name';
  if (name.contains('/') || name.contains(r'\')) return 'not flat';
  if (name.contains('..')) return 'parent';
  if (name.contains(':')) return 'drive';
  if (name.startsWith('.')) return 'hidden';
  if (name.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) return 'control character';
  return null;
}

String _shown(String name) => name.length <= 60 ? name : '${name.substring(0, 60)}…';

/// An unpacked file and its size.
final class SkinFile {
  const SkinFile(this.file, this.size);

  final File file;
  final int size;

  String get name => _nameOf(file.path);

  /// The name without its extension: what the official app looks a role up by.
  String get stem {
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }
}

/// The files in an unpacked version's [folder], sorted by name, its hidden bookkeeping left out.
Future<List<SkinFile>> listSkinFiles(Directory folder) async {
  final files = <SkinFile>[];
  await for (final entity in folder.list(followLinks: false)) {
    if (entity is! File || _nameOf(entity.path).startsWith('.')) continue;
    files.add(SkinFile(entity, await entity.length()));
  }
  return files..sort((a, b) => a.name.compareTo(b.name));
}

String _nameOf(String path) => path.split(RegExp(r'[\\/]')).last;

/// [files] by role, each found by its name without the extension (the first in name order when two share one).
/// `head_myself_squared_bg` comes before `head_myself_bg`; each set of the bar's icons is kept only whole, so a
/// set missing any of its five leaves the bar stock.
Skin resolveSkin(SkinEquip equip, List<SkinFile> files) {
  final byStem = <String, File>{};
  for (final file in files) {
    byStem.putIfAbsent(file.stem, () => file.file);
  }
  SkinIcon? icon(String stem) => switch (byStem[stem]) {
    final file? => SkinIcon(file, animated: _isSvga(file)),
    null => null,
  };
  List<SkinIcon> iconSet(List<String> stems) {
    final icons = [for (final stem in stems) ?icon(stem)];
    return icons.length == stems.length ? icons : const [];
  }

  return Skin(
    equip: equip,
    headBg: byStem[SkinNames.headBg],
    headTabBg: byStem[SkinNames.headTabBg],
    headMyself: byStem[SkinNames.headMyselfSquared] ?? byStem[SkinNames.headMyself],
    headMyselfVideo: byStem[SkinNames.headMyselfVideo],
    tailBg: byStem[SkinNames.tailBg],
    tailIcons: iconSet(SkinNames.tailIcons),
    tailIconsSelected: iconSet(SkinNames.tailIconsSelected),
    pubButton: icon(SkinNames.pubButton),
    pubButtonSelected: icon(SkinNames.pubButtonSelected),
    files: Map.unmodifiable(byStem),
  );
}

bool _isSvga(File file) => file.path.toLowerCase().endsWith('.svga');

/// What leaves the themed bar stock, for the log; empty when [skin] themes it.
List<String> skinBarGaps(Skin skin) => [
  if (skin.tailIcons.isEmpty) 'tail icons',
  if (skin.tailIconsSelected.isEmpty) 'selected tail icons',
  if (skin.tailColor == null) 'tail color',
  if (skin.tailColorSelected == null) 'selected tail color',
];
