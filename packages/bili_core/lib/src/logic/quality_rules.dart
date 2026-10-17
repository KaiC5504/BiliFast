abstract final class QualityRules {
  /// Bilibili's qn values from 112 (1080P+) up are paid-member only.
  static bool needsVip(int qn) => qn >= 112;

  static int? auto({required List<int> offered, required bool isVip}) {
    int? best;
    for (final qn in offered) {
      if ((isVip || !needsVip(qn)) && (best == null || qn > best)) best = qn;
    }
    return best;
  }
}
