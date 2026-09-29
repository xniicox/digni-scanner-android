import 'dart:convert';
import 'package:http/http.dart' as http;
import 'session_store.dart';

class DigniApiException implements Exception {
  DigniApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class DigniSession {
  const DigniSession({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
    required this.operatorId,
    required this.operatorName,
    required this.email,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;
  final int operatorId;
  final String operatorName;
  final String email;

  factory DigniSession.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();
    return DigniSession(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      accessExpiresAt: now.add(Duration(seconds: (json['expires_in'] as num?)?.toInt() ?? 900)),
      refreshExpiresAt: now.add(Duration(seconds: (json['refresh_expires_in'] as num?)?.toInt() ?? 2592000)),
      operatorId: (json['operator']?['id'] as num?)?.toInt() ?? 0,
      operatorName: (json['operator']?['name'] ?? 'Operador DIGNI').toString(),
      email: (json['operator']?['email'] ?? '').toString(),
    );
  }
}

class DigniEvent {
  const DigniEvent({
    required this.id,
    required this.title,
    required this.mode,
    required this.organizer,
    required this.dateLabel,
    required this.location,
    this.logoUrl,
    this.captureId,
    this.journeys = const [],
  });

  final int id;
  final String title;
  final String mode; // owned | participating
  final String organizer;
  final String dateLabel;
  final String location;
  final String? logoUrl;
  final int? captureId;
  final List<Map<String, dynamic>> journeys;

  bool get isOwned => mode == 'owned';

  factory DigniEvent.fromJson(Map<String, dynamic> json) => DigniEvent(
    id: (json['id'] as num).toInt(),
    title: (json['title'] ?? '').toString(),
    mode: (json['mode'] ?? 'owned').toString(),
    organizer: (json['organizer'] ?? '').toString(),
    dateLabel: (json['date_label'] ?? '').toString(),
    location: (json['location'] ?? '').toString(),
    logoUrl: json['logo_url']?.toString(),
    captureId: (json['capture_id'] as num?)?.toInt(),
    journeys: ((json['journeys'] as List?) ?? const [])
      .whereType<Map>()
      .map((x) => Map<String, dynamic>.from(x))
      .toList(),
  );
}

class DigniAttendee {
  const DigniAttendee({
    required this.id,
    required this.name,
    required this.maskedRut,
    required this.status,
    this.checkedAt,
    this.reentries = 0,
  });
  final int id;
  final String name;
  final String maskedRut;
  final String status;
  final String? checkedAt;
  final int reentries;

  factory DigniAttendee.fromJson(Map<String, dynamic> json) => DigniAttendee(
    id: (json['id'] as num).toInt(),
    name: (json['name'] ?? '').toString(),
    maskedRut: (json['masked_rut'] ?? '').toString(),
    status: (json['status'] ?? 'pending').toString(),
    checkedAt: json['checked_at']?.toString(),
    reentries: (json['reentries'] as num?)?.toInt() ?? 0,
  );
}

class DigniValidation {
  const DigniValidation({
    required this.outcome,
    required this.title,
    required this.message,
    this.ticketId,
    this.name,
    this.maskedRut,
    this.canReenter = false,
    this.requiresSupervisor = false,
  });
  final String outcome;
  final String title;
  final String message;
  final int? ticketId;
  final String? name;
  final String? maskedRut;
  final bool canReenter;
  final bool requiresSupervisor;

  factory DigniValidation.fromJson(Map<String, dynamic> json) => DigniValidation(
    outcome: (json['outcome'] ?? 'not_found').toString(),
    title: (json['title'] ?? 'No disponible').toString(),
    message: (json['message'] ?? '').toString(),
    ticketId: (json['ticket_id'] as num?)?.toInt(),
    name: json['name']?.toString(),
    maskedRut: json['masked_rut']?.toString(),
    canReenter: json['can_reenter'] == true,
    requiresSupervisor: json['requires_supervisor'] == true,
  );
}

class DigniApi {
  DigniApi({
    required String baseUrl,
    required this.sessions,
    http.Client? client,
  }) : base = Uri.parse(baseUrl.replaceAll(RegExp(r'/+$'), '')),
       client = client ?? http.Client();

  final Uri base;
  final SessionStore sessions;
  final http.Client client;

  Uri _uri(String path, [Map<String, String>? query]) {
    final root = base.toString();
    return Uri.parse('$root/wp-json/digni-scanner/v1$path')
        .replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool authenticated = true,
    bool retryAfterRefresh = true,
  }) async {
    var token = authenticated ? await sessions.accessToken : null;
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'X-DIGNI-App': 'android',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    late http.Response response;
    final uri = _uri(path, query);
    final encoded = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'GET':
        response = await client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 15));
        break;
      case 'POST':
        response = await client
            .post(uri, headers: headers, body: encoded)
            .timeout(const Duration(seconds: 15));
        break;
      default:
        throw ArgumentError('Unsupported method $method');
    }

    if (response.statusCode == 401 && authenticated && retryAfterRefresh) {
      final refreshed = await refresh();
      if (refreshed) {
        return _request(method, path,
          body: body, query: query, authenticated: authenticated,
          retryAfterRefresh: false);
      }
    }

    Map<String, dynamic> json = const {};
    if (response.body.isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) json = Map<String, dynamic>.from(decoded);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DigniApiException(
        (json['message'] ?? 'Error de conexión con DIGNI').toString(),
        statusCode: response.statusCode,
      );
    }
    return json;
  }

  Future<DigniSession> login({
    required String email,
    required String pin,
    required String deviceId,
    required String deviceName,
    required String appVersion,
  }) async {
    final json = await _request('POST', '/auth/login', authenticated: false, body: {
      'email': email,
      'pin': pin,
      'device_id': deviceId,
      'device_name': deviceName,
      'app_version': appVersion,
    });
    final session = DigniSession.fromJson(json);
    await sessions.save(session);
    return session;
  }

  Future<bool> refresh() async {
    final refreshToken = await sessions.refreshToken;
    final deviceId = await sessions.deviceId;
    if (refreshToken == null || refreshToken.isEmpty || deviceId == null) return false;
    try {
      final json = await _request('POST', '/auth/refresh',
        authenticated: false,
        body: {'refresh_token': refreshToken, 'device_id': deviceId});
      final session = DigniSession.fromJson(json);
      await sessions.save(session, deviceId: deviceId);
      return true;
    } catch (_) {
      await sessions.clear();
      return false;
    }
  }

  Future<void> logout() async {
    final refreshToken = await sessions.refreshToken;
    try {
      await _request('POST', '/auth/logout',
        body: {'refresh_token': refreshToken}, retryAfterRefresh: false);
    } catch (_) {
      // Local logout must still work when the network is unavailable.
    } finally {
      await sessions.clear();
    }
  }

  Future<List<DigniEvent>> events() async {
    final json = await _request('GET', '/events');
    return ((json['events'] as List?) ?? const [])
      .whereType<Map>()
      .map((x) => DigniEvent.fromJson(Map<String, dynamic>.from(x)))
      .toList();
  }

  Future<Map<String, dynamic>> summary(int eventId, {int? journeyId}) =>
    _request('GET', '/events/$eventId/summary',
      query: journeyId == null ? null : {'journey_id': '$journeyId'});

  Future<List<DigniAttendee>> attendees(
    int eventId, {
    int? journeyId,
    String query = '',
    String status = 'all',
  }) async {
    final json = await _request('GET', '/events/$eventId/attendees', query: {
      if (journeyId != null) 'journey_id': '$journeyId',
      if (query.isNotEmpty) 'q': query,
      if (status != 'all') 'status': status,
      'limit': '100',
    });
    return ((json['items'] as List?) ?? const [])
      .whereType<Map>()
      .map((x) => DigniAttendee.fromJson(Map<String, dynamic>.from(x)))
      .toList();
  }

  Future<List<Map<String, dynamic>>> attendeeHistory(int ticketId) async {
    final json = await _request('GET', '/tickets/$ticketId/history');
    return ((json['items'] as List?) ?? const [])
      .whereType<Map>()
      .map((x) => Map<String, dynamic>.from(x))
      .toList();
  }

  Future<DigniValidation> validate({
    required int eventId,
    int? journeyId,
    required String code,
    required String deviceId,
  }) async {
    final json = await _request('POST', '/validate', body: {
      'event_id': eventId,
      if (journeyId != null) 'journey_id': journeyId,
      'code': code,
      'device_id': deviceId,
    });
    return DigniValidation.fromJson(json);
  }

  Future<DigniValidation> checkIn({
    required int eventId,
    int? journeyId,
    required int ticketId,
    required String deviceId,
    required String idempotencyKey,
    bool reentry = false,
  }) async {
    final json = await _request('POST', '/check-in', body: {
      'event_id': eventId,
      if (journeyId != null) 'journey_id': journeyId,
      'ticket_id': ticketId,
      'device_id': deviceId,
      'idempotency_key': idempotencyKey,
      'action': reentry ? 'reentry' : 'checkin',
    });
    return DigniValidation.fromJson(json);
  }

  Future<List<Map<String, dynamic>>> captures(int eventId, {String query = ''}) async {
    final json = await _request('GET', '/events/$eventId/captures',
      query: {if (query.isNotEmpty) 'q': query, 'limit': '100'});
    return ((json['items'] as List?) ?? const [])
      .whereType<Map>()
      .map((x) => Map<String, dynamic>.from(x))
      .toList();
  }
}
