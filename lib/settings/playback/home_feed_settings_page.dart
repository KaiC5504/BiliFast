import 'package:flutter/material.dart';

import '../../shared/theme.dart';
import '../../video/player_prefs.dart';
import '../settings_page.dart';
import 'autoplay_settings_page.dart';
import 'playback_settings_page.dart';

/// 设置 → 首页推荐设置 (170). 首页自动播放 and 大卡默认声音 change; the rest show what 首页 does: it picks a video's
/// player by the video (自动模式), and 推荐 refreshes only when asked (a pull, 首页 or the account changing), never by
/// itself on a return to the app.
class HomeFeedSettingsPage extends StatefulWidget {
  const HomeFeedSettingsPage({super.key, this.prefs});

  /// [PlayerPrefs.shared] unless a test passes its own.
  final PlayerPrefs? prefs;

  @override
  State<HomeFeedSettingsPage> createState() => _HomeFeedSettingsPageState();
}

class _HomeFeedSettingsPageState extends State<HomeFeedSettingsPage> {
  PlayerPrefs get _prefs => widget.prefs ?? PlayerPrefs.shared;

  void _soon() => showNotBuilt(context);

  void _setAutoplay(AutoplayChoice choice) {
    if (choice == _prefs.homeAutoplay) return;
    setState(() => _prefs.homeAutoplay = choice);
    logPlaybackSetting('homeAutoplay', choice.name);
  }

  void _setSound(bool on) {
    if (on == _prefs.bigCardSound) return;
    setState(() => _prefs.bigCardSound = on);
    logPlaybackSetting('bigCardSound', on);
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
    title: '首页推荐设置',
    children: [
      SettingsSection(
        look: SettingsSectionLook.feed,
        label: '首页视频播放模式',
        children: [
          SettingsPickRow(
            key: const ValueKey('home-feed-mode-vertical'),
            title: '竖屏模式',
            subtitle: '默认用竖屏模式播放视频',
            chosen: false,
            onTap: _soon,
          ),
          SettingsPickRow(
            key: const ValueKey('home-feed-mode-auto'),
            title: '自动模式',
            subtitle: '根据视频类型自动选择播放模式',
            chosen: true,
            onTap: () {},
          ),
        ],
      ),
      SettingsSection(
        look: SettingsSectionLook.feed,
        label: '首页自动播放',
        children: [
          for (final choice in AutoplayChoice.values)
            SettingsPickRow(
              key: ValueKey('home-feed-autoplay-${choice.name}'),
              title: choice.homeLabel,
              chosen: choice == _prefs.homeAutoplay,
              onTap: () => _setAutoplay(choice),
            ),
        ],
      ),
      SettingsSection(
        look: SettingsSectionLook.feed,
        label: '大卡默认声音（重启后生效）',
        children: [
          SettingsPickRow(
            key: const ValueKey('home-feed-sound-on'),
            title: '默认打开',
            chosen: _prefs.bigCardSound,
            onTap: () => _setSound(true),
          ),
          SettingsPickRow(
            key: const ValueKey('home-feed-sound-muted'),
            title: '默认静音',
            chosen: !_prefs.bigCardSound,
            onTap: () => _setSound(false),
          ),
        ],
      ),
      SettingsSection(
        look: SettingsSectionLook.feed,
        label: '首页推荐自动刷新',
        children: [
          SettingsPickRow(key: const ValueKey('home-feed-refresh-on'), title: '开启', chosen: false, onTap: _soon),
          SettingsPickRow(key: const ValueKey('home-feed-refresh-off'), title: '关闭', chosen: true, onTap: () {}),
        ],
      ),
      SettingsSection(
        look: SettingsSectionLook.feedLink,
        children: [
          SettingsRow(
            key: const ValueKey('home-feed-columns'),
            title: '首页单双列切换',
            height: SettingsListTheme.feedLinkHeight,
            onTap: _soon,
          ),
        ],
      ),
    ],
  );
}
