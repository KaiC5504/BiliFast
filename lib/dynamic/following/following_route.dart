import 'package:flutter/widgets.dart';

import '../../app/swipe_back_route.dart';
import 'following_page.dart';

/// Opens 我的关注 (129) from 最常访问's 更多.
Future<void> openFollowingList(BuildContext context) =>
    Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => const FollowingListPage()));
