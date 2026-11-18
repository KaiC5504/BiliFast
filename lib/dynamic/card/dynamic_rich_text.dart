import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bili_core/api.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../shared/remote_image.dart';
import '../../shared/theme.dart';
import '../../shared/toast.dart';
import '../../space/uploader_tap.dart';
import '../../video/video_route.dart';
import 'dynamic_open.dart';

/// A post's text: topics and links blue, emotes inline, @names opening the space, a video link (▶) opening the video,
/// badges (🎁 互动抽奖) toasting. Past [maxLines], or always when [folded], it ends in ... [moreLabel] (全文 / 展开),
/// tapped to [onMore]. An @name run into the words around it is set apart from them (29).
class DynamicRichText extends StatefulWidget {
  const DynamicRichText({
    super.key,
    required this.nodes,
    required this.style,
    this.maxLines,
    this.folded = false,
    this.moreLabel = '全文',
    this.onMore,
    this.wideTopicGaps = false,
    this.emoteLinesGrow = false,
    this.ellipsisInk,
    this.moreInk,
  });

  final List<DynamicNode> nodes;
  final TextStyle style;
  final int? maxLines;

  /// The server cut the text, so … [moreLabel] shows even when it fits.
  final bool folded;
  final String moreLabel;
  final VoidCallback? onMore;

  /// The spaces beside topics [DynamicCardTheme.topicGap] wider, as a 图文 post's text on 关注 (135, 29).
  final bool wideTopicGaps;

  /// A line holding an emote grows past the pitch, as 图文's text on 关注 does (243); see
  /// [DynamicCardTheme.pingFangAscent].
  final bool emoteLinesGrow;

  /// The ... and [moreLabel] in these instead of the text's colour and the link blue (29's repost block).
  final Color? ellipsisInk;
  final Color? moreInk;

  /// What the text ends with when cut: three periods and a space before [moreLabel] (127, 128).
  static const ellipsis = '... ';

  @override
  State<DynamicRichText> createState() => _DynamicRichTextState();
}

class _DynamicRichTextState extends State<DynamicRichText> {
  final _recognizers = <TapGestureRecognizer>[];
  TapGestureRecognizer? _more;
  late List<_Run> _runs;
  late int _units;
  bool _large = false;
  bool _grown = false;

  /// The runs carry the link colour of the mode they were made in.
  bool _builtDark = BiliTheme.dark;

  /// The last cut, kept while nothing that decides it changes.
  Object? _cutFor;
  int? _cut;

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void didUpdateWidget(DynamicRichText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.nodes, widget.nodes) ||
        oldWidget.style.fontSize != widget.style.fontSize ||
        oldWidget.style.height != widget.style.height ||
        oldWidget.wideTopicGaps != widget.wideTopicGaps ||
        oldWidget.emoteLinesGrow != widget.emoteLinesGrow ||
        (oldWidget.onMore == null) != (widget.onMore == null)) {
      _build();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    _more?.dispose();
    _more = null;
  }

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(recognizer);
    return recognizer;
  }

  void _build() {
    _builtDark = BiliTheme.dark;
    _disposeRecognizers();
    _cutFor = null;
    _more = widget.onMore == null ? null : (TapGestureRecognizer()..onTap = () => widget.onMore?.call());
    final linked = TextStyle(color: DynamicCardTheme.linkInk);
    final runs = <_Run>[];
    _large = false;
    _grown = false;
    final scale = (widget.style.fontSize ?? DynamicCardTheme.text) / DynamicCardTheme.text;
    final growth = widget.emoteLinesGrow ? _EmoteGrowth.of(widget.style) : null;
    final nodes = widget.nodes;
    // True right after the space put in after an @name: the next @name is still set apart from it.
    var spaced = false;
    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      final afterSpaced = spaced;
      spaced = false;
      switch (node) {
        case DynamicTextNode(:final text):
          bool besideTopic(int at) =>
              widget.wideTopicGaps && at >= 0 && at < nodes.length && nodes[at] is DynamicTopicNode;
          _addText(runs, text, widenFirst: besideTopic(index - 1), widenLast: besideTopic(index + 1));
        case DynamicEmojiNode(:final text, :final url) when url.isEmpty:
          runs.add(_TextRun(text));
        case DynamicEmojiNode(:final text, :final url, :final large):
          if (large) _large = true;
          final side = large ? DynamicCardTheme.emoteLarge : DynamicCardTheme.emote;
          final emote = Semantics(
            label: text,
            image: true,
            child: RemoteImage(url, size: Size.square(side), fit: BoxFit.contain, placeholder: const SizedBox.shrink()),
          );
          if (growth != null && !large) {
            _grown = true;
            runs.add(
              _WidgetRun(
                Size(side, growth.box),
                Stack(
                  clipBehavior: Clip.none,
                  children: [Positioned(left: 0, top: growth.top, width: side, height: side, child: emote)],
                ),
                alignment: ui.PlaceholderAlignment.aboveBaseline,
              ),
            );
          } else {
            runs.add(_WidgetRun(Size.square(side), emote));
          }
        case DynamicMentionNode(:final text, :final mid):
          final name = text.startsWith('@') ? text : '@$text';
          if (afterSpaced || _endsInWord(runs)) _lead(runs);
          runs.add(_TextRun(name, linked, mid > 0 ? _tap(() => _openSpace(mid, name)) : null));
          if (!_isSpace(name.codeUnitAt(name.length - 1)) && _wordNext(nodes, index)) {
            runs.add(_TextRun(' '));
            spaced = true;
          }
        case DynamicTopicNode(:final text):
          runs.add(_TextRun(text, linked, _tap(_soon)));
        case DynamicLinkNode(:final text, :final url):
          runs.add(_TextRun(text, linked, _tap(() => unawaited(openDynamicLink(context, url)))));
        case DynamicVideoLinkNode(:final text, :final bvid):
          void open() => unawaited(DynamicOpen.video(context, VideoRoute(bvid: bvid)));
          runs
            ..add(
              _WidgetRun(
                const Size(
                  DynamicCardTheme.videoLinkBefore + DynamicCardTheme.videoLinkSide + DynamicCardTheme.videoLinkAfter,
                  DynamicCardTheme.videoLinkSide,
                ),
                _IconTap(
                  onTap: open,
                  before: DynamicCardTheme.videoLinkBefore,
                  child: DynamicIcon(
                    DynamicArt.videoLink,
                    width: DynamicCardTheme.videoLinkSide,
                    color: DynamicCardTheme.linkInk,
                  ),
                ),
              ),
            )
            ..add(_TextRun(text, linked, _tap(open)));
        case DynamicBadgeNode(:final text, :final kind):
          if (kind == 'lottery') {
            final before = DynamicCardTheme.giftBefore * scale;
            final width = DynamicCardTheme.giftWidth * scale;
            final height = DynamicCardTheme.giftHeight * scale;
            runs.add(
              _WidgetRun(
                Size(before + width + DynamicCardTheme.giftAfter * scale, height),
                _IconTap(
                  onTap: _soon,
                  before: before,
                  child: DynamicIcon(DynamicArt.gift, width: width, height: height, color: DynamicCardTheme.linkInk),
                ),
              ),
            );
          }
          runs.add(_TextRun(text, linked, _tap(_soon)));
      }
    }
    _runs = runs;
    _units = runs.fold(0, (sum, run) => sum + run.length);
  }

  void _soon() => showToast(context, notBuilt);

  static final _word = RegExp(r'[\p{L}\p{N}]', unicode: true);

  static bool _isWord(int rune) => _word.hasMatch(String.fromCharCode(rune));

  static bool _isSpace(int unit) =>
      unit == 0x20 || unit == 0x0A || unit == 0x3000 || unit == 0x09 || unit == _zeroWidthSpace;

  static const _zeroWidthSpace = 0x200B;

  static bool _endsInWord(List<_Run> runs) => switch (runs.lastOrNull) {
    _TextRun(:final text) when text.isNotEmpty => _isWord(text.runes.last),
    _ => false,
  };

  /// Whether the node after [index] starts with a word (or is another @name), so an @name needs a space before it.
  static bool _wordNext(List<DynamicNode> nodes, int index) {
    if (index + 1 >= nodes.length) return false;
    return switch (nodes[index + 1]) {
      DynamicMentionNode() => true,
      DynamicEmojiNode(:final url) when url.isNotEmpty => false,
      DynamicVideoLinkNode() => false,
      DynamicBadgeNode(:final kind) when kind == 'lottery' => false,
      final next => next.text.isNotEmpty && _isWord(next.text.runes.first),
    };
  }

  /// [text] as a run, its first or last space widened by [DynamicCardTheme.topicGap] when a topic is on that side.
  static void _addText(List<_Run> runs, String text, {required bool widenFirst, required bool widenLast}) {
    if (text.isEmpty) return;
    final first = widenFirst && text.codeUnitAt(0) == 0x20;
    final last = widenLast && text.codeUnitAt(text.length - 1) == 0x20 && !(first && text.length == 1);
    final start = first ? 1 : 0;
    final end = last ? text.length - 1 : text.length;
    if (first) runs.add(_TextRun(' ', const TextStyle(letterSpacing: DynamicCardTheme.topicGap)));
    if (start < end) runs.add(_TextRun(text.substring(start, end)));
    if (last) runs.add(_TextRun(' ', const TextStyle(letterSpacing: DynamicCardTheme.topicGap)));
  }

  /// [DynamicCardTheme.mentionLead] after the last run, as letter spacing on its last character; after a link, badge or
  /// title on a zero-width space of its own instead, since splitting a tappable run makes it two elements to VoiceOver.
  static void _lead(List<_Run> runs) {
    final run = runs.last as _TextRun;
    if (run.recognizer != null) {
      runs.add(
        _TextRun(String.fromCharCode(_zeroWidthSpace), const TextStyle(letterSpacing: DynamicCardTheme.mentionLead)),
      );
      return;
    }
    runs.removeLast();
    final text = run.text;
    final cut = text.length - String.fromCharCode(text.runes.last).length;
    if (cut > 0) runs.add(_TextRun(text.substring(0, cut), run.style));
    final style = run.style ?? const TextStyle();
    runs.add(
      _TextRun(
        text.substring(cut),
        style.copyWith(letterSpacing: (style.letterSpacing ?? 0) + DynamicCardTheme.mentionLead),
      ),
    );
  }

  void _openSpace(int mid, String name) {
    final bare = name.startsWith('@') ? name.substring(1) : name;
    unawaited(DynamicOpen.space(context, UploaderRef(mid: mid, name: bare.isEmpty ? null : bare)));
  }

  /// The runs' first [units] as spans, the placeholders' dimensions in their order into [placeholders].
  List<InlineSpan> _spans(int units, List<PlaceholderDimensions> placeholders) {
    final spans = <InlineSpan>[];
    var left = units;
    for (final run in _runs) {
      if (left <= 0) break;
      final take = run.length < left ? run.length : left;
      spans.add(run.span(take, placeholders));
      left -= take;
    }
    return spans;
  }

  List<InlineSpan> _suffix() {
    final ellipsisInk = widget.ellipsisInk;
    return [
      TextSpan(
        text: DynamicRichText.ellipsis,
        style: ellipsisInk == null ? null : TextStyle(color: ellipsisInk),
      ),
      TextSpan(
        text: widget.moreLabel,
        style: TextStyle(color: widget.moreInk ?? DynamicCardTheme.linkInk),
        recognizer: _more,
      ),
    ];
  }

  /// How many units show before … [DynamicRichText.moreLabel], or null when the whole text shows as it is.
  int? _cutAt(BuildContext context, double width, TextStyle style, StrutStyle? strut) {
    final maxLines = widget.maxLines;
    if (maxLines == null || !width.isFinite) return null;
    final defaults = DefaultTextStyle.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    final key = (width, style, maxLines, widget.folded, widget.moreLabel, scaler);
    if (key == _cutFor) return _cut;

    bool fits(int units, {required bool withSuffix}) {
      final placeholders = <PlaceholderDimensions>[];
      final spans = _spans(units, placeholders);
      final painter = TextPainter(
        text: TextSpan(style: style, children: [...spans, if (withSuffix) ..._suffix()]),
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
        strutStyle: strut,
        textScaler: scaler,
        locale: locale,
        textHeightBehavior: defaults.textHeightBehavior,
        textWidthBasis: defaults.textWidthBasis,
      )..setPlaceholderDimensions(placeholders);
      painter.layout(maxWidth: width);
      final fit = !painter.didExceedMaxLines;
      painter.dispose();
      return fit;
    }

    int? cut;
    if (widget.folded || !fits(_units, withSuffix: false)) {
      if (fits(_units, withSuffix: true)) {
        cut = _units;
      } else {
        var low = 0, high = _units;
        while (low < high) {
          final middle = (low + high + 1) ~/ 2;
          if (fits(middle, withSuffix: true)) {
            low = middle;
          } else {
            high = middle - 1;
          }
        }
        cut = low;
      }
      cut = _trimmed(cut);
    }
    _cutFor = key;
    _cut = cut;
    return cut;
  }

  /// [units] less the spaces and line breaks they end with, so … follows the last word.
  int _trimmed(int units) {
    var at = units;
    while (at > 0) {
      final (run, offset) = _locate(at - 1);
      if (run is! _TextRun || !_isSpace(run.text.codeUnitAt(offset))) break;
      at -= 1;
    }
    return at;
  }

  (_Run, int) _locate(int unit) {
    var left = unit;
    for (final run in _runs) {
      if (left < run.length) return (run, left);
      left -= run.length;
    }
    return (_runs.last, _runs.last.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    if (_builtDark != BiliTheme.dark) _build();
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    var strut = _large ? null : BiliFonts.strut(style);
    // Forced, the strut holds every line to the pitch; an emote's line may only grow past a loose one.
    if (_grown && strut != null) {
      strut = StrutStyle(
        fontFamily: strut.fontFamily,
        fontSize: strut.fontSize,
        height: strut.height,
        leadingDistribution: strut.leadingDistribution,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final cut = _cutAt(context, constraints.maxWidth, style, strut);
        final spans = cut == null ? _spans(_units, []) : [..._spans(cut, []), ..._suffix()];
        return Text.rich(
          TextSpan(children: spans),
          style: widget.style,
          strutStyle: strut,
          maxLines: widget.maxLines,
          overflow: widget.maxLines == null ? null : TextOverflow.clip,
        );
      },
    );
  }
}

sealed class _Run {
  int get length;

  InlineSpan span(int units, List<PlaceholderDimensions> placeholders);
}

final class _TextRun extends _Run {
  _TextRun(this.text, [this.style, this.recognizer]);

  final String text;
  final TextStyle? style;
  final GestureRecognizer? recognizer;

  @override
  int get length => text.length;

  @override
  InlineSpan span(int units, List<PlaceholderDimensions> placeholders) {
    var end = units;
    // Never between the halves of a surrogate pair.
    if (end < text.length && end > 0 && _isHighSurrogate(text.codeUnitAt(end - 1))) end -= 1;
    return TextSpan(text: end >= text.length ? text : text.substring(0, end), style: style, recognizer: recognizer);
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
}

final class _WidgetRun extends _Run {
  _WidgetRun(this.size, this.child, {this.alignment = ui.PlaceholderAlignment.middle});

  final Size size;
  final Widget child;
  final ui.PlaceholderAlignment alignment;

  @override
  int get length => 1;

  @override
  InlineSpan span(int units, List<PlaceholderDimensions> placeholders) {
    placeholders.add(PlaceholderDimensions(size: size, alignment: alignment, baseline: TextBaseline.alphabetic));
    return WidgetSpan(
      alignment: alignment,
      baseline: TextBaseline.alphabetic,
      child: SizedBox.fromSize(size: size, child: child),
    );
  }
}

/// An emote in a line that grows for it ([DynamicCardTheme.pingFangAscent]): its placeholder [box] tall above the
/// baseline, so the line ends the grown height under the line before, and the emote [top] down in it.
final class _EmoteGrowth {
  const _EmoteGrowth(this.box, this.top);

  final double box;
  final double top;

  /// Null where the text isn't held to a pitch (no strut: not the system font, or no line height).
  static _EmoteGrowth? of(TextStyle style) {
    final size = style.fontSize;
    final height = style.height;
    if (size == null || height == null || BiliFonts.strut(style) == null) return null;
    final line = size * height;
    final natural = DynamicCardTheme.pingFangLine * size;
    final descent = DynamicCardTheme.pingFangDescent * size;
    const side = DynamicCardTheme.emote;
    final grown = math.max(line, (side + descent) * line / natural);
    // The strut's descent: PingFang's, with half the leading dynamicStyle spreads evenly.
    final box = grown - (descent + (line - natural) / 2);
    return _EmoteGrowth(box, box + descent - side);
  }
}

/// An icon inside the text, [before] in from its box's left, tapped as the words after it.
class _IconTap extends StatelessWidget {
  const _IconTap({required this.onTap, required this.before, required this.child});

  final VoidCallback onTap;
  final double before;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    excludeFromSemantics: true,
    onTap: onTap,
    child: Padding(
      padding: EdgeInsets.only(left: before),
      child: Align(alignment: Alignment.centerLeft, child: child),
    ),
  );
}
