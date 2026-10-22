import 'dart:io' show Platform;

import 'package:bili_core/devlog.dart';

import '../account/app_auth_client.dart';

/// Opens [page] in the official app's own browser, where the account is logged in (Safari isn't), as 授权 hands over
/// its confirm page; without the official app, in the browser. False when neither opened.
Future<bool> openInOfficialApp(
  Uri page, {
  required Future<bool> Function(Uri link) open,
  required Future<bool> Function(Uri link) canOpen,
  bool? isIOS,
  Logger? logger,
}) async {
  final log = logger ?? Logger.shared;
  final inApp = officialAppLink(page);
  // As 授权's hand-off: iOS answers canLaunchUrl only for schemes listed in Info.plist, so there it just tries; a PC
  // without the official app may answer launchUrl true behind its own pick-an-app dialog, so there it asks first.
  final worthTrying = (isIOS ?? Platform.isIOS) || await _tryOpen(inApp, canOpen, log);
  if (worthTrying && await _tryOpen(inApp, open, log)) return true;
  log.info(LogCategory.ui, 'official app not opened, trying the browser');
  return _tryOpen(page, open, log);
}

/// launchUrl throws a PlatformException where nothing takes the scheme, rather than answering false.
Future<bool> _tryOpen(Uri link, Future<bool> Function(Uri link) open, Logger log) async {
  try {
    return await open(link);
  } catch (error) {
    log.warn(LogCategory.ui, 'link not opened', {'scheme': link.scheme, 'error': '${error.runtimeType}'});
    return false;
  }
}
