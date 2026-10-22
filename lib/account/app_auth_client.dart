import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens Bilibili's confirm page in the official app's own browser, the only place its 确认 works (a web view gets
/// 请在哔哩哔哩客户端内打开). Completes once BiliFast is back in front: true, or false when there was no app to open.
/// [isIOS], [canOpen] and [open] are for tests.
Future<bool> confirmInBilibili(
  Uri page, {
  bool? isIOS,
  Future<bool> Function(Uri link) canOpen = canLaunchUrl,
  Future<bool> Function(Uri link) open = _openOutside,
}) async {
  final link = officialAppLink(page);
  // iOS answers canLaunchUrl only for schemes listed in Info.plist; launchUrl itself says whether the app opened.
  if (!(isIOS ?? Platform.isIOS) && !await canOpen(link)) return false;
  final back = _BackInFront();
  try {
    if (!await open(link)) return false;
    // The code lasts 180 s; past that the poll answers expired anyway.
    await back.future.timeout(const Duration(minutes: 3), onTimeout: () {});
    return true;
  } catch (_) {
    return false;
  } finally {
    back.dispose();
  }
}

/// [page] in the official app's own browser.
Uri officialAppLink(Uri page) => Uri.parse('bilibili://browser?url=${Uri.encodeComponent(page.toString())}');

Future<bool> _openOutside(Uri link) => launchUrl(link, mode: LaunchMode.externalApplication);

/// Completes on the first return to the front after the app has left it.
class _BackInFront {
  _BackInFront() {
    _listener = AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed) {
          _left = true;
        } else if (_left && !_done.isCompleted) {
          _done.complete();
        }
      },
    );
  }

  final _done = Completer<void>();
  late final AppLifecycleListener _listener;
  bool _left = false;

  Future<void> get future => _done.future;

  void dispose() => _listener.dispose();
}
