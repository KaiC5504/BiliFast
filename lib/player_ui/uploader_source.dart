import 'package:bili_core/api.dart' show UploaderCard, VideoOwner;

/// The uploader from whichever source has each part: the detail's owner, then the page's card, then for the name the
/// view's. A card can come back with an empty name or face, which counts as missing.
VideoOwner? uploaderOf(VideoOwner? fromDetail, UploaderCard? card, String? viewName) {
  if (fromDetail == null && card == null) return null;
  String filled(List<String?> each) => each.nonNulls.firstWhere((text) => text.isNotEmpty, orElse: () => '');
  return VideoOwner(
    mid: fromDetail == null || fromDetail.mid == 0 ? card?.mid ?? 0 : fromDetail.mid,
    name: filled([fromDetail?.name, card?.name, viewName]),
    face: filled([fromDetail?.face, card?.face]),
  );
}
