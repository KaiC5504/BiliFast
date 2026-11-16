import 'dart:async';
import 'dart:io' show Platform;

import 'package:bili_core/devlog.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl;

import '../notify/notify_host.dart';
import '../shared/menu.dart' show PressHighlight;
import '../shared/theme.dart';
import '../shared/toast.dart';
import '../video/intro/collection_row.dart' show Chevron;
import 'playback/playback_settings_page.dart' show showNotBuilt;
import 'settings_page.dart';

/// iOS's Settings at the app's own page (`UIApplication.openSettingsURLString`); nothing off the phone.
Future<bool> openAppSettings() async {
  if (!Platform.isIOS) return false;
  return launchUrl(Uri.parse('app-settings:'));
}

/// 推送设置's switches that are the phone's [NotifyKinds].
enum PushKind {
  likes('点赞'),
  replies('评论'),
  mentions('@'),
  messages('聊天消息'),
  uploads('关注up主的更新提醒');

  const PushKind(this.title);

  final String title;

  bool of(NotifyKinds kinds) => switch (this) {
    PushKind.likes => kinds.likes,
    PushKind.replies => kinds.replies,
    PushKind.mentions => kinds.mentions,
    PushKind.messages => kinds.messages,
    PushKind.uploads => kinds.uploads,
  };

  NotifyKinds set(NotifyKinds kinds, bool on) => switch (this) {
    PushKind.likes => kinds.copyWith(likes: on),
    PushKind.replies => kinds.copyWith(replies: on),
    PushKind.mentions => kinds.copyWith(mentions: on),
    PushKind.messages => kinds.copyWith(messages: on),
    PushKind.uploads => kinds.copyWith(uploads: on),
  };
}

/// 设置 → 推送设置 (189, 190). 接收通知总开关 says whether iOS lets the app notify and opens the app's page in iOS's
/// Settings; 点赞, 评论, @, 聊天消息 and 关注up主的更新提醒 are the [host]'s; every other row is drawn off and toasts.
class PushSettingsPage extends StatefulWidget {
  const PushSettingsPage({super.key, required this.host, @visibleForTesting this.openSettings = openAppSettings});

  final NotifyHost host;
  final Future<bool> Function() openSettings;

  @override
  State<PushSettingsPage> createState() => _PushSettingsPageState();
}

class _PushSettingsPageState extends State<PushSettingsPage> {
  late final AppLifecycleListener _lifecycle;
  NotifyKinds _kinds = NotifyKinds.none;
  NotifyPermission? _permission;
  bool _loaded = false;
  bool _asking = false;

  NotifyHost get _host => widget.host;

  @override
  void initState() {
    super.initState();
    // The user may have changed it in iOS's Settings meanwhile.
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_readPermission()));
    unawaited(_readKinds());
    unawaited(_readPermission());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _readKinds() async {
    try {
      final kinds = await _host.kinds();
      if (mounted) setState(() => _kinds = kinds);
    } catch (error) {
      Logger.shared.warn(LogCategory.app, 'notify kinds not read', {'error': '${error.runtimeType}'});
    } finally {
      _loaded = true;
    }
  }

  Future<void> _readPermission() async {
    try {
      final permission = await _host.permission();
      if (mounted) setState(() => _permission = permission);
    } catch (error) {
      Logger.shared.warn(LogCategory.app, 'notify permission not read', {'error': '${error.runtimeType}'});
    }
  }

  /// Whether iOS lets the app notify, asking first when it never has.
  Future<bool> _allowed() async {
    try {
      final permission = await _host.permission();
      if (permission != NotifyPermission.notDetermined) {
        if (mounted) setState(() => _permission = permission);
        return permission == NotifyPermission.allowed;
      }
      final granted = await _host.requestPermission();
      Logger.shared.info(LogCategory.ui, 'notify permission asked', {'granted': '$granted'});
      await _readPermission();
      return granted;
    } catch (error) {
      Logger.shared.warn(LogCategory.app, 'notify permission failed', {'error': '${error.runtimeType}'});
      return false;
    }
  }

  Future<void> _flip(PushKind kind, bool on) async {
    if (!_loaded || _asking) return;
    if (on && _host.available) {
      _asking = true;
      final allowed = await _allowed();
      _asking = false;
      if (!mounted) return;
      if (!allowed) {
        showToast(context, '请在系统设置中允许通知');
        return;
      }
    }
    final before = _kinds;
    final next = kind.set(before, on);
    setState(() => _kinds = next);
    Logger.shared.info(LogCategory.ui, 'settings push', {'key': kind.name, 'value': '$on'});
    try {
      await _host.setKinds(next);
    } catch (error) {
      Logger.shared.warn(LogCategory.app, 'notify kinds not saved', {'error': '${error.runtimeType}'});
      if (mounted && _kinds == next) setState(() => _kinds = before);
    }
  }

  void _openSettings() {
    Logger.shared.info(LogCategory.ui, 'settings push', {'key': 'openSettings'});
    unawaited(
      widget.openSettings().catchError((Object error) {
        Logger.shared.warn(LogCategory.app, 'app settings not opened', {'error': '${error.runtimeType}'});
        return false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    void soon() => showNotBuilt(context);
    Widget kept(PushKind kind) => SettingsSwitchRow(
      key: ValueKey('push-${kind.name}'),
      title: kind.title,
      value: kind.of(_kinds),
      onChanged: (on) => unawaited(_flip(kind, on)),
    );
    Widget drawn(String key, String title, {String? subtitle}) => SettingsSwitchRow(
      key: ValueKey('push-$key'),
      title: title,
      subtitle: subtitle,
      value: false,
      onChanged: (_) => soon(),
    );
    SettingsSection labelled(String label, List<Widget> rows) =>
        SettingsSection(look: SettingsSectionLook.labelled, label: label, children: rows);
    return SettingsScaffold(
      title: '推送设置',
      children: [
        SettingsSection(
          look: const SettingsSectionLook(top: SettingsListTheme.pushTop),
          children: [
            _LinkRow(
              key: const ValueKey('push-master'),
              title: '接收通知总开关',
              state: switch (_permission) {
                null => null,
                NotifyPermission.allowed => '[已开启]',
                _ => '[已关闭]',
              },
              subtitle: '请在您设备的“设置-通知”中，选择“BiliFast”进行修改',
              onTap: _openSettings,
            ),
            _LinkRow(key: const ValueKey('push-quiet'), title: '消息免打扰', subtitle: '开启后，免打扰时间内将不会收到推送消息', onTap: soon),
          ],
        ),
        labelled('互动通知', [kept(PushKind.likes), kept(PushKind.replies), kept(PushKind.mentions)]),
        labelled('私信通知', [kept(PushKind.messages)]),
        labelled('关注通知', [kept(PushKind.uploads)]),
        labelled('内容推荐', [drawn('recommend', '推荐可能感兴趣的内容'), drawn('hot', '热点'), drawn('events', '活动')]),
        labelled('订阅/预约通知', [
          drawn('bangumi', '追番追剧更新提醒'),
          drawn('live', '直播提醒'),
          drawn('collection', '订阅合集更新提醒'),
          drawn('search', '搜索内容更新提醒'),
          drawn('reserve', '其他订阅/预约提醒'),
        ]),
        labelled('UP主小助手', [drawn('creator', '投稿服务通知')]),
        labelled('服务通知', [drawn('orders', '物流与订单通知'), drawn('vip', '增值服务通知')]),
        labelled('其他通知', [drawn('security', '账号安全通知'), drawn('other', '其他通知')]),
        labelled('APP内通知横幅', [drawn('banner', '应用内顶部横幅提醒', subtitle: '开启后，应用使用期间会收到推送通知')]),
      ],
    );
  }
}

/// A row with a grey second line and a › (189's first two); a [state] follows the title in the second line's grey,
/// set a little lower.
class _LinkRow extends StatelessWidget {
  const _LinkRow({super.key, required this.title, required this.subtitle, required this.onTap, this.state});

  final String title;
  final String? state;
  final String subtitle;
  final VoidCallback onTap;

  static const _textRight = SettingsTheme.chevronRight + SettingsTheme.chevronWidth + SettingsTheme.valueGap;

  @override
  Widget build(BuildContext context) {
    final state = this.state;
    final grey = TextStyle(
      fontFamily: BiliFonts.family,
      fontSize: SettingsListTheme.subtitleText,
      color: SettingsListTheme.subtitle,
    );
    Widget greyText(String text) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: grey,
      strutStyle: BiliFonts.strutOf(context, grey),
    );
    return MergeSemantics(
      child: Semantics(
        button: true,
        onTap: onTap,
        child: PressHighlight(
          onTap: onTap,
          child: SizedBox(
            height: SettingsListTheme.switchTallHeight,
            child: Stack(
              children: [
                settingsLineAt(
                  centre: SettingsListTheme.switchTitleCentre,
                  left: SettingsTheme.rowInset,
                  right: _textRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: SettingsRow.titleText(title)),
                      if (state != null) ...[
                        const SizedBox(width: SettingsListTheme.pushStateGap),
                        Transform.translate(
                          offset: const Offset(0, SettingsListTheme.pushStateDrop),
                          child: greyText(state),
                        ),
                      ],
                    ],
                  ),
                ),
                settingsLineAt(
                  centre: SettingsListTheme.switchSubtitleCentre,
                  left: SettingsTheme.rowInset,
                  right: _textRight,
                  child: greyText(subtitle),
                ),
                const Positioned(
                  top: 0,
                  bottom: 0,
                  right: SettingsTheme.chevronRight,
                  child: Center(
                    child: Chevron(
                      size: Size(SettingsTheme.chevronWidth, SettingsTheme.chevronHeight),
                      stroke: SettingsTheme.chevronStroke,
                      color: SettingsTheme.chevron,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
