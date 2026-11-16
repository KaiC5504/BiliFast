import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

/// The danmaku socket's operations.
abstract final class LiveOp {
  static const heartbeat = 2;
  static const heartbeatReply = 3;
  static const command = 5;
  static const auth = 7;
  static const authReply = 8;
}

/// A stream that can't be read as packets any more (a length that makes no sense); the connection has to go.
final class LivePacketError implements Exception {
  const LivePacketError(this.message);

  final String message;

  @override
  String toString() => 'LivePacketError: $message';
}

/// One packet: a 16-byte big-endian header (total length, header length, protover, op, seq) and its body.
final class LivePacket {
  const LivePacket({required this.op, required this.body, this.protover = 1, this.seq = 1});

  LivePacket.json({required this.op, required Object? json, this.protover = 1, this.seq = 1})
    : body = Uint8List.fromList(utf8.encode(jsonEncode(json)));

  static const headerLength = 16;

  // Far above anything the server sends; a larger length means the stream is out of step.
  static const maxLength = 16 << 20;

  static final _zlib = ZLibCodec();

  final int op;

  /// 0 or 1 plain, 2 zlib (sub-packets inside); 3 is brotli, which this socket never asks for.
  final int protover;
  final int seq;
  final Uint8List body;

  Uint8List encode() {
    final bytes = Uint8List(headerLength + body.length);
    ByteData.sublistView(bytes)
      ..setUint32(0, bytes.length)
      ..setUint16(4, headerLength)
      ..setUint16(6, protover)
      ..setUint32(8, op)
      ..setUint32(12, seq);
    bytes.setRange(headerLength, bytes.length, body);
    return bytes;
  }

  /// [data] as whole packets back to back, as a zlib body holds them; a cut-off packet at the end throws.
  static List<LivePacket> split(Uint8List data) {
    final reader = LivePacketReader()..add(data);
    final packets = reader.take();
    if (reader.pending > 0) throw const LivePacketError('cut-off packet');
    return packets;
  }

  /// An op 5 packet's command bodies (JSON bytes), zlib bodies opened and split. A body that won't open costs only
  /// itself: [onBad] hears its protover and the rest still come back.
  List<Uint8List> commands({void Function(int protover, Object error)? onBad}) {
    final result = <Uint8List>[];
    _collect(this, result, onBad, 0);
    return result;
  }

  static void _collect(LivePacket packet, List<Uint8List> into, void Function(int, Object)? onBad, int depth) {
    if (packet.op != LiveOp.command) return;
    switch (packet.protover) {
      case 0 || 1:
        into.add(packet.body);
      case 2 when depth < 4:
        final List<LivePacket> inner;
        try {
          inner = split(Uint8List.fromList(_zlib.decode(packet.body)));
        } catch (error) {
          onBad?.call(packet.protover, error);
          return;
        }
        for (final each in inner) {
          _collect(each, into, onBad, depth + 1);
        }
      default:
        onBad?.call(packet.protover, const LivePacketError('unsupported protover'));
    }
  }
}

/// Gathers a connection's bytes into whole packets, however the reads cut them.
final class LivePacketReader {
  final _buffer = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);

  /// Bytes held for a packet not yet whole.
  int get pending => _pending.length + _buffer.length;

  void add(List<int> bytes) => _buffer.add(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));

  /// The packets now whole, in order; throws [LivePacketError] when the stream can't be read as packets.
  List<LivePacket> take() {
    if (_buffer.isNotEmpty) {
      final joined = BytesBuilder(copy: false)
        ..add(_pending)
        ..add(_buffer.takeBytes());
      _pending = joined.takeBytes();
    }
    final packets = <LivePacket>[];
    var offset = 0;
    while (_pending.length - offset >= LivePacket.headerLength) {
      final header = ByteData.sublistView(_pending, offset, offset + LivePacket.headerLength);
      final total = header.getUint32(0);
      final headerLength = header.getUint16(4);
      if (headerLength < LivePacket.headerLength || total < headerLength || total > LivePacket.maxLength) {
        throw LivePacketError('bad lengths $total/$headerLength');
      }
      if (_pending.length - offset < total) break;
      packets.add(
        LivePacket(
          protover: header.getUint16(6),
          op: header.getUint32(8),
          seq: header.getUint32(12),
          body: Uint8List.sublistView(_pending, offset + headerLength, offset + total),
        ),
      );
      offset += total;
    }
    if (offset > 0) _pending = Uint8List.sublistView(_pending, offset);
    return packets;
  }
}
