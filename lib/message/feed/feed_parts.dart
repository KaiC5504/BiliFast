import 'package:flutter/widgets.dart';

import '../../shared/remote_image.dart';
import '../../shared/theme.dart';

TextStyle feedStyle(double size, Color color, {double? line, FontWeight weight = FontWeight.w400}) => TextStyle(
  fontFamily: BiliFonts.family,
  fontFamilyFallback: BiliFonts.fallback,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: line == null ? null : line / size,
  leadingDistribution: line == null ? null : TextLeadingDistribution.even,
  letterSpacing: 0,
  decoration: TextDecoration.none,
);

/// One line of [text] in [style], cut with … where it runs out.
Widget feedLine(String text, TextStyle style, {Key? key, TextAlign align = TextAlign.left}) => Text(
  text,
  key: key,
  style: style,
  strutStyle: BiliFonts.strut(style),
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  textAlign: align,
);

/// Words on a row's date line, lifted as 197 draws them; the row's label says them.
Widget feedDateWords(String text, TextStyle style) => ExcludeSemantics(
  child: Transform.translate(offset: const Offset(0, -MessageFeedTheme.dateLift), child: feedLine(text, style)),
);

/// A button to accessibility and to taps, its whole box answering.
class FeedTap extends StatelessWidget {
  const FeedTap({super.key, required this.label, required this.onTap, required this.child, this.selected});

  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final bool? selected;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: label,
    selected: selected,
    enabled: onTap != null,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: child),
  );
}

/// A row that is a button and holds buttons of its own (the face, 回复, 点赞, ⋮): its words are its [label], so the
/// rows' texts sit under [ExcludeSemantics], and the buttons inside stay buttons to VoiceOver and ghosthand.
class FeedRowTap extends StatelessWidget {
  const FeedRowTap({super.key, required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: label,
    onTap: onTap,
    child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: child),
  );
}

/// A round face, Bilibili's default while it loads and when there is none.
class FeedFace extends StatelessWidget {
  const FeedFace(this.url, {super.key});

  final String url;

  @override
  Widget build(BuildContext context) => ClipOval(child: RemoteImage.avatar(url));
}

/// The right column (197, 198): what was replied to or liked, else its picture.
class FeedSide extends StatelessWidget {
  const FeedSide({super.key, required this.text, required this.picture});

  final String text;
  final String picture;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty && picture.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(MessageFeedTheme.sidePictureRadius),
        child: SizedBox.square(dimension: MessageFeedTheme.sidePicture, child: RemoteImage(picture)),
      );
    }
    final style = feedStyle(MessageFeedTheme.sideText, MessageFeedTheme.sideInk, line: MessageFeedTheme.sideLine);
    return Text(
      text,
      style: style,
      strutStyle: BiliFonts.strut(style),
      maxLines: MessageFeedTheme.sideLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// An empty list (199, 213): the empty picture [top] under where the list starts, 这里还什么都没有呢～ with its middle
/// [textCentre] under the picture's top.
class FeedEmpty extends StatelessWidget {
  const FeedEmpty({super.key, required this.top, required this.textCentre});

  final double top;
  final double textCentre;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: top + textCentre + MessageFeedTheme.emptyLine / 2,
    child: Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: top,
          child: Center(
            child: Image.asset(
              'assets/images/friends/page_status_empty.png',
              width: MessageFeedTheme.emptyPicture,
              height: MessageFeedTheme.emptyPicture,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: top + textCentre - MessageFeedTheme.emptyLine / 2,
          height: MessageFeedTheme.emptyLine,
          child: feedLine(
            '这里还什么都没有呢～',
            feedStyle(MessageFeedTheme.emptyText, MessageFeedTheme.emptyInk, line: MessageFeedTheme.emptyLine),
            align: TextAlign.center,
          ),
        ),
      ],
    ),
  );
}

/// ⋮: three grey dots on top of each other, centred.
class FeedMorePainter extends CustomPainter {
  const FeedMorePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = MessageFeedTheme.moreInk;
    final centre = size.center(Offset.zero);
    for (final step in const [-1, 0, 1]) {
      canvas.drawCircle(centre.translate(0, step * MessageFeedTheme.moreSpacing), MessageFeedTheme.moreDot / 2, paint);
    }
  }

  @override
  bool shouldRepaint(FeedMorePainter oldDelegate) => false;
}

/// The ⋮ button, its box [MessageFeedTheme.moreTarget] wide and [height] tall around the dots.
class FeedMoreButton extends StatelessWidget {
  const FeedMoreButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FeedTap(
    label: '更多',
    onTap: onTap,
    child: const SizedBox(
      width: MessageFeedTheme.moreTarget,
      height: MessageFeedTheme.dateBox,
      child: CustomPaint(painter: FeedMorePainter()),
    ),
  );
}

/// The 2/3 rule under a row, the screen's width; its room alone under the last row.
class FeedRowRule extends StatelessWidget {
  const FeedRowRule({super.key, this.shown = true});

  final bool shown;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MessageFeedTheme.rowRule,
    child: shown ? const ColoredBox(color: MessageFeedTheme.rowRuleInk) : null,
  );
}
