import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../api/models.dart';
import '../playback.dart';
import '../services.dart';
import 'theme.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key, required this.card});

  final FeedCard card;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  final _playback = Playback();
  PlayInfo? _info;
  PlayMode _mode = PlayMode.btr;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      var cid = widget.card.cid;
      if (cid == 0) cid = (await Services.client.view(widget.card.bvid)).cid;
      final info = _info ??= await Services.playInfo(widget.card.bvid, cid);
      if (!mounted) return;
      await _playback.open(info, _mode, maxQuality: Services.maxQuality);
      await _playback.player.play();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() {});
  }

  void _switch(PlayMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    _start();
  }

  @override
  void dispose() {
    _playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            Container(color: Colors.black, height: MediaQuery.paddingOf(context).top),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Video(controller: _playback.controller, controls: NoVideoControls),
                    _PlayerOverlay(playback: _playback),
                    Positioned(
                      left: 4,
                      top: 4,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                children: [
                  Row(children: [
                    const Text('引擎', style: TextStyle(color: Bili.grey, fontSize: 13)),
                    const SizedBox(width: 10),
                    SegmentedButton<PlayMode>(
                      segments: const [
                        ButtonSegment(value: PlayMode.btr, label: Text('BTR 多节点')),
                        ButtonSegment(value: PlayMode.direct, label: Text('直连')),
                      ],
                      selected: {_mode},
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: Bili.pinkTint,
                        selectedForegroundColor: Bili.pink,
                        visualDensity: VisualDensity.compact,
                      ),
                      onSelectionChanged: (s) => _switch(s.first),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Text(widget.card.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4)),
                  const SizedBox(height: 6),
                  Text('${widget.card.ownerName} · ${Bili.count(widget.card.views)}播放 · ${widget.card.bvid}',
                      style: const TextStyle(color: Bili.grey, fontSize: 12)),
                  const SizedBox(height: 14),
                  if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                  ListenableBuilder(listenable: _playback, builder: (_, _) => _Stats(playback: _playback, info: _info)),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () {
                      final d = _playback.player.state.duration;
                      if (d > Duration.zero) _playback.seek(d * 0.5);
                    },
                    child: const Text('跳到中间（测试跳转）'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerOverlay extends StatelessWidget {
  const _PlayerOverlay({required this.playback});

  final Playback playback;

  @override
  Widget build(BuildContext context) {
    final player = playback.player;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: player.playOrPause,
      child: StreamBuilder<Duration>(
        stream: player.stream.position,
        builder: (context, _) {
          final s = player.state;
          final total = s.duration.inMilliseconds;
          final value = total > 0 ? (s.position.inMilliseconds / total).clamp(0.0, 1.0) : 0.0;
          final buffered = total > 0 ? (s.buffer.inMilliseconds / total).clamp(0.0, 1.0) : 0.0;
          return Stack(children: [
            if (s.buffering)
              const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))),
            Positioned(
              left: 10,
              right: 10,
              bottom: 6,
              child: Row(children: [
                Icon(s.playing ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 20),
                const SizedBox(width: 6),
                Text(Bili.duration(s.position.inSeconds), style: const TextStyle(color: Colors.white, fontSize: 11)),
                const SizedBox(width: 8),
                Expanded(
                  child: Stack(alignment: Alignment.centerLeft, children: [
                    Container(height: 2, color: Colors.white24),
                    FractionallySizedBox(widthFactor: buffered, child: Container(height: 2, color: Colors.white54)),
                    FractionallySizedBox(widthFactor: value, child: Container(height: 2, color: Bili.pink)),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(Bili.duration(s.duration.inSeconds), style: const TextStyle(color: Colors.white, fontSize: 11)),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.playback, required this.info});

  final Playback playback;
  final PlayInfo? info;

  @override
  Widget build(BuildContext context) {
    final m = playback.metrics;
    String ms(double? v) => v == null ? '…' : '${(v / 1000).toStringAsFixed(2)} s';
    final rows = <(String, String)>[
      ('画质', m.codec.isEmpty ? '…' : m.codec),
      ('解码', '${m.hwdec.isEmpty || m.hwdec == 'no' ? '软件' : m.hwdec}  ${m.pixelFormat} ${m.gamma}'),
      ('首帧', ms(m.firstFrameMs)),
      ('开始播放', ms(m.playingMs)),
      ('卡顿', '${m.stalls} 次 · ${ms(m.stallMs)}'),
      ('跳转', m.seekMs.isEmpty ? '—' : m.seekMs.map((e) => ms(e)).join(', ')),
      ('缓冲', '${m.bufferAheadS.toStringAsFixed(1)} s'),
      ('下载', '${(m.downloadBps / 1048576).toStringAsFixed(2)} MB/s'),
    ];
    final session = playback.session;
    if (session != null) {
      final s = session.stats;
      rows.add(('引擎', '${s.pieces} 片 · 备份 ${s.hedges} · 失败 ${s.failures} · ${(s.bytes / 1048576).toStringAsFixed(1)} MB'));
      for (final e in s.nodes.entries) {
        final host = e.key.split('.').first.replaceFirst('upos-', '');
        rows.add(('  $host', '${(e.value.bytes / 1048576).toStringAsFixed(1)} MB · 首字节 ${e.value.ttfbMs.round()} ms'));
      }
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Bili.page, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 92, child: Text(k, style: const TextStyle(color: Bili.grey, fontSize: 12))),
                Expanded(child: Text(v, style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]))),
              ]),
            ),
        ],
      ),
    );
  }
}
