import 'package:bilifast/account/web_cookies.dart';

/// The web view's store in memory: hands out [jar] (or throws [readError]) and counts every call.
class FakeWebCookies implements WebCookies {
  final jar = <String, String>{};
  Object? readError;
  Object? clearBilibiliError;
  Object? clearAllError;
  int reads = 0;
  int bilibiliClears = 0;
  int allClears = 0;

  @override
  Future<Map<String, String>> bilibili() async {
    reads += 1;
    final error = readError;
    if (error != null) throw error;
    return Map.of(jar);
  }

  @override
  Future<void> clearBilibili() async {
    bilibiliClears += 1;
    final error = clearBilibiliError;
    if (error != null) throw error;
    jar.clear();
  }

  @override
  Future<void> clearAll() async {
    allClears += 1;
    final error = clearAllError;
    if (error != null) throw error;
    jar.clear();
  }
}
