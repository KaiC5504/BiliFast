import 'package:flutter/widgets.dart';

import '../space_page.dart';
import '../uploader_tap.dart';

/// The account's own space (108, 114-117): the tall themed banner, 编辑资料, the level's exp, and 主页 / 投稿 / 收藏 /
/// 追番, collapsing to the black bar with the tab row pinned (115).
class OwnSpacePage extends StatelessWidget {
  const OwnSpacePage({super.key, required this.uploader});

  final UploaderRef uploader;

  @override
  Widget build(BuildContext context) => SpacePage(uploader: uploader);
}
