import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/comments/composer_model.dart';
import 'package:bilifast/comments/picture_attach.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

class FakePicker extends Fake implements ImagePicker {
  FakePicker(this.answer);

  final Future<List<XFile>> Function() answer;
  final calls = <({int? limit, int? imageQuality, double? maxWidth, double? maxHeight, bool fullMetadata})>[];

  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) {
    calls.add((
      limit: limit,
      imageQuality: imageQuality,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      fullMetadata: requestFullMetadata,
    ));
    return answer();
  }
}

/// On the PC an XFile's name is the last part of its path.
XFile file(List<int> bytes, String name) => XFile.fromData(Uint8List.fromList(bytes), path: name);

final pngBytes = base64.decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

List<int> segment(int marker, List<int> data) => [
  0xFF,
  marker,
  (data.length + 2) >> 8,
  (data.length + 2) & 0xFF,
  ...data,
];

Uint8List jpeg(List<List<int>> segments) => Uint8List.fromList([
  0xFF, 0xD8, //
  for (final each in segments) ...each,
  0xFF, 0xDA, 0x00, 0x04, 0x01, 0x02, 0x11, 0x22, 0x33, 0xFF, 0xD9,
]);

/// A TIFF block as a phone writes it: IFD0 with the orientation and a pointer to the GPS IFD at 38, which holds
/// GPSLatitudeRef inline and GPSLatitude's three rationals out of line at 68.
Uint8List tiff(Endian endian) {
  final data = ByteData(92);
  data.setUint8(0, endian == Endian.little ? 0x49 : 0x4D);
  data.setUint8(1, endian == Endian.little ? 0x49 : 0x4D);
  data.setUint16(2, 42, endian);
  data.setUint32(4, 8, endian);
  data.setUint16(8, 2, endian);
  data.setUint16(10, 0x0112, endian);
  data.setUint16(12, 3, endian);
  data.setUint32(14, 1, endian);
  data.setUint16(18, 6, endian);
  data.setUint16(22, 0x8825, endian);
  data.setUint16(24, 4, endian);
  data.setUint32(26, 1, endian);
  data.setUint32(30, 38, endian);
  data.setUint32(34, 0, endian);
  data.setUint16(38, 2, endian);
  data.setUint16(40, 0x0001, endian);
  data.setUint16(42, 2, endian);
  data.setUint32(44, 2, endian);
  data.setUint8(48, 0x4E);
  data.setUint16(52, 0x0002, endian);
  data.setUint16(54, 5, endian);
  data.setUint32(56, 3, endian);
  data.setUint32(60, 68, endian);
  data.setUint32(64, 0, endian);
  for (final (index, (top, bottom)) in [(31, 1), (12, 1), (3456, 100)].indexed) {
    data.setUint32(68 + index * 8, top, endian);
    data.setUint32(72 + index * 8, bottom, endian);
  }
  return data.buffer.asUint8List();
}

List<int> exif(Uint8List tiff) => segment(0xE1, [...ascii.encode('Exif\x00\x00'), ...tiff]);

List<int> xmp(String body) =>
    segment(0xE1, [...ascii.encode('http://ns.adobe.com/xap/1.0/\x00'), ...utf8.encode(body)]);

void main() {
  late MemorySink sink;

  setUp(() {
    sink = MemorySink();
    Logger.shared.add(sink);
  });

  tearDown(() => Logger.shared.remove(sink));

  group('pickPictures', () {
    test('asks the system picker for up to the limit, without full metadata, re-encoded at quality 90', () async {
      final picker = FakePicker(
        () async => [
          file(pngBytes, 'image_picker_1.png'),
          file([0xFF, 0xD8, 1], 'b.jpg'),
        ],
      );
      final picked = await pickPictures(limit: 9, picker: picker);
      expect(picker.calls.single, (limit: 9, imageQuality: 90, maxWidth: null, maxHeight: null, fullMetadata: false));
      expect(picked.map((picture) => picture.name), ['image_picker_1.png', 'b.jpg']);
      expect(picked[0].bytes, pngBytes);
      expect(picked[1].bytes, [0xFF, 0xD8, 1]);
    });

    test('keeps at most the limit, and asks nothing once there is no room', () async {
      final picker = FakePicker(
        () async => [
          for (var index = 0; index < 4; index++) file([index], 'p$index.jpg'),
        ],
      );
      final picked = await pickPictures(limit: 2, picker: picker);
      expect(picked.map((picture) => picture.name), ['p0.jpg', 'p1.jpg']);

      expect(await pickPictures(limit: 0, picker: picker), isEmpty);
      expect(picker.calls.length, 1);
    });

    test('a cancel is an empty list', () async {
      expect(await pickPictures(limit: 9, picker: FakePicker(() async => [])), isEmpty);
      expect(sink.events, isEmpty);
    });

    test('a failure is logged and comes back empty', () async {
      final picker = FakePicker(
        () async => throw PlatformException(code: 'invalid_image', message: 'Could not decode'),
      );
      expect(await pickPictures(limit: 9, picker: picker), isEmpty);
      final event = sink.events.single;
      expect(event.level, LogLevel.warn);
      expect(event.cat, LogCategory.ui);
      expect(event.msg, 'pick pictures failed');
      expect(event.encode(), contains('invalid_image'));
    });

    test('a name without an extension gets one from the bytes', () async {
      final gif = ascii.encode('GIF89a......');
      final webp = ascii.encode('RIFF....WEBPVP8 ');
      final picker = FakePicker(
        () async => [
          file(pngBytes, 'a'),
          file(gif, 'b'),
          file(webp, 'c'),
          file([0xFF, 0xD8, 0xFF], 'd'),
          file([1, 2, 3], 'e'),
        ],
      );
      final picked = await pickPictures(limit: 9, picker: picker);
      expect(picked.map((picture) => picture.name), ['a.png', 'b.gif', 'c.webp', 'd.jpg', 'e.jpg']);
    });

    test('a picked photo loses its location', () async {
      final photo = jpeg([exif(tiff(Endian.little))]);
      final picked = await pickPictures(limit: 9, picker: FakePicker(() async => [file(photo, 'p.jpg')]));
      expect(picked.single.bytes, withoutLocation(photo));
      expect(picked.single.bytes, isNot(photo));
    });
  });

  group('withoutLocation', () {
    for (final endian in [Endian.little, Endian.big]) {
      test('empties the GPS block and its values and keeps the rest (${endian == Endian.little ? 'II' : 'MM'})', () {
        final before = jpeg([segment(0xE0, ascii.encode('JFIF\x00\x01\x01')), exif(tiff(endian))]);
        final after = withoutLocation(before);
        expect(after.length, before.length);
        final start = 2 + 11 + 4 + 6;
        expect(
          after.sublist(0, start + 38),
          before.sublist(0, start + 38),
          reason: 'header and IFD0, orientation included',
        );
        expect(after.sublist(start + 38, start + 92), everyElement(0), reason: 'the GPS IFD and its rationals');
        expect(after.sublist(start + 92), before.sublist(start + 92), reason: 'the picture itself');
        expect(before.sublist(start + 38, start + 92).any((byte) => byte != 0), isTrue);
      });
    }

    test('an EXIF block without GPS, or no EXIF at all, comes back unchanged', () {
      final noGps = tiff(Endian.little);
      ByteData.sublistView(noGps).setUint16(8, 1, Endian.little);
      final photo = jpeg([exif(noGps)]);
      expect(withoutLocation(photo), photo);

      final plain = jpeg([segment(0xE0, ascii.encode('JFIF\x00\x01\x01'))]);
      expect(identical(withoutLocation(plain), plain), isTrue);
    });

    test('anything that is not a well-formed JPEG comes back as it came', () {
      expect(identical(withoutLocation(pngBytes), pngBytes), isTrue);
      final short = Uint8List.fromList([0xFF, 0xD8]);
      expect(identical(withoutLocation(short), short), isTrue);

      final overrun = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0x7F, 0xFF, 0x45, 0x78]);
      expect(identical(withoutLocation(overrun), overrun), isTrue);

      final badPointer = tiff(Endian.little);
      ByteData.sublistView(badPointer).setUint32(30, 5000, Endian.little);
      final photo = jpeg([exif(badPointer)]);
      expect(identical(withoutLocation(photo), photo), isTrue);

      final badRational = tiff(Endian.little);
      ByteData.sublistView(badRational).setUint32(60, 90, Endian.little);
      final second = jpeg([exif(badRational)]);
      expect(identical(withoutLocation(second), second), isTrue);
    });

    test('XMP that mentions GPS is dropped; other XMP stays', () {
      final keep = xmp('<x:xmpmeta><xmp:CreatorTool>Photos</xmp:CreatorTool></x:xmpmeta>');
      final drop = xmp('<x:xmpmeta><exif:GPSLatitude>31,12.5N</exif:GPSLatitude></x:xmpmeta>');
      final photo = jpeg([keep, drop]);
      expect(withoutLocation(photo), jpeg([keep]));
    });

    test('both at once: GPS emptied and the XMP dropped', () {
      final drop = xmp('<exif:GPSLongitude>121,28.1E</exif:GPSLongitude>');
      final photo = jpeg([exif(tiff(Endian.big)), drop]);
      final expected = jpeg([exif(tiff(Endian.big))]);
      final start = 2 + 4 + 6;
      for (var index = start + 38; index < start + 92; index++) {
        expected[index] = 0;
      }
      expect(withoutLocation(photo), expected);
    });
  });

  group('AttachedPictures', () {
    Future<List<int>> mount(WidgetTester tester, List<PickedPicture> pictures) async {
      final removed = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [AttachedPictures(pictures: pictures, onRemove: removed.add)],
              ),
            ),
          ),
        ),
      );
      return removed;
    }

    List<PickedPicture> pictures(int count) => [
      for (var index = 0; index < count; index++) PickedPicture(bytes: pngBytes, name: 'p$index.png'),
    ];

    testWidgets('nothing picked takes no room', (tester) async {
      await mount(tester, const []);
      expect(find.byKey(const ValueKey('attached-pictures')), findsNothing);
      expect(tester.getSize(find.byType(AttachedPictures)), const Size(0, 0));
    });

    testWidgets('a rounded thumbnail per picture, 72 square, under the field with the gutter', (tester) async {
      await mount(tester, pictures(3));
      expect(find.byType(Image), findsNWidgets(3));
      expect(tester.getSize(find.byType(AttachedPictures)).height, 80);
      final first = tester.getRect(find.byType(Image).first);
      expect(first.size, const Size(72, 72));
      expect(first.left, 12);
      expect(tester.getRect(find.byType(Image).at(1)).left, 12 + 72 + 8);
      final image = tester.widget<Image>(find.byType(Image).first);
      expect(image.fit, BoxFit.cover);
    });

    testWidgets('each ✕ takes out its own picture, by tap and by accessibility', (tester) async {
      final semantics = tester.ensureSemantics();
      final removed = await mount(tester, pictures(3));
      await tester.tap(find.byKey(const ValueKey('remove-picture-2')));
      expect(removed, [1]);

      expect(find.bySemanticsLabel('删除图片 1'), findsOneWidget);
      expect(find.bySemanticsLabel('删除图片 3'), findsOneWidget);
      tester.semantics.tap(find.semantics.byLabel('删除图片 3'));
      expect(removed, [1, 2]);
      semantics.dispose();
    });

    testWidgets('the ✕ sits in the top right corner of its thumbnail', (tester) async {
      await mount(tester, pictures(1));
      final thumb = tester.getRect(find.byType(Image));
      final remove = tester.getRect(find.byKey(const ValueKey('remove-picture-1')));
      expect(remove.topRight, thumb.topRight);
      expect(remove.width, 28);
    });
  });
}
