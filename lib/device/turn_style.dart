import 'package:flutter/foundation.dart';

/// 开发者 → 旋转动画: how a turn to or from landscape full screen is animated. Everything but [system] and [noSpin] is
/// drawn by the video page, each with its own way of keeping iOS's rotation out of it (NativeTurnMethod in
/// pigeons/device_api.dart). The test build carries them all; the phone's log decides which stays.
enum TurnMethod {
  system('系统'),
  legacy('原样'),
  remove('移除'),
  counter('抵消'),
  noActions('关动作'),
  quietRequest('请求前关'),

  /// iOS turns the screen; the page only grows the player, at the turned size from the start.
  noSpin('不转');

  const TurnMethod(this.label);

  final String label;

  /// Whether the host takes the turns over: 不转 too, for the turned size at once.
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
    this.method = TurnMethod.remove,
    this.picture = TurnPicture.cut,
    this.spinStart = TurnSpinStart.immediate,
  });

  static const system = TurnStyle(method: TurnMethod.system);

  final TurnMethod method;
  final TurnPicture picture;
  final TurnSpinStart spinStart;

  /// Whether [picture] and [spinStart] take part: 系统 and 不转 have no picture or drawn start to choose.
  bool get choosesPicture => method != TurnMethod.system && method != TurnMethod.noSpin;

  TurnStyle copyWith({TurnMethod? method, TurnPicture? picture, TurnSpinStart? spinStart}) => TurnStyle(
        method: method ?? this.method,
        picture: picture ?? this.picture,
        spinStart: spinStart ?? this.spinStart,
      );

  /// 系统 and 不转 have no picture or drawn start to choose.
  String get label => switch (method) {
        TurnMethod.system || TurnMethod.noSpin => method.label,
        _ => '${method.label}·${picture.label}·${spinStart.label}',
      };

  /// 轮换测试's order: the reference, every method as it would ship (原样 faded, as 1.0.0 (12) always did), then the
  /// pictures and the late start on the two methods most likely to win.
  static const cycle = <TurnStyle>[
    system,
    TurnStyle(method: TurnMethod.legacy, picture: TurnPicture.fade),
    TurnStyle(method: TurnMethod.remove),
    TurnStyle(method: TurnMethod.counter),
    TurnStyle(method: TurnMethod.noActions),
    TurnStyle(method: TurnMethod.quietRequest),
    TurnStyle(method: TurnMethod.noSpin, picture: TurnPicture.none),
    TurnStyle(method: TurnMethod.remove, picture: TurnPicture.fade),
    TurnStyle(method: TurnMethod.remove, picture: TurnPicture.none),
    TurnStyle(method: TurnMethod.remove, spinStart: TurnSpinStart.afterPicture),
    TurnStyle(method: TurnMethod.counter, picture: TurnPicture.fade),
    TurnStyle(method: TurnMethod.counter, picture: TurnPicture.none),
    TurnStyle(method: TurnMethod.counter, spinStart: TurnSpinStart.afterPicture),
  ];

  @override
  bool operator ==(Object other) =>
      other is TurnStyle && other.method == method && other.picture == picture && other.spinStart == spinStart;

  @override
  int get hashCode => Object.hash(method, picture, spinStart);

  @override
  String toString() => label;
}
