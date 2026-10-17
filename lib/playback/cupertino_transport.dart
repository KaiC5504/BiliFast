import 'package:bili_core/engine.dart';

/// The iOS transport: URLSession through cupertino_http (HTTP/2 to the mirrors, 8 per host for Akamai).
/// A top-level function, because it runs inside the engine isolate.
RangeTransport createCupertinoTransport() => throw UnimplementedError('engine agent');
