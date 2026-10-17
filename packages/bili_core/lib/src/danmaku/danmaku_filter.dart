import 'danmaku_elem.dart';

enum BlockRuleKind {
  keyword(0),
  regex(1),
  user(2);

  const BlockRuleKind(this.rawValue);

  final int rawValue;

  /// Null for a type the server added later, like Swift's `Kind(rawValue:)`.
  static BlockRuleKind? fromRawValue(int rawValue) {
    for (final kind in values) {
      if (kind.rawValue == rawValue) return kind;
    }
    return null;
  }
}

final class BlockRule {
  const BlockRule({required this.id, required this.kind, required this.filter});

  final int id;
  final BlockRuleKind kind;
  final String filter;

  @override
  bool operator ==(Object other) =>
      other is BlockRule && other.id == id && other.kind == kind && other.filter == filter;

  @override
  int get hashCode => Object.hash(id, kind, filter);

  @override
  String toString() => 'BlockRule($id, ${kind.name}, $filter)';
}

final class DanmakuFilterOptions {
  const DanmakuFilterOptions({
    this.blockFixed = false,
    this.blockScroll = false,
    this.blockColored = false,
    this.blockAdvanced = false,
    this.blockCount = false,
    this.dedupe = false,
    this.hideBottom = false,
    this.applyRules = true,
  });

  /// Settings saved by an older build lack newer keys; they take the defaults instead of failing.
  factory DanmakuFilterOptions.fromJson(Map<String, Object?> json) => DanmakuFilterOptions(
    blockFixed: json['blockFixed'] as bool? ?? false,
    blockScroll: json['blockScroll'] as bool? ?? false,
    blockColored: json['blockColored'] as bool? ?? false,
    blockAdvanced: json['blockAdvanced'] as bool? ?? false,
    blockCount: json['blockCount'] as bool? ?? false,
    dedupe: json['dedupe'] as bool? ?? false,
    hideBottom: json['hideBottom'] as bool? ?? false,
    applyRules: json['applyRules'] as bool? ?? true,
  );

  final bool blockFixed;
  final bool blockScroll;
  final bool blockColored;

  /// Mode 7 is dropped whatever this says; kept so the settings panel has its switch.
  final bool blockAdvanced;

  /// Hides the danmaku that dedupe would show as "×N".
  final bool blockCount;
  final bool dedupe;
  final bool hideBottom;
  final bool applyRules;

  Map<String, Object?> toJson() => {
    'blockFixed': blockFixed,
    'blockScroll': blockScroll,
    'blockColored': blockColored,
    'blockAdvanced': blockAdvanced,
    'blockCount': blockCount,
    'dedupe': dedupe,
    'hideBottom': hideBottom,
    'applyRules': applyRules,
  };

  DanmakuFilterOptions copyWith({
    bool? blockFixed,
    bool? blockScroll,
    bool? blockColored,
    bool? blockAdvanced,
    bool? blockCount,
    bool? dedupe,
    bool? hideBottom,
    bool? applyRules,
  }) => DanmakuFilterOptions(
    blockFixed: blockFixed ?? this.blockFixed,
    blockScroll: blockScroll ?? this.blockScroll,
    blockColored: blockColored ?? this.blockColored,
    blockAdvanced: blockAdvanced ?? this.blockAdvanced,
    blockCount: blockCount ?? this.blockCount,
    dedupe: dedupe ?? this.dedupe,
    hideBottom: hideBottom ?? this.hideBottom,
    applyRules: applyRules ?? this.applyRules,
  );

  @override
  bool operator ==(Object other) =>
      other is DanmakuFilterOptions &&
      other.blockFixed == blockFixed &&
      other.blockScroll == blockScroll &&
      other.blockColored == blockColored &&
      other.blockAdvanced == blockAdvanced &&
      other.blockCount == blockCount &&
      other.dedupe == dedupe &&
      other.hideBottom == hideBottom &&
      other.applyRules == applyRules;

  @override
  int get hashCode =>
      Object.hash(blockFixed, blockScroll, blockColored, blockAdvanced, blockCount, dedupe, hideBottom, applyRules);

  @override
  String toString() => 'DanmakuFilterOptions(${toJson()})';
}

final class DisplayDanmaku {
  const DisplayDanmaku({required this.elem, required this.text, required this.isOwn});

  final DanmakuElem elem;
  final String text;
  final bool isOwn;

  @override
  bool operator ==(Object other) =>
      other is DisplayDanmaku && other.elem == elem && other.text == text && other.isOwn == isOwn;

  @override
  int get hashCode => Object.hash(elem, text, isOwn);

  @override
  String toString() => 'DisplayDanmaku("$text", ${elem.progressMs} ms${isOwn ? ', own' : ''})';
}

abstract final class DanmakuFilter {
  static const int _mergeWindowMs = 10000;

  static List<DisplayDanmaku> apply(
    List<DanmakuElem> elems, {
    required DanmakuFilterOptions options,
    required List<BlockRule> rules,
    String? ownHash,
  }) {
    final own = (ownHash == null || ownHash.isEmpty) ? null : ownHash;
    final matcher = options.applyRules && rules.isNotEmpty ? _RuleMatcher(rules) : null;

    var passed = <_Passed>[];
    for (final elem in elems) {
      if (elem.mode >= 7 && elem.mode <= 9) continue;
      if (_typeBlocked(elem, options)) continue;
      final isOwn = own != null && elem.midHash == own;
      if (!isOwn && matcher != null && matcher.blocks(elem)) continue;
      passed.add(_Passed(elem, isOwn));
    }

    if (!_isSorted(passed)) {
      // List.sort is not stable, so ties fall back to arrival order.
      final indexed = [for (var i = 0; i < passed.length; i++) (i, passed[i])];
      indexed.sort((a, b) {
        final byTime = a.$2.elem.progressMs.compareTo(b.$2.elem.progressMs);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });
      passed = [for (final entry in indexed) entry.$2];
    }

    if (!options.dedupe && !options.blockCount) {
      return [for (final p in passed) DisplayDanmaku(elem: p.elem, text: p.elem.content, isOwn: p.isOwn)];
    }
    return _merged(passed, dropMerged: options.blockCount);
  }

  static bool _typeBlocked(DanmakuElem elem, DanmakuFilterOptions options) {
    switch (elem.mode) {
      case 1 || 6:
        if (options.blockScroll) return true;
      case 4:
        if (options.blockFixed || options.hideBottom) return true;
      case 5:
        if (options.blockFixed) return true;
    }
    return options.blockColored && (elem.color != 0xFFFFFF || elem.colorful != 0);
  }

  static bool _isSorted(List<_Passed> items) {
    for (var i = 1; i < items.length; i++) {
      if (items[i].elem.progressMs < items[i - 1].elem.progressMs) return false;
    }
    return true;
  }

  /// Own danmaku are never merged away, so the sender always sees theirs.
  static List<DisplayDanmaku> _merged(List<_Passed> items, {required bool dropMerged}) {
    final groups = <_Group>[];
    final lastKept = <String, int>{};
    for (final item in items) {
      if (!item.isOwn) {
        final index = lastKept[item.elem.content];
        if (index != null && item.elem.progressMs - groups[index].elem.progressMs <= _mergeWindowMs) {
          groups[index].count += 1;
          continue;
        }
        lastKept[item.elem.content] = groups.length;
      }
      groups.add(_Group(item.elem, item.isOwn));
    }
    final result = <DisplayDanmaku>[];
    for (final group in groups) {
      if (group.count >= 2 && dropMerged) continue;
      final text = group.count >= 2 ? '${group.elem.content} ×${group.count}' : group.elem.content;
      result.add(DisplayDanmaku(elem: group.elem, text: text, isOwn: group.isOwn));
    }
    return result;
  }
}

final class _Passed {
  const _Passed(this.elem, this.isOwn);

  final DanmakuElem elem;
  final bool isOwn;
}

final class _Group {
  _Group(this.elem, this.isOwn);

  final DanmakuElem elem;
  final bool isOwn;
  int count = 1;
}

final class _RuleMatcher {
  _RuleMatcher(List<BlockRule> rules) {
    for (final rule in rules) {
      if (rule.filter.isEmpty) continue;
      switch (rule.kind) {
        case BlockRuleKind.keyword:
          _keywords.add(rule.filter);
        case BlockRuleKind.regex:
          var pattern = rule.filter;
          if (pattern.length >= 2 && pattern.startsWith('/') && pattern.endsWith('/')) {
            pattern = pattern.substring(1, pattern.length - 1);
          }
          // An empty pattern would match every danmaku.
          if (pattern.isEmpty) continue;
          try {
            _regexes.add(RegExp(pattern, caseSensitive: false));
          } on FormatException {
            // A rule the server accepted but this engine cannot compile blocks nothing.
          }
        case BlockRuleKind.user:
          _users.add(rule.filter);
      }
    }
  }

  final List<String> _keywords = [];
  final List<RegExp> _regexes = [];
  final Set<String> _users = {};

  bool blocks(DanmakuElem elem) {
    if (_users.isNotEmpty && _users.contains(elem.midHash)) return true;
    final content = elem.content;
    for (final keyword in _keywords) {
      if (content.contains(keyword)) return true;
    }
    for (final regex in _regexes) {
      if (regex.hasMatch(content)) return true;
    }
    return false;
  }
}
