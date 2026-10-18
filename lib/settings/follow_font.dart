import 'package:flutter/widgets.dart';

import 'font_store.dart';

/// Draws the app in the font [fonts] holds. Styles name the font where they're built, many in widgets nothing else
/// rebuilds, so a new font builds every widget again, as a hot reload does, keeping the pages and their state.
class FollowFont extends StatefulWidget {
  const FollowFont({super.key, required this.fonts, required this.builder});

  final FontStore fonts;
  final WidgetBuilder builder;

  @override
  State<FollowFont> createState() => _FollowFontState();
}

class _FollowFontState extends State<FollowFont> {
  @override
  void initState() {
    super.initState();
    widget.fonts.addListener(_changed);
  }

  @override
  void didUpdateWidget(FollowFont oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.fonts, widget.fonts)) return;
    oldWidget.fonts.removeListener(_changed);
    widget.fonts.addListener(_changed);
  }

  @override
  void dispose() {
    widget.fonts.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    setState(() {});
    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
