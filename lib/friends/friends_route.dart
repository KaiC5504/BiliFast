import 'package:flutter/widgets.dart';

import '../shared/toast.dart';

/// 我的好友's two tabs (163, 165).
enum FriendsTab { following, fans }

/// Opens 我的好友 on [tab], from 我的's 关注 and 粉丝 counts and the own space's.
Future<void> openFriends(BuildContext context, {FriendsTab tab = FriendsTab.following}) async {
  showToast(context, '我的好友');
}
