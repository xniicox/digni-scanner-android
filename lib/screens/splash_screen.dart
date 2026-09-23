import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    Future<void>.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: -110,
            left: -90,
            child: Container(
              width: 300,
              height: 300,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x334BE7DF), Color(0x004BE7DF)],
                ),
              ),
            ),
          ),
          Positioned(
            right: -120,
            bottom: -140,
            child: Container(
              width: 360,
              height: 360,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x3348B9D0), Color(0x0048B9D0)],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (_, child) {
                    final p = (_controller.value * 2).clamp(0.0, 1.0);
                    final scale = 0.985 + (0.015 * Curves.easeInOut.transform(p));
                    return Transform.scale(scale: scale, child: child);
                  },
                  child: const _DigniMark(),
                ),
                const SizedBox(height: 34),
                SizedBox(
                  width: 96,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (_, __) => LinearProgressIndicator(
                      value: _controller.value,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(20),
                      backgroundColor: const Color(0xFFE3EAEB),
                      color: AppColors.teal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DigniMark extends StatelessWidget {
  const _DigniMark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Text(
          'Digni',
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w900,
            letterSpacing: -2,
            color: AppColors.ink,
          ),
        ),
        SizedBox(height: 2),
        Text(
          'e-ticket',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
            color: AppColors.teal,
          ),
        ),
      ],
    );
  }
}
