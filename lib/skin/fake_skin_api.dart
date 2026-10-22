import 'dart:async';

import 'package:bili_core/api.dart';

import 'skin_api.dart';

/// Made-up answers for tests and `--fake-account` on the PC: no skin call leaves the machine. [demo] builds a package
/// of drawn stand-in pictures (never the official art). [calls] lists what was asked; [holds] keeps a call waiting
/// and [failures] makes it throw.
class FakeSkinApi implements SkinApi {
  FakeSkinApi({this.equip, this.package = const []});

  factory FakeSkinApi.demo() => FakeSkinApi();

  SkinEquip? equip;
  List<int> package;

  final calls = <String>[];
  final holds = <String, Completer<void>>{};
  final failures = <String, Object>{};

  Future<T> _answer<T>(String name, T Function() value) async {
    calls.add(name);
    if (holds[name] case final hold?) await hold.future;
    if (failures[name] case final failure?) throw failure;
    return value();
  }

  @override
  Future<SkinEquip?> equipped() => _answer('equipped', () => equip);

  @override
  Future<List<int>> download(Uri package) => _answer('download', () => this.package);
}
