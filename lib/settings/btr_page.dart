import 'package:bili_core/devlog.dart';
import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../shared/theme.dart';
import '../video/player_prefs.dart';
import 'settings_page.dart';

/// 设置 → BTR: the download engine's switch and its CDN nodes, with BTR's licence note.
class BtrPage extends StatefulWidget {
  const BtrPage({super.key, this.prefs});

  /// [PlayerPrefs.shared] unless a test passes its own.
  final PlayerPrefs? prefs;

  @override
  State<BtrPage> createState() => _BtrPageState();
}

class _BtrPageState extends State<BtrPage> {
  PlayerPrefs get _prefs => widget.prefs ?? PlayerPrefs.shared;

  void _setNode(NodeChoice choice) {
    if (choice == _prefs.node) return;
    setState(() => _prefs.node = choice);
    Logger.shared.info(LogCategory.ui, 'settings node', {'node': choice.name});
    // A cold start reads the saved node; the engine running now, or starting now, is told.
    AppScope.of(context).playback.setNodeMode(choice.mode);
  }

  @override
  Widget build(BuildContext context) {
    final footerStyle = SettingsSection.footerStyle;
    return SettingsScaffold(
      title: 'BTR',
      children: [
        SettingsSection(
          children: [
            SettingsSwitchRow(
              key: const ValueKey('btr-switch'),
              title: 'BTR 加速',
              value: _prefs.btr,
              onChanged: (on) => setState(() => _prefs.btr = on),
            ),
          ],
        ),
        SettingsSection(
          label: 'CDN 节点',
          look: SettingsSectionLook.labelled,
          footer: '从下一个视频开始使用。',
          children: [
            for (final choice in NodeChoice.values)
              SettingsPickRow(
                key: ValueKey('node-${choice.name}'),
                title: choice.label,
                chosen: choice == _prefs.node,
                onTap: () => _setNode(choice),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SettingsTheme.rowInset,
            BiliMetrics.settingsSectionGap,
            SettingsTheme.rowInset,
            BiliMetrics.settingsSectionGap,
          ),
          // Under the Scaffold's Material, whose style the strut takes.
          child: Builder(
            builder: (context) => Text(
              '下载加速移植自 Bilibili 线程撕裂者（BTR），MIT 许可。',
              key: const ValueKey('btr-licence'),
              style: footerStyle,
              strutStyle: BiliFonts.strutOf(context, footerStyle),
            ),
          ),
        ),
      ],
    );
  }
}
