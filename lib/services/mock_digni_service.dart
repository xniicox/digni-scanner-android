import '../core/rut_mask.dart';

enum AccessSeverity { success, warning, danger }

class AccessResult {
  final AccessSeverity severity;
  final String title;
  final String detail;
  final String? fullName;
  final String? rut;
  final bool canReenter;

  const AccessResult({
    required this.severity,
    required this.title,
    required this.detail,
    this.fullName,
    this.rut,
    this.canReenter = false,
  });

  String? get maskedRut => rut == null ? null : maskRut(rut!);
}

class MockDigniService {
  Future<AccessResult> validate(String raw) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final q = raw.toLowerCase();

    if (q.contains('otra-jornada')) {
      return const AccessResult(
        severity: AccessSeverity.warning,
        title: 'Entrada de otra jornada',
        detail: 'Corresponde a una jornada distinta. Aclare antes de registrar el ingreso.',
        fullName: 'NICOLÁS ORTIZ',
        rut: '19.502.901-6',
      );
    }

    if (q.contains('reingreso')) {
      return const AccessResult(
        severity: AccessSeverity.warning,
        title: 'Entrada utilizada anteriormente',
        detail: 'Primer ingreso 10:32 · 1 acceso anterior.',
        fullName: 'NICOLÁS ORTIZ',
        rut: '19.502.901-6',
        canReenter: true,
      );
    }

    if (q.contains('invalido') || q.contains('no-existe')) {
      return const AccessResult(
        severity: AccessSeverity.danger,
        title: 'Entrada no encontrada',
        detail: 'Favor verifique con soporte.',
      );
    }

    return const AccessResult(
      severity: AccessSeverity.success,
      title: 'Acceso autorizado',
      detail: 'Ingreso registrado correctamente.',
      fullName: 'NICOLÁS ORTIZ',
      rut: '19.502.901-6',
    );
  }
}
