import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import 'actions/video_actions.dart';
import 'page_api.dart';
import 'page_details.dart';
import 'page_session.dart' show PeriodicTimer;
import 'player_session.dart';

/// Contracts stub: nothing loads until the models agent fills it in.
class VideoPageDetailsModel extends ChangeNotifier implements PageDetails {
  VideoPageDetailsModel({
    required PlayerSession session,
    required PageApi api,
    required bool Function() isLoggedIn,
    required int? Function() accountMid,
    required VoidCallback requestLogin,
    required void Function(String message) toast,
    bool dislikeAvailable = false,
    PeriodicTimer? periodic,
    Logger? logger,
  });

  @override
  VideoActions? get actions => null;

  @override
  UploaderCard? get uploader => null;

  @override
  List<VideoTag> get tags => const [];

  final ValueNotifier<String?> _online = ValueNotifier(null);

  @override
  ValueListenable<String?> get online => _online;

  @override
  Future<ActionResult> watchLater(VideoCard card) async => const ActionResult('', ok: false);

  @override
  set active(bool value) {}

  @override
  void dispose() {
    _online.dispose();
    super.dispose();
  }
}
