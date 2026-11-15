import 'package:flutter/widgets.dart';

import 'app_icon.dart';
import 'settings_page.dart';

/// 设置 → 应用图标: a row per [AppIconChoice] with its picture, its name and a tick on the current one.
class AppIconPage extends StatefulWidget {
  const AppIconPage({super.key, required this.host});

  final AppIconHost host;

  @override
  State<AppIconPage> createState() => _AppIconPageState();
}

class _AppIconPageState extends State<AppIconPage> {
  @override
  Widget build(BuildContext context) => const SettingsScaffold(title: '应用图标', children: []);
}
