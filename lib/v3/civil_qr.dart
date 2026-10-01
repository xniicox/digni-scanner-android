/// Extracts only the identity fields needed for ticket lookup. Chilean ID QR
/// URLs may contain Latin-1 percent escapes in the name, so we must not
/// decode the entire query string as UTF-8 just to obtain RUN.
class CivilQr {
  static final _urlRun = RegExp(
    r'(?:[?&]|^)(?:RUN|RUT)=([0-9.\-]+[0-9K])(?:&|$)',
    caseSensitive: false,
  );
  static final _textRun = RegExp(
    r'(?:RUN|RUT|document_number)\s*[=:]\s*([0-9.\-]{7,12}[0-9K])',
    caseSensitive: false,
  );

  static String normalizePayload(String raw) {
    final value = raw.trim();
    if (value.toLowerCase().contains('registrocivil.cl')) {
      return _urlRun.firstMatch(value)?.group(1) ?? value;
    }
    return value;
  }

  static Map<String, String> identity(String raw) {
    final value = raw.trim();
    final civilUrl = value.toLowerCase().contains('registrocivil.cl');
    final rut = (civilUrl ? _urlRun.firstMatch(value)?.group(1) : null) ??
        _textRun.firstMatch(value)?.group(1) ?? '';
    final name = civilUrl ? '' : (RegExp(
      r'(?:name|nombre)\s*[=:]\s*([^&\n]+)', caseSensitive: false,
    ).firstMatch(value)?.group(1)?.trim() ?? '');
    if (!civilUrl && rut.isEmpty && name.isEmpty) return const {};
    return {
      if (rut.isNotEmpty) 'rut': rut,
      if (name.isNotEmpty) 'name': name,
    };
  }
}
