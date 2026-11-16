import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/message/chat/chat_page.dart';
import 'package:bilifast/message/fake_message_api.dart';
import 'package:bilifast/message/message_model.dart';
import 'package:bilifast/message/message_routes.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../home/fake_login_gate.dart';
import '../../playback/fakes.dart';
import '../../video/mixed_lines.dart' show appTheme;

/// The account the tests are logged in as (Canned's), a 大会员 with the 大 on its face.
const selfMid = 12345;

const _nav = r'''
{"code":0,"message":"0","ttl":1,"data":{"isLogin":true,"mid":12345,"uname":"测试用户","face":"","vipStatus":1,"vipType":2,"vip_avatar_subscript":1,"wbi_img":{"img_url":"https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png","sub_url":"https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png"}}}''';

/// 消息's model, recording the chats opened (the ack) and doing nothing else.
class RecordingMessages extends MessageModel {
  RecordingMessages({required super.api, required super.environment});

  final opened = <ChatSession>[];

  @override
  Future<void> chatOpened(ChatSession session) async => opened.add(session);
}

final class ChatHarness {
  ChatHarness(this.services, this.api, this.messages, this.loginGate, this.pageApi);

  final AppServices services;
  final FakeMessageApi api;
  final RecordingMessages messages;
  final FakeLoginGate loginGate;
  final FakePageApi pageApi;

  final webOpened = <Uri>[];
  final videosOpened = <String>[];
  bool webAnswer = true;
}

Future<ChatHarness> chatHarness(FakeMessageApi api, {bool loggedIn = true}) async {
  final logger = Logger(session: 'test');
  final http = Canned.http(loggedIn: loggedIn);
  if (loggedIn) http.routes[Canned.navPath] = (200, _nav);
  final environment = await AppEnvironment.load(
    keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
    http: http,
    logger: logger,
  );
  await environment.refreshAccount();
  final playback = AppPlayback(() async => throw UnimplementedError());
  addTearDown(playback.dispose);
  final loginGate = FakeLoginGate();
  final messages = RecordingMessages(api: api, environment: environment);
  addTearDown(messages.dispose);
  final pageApi = FakePageApi()
    ..emotes = [
      EmotePackage(
        id: 1,
        name: '小黄脸',
        icon: '',
        isText: false,
        emotes: [
          for (final name in ['微笑', '大笑', '演示']) Emote(token: '[$name]', url: '', large: false),
        ],
      ),
    ];
  final services = AppServices(
    environment: environment,
    playback: playback,
    recents: await RecentStore.load(null, logger: logger),
    loginGate: loginGate,
    spaceApi: FakeSpaceApi.demo(),
    pageApi: pageApi,
    messageApi: api,
    messages: messages,
  );
  return ChatHarness(services, api, messages, loginGate, pageApi);
}

/// A page with one button that opens [session] as 消息 does, with links recorded instead of opened.
class ChatLauncher extends StatelessWidget {
  const ChatLauncher({super.key, required this.harness, required this.session});

  final ChatHarness harness;
  final ChatSession session;

  @override
  Widget build(BuildContext context) => Center(
    child: GestureDetector(
      key: const ValueKey('open-chat'),
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatPage(
            session: session,
            openWeb: (uri) async {
              harness.webOpened.add(uri);
              return harness.webAnswer;
            },
            openVideo: (context, link) async => harness.videosOpened.add(link),
          ),
        ),
      ),
      child: const SizedBox.square(dimension: 80),
    ),
  );
}

/// The app over the harness with [home] first; the RepaintBoundary keyed `shot` holds the screen.
Future<void> pumpChatApp(WidgetTester tester, ChatHarness harness, Widget home, {bool sized = true}) async {
  if (sized) {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      builder: (context, child) => RepaintBoundary(
        key: const ValueKey('shot'),
        child: AppScope(services: harness.services, child: child!),
      ),
      home: home,
    ),
  );
}

/// Opens [session]'s chat over [api]; returns the harness.
Future<ChatHarness> openChat(
  WidgetTester tester,
  FakeMessageApi api,
  ChatSession session, {
  bool loggedIn = true,
}) async {
  final harness = await chatHarness(api, loggedIn: loggedIn);
  await pumpChatApp(tester, harness, ChatLauncher(harness: harness, session: session));
  await tester.tap(find.byKey(const ValueKey('open-chat')));
  await settle(tester);
  return harness;
}

/// Opens [session] through the app's own route, as 消息's rows do.
Future<ChatHarness> openChatByRoute(WidgetTester tester, FakeMessageApi api, ChatSession session) async {
  final harness = await chatHarness(api);
  await pumpChatApp(
    tester,
    harness,
    Builder(
      builder: (context) => Center(
        child: GestureDetector(
          key: const ValueKey('open-chat'),
          behavior: HitTestBehavior.opaque,
          onTap: () => openMessageChat(context, session),
          child: const SizedBox.square(dimension: 80),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-chat')));
  await settle(tester);
  return harness;
}

/// Lets the route come in and the fake's answers land.
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets a toast run out, so no timer is left when the test ends.
Future<void> toastGone(WidgetTester tester) async {
  for (final wait in const [Duration(milliseconds: 500), Duration(seconds: 3), Duration(seconds: 1)]) {
    await tester.pump(wait);
  }
}

Finder byKey(String key) => find.byKey(ValueKey(key));

TextEditingController chatField(WidgetTester tester) => tester.widget<TextField>(byKey('chat-field')).controller!;

/// Return as the phone's keyboard types it with its plain ⏎: a line break at the caret, then the newline action.
Future<void> pressReturn(WidgetTester tester) async {
  final value = chatField(tester).value;
  final selection = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: value.text.replaceRange(selection.start, selection.end, '\n'),
      selection: TextSelection.collapsed(offset: selection.start + 1),
    ),
  );
  await tester.testTextInput.receiveAction(TextInputAction.newline);
  await tester.pump();
}

final demoTime = DateTime(2026, 11, 12, 15, 34);

/// A person (made up), not followed unless [settings] say so.
ChatSession person({int talkerId = 777, String name = '演示好友', int maxSeqno = 0}) =>
    ChatSession(talkerId: talkerId, name: name, face: '', lastText: '', time: demoTime, maxSeqno: maxSeqno);

ChatSession boxSession(NoticeBox box, {int talkerId = 844424930131966}) =>
    ChatSession(talkerId: talkerId, name: box.label, face: '', lastText: '', time: demoTime, box: box);

ChatMessage text(
  int seqno,
  String body, {
  int sender = 777,
  DateTime? at,
  Map<String, String> emotes = const {},
  bool autoReply = false,
}) => ChatMessage(
  seqno: seqno,
  senderMid: sender,
  kind: ChatMessageKind.text,
  text: body,
  time: at ?? demoTime,
  emotes: emotes,
  autoReply: autoReply,
);

ChatMessage tip(int seqno, String body, {DateTime? at}) =>
    ChatMessage(seqno: seqno, senderMid: 0, kind: ChatMessageKind.tip, text: body, time: at ?? demoTime);

ChatMessage notice(
  int seqno, {
  required String title,
  required String body,
  List<({String title, String detail})> fields = const [],
  List<({String text, String uri})> links = const [],
  DateTime? at,
  int sender = 844424930131966,
}) => ChatMessage(
  seqno: seqno,
  senderMid: sender,
  kind: ChatMessageKind.notice,
  title: title,
  text: body,
  fields: fields,
  links: links,
  time: at ?? demoTime,
);
