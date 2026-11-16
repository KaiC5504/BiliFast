import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../../app/app_scope.dart';
import '../../settings/settings_page.dart' show SettingsCheckPainter, settingsLineAt;
import '../../shared/menu.dart' show PressHighlight;
import '../../shared/theme.dart';
import '../../skin/skin.dart';
import '../../video/intro/collection_row.dart' show Chevron;

typedef _T = MessageSettingsTheme;

/// The bar's colours: the equipped 装扮's second-page colour and text colour (188's green is KaiC's skin's
/// `color_second_page`), else white. The status bar goes by the fill.
final class MessageSettingsBarLook {
  const MessageSettingsBarLook({required this.fill, required this.ink, required this.lightStatus});

  static const stock = MessageSettingsBarLook(fill: _T.bar, ink: _T.barInk, lightStatus: false);

  factory MessageSettingsBarLook.of(Skin? skin) {
    final page = skin?.equip.colors.colorSecondPage;
    if (skin == null || skin.equip.primaryOnly || page == null) return stock;
    final fill = Color(page);
    return MessageSettingsBarLook(
      fill: fill,
      ink: skin.color ?? (skin.lightText ? _T.barLightInk : _T.barInk),
      lightStatus: SkinStatusBar.whiteOverColor(fill),
    );
  }

  final Color fill;
  final Color ink;
  final bool lightStatus;
}

/// 消息设置's pages (188, 215): the bar with ‹ and its title over the grey page, the groups stacked below.
class MessageSettingsScaffold extends StatelessWidget {
  const MessageSettingsScaffold({super.key, required this.title, required this.children, this.skin});

  final String title;
  final List<Widget> children;

  /// [AppScope]'s by default.
  final ValueListenable<Skin?>? skin;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Skin?>(
    valueListenable: skin ?? AppScope.of(context).skin,
    builder: (context, skin, _) {
      final look = MessageSettingsBarLook.of(skin);
      final bottom = MediaQuery.paddingOf(context).bottom;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: look.lightStatus ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: _T.page,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Bar(title: title, look: look),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: ListView(
                    padding: EdgeInsets.only(bottom: bottom),
                    children: children,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Bar extends StatelessWidget {
  const _Bar({required this.title, required this.look});

  final String title;
  final MessageSettingsBarLook look;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final style = _style(
      _T.titleText,
      look.ink,
      weight: _T.titleWeight,
    ).copyWith(height: _T.titleLine / _T.titleText, leadingDistribution: TextLeadingDistribution.even);
    void back() => unawaited(Navigator.of(context).maybePop());
    return ColoredBox(
      key: const ValueKey('message-settings-bar'),
      color: look.fill,
      child: SizedBox(
        height: top + _T.barRow,
        child: Stack(
          children: [
            Positioned(
              left: _T.backTarget,
              right: _T.backTarget,
              top: top,
              height: _T.barRow,
              child: Center(
                child: Transform.translate(
                  offset: const Offset(0, _T.titleDrop),
                  child: Text(
                    title,
                    key: const ValueKey('message-settings-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                    strutStyle: BiliFonts.strut(style),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: top,
              width: _T.backTarget,
              height: _T.barRow,
              child: Semantics(
                button: true,
                label: '返回',
                onTap: back,
                excludeSemantics: true,
                child: GestureDetector(
                  key: const ValueKey('message-settings-back'),
                  behavior: HitTestBehavior.opaque,
                  onTap: back,
                  child: CustomPaint(painter: _BackPainter(look.ink)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackPainter extends CustomPainter {
  const _BackPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    canvas.drawPath(
      Path()
        ..moveTo(_T.backEndX, middle - _T.backHalfHeight)
        ..lineTo(_T.backTipX, middle)
        ..lineTo(_T.backEndX, middle + _T.backHalfHeight),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _T.backStroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_BackPainter oldDelegate) => oldDelegate.color != color;
}

TextStyle _style(double size, Color color, {FontWeight weight = FontWeight.w400}) =>
    TextStyle(fontFamily: BiliFonts.family, fontSize: size, color: color, fontWeight: weight);

Widget _text(String text, TextStyle style, {Key? key}) => Builder(
  builder: (context) => Text(
    text,
    key: key,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: style,
    strutStyle: BiliFonts.strutOf(context, style),
  ),
);

/// A group: 10 pt of grey, or the grey band with its [label]; then white rows, 2 px of grey between two.
class MessageSettingsGroup extends StatelessWidget {
  const MessageSettingsGroup({super.key, this.label, required this.children});

  final String? label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label == null)
          const SizedBox(height: _T.top)
        else
          SizedBox(
            height: _T.labelHeight,
            child: Stack(
              children: [
                settingsLineAt(
                  centre: _T.labelCentre,
                  left: _T.labelInset,
                  right: _T.labelInset,
                  child: _text(label, _style(_T.labelText, _T.label)),
                ),
              ],
            ),
          ),
        for (final (index, child) in children.indexed) ...[
          if (index > 0)
            const SizedBox(
              height: _T.rule,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: _T.hairlineInset),
                    child: ColoredBox(
                      color: _T.hairlineColor,
                      child: SizedBox(height: _T.hairline),
                    ),
                  ),
                ],
              ),
            ),
          ColoredBox(color: _T.row, child: child),
        ],
      ],
    );
  }
}

/// A row's title and grey second line on the left, and [trailing] centred where 188 has it: [oneLineCentre] down a
/// one-line row, on a two-line row's middle, ending [trailingRight] from the edge; the text is kept [textRight] clear
/// of the edge.
class _RowLayout extends StatelessWidget {
  const _RowLayout({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.trailingRight,
    required this.textRight,
    this.oneLineCentre = _T.trailingCentre,
  });

  final Widget title;
  final String? subtitle;
  final Widget? trailing;
  final double trailingRight;
  final double textRight;
  final double oneLineCentre;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    final trailing = this.trailing;
    final height = subtitle == null ? _T.rowHeight : _T.tallHeight;
    final trailingCentre = subtitle == null ? oneLineCentre : _T.tallHeight / 2;
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          settingsLineAt(centre: _T.titleCentre, left: _T.rowInset, right: textRight, child: title),
          if (subtitle != null)
            settingsLineAt(
              centre: _T.subtitleCentre,
              left: _T.rowInset,
              right: textRight,
              child: _text(subtitle, _style(_T.subtitleText, _T.subtitle)),
            ),
          if (trailing != null)
            Positioned(
              right: trailingRight,
              top: trailingCentre - height,
              height: height * 2,
              child: Center(child: trailing),
            ),
        ],
      ),
    );
  }
}

/// A row that opens something, a › at its end; its [value] in grey before the ›. A null [value] shows nothing there.
class MessageSettingsLinkRow extends StatelessWidget {
  const MessageSettingsLinkRow({super.key, required this.title, required this.onTap, this.subtitle, this.value});

  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    return MergeSemantics(
      child: Semantics(
        button: true,
        onTap: onTap,
        child: PressHighlight(
          onTap: onTap,
          child: _RowLayout(
            title: _text(title, _style(_T.rowTitleText, _T.rowTitle)),
            subtitle: subtitle,
            trailingRight: _T.chevronRight,
            textRight: _T.chevronRight + _T.chevronWidth + _T.valueGap,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (value != null) ...[
                  _text(value, _style(_T.valueText, _T.value), key: const ValueKey('message-settings-value')),
                  const SizedBox(width: _T.valueGap),
                ],
                const Chevron(
                  size: Size(_T.chevronWidth, _T.chevronHeight),
                  stroke: _T.chevronStroke,
                  color: _T.chevron,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row with 188's switch at its end; the whole row flips it.
class MessageSettingsSwitchRow extends StatelessWidget {
  const MessageSettingsSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    void flip() => onChanged(!value);
    return MergeSemantics(
      child: Semantics(
        toggled: value,
        onTap: flip,
        child: PressHighlight(
          onTap: flip,
          child: _RowLayout(
            title: _text(title, _style(_T.rowTitleText, _T.rowTitle)),
            subtitle: subtitle,
            trailingRight: _T.switchRight,
            textRight: _T.switchRight + _T.switchWidth + _T.valueGap,
            trailing: _Switch(on: value),
          ),
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final motion = MediaQuery.disableAnimationsOf(context) ? Duration.zero : _T.switchMotion;
    return AnimatedContainer(
      key: const ValueKey('message-settings-switch'),
      duration: motion,
      curve: Curves.easeOutCubic,
      width: _T.switchWidth,
      height: _T.switchHeight,
      padding: const EdgeInsets.all((_T.switchHeight - _T.switchKnob) / 2),
      decoration: BoxDecoration(
        color: on ? _T.switchOn : _T.switchOff,
        borderRadius: BorderRadius.circular(_T.switchHeight / 2),
      ),
      child: AnimatedAlign(
        duration: motion,
        curve: Curves.easeOutCubic,
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: const DecoratedBox(
          decoration: BoxDecoration(color: _T.switchKnobFill, shape: BoxShape.circle),
          child: SizedBox.square(dimension: _T.switchKnob),
        ),
      ),
    );
  }
}

/// A picker's row (215): the [chosen] one's words pink and semibold, with the pink ✓ at its end.
class MessageSettingsChoiceRow extends StatelessWidget {
  const MessageSettingsChoiceRow({super.key, required this.title, required this.chosen, required this.onTap});

  final String title;
  final bool chosen;
  final VoidCallback onTap;

  static const _check = Size(_T.checkShort + _T.checkLong + _T.checkStroke, _T.checkLong + _T.checkStroke);

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      button: true,
      selected: chosen,
      onTap: onTap,
      child: PressHighlight(
        onTap: onTap,
        child: _RowLayout(
          title: _text(
            title,
            chosen ? _style(_T.rowTitleText, _T.chosen, weight: _T.chosenWeight) : _style(_T.rowTitleText, _T.rowTitle),
          ),
          subtitle: null,
          oneLineCentre: _T.checkCentre,
          trailingRight: _T.checkEnd,
          textRight: _T.checkEnd + _check.width + _T.valueGap,
          trailing: chosen
              ? CustomPaint(
                  key: const ValueKey('message-settings-check'),
                  size: _check,
                  painter: const SettingsCheckPainter(_T.checkShort, _T.checkLong, _T.checkStroke),
                )
              : null,
        ),
      ),
    ),
  );
}
