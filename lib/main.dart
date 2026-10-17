import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'bench.dart';
import 'services.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Services.init(args);
  final bench = BenchPlan.fromArgs(args);
  runApp(SpikeApp(home: bench == null ? const HomePage() : BenchPage(plan: bench)));
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BiliFlutter spike',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Bili.pink, primary: Bili.pink),
        scaffoldBackgroundColor: Bili.page,
        pageTransitionsTheme: PageTransitionsTheme(builders: {
          for (final p in TargetPlatform.values) p: const CupertinoPageTransitionsBuilder(),
        }),
      ),
      home: home,
    );
  }
}
