import 'package:flutter/material.dart';
import 'core/app_theme.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DigniScannerApp());
}

class DigniScannerApp extends StatelessWidget {
  const DigniScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DIGNI Scanner',
      theme: buildTheme(),
      home: const SplashScreen(),
    );
  }
}
