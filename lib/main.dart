import 'package:flutter/material.dart';
import 'v3/app.dart';
import 'v3/push.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDigniFirebase();
  runApp(const DigniV3App());
}
