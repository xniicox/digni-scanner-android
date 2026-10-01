import 'package:flutter_test/flutter_test.dart';
import 'package:digni_scanner/v3/civil_qr.dart';

void main() {
  test('extracts RUN even when the name uses Latin-1 percent escapes', () {
    const qr = 'https://portal.sidiv.registrocivil.cl/docstatus?'
        'RUN=12345678-5&type=CEDULA&name=JOSE%C9%20PEREZ';
    expect(CivilQr.identity(qr)['rut'], '12345678-5');
    expect(CivilQr.normalizePayload(qr), '12345678-5');
  });

  test('keeps ticket codes and reads raw RUN fields', () {
    expect(CivilQr.identity('RUN=12345678-5&name=TEST')['rut'], '12345678-5');
    expect(CivilQr.normalizePayload('DIGNI-123-ABC'), 'DIGNI-123-ABC');
  });
}
