final class CookieJar {
  CookieJar([Map<String, String> cookies = const {}]) : _cookies = Map.of(cookies);

  Map<String, String> _cookies;

  /// Called with the full jar after every change (the app persists it to the Keychain).
  void Function(Map<String, String> cookies)? onChange;

  Map<String, String> get all => Map.unmodifiable(_cookies);

  String? value(String name) => _cookies[name];

  void set(String name, String value) {
    _cookies[name] = value;
    _changed();
  }

  void remove(String name) {
    _cookies.remove(name);
    _changed();
  }

  void replaceAll(Map<String, String> cookies) {
    _cookies = Map.of(cookies);
    _changed();
  }

  void removeAll() {
    _cookies = {};
    _changed();
  }

  void _changed() => onChange?.call(Map.unmodifiable(_cookies));

  String? get headerValue {
    if (_cookies.isEmpty) return null;
    int rank(String name) => name.toLowerCase() == 'sessdata' ? 0 : 1;
    final names = _cookies.keys.toList()
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : a.compareTo(b);
      });
    return names.map((name) => '$name=${_cookies[name]}').join('; ');
  }

  static Map<String, String> parse(String header) {
    final result = <String, String>{};
    for (final pair in header.split(';')) {
      final equals = pair.indexOf('=');
      if (equals <= 0 || equals == pair.length - 1) continue;
      final name = pair.substring(0, equals).trim();
      if (name.isNotEmpty) result[name] = pair.substring(equals + 1).trim();
    }
    return result;
  }
}
