import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../shared/theme.dart';

/// A notice box's round pink face (196's 服务通知 and 社区中心, 200's bubbles), [size] across.
class NoticeBoxIcon extends StatelessWidget {
  const NoticeBoxIcon(this.box, {super.key, required this.size});

  final NoticeBox box;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const DecoratedBox(
      decoration: BoxDecoration(color: BiliColors.pink, shape: BoxShape.circle),
    ),
  );
}
