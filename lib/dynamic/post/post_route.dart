import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../app/swipe_back_route.dart';
import 'post_page.dart';

/// Opens a post on its own page (131-134, 140), from the right with 正在努力加载... (133) until [item]'s detail is in.
/// [toComments] scrolls to 评论 once it shows.
Future<void> openDynamicPost(BuildContext context, {required String id, DynamicItem? item, bool toComments = false}) =>
    Navigator.of(context).push(
      SwipeBackPageRoute<void>(
        builder: (_) => DynamicPostPage(id: id, item: item, toComments: toComments),
      ),
    );
