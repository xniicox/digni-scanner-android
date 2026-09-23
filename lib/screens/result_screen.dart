import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/mock_digni_service.dart';
import 'dashboard_screen.dart';

class ResultScreen extends StatefulWidget {
  final AccessResult result;

  const ResultScreen({super.key, required this.result});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  @override
  void initState() {
    super.initState();

    if (!widget.result.canReenter) {
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
          (_) => false,
        );
      });
    }
  }

  Color get color => switch (widget.result.severity) {
        AccessSeverity.success => AppColors.success,
        AccessSeverity.warning => AppColors.warning,
        AccessSeverity.danger => AppColors.danger,
      };

  IconData get icon => switch (widget.result.severity) {
        AccessSeverity.success => Icons.check_rounded,
        AccessSeverity.warning => Icons.priority_high_rounded,
        AccessSeverity.danger => Icons.close_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final result = widget.result;

    return Scaffold(
      backgroundColor: Color.alphaBlend(color.withOpacity(.10), Colors.white),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 26),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(.25),
                      blurRadius: 38,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: Icon(icon, size: 62, color: Colors.white),
              ),
              const SizedBox(height: 28),
              Text(
                result.title.toUpperCase(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 25),
              ),
              const SizedBox(height: 18),
              if (result.fullName != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 28,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        result.fullName!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                      if (result.maskedRut != null) ...[
                        const SizedBox(height: 7),
                        Text(
                          'RUT ${result.maskedRut}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              Text(
                result.detail,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15.5, height: 1.35),
              ),
              const Spacer(),
              if (result.canReenter)
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: color),
                  onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const DashboardScreen()),
                    (_) => false,
                  ),
                  child: const Text('Registrar reingreso'),
                )
              else
                SizedBox(
                  width: 94,
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(20),
                    color: color,
                    backgroundColor: color.withOpacity(.15),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
