import 'package:bili_core/api.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:flutter/widgets.dart';

/// The calendar the tests count days in (China's, where Bilibili's day ends).
const testOffset = Duration(hours: 8);

/// Unix seconds of a wall-clock time at [testOffset].
int wall(int day, int hour, int minute, {int month = 10}) =>
    DateTime.utc(2026, month, day, hour, minute).subtract(testOffset).millisecondsSinceEpoch ~/ 1000;

DateTime wallTime(int day, int hour, int minute) => DateTime.fromMillisecondsSinceEpoch(wall(day, hour, minute) * 1000);

HistoryItem historyItem(
  int aid, {
  required int viewAt,
  int progress = 30,
  int duration = 300,
  int device = 2,
  String? title,
}) => HistoryItem(
  aid: aid,
  bvid: 'BV1test$aid',
  cid: 1000 + aid,
  title: title ?? '视频$aid',
  cover: '',
  ownerName: 'UP$aid',
  progress: progress,
  duration: duration,
  viewAt: viewAt,
  device: device,
  part: null,
);

/// [count] rows a minute apart, newest first, starting at [from].
List<HistoryItem> historyRows(int count, {required int from, int firstAid = 1}) => [
  for (var i = 0; i < count; i++) historyItem(firstAid + i, viewAt: from - i * 60),
];

/// Answers the login page's request with [answer], after running [onRequest].
class FakeLoginGate implements LoginGate {
  FakeLoginGate({this.answer = true, this.onRequest});

  bool answer;
  VoidCallback? onRequest;
  int requests = 0;

  @override
  Future<bool> request(BuildContext context) async {
    requests++;
    onRequest?.call();
    return answer;
  }
}
