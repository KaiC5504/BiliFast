import 'package:bili_core/api.dart' show SpaceTabKind;
import 'package:flutter/widgets.dart';

import '../app/app_scope.dart';
import '../app/swipe_back_route.dart';
import 'own/own_space_page.dart';
import 'space_page.dart';
import 'uploader_tap.dart';

/// Every way into UP主空间 comes through here; the logged-in account's own mid opens its own space, on [ownTab] when
/// it has that tab.
Future<void> openSpace(BuildContext context, UploaderRef uploader, {SpaceTabKind? ownTab}) {
  final own = AppScope.of(context).environment.mid == uploader.mid;
  return Navigator.of(context).push(
    SwipeBackPageRoute<void>(
      builder: (_) => own ? OwnSpacePage(uploader: uploader, initialTab: ownTab) : SpacePage(uploader: uploader),
    ),
  );
}
