/// A journey date is a calendar day, not a moment to convert between zones.
String journeyCalendarDate(Map<String, dynamic>? journey) {
  final raw = journey?['date']?.toString() ?? '';
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return '';
  return '${raw.substring(8, 10)}/${raw.substring(5, 7)}/${raw.substring(0, 4)}';
}

String journeyChoiceLabel(Map<String, dynamic> journey, int index) {
  final date = journeyCalendarDate(journey);
  final number = 'Jornada ${index + 1}';
  return date.isEmpty ? number : '$number · $date';
}
