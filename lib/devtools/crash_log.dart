import 'dart:convert';

import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

/// Dart errors as DevLog `app` events with message `crash`, split like CrashReport.swift so a long stack stays a
/// few readable lines, every part sharing one `report` id. Native crashes (MetricKit) come later.
abstract final class CrashLog {
  /// Bytes of stack text per event.
  static const chunkBytes = 12000;

  /// Chains to the handlers already set, so the console still shows every error.
  static void install({Logger? logger}) {
    final log = logger ?? Logger.shared;
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      report(details.exception, details.stack, source: 'flutter', logger: log, fields: {
        if (details.library != null) 'library': details.library!,
        if (details.context != null) 'context': '${details.context}',
      });
      (previousFlutter ?? FlutterError.presentError)(details);
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, source: 'platform', logger: log);
      return previousPlatform?.call(error, stack) ?? false;
    };
  }

  /// Never throws: a failing crash handler would report itself.
  static void report(Object error, StackTrace? stack,
      {required String source, Map<String, Object> fields = const {}, Logger? logger}) {
    try {
      final log = logger ?? Logger.shared;
      for (final event in events(source: source, error: '$error', stack: '${stack ?? ''}', fields: fields)) {
        log.error(LogCategory.app, 'crash', event);
      }
    } catch (_) {}
  }

  /// The first part carries the error and its fields; every part carries `report`, `part`, `parts` and a slice of
  /// `stack`.
  static List<Map<String, Object>> events({
    required String source,
    required String error,
    required String stack,
    Map<String, Object> fields = const {},
    int maxBytes = chunkBytes,
  }) {
    final meta = <String, Object>{...fields, 'source': source, 'error': error};
    final id = reportId(meta, stack);
    final chunks = split(stack, maxBytes: maxBytes < 256 ? 256 : maxBytes);
    return [
      for (var index = 0; index < chunks.length; index++)
        {
          if (index == 0) ...meta,
          'report': id,
          'part': index + 1,
          'parts': chunks.length,
          'stack': chunks[index],
        },
    ];
  }

  /// Cuts at line ends; a single line longer than [maxBytes] is cut inside.
  static List<String> split(String text, {required int maxBytes}) {
    final chunks = <String>[];
    var current = StringBuffer();
    var currentBytes = 0;
    for (var piece in text.split('\n')) {
      while (utf8.encode(piece).length > maxBytes) {
        if (current.isNotEmpty) {
          chunks.add('$current');
          current = StringBuffer();
          currentBytes = 0;
        }
        final head = StringBuffer();
        var headBytes = 0;
        for (final rune in piece.runes) {
          final character = String.fromCharCode(rune);
          final size = utf8.encode(character).length;
          if (headBytes + size > maxBytes) break;
          head.write(character);
          headBytes += size;
        }
        final cut = '$head';
        chunks.add(cut);
        piece = piece.substring(cut.length);
      }
      final pieceBytes = utf8.encode(piece).length;
      final size = pieceBytes + (current.isEmpty ? 0 : 1);
      if (currentBytes + size > maxBytes && current.isNotEmpty) {
        chunks.add('$current');
        current = StringBuffer(piece);
        currentBytes = pieceBytes;
      } else {
        if (current.isNotEmpty) current.write('\n');
        current.write(piece);
        currentBytes += size;
      }
    }
    if (current.isNotEmpty || chunks.isEmpty) chunks.add('$current');
    return chunks;
  }

  /// FNV-1a 64 over the fields and the stack, as CrashReport.swift's `reportID`.
  static String reportId(Map<String, Object> meta, String stack) {
    final text = StringBuffer('crash');
    for (final key in meta.keys.toList()..sort()) {
      text.write('|$key=${meta[key]}');
    }
    text.write('|$stack');
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode('$text')) {
      hash ^= byte;
      hash *= 0x00000100000001b3;
    }
    final high = (hash >>> 32).toRadixString(16).padLeft(8, '0');
    final low = (hash & 0xffffffff).toRadixString(16).padLeft(8, '0');
    return high + low;
  }
}
