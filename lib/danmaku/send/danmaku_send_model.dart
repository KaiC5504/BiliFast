import 'package:flutter/widgets.dart';

import '../../video/player_prefs.dart';

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

  /// White, then the colours of the official picker in its order, as its light picker shows them (38): the dark one
  /// dims them (23). The 会员 gradient chip sits between white and red and is not a colour value.
  static const colors = [
    0xFFFFFF, 0xE70012, 0xFEF102, 0x009843, 0x00A0EA, 0xE2027F, //
    0x90C320, 0x002E72, 0xF0AB2A, 0x683A7B, 0x84C0CB, 0x927939,
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
class DanmakuSendModel extends ChangeNotifier {
  DanmakuSendModel(this._post, {this._prefs});

  static const maxLength = 100;

  final DanmakuPost _post;

  /// Read when asked rather than kept: the app swaps in the loaded prefs at launch.
  final PlayerPrefs? _prefs;

  String _text = '';
  DanmakuStyle _style = const DanmakuStyle();
  bool _sending = false;
  bool _disposed = false;

  PlayerPrefs get _shared => _prefs ?? PlayerPrefs.shared;

  String get text => _text;

  /// Cut to [maxLength] characters as the user sees them, so an emoji is never split.
  set text(String value) {
    final characters = value.characters;
    final capped = characters.length > maxLength ? characters.take(maxLength).string : value;
    if (capped == _text) return;
    _text = capped;
    notifyListeners();
  }

  DanmakuStyle get style => _style;

  set style(DanmakuStyle value) {
    if (value == _style) return;
    _style = value;
    notifyListeners();
  }

  bool get sending => _sending;

  bool get canSend => !sending && text.trim().isNotEmpty;

  /// A's red dot shows until A is first pressed, once for the app (BiliNative `danmaku.styleHintSeen`).
  bool get styleHintSeen => _shared.danmakuStyleHintSeen;

  void sawStyleHint() {
    if (styleHintSeen) return;
    _shared.danmakuStyleHintSeen = true;
    notifyListeners();
  }

  /// The message to show, or null once it went out (or there was nothing to send). The text clears only once it went.
  Future<String?> send() async {
    final message = _text.trim();
    if (message.isEmpty || _sending) return null;
    _sending = true;
    notifyListeners();
    try {
      final failure = await _post(message, _style);
      if (failure == null) _text = '';
      return failure;
    } finally {
      _sending = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
