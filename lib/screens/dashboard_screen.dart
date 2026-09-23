import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import 'scanner_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Align(
                alignment: Alignment.centerRight,
                child: CircleAvatar(radius: 18, child: Text('NO')),
              ),
              const SizedBox(height: 16),
              Text('Evento activo', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              const Text('10 diciembre 2026'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5F6EA),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Jornada abierta',
                      style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('08:30 – 17:00'),
                ],
              ),
              const SizedBox(height: 18),
              const Card(
                elevation: 0,
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _Metric(value: '181', label: 'Ingresados'),
                          _Metric(value: '350', label: 'Inscritos'),
                          _Metric(value: '51,7%', label: 'Asistencia'),
                        ],
                      ),
                      SizedBox(height: 18),
                      LinearProgressIndicator(value: .517, minHeight: 6),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Card(
                elevation: 0,
                child: Column(
                  children: [
                    ListTile(
                      title: Text('Reingresos'),
                      trailing: Text('12', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    Divider(height: 1),
                    ListTile(
                      title: Text('Registrados por ti'),
                      trailing: Text('73', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ScannerScreen()),
                ),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Validar acceso'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;

  const _Metric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF677176))),
      ],
    );
  }
}
