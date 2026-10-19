import 'package:flutter/foundation.dart';

import '../video/page_api.dart';

/// 历史记录 (BiliNative `HistoryModel.swift`): pages through the cursor, groups by day, and knows where each video
/// resumes.
class HistoryModel extends ChangeNotifier {
  HistoryModel({required this.api, required this.isLoggedIn, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final PageApi api;
  final bool Function() isLoggedIn;
  // ignore: unused_field
  final DateTime Function() _now;
}
