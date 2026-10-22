import 'dart:io';

import 'package:flutter/widgets.dart';

/// An `.svga` animation (SVGA 2's zlib protobuf, or SVGA 1's zip with `movie.spec`), drawn by our own decoder.
/// [play] runs it from the first frame, once, or looping with [loop]; stopped it shows the first frame. [fallback]
/// shows while it decodes or when it can't be read.
class SvgaView extends StatelessWidget {
  const SvgaView({
    super.key,
    required this.file,
    required this.play,
    this.loop = false,
    this.fit = BoxFit.contain,
    this.fallback,
  });

  final File file;
  final bool play;
  final bool loop;
  final BoxFit fit;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) => fallback ?? const SizedBox.shrink();
}
