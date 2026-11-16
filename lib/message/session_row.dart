import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../comments/comment_badges.dart' show DecorImage;
import '../home/home_tab_bar.dart' show TabCount;
import '../search/results/user_row.dart' show VerifiedBoltPainter;
import '../shared/menu.dart' show PressHighlight;
import '../shared/remote_image.dart';
import '../shared/theme.dart';
import 'message_dates.dart';
import 'notice_box_icon.dart';

TextStyle messageStyle(double size, Color colour, {double? line, FontWeight weight = FontWeight.w400}) => TextStyle(
  fontFamily: BiliFonts.family,
  fontFamilyFallback: BiliFonts.fallback,
  fontSize: size,
  fontWeight: weight,
  color: colour,
  height: line == null ? null : line / size,
  leadingDistribution: line == null ? null : TextLeadingDistribution.even,
  letterSpacing: 0,
  decoration: TextDecoration.none,
);

/// One line of [text] in [style], cut with an ellipsis, its line box centred where it is placed.
Widget messageLine(String text, TextStyle style, {Key? key, TextAlign align = TextAlign.left}) => Text(
  text,
  key: key,
  style: style,
  strutStyle: BiliFonts.strut(style),
  maxLines: 1,
  softWrap: false,
  overflow: TextOverflow.ellipsis,
  textAlign: align,
);

/// A row of 消息's session list (196): the face (or a notice box's pink one) with its badge and red count, the name,
/// the date and the last message.
class SessionRow extends StatelessWidget {
  const SessionRow({super.key, required this.session, required this.now, required this.onTap, this.counts = true});

  final ChatSession session;

  /// What the date is told from.
  final DateTime now;
  final VoidCallback onTap;

  /// 消息提醒 is on: the red count shows.
  final bool counts;

  @override
  Widget build(BuildContext context) {
    final session = this.session;
    final box = session.box;
    final id = box?.name ?? '${session.talkerId}';
    final name = messageStyle(
      MessageTabTheme.nameText,
      session.vipPink ? MessageTabTheme.vipName : MessageTabTheme.name,
      line: MessageTabTheme.nameLine,
    );
    final date = messageStyle(MessageTabTheme.dateText, MessageTabTheme.date, line: MessageTabTheme.dateLine);
    final last = messageStyle(MessageTabTheme.lastText, MessageTabTheme.last, line: MessageTabTheme.lastLine);
    final unread = counts ? session.unread : 0;
    return Semantics(
      button: true,
      label: session.name,
      value: unread > 0 ? '${TabCount.label(unread)}条未读' : null,
      onTap: onTap,
      excludeSemantics: true,
      child: PressHighlight(
        key: ValueKey('message-session-$id'),
        onTap: onTap,
        child: SizedBox(
          height: MessageTabTheme.row,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: MessageTabTheme.faceLeft,
                top: (MessageTabTheme.row - MessageTabTheme.face) / 2,
                width: MessageTabTheme.face,
                height: MessageTabTheme.face,
                child: box == null ? SessionFace(session: session) : NoticeBoxIcon(box, size: MessageTabTheme.face),
              ),
              if (unread > 0)
                Positioned(
                  left: MessageTabTheme.faceLeft + MessageTabTheme.face - MessageTabTheme.countFaceInset,
                  top: (MessageTabTheme.row - MessageTabTheme.face) / 2 + MessageTabTheme.countFaceInset,
                  child: FractionalTranslation(
                    translation: const Offset(-0.5, -0.5),
                    child: TabCount(unread, key: ValueKey('message-session-count-$id')),
                  ),
                ),
              Positioned(
                left: MessageTabTheme.textLeft,
                right: MessageTabTheme.dateRight,
                top: MessageTabTheme.nameCentre - MessageTabTheme.nameLine / 2,
                height: MessageTabTheme.nameLine,
                child: Row(
                  children: [
                    Expanded(child: messageLine(session.name, name, key: ValueKey('message-session-name-$id'))),
                    const SizedBox(width: MessageTabTheme.nameGap),
                    messageLine(noticeDate(session.time, now: now), date, key: ValueKey('message-session-date-$id')),
                  ],
                ),
              ),
              Positioned(
                left: MessageTabTheme.textLeft,
                right: MessageTabTheme.lastRight,
                top: MessageTabTheme.lastCentre - MessageTabTheme.lastLine / 2,
                height: MessageTabTheme.lastLine,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: messageLine(session.lastText, last, key: ValueKey('message-session-text-$id')),
                ),
              ),
              const Positioned(
                left: MessageTabTheme.textLeft,
                right: 0,
                bottom: 0,
                height: MessageTabTheme.hairline,
                child: ColoredBox(color: MessageTabTheme.hairlineInk),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A person's face in a session row: smaller inside a pendant frame, with the verify bolt or else 大会员's 大 on its
/// bottom right.
class SessionFace extends StatelessWidget {
  const SessionFace({super.key, required this.session});

  final ChatSession session;

  @override
  Widget build(BuildContext context) {
    final session = this.session;
    final pendant = session.pendant.isNotEmpty;
    final face = pendant ? MessageTabTheme.pendantFace : MessageTabTheme.face;
    const frame = MessageTabTheme.pendantFace * MessageTabTheme.pendantScale;
    final bolt = switch (session.verify) {
      DynamicVerify.personal => MessageTabTheme.badgePerson,
      DynamicVerify.organisation => MessageTabTheme.badgeOrganisation,
      DynamicVerify.none => null,
    };
    final inset = (MessageTabTheme.face - face) / 2 - MessageTabTheme.badgeRing;
    final id = session.talkerId;
    return ExcludeSemantics(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          SizedBox.square(
            dimension: face,
            child: ClipOval(child: RemoteImage.avatar(session.face)),
          ),
          if (pendant)
            OverflowBox(
              maxWidth: frame,
              maxHeight: frame,
              child: IgnorePointer(
                child: SizedBox.square(
                  key: ValueKey('message-session-pendant-$id'),
                  dimension: frame,
                  child: DecorImage(session.pendant),
                ),
              ),
            ),
          if (bolt != null || session.bigVip)
            Positioned(
              right: inset,
              bottom: inset,
              child: _Badge(
                key: ValueKey(bolt != null ? 'message-session-verified-$id' : 'message-session-vip-$id'),
                child: bolt != null ? CustomPaint(painter: VerifiedBoltPainter(bolt)) : const _VipMark(),
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: MessageTabTheme.badge + MessageTabTheme.badgeRing * 2,
    height: MessageTabTheme.badge + MessageTabTheme.badgeRing * 2,
    padding: const EdgeInsets.all(MessageTabTheme.badgeRing),
    decoration: const BoxDecoration(color: MessageTabTheme.badgeRim, shape: BoxShape.circle),
    child: child,
  );
}

class _VipMark extends StatelessWidget {
  const _VipMark();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(color: MessageTabTheme.vipFill, shape: BoxShape.circle),
    child: Center(
      child: Text(
        '大',
        style: messageStyle(
          MessageTabTheme.vipText,
          MessageTabTheme.vipInk,
          weight: MessageTabTheme.vipWeight,
        ).copyWith(height: 1),
      ),
    ),
  );
}
