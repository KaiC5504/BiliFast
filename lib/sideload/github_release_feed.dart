import 'dart:async';
import 'dart:convert';

import 'package:bili_core/devlog.dart';
import 'package:http/http.dart' as http;

import 'sideload_links.dart';
import 'sideload_model.dart';

/// The repo's newest release on GitHub, its tag `v<version>-<build>` as the workflow's `release` job names it.
final class GitHubReleaseFeed implements ReleaseFeed {
  GitHubReleaseFeed(this._client, {Logger? logger, this.timeout = const Duration(seconds: 10)})
    : _logger = logger ?? Logger.shared;

  final http.Client _client;
  final Logger _logger;
  final Duration timeout;

  static final _tag = RegExp(r'^v(\d+(?:\.\d+)*)-(\d+)$');

  // GitHub refuses API calls without a User-Agent.
  static const _headers = {'Accept': 'application/vnd.github+json', 'User-Agent': 'BiliFast'};

  @override
  Future<ReleaseInfo?> latest() async {
    try {
      final response = await _client.get(Uri.parse(latestReleaseApi), headers: _headers).timeout(timeout);
      if (response.statusCode != 200) return _failed('status ${response.statusCode}');
      final release = parseRelease(jsonDecode(response.body));
      return release ?? _failed('unexpected shape');
    } on TimeoutException {
      return _failed('timeout');
    } on FormatException {
      return _failed('not json');
    } catch (error) {
      return _failed('${error.runtimeType}');
    }
  }

  /// A release from the API's answer, or null when it isn't one of ours: a tag named otherwise, or a page that isn't
  /// on GitHub.
  static ReleaseInfo? parseRelease(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final tag = json['tag_name'];
    final link = json['html_url'];
    if (tag is! String || link is! String) return null;
    final match = _tag.firstMatch(tag);
    final page = Uri.tryParse(link);
    if (match == null || page == null || page.scheme != 'https' || page.host != 'github.com') return null;
    final build = int.tryParse(match.group(2)!);
    if (build == null) return null;
    return ReleaseInfo(version: match.group(1)!, build: build, page: page);
  }

  ReleaseInfo? _failed(String reason) {
    _logger.warn(LogCategory.app, 'release check failed', {'reason': reason});
    return null;
  }
}
