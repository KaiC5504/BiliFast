import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../../shared/toast.dart';
import '../../skin/skin.dart';
import '../message_api.dart';
import 'message_settings_parts.dart';

/// What 消息设置 (188) and the pickers (215, 216, 195) call each setting and choice.
extension NoticeSettingWords on NoticeSettingKind {
  /// 188's row.
  String get title => switch (this) {
    NoticeSettingKind.replies => '回复与@',
    NoticeSettingKind.likes => '收到喜欢',
    NoticeSettingKind.fans => '新增粉丝',
  };

  String get subtitle => switch (this) {
    NoticeSettingKind.replies => '你将收到这些人的评论、弹幕等通知提醒',
    NoticeSettingKind.likes => '是否接收点赞等通知提醒',
    NoticeSettingKind.fans => '是否接收新增粉丝通知提醒',
  };

  String get pickerTitle => '$title消息提醒';

  /// 新增粉丝 offers only on and off (195).
  List<NoticeAudience> get choices => switch (this) {
    NoticeSettingKind.fans => const [NoticeAudience.everyone, NoticeAudience.off],
    _ => NoticeAudience.values,
  };

  /// [audience] as one of [choices]: 新增粉丝 has no 关注的人, so that counts as on there.
  NoticeAudience shown(NoticeAudience audience) => choices.contains(audience) ? audience : NoticeAudience.everyone;

  /// The words for [audience], the same on the picker and on 188's row.
  String wordFor(NoticeAudience audience) => switch ((this, shown(audience))) {
    (NoticeSettingKind.fans, NoticeAudience.off) => '永不提醒',
    (NoticeSettingKind.fans, _) => '接收提醒',
    (_, NoticeAudience.everyone) => '所有人',
    (_, NoticeAudience.following) => '关注的人',
    (_, NoticeAudience.off) => '不接收任何消息提醒',
  };
}

/// A 消息提醒 picker: 回复与@ (215), 收到喜欢 (216), 新增粉丝 (195). It reads the account's choice as it opens; a tap
/// moves the ✓ at once and writes it, putting it back if the write fails.
class NoticePickerPage extends StatefulWidget {
  const NoticePickerPage({super.key, required this.kind, @visibleForTesting this.skin});

  final NoticeSettingKind kind;

  /// [AppScope]'s by default.
  final ValueListenable<Skin?>? skin;

  @override
  State<NoticePickerPage> createState() => _NoticePickerPageState();
}

class _NoticePickerPageState extends State<NoticePickerPage> {
  MessageApi? _api;
  NoticeAudience? _chosen;
  bool _picked = false;
  bool _writing = false;

  NoticeSettingKind get _kind => widget.kind;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_api != null) return;
    final api = _api = AppScope.of(context).messageApi;
    unawaited(_read(api));
  }

  Future<void> _read(MessageApi api) async {
    try {
      final settings = await api.noticeSettings();
      // A tap that landed first is newer than this answer.
      if (!mounted || _picked) return;
      final audience = settings[_kind];
      setState(() => _chosen = audience == null ? null : _kind.shown(audience));
    } catch (error) {
      Logger.shared.warn(LogCategory.app, 'notice settings not read', {
        'kind': _kind.name,
        'error': '${error.runtimeType}',
      });
      if (mounted) showToast(context, error is UnsupportedError ? '暂未开放' : '加载失败，请稍后重试');
    }
  }

  /// One write at a time: a tap while one is out is dropped, so a failure always puts back what was confirmed.
  Future<void> _pick(NoticeAudience audience) async {
    final api = _api;
    if (api == null || _writing || audience == _chosen) return;
    final before = _chosen;
    _picked = true;
    _writing = true;
    setState(() => _chosen = audience);
    Logger.shared.info(LogCategory.ui, 'settings message', {'key': _kind.name, 'value': audience.name});
    try {
      await api.setNoticeSetting(_kind, audience);
    } catch (error) {
      Logger.shared.warn(LogCategory.app, 'notice setting not saved', {
        'kind': _kind.name,
        'error': '${error.runtimeType}',
      });
      if (!mounted) return;
      setState(() => _chosen = before);
      showToast(context, error is UnsupportedError ? '暂未开放' : '设置失败，请稍后重试');
    } finally {
      _writing = false;
    }
  }

  @override
  Widget build(BuildContext context) => MessageSettingsScaffold(
    title: _kind.pickerTitle,
    skin: widget.skin,
    children: [
      MessageSettingsGroup(
        children: [
          for (final audience in _kind.choices)
            MessageSettingsChoiceRow(
              key: ValueKey('notice-picker-${audience.name}'),
              title: _kind.wordFor(audience),
              chosen: audience == _chosen,
              onTap: () => unawaited(_pick(audience)),
            ),
        ],
      ),
    ],
  );
}
