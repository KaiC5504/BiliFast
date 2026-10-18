import 'package:flutter/widgets.dart';

/// 确定不再关注？ with 取消 and 确定, over the page.
class UnfollowConfirm extends StatelessWidget {
  const UnfollowConfirm({super.key, required this.onConfirm, required this.onCancel});

  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
