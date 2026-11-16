import 'package:bili_core/api.dart';
import 'package:bili_core/danmaku.dart';
import 'package:bilifast/danmaku/danmaku_settings.dart';
import 'package:bilifast/live/danmaku/live_danmaku_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'live_send_support.dart';

void main() {
  late LiveHarness harness;
  late FakeRoom room;

  Future<void> pumpLayer(WidgetTester tester, {bool on = true, Size box = const Size(440, 247.5)}) => pumpLive(
    tester,
    harness,
    Align(
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: box,
        child: LiveDanmakuLayer(room: room, on: on),
      ),
    ),
    size: box.width > 440 ? const Size(956, 440) : const Size(440, 956),
  );

  LiveDanmakuLayerState layer(WidgetTester tester) => tester.state(find.byType(LiveDanmakuLayer));

  List<String> shown(WidgetTester tester) => [for (final item in layer(tester).scene.visible) item.text];

  Future<void> frames(WidgetTester tester, [int count = 10]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  setUp(() async {
    room = FakeRoom(api: demoApi());
  });

  tearDown(() => room.dispose());

  testWidgets('a danmaku from the feed enters now and flies across', (tester) async {
    harness = await liveHarness();
    await pumpLayer(tester);
    await frames(tester, 2);
    expect(layer(tester).ticking, isFalse, reason: 'nothing on screen, nothing due');

    room.fly(danmaku('上船了'));
    await frames(tester, 3);
    final first = layer(tester).scene.visible.single;
    expect(first.text, '上船了');
    expect(first.kind, LaneKind.scroll);
    // Entered at the right edge a frame or two ago.
    expect(first.rect.left, greaterThan(440 - 20));

    await frames(tester, 30);
    expect(layer(tester).scene.visible.single.rect.left, lessThan(first.rect.left - 30));
  });

  testWidgets('top and bottom danmaku keep their mode, and the colour is the message\'s', (tester) async {
    harness = await liveHarness();
    await pumpLayer(tester);
    room
      ..fly(danmaku('顶部', mode: 5, color: 0xFFFF0000))
      ..fly(danmaku('底部', mode: 4));
    await frames(tester, 3);
    final kinds = {for (final item in layer(tester).scene.visible) item.text: item.kind};
    expect(kinds, {'顶部': LaneKind.top, '底部': LaneKind.bottom});
  });

  testWidgets('a whole-message emote flies as its name', (tester) async {
    harness = await liveHarness();
    await pumpLayer(tester);
    room.fly(
      danmaku(
        '',
        bigEmote: const LiveEmote(text: '赞', url: '', unique: 'room_zan'),
      ),
    );
    await frames(tester, 3);
    expect(shown(tester), ['赞']);
  });

  testWidgets('off: nothing flies, and what came meanwhile is dropped, not queued', (tester) async {
    harness = await liveHarness();
    await pumpLayer(tester, on: false);
    room.fly(danmaku('关着的时候'));
    await frames(tester, 3);
    expect(layer(tester).held, 0);
    expect(layer(tester).ticking, isFalse);

    await pumpLayer(tester);
    await frames(tester, 3);
    expect(shown(tester), isEmpty);
    room.fly(danmaku('开了以后'));
    await frames(tester, 3);
    expect(shown(tester), ['开了以后']);

    // Turning it off takes what is flying away at once.
    await pumpLayer(tester, on: false);
    await frames(tester, 2);
    expect(layer(tester).scene.visible, isEmpty);
    expect(layer(tester).ticking, isFalse);
  });

  testWidgets('this account\'s own danmaku passes its 屏蔽词', (tester) async {
    harness = await liveHarness(
      rules: [const BlockRule(id: 1, kind: BlockRuleKind.keyword, filter: '剧透')],
    );
    await pumpLayer(tester);
    room.fly(danmaku('我自己剧透', uid: selfUid));
    await frames(tester, 3);
    expect(shown(tester), ['我自己剧透']);
  });

  testWidgets('a 屏蔽词 keeps its danmaku off, and a blocked user too', (tester) async {
    harness = await liveHarness(
      rules: [
        const BlockRule(id: 1, kind: BlockRuleKind.keyword, filter: '剧透'),
        BlockRule(id: 2, kind: BlockRuleKind.user, filter: MidHash.of(4242)),
      ],
    );
    await pumpLayer(tester);
    room
      ..fly(danmaku('不要剧透啊'))
      ..fly(danmaku('被屏蔽的人', uid: 4242))
      ..fly(danmaku('正常的'));
    await frames(tester, 3);
    expect(shown(tester), ['正常的']);
  });

  testWidgets('the 弹幕设置 values apply: type switches, area, speed, size and opacity', (tester) async {
    harness = await liveHarness();
    harness.settings.update(
      DanmakuSettings(
        area: 0.25,
        opacity: 0.6,
        scale: 1.5,
        speed: 4,
        filter: const DanmakuFilterOptions(blockScroll: true),
      ),
    );
    await pumpLayer(tester);
    final options = layer(tester).options;
    expect(options.area, 0.25);
    expect(options.scale, 1.5);
    expect(options.scrollDuration, DanmakuSettings.scrollDurations[4]);
    expect(
      tester
          .widget<Opacity>(find.descendant(of: find.byType(LiveDanmakuLayer), matching: find.byType(Opacity)))
          .opacity,
      0.6,
    );

    room
      ..fly(danmaku('滚动的'))
      ..fly(danmaku('顶部的', mode: 5));
    await frames(tester, 3);
    expect(shown(tester), ['顶部的']);

    // A change shows at once.
    harness.settings.update(harness.settings.value.copyWith(filter: const DanmakuFilterOptions(), opacity: 1));
    await tester.pump();
    expect(
      tester
          .widget<Opacity>(find.descendant(of: find.byType(LiveDanmakuLayer), matching: find.byType(Opacity)))
          .opacity,
      1,
    );
    room.fly(danmaku('又能滚了'));
    await frames(tester, 3);
    expect(shown(tester), containsAll(['顶部的', '又能滚了']));
  });

  testWidgets('合并重复 drops a repeat within ten seconds', (tester) async {
    harness = await liveHarness();
    harness.settings.update(const DanmakuSettings(filter: DanmakuFilterOptions(dedupe: true)));
    await pumpLayer(tester);
    room
      ..fly(danmaku('哈哈哈', id: 'a'))
      ..fly(danmaku('哈哈哈', id: 'b'));
    await frames(tester, 3);
    expect(shown(tester), ['哈哈哈']);
  });

  testWidgets('the ticker sleeps once the screen is clear', (tester) async {
    harness = await liveHarness();
    harness.settings.update(const DanmakuSettings(speed: 4));
    await pumpLayer(tester);
    room.fly(danmaku('一闪而过'));
    await frames(tester, 2);
    expect(layer(tester).ticking, isTrue);
    await tester.pump(const Duration(seconds: 5));
    await frames(tester, 3);
    expect(layer(tester).scene.visible, isEmpty);
    expect(layer(tester).ticking, isFalse);

    // And wakes for the next one, its clock carrying on.
    room.fly(danmaku('下一条'));
    await frames(tester, 3);
    expect(shown(tester), ['下一条']);
  });

  testWidgets('what is flying survives the box growing to full screen', (tester) async {
    harness = await liveHarness();
    await pumpLayer(tester);
    room.fly(danmaku('跟着全屏'));
    await frames(tester, 60);
    expect(layer(tester).options.fullScreen, isFalse);

    await pumpLayer(tester, box: const Size(956, 440));
    await frames(tester, 3);
    expect(layer(tester).options.fullScreen, isTrue);
    final item = layer(tester).scene.visible.single;
    expect(item.text, '跟着全屏');
    // Mid-flight at the new width, not entering again.
    expect(item.rect.left, lessThan(956 - 100));
  });

  testWidgets('a busy room keeps the timeline short', (tester) async {
    harness = await liveHarness();
    await pumpLayer(tester);
    for (var i = 0; i < 700; i++) {
      room.fly(danmaku('第$i条', id: '$i'));
      if (i % 50 == 0) await tester.pump(const Duration(milliseconds: 16));
    }
    expect(layer(tester).held, lessThanOrEqualTo(600));
    await frames(tester, 3);
    expect(layer(tester).scene.visible, isNotEmpty);
    await tester.pump(const Duration(seconds: 15));
    await frames(tester, 2);
  });
}
