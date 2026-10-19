/// The log kept on the phone (BiliNative `DevLogSetup`'s FileSink, the last 20 MB), for 设置's 清除日志 and
/// 开发者's 导出日志.
abstract interface class LogFiles {
  /// Attaches the file sink to `Logger.shared` where there is a place to keep it.
  factory LogFiles.platform() = NoLogFiles;

  Future<void> clear();

  /// The file to share, or null when nothing is logged.
  Future<String?> export();
}

/// Tests, and platforms without a support folder.
class NoLogFiles implements LogFiles {
  const NoLogFiles();

  @override
  Future<void> clear() async {}

  @override
  Future<String?> export() async => null;
}
