import 'package:flutter/widgets.dart';

import '../app/swipe_back_route.dart';
import 'space_page.dart';
import 'uploader_tap.dart';

/// Every way into UP主空间 comes through here: the sheet's 进入空间 and face, comments, @mentions, 搜索's 用户 rows.
Future<void> openSpace(BuildContext context, UploaderRef uploader) =>
    Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => SpacePage(uploader: uploader)));
