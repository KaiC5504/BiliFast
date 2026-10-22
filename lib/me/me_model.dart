// Stub for the data agent, who removes this line.
// ignore_for_file: unused_field, prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../app/app_environment.dart';
import 'me_api.dart';

/// What 我的's header shows of the account.
@immutable
final class MeProfile {
  const MeProfile({
    required this.mid,
    required this.name,
    required this.face,
    required this.level,
    required this.coins,
    required this.bcoin,
    this.pendant,
    this.vip = false,
    this.vipLabel = '',
    this.vipBadge = false,
  });

  final int mid;
  final String name;
  final String face;

  /// The avatar frame's picture, if the account wears one.
  final String? pendant;
  final int level;

  /// 硬币 and B币 as the nav answered them.
  final double coins;
  final double bcoin;

  /// A current 大会员: the 会员 card shows (hidden otherwise, no screenshot of it).
  final bool vip;

  /// The pink pill after the level, such as 年度大会员; empty hides it.
  final String vipLabel;

  /// The 大 badge on the avatar's corner.
  final bool vipBadge;
}

/// 动态, 关注 and 粉丝.
@immutable
final class MeCounts {
  const MeCounts({required this.dynamics, required this.following, required this.followers});

  final int dynamics;
  final int following;
  final int followers;
}

/// What 我的 draws.
sealed class MeView {
  const MeView();
}

/// No account: the grey avatar and 点击登录, counts as -, no 会员 card.
final class MeLoggedOut extends MeView {
  const MeLoggedOut();
}

/// Logged in, nothing answered yet.
final class MeLoading extends MeView {
  const MeLoading();
}

/// The account, with [counts] null until (or if) nav/stat answers.
final class MeShown extends MeView {
  const MeShown(this.profile, this.counts);

  final MeProfile profile;
  final MeCounts? counts;
}

/// Logged in, and the first load failed with nothing to show; [message] is the user-facing reason.
final class MeFailed extends MeView {
  const MeFailed(this.message);

  final String message;
}

/// 我的's account and counts, following the login.
class MeModel extends ChangeNotifier {
  MeModel({
    required MeApi api,
    required AppEnvironment environment,
    this.quietGap = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _api = api,
       _environment = environment,
       _now = now ?? DateTime.now;

  final MeApi _api;
  final AppEnvironment _environment;
  final DateTime Function() _now;

  /// The least time between two loads that [shown] starts on its own.
  final Duration quietGap;

  MeView get view => const MeLoading();

  /// The tab came on screen: loads the first time, then again quietly (the page stays as it is) at most every
  /// [quietGap]. Logged out it calls nothing.
  void shown() {}

  /// The pull. Completes when the answer is in; with the page shown, a failure keeps it and returns the message to
  /// toast. Null on success.
  Future<String?> refresh() async => null;
}
