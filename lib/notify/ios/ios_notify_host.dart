import 'package:flutter/services.dart';

import '../notify_host.dart';
import 'notify_api.g.dart';

/// The phone's [NotifyHost], over Pigeon's NotifyHostApi (NotifyHost.swift).
class IosNotifyHost implements NotifyHost {
  IosNotifyHost({BinaryMessenger? binaryMessenger}) : _api = NotifyHostApi(binaryMessenger: binaryMessenger) {
    NotifyEventApi.setUp(_events, binaryMessenger: binaryMessenger);
  }

  final NotifyHostApi _api;
  final _events = _Events();

  @override
  bool get available => true;

  @override
  Future<NotifyKinds> kinds() async {
    final kinds = await _api.kinds();
    return NotifyKinds(
      replies: kinds.replies,
      mentions: kinds.mentions,
      likes: kinds.likes,
      messages: kinds.messages,
      uploads: kinds.uploads,
    );
  }

  @override
  Future<void> setKinds(NotifyKinds kinds) => _api.setKinds(
    NativeNotifyKinds(
      replies: kinds.replies,
      mentions: kinds.mentions,
      likes: kinds.likes,
      messages: kinds.messages,
      uploads: kinds.uploads,
    ),
  );

  @override
  Future<NotifyPermission> permission() async => switch (await _api.permission()) {
    NativeNotifyPermission.notDetermined => NotifyPermission.notDetermined,
    NativeNotifyPermission.denied => NotifyPermission.denied,
    NativeNotifyPermission.allowed => NotifyPermission.allowed,
  };

  @override
  Future<bool> requestPermission() => _api.requestPermission();

  @override
  Future<NotifyRoute?> takeLaunchRoute() async {
    final route = await _api.takeLaunchRoute();
    return route == null ? null : routeOf(route);
  }

  @override
  Future<List<NotifyTrip>> takeTrips() async => [
    for (final trip in await _api.takeTrips())
      NotifyTrip(
        at: DateTime.fromMillisecondsSinceEpoch(trip.atMs),
        outcome: trip.outcome,
        calls: trip.calls,
        posted: trip.posted,
      ),
  ];

  @override
  set onTap(void Function(NotifyRoute route)? callback) => _events.tap = callback;
}

/// A route without what its target needs opens the app.
NotifyRoute routeOf(NativeNotifyRoute route) => switch (route.target) {
  NativeNotifyTarget.video when route.bvid?.isNotEmpty ?? false => NotifyVideo(
    bvid: route.bvid!,
    commentRoot: route.commentRoot,
    comment: route.comment,
  ),
  NativeNotifyTarget.dynamicPost when route.dynamicId?.isNotEmpty ?? false => NotifyDynamicPost(
    id: route.dynamicId!,
    toComments: route.toComments,
  ),
  _ => const NotifyApp(),
};

class _Events implements NotifyEventApi {
  void Function(NotifyRoute route)? tap;

  @override
  void onTap(NativeNotifyRoute route) => tap?.call(routeOf(route));
}
