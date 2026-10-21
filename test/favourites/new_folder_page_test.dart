import 'dart:async';
import 'dart:convert';

import 'package:bili_core/api.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/comments/composer_model.dart';
import 'package:bilifast/comments/picture_attach.dart';
import 'package:bilifast/favourites/new_folder_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'favourites_support.dart';

/// A 1×1 PNG, so the thumbnail decodes.
final _png = base64.decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _Picker extends Fake implements ImagePicker {
  _Picker(this.answer);

  final Future<XFile?> Function() answer;
  final sources = <ImageSource>[];
  final fullMetadata = <bool>[];

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) {
    sources.add(source);
    fullMetadata.add(requestFullMetadata);
    return answer();
  }
}

void main() {
  late List<String> calls;
  late List<String> uploads;
  late Object? result;
  late bool returned;
  late Completer<void>? uploadHold;
  late Object? uploadFailure;
  late Object? createFailure;
  late List<ImageSource> picks;
  late CoverPick pickAnswer;

  setUp(() {
    calls = [];
    uploads = [];
    result = null;
    returned = false;
    uploadHold = null;
    uploadFailure = null;
    createFailure = null;
    picks = [];
    pickAnswer = (picture: PickedPicture(bytes: Uint8List.fromList(_png), name: 'image_picker_1.png'), failure: null);
  });

  Future<FavFolder> create({
    required String title,
    required String intro,
    required bool isPrivate,
    String cover = '',
  }) async {
    calls.add('create title=$title intro=$intro private=$isPrivate cover=$cover');
    if (createFailure case final failure?) throw failure;
    return FavFolder(id: 77, title: title, count: 0, isPrivate: isPrivate, contains: false, isDefault: false);
  }

  Future<String> upload({required List<int> bytes, required String filename}) async {
    uploads.add('$filename ${bytes.length}');
    if (uploadHold case final hold?) await hold.future;
    if (uploadFailure case final failure?) throw failure;
    return 'https://i0.hdslb.com/bfs/medialist/cover/test.png';
  }

  Future<CoverPick> pick(ImageSource source) async {
    picks.add(source);
    return pickAnswer;
  }

  Future<void> show(WidgetTester tester, {bool withUpload = true, bool viaOpen = false}) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => GestureDetector(
            key: const ValueKey('launch'),
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              result = viaOpen
                  ? await openNewFolder(context, create: create, uploadCover: withUpload ? upload : null)
                  : await Navigator.of(context).push<FavFolder>(
                      SwipeBackPageRoute(
                        builder: (_) =>
                            NewFolderPage(create: create, uploadCover: withUpload ? upload : null, pickCover: pick),
                      ),
                    );
              returned = true;
            },
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('launch')));
    await settle(tester, 20);
    expect(find.byType(NewFolderPage), findsOneWidget);
  }

  Future<void> name(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('fav-new-title')), text);
    await tester.pump();
  }

  Future<void> done(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('fav-new-done')));
    await settle(tester, 20);
  }

  Future<void> chooseAlbum(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('fav-new-cover')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('fav-new-cover-album')));
    await settle(tester);
  }

  Matcher doneEnabled(bool on) => isSemantics(label: '完成', isButton: true, isEnabled: on);

  testWidgets('100: 封面, *名称, 简介 and 公开 (on), and 完成 inactive while the name is empty', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester);
    expect(find.text('创建'), findsOneWidget);
    expect(find.text('封面'), findsOneWidget);
    expect(find.text('名称'), findsWidgets);
    expect(find.text('可填写简介'), findsOneWidget);
    expect(find.text('公开'), findsOneWidget);
    expect(tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value, isTrue);
    expect(tester.getSemantics(find.byKey(const ValueKey('fav-new-done'))), doneEnabled(false));
    await done(tester);
    expect(calls, isEmpty);
    await name(tester, '   ');
    await done(tester);
    expect(calls, isEmpty, reason: 'spaces are no name');
    await name(tester, '新的收藏夹');
    expect(tester.getSemantics(find.byKey(const ValueKey('fav-new-done'))), doneEnabled(true));
    semantics.dispose();
  });

  testWidgets('完成 creates the folder with its 简介 and privacy, and pops with it', (tester) async {
    await show(tester, viaOpen: true);
    await name(tester, ' 新的收藏夹 ');
    await tester.enterText(find.byKey(const ValueKey('fav-new-intro')), '一些简介');
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pump();
    await done(tester);
    expect(calls, ['create title=新的收藏夹 intro=一些简介 private=true cover=']);
    expect(returned, isTrue);
    expect((result! as FavFolder).id, 77);
    expect(find.byType(NewFolderPage), findsNothing);
  });

  testWidgets('a refused 完成 stays with the words why, and can be pressed again', (tester) async {
    await show(tester);
    createFailure = const BiliError.api(code: 11010, message: '收藏夹名称重复');
    await name(tester, '重复的');
    await tester.tap(find.byKey(const ValueKey('fav-new-done')));
    await tester.pump();
    await tester.pump();
    expect(find.text('B 站返回错误 11010：收藏夹名称重复'), findsOneWidget);
    await settle(tester);
    expect(find.byType(NewFolderPage), findsOneWidget);
    expect(returned, isFalse);
    createFailure = null;
    await settle(tester, 60);
    await done(tester);
    expect(calls, hasLength(2));
    expect(returned, isTrue);
  });

  testWidgets('back leaves without making anything', (tester) async {
    await show(tester);
    await name(tester, '不要了');
    await tester.tap(find.byKey(const ValueKey('fav-new-back')));
    await settle(tester, 20);
    expect(returned, isTrue);
    expect(result, isNull);
    expect(calls, isEmpty);
  });

  group('封面 (101)', () {
    testWidgets('opens the sheet; 取消, the dim and back close it without picking', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('fav-new-cover')));
      await settle(tester);
      expect(find.byKey(const ValueKey('fav-new-cover-sheet')), findsOneWidget);
      expect(find.text('从相册选择'), findsOneWidget);
      expect(find.text('拍照'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fav-new-cover-cancel')));
      await settle(tester);
      expect(find.byKey(const ValueKey('fav-new-cover-sheet')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('fav-new-cover')));
      await settle(tester);
      await tester.tapAt(const Offset(220, 300));
      await settle(tester);
      expect(find.byKey(const ValueKey('fav-new-cover-sheet')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('fav-new-cover')));
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byKey(const ValueKey('fav-new-cover-sheet')), findsNothing);
      expect(find.byType(NewFolderPage), findsOneWidget, reason: 'back closed the sheet, not the page');
      expect(picks, isEmpty);
    });

    testWidgets('a picked picture uploads at once, shows beside the ›, and goes with 完成', (tester) async {
      await show(tester);
      await chooseAlbum(tester);
      expect(picks, [ImageSource.gallery]);
      expect(uploads, ['image_picker_1.png ${_png.length}']);
      expect(find.byKey(const ValueKey('fav-new-cover-thumb')), findsOneWidget);
      await name(tester, '有封面');
      await done(tester);
      expect(calls, ['create title=有封面 intro= private=false cover=https://i0.hdslb.com/bfs/medialist/cover/test.png']);
    });

    testWidgets('完成 waits for an upload still going', (tester) async {
      await show(tester);
      final hold = uploadHold = Completer<void>();
      await chooseAlbum(tester);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      await name(tester, '等一下');
      await tester.tap(find.byKey(const ValueKey('fav-new-done')));
      await settle(tester);
      expect(calls, isEmpty);
      hold.complete();
      await settle(tester, 20);
      expect(calls, ['create title=等一下 intro= private=false cover=https://i0.hdslb.com/bfs/medialist/cover/test.png']);
      expect(returned, isTrue);
    });

    testWidgets('a failed upload says so and leaves 封面 empty; 完成 then makes the folder without one', (tester) async {
      await show(tester);
      uploadFailure = const BiliError.http(500);
      await chooseAlbum(tester);
      expect(find.text('网络请求失败（HTTP 500）'), findsOneWidget);
      expect(find.byKey(const ValueKey('fav-new-cover-thumb')), findsNothing);
      await settle(tester, 60);
      await name(tester, '没封面');
      await done(tester);
      expect(calls, ['create title=没封面 intro= private=false cover=']);
    });

    testWidgets('an upload failing while 完成 waits stops 完成, so the folder is not made without its cover', (
      tester,
    ) async {
      await show(tester);
      final hold = uploadHold = Completer<void>();
      uploadFailure = const BiliError.http(500);
      await chooseAlbum(tester);
      await name(tester, '等一下');
      await tester.tap(find.byKey(const ValueKey('fav-new-done')));
      await tester.pump();
      hold.complete();
      await settle(tester);
      expect(calls, isEmpty);
      expect(find.byType(NewFolderPage), findsOneWidget);
      await settle(tester, 60);
    });

    testWidgets('a cancelled pick changes nothing; a refused library says how to allow it', (tester) async {
      await show(tester);
      pickAnswer = (picture: null, failure: null);
      await chooseAlbum(tester);
      expect(uploads, isEmpty);
      expect(find.byKey(const ValueKey('fav-new-cover-thumb')), findsNothing);
      pickAnswer = (picture: null, failure: PickFailure.noAccess);
      await chooseAlbum(tester);
      expect(find.text('无法访问照片，请在设置中允许BiliFast访问照片'), findsOneWidget);
      expect(uploads, isEmpty);
      await settle(tester, 60);
    });

    testWidgets('拍照 takes a photo on the phone; on Windows it is 暂未开放', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('fav-new-cover')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('fav-new-cover-camera')));
      await settle(tester);
      expect(picks, [ImageSource.camera]);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await tester.tap(find.byKey(const ValueKey('fav-new-cover')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('fav-new-cover-camera')));
        await tester.pump();
        expect(find.text('暂未开放'), findsOneWidget);
        expect(picks, hasLength(1));
        await settle(tester, 60);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('without an upload, 封面 says 暂未开放', (tester) async {
      await show(tester, withUpload: false);
      await tester.tap(find.byKey(const ValueKey('fav-new-cover')));
      await tester.pump();
      expect(find.text('暂未开放'), findsOneWidget);
      expect(find.byKey(const ValueKey('fav-new-cover-sheet')), findsNothing);
      await settle(tester, 60);
    });
  });

  group('pickFolderCover', () {
    test('asks for one picture without its metadata; a cancel is nothing', () async {
      final picker = _Picker(() async => null);
      final picked = await pickFolderCover(ImageSource.gallery, picker: picker);
      expect(picked.picture, isNull);
      expect(picked.failure, isNull);
      expect(picker.sources, [ImageSource.gallery]);
      expect(picker.fullMetadata, [false]);
    });

    test('a picture comes back with its name, or cover.jpg without an extension', () async {
      final named = await pickFolderCover(
        ImageSource.camera,
        picker: _Picker(() async => XFile.fromData(Uint8List.fromList(_png), path: 'shot.png')),
      );
      expect(named.picture!.name, 'shot.png');
      expect(named.picture!.bytes, _png);
      final bare = await pickFolderCover(
        ImageSource.gallery,
        picker: _Picker(() async => XFile.fromData(Uint8List.fromList([0xFF, 0xD8, 1]), path: 'picture')),
      );
      expect(bare.picture!.name, 'cover.jpg');
    });

    test('a shut library or camera reads as no access; anything else as failed', () async {
      for (final code in ['photo_access_denied', 'camera_access_denied']) {
        final denied = await pickFolderCover(
          ImageSource.gallery,
          picker: _Picker(() async => throw PlatformException(code: code)),
        );
        expect(denied.failure, PickFailure.noAccess, reason: code);
      }
      final failed = await pickFolderCover(ImageSource.gallery, picker: _Picker(() async => throw StateError('no')));
      expect(failed.failure, PickFailure.failed);
    });
  });
}
