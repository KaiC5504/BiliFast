import 'package:flutter/material.dart';

class Bili {
  static const pink = Color(0xFFFB7299);
  static const pinkTint = Color(0xFFFFECF1);
  static const page = Color(0xFFF4F5F7);
  static const card = Colors.white;
  static const text = Color(0xFF18191C);
  static const grey = Color(0xFF9499A0);
  static const greyLight = Color(0xFFE3E5E7);
  static const field = Color(0xFFF1F2F3);

  static String count(int n) {
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000000) return '${(n / 10000).round()}万';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return '$n';
  }

  static String duration(int seconds) {
    final h = seconds ~/ 3600, m = seconds % 3600 ~/ 60, s = seconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}
