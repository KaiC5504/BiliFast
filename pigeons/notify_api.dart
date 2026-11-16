// Regenerate after any change, from the repo root:
//   fvm dart run pigeon --input pigeons/notify_api.dart
// and commit both outputs (lib/notify/ios/notify_api.g.dart, ios/Runner/NotifyApi.g.swift).
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/notify/ios/notify_api.g.dart',
    swiftOut: 'ios/Runner/NotifyApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'NotifyApiError'),
  ),
)
enum NativeNotifyPermission { notDetermined, denied, allowed }

/// 推送设置's switches. Kept natively, so a background check needs no Dart.
class NativeNotifyKinds {
  NativeNotifyKinds({
    required this.replies,
    required this.mentions,
    required this.likes,
    required this.messages,
    required this.uploads,
  });

  /// 回复我的.
  bool replies;

  /// @我的.
  bool mentions;

  /// 收到的赞.
  bool likes;

  /// 私信.
  bool messages;

  /// 关注的UP主投稿 (动态's videos).
  bool uploads;
}

enum NativeNotifyTarget { video, dynamicPost, app, likes, messages }

/// Where a tapped notification leads: a video (its page, with a comment thread open when [commentRoot] is set), a
/// 动态 post, 收到喜欢, 消息, or just the app.
class NativeNotifyRoute {
  NativeNotifyRoute({
    required this.target,
    this.bvid,
    this.commentRoot,
    this.comment,
    this.dynamicId,
    required this.toComments,
  });

  NativeNotifyTarget target;
  String? bvid;

  /// The thread's root comment (rpid).
  int? commentRoot;

  /// The reply itself, inside the thread.
  int? comment;

  String? dynamicId;

  /// A 动态 post opens on its comments.
  bool toComments;
}

/// One background check, for the phone log at the next launch. No ids, names or text.
class NativeNotifyTrip {
  NativeNotifyTrip({
    required this.atMs,
    required this.outcome,
    required this.calls,
    required this.posted,
  });

  int atMs;

  /// `posted` (or `posted, N failed <domain> <code>`), `nothing new`, `seeded`, `logged out`, `all off`, `not allowed`,
  /// `expired`, or `failed <reason>` (a scheduling refusal too: `failed not scheduled <code>`, `failed not registered`).
  String outcome;
  int calls;
  int posted;
}

/// Notifications from background checks (NotifyHost.swift): iOS's app refresh wakes the app, which asks Bilibili for
/// unread counts with the keychain's login and posts local notifications. No server, no push.
@HostApi()
abstract class NotifyHostApi {
  NativeNotifyKinds kinds();

  /// Saves the switches; with any on, a refresh is scheduled, with all off it is cancelled.
  void setKinds(NativeNotifyKinds kinds);

  @async
  NativeNotifyPermission permission();

  /// Asks iOS for alert and sound permission, as the sideload reminder does; true when given.
  @async
  bool requestPermission();

  /// iOS's Background App Refresh for the app (UIApplication.backgroundRefreshStatus): without it no check ever runs.
  bool backgroundRefreshAllowed();

  /// The latest tap before Dart first asked (the one that launched the app, if any), once; null if none.
  NativeNotifyRoute? takeLaunchRoute();

  /// The checks since the last call, oldest first.
  List<NativeNotifyTrip> takeTrips();
}

@FlutterApi()
abstract class NotifyEventApi {
  /// A notification tapped while the app runs.
  void onTap(NativeNotifyRoute route);
}
