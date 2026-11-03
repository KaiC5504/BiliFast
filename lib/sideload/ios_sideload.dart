import 'package:http/http.dart' as http;

import 'github_release_feed.dart';
import 'ios_reminder_host.dart';
import 'provision_reader.dart';
import 'sideload_model.dart';
import 'sideload_store.dart';

/// The phone's: the signature from the app's own profile, releases from GitHub, the reminder through DeviceHostApi,
/// answers kept in [storePath] (`sideload.json`).
SideloadModel iosSideloadModel({required String? storePath}) => SideloadModel(
  source: ProvisionSignatureSource(),
  feed: GitHubReleaseFeed(http.Client()),
  reminders: IosReminderHost(),
  store: SideloadStore.file(storePath),
);
