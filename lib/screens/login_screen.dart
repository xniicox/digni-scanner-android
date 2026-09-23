import 'package:flutter/material.dart';
import 'event_selection_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Text(
                'Digni',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontSize: 42),
              ),
              const SizedBox(height: 34),
              const TextField(
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                  hintText: 'Correo electrónico',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const TextField(
                obscureText: true,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                  hintText: 'PIN',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => const EventSelectionScreen(),
                  ),
                ),
                child: const Text('Ingresar'),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
