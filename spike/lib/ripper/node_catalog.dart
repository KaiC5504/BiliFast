// Port of BTR's cdn-resolver node lists (see LICENSE-BTR.txt), by way of BiliNative's NodeCatalog.swift.

enum NodeMode { mainland, overseas }

class NodeCatalog {
  static const mainland = [
    'upos-sz-mirrorali.bilivideo.com',
    'upos-sz-mirrorhw.bilivideo.com',
    'upos-sz-mirrorbos.bilivideo.com',
    'upos-sz-mirror08c.bilivideo.com',
    'upos-sz-mirrorbd.bilivideo.com',
    'upos-sz-mirror14b.bilivideo.com',
    'upos-sz-estgoss.bilivideo.com',
    'upos-sz-mirrorcos.bilivideo.com',
  ];

  static const overseas = [
    'upos-sz-mirrorcosov.bilivideo.com',
    'upos-sz-mirroraliov.bilivideo.com',
    'cn-hk-eq-01-01.bilivideo.com',
    'cn-hk-eq-01-03.bilivideo.com',
  ];

  static const _mediaHostSuffixes = [
    'bilivideo.com', 'bilivideo.cn', 'bilivideo.net', 'akamaized.net', 'szbdyd.com', //
    'hdslb.com', 'xycdn.com', 'mountaintoys.cn', 'nexusedgeio.com', 'ahdohpiechei.com',
  ];

  static final _plainHost = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$');

  /// Signed download addresses are only ever sent to Bilibili's own media hosts.
  static bool allows(String url) {
    if (url.contains(r'\')) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) return false;
    final host = uri.host.toLowerCase();
    if (!_plainHost.hasMatch(host)) return false;
    final path = uri.path.toLowerCase();
    if (!(path.endsWith('.m4s') || path.endsWith('.mp4') || path.endsWith('.flv'))) return false;
    return _mediaHostSuffixes.any((s) => host == s || host.endsWith('.$s'));
  }

  static String host(String url) => Uri.tryParse(url)?.host.toLowerCase() ?? '';

  static String nodeKey(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    return uri.hasPort ? '${uri.host.toLowerCase()}:${uri.port}' : uri.host.toLowerCase();
  }

  static bool isAkamai(String url) => host(url).endsWith('.akamaized.net');

  static String? swapHost(String url, String node, {bool allowAkamai = false}) {
    if (!allowAkamai && isAkamai(url)) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    // Rebuilt by hand: Uri.replace re-encodes the signed query.
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return 'https://$node${uri.path}$query';
  }

  /// BTR `representationUrls`: the addresses Bilibili gave that suit the mode, then the signed
  /// address swapped onto every node of the mode.
  static List<String> representationUrls(String primary, List<String> backups, NodeMode mode) {
    final originals = _dedup([primary, ...backups].where(allows).toList());
    final nodes = mode == NodeMode.overseas ? overseas : mainland;
    final donor = originals.where((u) => !isAkamai(u)).firstOrNull;
    // Some overseas accounts only get akamaized.net addresses; the nodes accept those signatures too.
    final synthetic = donor != null
        ? [for (final n in nodes) ?swapHost(donor, n)]
        : [for (final n in nodes) for (final o in originals) ?swapHost(o, n, allowAkamai: true)];
    final kept = mode == NodeMode.overseas
        ? originals.where((u) => !mainland.contains(host(u)))
        : originals.where((u) => mainland.contains(host(u)));
    return _dedup([...kept, ...synthetic.where(allows)]);
  }

  static List<String> _dedup(List<String> list) {
    final seen = <String>{};
    return [for (final u in list) if (seen.add(u)) u];
  }
}
