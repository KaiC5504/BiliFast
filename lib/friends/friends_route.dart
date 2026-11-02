import 'package:flutter/widgets.dart';

import '../app/swipe_back_route.dart';
import 'friends_page.dart';

/// 我的好友's two tabs (163, 165).
enum FriendsTab { following, fans }

/// Opens 我的好友 on [tab], from 我的's 关注 and 粉丝 counts and the own space's.
Future<void> openFriends(BuildContext context, {FriendsTab tab = FriendsTab.following}) =>
    Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => FriendsPage(initialTab: tab)));
