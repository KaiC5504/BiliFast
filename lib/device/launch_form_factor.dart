import 'package:flutter/foundation.dart';

import '../app/form_factor.dart';
import 'ios/device_api.g.dart';

/// The device's [FormFactor] at launch and where it came from, for the log's `form factor` line.
final class LaunchFormFactor {
  const LaunchFormFactor(this.kind, this.via, {this.error});

  final FormFactor kind;

  /// `native` (UIKit's idiom), `flag` (Windows' `--pad`) or `default`.
  final String via;

  /// The host call's failure, when iOS couldn't answer.
  final Object? error;

  Map<String, Object> get logFields => {
        'kind': kind.name,
        'via': via,
        if (error != null) 'error': '${error.runtimeType}',
      };
}

/// On iOS UIKit's idiom decides, the same answer DeviceChannel.swift's masks go by; a size can't, since the view may
/// not be laid out yet when Dart starts. Windows takes `--pad`; everything else is the phone.
Future<LaunchFormFactor> launchFormFactor(List<String> args, {TargetPlatform? platform, DeviceHostApi? host}) async {
  switch (platform ?? defaultTargetPlatform) {
    case TargetPlatform.iOS:
      try {
        final pad = await (host ?? DeviceHostApi()).isPad();
        return LaunchFormFactor(pad ? FormFactor.pad : FormFactor.phone, 'native');
      } on Object catch (error) {
        return LaunchFormFactor(FormFactor.phone, 'default', error: error);
      }
    case TargetPlatform.windows when args.contains('--pad'):
      return const LaunchFormFactor(FormFactor.pad, 'flag');
    default:
      return const LaunchFormFactor(FormFactor.phone, 'default');
  }
}
