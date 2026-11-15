import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:flutter/widgets.dart';

import '../shared/menu.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import 'app_icon.dart';
import 'settings_page.dart';

/// No official screen to measure: 设置's row look, with the icon at its home screen size.
const _iconSize = 60.0;
const _iconRadius = 13.4;
const _iconPadding = 10.0;
const _iconGap = 12.0;

/// 设置 → 应用图标: a row per [AppIconChoice] with its picture, its name and a tick on the current one.
class AppIconPage extends StatefulWidget {
  const AppIconPage({super.key, required this.host});

  final AppIconHost host;

  @override
  State<AppIconPage> createState() => _AppIconPageState();
}

class _AppIconPageState extends State<AppIconPage> {
  AppIconChoice? _current;
  bool _changing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final current = await widget.host.current();
      // A change made before the answer came is newer than it.
      if (mounted && _current == null) setState(() => _current = current);
    } catch (error) {
      Logger.shared.warn(LogCategory.app, 'app icon not read', {'error': '${error.runtimeType}'});
    }
  }

  Future<void> _choose(AppIconChoice choice) async {
    if (_changing || choice == _current) return;
    _changing = true;
    try {
      await widget.host.choose(choice);
      if (mounted) setState(() => _current = choice);
    } catch (error) {
      Logger.shared.warn(LogCategory.app, 'app icon change failed', {
        'choice': choice.name,
        'error': '${error.runtimeType}',
      });
      if (mounted) showToast(context, '更换失败');
    } finally {
      _changing = false;
    }
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
    title: '应用图标',
    children: [
      SettingsSection(
        children: [
          for (final choice in AppIconChoice.values)
            _IconRow(
              key: ValueKey('app-icon-${choice.name}'),
              choice: choice,
              chosen: choice == _current,
              onTap: () => unawaited(_choose(choice)),
            ),
        ],
      ),
    ],
  );
}

class _IconRow extends StatelessWidget {
  const _IconRow({super.key, required this.choice, required this.chosen, required this.onTap});

  final AppIconChoice choice;
  final bool chosen;
  final VoidCallback onTap;

  static const _look = SettingsPickLook.feed;

  @override
  Widget build(BuildContext context) {
    final check = _look.checkSize;
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: chosen,
        onTap: onTap,
        child: PressHighlight(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(SettingsTheme.rowInset, _iconPadding, 0, _iconPadding),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(_iconRadius),
                  child: Image.asset(
                    choice.preview,
                    width: _iconSize,
                    height: _iconSize,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
                  ),
                ),
                const SizedBox(width: _iconGap),
                Expanded(child: SettingsRow.titleText(choice.label)),
                const SizedBox(width: SettingsTheme.valueGap),
                SizedBox(
                  width: check.width,
                  height: check.height,
                  child: chosen
                      ? CustomPaint(key: const ValueKey('app-icon-check'), size: check, painter: const _CheckPainter())
                      : null,
                ),
                const SizedBox(width: SettingsListTheme.feedCheckEnd),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 设置's pink ✓ (SettingsPickRow's), at 首页推荐设置's size.
class _CheckPainter extends CustomPainter {
  const _CheckPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const half = SettingsListTheme.feedCheckStroke / 2;
    const short = SettingsListTheme.feedCheckShort;
    const long = SettingsListTheme.feedCheckLong;
    canvas.drawPath(
      Path()
        ..moveTo(half, half + long - short)
        ..lineTo(half + short, half + long)
        ..lineTo(half + short + long, half),
      Paint()
        ..color = BiliColors.pink
        ..style = PaintingStyle.stroke
        ..strokeWidth = SettingsListTheme.feedCheckStroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => false;
}
