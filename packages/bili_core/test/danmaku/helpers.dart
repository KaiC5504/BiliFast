import 'package:bili_core/danmaku.dart';

DanmakuElem makeElem(
  String content, {
  int at = 0,
  int mode = 1,
  int color = 0xFFFFFF,
  String midHash = '',
  int colorful = 0,
}) => DanmakuElem(progressMs: at, mode: mode, color: color, midHash: midHash, content: content, colorful: colorful);
