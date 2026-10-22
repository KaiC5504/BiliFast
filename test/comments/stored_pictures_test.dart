import 'package:bili_core/api.dart' hide RichText;
import 'package:bilifast/comments/comment_badges.dart';
import 'package:bilifast/comments/comment_row.dart' show CommentPictures;
import 'package:bilifast/comments/picture_viewer.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/stored_pictures.dart';

const _picture = CommentPicture(url: 'https://i0.hdslb.com/bfs/new_dyn/moving.gif', width: 400, height: 300);

void main() {
  tearDown(
    () => PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages(),
  );

  Future<void> show(WidgetTester tester, Widget child) {
    tester.view
      ..physicalSize = const Size(1320, 2868)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(440, 956), devicePixelRatio: 3),
        child: Directionality(textDirection: TextDirection.ltr, child: child),
      ),
    );
  }

  List<ImageProvider> images(WidgetTester tester) => [
    for (final image in tester.widgetList<Image>(find.byType(Image))) image.image,
  ];

  testWidgets('avatar frames and badges come from the pictures kept on the phone, and still move', (tester) async {
    final pictures = await StoredPictures.keep(tester);
    await show(
      tester,
      const Center(
        child: SizedBox.square(dimension: 60, child: DecorImage('//i0.hdslb.com/bfs/garb/item/pendant.gif')),
      ),
    );
    await StoredPictures.arrive(tester);
    expect(pictures.downloads, ['https://i0.hdslb.com/bfs/garb/item/pendant.gif']);
    expect(images(tester).single, isA<StoredNetworkImage>().having((image) => image.still, 'still', isFalse));
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    await pictures.drop(tester);
  });

  testWidgets("a comment's pictures come from the pictures kept on the phone, and the viewer shows the list's own "
      'thumbnail while its picture loads', (tester) async {
    final pictures = await StoredPictures.keep(tester);
    await show(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 440,
          child: CommentPictures(pictures: const [_picture], onOpen: (_) {}),
        ),
      ),
    );
    await StoredPictures.arrive(tester);
    final thumbnail = images(tester).single as StoredNetworkImage;
    expect(thumbnail.still, isFalse, reason: 'a GIF keeps moving');
    expect(pictures.downloads, [thumbnail.url]);

    await show(tester, PictureViewer(pictures: const [_picture], initialIndex: 0, onClose: () {}));
    await tester.pump();
    final [picture, under] = images(tester);
    expect(under, thumbnail, reason: 'found in the image cache under the key the list used');
    expect(picture, isA<StoredNetworkImage>().having((image) => image.still, 'still', isFalse));

    await StoredPictures.arrive(tester);
    expect(pictures.downloads, [thumbnail.url, (picture as StoredNetworkImage).url]);
    await pictures.drop(tester);
  });
}
