import 'package:flutter/widgets.dart';

import 'theme.dart';

OverlayEntry? _shown;

/// A dark rounded note low in the middle of the screen for two seconds, as the official app's; a new one replaces it.
void showToast(BuildContext context, String message) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  if (_shown case final previous?) _dismiss(previous);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _Toast(
      message: message,
      onDone: () {
        if (identical(_shown, entry)) _dismiss(entry);
      },
    ),
  );
  _shown = entry;
  overlay.insert(entry);
}

void _dismiss(OverlayEntry entry) {
  _shown = null;
  entry
    ..remove()
    ..dispose();
}

class _Toast extends StatefulWidget {
  const _Toast({required this.message, required this.onDone});

  final String message;
  final VoidCallback onDone;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await _fade.forward();
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    await _fade.reverse();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    // Over the keyboard when one is up, or a failed post's reason would land behind the composer's.
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Align(
        alignment: const Alignment(0, 0.6),
        child: FadeTransition(
          opacity: _fade,
          child: Container(
            key: const ValueKey('toast'),
            margin: const EdgeInsets.symmetric(horizontal: BiliMetrics.sectionGap * 2),
            padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.sectionGap, vertical: BiliMetrics.gutter),
            decoration: BoxDecoration(
              color: BiliColors.toastFill,
              borderRadius: BorderRadius.circular(BiliMetrics.toastRadius),
            ),
            child: Text(
              widget.message,
              textAlign: TextAlign.center,
              // The root overlay sits outside any Material; what it would inherit is WidgetsApp's monospace w900 error
              // style, so nothing is inherited.
              style: TextStyle(
                inherit: false,
                fontFamily: BiliFonts.family,
                fontFamilyFallback: BiliFonts.fallback,
                fontSize: BiliMetrics.bodyText,
                color: BiliColors.panelText,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
