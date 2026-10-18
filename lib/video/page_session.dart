import '../app/app_scope.dart';
import '../playback/playback_controller.dart';
import 'player_session.dart';

/// Plays another part or video on the same page: the page opens it, so its own bookkeeping (watch reports, which open
/// is its) stays right.
typedef SessionOpen = void Function(String bvid, {int? cid});

/// The video page's [PlayerSession] over the shared controller, one per page.
PlayerSession createPageSession({
  required PlaybackController controller,
  required AppServices services,
  required SessionOpen open,
}) => throw UnimplementedError('PagePlayerSession');
