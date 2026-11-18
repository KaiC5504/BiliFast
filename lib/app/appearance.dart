import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../device/ios/device_api.g.dart' show NativeInterfaceStyle;
import '../shared/theme.dart';

/// 深色模式 (GitHub issue 3): 我的's ☾/☀ and 深色设置's 深色跟随系统 (249), kept in `appearance.json` in the support
/// folder. It sets [BiliTheme.dark]; [AppearanceRedraw] then draws the whole app again in place, state kept.
class AppearanceModel extends ChangeNotifier with WidgetsBindingObserver {
  AppearanceModel._(this._path, this._dark, this._followSystem, this._logger, this._native);

  /// Kept in memory only, for tests, the PC and a store that can't be read.
  factory AppearanceModel.memory({
    bool dark = false,
    bool followSystem = false,
    void Function(NativeInterfaceStyle style)? native,
  }) => AppearanceModel._(null, dark, followSystem, Logger.shared, native);

  /// [path] null keeps it in memory. A file that can't be read is set aside as `.bad` and the defaults apply (light,
  /// not following iOS). [native] tells the iOS windows, so its own sheets and the keyboard match.
  static Future<AppearanceModel> load(
    String? path, {
    Logger? logger,
    void Function(NativeInterfaceStyle style)? native,
  }) async {
    final log = logger ?? Logger.shared;
    AppearanceModel fresh() => AppearanceModel._(path, false, false, log, native);
    if (path == null) return fresh();
    final file = File(path);
    if (!await file.exists()) return fresh();
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?>) throw const FormatException('not an object');
      final dark = json['dark'];
      final follow = json['followSystem'];
      return AppearanceModel._(path, dark is bool && dark, follow is bool && follow, log, native);
    } catch (error) {
      log.warn(LogCategory.app, 'appearance unreadable, using defaults', {'error': _reason(error)});
    }
    try {
      await file.rename('$path.bad');
    } catch (error) {
      log.warn(LogCategory.app, 'appearance not set aside', {'error': _reason(error)});
    }
    return fresh();
  }

  final String? _path;
  final Logger _logger;
  final void Function(NativeInterfaceStyle style)? _native;
  bool _dark;
  bool _followSystem;
  bool _attached = false;
  Future<void> _writing = Future.value();

  /// The PC's `--dark`: dark for this run, nothing saved.
  bool forced = false;

  /// 深色跟随系统: dark whenever iOS is.
  bool get followSystem => _followSystem;

  /// Whether the app draws dark now.
  bool get dark => BiliTheme.dark;

  bool get _wanted {
    if (forced) return true;
    if (!_followSystem) return _dark;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
  }

  /// Applies the stored choice and starts following iOS's changes; call once the binding exists.
  void attach() {
    if (!_attached) {
      _attached = true;
      WidgetsBinding.instance.addObserver(this);
    }
    _apply();
  }

  /// 我的's ☾/☀: the other mode, which also stops following iOS (as the official app's switch does).
  Future<void> toggle() {
    _dark = !BiliTheme.dark;
    _followSystem = false;
    _apply();
    return _save();
  }

  /// 深色设置's 深色跟随系统. Turned off, the app keeps the mode it shows.
  Future<void> setFollowSystem(bool value) {
    if (value == _followSystem) return Future.value();
    if (!value) _dark = BiliTheme.dark;
    _followSystem = value;
    // The switch's own listeners hear it even when the mode stays.
    if (!_apply()) notifyListeners();
    return _save();
  }

  @override
  void didChangePlatformBrightness() {
    if (_followSystem) _apply();
  }

  /// Whether listeners were told of a change of mode.
  bool _apply() {
    _native?.call(
      forced || !_followSystem
          ? (_wanted ? NativeInterfaceStyle.dark : NativeInterfaceStyle.light)
          : NativeInterfaceStyle.system,
    );
    final dark = _wanted;
    if (dark == BiliTheme.dark) return false;
    BiliTheme.dark = dark;
    _logger.info(LogCategory.ui, 'appearance', {'dark': dark, 'followSystem': _followSystem});
    notifyListeners();
    return true;
  }

  Future<void> _save() {
    final path = _path;
    if (path == null || forced) return Future.value();
    final text = jsonEncode({'dark': _dark, 'followSystem': _followSystem});
    // One write after another, so an older state never lands last; a failed one doesn't stop the next.
    final write = _writing.then((_) => _write(path, text));
    _writing = write.then((_) {}, onError: (Object _) {});
    return write;
  }

  Future<void> _write(String path, String text) async {
    try {
      await File(path).parent.create(recursive: true);
      final temporary = File('$path.tmp');
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(path);
    } catch (error) {
      _logger.warn(LogCategory.app, 'appearance not saved', {'error': _reason(error)});
    }
  }

  /// Waits for the writes made so far; for tests.
  Future<void> get settled => _writing;

  @override
  void dispose() {
    if (_attached) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  static String _reason(Object error) => switch (error) {
    FormatException(:final message) => message,
    FileSystemException(:final message, :final osError) => osError == null ? message : '$message: $osError',
    _ => '${error.runtimeType}',
  };
}

/// Builds the app from [builder] and, when [model] changes mode, builds and paints every widget below again: the
/// colour tokens are read where widgets build and paint, and const widgets or painters that compare equal would
/// otherwise keep the old colours. State is kept, so a playing video plays on.
class AppearanceRedraw extends StatefulWidget {
  const AppearanceRedraw({super.key, required this.model, required this.builder});

  final AppearanceModel model;
  final WidgetBuilder builder;

  @override
  State<AppearanceRedraw> createState() => _AppearanceRedrawState();
}

class _AppearanceRedrawState extends State<AppearanceRedraw> {
  @override
  void initState() {
    super.initState();
    _drawnDark = BiliTheme.dark;
    widget.model.addListener(_changed);
  }

  @override
  void didUpdateWidget(AppearanceRedraw oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.model, widget.model)) {
      oldWidget.model.removeListener(_changed);
      widget.model.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.model.removeListener(_changed);
    super.dispose();
  }

  bool _drawnDark = false;

  void _changed() {
    if (!mounted || _drawnDark == BiliTheme.dark) return;
    _drawnDark = BiliTheme.dark;
    setState(() {});
    redrawAll(context);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// Marks every element under [context] to build and every render object to paint again.
void redrawAll(BuildContext context) {
  void build(Element element) {
    element.markNeedsBuild();
    element.visitChildren(build);
  }

  (context as Element).visitChildren(build);
  void paint(RenderObject object) {
    object.markNeedsPaint();
    object.visitChildren(paint);
  }

  for (final view in RendererBinding.instance.renderViews) {
    paint(view);
  }
}
