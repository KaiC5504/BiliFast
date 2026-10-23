import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/skin/fake_skin_api.dart';
import 'package:bilifast/skin/skin_loading.dart';
import 'package:bilifast/skin/skin_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';

/// The stand-in 加载动画 ([DemoSkin.loadingGif], 8 frames of 144 px) decoded as the model keeps it.
Future<SkinLoadingAnimation> standInLoading(WidgetTester tester) async {
  final check = (await tester.runAsync(() => checkSkinLoading(DemoSkin.loadingGif())))!;
  return check.animation(id: 2, ver: 1, name: 'stand-in')!;
}

/// A skin model whose 加载动画 the test sets in [shownLoading]; it asks nothing.
class LoadingSkinModel extends SkinModel {
  LoadingSkinModel({required super.environment}) : super(api: FakeSkinApi(), folder: null);

  final shownLoading = ValueNotifier<SkinLoadingAnimation?>(null);

  @override
  ValueListenable<SkinLoadingAnimation?> get loading => shownLoading;

  @override
  Future<void> refresh() async {}

  @override
  void dispose() {
    shownLoading.dispose();
    super.dispose();
  }
}

/// Services for a widget that reads only the skin from [AppScope]: logged out, no network, [LoadingSkinModel].
Future<(AppServices, LoadingSkinModel)> skinOnlyServices() async {
  final logger = Logger(session: 'test');
  final environment = await AppEnvironment.load(
    keychain: FakeKeychain(const NoStoredCookies()),
    http: CannedHttp(),
    logger: logger,
  );
  final skin = LoadingSkinModel(environment: environment);
  addTearDown(skin.dispose);
  final playback = AppPlayback(() => throw StateError('no playback here'));
  addTearDown(playback.dispose);
  final services = AppServices(
    environment: environment,
    playback: playback,
    recents: await RecentStore.load(null, logger: logger),
    skin: skin,
  );
  return (services, skin);
}
