import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bilifast/playback/shared_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const ali = 'upos-sz-mirrorali.bilivideo.com';
const cos = 'upos-sz-mirrorcos.bilivideo.com';

/// The nodes the shared engine's playbacks report in their stats, kept for 开发者's 状态.
void main() {
  late List<FakeEngine> engines;
  late SharedEngine shared;

  setUp(() {
    engines = [];
    shared = SharedEngine(() async {
      final engine = FakeEngine();
      engines.add(engine);
      return engine;
    }, logger: Logger(session: 'test'));
  });

  test('nothing before any playback reports', () async {
    expect(shared.seenNodes, isEmpty);
    await shared.current();
    expect(shared.seenNodes, isEmpty);
  });

  test('each node\'s best state, speed and first byte as reported', () async {
    await shared.current();
    engines.single.statsController.add(
      const EngineSnapshot(
        nodes: [NodeTiming(node: ali, firstByteMs: 62)],
        nodeStates: [
          NodeStatus(node: ali, state: 'banned', bps: 0),
          NodeStatus(node: ali, state: 'healthy', bps: 9e6),
          NodeStatus(node: cos, state: 'untested', bps: 0),
        ],
      ),
    );
    expect(shared.seenNodes, {
      ali: (state: 'healthy', firstByteMs: 62.0, bps: 9e6),
      cos: (state: 'untested', firstByteMs: 0.0, bps: 0.0),
    });
  });

  test('a later report changes the state, and keeps the last measurements where it has none', () async {
    await shared.current();
    final stats = engines.single.statsController;
    stats.add(
      const EngineSnapshot(
        nodes: [NodeTiming(node: ali, firstByteMs: 62)],
        nodeStates: [NodeStatus(node: ali, state: 'healthy', bps: 9e6)],
      ),
    );
    stats.add(
      const EngineSnapshot(
        nodes: [NodeTiming(node: ali, firstByteMs: double.infinity)],
        nodeStates: [NodeStatus(node: ali, state: 'banned', bps: 0)],
      ),
    );
    expect(shared.seenNodes[ali], (state: 'banned', firstByteMs: 62.0, bps: 9e6));
  });

  test(
    'what an engine reported stays when a replacement takes over, and the replacement\'s reports add to it',
    () async {
      final first = await shared.current();
      engines.single.statsController.add(
        const EngineSnapshot(
          nodeStates: [NodeStatus(node: ali, state: 'healthy', bps: 9e6)],
        ),
      );
      engines.single.closed = true;
      await engines.single.fatalController.close();
      await Future<void>.delayed(Duration.zero);
      final second = await shared.current();
      expect(second, isNot(same(first)));
      engines.last.statsController.add(
        const EngineSnapshot(
          nodeStates: [NodeStatus(node: cos, state: 'healthy', bps: 4e6)],
        ),
      );
      expect(shared.seenNodes.keys, unorderedEquals([ali, cos]));
    },
  );
}
