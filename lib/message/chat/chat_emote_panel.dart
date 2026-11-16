import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/widgets.dart';

import '../../shared/remote_image.dart';
import '../../shared/theme.dart';
import 'chat_glyphs.dart';
import 'chat_rows.dart' show chatStyle;

/// 219's emote panel in the keyboard's place under a chat's composer: the shown package's emotes (🕒's recently used
/// ones) under a grab handle, and the bar of ⚙, 🔍 and ★ (the page toasts 暂未开放), 🕒 and the packages.
class ChatEmotePanel extends StatefulWidget {
  const ChatEmotePanel({
    super.key,
    required this.packages,
    required this.recent,
    required this.height,
    required this.bottomInset,
    required this.onPick,
    required this.onUnavailable,
    this.onRetry,
  });

  /// Null while they load or after a failure.
  final List<EmotePackage>? packages;

  /// Read as 🕒 is shown, so it holds what was picked since the panel opened.
  final List<Emote> Function() recent;

  /// The whole panel, the bar and the home indicator's strip included.
  final double height;
  final double bottomInset;
  final ValueChanged<Emote> onPick;
  final VoidCallback onUnavailable;

  /// Set once loading failed: a tap on the message asks again.
  final VoidCallback? onRetry;

  @override
  State<ChatEmotePanel> createState() => _ChatEmotePanelState();
}

class _ChatEmotePanelState extends State<ChatEmotePanel> {
  int? _package;
  bool _recent = false;

  EmotePackage? get _selected {
    final packages = widget.packages;
    if (packages == null || packages.isEmpty) return null;
    for (final package in packages) {
      if (package.id == _package) return package;
    }
    return packages.first;
  }

  @override
  Widget build(BuildContext context) {
    final grid = math.max(0.0, widget.height - MessageChatTheme.barHeight - widget.bottomInset);
    final selected = _selected;
    return SizedBox(
      key: const ValueKey('chat-emote-panel'),
      height: widget.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: grid,
            child: ColoredBox(
              color: MessageChatTheme.panelFill,
              child: Stack(
                children: [
                  Positioned.fill(child: _content(selected)),
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: MessageChatTheme.panelLineTop,
                    height: MessageChatTheme.panelLine,
                    child: ColoredBox(color: MessageChatTheme.panelLineInk),
                  ),
                  Positioned(
                    top: MessageChatTheme.handleTop,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        key: const ValueKey('chat-emote-handle'),
                        width: MessageChatTheme.handleWidth,
                        height: MessageChatTheme.handleHeight,
                        decoration: BoxDecoration(
                          color: MessageChatTheme.handleInk,
                          borderRadius: BorderRadius.circular(MessageChatTheme.handleHeight / 2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: MessageChatTheme.barHeight,
            child: ColoredBox(color: MessageChatTheme.bar, child: _bar(selected)),
          ),
          SizedBox(
            height: widget.bottomInset,
            child: const ColoredBox(color: MessageChatTheme.bar),
          ),
        ],
      ),
    );
  }

  Widget _content(EmotePackage? selected) {
    if (_recent) return _grid(widget.recent(), key: const ValueKey('chat-emote-grid-recent'));
    if (selected == null) return _state();
    final key = ValueKey('chat-emote-grid-${selected.id}');
    if (selected.isText) {
      return _grid(
        selected.emotes,
        key: key,
        columns: MessageChatTheme.textColumns,
        row: MessageChatTheme.textRow,
        side: 0,
      );
    }
    if (selected.emotes.any((emote) => emote.large)) {
      return _grid(
        selected.emotes,
        key: key,
        columns: MessageChatTheme.largeColumns,
        row: MessageChatTheme.largeRow,
        side: MessageChatTheme.largeEmote,
      );
    }
    return _grid(selected.emotes, key: key);
  }

  Widget _state() {
    final onRetry = widget.onRetry;
    if (onRetry == null && widget.packages == null) {
      return const Center(child: CupertinoActivityIndicator(radius: MessageChatTheme.panelSpinnerRadius));
    }
    const message = '表情加载失败，点击重试';
    return Semantics(
      key: const ValueKey('chat-emote-retry'),
      button: onRetry != null,
      label: message,
      onTap: onRetry,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onRetry,
        child: Center(child: Text(message, style: chatStyle(MessageChatTheme.tipText, MessageChatTheme.grey))),
      ),
    );
  }

  Widget _grid(
    List<Emote> emotes, {
    required Key key,
    int columns = MessageChatTheme.columns,
    double row = MessageChatTheme.row,
    double side = MessageChatTheme.emoteSide,
  }) => GridView.builder(
    // Another package starts at its top.
    key: key,
    padding: const EdgeInsets.fromLTRB(
      MessageChatTheme.gridSide,
      MessageChatTheme.gridTop,
      MessageChatTheme.gridSide,
      0,
    ),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, mainAxisExtent: row),
    itemCount: emotes.length,
    itemBuilder: (context, index) => _cell(emotes[index], side: side),
  );

  Widget _cell(Emote emote, {required double side}) {
    final Widget picture;
    if (emote.url.isEmpty) {
      final style = chatStyle(MessageChatTheme.kaomojiText, MessageChatTheme.text);
      picture = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: MessageChatTheme.kaomojiPad),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              emote.token,
              maxLines: 1,
              softWrap: false,
              style: style,
              strutStyle: BiliFonts.strutOf(context, style),
            ),
          ),
        ),
      );
    } else {
      picture = Center(
        child: SizedBox.square(
          dimension: side,
          child: RemoteImage(emote.url, fit: BoxFit.contain, placeholder: const SizedBox.shrink()),
        ),
      );
    }
    return Semantics(
      button: true,
      label: emote.token,
      onTap: () => widget.onPick(emote),
      excludeSemantics: true,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => widget.onPick(emote), child: picture),
    );
  }

  Widget _bar(EmotePackage? selected) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        _Slot(
          key: const ValueKey('chat-emote-settings'),
          label: '设置',
          onTap: widget.onUnavailable,
          child: const ChatGlyph(
            ChatArt.settings,
            width: MessageChatTheme.barGearWidth,
            height: MessageChatTheme.barGearHeight,
            color: MessageChatTheme.dim,
          ),
        ),
        _Slot(
          key: const ValueKey('chat-emote-search'),
          label: '搜索',
          onTap: widget.onUnavailable,
          badge: const _NewTag(),
          child: const ChatGlyph(
            ChatArt.emoteSearch,
            width: MessageChatTheme.barGlyph,
            height: MessageChatTheme.barGlyph,
            color: MessageChatTheme.dim,
          ),
        ),
        _Slot(
          key: const ValueKey('chat-emote-recent'),
          label: '最近使用',
          selected: _recent,
          onTap: () => setState(() => _recent = true),
          child: const ChatGlyph(
            ChatArt.emoteRecent,
            width: MessageChatTheme.barGlyph,
            height: MessageChatTheme.barGlyph,
            color: MessageChatTheme.dim,
          ),
        ),
        _Slot(
          key: const ValueKey('chat-emote-favourites'),
          label: '收藏',
          onTap: widget.onUnavailable,
          child: Transform.translate(
            offset: const Offset(0, -MessageChatTheme.barStarLift),
            child: const ChatGlyph(
              ChatArt.emoteStar,
              width: MessageChatTheme.barStarWidth,
              height: MessageChatTheme.barStarHeight,
              color: MessageChatTheme.barStar,
            ),
          ),
        ),
        for (final package in widget.packages ?? const <EmotePackage>[])
          _Slot(
            key: ValueKey('chat-emote-tab-${package.id}'),
            label: package.name,
            selected: !_recent && package.id == selected?.id,
            onTap: () => setState(() {
              _recent = false;
              _package = package.id;
            }),
            child: _packageIcon(package),
          ),
      ],
    ),
  );

  Widget _packageIcon(EmotePackage package) {
    if (!package.isText && package.icon.isNotEmpty) {
      return SizedBox.square(
        dimension: MessageChatTheme.packageIcon,
        child: RemoteImage(package.icon, fit: BoxFit.contain, placeholder: const SizedBox.shrink()),
      );
    }
    final label = package.isText ? (package.emotes.firstOrNull?.token ?? package.name) : package.name;
    final style = chatStyle(MessageChatTheme.kaomojiTabText, MessageChatTheme.kaomojiTab);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MessageChatTheme.kaomojiTabPad),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, maxLines: 1, softWrap: false, style: style, strutStyle: BiliFonts.strutOf(context, style)),
      ),
    );
  }
}

/// One 50 pt slot of the bar, on the page's grey while its emotes are shown.
class _Slot extends StatelessWidget {
  const _Slot({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.selected = false,
    this.badge,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool selected;
  final Widget? badge;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: MessageChatTheme.barSlot,
        height: MessageChatTheme.barHeight,
        color: selected ? MessageChatTheme.barSelected : null,
        child: Stack(
          children: [
            Center(child: child),
            if (badge case final badge?)
              Positioned(left: MessageChatTheme.newLeft, top: MessageChatTheme.newTop, child: badge),
          ],
        ),
      ),
    ),
  );
}

/// 🔍's pink NEW.
class _NewTag extends StatelessWidget {
  const _NewTag();

  @override
  Widget build(BuildContext context) => Container(
    width: MessageChatTheme.newWidth,
    height: MessageChatTheme.newHeight,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: MessageChatTheme.newFill,
      borderRadius: BorderRadius.circular(MessageChatTheme.newRadius),
    ),
    child: Text(
      'NEW',
      maxLines: 1,
      softWrap: false,
      style: chatStyle(MessageChatTheme.newText, MessageChatTheme.newInk, line: MessageChatTheme.newHeight),
    ),
  );
}
