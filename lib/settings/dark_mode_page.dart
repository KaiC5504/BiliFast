import 'dart:async';

import 'package:flutter/widgets.dart';

import '../app/appearance.dart';
import '../shared/theme.dart';
import 'settings_page.dart';

/// 设置 → 深色设置 (249): 深色跟随系统, dark whenever iOS is.
class DarkModePage extends StatefulWidget {
  const DarkModePage({super.key, required this.model});

  final AppearanceModel model;

  @override
  State<DarkModePage> createState() => _DarkModePageState();
}

class _DarkModePageState extends State<DarkModePage> {
  // The model tells only of a change of mode, so a switch that leaves the mode as it was redraws itself.
  void _set(bool on) {
    unawaited(widget.model.setFollowSystem(on));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
    title: '深色设置',
    children: [
      SettingsSection(
        look: const SettingsSectionLook(rule: DarkModeTheme.rule),
        children: [
          SettingsSwitchRow(
            key: const ValueKey('dark-follow-system'),
            title: '深色跟随系统',
            subtitle: '开启后，将跟随系统打开或关闭深色模式',
            tallHeight: DarkModeTheme.rowHeight,
            value: widget.model.followSystem,
            onChanged: _set,
          ),
        ],
      ),
    ],
  );
}
