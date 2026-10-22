import 'dart:ui' as ui;

import 'package:bilifast/skin/svga/svga_decoder.dart';
import 'package:bilifast/skin/svga/svga_painter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'svga_fixtures.dart';

const red = 0xFFFF0000;
const green = 0xFF00FF00;
const clear = 0x00000000;

Future<SvgaComposition> compose(Uint8List file) async {
  final movie = SvgaDecoder.decode(file);
  final images = <String, ui.Image>{};
  for (final MapEntry(:key, :value) in movie.images.entries) {
    final codec = await ui.instantiateImageCodec(value);
    images[key] = (await codec.getNextFrame()).image;
  }
  return SvgaComposition(movie, images);
}

/// Frame [frame] drawn into [width] × [height] pixels, read back as 0xAARRGGBB by position.
Future<int Function(int x, int y)> render(
  SvgaComposition composition, {
  int frame = 0,
  int width = 10,
  int height = 10,
  BoxFit fit = BoxFit.contain,
}) async {
  final recorder = ui.PictureRecorder();
  SvgaPainter(
    composition: composition,
    frame: ValueNotifier(frame),
    fit: fit,
  ).paint(ui.Canvas(recorder), Size(width.toDouble(), height.toDouble()));
  final image = await recorder.endRecording().toImage(width, height);
  final data = (await image.toByteData())!;
  return (int x, int y) {
    final at = (y * width + x) * 4;
    final [r, g, b, a] = [for (var i = 0; i < 4; i++) data.getUint8(at + i)];
    return a << 24 | r << 16 | g << 8 | b;
  };
}

/// One sprite with a 2 × 2 red picture over a 10 × 10 view box.
Uint8List single(ProtoWriter frame, {int frames = 1}) => movie2(
  width: 10,
  height: 10,
  frames: frames,
  images: {'pic': png(2, 2, red)},
  sprites: [
    sprite2('pic', [frame]),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the picture fills its layout, moved by the frame\'s transform', () async {
    final pixel = await render(
      await compose(single(frame2(alpha: 1, layout: [0, 0, 4, 4], transform: [1, 0, 0, 1, 3, 2]))),
    );
    expect(pixel(3, 2), red);
    expect(pixel(6, 5), red);
    expect(pixel(2, 2), clear);
    expect(pixel(7, 5), clear);
    expect(pixel(4, 6), clear);
  });

  test('a scaling transform scales the layout around the origin', () async {
    final pixel = await render(
      await compose(single(frame2(alpha: 1, layout: [1, 1, 2, 2], transform: [2, 0, 0, 2, 0, 0]))),
    );
    expect(pixel(2, 2), red);
    expect(pixel(5, 5), red);
    expect(pixel(1, 1), clear);
    expect(pixel(6, 6), clear);
  });

  test('alpha fades the picture; a hidden frame draws nothing', () async {
    final faded = await render(await compose(single(frame2(alpha: 0.5, layout: [0, 0, 10, 10]))));
    expect(faded(5, 5) >>> 24, closeTo(128, 2));
    final hidden = await render(await compose(single(frame2(layout: [0, 0, 10, 10]))));
    expect(hidden(5, 5), clear);
  });

  test('the clip path cuts the picture in the sprite\'s own coordinates', () async {
    final pixel = await render(
      await compose(
        single(frame2(alpha: 1, layout: [0, 0, 10, 10], transform: [1, 0, 0, 1, 2, 0], clipPath: 'M0 0 h4 v10 h-4 z')),
      ),
    );
    expect(pixel(2, 5), red);
    expect(pixel(5, 5), red);
    expect(pixel(6, 5), clear);
    expect(pixel(1, 5), clear);
  });

  test('the view box is fitted: contain centres it, cover fills and crops', () async {
    final movie = await compose(single(frame2(alpha: 1, layout: [0, 0, 10, 10])));
    final contained = await render(movie, width: 20, height: 10);
    expect(contained(4, 5), clear);
    expect(contained(5, 5), red);
    expect(contained(14, 5), red);
    expect(contained(15, 5), clear);
    final covered = await render(movie, width: 20, height: 10, fit: BoxFit.cover);
    expect(covered(0, 0), red);
    expect(covered(19, 9), red);
  });

  test('drawing stays inside the view box', () async {
    final pixel = await render(await compose(single(frame2(alpha: 1, layout: [-5, 0, 30, 10]))), width: 20);
    expect(pixel(7, 5), red);
    expect(pixel(2, 5), clear, reason: 'left of the centred box');
    expect(pixel(17, 5), clear);
  });

  test('shapes: a rect\'s fill, an ellipse, a path\'s stroke, each under its own transform', () async {
    final pixel = await render(
      await compose(
        movie2(
          width: 10,
          height: 10,
          sprites: [
            sprite2('a.vector', [
              frame2(
                alpha: 1,
                shapes: [
                  shape2(type: 1, rect: [0, 0, 3, 3], fill: [0, 1, 0, 1]),
                  shape2(type: 2, ellipse: [7, 2, 2, 2], fill: [1, 0, 0, 1]),
                  shape2(d: 'M0 8 H10', stroke: [0, 1, 0, 1], strokeWidth: 2, transform: [1, 0, 0, 1, 0, 0]),
                  shape2(type: 1, rect: [0, 0, 1, 1], fill: [1, 0, 0, 1], transform: [1, 0, 0, 1, 4, 4]),
                ],
              ),
            ]),
          ],
        ),
      ),
    );
    expect(pixel(1, 1), green);
    expect(pixel(4, 1), clear);
    expect(pixel(7, 2), red);
    expect(pixel(5, 8), green);
    expect(pixel(5, 5), clear);
    expect(pixel(4, 4), red);
  });

  test('a dashed stroke leaves its gaps', () async {
    final pixel = await render(
      await compose(
        movie2(
          width: 10,
          height: 10,
          sprites: [
            sprite2('a.vector', [
              frame2(
                alpha: 1,
                shapes: [
                  shape2(d: 'M0 5 H10', stroke: [0, 1, 0, 1], strokeWidth: 2, dash: [2, 2]),
                ],
              ),
            ]),
          ],
        ),
      ),
    );
    expect(pixel(0, 5), green);
    expect(pixel(1, 5), green);
    expect(pixel(2, 5), clear);
    expect(pixel(3, 5), clear);
    expect(pixel(4, 5), green);
  });

  test('a matte masks the sprite that names it and isn\'t drawn itself', () async {
    final pixel = await render(
      await compose(
        movie2(
          width: 10,
          height: 10,
          images: {'pic': png(2, 2, red)},
          sprites: [
            sprite2('m.matte', [
              frame2(
                alpha: 1,
                shapes: [
                  shape2(type: 1, rect: [0, 0, 5, 10], fill: [0, 0, 1, 1]),
                ],
              ),
            ]),
            sprite2('pic', [
              frame2(alpha: 1, layout: [0, 0, 10, 5]),
            ], matteKey: 'm.matte'),
          ],
        ),
      ),
    );
    expect(pixel(2, 2), red);
    expect(pixel(7, 2), clear);
    expect(pixel(2, 7), clear, reason: 'the matte\'s own blue never shows');
  });

  test('a sprite\'s frame follows the frame drawn; past its frames it is hidden', () async {
    final movie = await compose(
      movie2(
        width: 10,
        height: 10,
        frames: 3,
        images: {'pic': png(2, 2, red)},
        sprites: [
          sprite2('pic', [
            frame2(alpha: 1, layout: [0, 0, 5, 5]),
            frame2(alpha: 1, layout: [5, 5, 5, 5]),
          ]),
        ],
      ),
    );
    expect((await render(movie))(2, 2), red);
    final second = await render(movie, frame: 1);
    expect(second(2, 2), clear);
    expect(second(7, 7), red);
    final third = await render(movie, frame: 2);
    expect(third(7, 7), clear);
  });
}
