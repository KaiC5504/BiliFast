import 'package:bili_core/devlog.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(WidgetTester tester, List<Widget> images, {double ratio = 1}) async {
    tester.view.physicalSize = Size(440 * ratio, 900 * ratio);
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [for (final image in images) SizedBox(width: 214, height: 160, child: image)],
        ),
      ),
    );
  }

  List<String> urls(WidgetTester tester) => [
    for (final image in tester.widgetList<Image>(find.byType(Image))) (image.image as NetworkImage).url,
  ];

  testWidgets('a box asks for its own size in steps; a fixed size is asked for whatever the box', (tester) async {
    await show(tester, ratio: 2, const [
      RemoteImage('https://i0.hdslb.com/bfs/archive/a.jpg'),
      RemoteImage('https://i0.hdslb.com/bfs/archive/b.jpg', size: Size(100, 50)),
    ]);
    expect(urls(tester), [
      'https://i1.hdslb.com/bfs/archive/a.jpg@480w_360h_1c.webp',
      'https://i1.hdslb.com/bfs/archive/b.jpg@240w_120h_1c.webp',
    ]);
  });

  testWidgets('a placeholder shows instead of the grey', (tester) async {
    await show(tester, const [
      RemoteImage('https://i0.hdslb.com/bfs/archive/a.jpg', placeholder: Text('card', key: ValueKey('under'))),
    ]);
    expect(find.byKey(const ValueKey('under')), findsOneWidget);
    expect(find.byType(ColoredBox), findsNothing);
  });

  testWidgets('a fallback shows for an empty url, while loading and after a failure, with no grey', (tester) async {
    await show(tester, const [
      RemoteImage('', fallback: Text('none', key: ValueKey('empty'))),
      RemoteImage('https://i7.hdslb.com/bfs/face/a.jpg', fallback: Text('none', key: ValueKey('loading'))),
    ]);
    expect(find.byKey(const ValueKey('empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('loading')), findsOneWidget);
    expect(find.byType(ColoredBox), findsNothing);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('loading')), findsOneWidget, reason: 'the test server answers 400');
  });

  testWidgets('without a fallback a failure leaves the grey, as before', (tester) async {
    await show(tester, const [RemoteImage('')]);
    expect(find.byType(ColoredBox), findsOneWidget);
  });

  testWidgets('an avatar falls back to Bilibili\'s default face', (tester) async {
    await show(tester, const [RemoteImage.avatar(null), RemoteImage.avatar('https://i6.hdslb.com/bfs/face/b.jpg')]);
    expect(find.byType(DefaultAvatar), findsNWidgets(2));
    final asset = tester.widget<Image>(find.byKey(const ValueKey('default-avatar')).first).image as AssetImage;
    expect(asset.assetName, 'assets/images/noface.jpeg');
  });

  testWidgets('a failure is logged once per host and status, with the path and never the query', (tester) async {
    final sink = MemorySink();
    Logger.shared.add(sink);
    addTearDown(() => Logger.shared.remove(sink));
    await show(tester, const [
      RemoteImage('https://i9.hdslb.com/bfs/archive/a.jpg'),
      RemoteImage('https://i9.hdslb.com/bfs/archive/b.jpg'),
      RemoteImage('https://i8.hdslb.com/bfs/face/c.jpg?token=hidden'),
    ]);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final failures = [for (final event in sink.events) if (event.msg == 'image failed') event.f];
    expect(failures, [
      {
        'host': const LogString('i9.hdslb.com'),
        'path': const LogString('/bfs/archive/a.jpg@240w_180h_1c.webp'),
        'status': const LogInt(400),
      },
      {
        'host': const LogString('i8.hdslb.com'),
        'path': const LogString('/bfs/face/c.jpg'),
        'status': const LogInt(400),
      },
    ]);
  });
}
