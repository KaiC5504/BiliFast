import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';

import 'sideload_model.dart';

/// The signature of the profile a signer put in the app (`embedded.mobileprovision`); TestFlight and the App Store
/// leave none, so their installs read as not sideloaded.
final class ProvisionSignatureSource implements SignatureSource {
  /// [bundle] defaults to the app's own folder, the executable's parent on iOS.
  ProvisionSignatureSource({Directory? bundle, Logger? logger})
    : _bundle = bundle ?? File(Platform.resolvedExecutable).parent,
      _logger = logger ?? Logger.shared;

  final Directory _bundle;
  final Logger _logger;

  @override
  Future<SignatureInfo?> read() async {
    final file = File('${_bundle.path}${Platform.pathSeparator}embedded.mobileprovision');
    try {
      if (!await file.exists()) return null;
      final expires = provisionExpiry(await file.readAsBytes());
      if (expires == null) _logger.warn(LogCategory.app, 'sideload profile has no expiry');
      return expires == null ? null : SignatureInfo(expires: expires);
    } on FileSystemException catch (error) {
      _logger.warn(LogCategory.app, 'sideload profile unreadable', {
        'error': error.osError == null ? error.message : '${error.message}: ${error.osError}',
      });
      return null;
    }
  }
}

/// A profile's `ExpirationDate`, in UTC. The file is a signed CMS envelope around an XML plist; only the plist's
/// bytes are read, without checking the signature. Null when there's no plist or no such date.
DateTime? provisionExpiry(List<int> bytes) {
  // Latin-1 keeps one character per byte, so the markers' places are the bytes' places.
  final text = latin1.decode(bytes);
  final start = text.indexOf('<?xml');
  if (start < 0) return null;
  const close = '</plist>';
  final end = text.indexOf(close, start);
  if (end < 0) return null;
  final plist = utf8.decode(bytes.sublist(start, end + close.length), allowMalformed: true);
  final match = RegExp(r'<key>ExpirationDate</key>\s*<date>([^<]+)</date>').firstMatch(plist);
  final value = match?.group(1)?.trim();
  if (value == null || !value.endsWith('Z')) return null;
  return DateTime.tryParse(value);
}
