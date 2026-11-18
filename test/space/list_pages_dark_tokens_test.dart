import 'package:bilifast/shared/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The list pages' night colours as measured on 245, 246, 253 and 258, and what stays the same by night.
void main() {
  tearDown(() => BiliTheme.dark = false);

  test('white action sheets take 246\'s grey, its gap band and its 取消', () {
    BiliTheme.dark = true;
    for (final fill in [
      HistoryTheme.sheetFill,
      FavouritesTheme.sheetFill,
      SpaceTheme.sheetFill,
      FriendsTheme.sheetFill,
      OfflinePageTheme.sheetFill,
    ]) {
      expect(fill, const Color(0xFF1E2022));
    }
    expect(HistoryTheme.sheetBandFill, const Color(0xFF0A0B0C));
    expect(HistoryTheme.sheetCancelInk, const Color(0xFFB9BDC2));
    expect(FriendsTheme.actionRuleInk, const Color(0xFF2F3134));
  });

  test('grey sheets with white groups take 245\'s and 258\'s', () {
    BiliTheme.dark = true;
    for (final fill in [SearchResultTheme.sheetFill, WatchLaterTheme.sheetFill, OfflineListTheme.sheet]) {
      expect(fill, const Color(0xFF202123));
    }
    for (final card in [SearchResultTheme.sheetCardFill, WatchLaterTheme.groupFill, OfflineListTheme.card]) {
      expect(card, const Color(0xFF242628));
    }
  });

  test('fields and chips take 253\'s grey; ink over pictures, pink and the skins stays white', () {
    BiliTheme.dark = true;
    for (final fill in [SearchTheme.chipFill, FriendsTheme.field, FollowingListTheme.field, OfflineListTheme.field]) {
      expect(fill, const Color(0xFF1E2022));
    }
    for (final white in [
      SpaceTheme.buttonInk,
      SpaceTheme.followInk,
      SpaceTheme.officialBolt,
      OwnSpaceTheme.labelInk,
      OwnSpaceTheme.barLightInk,
      FollowingListTheme.barLightInk,
      OfflineListTheme.barLightInk,
      SearchResultTheme.badgeBolt,
    ]) {
      expect(white, const Color(0xFFFFFFFF));
    }
    expect(FollowingListTheme.badgePerson, const Color(0xFFFFCC00));
  });

  test('by day every one keeps its light colour', () {
    expect(HistoryTheme.sheetFill, const Color(0xFFFFFFFF));
    expect(HistoryTheme.sheetBandFill, const Color(0xFFF4F4F4));
    expect(SearchResultTheme.sheetFill, const Color(0xFFF6F7F8));
    expect(SearchTheme.chipFill, const Color(0xFFF6F7F8));
    expect(SearchResultTheme.headerFill, const Color(0xFFFFFFFF));
    expect(FriendsTheme.field, const Color(0xFFF4F4F4));
    expect(FollowingListTheme.badgeOrganisation, const Color(0xFF3EA2F4));
  });
}
