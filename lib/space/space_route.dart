import 'package:flutter/widgets.dart';

import '../app/swipe_back_route.dart';
import 'space_page.dart';
import 'uploader_tap.dart';

/// Every way into UP主空间 comes through here.
Future<void> openSpace(BuildContext context, UploaderRef uploader) =>
    Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => SpacePage(uploader: uploader)));
