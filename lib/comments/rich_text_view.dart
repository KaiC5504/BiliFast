import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart' hide RichText;
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../shared/remote_image.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import '../video/intro/desc_text.dart' show linkTarget;

/// A reply inside a thread starts "回复 @名字 :". When the server sent no mid for that name the runs keep it as text,
/// so the name is made a mention here (mid 0, blue but leading nowhere) like the others.
List<RichRun> markingReplyTarget(List<RichRun> runs) {
  const lead = '回复 @';
  if (runs.firstOrNull case TextRun(:final text) when text.startsWith(lead)) {
    final rest = text.substring(lead.length);
    final colon = rest.indexOf(RegExp('[:：]'));
    if (colon < 0) return runs;
    final written = rest.substring(0, colon);
    final name = written.trim();
    if (name.isEmpty) return runs;
    final trailing = written.endsWith(' ') ? ' ' : '';
    return [
      const RichRun.text('回复 '),
      RichRun.mention(name: name, mid: 0),
      RichRun.text('$trailing${rest.substring(colon)}'),
      ...runs.skip(1),
    ];
  }
  return runs;
}

/// A comment's text (BiliNative `RichTextView`): emotes inline, sized from the text (large ones bigger), @mentions,
/// links and video ids in the link blue, timestamps that seek, a 笔记 link as a "[笔记]" lead. [leading] goes first,
/// as a reply preview's "name: ".
class CommentText extends StatefulWidget {
  const CommentText({
    super.key,
    required this.runs,
    required this.style,
    this.leading,
    this.maxLines,
    this.onSeek,
    this.onOpenVideo,
    this.openLink = _openInBrowser,
    this.marksReplyTarget = true,
  });

  final List<RichRun> runs;
  final TextStyle style;
  final InlineSpan? leading;

  /// Ends in an ellipsis when set.
  final int? maxLines;
  final ValueChanged<int>? onSeek;
  final ValueChanged<String>? onOpenVideo;

  /// A web link or a mention's space page; the browser by default. False when nothing could open it.
  final Future<bool> Function(Uri link) openLink;

  /// Turns a leading "回复 @名字 :" into a mention, as [markingReplyTarget].
  final bool marksReplyTarget;

  static Future<bool> _openInBrowser(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);

  @override
  State<CommentText> createState() => _CommentTextState();
}

class _CommentTextState extends State<CommentText> {
  final _recognizers = <TapGestureRecognizer>[];
  late List<InlineSpan> _spans;
  bool _hasEmote = false;

  @override
  void initState() {
    super.initState();
    _spans = _build();
  }

  @override
  void didUpdateWidget(CommentText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Taps read the callbacks when they happen; only what changes the spans' looks needs new spans.
    if (!listEquals(oldWidget.runs, widget.runs) ||
        oldWidget.style.fontSize != widget.style.fontSize ||
        oldWidget.marksReplyTarget != widget.marksReplyTarget ||
        (oldWidget.onSeek == null) != (widget.onSeek == null) ||
        (oldWidget.onOpenVideo == null) != (widget.onOpenVideo == null)) {
      _spans = _build();
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
  }

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(recognizer);
    return recognizer;
  }

  Future<void> _open(Uri link) async {
    var opened = false;
    try {
      opened = await widget.openLink(link);
    } catch (error) {
      Logger.shared.warn(LogCategory.ui, 'comment link failed', {'error': '$error'});
    }
    if (!opened && mounted) showToast(context, '无法打开链接');
  }

  List<InlineSpan> _build() {
    _disposeRecognizers();
    _hasEmote = widget.runs.any((run) => run is EmoteRun && run.url.isNotEmpty);
    const linked = TextStyle(color: CommentTextTheme.link);
    final fontSize = widget.style.fontSize ?? kDefaultFontSize;
    final runs = widget.marksReplyTarget ? markingReplyTarget(widget.runs) : widget.runs;
    return [
      for (final run in runs)
        switch (run) {
          TextRun(:final text) => TextSpan(text: text),
          EmoteRun(:final token, :final url) when url.isEmpty => TextSpan(text: token),
          EmoteRun(:final token, :final url, :final size) => _emote(token, url, size, fontSize),
          MentionRun(:final name, :final mid) => TextSpan(
            text: name.startsWith('@') ? name : '@$name',
            style: linked,
            recognizer: mid > 0 ? _tap(() => unawaited(_open(Uri.parse('https://space.bilibili.com/$mid')))) : null,
          ),
          TimestampRun(:final label, :final seconds) =>
            widget.onSeek == null
                ? TextSpan(text: label)
                : TextSpan(text: label, style: linked, recognizer: _tap(() => widget.onSeek?.call(seconds))),
          VideoRun(:final id) =>
            widget.onOpenVideo == null
                ? TextSpan(text: id)
                : TextSpan(text: id, style: linked, recognizer: _tap(() => widget.onOpenVideo?.call(id))),
          LinkRun() => _link(run, linked),
        },
    ];
  }

  /// A bilibili.com video address opens in the app; anything else on the web, or such an address when the page has
  /// nowhere to open videos, goes to the browser. A jump word with no web address stays plain.
  InlineSpan _link(LinkRun run, TextStyle linked) {
    final title = run.note ? '[笔记] ' : run.title;
    final target = linkTarget(run);
    if (target?.video case final id? when widget.onOpenVideo != null) {
      return TextSpan(text: title, style: linked, recognizer: _tap(() => widget.onOpenVideo?.call(id)));
    }
    final web = target?.web ?? (target == null ? null : Uri.tryParse(run.url));
    if (web == null) return TextSpan(text: title);
    return TextSpan(text: title, style: linked, recognizer: _tap(() => unawaited(_open(web))));
  }

  InlineSpan _emote(String token, String url, int size, double fontSize) {
    final side = fontSize * CommentTextTheme.emoteScale * math.max(size, 1);
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: _Emote(
        distance: side / 2 + fontSize * CommentTextTheme.emoteRise,
        child: Semantics(
          label: token,
          image: true,
          child: SizedBox.square(
            dimension: side,
            child: RemoteImage(url, size: Size.square(side), fit: BoxFit.contain, placeholder: const SizedBox.shrink()),
          ),
        ),
      ),
    );
  }

  /// How far below the baseline a line holding an emote reaches: the text's own descent plus
  /// [CommentTextTheme.emoteLineGrowth].
  double _emoteLineDescent(BuildContext context) {
    final defaults = DefaultTextStyle.of(context);
    final painter = TextPainter(
      text: TextSpan(text: '中', style: defaults.style.merge(widget.style)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      textHeightBehavior: defaults.textHeightBehavior,
    )..layout();
    final descent = painter.computeLineMetrics().firstOrNull?.descent ?? 0;
    painter.dispose();
    return descent + CommentTextTheme.emoteLineGrowth;
  }

  @override
  Widget build(BuildContext context) {
    final text = Text.rich(
      TextSpan(children: [?widget.leading, ..._spans]),
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.maxLines == null ? null : TextOverflow.ellipsis,
    );
    if (!_hasEmote) return text;
    return _EmoteLine(descent: _emoteLineDescent(context), child: text);
  }
}

class _EmoteLine extends InheritedWidget {
  const _EmoteLine({required this.descent, required super.child});

  final double descent;

  @override
  bool updateShouldNotify(_EmoteLine oldWidget) => descent != oldWidget.descent;
}

class _Emote extends StatelessWidget {
  const _Emote({required this.distance, required this.child});

  final double distance;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final descent = context.dependOnInheritedWidgetOfExactType<_EmoteLine>()?.descent ?? 0;
    return _Baseline(distance: distance, minHeight: distance + descent, child: child);
  }
}

/// Tells the paragraph its child's baseline is [distance] below its top, which sets an emote's middle where the text
/// wants it rather than its bottom on the baseline. The box reaches [minHeight] down, empty under the emote, so its
/// line grows below the text as 12's does.
class _Baseline extends SingleChildRenderObjectWidget {
  const _Baseline({required this.distance, required this.minHeight, super.child});

  final double distance;
  final double minHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBaseline(distance, minHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderBaseline renderObject) => renderObject
    ..distance = distance
    ..minHeight = minHeight;
}

class _RenderBaseline extends RenderProxyBox {
  _RenderBaseline(this._distance, this._minHeight);

  double _distance;
  double _minHeight;

  set distance(double value) {
    if (value == _distance) return;
    _distance = value;
    markNeedsLayout();
  }

  set minHeight(double value) {
    if (value == _minHeight) return;
    _minHeight = value;
    markNeedsLayout();
  }

  Size _grown(BoxConstraints constraints, Size child) =>
      constraints.constrain(Size(child.width, math.max(child.height, _minHeight)));

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = _grown(constraints, Size.zero);
      return;
    }
    child.layout(constraints.loosen(), parentUsesSize: true);
    size = _grown(constraints, child.size);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _grown(constraints, child?.getDryLayout(constraints.loosen()) ?? Size.zero);

  @override
  double computeMinIntrinsicHeight(double width) => math.max(super.computeMinIntrinsicHeight(width), _minHeight);

  @override
  double computeMaxIntrinsicHeight(double width) => math.max(super.computeMaxIntrinsicHeight(width), _minHeight);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _distance;

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) => _distance;
}
