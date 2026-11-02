import 'package:flutter/material.dart';

import '../settings/settings_page.dart';
import '../shared/menu.dart';
import '../shared/theme.dart';

/// A titled group of 设置's sections: the grey title, then the sections, each with 设置's gap above it.
class DeveloperGroup extends StatelessWidget {
  const DeveloperGroup({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: BiliFonts.family,
      fontSize: DevToolsTheme.headerText,
      color: DevToolsTheme.header,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SettingsTheme.rowInset,
            DevToolsTheme.headerTop,
            SettingsTheme.rowInset,
            0,
          ),
          child: Transform.translate(
            offset: const Offset(0, DevToolsTheme.headerSink),
            child: Semantics(
              header: true,
              child: Text(title, style: style, strutStyle: BiliFonts.strutOf(context, style)),
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

/// A row that does something at once: its title in [color], no ›.
class DeveloperActionRow extends StatelessWidget {
  const DeveloperActionRow({super.key, required this.title, required this.onTap, this.color = DevToolsTheme.actionInk});

  final String title;

  /// Null greys the title and ignores taps.
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      button: true,
      enabled: onTap != null,
      child: PressHighlight(
        onTap: onTap,
        child: SizedBox(
          height: SettingsSection.rowHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: SettingsTheme.rowInset, right: SettingsTheme.chevronRight),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SettingsRow.titleText(title, color: onTap == null ? SettingsTheme.rowDisabled : color),
            ),
          ),
        ),
      ),
    ),
  );
}

/// One of a choice's rows, as CDN 节点's are: the title, a grey [value] when there is one, and a pink check on the
/// chosen.
class DeveloperCheckRow extends StatelessWidget {
  const DeveloperCheckRow({super.key, required this.title, this.value, required this.selected, required this.onTap});

  final String title;
  final String? value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    final valueStyle = TextStyle(
      fontFamily: BiliFonts.family,
      fontSize: BiliMetrics.settingsValueText,
      color: SettingsTheme.value,
    );
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        child: PressHighlight(
          onTap: onTap,
          child: SizedBox(
            height: SettingsSection.rowHeight,
            child: Padding(
              padding: const EdgeInsets.only(left: SettingsTheme.rowInset, right: SettingsTheme.chevronRight),
              child: Row(
                children: [
                  Expanded(child: SettingsRow.titleText(title)),
                  if (value != null)
                    Text(value, maxLines: 1, style: valueStyle, strutStyle: BiliFonts.strutOf(context, valueStyle)),
                  if (selected) ...[
                    const SizedBox(width: SettingsTheme.valueGap),
                    const Icon(Icons.check, size: BiliMetrics.fontCheck, color: BiliColors.pink),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small pink word at a row's end that acts, such as 连接.
class DeveloperTextButton extends StatelessWidget {
  const DeveloperTextButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: BiliFonts.family,
      fontSize: DevToolsTheme.fieldText,
      color: DevToolsTheme.actionInk,
    );
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: DevToolsTheme.fieldButtonPadding),
          child: Center(
            widthFactor: 1,
            child: Text(label, style: style, strutStyle: BiliFonts.strutOf(context, style)),
          ),
        ),
      ),
    );
  }
}

/// Grey lines under a section, set as 设置's footers are.
class DeveloperFootnote extends StatelessWidget {
  const DeveloperFootnote({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SettingsTheme.rowInset,
      SettingsTheme.footerTop,
      SettingsTheme.rowInset,
      SettingsTheme.footerBottom,
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  /// A footnote line in 设置's footer style.
  static Widget line(String text, {Key? key}) => Builder(
    builder: (context) {
      final style = SettingsSection.footerStyle;
      return Text(text, key: key, style: style, strutStyle: BiliFonts.strutOf(context, style));
    },
  );
}

/// A choice on a page of its own, picked with a tap as CDN 节点's nodes are.
class DeveloperChoicePage<T> extends StatefulWidget {
  const DeveloperChoicePage({
    super.key,
    required this.title,
    required this.choices,
    required this.value,
    required this.onChanged,
    this.footer,
  });

  final String title;

  /// Each value with its label, in order.
  final List<(T, String)> choices;
  final T value;
  final ValueChanged<T> onChanged;
  final String? footer;

  @override
  State<DeveloperChoicePage<T>> createState() => _DeveloperChoicePageState<T>();
}

class _DeveloperChoicePageState<T> extends State<DeveloperChoicePage<T>> {
  late T _value = widget.value;

  void _pick(T value) {
    if (value == _value) return;
    setState(() => _value = value);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
    title: widget.title,
    children: [
      SettingsSection(
        footer: widget.footer,
        children: [
          for (final (value, label) in widget.choices)
            DeveloperCheckRow(
              key: ValueKey('choice-$label'),
              title: label,
              selected: value == _value,
              onTap: () => _pick(value),
            ),
        ],
      ),
    ],
  );
}
