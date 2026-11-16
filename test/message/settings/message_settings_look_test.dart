import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bilifast/message/fake_message_api.dart';
import 'package:bilifast/message/settings/message_settings_page.dart';
import 'package:bilifast/message/settings/notice_picker_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import 'message_settings_support.dart';

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

/// 消息设置 (188) and its pickers (215, 216, 195) as KaiC's iPhone draws them, under the system font and his skin's
/// bar, measured against the screenshots in px / 3. With BILIFAST_SHOTS naming a folder outside the repo, the 3× shots
/// are saved there for tools/screen_diff.py.
void main() {
  Future<MessageSettingsWorld> shoot(WidgetTester tester, String name, Widget page) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    final world = await MessageSettingsWorld.create(
      api: FakeMessageApi(settings: const {NoticeSettingKind.fans: NoticeAudience.everyone}),
      skin: greenSkin,
    );
    await world.pump(tester, page);
    expect(tester.takeException(), isNull, reason: 'nothing overflows');
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, byKey('shot'), '$shots/$name.png');
    return world;
  }

  void near(Rect actual, Rect expected) {
    for (final (a, b) in [
      (actual.left, expected.left),
      (actual.top, expected.top),
      (actual.right, expected.right),
      (actual.bottom, expected.bottom),
    ]) {
      expect(a, closeTo(b, 0.01), reason: '$actual against $expected');
    }
  }

  testWidgets('188: the bar, the groups and their rows', (tester) async {
    await shoot(tester, '188-message-settings-ours', const MessageSettingsPage());
    near(tester.getRect(byKey('message-settings-bar')), const Rect.fromLTRB(0, 0, 440, 106));
    // Each row's top and bottom, from 188's px.
    const rows = {
      'message-settings-badge': (348, 554),
      'message-settings-intercept': (645, 851),
      'message-settings-block-words': (853, 1059),
      'message-settings-replies': (1150, 1356),
      'message-settings-likes': (1358, 1564),
      'message-settings-fans': (1566, 1772),
      'message-settings-support': (1863, 2016),
      'message-settings-strangers': (2018, 2171),
      'message-settings-blacklist': (2262, 2415),
    };
    for (final MapEntry(:key, value: (top, bottom)) in rows.entries) {
      final rect = tester.getRect(byKey(key));
      expect(rect.top * 3, closeTo(top, 0.01), reason: key);
      expect(rect.bottom * 3, closeTo(bottom, 0.01), reason: key);
    }
    final badge = tester.getRect(byKey('message-settings-switch').first);
    near(badge, const Rect.fromLTRB(376, 135.33, 424, 165.33));
  });

  for (final (kind, name) in [
    (NoticeSettingKind.replies, '215-message-reply-remind-picker-ours'),
    (NoticeSettingKind.likes, '216-message-likes-remind-picker-ours'),
    (NoticeSettingKind.fans, '195-new-fans-remind-picker-ours'),
  ]) {
    testWidgets('${kind.pickerTitle}: its rows and the ✓', (tester) async {
      await shoot(tester, name, NoticePickerPage(kind: kind));
      for (final (index, audience) in kind.choices.indexed) {
        final rect = tester.getRect(byKey('notice-picker-${audience.name}'));
        expect(rect.top * 3, closeTo(348 + index * 155, 0.01), reason: audience.name);
        expect(rect.height * 3, closeTo(153, 0.01), reason: audience.name);
      }
      final check = tester.getRect(byKey('message-settings-check'));
      expect(check.right, closeTo(440 - 53 / 3, 0.01));
      expect(check.center.dy, closeTo(141.5, 0.01));
    });
  }
}
