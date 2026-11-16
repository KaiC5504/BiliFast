import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/message/fake_message_api.dart';
import 'package:bilifast/message/message_model.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/skin/fake_skin_api.dart';
import 'package:bilifast/skin/skin.dart';
import 'package:bilifast/skin/skin_model.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../settings/settings_fakes.dart' show FakeEnvironment;
import '../../video/mixed_lines.dart' show appTheme;

/// 消息提醒 kept in memory: [on] as the switch reads it, each [setBadgeOn] recorded in [saves]; a [saveGate] holds the
/// save until the test completes it, and a [saveError] is thrown instead of saving.
class BadgeModel extends MessageModel {
  BadgeModel({required super.api, required super.environment, this.on = true});

  bool on;
  final saves = <bool>[];
  Completer<void>? saveGate;
  Object? saveError;

  @override
  bool get badgeOn => on;

  @override
  Future<void> setBadgeOn(bool value) async {
    saves.add(value);
    await saveGate?.future;
    if (saveError case final error?) throw error;
    on = value;
    notifyListeners();
  }
}

/// The equipped skin the test sets, never asking the account.
class FixedSkins extends SkinModel {
  FixedSkins(this._skin, {required super.environment}) : super(api: FakeSkinApi(), folder: null);

  final Skin? _skin;

  @override
  Skin? get value => _skin;
}

/// 188's skin: KaiC's green second-page colour, black text.
final greenSkin = Skin(
  equip: const SkinEquip(
    id: 1,
    name: '测试装扮',
    ver: 1,
    packageUrl: '',
    packageMd5: '',
    colors: SkinColors(color: 0xFF000000, colorSecondPage: 0xFFD9E8D3, lightText: true),
  ),
);

/// 消息设置's world: a logged-in account, 消息's calls answered by [api], 消息提醒 by [messages], the [skin] worn.
class MessageSettingsWorld {
  MessageSettingsWorld._(this.services, this.api, this.messages);

  static Future<MessageSettingsWorld> create({FakeMessageApi? api, bool badgeOn = true, Skin? skin}) async {
    final environment = FakeEnvironment(const LoggedIn(name: '测试账号', vip: false));
    final messageApi = api ?? FakeMessageApi();
    final messages = BadgeModel(api: messageApi, environment: environment, on: badgeOn);
    final skins = FixedSkins(skin, environment: environment);
    final services = AppServices(
      environment: environment,
      playback: AppPlayback(() => Completer<PlaybackController>().future),
      recents: await RecentStore.load(null),
      pageApi: FakePageApi(),
      messageApi: messageApi,
      messages: messages,
      skin: skins,
    );
    addTearDown(() {
      services.playback.dispose();
      messages.dispose();
      skins.dispose();
    });
    return MessageSettingsWorld._(services, messageApi, messages);
  }

  final AppServices services;
  final FakeMessageApi api;
  final BadgeModel messages;

  /// The app over these services with [home] first; the RepaintBoundary keyed `shot` holds the screen.
  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        debugShowCheckedModeBanner: false,
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('shot'),
          child: AppScope(services: services, child: child!),
        ),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }
}

/// The phone's size, without its safe areas.
void phone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(440, 956) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Finder byKey(String key) => find.byKey(ValueKey(key));

int callCount(FakeMessageApi api, String prefix) => api.calls.where((call) => call.startsWith(prefix)).length;

/// Lets a toast run out, so no timer is left when the test ends.
Future<void> runOutToast(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}
