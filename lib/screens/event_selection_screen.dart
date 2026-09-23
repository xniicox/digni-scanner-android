import 'package:flutter/material.dart';
import 'dashboard_screen.dart';

class EventSelectionScreen extends StatelessWidget {
  const EventSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Align(
                alignment: Alignment.centerRight,
                child: CircleAvatar(radius: 18, child: Text('NO')),
              ),
              const SizedBox(height: 22),
              Text(
                '¿En qué evento estás hoy?',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 18),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 132,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE9F7F7), Color(0xFFD9EDEF)],
                          ),
                        ),
                        child: const Center(
                          child: Icon(Icons.location_on_rounded, size: 42),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Evento detectado',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 19,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text('10 diciembre 2026 · 08:30–17:00'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () =>
                            Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const DashboardScreen(),
                          ),
                        ),
                        child: const Text('Seleccionar'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Otros eventos hoy',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Card(
                elevation: 0,
                child: ListTile(
                  leading: CircleAvatar(child: Text('E1')),
                  title: Text(
                    'Evento disponible',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('10:00 – 19:00'),
                  trailing: Icon(Icons.chevron_right_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
