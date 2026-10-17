import 'package:flutter/material.dart';

import 'shared/theme.dart';

void main() {
  runApp(const BiliFastApp());
}

class BiliFastApp extends StatelessWidget {
  const BiliFastApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BiliFast',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: BiliColors.pink, primary: BiliColors.pink),
        scaffoldBackgroundColor: BiliColors.pageGrey,
      ),
      home: const _PlaceholderHome(),
    );
  }
}

/// Stands in until slice 3 ports the 推荐 home.
class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'BiliFast',
          style: TextStyle(color: BiliColors.pink, fontSize: 28, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
