import 'package:flutter/foundation.dart';

/// 弹幕字号.
enum DanmakuSize {
  normal(25),
  small(18);

  const DanmakuSize(this.fontSize);

  final int fontSize;
}

/// 弹幕类型: 滚动, 置顶, 置底. 竖屏's style panel offers no 置底 (38).
enum DanmakuPosition {
  scroll(1),
  top(5),
  bottom(4);

  const DanmakuPosition(this.mode);

  final int mode;
}

/// The look of the next danmaku the user sends; kept for the life of the page (BiliNative `DanmakuStyle`).
@immutable
final class DanmakuStyle {
  const DanmakuStyle({
    this.size = DanmakuSize.normal,
    this.position = DanmakuPosition.scroll,
    this.color = 0xFFFFFF,
    this.gradient = false,
  });

  /// White, then the colours of the official picker in its order (23). The 会员 gradient chip sits between white and
  /// red and is not a colour value.
  static const colors = [
    0xFFFFFF, 0xD42D25, 0xFCF150, 0x42954C, 0x469DE4, 0xCF2C7D, //
    0x9AC143, 0x0F2D6E, 0xE6AE48, 0x613C77, 0x91BEC9, 0x8E7A43,
  ];

  final DanmakuSize size;
  final DanmakuPosition position;

  /// 0xRRGGBB.
  final int color;

  /// The 大会员 gradient. The server wants it together with white.
  final bool gradient;

  DanmakuStyle copyWith({DanmakuSize? size, DanmakuPosition? position, int? color, bool? gradient}) => DanmakuStyle(
    size: size ?? this.size,
    position: position ?? this.position,
    color: color ?? this.color,
    gradient: gradient ?? this.gradient,
  );

  @override
  bool operator ==(Object other) =>
      other is DanmakuStyle &&
      other.size == size &&
      other.position == position &&
      other.color == color &&
      other.gradient == gradient;

  @override
  int get hashCode => Object.hash(size, position, color, gradient);
}

/// Posts [text] in [style]: the message to show, or null once it went out.
typedef DanmakuPost = Future<String?> Function(String text, DanmakuStyle style);

/// The draft in the send bar: its text (100 characters at most), its style and whether it is going out.
// Contracts stub: slice 5's send agent writes it.
class DanmakuSendModel extends ChangeNotifier {
  DanmakuSendModel(this._post);

  static const maxLength = 100;

  final DanmakuPost _post;

  String text = '';
  DanmakuStyle style = const DanmakuStyle();

  bool get sending => false;

  bool get canSend => !sending && text.trim().isNotEmpty;

  /// The message to show, or null once it went out (or there was nothing to send).
  Future<String?> send() => _post(text, style);
}
