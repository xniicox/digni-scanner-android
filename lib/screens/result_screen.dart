import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/mock_digni_service.dart';
import '../widgets/digni_logo.dart';
import 'dashboard_screen.dart';

class ResultScreen extends StatefulWidget {
  final AccessResult result;

  const ResultScreen({
    super.key,
    required this.result,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation;

  @override
  void initState() {
    super.initState();

    animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();

    if (!widget.result.canReenter) {
      Future<void>.delayed(const Duration(milliseconds: 2600), () {
        if (!mounted) return;
        _home();
      });
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  void _home() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
      (_) => false,
    );
  }

  Color get color => switch (widget.result.severity) {
        AccessSeverity.success => AppColors.success,
        AccessSeverity.warning => AppColors.warning,
        AccessSeverity.danger => AppColors.danger,
      };

  Color get softColor => switch (widget.result.severity) {
        AccessSeverity.success => const Color(0xFFE9F8EF),
        AccessSeverity.warning => const Color(0xFFFFF6DF),
        AccessSeverity.danger => const Color(0xFFFFEAEC),
      };

  IconData get icon => switch (widget.result.severity) {
        AccessSeverity.success => Icons.check_rounded,
        AccessSeverity.warning => Icons.priority_high_rounded,
        AccessSeverity.danger => Icons.close_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final curve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutBack,
    );

    return Scaffold(
      backgroundColor: softColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
          child: Column(
            children: [
              const Row(
                children: [
                  DigniLogo(width: 112),
                  Spacer(),
                  Text(
                    'CONTROL DE ACCESO',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.3,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              ScaleTransition(
                scale: curve,
                child: Container(
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: .28),
                        blurRadius: 42,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    size: 64,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              FadeTransition(
                opacity: animation,
                child: Text(
                  result.title.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(
                        fontSize: 27,
                        color: AppColors.ink,
                      ),
                ),
              ),
              const SizedBox(height: 20),
              if (result.fullName != null)
                FadeTransition(
                  opacity: animation,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 21, 20, 21),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: color.withValues(alpha: .16),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x12000000),
                          blurRadius: 34,
                          offset: Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'IDENTIDAD',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 10,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          result.fullName!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                        if (result.maskedRut != null) ...[
                          const SizedBox(height: 7),
                          Text(
                            'RUT ' + result.maskedRut!,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .25,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              Text(
                result.detail,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15.5,
                  height: 1.4,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (result.canReenter)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                  ),
                  onPressed: _home,
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Registrar reingreso'),
                )
              else ...[
                SizedBox(
                  width: 118,
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(20),
                    color: color,
                    backgroundColor: color.withValues(alpha: .14),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Volviendo al panel',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
