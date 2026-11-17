import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../../app/app_environment.dart';
import '../dynamic_api.dart';

/// The newest post 关注's 全部 showed each account, kept on the phone (`follow_badge.json`): what [FollowBadge]
/// counts from, across launches.
class FollowBaselines {
  FollowBaselines._(this._path, this._baselines, this._logger);

  /// Kept in memory only, for tests and for platforms without a support folder.
  factory FollowBaselines.memory({Logger? logger}) => FollowBaselines._(null, {}, logger ?? Logger.shared);

  /// [path] null keeps it in memory.
  static Future<FollowBaselines> load(String? path, {Logger? logger}) async =>
      FollowBaselines._(path, {}, logger ?? Logger.shared);

  // ignore: unused_field
  final String? _path;
  // ignore: unused_field
  final Logger _logger;
  final Map<int, String> _baselines;

  String? of(int mid) => _baselines[mid];

  Future<void> set(int mid, String baseline) async => _baselines[mid] = baseline;
}

/// 关注's red count on the bottom bar (238), one for the app ([AppServices.followBadge]): posts of every kind since
/// the newest one 关注's 全部 showed this account. No count until 全部 has shown a first page, and none logged out.
class FollowBadge extends ChangeNotifier {
  FollowBadge({
    required this.api,
    required this.environment,
    FollowBaselines? baselines,
    this.resumeGap = const Duration(minutes: 1),
    DateTime Function()? now,
    Logger? logger,
  }) : _baselines = baselines ?? FollowBaselines.memory();

  final DynamicApi api;
  final AppEnvironment environment;
  // ignore: unused_field
  final FollowBaselines _baselines;

  /// How long after the count was last asked a return to the app asks it again.
  final Duration resumeGap;

  /// The number on 关注's place; 0 logged out or before a baseline.
  int get count => 0;

  /// Starts the count's upkeep: once at launch, on a return to the app at most once per [resumeGap], on each login.
  void start() {}

  /// Asks the count again; [force] skips the [resumeGap] limit.
  Future<void> refresh({bool force = false}) async {}

  /// 全部's first page landed with [baseline]: the count starts over from it.
  void seen(String baseline) {}

  /// 关注 was opened over a count: it goes at once.
  void clear() {}
}
