import 'package:flutter/widgets.dart';

/// Folds iOS's Reduce Motion into [MediaQuery.disableAnimationsOf], which the app's own animations ask: iOS reports it
/// as `accessibilityFeatures.reduceMotion` and leaves `disableAnimations` (Android's Remove animations) off.
class ReduceMotion extends StatefulWidget {
  const ReduceMotion({super.key, required this.child});

  final Widget child;

  @override
  State<ReduceMotion> createState() => _ReduceMotionState();
}

class _ReduceMotionState extends State<ReduceMotion> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// MediaQueryData has no reduceMotion, so a change to it alone rebuilds nothing that reads the MediaQuery.
  @override
  void didChangeAccessibilityFeatures() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    final reduce = View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;
    return MediaQuery(data: data.copyWith(disableAnimations: data.disableAnimations || reduce), child: widget.child);
  }
}
