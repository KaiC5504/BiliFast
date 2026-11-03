import 'sideload_links.dart';
import 'sideload_model.dart';
import 'sideload_store.dart';

/// `--fake-sideload` on the PC: an install whose signature lapses tomorrow with a newer release out, so 设置's 签名
/// section and both launch alerts can be pressed on Windows. Nothing reaches GitHub or iOS.
SideloadModel fakeSideloadModel({FakeReminderHost? reminders, DateTime Function()? now}) {
  final clock = now ?? DateTime.now;
  return SideloadModel(
    source: FixedSignature(SignatureInfo(expires: clock().add(const Duration(days: 1, hours: 5)))),
    feed: FixedReleaseFeed(ReleaseInfo(version: '1.3.0', build: 99, page: Uri.parse(releasesPage))),
    reminders: reminders ?? FakeReminderHost(),
    store: SideloadStore.memory(),
    // Its own build rather than this one's, so the release is newer whatever is built.
    version: '1.3.0',
    build: '7',
    now: clock,
  );
}

final class FixedSignature implements SignatureSource {
  const FixedSignature(this.info);

  final SignatureInfo? info;

  @override
  Future<SignatureInfo?> read() async => info;
}

final class FixedReleaseFeed implements ReleaseFeed {
  FixedReleaseFeed(this.release);

  final ReleaseInfo? release;
  var asked = 0;

  @override
  Future<ReleaseInfo?> latest() async {
    asked++;
    return release;
  }
}

/// Grants permission (unless [grants] is false) and records what it was asked.
final class FakeReminderHost implements ReminderHost {
  FakeReminderHost({this.grants = true});

  bool grants;
  var permissionAsks = 0;
  final schedules = <({DateTime at, String title, String body})>[];
  var cancels = 0;

  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    return grants;
  }

  @override
  Future<void> schedule(DateTime at, String title, String body) async {
    schedules.add((at: at, title: title, body: body));
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }
}
