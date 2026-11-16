import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/live.dart';
import 'package:flutter/widgets.dart';

import '../../../shared/remote_image.dart';
import '../../../shared/theme.dart';
import '../../live_badges.dart';
import '../live_chat_item.dart';

/// One row of the chat (207, 208, 228), at most the chat's width, from its left.
class RoomChatRow extends StatelessWidget {
  const RoomChatRow({super.key, required this.item, required this.now});

  final LiveChatItem item;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) => switch (item) {
    LiveChatNotice(:final text) => _Card(
      child: Text(
        text,
        key: const ValueKey('live-chat-notice'),
        style: liveStyle(LiveRoomTheme.rowText, LiveRoomTheme.ink, line: LiveRoomTheme.cardLine),
      ),
    ),
    final LiveChatRoomCard card => _RoomCard(card: card, now: now),
    LiveChatDanmaku(:final message) => _Capsule(child: _DanmakuText(message: message)),
    LiveChatInteraction(:final kind, :final user) => _Capsule(
      child: _InteractionText(kind: kind, user: user),
    ),
    LiveChatSuperChat(:final superChat) => RoomSuperChatRow(superChat: superChat),
    LiveChatTip(:final text) => _Capsule(
      child: Text(
        text,
        key: const ValueKey('live-chat-tip'),
        style: liveStyle(LiveRoomTheme.rowText, LiveRoomTheme.tipInk, line: LiveRoomTheme.rowLine),
      ),
    ),
  };
}

/// A row's translucent capsule, at least [LiveRoomTheme.rowMinHeight] tall.
class _Capsule extends StatelessWidget {
  const _Capsule({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: LiveRoomTheme.rowMinHeight),
    padding: const EdgeInsets.symmetric(
      horizontal: LiveRoomTheme.rowPadX,
      vertical: (LiveRoomTheme.rowMinHeight - LiveRoomTheme.rowLine) / 2,
    ),
    decoration: BoxDecoration(
      color: LiveRoomTheme.glass,
      borderRadius: BorderRadius.circular(LiveRoomTheme.rowMinHeight / 2),
    ),
    child: child,
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.bottom = LiveRoomTheme.cardPadY, this.top = LiveRoomTheme.cardPadY});

  final Widget child;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(LiveRoomTheme.rowPadX, top, LiveRoomTheme.rowPadX, bottom),
    decoration: BoxDecoration(
      color: LiveRoomTheme.glass,
      borderRadius: BorderRadius.circular(LiveRoomTheme.cardRadius),
    ),
    child: child,
  );
}

/// The chips a sender carries before their name: 荣耀等级, then the medal.
List<InlineSpan> _chips(LiveUser user) => [
  if (user.wealthLevel > 0) ...[
    WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: LiveWealthChip(level: user.wealthLevel, onDark: true),
    ),
    const WidgetSpan(child: SizedBox(width: LiveRoomTheme.rowChipGap)),
  ],
  if (user.medal case final medal?) ...[
    WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: LiveMedalChip(medal: medal),
    ),
    const WidgetSpan(child: SizedBox(width: LiveRoomTheme.rowNameGap)),
  ] else if (user.wealthLevel > 0)
    const WidgetSpan(child: SizedBox(width: LiveRoomTheme.rowNameGap - LiveRoomTheme.rowChipGap)),
];

Color _nameColour(LiveUser user) => liveColor(user.nameColor, LiveRoomTheme.nameBlue);

TextStyle get _rowStyle => liveStyle(LiveRoomTheme.rowText, LiveRoomTheme.ink, line: LiveRoomTheme.rowLine);

StrutStyle get _rowStrut => StrutStyle(
  fontFamily: BiliFonts.family,
  fontFamilyFallback: BiliFonts.fallback,
  fontSize: LiveRoomTheme.rowText,
  height: LiveRoomTheme.rowLine / LiveRoomTheme.rowText,
  leadingDistribution: TextLeadingDistribution.even,
  forceStrutHeight: true,
);

/// `name: text`, the name and colon in the sender's colour, inline emotes as pictures, a whole-message emote as one
/// bigger picture.
class _DanmakuText extends StatelessWidget {
  const _DanmakuText({required this.message});

  final LiveChatMessage message;

  @override
  Widget build(BuildContext context) {
    final big = message.bigEmote;
    final body = big != null
        ? <InlineSpan>[
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _Emote(emote: big, height: LiveRoomTheme.emoteBig, key: const ValueKey('live-chat-big-emote')),
            ),
          ]
        : _textWithEmotes(
            message.replyTo.isEmpty ? message.text : '@${message.replyTo} ${message.text}',
            message.emotes,
          );
    return Text.rich(
      TextSpan(
        style: _rowStyle,
        children: [
          ..._chips(message.user),
          TextSpan(
            text: '${message.user.name}: ',
            style: TextStyle(color: _nameColour(message.user)),
          ),
          ...body,
        ],
      ),
      key: ValueKey('live-chat-danmaku-${message.id}'),
      strutStyle: big == null ? _rowStrut : null,
    );
  }

  static List<InlineSpan> _textWithEmotes(String text, Map<String, LiveEmote> emotes) {
    if (emotes.isEmpty) return [TextSpan(text: text)];
    final pattern = RegExp(emotes.keys.map(RegExp.escape).join('|'));
    final spans = <InlineSpan>[];
    var at = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > at) spans.add(TextSpan(text: text.substring(at, match.start)));
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _Emote(emote: emotes[match[0]]!, height: LiveRoomTheme.emoteInline),
        ),
      );
      at = match.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return spans;
  }
}

class _Emote extends StatelessWidget {
  const _Emote({super.key, required this.emote, required this.height});

  final LiveEmote emote;
  final double height;

  @override
  Widget build(BuildContext context) {
    final width = emote.width > 0 && emote.height > 0 ? height * emote.width / emote.height : height;
    return SizedBox(
      width: width,
      height: height,
      child: RemoteImage(emote.url, fit: BoxFit.contain, placeholder: const SizedBox.shrink()),
    );
  }
}

/// 进入直播间, 关注了主播, 分享了直播间, 为主播点赞了: the name in its colour, the words in white.
class _InteractionText extends StatelessWidget {
  const _InteractionText({required this.kind, required this.user});

  final LiveInteraction kind;
  final LiveUser user;

  static String words(LiveInteraction kind) => switch (kind) {
    LiveInteraction.entered => '进入直播间',
    LiveInteraction.followed => '关注了主播',
    LiveInteraction.shared => '分享了直播间',
    LiveInteraction.liked => '为主播点赞了',
  };

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      style: _rowStyle,
      children: [
        ..._chips(user),
        TextSpan(
          text: user.name,
          style: TextStyle(color: _nameColour(user)),
        ),
        TextSpan(text: ' ${words(kind)}'),
      ],
    ),
    key: ValueKey('live-chat-interaction-${kind.name}'),
    strutStyle: _rowStrut,
  );
}

/// The room's card (207): its title, the announcement and how long it has been live, ticking.
class _RoomCard extends StatefulWidget {
  const _RoomCard({required this.card, required this.now});

  final LiveChatRoomCard card;
  final DateTime Function() now;

  @override
  State<_RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<_RoomCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(_RoomCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _follow();
  }

  void _follow() {
    if (widget.card.liveTime == null) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String clock(Duration elapsed) {
    final seconds = elapsed.isNegative ? 0 : elapsed.inSeconds;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(seconds ~/ 3600)}:${two(seconds ~/ 60 % 60)}:${two(seconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final liveTime = card.liveTime;
    return _Card(
      top: LiveRoomTheme.roomPadTop,
      bottom: LiveRoomTheme.roomPadBottom,
      child: Column(
        key: const ValueKey('live-chat-room-card'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card.title,
            style: liveStyle(LiveRoomTheme.rowText, LiveRoomTheme.ink, line: LiveRoomTheme.roomTitleLine),
          ),
          if (card.description.isNotEmpty)
            Text(
              card.description,
              style: liveStyle(LiveRoomTheme.roomTextSize, LiveRoomTheme.ink, line: LiveRoomTheme.cardLine),
            ),
          if (liveTime != null)
            Text(
              clock(widget.now().difference(liveTime)),
              key: const ValueKey('live-chat-room-time'),
              style: liveStyle(LiveRoomTheme.roomTextSize, LiveRoomTheme.roomTimeInk, line: LiveRoomTheme.roomTimeLine),
            ),
        ],
      ),
    );
  }
}

/// A 醒目留言 in the chat (228): the header band with the sender and the 电池, the message on the band under it, in the
/// 醒目留言's own colours.
class RoomSuperChatRow extends StatelessWidget {
  const RoomSuperChatRow({super.key, required this.superChat});

  final LiveSuperChat superChat;

  @override
  Widget build(BuildContext context) {
    final sc = superChat;
    final header = liveColor(sc.background, LiveRoomTheme.superChatHeaderFallback);
    final body = liveColor(sc.backgroundBottom, LiveRoomTheme.superChatFallback);
    final ink = liveStyle(LiveRoomTheme.rowText, LiveRoomTheme.scHeaderInk, line: LiveRoomTheme.scRowHeader);
    return Opacity(
      opacity: LiveRoomTheme.cardAlpha,
      child: Container(
        key: ValueKey('live-chat-sc-${sc.id}'),
        decoration: BoxDecoration(
          color: body,
          border: Border.all(color: body, width: LiveRoomTheme.scRowBorder),
          borderRadius: BorderRadius.circular(LiveRoomTheme.scRowRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: LiveRoomTheme.scRowHeader,
              decoration: BoxDecoration(
                color: header,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(LiveRoomTheme.scRowRadius - 1)),
              ),
              padding: const EdgeInsets.only(
                left: LiveRoomTheme.scRowHeaderPad - LiveRoomTheme.scRowBorder,
                right: LiveRoomTheme.scRowPriceRight - LiveRoomTheme.scRowBorder,
              ),
              child: Row(
                children: [
                  if (sc.user.medal case final medal?) ...[
                    LiveMedalChip(medal: medal),
                    const SizedBox(width: LiveRoomTheme.rowNameGap),
                  ],
                  Expanded(
                    child: Text(sc.user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ink),
                  ),
                  Text('${sc.batteries} 电池', maxLines: 1, style: ink),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LiveRoomTheme.scRowBodyPad - LiveRoomTheme.scRowBorder,
                vertical: (LiveRoomTheme.scRowBody - LiveRoomTheme.rowLine) / 2,
              ),
              child: Text(
                sc.message,
                style: liveStyle(LiveRoomTheme.rowText, LiveRoomTheme.ink, line: LiveRoomTheme.rowLine),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
