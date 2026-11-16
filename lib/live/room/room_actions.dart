import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_environment.dart';
import '../../app/app_scope.dart';
import '../../shared/toast.dart';
import '../live_login.dart';
import 'live_overlays.dart';
import 'live_room_model.dart';
import '../../video/actions/actions_model.dart' show ActionsModel;

const roomNotYet = '暂未开放';

/// What every unbuilt control in a room says.
void toastNotYet(BuildContext context) => showToast(context, roomNotYet);

bool roomLoggedOut(AppServices services) => switch (services.environment.account) {
  LoggedOut() || LoginExpired() => true,
  _ => false,
};

/// Bilibili's "needs a login", or the room model's own refusal of a logged-out write.
bool liveNeedsLogin(Object error) =>
    (error is BiliError && error.needsLogin) || error is LiveNotLoggedIn;

/// Runs [action] for a logged-in viewer: logged out it opens the login page instead, as does a refusal that needs a
/// login; any other failure toasts.
Future<void> roomWrite(BuildContext context, Future<void> Function() action) async {
  if (roomLoggedOut(AppScope.of(context))) {
    await requestLiveLogin(context);
    return;
  }
  try {
    await action();
  } catch (error) {
    if (!context.mounted) return;
    if (liveNeedsLogin(error)) {
      await requestLiveLogin(context);
    } else {
      showToast(context, ActionsModel.failureMessage(error));
    }
  }
}

/// The 弹幕 input (on its emote panel with [emotes]), through the login page when logged out.
Future<void> openRoomSend(BuildContext context, LiveOverlays overlays, {bool emotes = false}) async {
  if (roomLoggedOut(AppScope.of(context))) {
    await requestLiveLogin(context);
    return;
  }
  overlays.openSend(emotes: emotes);
}

/// The header's online count: 9349, then 1万+.
String roomOnlineCount(int count) => count < 10000 ? '$count' : '${count ~/ 10000}万+';
