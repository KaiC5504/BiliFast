import 'package:flutter/widgets.dart';

import 'notify_host.dart';

/// Opens what a tapped notification names, and logs the background checks NotifyHost.swift ran since the last launch.
class NotifyTaps {
  NotifyTaps({required this.host, required this.navigator});

  final NotifyHost host;
  final GlobalKey<NavigatorState> navigator;

  /// Once the first page shows.
  void start() {}
}
