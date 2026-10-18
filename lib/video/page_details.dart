import 'package:bili_core/api.dart' show UploaderCard, VideoCard, VideoTag;
import 'package:flutter/foundation.dart';

import 'actions/video_actions.dart';
import 'player_session.dart' show ActionResult;

enum PageTab { intro, comments }

/// What the page body shows besides the session's video: the uploader's card, the tags, N人正在看 and the actions.
/// One per page; it follows whatever video the page plays.
abstract interface class PageDetails implements Listenable {
  /// Null until the video's detail arrives; a new one for each video the page opens.
  VideoActions? get actions;

  UploaderCard? get uploader;

  /// The part's tags (topic, BGM and plain); empty until they arrive.
  List<VideoTag> get tags;

  /// N人正在看's N as the server words it ("53", "1000+"); null until known. Asked every 30 s while active.
  ValueListenable<String?> get online;

  /// 稍后再看 from a related row's ⋮; completes with the toast text, empty when it asked for a login instead.
  Future<ActionResult> watchLater(VideoCard card);

  /// False while the page is covered or has left: no polls, no fetches.
  set active(bool value);

  void dispose();
}
