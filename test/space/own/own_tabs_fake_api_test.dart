import 'package:bili_core/api.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'own_tabs_support.dart';

void main() {
  test('the demo’s own space is the fake account’s, made up and fetching nothing', () async {
    final api = FakeSpaceApi.demo();
    final profile = await api.ownProfile(1);
    final own = profile.own!;
    expect(profile.mid, 1);
    expect(profile.videoCount, 0);
    expect(profile.tabs.map((tab) => (tab.kind, tab.title)), [
      (SpaceTabKind.home, '主页'),
      (SpaceTabKind.contribute, '投稿'),
      (SpaceTabKind.favourite, '收藏'),
      (SpaceTabKind.bangumi, '追番'),
    ]);
    expect((own.exp, own.nextExp), (14805, 28800));
    expect(own.bannerLabel, isNotNull);
    expect(own.favourites.items, hasLength(2));
    expect(own.favourites.items.where((folder) => folder.isPrivate), hasLength(1));
    expect(own.bangumi.count, 5);
    expect(own.coins.items, hasLength(2));
    expect(own.likes.items, hasLength(2));
    expect((own.garbs.count, own.garbTotal), (2, 7779));
    for (final section in [own.favourites, own.bangumi, own.coins, own.likes, own.garbs]) {
      expect(section.hidden, isTrue);
    }
    final pictures = [
      profile.face,
      ?profile.banner,
      ?own.banner,
      ?own.pendant,
      for (final folder in own.favourites.items) folder.cover,
      for (final bangumi in own.bangumi.items) bangumi.cover,
      for (final video in [...own.coins.items, ...own.likes.items]) video.cover,
      for (final garb in own.garbs.items) garb.image,
    ];
    expect(pictures.where((url) => url.isNotEmpty), isEmpty);
    expect((await api.bangumi(1, page: 1)).items, hasLength(5));
  });

  test('the demo keeps its uploader for every other mid, and the fake account’s own space for its own', () async {
    final api = FakeSpaceApi.demo();
    expect((await api.profile(7)).name, '演示UP主');
    expect((await api.profile(7)).own, isNull);
    expect((await api.ownProfile(1)).own, isNotNull);
  });

  test('the own mid’s plain profile is the own space without its extras, as the real call without the token', () async {
    final api = FakeSpaceApi.demo();
    final plain = await api.profile(1);
    final own = await api.ownProfile(1);
    expect(plain.own, isNull);
    expect((plain.mid, plain.name, plain.level, plain.vip), (own.mid, own.name, own.level, own.vip));
    expect(plain.tabs.map((tab) => tab.kind), own.tabs.map((tab) => tab.kind));
  });

  test('追番 comes a page at a time, from 1', () async {
    final api = FakeSpaceApi(bangumiList: [for (var i = 0; i < 7; i++) ownBangumi(i)], bangumiPageSize: 3);
    final first = await api.bangumi(ownMid, page: 1);
    final last = await api.bangumi(ownMid, page: 3);
    final past = await api.bangumi(ownMid, page: 4);
    expect(first.items.map((card) => card.seasonId), [800, 801, 802]);
    expect((first.hasMore, first.total), (true, 7));
    expect(last.items.map((card) => card.seasonId), [806]);
    expect(last.hasMore, isFalse);
    expect(past.items, isEmpty);
    expect(api.calls, ['bangumi mid=$ownMid page=1', 'bangumi mid=$ownMid page=3', 'bangumi mid=$ownMid page=4']);
  });

  test('without an own space given, the own call answers a plain one', () async {
    final profile = await FakeSpaceApi().ownProfile(ownMid);
    expect(profile.mid, ownMid);
    expect(profile.own, isNotNull);
  });
}
