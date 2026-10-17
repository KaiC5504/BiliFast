abstract final class BiliHosts {
  /// bilibili.com or any subdomain; a plain suffix test would also accept "evilbilibili.com".
  /// Cookie domains arrive with a leading dot, hence the trim.
  static bool isBilibili(String host) {
    var name = host.toLowerCase();
    if (name.startsWith('.')) name = name.substring(1);
    return name == 'bilibili.com' || name.endsWith('.bilibili.com');
  }
}
