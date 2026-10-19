import 'package:bili_core/danmaku.dart';
import 'package:flutter/foundation.dart';

import 'danmaku_scene.dart';

/// The 弹幕设置 panel's values, kept for every video (BiliNative `DanmakuSettings.swift`). Whether danmaku show at all
/// is the 弹 switch in `PlayerPrefs`, not part of these.
@immutable
final class DanmakuSettings {
  const DanmakuSettings({
    this.area = 0.5,
    this.opacity = 1,
    this.scale = 1,
    this.speed = 2,
    this.filter = const DanmakuFilterOptions(),
  });

  /// 显示区域's five stops: the share of the video's height the lanes may use.
  static const areas = [0.1, 0.25, 0.5, 0.75, 1.0];

  /// 不透明度's range, read off 40 (70% sits at 62% of the track).
  static const minOpacity = 0.2;
  static const maxOpacity = 1.0;

  /// 字体大小's range, read off 24 and 40 (100% sits a third of the way along).
  static const minScale = 0.5;
  static const maxScale = 2.0;

  /// Seconds a scrolling danmaku takes to cross the screen, 极慢 to 极快.
  static const scrollDurations = [11.0, 9.0, 7.0, 5.5, 4.0];
  static const speedNames = ['极慢', '较慢', '适中', '较快', '极快'];

  final double area;
  final double opacity;
  final double scale;

  /// Index into [scrollDurations].
  final int speed;
  final DanmakuFilterOptions filter;

  double get scrollDuration => scrollDurations[speed.clamp(0, scrollDurations.length - 1)];

  String get speedName => speedNames[speed.clamp(0, speedNames.length - 1)];

  DanmakuOptions display({required bool fullScreen}) => DanmakuOptions(
    area: area,
    opacity: opacity,
    scale: scale,
    scrollDuration: scrollDuration,
    fullScreen: fullScreen,
  );

  DanmakuSettings copyWith({double? area, double? opacity, double? scale, int? speed, DanmakuFilterOptions? filter}) =>
      DanmakuSettings(
        area: area ?? this.area,
        opacity: opacity ?? this.opacity,
        scale: scale ?? this.scale,
        speed: speed ?? this.speed,
        filter: filter ?? this.filter,
      );

  /// Settings saved by an older build lack newer keys; they take the defaults instead of failing.
  factory DanmakuSettings.fromJson(Map<String, Object?> json) {
    const fallback = DanmakuSettings();
    double number(String key, double value, double low, double high) =>
        ((json[key] as num?)?.toDouble() ?? value).clamp(low, high);
    return DanmakuSettings(
      area: number('area', fallback.area, areas.first, areas.last),
      opacity: number('opacity', fallback.opacity, minOpacity, maxOpacity),
      scale: number('scale', fallback.scale, minScale, maxScale),
      speed: ((json['speed'] as num?)?.toInt() ?? fallback.speed).clamp(0, scrollDurations.length - 1),
      filter: switch (json['filter']) {
        final Map<String, Object?> filter => DanmakuFilterOptions.fromJson(filter),
        _ => fallback.filter,
      },
    );
  }

  Map<String, Object?> toJson() => {
    'area': area,
    'opacity': opacity,
    'scale': scale,
    'speed': speed,
    'filter': filter.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is DanmakuSettings &&
      other.area == area &&
      other.opacity == opacity &&
      other.scale == scale &&
      other.speed == speed &&
      other.filter == filter;

  @override
  int get hashCode => Object.hash(area, opacity, scale, speed, filter);

  @override
  String toString() => 'DanmakuSettings(${toJson()})';
}
