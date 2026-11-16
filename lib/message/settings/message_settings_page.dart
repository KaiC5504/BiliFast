import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_environment.dart';
import '../../app/app_scope.dart';
import '../../shared/toast.dart';
import '../../skin/skin.dart';
import '../message_model.dart';
import '../message_routes.dart';
import 'message_settings_parts.dart';
import 'notice_picker_page.dart';

/// 消息设置 (188). 消息提醒 is [MessageModel.badgeOn]; 回复与@, 收到喜欢 and 新增粉丝 show the account's choice and open
/// their pickers, asking for the login first while logged out or once Bilibili answers -101; every other row is drawn
/// and toasts.
class MessageSettingsPage extends StatefulWidget {
  const MessageSettingsPage({super.key, @visibleForTesting this.skin});

  /// [AppScope]'s by default.
  final ValueListenable<Skin?>? skin;

  @override
  State<MessageSettingsPage> createState() => _MessageSettingsPageState();
}

class _MessageSettingsPageState extends State<MessageSettingsPage> {
  AppServices? _services;
  Map<NoticeSettingKind, NoticeAudience>? _settings;
  bool _unsupported = false;

  /// Bilibili answered -101 since the last login here, though the app may still read logged in.
  bool _loginGone = false;
  bool _askingLogin = false;

  /// The switch as last flipped, shown until the model has it.
  bool? _badgeFlipped;
  int _badgeFlips = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = AppScope.of(context);
    if (_needsLogin) {
      // The login page can't be pushed while this one is still building.
      SchedulerBinding.instance.addPostFrameCallback((_) => unawaited(_login()));
    } else {
      unawaited(_read());
    }
  }

  bool get _needsLogin =>
      _loginGone ||
      switch (_services!.environment.account) {
        LoggedOut() || LoginExpired() => true,
        _ => false,
      };

  /// Back logged in, the settings are read again; the row that asked doesn't open.
  Future<void> _login() async {
    final services = _services!;
    if (_askingLogin || !mounted) return;
    _askingLogin = true;
    final bool loggedIn;
    try {
      loggedIn = await services.loginGate.request(context);
    } finally {
      _askingLogin = false;
    }
    if (!loggedIn || !mounted) return;
    _loginGone = false;
    await _read();
  }

  /// [quiet] for the read back after a picker, which has already told of its own failures and asked its own login.
  Future<void> _read({bool quiet = false}) async {
    try {
      final settings = await _services!.messageApi.noticeSettings();
      if (mounted) setState(() => _settings = settings);
    } on UnsupportedError {
      if (mounted) setState(() => _unsupported = true);
    } catch (error) {
      Logger.shared.warn(LogCategory.app, 'notice settings not read', {'error': '${error.runtimeType}'});
      if (!mounted) return;
      if (error is BiliError && error.needsLogin) {
        _loginGone = true;
        if (!quiet) unawaited(_login());
      } else if (!quiet) {
        showToast(context, '加载失败，请稍后重试');
      }
    }
  }

  void _soon() => showToast(context, '暂未开放');

  void _open(NoticeSettingKind kind) {
    if (_unsupported) {
      _soon();
      return;
    }
    if (_needsLogin) {
      unawaited(_login());
      return;
    }
    // The picker may have changed it; what it wrote is read back rather than passed.
    unawaited(
      openNoticePicker(context, kind).then((_) {
        if (mounted && !_needsLogin) unawaited(_read(quiet: true));
      }),
    );
  }

  Future<void> _flipBadge(MessageModel messages, bool on) async {
    final flip = ++_badgeFlips;
    setState(() => _badgeFlipped = on);
    Logger.shared.info(LogCategory.ui, 'settings message', {'key': 'badge', 'value': '$on'});
    try {
      await messages.setBadgeOn(on);
    } catch (error) {
      Logger.shared.warn(LogCategory.app, 'message badge not saved', {'error': '${error.runtimeType}'});
      if (mounted && flip == _badgeFlips) showToast(context, '设置失败，请稍后重试');
    }
    if (mounted && flip == _badgeFlips) setState(() => _badgeFlipped = null);
  }

  @override
  Widget build(BuildContext context) {
    final messages = AppScope.of(context).messages;
    final settings = _settings;
    Widget notice(NoticeSettingKind kind) {
      final audience = settings?[kind];
      return MessageSettingsLinkRow(
        key: ValueKey('message-settings-${kind.name}'),
        title: kind.title,
        subtitle: kind.subtitle,
        value: audience == null ? null : kind.wordFor(audience),
        onTap: () => _open(kind),
      );
    }

    return MessageSettingsScaffold(
      title: '消息设置',
      skin: widget.skin,
      children: [
        MessageSettingsGroup(
          children: [
            ListenableBuilder(
              listenable: messages,
              builder: (context, _) => MessageSettingsSwitchRow(
                key: const ValueKey('message-settings-badge'),
                title: '消息提醒',
                subtitle: '关闭后，APP首页将不再进行数字提醒',
                value: _badgeFlipped ?? messages.badgeOn,
                onChanged: (on) => unawaited(_flipBadge(messages, on)),
              ),
            ),
          ],
        ),
        MessageSettingsGroup(
          label: '消息接收设置',
          children: [
            MessageSettingsSwitchRow(
              key: const ValueKey('message-settings-intercept'),
              title: '私信智能拦截',
              subtitle: '开启后，将自动拦截疑似骚扰和不良的会话',
              // Bilibili's default, as 188 shows it; the account's own isn't read.
              value: true,
              onChanged: (_) => _soon(),
            ),
            MessageSettingsLinkRow(
              key: const ValueKey('message-settings-block-words'),
              title: '消息屏蔽词',
              subtitle: '添加后，将不再接受包含屏蔽词的消息',
              onTap: _soon,
            ),
          ],
        ),
        MessageSettingsGroup(label: '互动通知', children: [for (final kind in NoticeSettingKind.values) notice(kind)]),
        MessageSettingsGroup(
          label: '应援团和未关注人',
          children: [
            MessageSettingsLinkRow(
              key: const ValueKey('message-settings-support'),
              title: '应援团消息',
              value: '接收消息',
              onTap: _soon,
            ),
            MessageSettingsLinkRow(key: const ValueKey('message-settings-strangers'), title: '未关注人消息', onTap: _soon),
          ],
        ),
        MessageSettingsGroup(
          label: '联系人',
          children: [
            MessageSettingsLinkRow(key: const ValueKey('message-settings-blacklist'), title: '黑名单', onTap: _soon),
          ],
        ),
      ],
    );
  }
}
