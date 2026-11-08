import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:flutter/material.dart';

import '../../app/swipe_back_route.dart';
import '../../shared/toast.dart';
import '../../video/player_prefs.dart';
import '../settings_page.dart';
import 'autoplay_settings_page.dart';

/// Logs a playback setting the user changed; the values are choices and switches, nothing of the account's.
void logPlaybackSetting(String key, Object value) =>
    Logger.shared.info(LogCategory.ui, 'settings playback', {'key': key, 'value': '$value'});

void showNotBuilt(BuildContext context) => showToast(context, '暂未开放');

/// Pushes a page under 设置 as 设置 does, and runs [then] when it is gone.
void openSettingsPage(BuildContext context, WidgetBuilder builder, {VoidCallback? then}) =>
    unawaited(Navigator.of(context).push(SwipeBackPageRoute<void>(builder: builder)).then((_) => then?.call()));

/// 设置 → 播放设置 (171): 自动播放设置, 竖屏模式设置 and 小窗播放/后台听视频设置 open their pages; 弹幕/字幕设置, 清晰度设置
/// and 其它设置 aren't built.
class PlaybackSettingsPage extends StatelessWidget {
  const PlaybackSettingsPage({super.key, this.prefs});

  /// [PlayerPrefs.shared] unless a test passes its own.
  final PlayerPrefs? prefs;

  @override
  Widget build(BuildContext context) {
    void soon() => showNotBuilt(context);
    return SettingsScaffold(
      title: '播放设置',
      children: [
        SettingsSection(
          children: [
            SettingsRow(
              key: const ValueKey('playback-autoplay'),
              title: '自动播放设置',
              onTap: () => openSettingsPage(context, (_) => AutoplaySettingsPage(prefs: prefs)),
            ),
            SettingsRow(
              key: const ValueKey('playback-vertical'),
              title: '竖屏模式设置',
              onTap: () => openSettingsPage(context, (_) => VerticalModeSettingsPage(prefs: prefs)),
            ),
            SettingsRow(
              key: const ValueKey('playback-pip'),
              title: '小窗播放/后台听视频设置',
              onTap: () => openSettingsPage(context, (_) => PipSettingsPage(prefs: prefs)),
            ),
            SettingsRow(key: const ValueKey('playback-danmaku'), title: '弹幕/字幕设置', onTap: soon),
            SettingsRow(key: const ValueKey('playback-quality'), title: '清晰度设置', onTap: soon),
            SettingsRow(key: const ValueKey('playback-other'), title: '其它设置', onTap: soon),
          ],
        ),
      ],
    );
  }
}

/// 播放设置 → 竖屏模式设置 (173): whether an upright video's full screen is 竖屏.
class VerticalModeSettingsPage extends StatefulWidget {
  const VerticalModeSettingsPage({super.key, this.prefs});

  final PlayerPrefs? prefs;

  @override
  State<VerticalModeSettingsPage> createState() => _VerticalModeSettingsPageState();
}

class _VerticalModeSettingsPageState extends State<VerticalModeSettingsPage> {
  PlayerPrefs get _prefs => widget.prefs ?? PlayerPrefs.shared;

  @override
  Widget build(BuildContext context) => SettingsScaffold(
    title: '竖屏模式设置',
    children: [
      SettingsSection(
        children: [
          SettingsSwitchRow(
            key: const ValueKey('vertical-full-screen'),
            title: '竖屏视频全屏用竖屏模式播放',
            subtitle: '全屏后可以上下滑视频',
            value: _prefs.verticalFullScreen,
            onChanged: (on) {
              setState(() => _prefs.verticalFullScreen = on);
              logPlaybackSetting('verticalFullScreen', on);
            },
          ),
        ],
      ),
    ],
  );
}

/// 播放设置 → 小窗播放/后台听视频设置 (174). 应用外自动小窗播放 and both 后台听视频 rows are ours to change (后台听视频 is
/// the same setting as the video page's ⋮ row); 应用内自动小窗播放 stays off and toasts, since a covered page pauses
/// and gives up its small window.
class PipSettingsPage extends StatefulWidget {
  const PipSettingsPage({super.key, this.prefs});

  final PlayerPrefs? prefs;

  @override
  State<PipSettingsPage> createState() => _PipSettingsPageState();
}

class _PipSettingsPageState extends State<PipSettingsPage> {
  PlayerPrefs get _prefs => widget.prefs ?? PlayerPrefs.shared;

  void _flip(String key, bool on, void Function(PlayerPrefs prefs) change) {
    setState(() => change(_prefs));
    logPlaybackSetting(key, on);
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
    title: '小窗播放/后台听视频设置',
    children: [
      SettingsSection(
        look: SettingsSectionLook.labelled,
        label: '小窗播放设置',
        children: [
          SettingsSwitchRow(
            key: const ValueKey('pip-outside'),
            title: '应用外自动小窗播放',
            subtitle: '切出APP时自动出小窗，继续播放视频/直播',
            value: _prefs.autoPip,
            onChanged: (on) => _flip('autoPip', on, (prefs) => prefs.autoPip = on),
          ),
          SettingsSwitchRow(
            key: const ValueKey('pip-inside'),
            title: '应用内自动小窗播放',
            subtitle: '切到APP内其他页面时出小窗，继续播放视频',
            value: false,
            onChanged: (_) => showNotBuilt(context),
          ),
        ],
      ),
      SettingsSection(
        look: SettingsSectionLook.labelled,
        label: '后台听视频设置',
        children: [
          SettingsSwitchRow(
            key: const ValueKey('pip-background'),
            title: '后台听视频',
            subtitle: '锁屏或切到后台时，继续播放视频声音',
            value: _prefs.backgroundListen,
            onChanged: (on) => _flip('backgroundListen', on, (prefs) => prefs.backgroundListen = on),
          ),
          SettingsSwitchRow(
            key: const ValueKey('pip-background-next'),
            title: '后台听视频时，自动连播相关视频',
            value: _prefs.backgroundNext,
            onChanged: (on) => _flip('backgroundNext', on, (prefs) => prefs.backgroundNext = on),
          ),
        ],
      ),
    ],
  );
}
