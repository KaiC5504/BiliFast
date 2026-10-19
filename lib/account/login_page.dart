import 'package:flutter/material.dart';

/// 登录: Bilibili's own login page in a web view (BiliNative `LoginView.swift`); on the PC, a note to log in on the
/// phone. Pops true once the account is logged in.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
