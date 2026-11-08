import 'package:flutter/material.dart';

import '../../video/player_prefs.dart';
import '../settings_page.dart';
import 'playback_settings_page.dart';

/// What each page calls an [AutoplayChoice].
extension AutoplayLabels on AutoplayChoice {
  /// 首页自动播放's (170, 172, 50).
  String get homeLabel => switch (this) {
    AutoplayChoice.always => 'Wi-Fi/免流/移动网络下自动播放',
    AutoplayChoice.wifiOnly => '仅Wi-Fi下自动播放',
    AutoplayChoice.off => '关闭自动播放',
  };

  /// 179's own rows: its second spells Wi–Fi with an en dash, where 170, 172 and 设置 keep the hyphen.
  String get homePickerLabel => switch (this) {
    AutoplayChoice.wifiOnly => '仅Wi–Fi下自动播放',
    _ => homeLabel,
  };

  /// 动态视频是否自动播放's (178).
  String get listLabel => switch (this) {
    AutoplayChoice.always => '开启自动播放',
    AutoplayChoice.wifiOnly => '仅WiFi/免流下自动播放',
    AutoplayChoice.off => '关闭自动播放',
  };
}

/// 播放设置 → 自动播放设置 (172): mobile data, the video page's start, and the lists' choices on their own pages.
class AutoplaySettingsPage extends StatefulWidget {
  const AutoplaySettingsPage({super.key, this.prefs});

  final PlayerPrefs? prefs;

  @override
  State<AutoplaySettingsPage> createState() => _AutoplaySettingsPageState();
}

class _AutoplaySettingsPageState extends State<AutoplaySettingsPage> {
  PlayerPrefs get _prefs => widget.prefs ?? PlayerPrefs.shared;

  void _flip(String key, bool on, void Function(PlayerPrefs prefs) change) {
    setState(() => change(_prefs));
    logPlaybackSetting(key, on);
  }

  void _openChoice(Widget Function(PlayerPrefs prefs) page) => openSettingsPage(
    context,
    (_) => page(_prefs),
    then: () {
      if (mounted) setState(() {});
    },
  );

  @override
  Widget build(BuildContext context) => SettingsScaffold(
    title: '自动播放设置',
    children: [
      SettingsSection(
        children: [
          SettingsSwitchRow(
            key: const ValueKey('autoplay-cellular'),
            title: '流量网络下自动播放',
            value: _prefs.cellularAutoplay,
            onChanged: (on) => _flip('cellularAutoplay', on, (prefs) => prefs.cellularAutoplay = on),
          ),
          SettingsSwitchRow(
            key: const ValueKey('autoplay-detail'),
            title: '详情页直接播放',
            subtitle: '进入视频详情页后自动播放视频',
            value: _prefs.detailAutoplay,
            onChanged: (on) => _flip('detailAutoplay', on, (prefs) => prefs.detailAutoplay = on),
          ),
          SettingsSwitchRow(
            key: const ValueKey('autoplay-detail-full-screen'),
            title: '详情页直接全屏播放',
            subtitle: '进入视频详情页后自动全屏播放视频',
            value: _prefs.detailFullScreen,
            onChanged: (on) => _flip('detailFullScreen', on, (prefs) => prefs.detailFullScreen = on),
          ),
          SettingsRow(
            key: const ValueKey('autoplay-list'),
            title: '动态/活动页单列视频是否自动播放',
            value: _prefs.listAutoplay.listLabel,
            onTap: () => _openChoice(
              (prefs) => AutoplayChoicePage.list(
                choice: prefs.listAutoplay,
                onChanged: (choice) {
                  prefs.listAutoplay = choice;
                  logPlaybackSetting('listAutoplay', choice.name);
                },
              ),
            ),
          ),
          SettingsRow(
            key: const ValueKey('autoplay-home'),
            title: '首页自动播放',
            value: _prefs.homeAutoplay.homeLabel,
            onTap: () => _openChoice(
              (prefs) => AutoplayChoicePage.home(
                choice: prefs.homeAutoplay,
                onChanged: (choice) {
                  prefs.homeAutoplay = choice;
                  logPlaybackSetting('homeAutoplay', choice.name);
                },
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

/// 动态视频是否自动播放 (178) or 首页自动播放 (179): the three [AutoplayChoice]s, picked with a tap.
class AutoplayChoicePage extends StatefulWidget {
  const AutoplayChoicePage.list({super.key, required this.choice, required this.onChanged})
    : title = '动态视频是否自动播放',
      note = '选择后，将影响所有列表场景下的视频播放',
      keyPrefix = 'list-autoplay',
      home = false;

  const AutoplayChoicePage.home({super.key, required this.choice, required this.onChanged})
    : title = '首页自动播放',
      note = null,
      keyPrefix = 'home-autoplay',
      home = true;

  final String title;
  final String? note;
  final String keyPrefix;
  final bool home;
  final AutoplayChoice choice;
  final ValueChanged<AutoplayChoice> onChanged;

  @override
  State<AutoplayChoicePage> createState() => _AutoplayChoicePageState();
}

class _AutoplayChoicePageState extends State<AutoplayChoicePage> {
  late AutoplayChoice _choice = widget.choice;

  void _pick(AutoplayChoice choice) {
    if (choice == _choice) return;
    setState(() => _choice = choice);
    widget.onChanged(choice);
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
    title: widget.title,
    children: [
      SettingsSection(
        look: widget.note == null ? SettingsSectionLook.picker : SettingsSectionLook.note,
        label: widget.note,
        children: [
          for (final choice in AutoplayChoice.values)
            SettingsPickRow(
              key: ValueKey('${widget.keyPrefix}-${choice.name}'),
              title: widget.home ? choice.homePickerLabel : choice.listLabel,
              chosen: choice == _choice,
              look: SettingsPickLook.picker,
              onTap: () => _pick(choice),
            ),
        ],
      ),
    ],
  );
}
