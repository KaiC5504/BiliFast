import 'package:bili_core/api.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/space/own/own_space_header.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/stored_pictures.dart';

const _label = 'https://i0.hdslb.com/bfs/vip/label.png';

const _profile = SpaceProfile(
  mid: 1,
  name: '测试账号',
  face: '',
  level: 5,
  vip: true,
  vipLabel: _label,
  fans: 0,
  following: 13,
  likes: 0,
  tagLines: [],
  tabs: [SpaceTab(kind: SpaceTabKind.contribute, title: '投稿')],
  defaultTab: SpaceTabKind.contribute,
  own: OwnSpace(exp: 14805, nextExp: 28800, vipBadge: true),
);

void main() {
  testWidgets('the 大会员 label comes from the pictures kept on the phone, moving as before', (tester) async {
    final pictures = await StoredPictures.keep(tester);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 440,
            child: OwnSpaceHeader(profile: _profile, onSoon: () {}),
          ),
        ),
      ),
    );
    await StoredPictures.arrive(tester);
    final label = tester.widget<Image>(find.byKey(const ValueKey('own-space-vip-label')));
    expect(label.image, isA<StoredNetworkImage>().having((image) => image.still, 'still', isFalse));
    expect(pictures.downloads, contains(_label));
    await pictures.drop(tester);
  });
}
