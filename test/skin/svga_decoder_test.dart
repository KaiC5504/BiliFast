import 'dart:convert';
import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

import 'package:bilifast/skin/svga/svga_decoder.dart';
import 'package:bilifast/skin/svga/svga_movie.dart';
import 'package:flutter_test/flutter_test.dart';

import 'svga_fixtures.dart';

void main() {
  final red = png(2, 2, 0xFFFF0000);

  group('SVGA 2', () {
    test('reads the movie: params, pictures, sprites and every part of a frame', () {
      final movie = SvgaDecoder.decode(
        movie2(
          version: '2.0.0',
          width: 750,
          height: 500,
          fps: 20,
          frames: 3,
          images: {'icon': red, 'sound': utf8.encode('ID3 not a picture')},
          sprites: [
            sprite2('icon', [
              frame2(
                alpha: 0.5,
                layout: [1, 2, 30, 40],
                transform: [2, 0.5, -0.5, 3, 10, 20],
                clipPath: 'M0 0 H10 V10 Z',
                shapes: [
                  shape2(type: 1, rect: [1, 2, 3, 4, 5], fill: [1, 0, 0, 1]),
                  shape2(type: 2, ellipse: [5, 6, 7, 8], stroke: [0, 0, 1, 0.5], strokeWidth: 2, lineCap: 1),
                  shape2(d: 'M0 0 L5 5', stroke: [0, 1, 0, 1], strokeWidth: 1, dash: [3, 2, 1]),
                ],
              ),
            ], matteKey: 'mask.matte'),
          ],
        ),
      );
      expect(movie.version, '2.0.0');
      expect((movie.width, movie.height, movie.fps, movie.frames), (750, 500, 20, 3));
      expect(movie.images.keys, ['icon'], reason: '2.x keeps its audio in the same map');
      expect(movie.images['icon'], red);
      final sprite = movie.sprites.single;
      expect(sprite.imageKey, 'icon');
      expect(sprite.matteKey, 'mask.matte');
      final frame = sprite.frames.single;
      expect(frame.alpha, 0.5);
      expect((frame.layout!.x, frame.layout!.y, frame.layout!.width, frame.layout!.height), (1, 2, 30, 40));
      final t = frame.transform!;
      expect((t.a, t.b, t.c, t.d, t.tx, t.ty), (2, 0.5, -0.5, 3, 10, 20));
      expect(frame.clipPath, 'M0 0 H10 V10 Z');
      final [rect, ellipse, path] = frame.shapes;
      expect(rect.type, SvgaShapeType.rect);
      expect((rect.rect!.x, rect.rect!.y, rect.rect!.width, rect.rect!.height, rect.cornerRadius), (1, 2, 3, 4, 5));
      expect((rect.style!.fill!.r, rect.style!.fill!.a), (1, 1));
      expect(rect.style!.stroke, isNull);
      expect(ellipse.type, SvgaShapeType.ellipse);
      expect((ellipse.ellipseCenterX, ellipse.ellipseCenterY, ellipse.radiusX, ellipse.radiusY), (5, 6, 7, 8));
      expect((ellipse.style!.stroke!.b, ellipse.style!.stroke!.a, ellipse.style!.strokeWidth), (1, 0.5, 2));
      expect(ellipse.style!.lineCap, SvgaLineCap.round);
      expect(path.type, SvgaShapeType.path);
      expect(path.d, 'M0 0 L5 5');
      expect((path.style!.dash, path.style!.gap, path.style!.dashOffset), (3, 2, 1));
    });

    test('what a frame leaves out: no alpha hides it, no transform is the identity, no layout or clip is none', () {
      final movie = SvgaDecoder.decode(
        movie2(
          frames: 4,
          sprites: [
            sprite2('a', [
              frame2(),
              frame2(alpha: 1),
              frame2(alpha: 1, transform: [1, 0, 0, 1, 5, 0]),
            ]),
          ],
        ),
      );
      final sprite = movie.sprites.single;
      final [hidden, bare, moved] = sprite.frames;
      expect(hidden.visible, isFalse);
      expect(bare.visible, isTrue);
      expect(bare.transform, isNull);
      expect(bare.layout, isNull);
      expect(bare.clipPath, isNull);
      expect(bare.shapes, isEmpty);
      // proto3 leaves zero fields out: b, c and ty here.
      expect((moved.transform!.a, moved.transform!.b, moved.transform!.d, moved.transform!.tx), (1, 0, 1, 5));
      expect(sprite.frameAt(3), same(SvgaFrame.hidden), reason: 'past its last frame a sprite is hidden');
      expect(sprite.frameAt(-1).visible, isFalse);
    });

    test('a KEEP shape takes the previous frame\'s shapes, and KEEP again keeps them', () {
      final movie = SvgaDecoder.decode(
        movie2(
          frames: 4,
          sprites: [
            sprite2('a.vector', [
              frame2(
                alpha: 1,
                shapes: [
                  shape2(d: 'M0 0 L1 1', fill: [1, 1, 1, 1]),
                ],
              ),
              frame2(alpha: 1, shapes: [shape2(type: 3)]),
              frame2(alpha: 1, shapes: [shape2(type: 3)]),
              frame2(
                alpha: 1,
                shapes: [
                  shape2(type: 1, rect: [0, 0, 2, 2], fill: [1, 1, 1, 1]),
                ],
              ),
            ]),
          ],
        ),
      );
      final frames = movie.sprites.single.frames;
      expect(frames[1].shapes, same(frames[0].shapes));
      expect(frames[2].shapes, same(frames[0].shapes));
      expect(frames[3].shapes.single.type, SvgaShapeType.rect);
    });

    test('fields it doesn\'t know are skipped, whatever their wire type', () {
      final movie = SvgaDecoder.decode(
        movie2(
          frames: 2,
          sprites: [
            sprite2('a', [frame2(alpha: 1)]),
          ],
          extra: (movie) => movie
            ..varint(90, 1 << 40)
            ..fixed64(91, 7)
            ..float(92, 1)
            ..string(93, 'later'),
        ),
      );
      expect(movie.sprites.single.frames.single.alpha, 1);
    });

    test('frames 0 in the params falls back to the longest sprite', () {
      final movie = SvgaDecoder.decode(
        movie2(
          frames: 0,
          sprites: [
            sprite2('a', [frame2(), frame2(), frame2()]),
          ],
        ),
      );
      expect(movie.frames, 3);
    });
  });

  group('SVGA 1', () {
    Map<String, Object?> spec({List<Object?>? sprites, Map<String, Object?>? images}) => {
      'ver': '1.1.0',
      'movie': {
        'viewBox': {'width': 300, 'height': 200},
        'fps': 15,
        'frames': 2,
      },
      'images': images ?? {'img_0': 'img_0'},
      'sprites': sprites ?? [],
    };

    test('reads movie.spec and finds each picture by its file name with or without .png', () {
      final movie = SvgaDecoder.decode(
        movie1(
          spec(
            images: {'img_0': 'img_0', 'img_1': 'other.png'},
            sprites: [
              {
                'imageKey': 'img_0',
                'frames': [
                  {
                    'alpha': 0.75,
                    'layout': {'x': 1, 'y': 2, 'width': 30, 'height': 40},
                    'transform': {'a': 1, 'b': 0, 'c': 0, 'd': 1, 'tx': 5, 'ty': 6},
                    'clipPath': 'M0 0 L1 1',
                    'shapes': [
                      {
                        'type': 'rect',
                        'args': {'x': 0, 'y': 0, 'width': 4, 'height': 5, 'cornerRadius': 1},
                        'styles': {
                          'fill': [255, 0, 0, 255],
                          'stroke': [0, 0, 1, 1],
                          'strokeWidth': 2,
                          'lineCap': 'square',
                          'lineJoin': 'bevel',
                          'lineDash': [4, 2, 0],
                        },
                      },
                      {
                        'type': 'ellipse',
                        'args': {'x': 1, 'y': 2, 'radiusX': 3, 'radiusY': 4},
                      },
                    ],
                  },
                  <String, Object?>{},
                ],
              },
              {
                'imageKey': 'img_1',
                'matteKey': 'm.matte',
                'frames': [
                  {
                    'alpha': 1,
                    'shapes': [
                      {
                        'type': 'shape',
                        'args': {'d': 'M0 0'},
                      },
                    ],
                  },
                  {
                    'alpha': 1,
                    'shapes': [
                      {'type': 'keep'},
                    ],
                  },
                ],
              },
            ],
          ),
          files: {'img_0.png': red, 'other.png': red, '__MACOSX/._img_0.png': red},
        ),
      );
      expect(movie.version, '1.1.0');
      expect((movie.width, movie.height, movie.fps, movie.frames), (300, 200, 15, 2));
      expect(movie.images.keys, unorderedEquals(['img_0', 'img_1']));
      final [first, second] = movie.sprites;
      final frame = first.frames.first;
      expect(frame.alpha, 0.75);
      expect((frame.layout!.x, frame.layout!.width), (1, 30));
      expect((frame.transform!.tx, frame.transform!.ty), (5, 6));
      expect(frame.clipPath, 'M0 0 L1 1');
      final [rect, ellipse] = frame.shapes;
      expect(rect.type, SvgaShapeType.rect);
      expect(rect.cornerRadius, 1);
      final style = rect.style!;
      expect((style.fill!.r, style.fill!.g, style.fill!.a), (1, 0, 1), reason: '0-255 channels are scaled to 0-1');
      expect((style.stroke!.b, style.strokeWidth), (1, 2));
      expect((style.lineCap, style.lineJoin), (SvgaLineCap.square, SvgaLineJoin.bevel));
      expect((style.dash, style.gap, style.dashOffset), (4, 2, 0));
      expect((ellipse.ellipseCenterX, ellipse.radiusY), (1, 4));
      expect(ellipse.style, isNull);
      expect(first.frames[1].visible, isFalse, reason: 'a hidden frame is {}');
      expect(second.matteKey, 'm.matte');
      expect(second.frames[1].shapes, same(second.frames[0].shapes));
    });

    test('a zip holding movie.binary is read as SVGA 2, its pictures named or held', () {
      final binary = ProtoWriter()
        ..string(1, '2.0.0')
        ..message(
          2,
          ProtoWriter()
            ..float(1, 10)
            ..float(2, 10)
            ..varint(3, 30)
            ..varint(4, 1),
        )
        ..message(
          3,
          ProtoWriter()
            ..string(1, 'named')
            ..bytes(2, utf8.encode('pic')),
        )
        ..message(
          3,
          ProtoWriter()
            ..string(1, 'held')
            ..bytes(2, red),
        );
      final movie = SvgaDecoder.decode(movie1(null, files: {'movie.binary': binary.toBytes(), 'pic.png': red}));
      expect(movie.fps, 30);
      expect(movie.images.keys, unorderedEquals(['named', 'held']));
    });
  });

  group('refuses', () {
    test('bytes that are neither zlib nor a zip', () {
      expect(() => SvgaDecoder.decode(Uint8List.fromList(List.generate(64, (i) => i * 7))), throwsFormatException);
    });

    test('a truncated movie', () {
      final whole =
          (ProtoWriter()..message(
                4,
                sprite2('a', [
                  frame2(alpha: 1, layout: [0, 0, 1, 1]),
                ]),
              ))
              .toBytes();
      final cut = whole.sublist(0, whole.length - 2);
      expect(() => SvgaDecoder.decode(Uint8List.fromList(ZLibEncoder().convert(cut))), throwsFormatException);
    });

    test('a movie with no view box', () {
      expect(() => SvgaDecoder.decode(movie2(width: 0)), throwsFormatException);
    });

    test('a zip without movie.spec, or with a spec that is not JSON', () {
      expect(() => SvgaDecoder.decode(movie1(null, files: {'a.png': red})), throwsFormatException);
      expect(() => SvgaDecoder.decode(movie1(null, files: {'movie.spec': utf8.encode('{{')})), throwsFormatException);
    });
  });
}
