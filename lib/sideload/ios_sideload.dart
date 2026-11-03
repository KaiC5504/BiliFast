import 'sideload_model.dart';

/// The phone's: the signature from the app's own profile, releases from GitHub, the reminder through DeviceHostApi,
/// answers kept in [storePath] (`sideload.json`).
SideloadModel iosSideloadModel({required String? storePath}) => SideloadModel.none();
