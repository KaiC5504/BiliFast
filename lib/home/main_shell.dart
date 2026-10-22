import 'package:flutter/widgets.dart';

import 'home_page.dart';

/// The bottom bar's places: 首页 and 我的 kept alive side by side, the bar under both (01, 02).
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.developerPage, this.initialLink});

  final WidgetBuilder? developerPage;

  /// Passed to 首页 (`--play=` on the PC).
  final String? initialLink;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  @override
  Widget build(BuildContext context) =>
      HomePage(developerPage: widget.developerPage, initialLink: widget.initialLink);
}
