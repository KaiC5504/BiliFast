import 'package:bili_core/devlog.dart';

/// Opens [page] in the official app's own browser, where the account is logged in (Safari isn't), as the official
/// login's confirm is handed over; without the official app, in the browser. False when neither opened.
Future<bool> openInOfficialApp(Uri page, {required Future<bool> Function(Uri link) open, Logger? logger}) async {
  final log = logger ?? Logger.shared;
  final inApp = Uri.parse('bilibili://browser?url=${Uri.encodeComponent(page.toString())}');
  if (await _tryOpen(inApp, open, log)) return true;
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
