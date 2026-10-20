import 'package:flutter/foundation.dart';

/// 开发者 → 旋转动画: how a turn to or from landscape full screen is animated. [quietRequest] asks for the rotation
/// with UIView animations already off, the only way 1.0.0 (13)'s phone test found to keep iOS's own rotation out
/// (09 in local/differences), so the video page draws the official turn; [system] leaves it to iOS.
enum TurnMethod {
  system('系统'),
  quietRequest('请求前关');

  const TurnMethod(this.label);

  final String label;

  /// Whether the host takes the turns over.
  bool get drawn => this != system;
}

/// What covers the screen while the window turns, until the page has drawn the turn's first frame.
enum TurnPicture {
  cut('直接切'),
  fade('淡出'),
  none('无截图');

  const TurnPicture(this.label);

  final String label;
}

/// When the page's turn starts moving: on its first frame at the turned size, or once the still picture is gone.
enum TurnSpinStart {
  immediate('立即'),
  afterPicture('等截图');

  const TurnSpinStart(this.label);

  final String label;
}

@immutable
class TurnStyle {
  const TurnStyle({
    this.method = TurnMethod.quietRequest,
    this.picture = TurnPicture.cut,
    this.spinStart = TurnSpinStart.immediate,
  });

  static const system = TurnStyle(method: TurnMethod.system);

  final TurnMethod method;
  final TurnPicture picture;
  final TurnSpinStart spinStart;

  /// Whether [picture] and [spinStart] take part: 系统 has no picture or drawn start to choose.
  bool get choosesPicture => method != TurnMethod.system;

  TurnStyle copyWith({TurnMethod? method, TurnPicture? picture, TurnSpinStart? spinStart}) => TurnStyle(
        method: method ?? this.method,
        picture: picture ?? this.picture,
        spinStart: spinStart ?? this.spinStart,
      );

  String get label => choosesPicture ? '${method.label}·${picture.label}·${spinStart.label}' : method.label;

  /// 轮换测试's order: the reference, then every picture and start of the drawn turn.
  static const cycle = <TurnStyle>[
    system,
    TurnStyle(),
    TurnStyle(spinStart: TurnSpinStart.afterPicture),
    TurnStyle(picture: TurnPicture.fade),
    TurnStyle(picture: TurnPicture.fade, spinStart: TurnSpinStart.afterPicture),
    TurnStyle(picture: TurnPicture.none),
    TurnStyle(picture: TurnPicture.none, spinStart: TurnSpinStart.afterPicture),
  ];

  @override
  bool operator ==(Object other) =>
      other is TurnStyle && other.method == method && other.picture == picture && other.spinStart == spinStart;

  @override
  int get hashCode => Object.hash(method, picture, spinStart);

  @override
  String toString() => label;
}
