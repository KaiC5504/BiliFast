import 'package:bilifast/offline/fake_offline_library.dart';
import 'package:bilifast/offline/offline_library.dart';
import 'package:flutter_test/flutter_test.dart';

import 'disk_test_support.dart';

/// What 开发者's 状态 reads of how downloads went on away: the disk library's trials, and none from a library that
/// never downloads away.
void main() {
  test('the disk library answers its own trials', () {
    final rig = Rig();
    addTearDown(rig.dispose);
    final OfflineLibrary library = rig.make();
    expect(library.trials, isA<PinnedTrials>());
    expect(library.trials, same((library as DiskOfflineLibrary).trials));
  });

  test('a library held in memory has none', () {
    final OfflineLibrary library = FakeOfflineLibrary.demo();
    expect(library.trials, isNull);
  });
}
