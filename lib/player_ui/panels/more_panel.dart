import 'package:bili_core/logic.dart' show TimeFormat;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;

import '../../player/bili_player.dart';
import '../../shared/theme.dart';
import '../../video/player_session.dart';
import 'panel_parts.dart';

enum _Page { root, timer, fit }

enum _Sleep { off, minutes15, minutes30, minutes60, custom }

/// ⋮ (20, 21): the official panel's rows that make sense here, plus a 测试 card for BTR and the stats overlay (port of
/// BiliNative `MorePanel.swift`).
class MorePanel extends StatefulWidget {
  const MorePanel({super.key, required this.session, required this.toast, required this.close});

  final PlayerSession session;
  final ValueChanged<String> toast;
  final VoidCallback close;

  static const maxCustomMinutes = 180;

  @override
  State<MorePanel> createState() => _MorePanelState();
}

class _MorePanelState extends State<MorePanel> {
  var _page = _Page.root;
  var _customMinutes = 30;

  PlayerSession get _session => widget.session;

  static _Sleep _sleepChoice(Duration? timer) => switch (timer?.inMinutes) {
    null => _Sleep.off,
    15 => _Sleep.minutes15,
    30 => _Sleep.minutes30,
    60 => _Sleep.minutes60,
    _ => _Sleep.custom,
  };

  void _chooseSleep(_Sleep choice) {
    switch (choice) {
      case _Sleep.off:
        _session.setSleepTimer(null);
      case _Sleep.minutes15:
        _session.setSleepTimer(const Duration(minutes: 15));
      case _Sleep.minutes30:
        _session.setSleepTimer(const Duration(minutes: 30));
      case _Sleep.minutes60:
        _session.setSleepTimer(const Duration(minutes: 60));
      case _Sleep.custom:
        setState(() {
          _customMinutes = (_session.sleepTimer?.inMinutes ?? _customMinutes).clamp(1, MorePanel.maxCustomMinutes);
          _page = _Page.timer;
        });
    }
  }

  Future<void> _watchLater() async {
    final message = (await _session.watchLater()).message;
    widget.toast(message);
    widget.close();
  }

  void _pictureInPicture() {
    _session.startPictureInPicture();
    widget.close();
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 220),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(animation),
        child: child,
      ),
    ),
    child: switch (_page) {
      _Page.root => KeyedSubtree(key: const ValueKey(_Page.root), child: _root()),
      _Page.timer => KeyedSubtree(key: const ValueKey(_Page.timer), child: _timer()),
      _Page.fit => KeyedSubtree(key: const ValueKey(_Page.fit), child: _fit()),
    },
  );

  Widget _root() {
    final timer = _session.sleepTimer;
    final customMinutes = _sleepChoice(timer) == _Sleep.custom ? timer?.inMinutes : null;
    final sleepItems = <(_Sleep, String)>[
      (_Sleep.off, '不开启'),
      (_Sleep.minutes15, '15:00'),
      (_Sleep.minutes30, '30:00'),
      (_Sleep.minutes60, '60:00'),
      (_Sleep.custom, customMinutes == null ? '自定义' : '$customMinutes分钟'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: BiliMetrics.panelTop),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelReveal(
            order: 0,
            child: Padding(
              padding: const EdgeInsets.only(left: BiliMetrics.panelActionLead),
              child: Row(
                spacing: BiliMetrics.panelActionGap,
                children: [
                  _ActionButton(icon: Icons.play_circle_outline, title: '稍后再看', onTap: _watchLater),
                  _ActionButton(
                    icon: Icons.picture_in_picture_alt_outlined,
                    title: '小窗播放',
                    onTap: _session.pictureInPictureSupported ? _pictureInPicture : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: BiliMetrics.panelSectionGap),
          PanelReveal(
            order: 1,
            child: PanelTitle(
              '定时关闭',
              trailing: ValueListenableBuilder(
                valueListenable: _session.sleepRemaining,
                builder: (context, remaining, _) => remaining == null
                    ? const SizedBox.shrink()
                    : Text(
                        '${TimeFormat.clock(remaining.inMilliseconds / 1000)} 后暂停',
                        key: const ValueKey('sleep-remaining'),
                        style: const TextStyle(fontSize: BiliMetrics.panelDetailText, color: BiliColors.pink),
                      ),
              ),
            ),
          ),
          const SizedBox(height: BiliMetrics.panelTitleGap),
          PanelReveal(
            order: 2,
            child: PanelGroup(
              children: [
                SizedBox(
                  height: BiliMetrics.panelRowHeight,
                  child: PanelSegments(items: sleepItems, selected: _sleepChoice(timer), onSelect: _chooseSleep),
                ),
              ],
            ),
          ),
          const SizedBox(height: BiliMetrics.panelCardGap),
          PanelReveal(
            order: 3,
            child: PanelGroup(
              children: [
                PanelToggleRow(
                  icon: Icons.skip_next_outlined,
                  title: '自动连播',
                  value: _session.autoplayNext,
                  onChanged: _session.setAutoplayNext,
                ),
                PanelRowFrame(
                  icon: Icons.loop,
                  title: '循环播放',
                  trailing: PanelSegments(
                    compact: true,
                    items: [for (final mode in LoopMode.values) (mode, mode.label)],
                    selected: _session.loop,
                    onSelect: _session.setLoop,
                  ),
                ),
                PanelToggleRow(
                  icon: Icons.flip,
                  title: '镜像翻转',
                  value: _session.mirrored,
                  onChanged: _session.setMirrored,
                ),
                GestureDetector(
                  key: const ValueKey('more-fit'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _page = _Page.fit),
                  child: PanelRowFrame(
                    icon: Icons.crop_free,
                    title: '画面尺寸',
                    divider: false,
                    trailing: Align(
                      alignment: Alignment.centerRight,
                      child: PanelDisclosure(text: _session.fit.label),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: BiliMetrics.panelSectionGap),
          const PanelReveal(order: 4, child: PanelTitle('测试')),
          const SizedBox(height: BiliMetrics.panelTitleGap),
          PanelReveal(
            order: 5,
            child: PanelGroup(
              children: [
                PanelToggleRow(icon: Icons.bolt, title: 'BTR 加速', value: _session.btr, onChanged: _session.setBtr),
                PanelToggleRow(
                  icon: Icons.bar_chart,
                  title: '显示统计',
                  divider: false,
                  value: _session.showStats,
                  onChanged: _session.setShowStats,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timer() => Padding(
    padding: const EdgeInsets.only(top: BiliMetrics.panelTop),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: BiliMetrics.gutter,
      children: [
        PanelHeader(title: '自定义定时关闭', back: () => setState(() => _page = _Page.root)),
        SizedBox(
          height: BiliMetrics.panelWheelHeight,
          child: CupertinoTheme(
            data: const CupertinoThemeData(
              brightness: Brightness.dark,
              textTheme: CupertinoTextThemeData(
                pickerTextStyle: TextStyle(
                  fontFamily: BiliFonts.family,
                  fontSize: BiliMetrics.bodyText,
                  color: BiliColors.panelText,
                ),
              ),
            ),
            child: CupertinoPicker(
              key: const ValueKey('sleep-wheel'),
              itemExtent: BiliMetrics.panelWheelItem,
              scrollController: FixedExtentScrollController(initialItem: _customMinutes - 1),
              onSelectedItemChanged: (index) => _customMinutes = index + 1,
              children: [
                for (var minutes = 1; minutes <= MorePanel.maxCustomMinutes; minutes++)
                  Center(child: Text('$minutes 分钟')),
              ],
            ),
          ),
        ),
        Semantics(
          button: true,
          child: PanelPressable(
            radius: BiliMetrics.panelButtonHeight / 2,
            onTap: () {
              _session.setSleepTimer(Duration(minutes: _customMinutes));
              setState(() => _page = _Page.root);
            },
            child: Container(
              height: BiliMetrics.panelButtonHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: BiliColors.pink,
                borderRadius: BorderRadius.circular(BiliMetrics.panelButtonHeight / 2),
              ),
              child: const Text('确定', style: TextStyle(color: BiliColors.onPink)),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _fit() => Padding(
    padding: const EdgeInsets.only(top: BiliMetrics.panelTop),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: BiliMetrics.panelGap,
      children: [
        PanelHeader(title: '画面尺寸', back: () => setState(() => _page = _Page.root)),
        for (final (index, mode) in FitMode.values.indexed)
          PanelReveal(
            order: index,
            child: PanelCardRow(
              title: mode.label,
              selected: _session.fit == mode,
              onTap: () {
                _session.setFit(mode);
                setState(() => _page = _Page.root);
              },
            ),
          ),
      ],
    ),
  );
}

/// The 稍后再看 and 小窗播放 squares at the top of ⋮.
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;

  /// Null greys it out, as 小窗播放 where picture in picture isn't available.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: title,
    excludeSemantics: true,
    child: Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: PanelPressable(
        onTap: onTap,
        radius: BiliMetrics.panelRowRadius,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: BiliMetrics.panelActionSize,
              height: BiliMetrics.panelActionSize,
              decoration: BoxDecoration(
                color: BiliColors.panelCard,
                borderRadius: BorderRadius.circular(BiliMetrics.panelRowRadius),
              ),
              child: Icon(icon, size: BiliMetrics.panelActionIcon, color: BiliColors.panelText),
            ),
            const SizedBox(height: BiliMetrics.panelGap),
            SizedBox(
              height: BiliMetrics.panelActionLabel,
              child: Center(
                child: Text(
                  title,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(fontSize: BiliMetrics.panelActionText, color: BiliColors.panelSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
