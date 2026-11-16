import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../../shared/remote_image.dart';
import '../../shared/theme.dart';
import 'live_send_glyphs.dart';

/// Whether [emote] goes into the field as its text ([dog]) rather than out as a danmaku of its own: an inline emote
/// names the text it replaces in brackets, a whole-message one only its name.
bool insertsAsText(LiveEmote emote) => emote.text.length > 2 && emote.text.startsWith('[') && emote.text.endsWith(']');

/// 227's panel in the keyboard's place: the chosen package's emotes under its title, ⌫ over the grid while the package
/// is one whose emotes go into the field, and the packages along the bottom.
class LiveEmotePanel extends StatefulWidget {
  const LiveEmotePanel({
    super.key,
    required this.packages,
    required this.height,
    required this.onPick,
    required this.onDelete,
    this.failed = false,
    this.onRetry,
  });

  /// Null while they load.
  final List<LiveEmotePackage>? packages;
  final double height;
  final ValueChanged<LiveEmote> onPick;
  final VoidCallback onDelete;
  final bool failed;
  final VoidCallback? onRetry;

  @override
  State<LiveEmotePanel> createState() => _LiveEmotePanelState();
}

class _LiveEmotePanelState extends State<LiveEmotePanel> {
  int _chosen = 0;

  @override
  Widget build(BuildContext context) {
    final packages = widget.packages ?? const <LiveEmotePackage>[];
    final index = packages.isEmpty ? 0 : math.min(_chosen, packages.length - 1);
    final package = packages.isEmpty ? null : packages[index];
    return SizedBox(
      key: const ValueKey('live-emote-panel'),
      height: widget.height,
      child: ColoredBox(
        color: LiveSendTheme.panelFill,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: LiveSendTheme.headerHeight,
              child: Padding(
                padding: const EdgeInsets.only(left: LiveSendTheme.headerLeft),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    // The first package is the one 227 titles 全部表情.
                    package == null || index == 0 ? '全部表情' : package.name,
                    key: const ValueKey('live-emote-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sendStyle(LiveSendTheme.headerText, LiveSendTheme.headerInk),
                  ),
                ),
              ),
            ),
            Expanded(child: package == null ? _empty() : _grid(package)),
            _bar(packages, index),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    final retry = widget.onRetry;
    if (!widget.failed || retry == null) return const SizedBox.expand();
    return Semantics(
      button: true,
      label: '加载失败，点击重试',
      onTap: retry,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('live-emote-retry'),
        behavior: HitTestBehavior.opaque,
        onTap: retry,
        child: Center(child: Text('加载失败，点击重试', style: sendStyle(LiveSendTheme.emptyText, LiveSendTheme.empty))),
      ),
    );
  }

  Widget _grid(LiveEmotePackage package) {
    final deletes = package.emotes.any(insertsAsText);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = math.max(((width - LiveSendTheme.gridSide * 2) / LiveSendTheme.gridCellWidth).floor(), 1);
        final side = math.max((width - columns * LiveSendTheme.gridCellWidth) / 2, 0.0);
        return Stack(
          children: [
            Positioned.fill(
              child: GridView.builder(
                key: ValueKey('live-emote-grid-${package.id}'),
                padding: EdgeInsets.only(
                  left: side,
                  right: side,
                  bottom: deletes ? LiveSendTheme.deleteHeight + LiveSendTheme.deleteBottom : 0,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: LiveSendTheme.gridCellHeight,
                ),
                itemCount: package.emotes.length,
                itemBuilder: (context, index) =>
                    LiveEmoteButton(emote: package.emotes[index], size: LiveSendTheme.gridEmote, onTap: widget.onPick),
              ),
            ),
            if (deletes)
              Positioned(
                right: LiveSendTheme.deleteRight,
                bottom: LiveSendTheme.deleteBottom,
                child: Semantics(
                  button: true,
                  label: '删除',
                  onTap: widget.onDelete,
                  excludeSemantics: true,
                  child: GestureDetector(
                    key: const ValueKey('live-emote-delete'),
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onDelete,
                    child: Container(
                      width: LiveSendTheme.deleteWidth,
                      height: LiveSendTheme.deleteHeight,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: LiveSendTheme.deleteFill,
                        borderRadius: BorderRadius.circular(LiveSendTheme.deleteRadius),
                      ),
                      child: const LiveDeleteGlyph(),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _bar(List<LiveEmotePackage> packages, int chosen) => ColoredBox(
    color: LiveSendTheme.barFill,
    child: Padding(
      padding: const EdgeInsets.only(bottom: LiveSendTheme.barBottom),
      child: SizedBox(
        height: LiveSendTheme.barCellHeight,
        child: ListView.builder(
          key: const ValueKey('live-emote-bar'),
          scrollDirection: Axis.horizontal,
          itemCount: packages.length,
          itemBuilder: (context, index) {
            final package = packages[index];
            final icon = package.icon.isNotEmpty ? package.icon : (package.emotes.firstOrNull?.url ?? '');
            void choose() => setState(() => _chosen = index);
            return Semantics(
              button: true,
              selected: index == chosen,
              label: package.name,
              onTap: choose,
              excludeSemantics: true,
              child: GestureDetector(
                key: ValueKey('live-emote-package-${package.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: choose,
                child: ColoredBox(
                  color: index == chosen ? LiveSendTheme.panelFill : LiveSendTheme.barFill,
                  child: SizedBox(
                    width: LiveSendTheme.barCellWidth,
                    child: Center(
                      child: SizedBox.square(
                        dimension: LiveSendTheme.barIcon,
                        child: RemoteImage(icon, fit: BoxFit.contain, placeholder: const SizedBox.shrink()),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// An emote's picture in a cell that takes the tap.
class LiveEmoteButton extends StatelessWidget {
  const LiveEmoteButton({
    super.key,
    required this.emote,
    required this.size,
    required this.onTap,
    this.width,
    this.keyPrefix = 'live-emote',
  });

  final LiveEmote emote;
  final double size;
  final ValueChanged<LiveEmote> onTap;

  /// The cell's width; the grid's cell when null.
  final double? width;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    void tap() => onTap(emote);
    return Semantics(
      button: true,
      label: emote.text,
      onTap: tap,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('$keyPrefix-${emote.unique.isNotEmpty ? emote.unique : emote.text}'),
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: SizedBox(
          width: width,
          child: Center(
            child: SizedBox.square(
              dimension: size,
              child: RemoteImage(emote.url, fit: BoxFit.contain, placeholder: const SizedBox.shrink()),
            ),
          ),
        ),
      ),
    );
  }
}

/// The input's words: the system font, untracked, undecorated.
TextStyle sendStyle(double size, Color color, {FontWeight? weight}) => TextStyle(
  fontFamily: BiliFonts.family,
  fontFamilyFallback: BiliFonts.fallback,
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: 0,
  decoration: TextDecoration.none,
);
