import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../app/swipe_back_route.dart';
import '../shared/menu.dart';
import '../shared/theme.dart';
import 'font_page.dart';

/// 设置: only 字体 so far; the rest of BiliNative's SettingsView moves in with its slice.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final fonts = AppScope.of(context).fonts;
    return SettingsScaffold(
      title: '设置',
      children: [
        SettingsSection(
          children: [
            ListenableBuilder(
              listenable: fonts,
              builder: (context, _) => SettingsRow(
                key: const ValueKey('settings-font'),
                title: '字体',
                value: fonts.label,
                onTap: () => unawaited(
                  Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => FontPage(fonts: fonts))),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A settings page: the white bar with its title over the grey page, sections stacked below.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: BiliColors.pageGrey,
    appBar: AppBar(
      backgroundColor: BiliColors.card,
      surfaceTintColor: BiliColors.card,
      centerTitle: true,
      title: Text(
        title,
        style: const TextStyle(fontSize: BiliMetrics.titleText, color: BiliColors.text),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.only(top: BiliMetrics.settingsSectionGap),
      children: children,
    ),
  );
}

/// White rows with hairlines between them, a gap below.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.children, this.footer});

  final List<Widget> children;

  /// Grey text under the section.
  final String? footer;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: BiliMetrics.settingsSectionGap),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: BiliColors.card,
          child: Column(
            children: [
              for (final (index, child) in children.indexed) ...[
                if (index > 0)
                  const Divider(height: 0.5, thickness: 0.5, indent: BiliMetrics.sectionGap, color: BiliColors.divider),
                child,
              ],
            ],
          ),
        ),
        if (footer case final footer?)
          Padding(
            padding: const EdgeInsets.fromLTRB(BiliMetrics.sectionGap, BiliMetrics.rowGap, BiliMetrics.sectionGap, 0),
            child: Text(
              footer,
              style: const TextStyle(fontSize: BiliMetrics.smallText, color: BiliColors.secondaryText),
            ),
          ),
      ],
    ),
  );
}

/// A row that opens a page: its title, the current value in grey, and a chevron.
class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required this.title, required this.onTap, this.value});

  final String title;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      button: true,
      child: PressHighlight(
        onTap: onTap,
        child: SizedBox(
          height: BiliMetrics.settingsRowHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: BiliMetrics.sectionGap, right: BiliMetrics.gutter),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.text),
                  ),
                ),
                if (value case final value?)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: BiliMetrics.settingsValueWidth),
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: BiliMetrics.settingsValueText, color: BiliColors.secondaryText),
                    ),
                  ),
                const Icon(Icons.chevron_right, size: BiliMetrics.settingsChevron, color: BiliColors.secondaryText),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
