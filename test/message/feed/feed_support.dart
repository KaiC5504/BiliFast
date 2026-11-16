import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/message/fake_message_api.dart';
import 'package:bilifast/message/feed/feed_targets.dart';
import 'package:bilifast/message/message_model.dart';
import 'package:bilifast/space/uploader_tap.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../home/fake_login_gate.dart';
import '../../playback/fakes.dart';
import '../../video/mixed_lines.dart' show appTheme;

/// Records what the pages tell 消息's model.
class RecordingMessages extends MessageModel {
  RecordingMessages({required super.api, required super.environment});

  final opened = <NoticeFeed>[];
  int shows = 0;

  @override
  void feedOpened(NoticeFeed feed) => opened.add(feed);

  @override
  void requestShow() {
    shows += 1;
    super.requestShow();
  }
}

/// What a row opened, in place of the pages (a video page needs a player).
class RecordingOpeners extends FeedOpeners {
  final videos = <VideoRoute>[];
  final posts = <(String, bool)>[];
  final spaces = <UploaderRef>[];

  @override
  Future<void> openVideo(BuildContext context, VideoRoute route) async => videos.add(route);

  @override
  Future<void> openPost(BuildContext context, {required String id, required bool toComments}) async =>
      posts.add((id, toComments));

  @override
  Future<void> openSpace(BuildContext context, UploaderRef uploader) async => spaces.add(uploader);
}

/// What the comment calls were sent, the area included.
class RecordingPageApi extends FakePageApi {
  final areas = <({String call, int aid, int type})>[];

  @override
  Future<Comment> postComment({
    required int aid,
    required String message,
    int root = 0,
    int parent = 0,
    bool syncToDynamic = false,
    Map<String, int> mentions = const {},
    List<UploadedPicture> pictures = const [],
    int type = 1,
  }) {
    areas.add((call: 'post', aid: aid, type: type));
    return super.postComment(
      aid: aid,
      message: message,
      root: root,
      parent: parent,
      syncToDynamic: syncToDynamic,
      mentions: mentions,
      pictures: pictures,
      type: type,
    );
  }

  @override
  Future<void> likeComment({required int aid, required int rpid, required bool on, int type = 1}) {
    areas.add((call: 'like', aid: aid, type: type));
    return super.likeComment(aid: aid, rpid: rpid, on: on, type: type);
  }
}

/// The app's services over [api], logged in as Canned's account (mid 12345) or logged out.
Future<AppServices> feedServices(
  FakeMessageApi api, {
  bool loggedIn = true,
  FakePageApi? page,
  LoginGate? loginGate,
}) async {
  final logger = Logger(session: 'test');
  final environment = await AppEnvironment.load(
    keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
    http: Canned.http(loggedIn: loggedIn),
    logger: logger,
  );
  await environment.refreshAccount();
  final playback = AppPlayback(() async => throw UnimplementedError());
  addTearDown(playback.dispose);
  return AppServices(
    environment: environment,
    playback: playback,
    recents: await RecentStore.load(null, logger: logger),
    loginGate: loginGate ?? FakeLoginGate(),
    pageApi: page ?? RecordingPageApi(),
    messageApi: api,
    messages: RecordingMessages(api: api, environment: environment),
  );
}

/// The app over [services] with a page that pushes [page] on a tap, at the phone's size unless [sized] is false.
Future<void> pumpFeed(WidgetTester tester, AppServices services, Widget page, {bool sized = true}) async {
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
        child: AppScope(services: services, child: child!),
      ),
      home: Builder(
        builder: (context) => Center(
          child: GestureDetector(
            key: const ValueKey('open-page'),
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
            child: const SizedBox.square(dimension: 80),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-page')));
  await settle(tester);
}

/// Lets the route come in and the fake's answers land.
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder byKey(String key) => find.byKey(ValueKey(key));

NoticeUser person(int mid, {String? name}) => NoticeUser(mid: mid, name: name ?? '演示用户$mid', face: '');

/// A reply on a video (business 1) unless told otherwise.
ReplyNotice reply(
  int id, {
  NoticeFeed feed = NoticeFeed.reply,
  String business = 'reply',
  int businessId = 1,
  int subjectId = 1000,
  int rootId = 0,
  int sourceId = 0,
  String text = '演示回复',
  String targetText = '我的演示评论',
  String image = '',
  String title = '',
  String uri = '',
  String nativeUri = '',
  bool fromUploader = false,
  bool liked = false,
  NoticeUser? user,
  DateTime? time,
}) => ReplyNotice(
  id: id,
  feed: feed,
  user: user ?? person(id),
  business: business,
  businessId: businessId,
  subjectId: subjectId,
  rootId: rootId,
  sourceId: sourceId == 0 ? id * 10 : sourceId,
  targetId: rootId,
  text: text,
  time: time ?? DateTime(2026, 11, 13, 9),
  targetText: targetText,
  image: image,
  title: title,
  uri: uri,
  nativeUri: nativeUri,
  fromUploader: fromUploader,
  liked: liked,
);

LikeNotice like(
  int id, {
  List<NoticeUser>? users,
  int count = 1,
  String business = '评论',
  String title = '我的演示评论',
  String uri = '',
  String nativeUri = '',
  bool notifying = true,
  DateTime? time,
}) => LikeNotice(
  id: id,
  users: users ?? [person(id)],
  count: count,
  business: business,
  title: title,
  uri: uri,
  nativeUri: nativeUri,
  notifying: notifying,
  time: time ?? DateTime(2026, 4, 2, 9),
);
