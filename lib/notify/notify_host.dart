import 'package:flutter/foundation.dart';

/// 推送设置's switches.
@immutable
class NotifyKinds {
  const NotifyKinds({
    this.replies = false,
    this.mentions = false,
    this.likes = false,
    this.messages = false,
    this.uploads = false,
  });

  static const none = NotifyKinds();

  /// 回复我的.
  final bool replies;

  /// @我的.
  final bool mentions;

  /// 收到的赞.
  final bool likes;

  /// 私信.
  final bool messages;

  /// 关注的UP主投稿.
  final bool uploads;

  bool get any => replies || mentions || likes || messages || uploads;

  NotifyKinds copyWith({bool? replies, bool? mentions, bool? likes, bool? messages, bool? uploads}) => NotifyKinds(
    replies: replies ?? this.replies,
    mentions: mentions ?? this.mentions,
    likes: likes ?? this.likes,
    messages: messages ?? this.messages,
    uploads: uploads ?? this.uploads,
  );

  @override
  bool operator ==(Object other) =>
      other is NotifyKinds &&
      other.replies == replies &&
      other.mentions == mentions &&
      other.likes == likes &&
      other.messages == messages &&
      other.uploads == uploads;

  @override
  int get hashCode => Object.hash(replies, mentions, likes, messages, uploads);
}

enum NotifyPermission { notDetermined, denied, allowed }

/// Where a tapped notification leads.
sealed class NotifyRoute {
  const NotifyRoute();
}

/// A video's page, with the thread of [commentRoot] open (and [comment] in it) when set.
final class NotifyVideo extends NotifyRoute {
  const NotifyVideo({required this.bvid, this.commentRoot, this.comment});

  final String bvid;
  final int? commentRoot;
  final int? comment;
}

final class NotifyDynamicPost extends NotifyRoute {
  const NotifyDynamicPost({required this.id, this.toComments = false});

  final String id;
  final bool toComments;
}

/// 私信 and 赞 until 消息 is built: the app opens where it was.
final class NotifyApp extends NotifyRoute {
  const NotifyApp();
}

/// One background check, as NotifyHost.swift recorded it.
@immutable
class NotifyTrip {
  const NotifyTrip({required this.at, required this.outcome, required this.calls, required this.posted});

  final DateTime at;
  final String outcome;
  final int calls;
  final int posted;
}

/// The phone's notifications (NotifyHost.swift); [NoNotifyHost] elsewhere.
abstract class NotifyHost {
  /// Notifications exist on this platform.
  bool get available;

  Future<NotifyKinds> kinds();

  Future<void> setKinds(NotifyKinds kinds);

  Future<NotifyPermission> permission();

  Future<bool> requestPermission();

  Future<NotifyRoute?> takeLaunchRoute();

  Future<List<NotifyTrip>> takeTrips();

  set onTap(void Function(NotifyRoute route)? callback);
}

/// Windows and tests: the switches kept in memory, nothing posted.
class NoNotifyHost implements NotifyHost {
  NoNotifyHost({this._kinds = NotifyKinds.none, this.allowed = NotifyPermission.notDetermined});

  NotifyKinds _kinds;
  NotifyPermission allowed;

  @override
  bool get available => false;

  @override
  Future<NotifyKinds> kinds() async => _kinds;

  @override
  Future<void> setKinds(NotifyKinds kinds) async => _kinds = kinds;

  @override
  Future<NotifyPermission> permission() async => allowed;

  @override
  Future<bool> requestPermission() async => allowed == NotifyPermission.allowed;

  @override
  Future<NotifyRoute?> takeLaunchRoute() async => null;

  @override
  Future<List<NotifyTrip>> takeTrips() async => const [];

  @override
  set onTap(void Function(NotifyRoute route)? callback) {}
}
