import 'package:flutter/widgets.dart';

import 'theme.dart';

/// Bilibili's own white alert (211, 260): a title, an optional message, a rule, then [cancel] and the pink [action].
/// True once [action] is pressed; [cancel] or a tap on the dim gives false.
Future<bool> showBiliAlert(BuildContext context, AlertWords words) async =>
    await Navigator.of(context).push(_AlertRoute(words, reduceMotion: MediaQuery.disableAnimationsOf(context))) ??
    false;

/// An alert's words, and the key its box and buttons are found by (`<key>` and `<key>-<label>`).
class AlertWords {
  const AlertWords({required this.key, required this.title, this.message, this.cancel = '取消', required this.action});

  final String key;
  final String title;

  /// Null draws the title alone, centred in [MessageTabTheme.alertTitleOnlyBody].
  final String? message;
  final String cancel;
  final String action;
}

TextStyle _style(double size, Color colour, {double? line, FontWeight weight = FontWeight.w400}) => TextStyle(
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

class _AlertRoute extends PopupRoute<bool> {
  _AlertRoute(this.words, {required this.reduceMotion});

  final AlertWords words;
  final bool reduceMotion;

  @override
  Color? get barrierColor => MessageTabTheme.alertDim;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => words.cancel;

  @override
  Duration get transitionDuration => reduceMotion ? Duration.zero : MessageTabTheme.alertMotion;

  /// Centred between the status bar and the home indicator, as 211's and 260's.
  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) => SafeArea(
    child: Center(
      child: FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: MessageTabTheme.alertStartScale, end: 1.0).animate(animation),
          child: _Alert(
            words: words,
            onCancel: () => Navigator.of(context).pop(false),
            onConfirm: () => Navigator.of(context).pop(true),
          ),
        ),
      ),
    ),
  );
}

class _Alert extends StatelessWidget {
  const _Alert({required this.words, required this.onCancel, required this.onConfirm});

  final AlertWords words;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    Widget line(String text, TextStyle style, double centre, double height) => Positioned(
      left: 0,
      right: 0,
      top: centre - height / 2,
      height: height,
      child: Center(
        child: Text(text, maxLines: 1, style: style, strutStyle: BiliFonts.strut(style)),
      ),
    );
    final message = words.message;
    final body = message == null ? MessageTabTheme.alertTitleOnlyBody : MessageTabTheme.alertBody;
    return Container(
      key: ValueKey(words.key),
      width: MessageTabTheme.alertWidth,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: MessageTabTheme.alertFill,
        borderRadius: BorderRadius.circular(MessageTabTheme.alertRadius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: body,
            child: Stack(
              children: [
                line(
                  words.title,
                  _style(
                    MessageTabTheme.alertTitleText,
                    MessageTabTheme.alertTitle,
                    line: MessageTabTheme.alertTitleLine,
                    weight: MessageTabTheme.alertTitleWeight,
                  ),
                  message == null ? body / 2 : MessageTabTheme.alertTitleCentre,
                  MessageTabTheme.alertTitleLine,
                ),
                if (message != null)
                  line(
                    message,
                    _style(
                      MessageTabTheme.alertMessageText,
                      MessageTabTheme.alertMessage,
                      line: MessageTabTheme.alertMessageLine,
                    ),
                    MessageTabTheme.alertMessageCentre,
                    MessageTabTheme.alertMessageLine,
                  ),
              ],
            ),
          ),
          SizedBox(
            height: MessageTabTheme.alertRule,
            child: ColoredBox(color: MessageTabTheme.alertRuleInk),
          ),
          SizedBox(
            height: MessageTabTheme.alertButton,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _AlertButton(
                    keyPrefix: words.key,
                    label: words.cancel,
                    colour: MessageTabTheme.alertCancel,
                    shift: -MessageTabTheme.alertSpread / 2,
                    onTap: onCancel,
                  ),
                ),
                Expanded(
                  child: _AlertButton(
                    keyPrefix: words.key,
                    label: words.action,
                    colour: MessageTabTheme.alertAction,
                    shift: MessageTabTheme.alertSpread / 2,
                    onTap: onConfirm,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertButton extends StatefulWidget {
  const _AlertButton({
    required this.keyPrefix,
    required this.label,
    required this.colour,
    required this.shift,
    required this.onTap,
  });

  final String keyPrefix;
  final String label;
  final Color colour;

  /// How far the word sits from its half's middle, outwards.
  final double shift;
  final VoidCallback onTap;

  @override
  State<_AlertButton> createState() => _AlertButtonState();
}

class _AlertButtonState extends State<_AlertButton> {
  bool _down = false;

  void _press(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    onTap: widget.onTap,
    excludeSemantics: true,
    child: GestureDetector(
      key: ValueKey('${widget.keyPrefix}-${widget.label}'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _press(true),
      onTapUp: (_) => _press(false),
      onTapCancel: () => _press(false),
      child: ColoredBox(
        color: _down ? MessageTabTheme.alertPressed : MessageTabTheme.alertFill,
        child: Center(
          child: Transform.translate(
            offset: Offset(widget.shift, 0),
            child: Text(
              widget.label,
              maxLines: 1,
              style: _style(MessageTabTheme.alertButtonText, widget.colour, line: MessageTabTheme.alertButton),
            ),
          ),
        ),
      ),
    ),
  );
}
