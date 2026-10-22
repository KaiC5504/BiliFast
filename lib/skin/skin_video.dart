import 'dart:io';

import 'package:flutter/widgets.dart';

/// The 我的 header's `head_myself_mp4_bg`: a muted video in a native view on the phone (`SkinVideoView.swift`, its
/// sound track left out so it never touches the audio session), [placeholder] elsewhere and until it draws.
class SkinVideo extends StatelessWidget {
  const SkinVideo({super.key, required this.file, required this.loop, required this.placeholder});

  final File file;
  final bool loop;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) => placeholder;
}
