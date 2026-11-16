/// A list's date (196, 197, 198): 刚刚, N分钟前, N小时前, N天前 up to three days, M月D日 this year, YYYY年M月D日
/// before.
String noticeDate(DateTime at, {required DateTime now}) {
  final gap = now.difference(at);
  if (gap.inMinutes < 1) return '刚刚';
  if (gap.inHours < 1) return '${gap.inMinutes}分钟前';
  if (gap.inDays < 1) return '${gap.inHours}小时前';
  if (gap.inDays <= 3) return '${gap.inDays}天前';
  if (at.year == now.year) return '${at.month}月${at.day}日';
  return '${at.year}年${at.month}月${at.day}日';
}

/// A chat's time line between bubbles (202, 200): 2025年11月26日 21:51, the year always given.
String chatStamp(DateTime at) =>
    '${at.year}年${at.month}月${at.day}日 ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
