import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import 'digni_logo.dart';
import '../screens/dashboard_screen.dart';
import '../screens/scanner_screen.dart';
import '../screens/simple_section_screen.dart';
import '../screens/login_screen.dart';

class DigniDrawer extends StatelessWidget {
  const DigniDrawer({super.key});

  void _go(BuildContext context, Widget page) {
    Navigator.pop(context);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 310,
      backgroundColor: const Color(0xFFF8FAFA),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DigniLogo(width: 152),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.tealBright, AppColors.teal],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: Text(
                            'N',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Operador DIGNI',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Makita Chile',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                children: [
                  _DrawerItem(
                    icon: Icons.home_rounded,
                    label: 'Inicio',
                    onTap: () => _go(context, const DashboardScreen()),
                  ),
                  _DrawerItem(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'Validar acceso',
                    emphasized: true,
                    onTap: () => _go(context, const ScannerScreen()),
                  ),
                  _DrawerItem(
                    icon: Icons.person_search_rounded,
                    label: 'Buscar asistente',
                    onTap: () => _go(
                      context,
                      const SimpleSectionScreen(
                        title: 'Buscar asistente',
                        icon: Icons.person_search_rounded,
                        description:
                            'Busca por nombre, RUT, correo o identificador de entrada.',
                      ),
                    ),
                  ),
                  _DrawerItem(
                    icon: Icons.history_rounded,
                    label: 'Movimientos',
                    onTap: () => _go(
                      context,
                      const SimpleSectionScreen(
                        title: 'Movimientos recientes',
                        icon: Icons.history_rounded,
                        description:
                            'Aquí aparecerán ingresos, reingresos y validaciones recientes.',
                      ),
                    ),
                  ),
                  _DrawerItem(
                    icon: Icons.sync_rounded,
                    label: 'Sincronizar',
                    onTap: () => _go(
                      context,
                      const SimpleSectionScreen(
                        title: 'Sincronización',
                        icon: Icons.sync_rounded,
                        description:
                            'Sincroniza entradas, cambios de jornada y movimientos pendientes.',
                      ),
                    ),
                  ),
                  _DrawerItem(
                    icon: Icons.swap_horiz_rounded,
                    label: 'Cambiar evento',
                    onTap: () => _go(
                      context,
                      const SimpleSectionScreen(
                        title: 'Cambiar evento',
                        icon: Icons.swap_horiz_rounded,
                        description:
                            'Selecciona otro evento disponible para tu usuario.',
                      ),
                    ),
                  ),
                  _DrawerItem(
                    icon: Icons.account_circle_rounded,
                    label: 'Mi perfil',
                    onTap: () => _go(
                      context,
                      const SimpleSectionScreen(
                        title: 'Mi perfil',
                        icon: Icons.account_circle_rounded,
                        description:
                            'Información del usuario, empresa y dispositivo autorizado.',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: const Icon(Icons.logout_rounded),
                title: const Text(
                  'Cerrar sesión',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (_) => false,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool emphasized;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        leading: Icon(
          icon,
          color: emphasized ? AppColors.teal : AppColors.ink,
        ),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: emphasized ? FontWeight.w800 : FontWeight.w700,
            color: emphasized ? AppColors.teal : AppColors.ink,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: onTap,
      ),
    );
  }
}
