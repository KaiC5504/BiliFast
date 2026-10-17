import 'dart:convert';
import 'dart:io';

import 'api/bili_client.dart';
import 'api/models.dart';
import 'ripper/local_server.dart';

/// App-wide singletons and the PC-only overrides passed on the command line.
class Services {
  static BiliClient client = BiliClient();
  static final server = LocalServer();
  static final media = HttpClient()
    ..maxConnectionsPerHost = 8
    ..idleTimeout = const Duration(seconds: 30)
    ..autoUncompress = false;

  /// A folder of saved playurl responses named `<BV>.json` (gitignored `local/`), used instead of the API so
  /// the bench can play the qualities of a logged-in browser session without the app holding any cookie.
  static String? playurlDir;

  static int maxQuality = 120;

  static Future<void> init(List<String> args) async {
    String? arg(String name) {
      final i = args.indexOf(name);
      return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
    }

    final cookieFile = arg('--cookies');
    if (cookieFile != null && File(cookieFile).existsSync()) {
      client = BiliClient(cookies: BiliClient.parseCookieHeader(File(cookieFile).readAsStringSync().trim()));
    }
    playurlDir = arg('--playurl-dir');
    maxQuality = int.tryParse(arg('--qn') ?? '') ?? maxQuality;
    await server.start();
    try {
      await client.ensureRiskCookies();
    } catch (_) {}
  }

  static Future<PlayInfo> playInfo(String bvid, int cid) async {
    final dir = playurlDir;
    if (dir != null) {
      final file = File('$dir/$bvid.json');
      if (file.existsSync()) {
        final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        return PlayInfo.parse((json['data'] ?? json) as Map<String, dynamic>);
      }
    }
    return client.playUrl(bvid, cid, maxQuality);
  }
}
