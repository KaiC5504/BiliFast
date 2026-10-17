// Port of BTR's cdn-resolver node lists (see LICENSE-BTR.txt), by way of BiliNative's NodeCatalog.swift.

final class NodeAddress {
  NodeAddress(String host, {this.port}) : host = host.toLowerCase();

  final String host;
  final int? port;

  @override
  bool operator ==(Object other) => other is NodeAddress && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => port == null ? host : '$host:$port';
}

sealed class NodeMode {
  const NodeMode();

  static const mainland = MainlandNodes();
  static const overseas = OverseasNodes();
}

final class MainlandNodes extends NodeMode {
  const MainlandNodes();
}

final class OverseasNodes extends NodeMode {
  const OverseasNodes();
}

/// Explicit nodes, as BTR's custom mode; the tests use it for loopback nodes.
final class CustomNodes extends NodeMode {
  const CustomNodes(this.nodes);

  final List<NodeAddress> nodes;
}

final class MediaURLPolicy {
  const MediaURLPolicy(this.allowsURL);

  final bool Function(String url) allowsURL;

  /// Signed download addresses are only ever sent to Bilibili's own media hosts.
  static const bilibili = MediaURLPolicy(_allowsBilibili);

  static const any = MediaURLPolicy(_allowsAny);
}

bool _allowsAny(String url) => true;

// Checked on the raw text as well as the parsed URI: Dart's Uri decodes escapes in the host and path that
// URLComponents' percent-encoded accessors keep, so the two could disagree about the host.
bool _allowsBilibili(String text) {
  if (text.contains(r'\')) return false;
  final uri = Uri.tryParse(text);
  final raw = NodeCatalog._parts.firstMatch(text);
  if (uri == null || raw == null || uri.scheme.toLowerCase() != 'https') return false;
  final authority = raw[2]!;
  if (authority.contains('@') || uri.userInfo.isNotEmpty) return false;
  final colon = authority.lastIndexOf(':');
  final host = (colon < 0 ? authority : authority.substring(0, colon)).toLowerCase();
  if (host != uri.host.toLowerCase() || !NodeCatalog.isPlainHostName(host)) return false;
  final rest = raw[3]!;
  final pathEnd = rest.indexOf(RegExp('[?#]'));
  final path = (pathEnd < 0 ? rest : rest.substring(0, pathEnd)).toLowerCase();
  if (!(path.endsWith('.m4s') || path.endsWith('.mp4') || path.endsWith('.flv'))) return false;
  return NodeCatalog.mediaHostSuffixes.any((suffix) => host == suffix || host.endsWith('.$suffix'));
}

abstract final class NodeCatalog {
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

  static const mediaHostSuffixes = [
    'bilivideo.com', 'bilivideo.cn', 'bilivideo.net', 'akamaized.net', 'szbdyd.com', //
    'hdslb.com', 'xycdn.com', 'mountaintoys.cn', 'nexusedgeio.com', 'ahdohpiechei.com',
  ];

  static final _plainHost = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$');
  static final _parts = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*://)([^/?#]*)(.*)$', dotAll: true);

  /// BTR `normalizeCdnHost`'s shape check: letters, digits and hyphens in dot-separated labels,
  /// so no percent escapes, userinfo, port or trailing dot.
  static bool isPlainHostName(String host) => _plainHost.hasMatch(host);

  static String host(String url) => Uri.tryParse(url)?.host.toLowerCase() ?? '';

  static String nodeKey(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return '';
    final host = uri.host.toLowerCase();
    return uri.hasPort ? '$host:${uri.port}' : host;
  }

  /// The signed address without its node: the same address can be asked of any node.
  static String address(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    return uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
  }

  static bool isAkamai(String url) => host(url).endsWith('.akamaized.net');

  /// Rebuilt on the original text, so the signed query goes out byte for byte as Bilibili wrote it.
  static String? swapHost(String url, NodeAddress node, {bool allowAkamai = false}) {
    if (!allowAkamai && isAkamai(url)) return null;
    final match = _parts.firstMatch(url);
    if (Uri.tryParse(url) == null || match == null) return null;
    final authority = match[2]!;
    final at = authority.lastIndexOf('@');
    final userInfo = at < 0 ? '' : authority.substring(0, at + 1);
    // The port is replaced too, or a peer CDN's non-standard port such as :4483 would stay.
    final port = node.port == null ? '' : ':${node.port}';
    return '${match[1]}$userInfo${node.host}$port${match[3]}';
  }

  static List<NodeAddress> nodes(NodeMode mode) => switch (mode) {
        MainlandNodes() => [for (final host in mainland) NodeAddress(host)],
        OverseasNodes() => [for (final host in overseas) NodeAddress(host)],
        CustomNodes(:final nodes) => nodes,
      };

  /// BTR `representationUrls`: the addresses Bilibili gave that suit the mode, then the signed
  /// address swapped onto every node of the mode.
  static List<String> representationURLs({
    required String primary,
    required List<String> backups,
    required NodeMode mode,
    required MediaURLPolicy policy,
  }) {
    final originals = deduplicated([primary, ...backups].where(policy.allowsURL).toList());
    // BTR: a custom mode without servers works like the mainland mode.
    final effective = mode is CustomNodes && mode.nodes.isEmpty ? NodeMode.mainland : mode;
    final nodes = NodeCatalog.nodes(effective);
    // Some overseas accounts only get akamaized.net addresses; the nodes accept those
    // signatures too, so then every one of them is tried on every node.
    final donor = originals.where((url) => !isAkamai(url)).firstOrNull;
    final synthetic = donor != null
        ? [for (final node in nodes) ?swapHost(donor, node)]
        : [
            for (final node in nodes)
              for (final original in originals) ?swapHost(original, node, allowAkamai: true),
          ];
    final allowedOriginals = switch (effective) {
      CustomNodes(:final nodes) => originals.where((url) => nodes.any((node) => node.host == host(url))),
      OverseasNodes() => originals.where((url) => !mainland.contains(host(url))),
      MainlandNodes() => originals.where((url) => mainland.contains(host(url))),
    };
    return deduplicated([...allowedOriginals, ...synthetic.where(policy.allowsURL)]);
  }

  static List<String> deduplicated(List<String> list) {
    final seen = <String>{};
    return [for (final url in list) if (seen.add(url)) url];
  }
}
