import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'api/models.dart';
import 'playback.dart';
import 'services.dart';

/// `--bench BV1,BV2 [--bench-play 25] [--bench-after-seek 15] [--bench-out local/bench]`
class BenchPlan {
  BenchPlan(this.videos, this.playSeconds, this.afterSeekSeconds, this.outDir);

  final List<String> videos;
  final int playSeconds;
  final int afterSeekSeconds;
  final String outDir;

  static BenchPlan? fromArgs(List<String> args) {
    String? arg(String name) {
      final i = args.indexOf(name);
      return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
    }

    final list = arg('--bench');
    if (list == null) return null;
    return BenchPlan(
      list.split(',').where((s) => s.isNotEmpty).toList(),
      int.tryParse(arg('--bench-play') ?? '') ?? 25,
      int.tryParse(arg('--bench-after-seek') ?? '') ?? 15,
      arg('--bench-out') ?? 'local/bench',
    );
  }
}

class BenchPage extends StatefulWidget {
  const BenchPage({super.key, required this.plan});

  final BenchPlan plan;

  @override
  State<BenchPage> createState() => _BenchPageState();
}

class _BenchPageState extends State<BenchPage> {
  Playback? _playback;
  final _log = <String>[];
  late final IOSink _out;

  @override
  void initState() {
    super.initState();
    Directory(widget.plan.outDir).createSync(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    _out = File('${widget.plan.outDir}/bench-$stamp.jsonl').openWrite();
    _run();
  }

  void _say(String line) {
    stdout.writeln(line);
    if (mounted) setState(() => _log.add(line));
  }

  Future<void> _waitFor(bool Function() done, Duration timeout) async {
    final until = DateTime.now().add(timeout);
    while (!done() && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// `feed:N` takes the first N videos of the 推荐 feed that run longer than two minutes.
  Future<List<String>> _videos() async {
    final list = widget.plan.videos;
    if (list.length != 1 || !list.first.startsWith('feed:')) return list;
    final n = int.parse(list.first.substring(5));
    final out = <String>[];
    for (var page = 0; out.length < n && page < 5; page++) {
      for (final c in await Services.client.recommendFeed(page)) {
        if (c.duration > 120 && out.length < n && !out.contains(c.bvid)) out.add(c.bvid);
      }
    }
    return out;
  }

  Future<void> _run() async {
    final videos = await _videos();
    _say('videos: ${videos.join(',')}');
    for (var v = 0; v < videos.length; v++) {
      final bvid = videos[v];
      PlayInfo info;
      try {
        final view = await Services.client.view(bvid);
        info = await Services.playInfo(bvid, view.cid);
      } catch (e) {
        _say('$bvid: playurl failed: $e');
        continue;
      }
      // The order alternates per video: the second run finds the CDN nodes warmer.
      final modes = v.isEven ? [PlayMode.btr, PlayMode.direct] : [PlayMode.direct, PlayMode.btr];
      for (final mode in modes) {
        await _one(bvid, info, mode, order: modes.indexOf(mode));
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
    await _out.close();
    _say('done');
    await Future<void>.delayed(const Duration(seconds: 1));
    exit(0);
  }

  Future<void> _one(String bvid, PlayInfo info, PlayMode mode, {required int order}) async {
    final p = Playback();
    setState(() => _playback = p);
    final m0 = DateTime.now();
    String? error;
    final buffer = <double>[];
    final speed = <double>[];
    try {
      await p.open(info, mode, maxQuality: Services.maxQuality);
      await p.player.play();
      await _waitFor(() => p.metrics.playingMs != null, const Duration(seconds: 30));
      for (var s = 0; s < widget.plan.playSeconds; s++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (s % 5 == 4) {
          buffer.add(p.metrics.bufferAheadS);
          speed.add(p.metrics.downloadBps / 1048576);
        }
      }
      final d = p.player.state.duration;
      if (d > const Duration(seconds: 60)) {
        await p.seek(d * 0.5);
        await _waitFor(() => p.metrics.seekMs.isNotEmpty, const Duration(seconds: 30));
        for (var s = 0; s < widget.plan.afterSeekSeconds; s++) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
    } catch (e) {
      error = '$e';
    }
    final stats = p.session?.stats;
    final record = {
      'bvid': bvid,
      'mode': mode.name,
      'order': order,
      'quality': p.video?.id,
      ...p.metrics.toJson(),
      'bufferAheadEvery5s': buffer.map((e) => double.parse(e.toStringAsFixed(1))).toList(),
      'downloadMBpsEvery5s': speed.map((e) => double.parse(e.toStringAsFixed(2))).toList(),
      if (stats != null)
        'engine': {
          'MB': (stats.bytes / 1048576).toStringAsFixed(1),
          'pieces': stats.pieces,
          'hedges': stats.hedges,
          'failures': stats.failures,
          'wastedMB': (stats.wastedBytes / 1048576).toStringAsFixed(1),
          'nodes': {
            for (final e in stats.nodes.entries)
              e.key: {'MB': (e.value.bytes / 1048576).toStringAsFixed(1), 'ttfbMs': e.value.ttfbMs.round(), 'failed': e.value.failures},
          },
          'errors': stats.errors,
        },
      'wallS': DateTime.now().difference(m0).inSeconds,
      'error': ?error,
    };
    _out.writeln(jsonEncode(record));
    await _out.flush();
    final m = p.metrics;
    _say('$bvid ${mode.name.padRight(6)} q${p.video?.id} first frame ${m.firstFrameMs?.round()} ms, playing ${m.playingMs?.round()} ms, '
        'stalls ${m.stalls} (${m.stallMs.round()} ms), seek ${m.seekMs.map((e) => e.round()).toList()} ms, hwdec ${m.hwdec}'
        '${error == null ? '' : ', error $error'}');
    setState(() => _playback = null);
    await p.stop();
    p.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _playback;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(children: [
        AspectRatio(aspectRatio: 16 / 9, child: p == null ? const SizedBox() : Video(controller: p.controller, controls: NoVideoControls)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [for (final l in _log) Text(l, style: const TextStyle(color: Colors.white70, fontSize: 11))],
          ),
        ),
      ]),
    );
  }
}
