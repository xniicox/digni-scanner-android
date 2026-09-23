import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../widgets/digni_logo.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    )..forward();

    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, .55, curve: Curves.easeOut),
    );

    _scale = Tween<double>(begin: .94, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    Future<void>.delayed(const Duration(milliseconds: 1850), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 420),
          pageBuilder: (_, animation, __) => const LoginScreen(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
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
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFF8FBFB),
                    Color(0xFFEAF7F7),
                    Color(0xFFF8FBFB),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: -80,
            top: -100,
            child: Container(
              width: 280,
              height: 280,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x2811C7C6), Color(0x0011C7C6)],
                ),
              ),
            ),
          ),
          Positioned(
            right: -120,
            bottom: -130,
            child: Container(
              width: 360,
              height: 360,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x24008C98), Color(0x00008C98)],
                ),
              ),
            ),
          ),
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 22,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .72),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .92),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14005C63),
                            blurRadius: 45,
                            offset: Offset(0, 20),
                          ),
                        ],
                      ),
                      child: const DigniLogo(width: 210),
                    ),
                    const SizedBox(height: 34),
                    SizedBox(
                      width: 74,
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(99),
                        backgroundColor: const Color(0xFFDCE9EA),
                        color: AppColors.teal,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'ACCESO SEGURO',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 2.2,
                        fontWeight: FontWeight.w800,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
