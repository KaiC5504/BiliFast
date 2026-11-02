import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../dynamic/following/following_page.dart' show followingStyle;
import '../shared/loading_tv.dart';
import '../shared/menu.dart' show PressHighlight;
import '../shared/theme.dart';
import 'friends_api.dart';
import 'friends_glyphs.dart';
import 'friends_rows.dart';
import 'group_sheet_model.dart';

/// An in-page sheet over everything under the bar: [open] holds the person it is up for, and setting it null (取消, a
/// tap on the dim, back) closes it. While it goes down it keeps drawing the last person.
class FriendsSheetLayer extends StatefulWidget {
  const FriendsSheetLayer({super.key, required this.open, required this.name, required this.builder});

  final ValueNotifier<RelationUser?> open;

  /// Names the layer's keys: `friends-<name>-dim` and `friends-<name>`.
  final String name;

  /// The sheet for one opening; a new opening builds it afresh.
  final Widget Function(BuildContext context, RelationUser user, VoidCallback close) builder;

  @override
  State<FriendsSheetLayer> createState() => _FriendsSheetLayerState();
}

class _FriendsSheetLayerState extends State<FriendsSheetLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: FriendsTheme.sheetIn,
    reverseDuration: FriendsTheme.sheetOut,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _motion,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  RelationUser? _user;
  int _openings = 0;

  @override
  void initState() {
    super.initState();
    widget.open.addListener(_changed);
    _motion.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && widget.open.value == null && mounted) setState(() => _user = null);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    _motion
      ..duration = still ? Duration.zero : FriendsTheme.sheetIn
      ..reverseDuration = still ? Duration.zero : FriendsTheme.sheetOut;
  }

  @override
  void didUpdateWidget(FriendsSheetLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.open, widget.open)) {
      oldWidget.open.removeListener(_changed);
      widget.open.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.open.removeListener(_changed);
    _curve.dispose();
    _motion.dispose();
    super.dispose();
  }

  void _changed() {
    final user = widget.open.value;
    if (user == null) {
      if (_user != null) unawaited(_motion.reverse());
      return;
    }
    setState(() {
      _user = user;
      _openings++;
    });
    unawaited(_motion.forward());
  }

  void _close() => widget.open.value = null;

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) return const SizedBox.shrink();
    final open = widget.open.value != null;
    return IgnorePointer(
      ignoring: !open,
      child: ExcludeSemantics(
        excluding: !open,
        child: BlockSemantics(
          blocking: open,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  key: ValueKey('friends-${widget.name}-dim'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _close,
                  child: FadeTransition(
                    opacity: _curve,
                    child: const ColoredBox(color: FriendsTheme.sheetDim),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(_curve),
                  child: ColoredBox(
                    key: ValueKey('friends-${widget.name}'),
                    color: FriendsTheme.sheetFill,
                    child: KeyedSubtree(key: ValueKey(_openings), child: widget.builder(context, user, _close)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 已关注's sheet (166): 设置分组 and 取消关注, then 取消 in its own block.
class FollowedSheet extends StatelessWidget {
  const FollowedSheet({super.key, required this.onGroups, required this.onUnfollow, required this.onCancel});

  final VoidCallback onGroups;
  final VoidCallback onUnfollow;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _Rule(),
      _ActionRow(
        key: const ValueKey('friends-sheet-groups'),
        label: '设置分组',
        glyph: const SizedBox(
          width: FriendsTheme.groupGlyphWidth,
          height: FriendsTheme.groupGlyphHeight,
          child: CustomPaint(painter: GroupActionPainter()),
        ),
        onTap: onGroups,
      ),
      const _Rule(),
      _ActionRow(
        key: const ValueKey('friends-sheet-unfollow'),
        label: '取消关注',
        glyph: const SizedBox(
          width: FriendsTheme.unfollowGlyphWidth,
          height: FriendsTheme.unfollowGlyphHeight,
          child: CustomPaint(painter: UnfollowActionPainter()),
        ),
        onTap: onUnfollow,
      ),
      const SizedBox(height: FriendsTheme.actionGap, child: ColoredBox(color: FriendsTheme.actionGapFill)),
      const _Rule(),
      PressHighlight(
        onTap: onCancel,
        child: Semantics(
          button: true,
          label: '取消',
          onTap: onCancel,
          excludeSemantics: true,
          child: SizedBox(
            key: const ValueKey('friends-sheet-cancel'),
            height: FriendsTheme.cancelRow,
            child: Center(
              child: friendsLine(
                '取消',
                followingStyle(FriendsTheme.cancelRowText, FriendsTheme.actionInk, line: FriendsTheme.cancelRowLine),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: FriendsTheme.actionRule, child: ColoredBox(color: FriendsTheme.actionRuleInk));
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({super.key, required this.label, required this.glyph, required this.onTap});

  final String label;
  final Widget glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressHighlight(
    onTap: onTap,
    child: Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox(
        height: FriendsTheme.actionRow,
        child: Stack(
          children: [
            Positioned(
              left: FriendsTheme.actionGlyphCentre - FriendsTheme.unfollowGlyphWidth / 2,
              width: FriendsTheme.unfollowGlyphWidth,
              top: FriendsTheme.actionCentre - FriendsTheme.unfollowGlyphWidth / 2,
              height: FriendsTheme.unfollowGlyphWidth,
              child: Center(child: glyph),
            ),
            Positioned(
              left: FriendsTheme.actionTextLeft,
              right: FriendsTheme.actionTextLeft,
              top: FriendsTheme.actionCentre - FriendsTheme.actionLine / 2,
              height: FriendsTheme.actionLine,
              child: Align(
                alignment: Alignment.centerLeft,
                child: friendsLine(
                  label,
                  followingStyle(FriendsTheme.actionText, FriendsTheme.actionInk, line: FriendsTheme.actionLine),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 设置分组 (167) for one person: the account's 分组 with a circle each, ticked for those the person is in;
/// ＋新建分组 ([onNewGroup]), and 保存至默认分组 or 保存. [onSaved] closes the sheet; it is told whether anything was
/// sent. A failed save says why ([onFailed]) and stays up.
class GroupSheet extends StatefulWidget {
  const GroupSheet({
    super.key,
    required this.api,
    required this.mid,
    required this.groups,
    required this.onNewGroup,
    required this.onSaved,
    required this.onFailed,
  });

  final FriendsApi api;

  /// The person's.
  final int mid;

  /// The account's 分组, which the page asks once.
  final Future<List<RelationTag>> Function() groups;
  final VoidCallback onNewGroup;
  final ValueChanged<bool> onSaved;
  final ValueChanged<String> onFailed;

  @override
  State<GroupSheet> createState() => _GroupSheetState();
}

class _GroupSheetState extends State<GroupSheet> {
  late final GroupSheetModel _model = GroupSheetModel(api: widget.api, mid: widget.mid, groups: widget.groups);

  @override
  void initState() {
    super.initState();
    unawaited(_model.load());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final sent = _model.changed;
    final failure = await _model.save();
    if (!mounted) return;
    if (failure != null) {
      widget.onFailed(failure);
    } else {
      widget.onSaved(sent);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: FriendsTheme.groupSheet,
    child: ListenableBuilder(
      listenable: _model,
      builder: (context, _) => Stack(
        children: [
          ..._head(),
          Positioned(
            left: 0,
            right: 0,
            top: FriendsTheme.groupsTop,
            bottom: FriendsTheme.saveCentre + FriendsTheme.saveTarget / 2,
            child: _body(),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: FriendsTheme.saveCentre - FriendsTheme.saveTarget / 2,
            height: FriendsTheme.saveTarget,
            child: _saveButton(),
          ),
        ],
      ),
    ),
  );

  List<Widget> _head() {
    final title = followingStyle(FriendsTheme.groupTitleText, FriendsTheme.groupInk, line: FriendsTheme.groupTitleLine);
    final add = followingStyle(FriendsTheme.newGroupText, FriendsTheme.newGroupInk, line: FriendsTheme.newGroupLine);
    return [
      Positioned(
        left: FriendsTheme.groupIconCentreX - FriendsTheme.groupIcon / 2,
        top: FriendsTheme.groupIconCentreY - FriendsTheme.groupIcon / 2,
        width: FriendsTheme.groupIcon,
        height: FriendsTheme.groupIcon,
        child: Image.asset('assets/images/friends/attention_group.png'),
      ),
      Positioned(
        left: FriendsTheme.groupTitleLeft,
        top: FriendsTheme.groupHeadCentre - FriendsTheme.groupTitleLine / 2,
        height: FriendsTheme.groupTitleLine,
        child: friendsLine('设置分组', title),
      ),
      Positioned(
        right: FriendsTheme.fieldInset,
        top: FriendsTheme.groupHeadCentre - FriendsTheme.saveTarget / 2,
        height: FriendsTheme.saveTarget,
        child: Semantics(
          button: true,
          label: '新建分组',
          onTap: widget.onNewGroup,
          excludeSemantics: true,
          child: GestureDetector(
            key: const ValueKey('friends-new-group'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onNewGroup,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: FriendsTheme.plus,
                  child: CustomPaint(painter: PlusPainter()),
                ),
                const SizedBox(width: FriendsTheme.plusGap),
                friendsLine('新建分组', add),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _body() {
    final groups = _model.groups;
    if (groups == null) {
      final error = _model.error;
      if (error == null) return const Center(child: LoadingTvState());
      return FriendsMessage(
        key: const ValueKey('friends-groups-failed'),
        message: error,
        action: '重试',
        actionKey: const ValueKey('friends-groups-retry'),
        onAction: () => unawaited(_model.load()),
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      children: [
        for (final group in groups)
          _GroupRow(
            group: group,
            ticked: _model.chosen.contains(group.id),
            onTap: () => _model.toggle(group.id),
          ),
      ],
    );
  }

  Widget _saveButton() {
    final label = _model.toDefault ? '保存至默认分组' : '保存';
    final ready = _model.groups != null && !_model.saving;
    return Semantics(
      button: true,
      label: label,
      onTap: ready ? () => unawaited(_save()) : null,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('friends-groups-save'),
        behavior: HitTestBehavior.opaque,
        onTap: ready ? () => unawaited(_save()) : null,
        child: Center(
          child: friendsLine(
            label,
            followingStyle(FriendsTheme.saveText, FriendsTheme.saveInk, line: FriendsTheme.saveLine),
          ),
        ),
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group, required this.ticked, required this.onTap});

  final RelationTag group;
  final bool ticked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = followingStyle(FriendsTheme.groupNameText, FriendsTheme.groupInk, line: FriendsTheme.groupNameLine);
    final tip = followingStyle(FriendsTheme.groupTipText, FriendsTheme.groupTipInk, line: FriendsTheme.groupTipLine);
    const textRight = FriendsTheme.fieldInset + FriendsTheme.tick + FriendsTheme.textGap;
    final hasTip = group.tip.isNotEmpty;
    return Semantics(
      button: true,
      selected: ticked,
      label: group.name,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('friends-group-${group.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: FriendsTheme.groupRow,
          child: Stack(
            children: [
              Positioned(
                left: FriendsTheme.fieldInset,
                right: textRight,
                top: (hasTip ? FriendsTheme.groupNameCentre : FriendsTheme.groupRow / 2) -
                    FriendsTheme.groupNameLine / 2,
                height: FriendsTheme.groupNameLine,
                child: Align(alignment: Alignment.centerLeft, child: friendsLine(group.name, name)),
              ),
              if (hasTip)
                Positioned(
                  left: FriendsTheme.fieldInset,
                  right: textRight,
                  top: FriendsTheme.groupTipCentre - FriendsTheme.groupTipLine / 2,
                  height: FriendsTheme.groupTipLine,
                  child: Align(alignment: Alignment.centerLeft, child: friendsLine(group.tip, tip)),
                ),
              Positioned(
                right: FriendsTheme.fieldInset,
                top: (FriendsTheme.groupRow - FriendsTheme.tick) / 2,
                width: FriendsTheme.tick,
                height: FriendsTheme.tick,
                child: CustomPaint(
                  key: ValueKey(ticked ? 'friends-group-${group.id}-ticked' : 'friends-group-${group.id}-open'),
                  painter: TickPainter(ticked: ticked),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
