import 'package:flutter/material.dart';

/// 我的, the bottom bar's Me page (87, 106, 107), apart from the avatar's page (49).
class MePage extends StatefulWidget {
  const MePage({super.key, required this.active, this.developerPage});

  /// Whether 我的 is the bar's current tab; turning true is a showing ([MeModel.shown]).
  final bool active;

  /// Passed on to 设置 (更多服务's row), null leaves 开发者 out.
  final WidgetBuilder? developerPage;

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  @override
  Widget build(BuildContext context) => const ColoredBox(color: Color(0xFFFFFFFF));
}
