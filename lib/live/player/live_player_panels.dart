import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_environment.dart' show LoggedIn;
import '../../app/app_scope.dart';
import '../../danmaku/danmaku_session.dart';
import '../../device/orientation.dart';
import '../../playback/danmaku_feed.dart';
import '../../player_ui/chrome_state.dart';
import '../../player_ui/landscape_chrome.dart' show fullScreenStrut, fullScreenText;
import '../../player_ui/panels/panel_controller.dart';
import '../../player_ui/panels/panel_layer.dart';
import '../../player_ui/player_ui.dart';
import '../../shared/theme.dart';
import '../../shared/toast.dart';
import '../../video/player_session.dart';
import '../live_login.dart';
import '../room/live_overlays.dart';
import '../room/live_room_model.dart';
import 'live_player_controller.dart';
import 'live_player_glyphs.dart';
import 'live_player_view.dart' show LivePlayerAssets;

/// A panel on the right of full screen (210, 222), filling the screen: a tap beside it closes [overlays].
class _SidePanel extends StatefulWidget {
  const _SidePanel({required this.overlays, required this.fill, required this.child, this.panelKey});

  final LiveOverlays overlays;
  final Color fill;
  final Widget child;
  final Key? panelKey;

  @override
  State<_SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<_SidePanel> with SingleTickerProviderStateMixin {
  late final _slide = AnimationController(vsync: this, duration: LivePlayerTheme.sideSlide)..forward();
  late final _curve = CurvedAnimation(parent: _slide, curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _curve.dispose();
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: fullScreenText,
    child: Stack(
      children: [
        Positioned.fill(
          child: Semantics(
            button: true,
            label: '关闭',
            onTap: widget.overlays.close,
            child: GestureDetector(
              key: const ValueKey('live-panel-dismiss'),
              behavior: HitTestBehavior.opaque,
              onTap: widget.overlays.close,
            ),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: LivePlayerTheme.sideWidth,
          child: AnimatedBuilder(
            animation: _curve,
            builder: (context, child) =>
                Transform.translate(offset: Offset((1 - _curve.value) * LivePlayerTheme.sideWidth, 0), child: child),
            child: GestureDetector(
              key: widget.panelKey,
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: ColoredBox(color: widget.fill, child: widget.child),
            ),
          ),
        ),
      ],
    ),
  );
}

TextStyle _style(double size, {Color color = BiliColors.panelText}) =>
    fullScreenText.merge(TextStyle(fontSize: size, color: color));

Widget _text(String text, double size, {Color color = BiliColors.panelText, Key? key}) {
  final style = _style(size, color: color);
  return Text(text, key: key, style: style, strutStyle: fullScreenStrut(style), maxLines: 1, softWrap: false);
}

/// One of 222's buttons.
enum LiveMoreItem {
  share('分享'),
  pictureInPicture('小窗播放'),
  playSettings('播放设置'),
  boost('助TA必火'),
  danmakuSettings('弹幕设置'),
  spending('消费管理'),
  hideEffects('隐藏特效'),
  cast('投屏'),
  report('举报'),
  feedback('反馈'),
  audioOnly('仅播声音'),
  colour('色觉优化'),
  desktop('添至桌面');

  const LiveMoreItem(this.label);

  final String label;
}

/// 222: full screen's ⋮ panel on the right. 分享, 小窗播放 and 弹幕设置 work; the rest toast 暂未开放. 222 has no 画质:
/// full screen's bottom row has its own.
class LiveMorePanel extends StatelessWidget {
  const LiveMorePanel({super.key, required this.controller, required this.room, required this.overlays});

  final LivePlayerController controller;
  final LiveRoomModel room;
  final LiveOverlays overlays;

  void _pressed(BuildContext context, LiveMoreItem item) {
    switch (item) {
      case LiveMoreItem.share:
        overlays.close();
        unawaited(controller.share(context));
      case LiveMoreItem.pictureInPicture:
        overlays.close();
        unawaited(controller.startPictureInPicture());
      case LiveMoreItem.danmakuSettings:
        overlays.open(LiveOverlay.danmakuSettings);
      default:
        showToast(context, '暂未开放');
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return _SidePanel(
      overlays: overlays,
      fill: LivePlayerTheme.moreFill,
      panelKey: const ValueKey('live-more-panel'),
      child: Stack(
        children: [
          for (final (index, item) in LiveMoreItem.values.indexed)
            Positioned(
              left:
                  LivePlayerTheme.moreFirstX +
                  (index % LivePlayerTheme.moreColumns) * LivePlayerTheme.moreColumn -
                  LivePlayerTheme.moreColumn / 2,
              top:
                  top +
                  LivePlayerTheme.moreFirstY +
                  (index ~/ LivePlayerTheme.moreColumns) * LivePlayerTheme.moreRow -
                  LivePlayerTheme.moreDisc / 2,
              width: LivePlayerTheme.moreColumn,
              child: _MoreButton(item: item, onTap: () => _pressed(context, item)),
            ),
        ],
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.item, required this.onTap});

  final LiveMoreItem item;
  final VoidCallback onTap;

  Widget _icon() {
    Widget asset(String path, [double size = LivePlayerTheme.moreIcon]) => Image.asset(path, width: size, height: size);
    return switch (item) {
      LiveMoreItem.share => asset(LivePlayerAssets.moreShare),
      LiveMoreItem.pictureInPicture => asset(LivePlayerAssets.morePip),
      LiveMoreItem.playSettings => asset(LivePlayerAssets.moreSettings),
      LiveMoreItem.boost => const LiveDrawnGlyph(LiveGlyph.flame),
      LiveMoreItem.danmakuSettings => asset(LivePlayerAssets.moreDanmaku),
      LiveMoreItem.spending => const LiveDrawnGlyph(LiveGlyph.shield),
      LiveMoreItem.hideEffects => asset(LivePlayerAssets.moreEffects),
      LiveMoreItem.cast => asset(LivePlayerAssets.moreCast),
      LiveMoreItem.report => asset(LivePlayerAssets.moreReport),
      LiveMoreItem.feedback => asset(LivePlayerAssets.moreFeedback),
      LiveMoreItem.audioOnly => asset(LivePlayerAssets.moreAudio),
      LiveMoreItem.colour => asset(LivePlayerAssets.moreColour, LivePlayerTheme.moreColourIcon),
      LiveMoreItem.desktop => asset(LivePlayerAssets.moreDesktop),
    };
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: item.label,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      key: ValueKey('live-more-${item.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: LivePlayerTheme.moreRow,
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            Container(
              width: LivePlayerTheme.moreDisc,
              height: LivePlayerTheme.moreDisc,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: LivePlayerTheme.moreDiscFill, shape: BoxShape.circle),
              child: OverflowBox(
                maxWidth: LivePlayerTheme.moreIcon,
                maxHeight: LivePlayerTheme.moreIcon,
                child: _icon(),
              ),
            ),
            if (item == LiveMoreItem.boost)
              Positioned(
                left:
                    LivePlayerTheme.moreColumn / 2 +
                    LivePlayerTheme.moreBadgeOffset -
                    LivePlayerTheme.moreBadge / 2 -
                    LivePlayerTheme.moreBadgeRing,
                top:
                    LivePlayerTheme.moreDisc / 2 -
                    LivePlayerTheme.moreBadgeOffset -
                    LivePlayerTheme.moreBadge / 2 -
                    LivePlayerTheme.moreBadgeRing,
                child: Container(
                  key: const ValueKey('live-more-boost-dot'),
                  width: LivePlayerTheme.moreBadge + LivePlayerTheme.moreBadgeRing * 2,
                  height: LivePlayerTheme.moreBadge + LivePlayerTheme.moreBadgeRing * 2,
                  decoration: BoxDecoration(
                    color: LivePlayerTheme.moreBadgeInk,
                    shape: BoxShape.circle,
                    border: Border.all(color: BiliColors.onVideo, width: LivePlayerTheme.moreBadgeRing),
                  ),
                ),
              ),
            Positioned(
              top: LivePlayerTheme.moreDisc / 2 + LivePlayerTheme.moreLabelDrop - LivePlayerTheme.moreLabel,
              height: LivePlayerTheme.moreLabel * 2,
              child: Center(child: _text(item.label, LivePlayerTheme.moreLabel)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 210: the room's qualities, on the right in full screen, as a sheet from the bottom in portrait.
///
/// Portrait has no screenshot: the sheet takes 221's (its dark fill and 分享's title) with 210's rows.
class LiveQualityPicker extends StatelessWidget {
  const LiveQualityPicker({
    super.key,
    required this.controller,
    required this.room,
    required this.overlays,
    required this.landscape,
  });

  final LivePlayerController controller;
  final LiveRoomModel room;
  final LiveOverlays overlays;
  final bool landscape;

  void _pick(LiveQuality? quality) {
    overlays.close();
    unawaited(controller.pickQuality(quality));
  }

  List<Widget> _rows() {
    final qualities = room.play?.qualities ?? const <LiveQuality>[];
    final current = controller.autoQuality ? null : controller.quality?.qn;
    return [
      for (final quality in qualities)
        _QualityRow(
          key: ValueKey('live-quality-${quality.qn}'),
          name: quality.name,
          current: quality.qn == current,
          onTap: () => _pick(quality),
        ),
      _QualityRow(
        key: const ValueKey('live-quality-auto'),
        name: '自动',
        current: controller.autoQuality,
        onTap: () => _pick(null),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, room]),
    builder: (context, _) => landscape ? _side(context) : _sheet(context),
  );

  Widget _side(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return _SidePanel(
      overlays: overlays,
      fill: LivePlayerTheme.qualityFill,
      panelKey: const ValueKey('live-quality-panel'),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: top,
          left: LivePlayerTheme.qualitySide,
          right: LivePlayerTheme.qualitySide,
          bottom: LivePlayerTheme.qualitySide,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: LivePlayerTheme.qualityTop,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: LivePlayerTheme.switchRight - LivePlayerTheme.qualitySide,
                    top: LivePlayerTheme.qualityTitleCentre - LivePlayerTheme.qualityTitleRow / 2,
                    height: LivePlayerTheme.qualityTitleRow,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: '画质增强', style: _style(LivePlayerTheme.qualityTitle)),
                                TextSpan(
                                  text: '(仅针对超清及以下生效)',
                                  style: _style(LivePlayerTheme.qualityTitle, color: LivePlayerTheme.qualityNote),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            strutStyle: fullScreenStrut(_style(LivePlayerTheme.qualityTitle)),
                          ),
                        ),
                        _EnhanceSwitch(onTap: () => showToast(context, '暂未开放')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ..._spaced(_rows()),
          ],
        ),
      ),
    );
  }

  Widget _sheet(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return DefaultTextStyle(
      style: fullScreenText,
      child: Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              button: true,
              label: '关闭',
              onTap: overlays.close,
              child: GestureDetector(
                key: const ValueKey('live-panel-dismiss'),
                behavior: HitTestBehavior.opaque,
                onTap: overlays.close,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: GestureDetector(
              key: const ValueKey('live-quality-sheet'),
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: Container(
                decoration: const BoxDecoration(
                  color: LivePlayerTheme.sheetFill,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(LivePlayerTheme.sheetRadius)),
                ),
                padding: EdgeInsets.only(bottom: bottom + LivePlayerTheme.sheetBottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        left: LivePlayerTheme.sheetTitleLeft,
                        top: LivePlayerTheme.sheetTitleTop,
                      ),
                      child: SizedBox(
                        height: LivePlayerTheme.sheetTitleHeight * 2,
                        child: Align(alignment: Alignment.centerLeft, child: _text('画质', LivePlayerTheme.sheetTitle)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: LivePlayerTheme.qualitySide),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced(_rows())),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static List<Widget> _spaced(List<Widget> rows) => [
    for (final (index, row) in rows.indexed) ...[
      if (index > 0) const SizedBox(height: LivePlayerTheme.qualityRowGap),
      row,
    ],
  ];
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({super.key, required this.name, required this.current, required this.onTap});

  final String name;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: current,
    label: name,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: LivePlayerTheme.qualityRow,
        padding: const EdgeInsets.symmetric(horizontal: LivePlayerTheme.qualityRowInset),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: LivePlayerTheme.qualityRowFill,
          borderRadius: BorderRadius.circular(LivePlayerTheme.qualityRowRadius),
        ),
        child: _text(name, LivePlayerTheme.qualityRowText, color: current ? LiveRoomTheme.pink : BiliColors.panelText),
      ),
    ),
  );
}

/// 画质增强's switch, drawn on as 210 shows it; it only toasts.
class _EnhanceSwitch extends StatelessWidget {
  const _EnhanceSwitch({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    toggled: true,
    label: '画质增强',
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      key: const ValueKey('live-quality-enhance'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: LivePlayerTheme.switchWidth,
        height: LivePlayerTheme.switchHeight,
        padding: const EdgeInsets.all(LivePlayerTheme.switchKnobInset),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: LivePlayerTheme.switchOn,
          borderRadius: BorderRadius.circular(LivePlayerTheme.switchHeight / 2),
        ),
        child: Container(
          width: LivePlayerTheme.switchKnobWidth,
          decoration: BoxDecoration(
            color: BiliColors.panelText,
            borderRadius: BorderRadius.circular(LivePlayerTheme.switchHeight / 2),
          ),
        ),
      ),
    ),
  );
}

/// 弹幕设置: the video page's own panel ([PanelLayer]'s 弹幕设置, the landscape strip or the portrait sheet) over the
/// shared [AppServices.danmakuSettings] and 屏蔽词, through a danmaku session of its own that loads nothing. Its
/// 添加屏蔽词 works; 当前弹幕列表 lists a video's danmaku, so it toasts 暂未开放 here. Closing it closes [overlays].
class LiveDanmakuSettingsPanel extends StatefulWidget {
  const LiveDanmakuSettingsPanel({
    super.key,
    required this.controller,
    required this.overlays,
    required this.landscape,
  });

  final LivePlayerController controller;
  final LiveOverlays overlays;
  final bool landscape;

  @override
  State<LiveDanmakuSettingsPanel> createState() => _LiveDanmakuSettingsPanelState();
}

class _LiveDanmakuSettingsPanelState extends State<LiveDanmakuSettingsPanel> {
  final _panels = PanelController();
  final _chrome = ChromeState();
  late final _layout = ValueNotifier(_presentation);
  DanmakuFeed? _feed;
  DanmakuSession? _danmaku;
  PlayerUi? _ui;
  Timer? _closing;

  Presentation get _presentation => widget.landscape ? Presentation.landscape : Presentation.inline;

  @override
  void initState() {
    super.initState();
    _panels.addListener(_panelChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ui != null) return;
    final services = AppScope.of(context);
    final environment = services.environment;
    final feed = _feed = DanmakuFeed(client: environment.client);
    final danmaku = _danmaku = DanmakuSession(
      feed: feed,
      settings: services.danmakuSettings,
      rules: services.blockRules,
      api: services.pageApi,
      target: () => null,
      position: () => 0,
      isLoggedIn: () => environment.account is LoggedIn,
      isVip: () => false,
      accountMid: () => environment.mid ?? 0,
      requestLogin: () {
        if (mounted) unawaited(requestLiveLogin(context));
      },
    );
    _ui = PlayerUi(
      session: _NoVideoSession(),
      chrome: _chrome,
      panels: _panels,
      orientation: services.device.orientation,
      device: services.device.controls,
      onBack: widget.overlays.close,
      danmaku: danmaku,
      layout: _layout,
    );
    _panels.open(PlayerPanel.danmakuSettings);
  }

  @override
  void didUpdateWidget(LiveDanmakuSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _layout.value = _presentation;
  }

  void _panelChanged() {
    switch (_panels.value) {
      case PlayerPanel.danmakuList:
        showToast(context, '暂未开放');
        _panels.open(PlayerPanel.danmakuSettings);
      case null:
        // After the layer's slide out.
        _closing ??= Timer(const Duration(milliseconds: 220), () {
          if (mounted && _panels.value == null) widget.overlays.close();
        });
      default:
        _closing?.cancel();
        _closing = null;
    }
  }

  @override
  void dispose() {
    _closing?.cancel();
    _panels.removeListener(_panelChanged);
    _danmaku?.dispose();
    _feed?.dispose();
    _panels.dispose();
    _chrome.dispose();
    _layout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = _ui;
    if (ui == null) return const SizedBox.shrink();
    return PanelLayer(key: const ValueKey('live-danmaku-settings'), ui: ui);
  }
}

/// The panel layer reads a video's session only for panels a room never opens; 弹幕设置 needs none of it.
class _NoVideoSession implements PlayerSession {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('a live room has no video session (${invocation.memberName})');
}
