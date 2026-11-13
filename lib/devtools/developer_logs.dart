import 'package:flutter/material.dart';

import '../settings/settings_page.dart';
import '../shared/theme.dart';
import 'developer_rows.dart';
import 'log_forwarder.dart';
import 'log_server_discovery.dart';

/// 开发者's 日志: 发送日志到电脑 with the PCs found over Bonjour and a typed address, then 导出日志, 清除日志 and 测试崩溃.
class DeveloperLogs extends StatelessWidget {
  const DeveloperLogs({
    super.key,
    required this.logs,
    required this.address,
    required this.exporting,
    required this.onExport,
    required this.onClear,
    required this.onCrash,
  });

  /// Null leaves the forwarder out.
  final LogForwarder? logs;
  final TextEditingController address;
  final bool exporting;

  /// [origin] is the row, where an iPad points the share sheet.
  final void Function(Rect? origin) onExport;
  final VoidCallback onClear;
  final VoidCallback onCrash;

  static Rect? _originOf(BuildContext context) {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
  }

  @override
  Widget build(BuildContext context) {
    final logs = this.logs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (logs != null)
          ListenableBuilder(
            listenable: logs,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsSection(
                  children: [
                    SettingsSwitchRow(
                      key: const ValueKey('log-switch'),
                      title: '发送日志到电脑',
                      value: logs.enabled,
                      onChanged: logs.setEnabled,
                    ),
                    if (logs.enabled) ...[
                      for (final server in logs.discovered) _serverRow(logs, server),
                      _AddressRow(logs: logs, address: address),
                    ],
                  ],
                ),
                DeveloperFootnote(
                  children: [
                    DeveloperFootnote.line(logs.status, key: const ValueKey('log-status')),
                    DeveloperFootnote.line('在电脑上运行 uv run tools/logserver.py，手机和电脑连同一个 Wi-Fi。'),
                  ],
                ),
              ],
            ),
          ),
        SettingsSection(
          children: [
            Builder(
              builder: (row) => SettingsRow(
                key: const ValueKey('log-export'),
                title: '导出日志',
                value: exporting ? '准备中…' : '最近 20 MB',
                enabled: !exporting,
                onTap: () => onExport(_originOf(row)),
              ),
            ),
            SettingsRow(key: const ValueKey('dev-clear-logs'), title: '清除日志', onTap: onClear),
            DeveloperActionRow(
              key: const ValueKey('test-crash'),
              title: '测试崩溃',
              color: DevToolsTheme.crashInk,
              onTap: onCrash,
            ),
          ],
        ),
      ],
    );
  }

  /// Tapping the chosen PC again goes back to the typed address.
  static Widget _serverRow(LogForwarder logs, LogServerEndpoint server) {
    final selected = logs.service?.host == server.host && logs.service?.port == server.port;
    return DeveloperCheckRow(
      key: ValueKey('log-server-${server.name}'),
      title: server.name,
      value: '${server.host}:${server.port}',
      selected: selected,
      onTap: () => logs.selectService(selected ? null : server),
    );
  }
}

/// The address typed by hand, taken when 连接 is pressed or the field submitted, not per keystroke.
class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.logs, required this.address});

  final LogForwarder logs;
  final TextEditingController address;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontFamily: BiliFonts.family, fontSize: DevToolsTheme.fieldText, color: BiliColors.text);
    return SizedBox(
      height: SettingsSection.rowHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: SettingsTheme.rowInset, right: SettingsTheme.chevronRight),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextField(
                  key: const ValueKey('log-address'),
                  controller: address,
                  keyboardType: TextInputType.url,
                  onSubmitted: logs.setManual,
                  style: style,
                  decoration: InputDecoration.collapsed(
                    hintText: '手动输入 IP:端口（默认 ${LogServerEndpoint.defaultPort}）',
                    hintStyle: style.copyWith(color: DevToolsTheme.fieldHint),
                  ),
                ),
              ),
            ),
            DeveloperTextButton(
              key: const ValueKey('log-connect'),
              label: '连接',
              onTap: () => logs.setManual(address.text),
            ),
          ],
        ),
      ),
    );
  }
}
