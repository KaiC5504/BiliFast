const _bvAlphabet = 'FcwAPNKTMug3GV5Lj7EJnHpWsx4tb8haYeviqBz6rkCy12mUSDQX9RdoZf';

/// The aid's BV id by Bilibili's published conversion, for answers that leave `bvid` out (the official feed's
/// cards, the own space's 投币/点赞 previews).
String avToBv(int aid) {
  const xor = 23442827791579;
  final chars = 'BV1000000000'.split('');
  var value = ((1 << 51) | aid) ^ xor;
  for (var index = chars.length - 1; value > 0; index--) {
    chars[index] = _bvAlphabet[value % 58];
    value ~/= 58;
  }
  void swap(int a, int b) {
    final kept = chars[a];
    chars[a] = chars[b];
    chars[b] = kept;
  }

  swap(3, 9);
  swap(4, 7);
  return chars.join();
}
