import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_core/api.dart';

import '../playback/fakes.dart';

const feedPath = '/x/web-interface/wbi/index/top/feed/rcmd';

/// One feed row as the web feed sends it.
Map<String, Object?> feedItem(String bvid, {String title = '视频', String? reason}) => {
  'goto': 'av',
  'id': bvid.hashCode.abs(),
  'bvid': bvid,
  'cid': 1,
  'title': '$title $bvid',
  'pic': 'https://i0.hdslb.com/bfs/archive/$bvid.jpg',
  'duration': 125,
  'owner': {'mid': 7, 'name': 'UP $bvid'},
  'stat': {'view': 12345, 'danmaku': 67},
  if (reason != null) 'rcmd_reason': {'content': reason},
};

/// The canned routes, and the feed's pages by `fresh_idx`: a page not set answers an empty list, and [failing]
/// pages answer HTTP 500. [gates] hold a page's answer until completed.
final class FeedHttp implements HTTPTransport {
  FeedHttp({bool loggedIn = true}) : canned = Canned.http(loggedIn: loggedIn);

  final CannedHttp canned;
  final pages = <int, List<Map<String, Object?>>>{};
  final failing = <int>{};
  final gates = <int, Completer<void>>{};
  final asked = <int>[];

  @override
  Future<HTTPResponse> send(HTTPRequest request) async {
    if (request.url.path != feedPath) return canned.send(request);
    final index = int.parse(request.url.queryParameters['fresh_idx']!);
    asked.add(index);
    await gates[index]?.future;
    if (failing.contains(index)) {
      return HTTPResponse(status: 500, headers: {}, body: Uint8List(0), finalURL: request.url);
    }
    final body = jsonEncode({
      'code': 0,
      'data': {'item': pages[index] ?? const []},
    });
    return HTTPResponse(status: 200, headers: {}, body: utf8.encode(body), finalURL: request.url);
  }
}
