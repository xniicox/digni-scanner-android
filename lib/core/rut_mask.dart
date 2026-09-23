String normalizeRut(String rut) {
  return rut.toUpperCase().replaceAll('.', '').replaceAll(' ', '');
}

String maskRut(String rut) {
  final normalized = normalizeRut(rut);
  final parts = normalized.split('-');
  if (parts.length != 2 || parts[0].length < 3) return rut;

  final body = parts[0].replaceAll(RegExp(r'[^0-9]'), '');
  final dv = parts[1].replaceAll(RegExp(r'[^0-9K]'), '');
  if (body.length < 3 || dv.isEmpty) return rut;

  final first = body.substring(0, body.length >= 8 ? 2 : 1);
  final lastBodyDigit = body.substring(body.length - 1);

  return '${first}.***.**${lastBodyDigit}-${dv.substring(0, 1)}';
}
