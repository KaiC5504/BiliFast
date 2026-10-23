import 'dart:io';

import 'package:bili_core/api.dart';

import 'skin_package.dart';

/// The equipped 装扮 and 加载动画, and their files.
abstract interface class SkinApi {
  /// The official app's `/x/resource/show/skin`, with the app token: the 装扮 with a package and the 加载动画, each
  /// null when none is worn.
  Future<SkinWorn> equipped();

  /// The package zip, a public file on Bilibili's CDN (no account, no cookies).
  Future<List<int>> download(Uri package);

  /// The 加载动画's picture, a public file on Bilibili's CDN (no account, no cookies).
  Future<List<int>> downloadLoading(Uri picture);
}

class ClientSkinApi implements SkinApi {
  ClientSkinApi(this._client, {this._http = HttpClient.new});

  final BiliClient _client;
  final HttpClient Function() _http;

  @override
  Future<SkinWorn> equipped() => _client.skin();

  /// Outside [BiliClient], whose transport carries the login's cookies.
  @override
  Future<List<int>> download(Uri package) => downloadSkinPackage(package, client: _http);

  @override
  Future<List<int>> downloadLoading(Uri picture) =>
      downloadSkinPackage(picture, client: _http, cap: SkinLimits.loadingBytes);
}
