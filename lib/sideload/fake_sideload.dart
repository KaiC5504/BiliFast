import 'sideload_model.dart';

/// `--fake-sideload` on the PC: an install whose signature lapses tomorrow with a newer release out, so 设置's 签名
/// section and both launch alerts can be pressed on Windows. Nothing reaches GitHub or iOS.
SideloadModel fakeSideloadModel() => SideloadModel.none();
