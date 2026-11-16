import 'package:flutter/widgets.dart';

import '../app/app_scope.dart';

/// A room page's own way to the login page, for every control inside it: from full screen it turns upright first,
/// as the video page does.
class LiveLoginScope extends InheritedWidget {
  const LiveLoginScope({super.key, required this.request, required super.child});

  final Future<bool> Function() request;

  @override
  bool updateShouldNotify(LiveLoginScope oldWidget) => false;
}

/// The login page for a logged-out action in a room; outside a room page, the app's login gate as it is.
Future<bool> requestLiveLogin(BuildContext context) {
  final scope = context.getInheritedWidgetOfExactType<LiveLoginScope>();
  if (scope != null) return scope.request();
  return AppScope.of(context).loginGate.request(context);
}
