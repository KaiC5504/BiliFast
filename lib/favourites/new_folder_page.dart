import 'package:bili_core/api.dart' show FavFolder;
import 'package:flutter/material.dart';

import '../app/swipe_back_route.dart';

typedef CreateFolder = Future<FavFolder> Function({required String title, required String intro, required bool isPrivate});

/// 创建 (100): 封面, 名称 (required), 简介 and 公开; 完成 creates the folder and pops with it.
class NewFolderPage extends StatelessWidget {
  const NewFolderPage({super.key, required this.create});

  final CreateFolder create;

  @override
  Widget build(BuildContext context) => const Scaffold();
}

/// 我的收藏's + and 新建收藏夹, and 稍后再看's folder sheet: completes with the folder made, or null.
Future<FavFolder?> openNewFolder(BuildContext context, {required CreateFolder create}) =>
    Navigator.of(context).push<FavFolder>(SwipeBackPageRoute(builder: (_) => NewFolderPage(create: create)));
