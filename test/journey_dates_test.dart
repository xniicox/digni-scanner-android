import 'package:flutter_test/flutter_test.dart';
import 'package:digni_scanner/v3/journey_dates.dart';

void main() {
  test('selected journey uses raw calendar date even if legacy name is shifted', () {
    final journey = <String, dynamic>{
      'date': '2026-10-02',
      'name': '01/10/2026 · 09:00–21:00',
    };
    expect(journeyCalendarDate(journey), '02/10/2026');
    expect(journeyChoiceLabel(journey, 1), 'Jornada 2 · 02/10/2026');
  });
}
