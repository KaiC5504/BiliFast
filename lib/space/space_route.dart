import 'package:flutter/widgets.dart';

import '../app/app_scope.dart';
import '../app/swipe_back_route.dart';
import 'own/own_space_page.dart';
import 'space_page.dart';
import 'uploader_tap.dart';

/// Every way into UP主空间 comes through here; the logged-in account's own mid opens its own space.
Future<void> openSpace(BuildContext context, UploaderRef uploader) {
  final own = AppScope.of(context).environment.mid == uploader.mid;
  return Navigator.of(context).push(
    SwipeBackPageRoute<void>(
      builder: (_) => own ? OwnSpacePage(uploader: uploader) : SpacePage(uploader: uploader),
    ),
  );
}
