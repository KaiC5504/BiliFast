import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'node_memory.dart';

/// [NodeMemory] in a JSON file. A missing or unreadable file starts an empty memory; the file holds node names,
/// speeds and hashed network names, nothing about the account.
final class NodeMemoryStore {
  NodeMemoryStore(this.path);

  final String path;

  NodeMemory load() {
    try {
      return NodeMemory.fromJson(jsonDecode(File(path).readAsStringSync()));
    } catch (_) {
      return NodeMemory();
    }
  }

  /// Written beside the file and renamed over it, so a kill mid-write leaves the old memory.
  void save(NodeMemory memory) {
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      final temporary = File('$path.tmp')..writeAsStringSync(jsonEncode(memory.toJson()), flush: true);
      temporary.renameSync(path);
    } catch (_) {
      // The memory is a speed-up; losing it costs one slower start.
    }
  }

  /// Wi-Fi and wired networks by their /24, so home and elsewhere keep apart; every cellular network is one, since
  /// its addresses change all the time. Empty turns the memory off.
  static Future<String> networkSignature() async {
    final List<NetworkInterface> interfaces;
    try {
      interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    } catch (_) {
      return '';
    }
    bool cellular(NetworkInterface i) => i.name.startsWith('pdp_ip');
    for (final interface in interfaces) {
      if (cellular(interface) || interface.name.startsWith('utun') || interface.addresses.isEmpty) continue;
      final prefix = interface.addresses.first.address.split('.').take(3).join('.');
      return 'lan:${sha1.convert(utf8.encode(prefix)).toString().substring(0, 12)}';
    }
    return interfaces.any(cellular) ? 'cellular' : '';
  }
}
