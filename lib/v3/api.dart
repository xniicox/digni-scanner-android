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

class DigniTwoFactorRequired implements Exception {
  DigniTwoFactorRequired(this.challengeId, this.message);
  final String challengeId;
  final String message;
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
    required this.operatorRole,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;
  final int operatorId;
  final String operatorName;
  final String email;
  final String operatorRole;

  factory DigniSession.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();
    final operator = (json['operator'] ?? json['user']) is Map
        ? Map<String, dynamic>.from((json['operator'] ?? json['user']) as Map)
        : const <String, dynamic>{};
    return DigniSession(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      accessExpiresAt: now.add(Duration(seconds: (json['expires_in'] as num?)?.toInt() ?? 900)),
      refreshExpiresAt: now.add(Duration(seconds: (json['refresh_expires_in'] as num?)?.toInt() ?? 2592000)),
      operatorId: int.tryParse((operator['id'] ?? '0').toString()) ?? 0,
      operatorName: (operator['name'] ?? 'Operador DIGNI').toString(),
      email: (operator['email'] ?? '').toString(),
      operatorRole: (operator['role'] ?? operator['user_role'] ?? operator['profile'] ?? 'operator').toString(),
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
    this.commune = '',
    this.region = '',
    this.state = 'active',
    this.logoUrl,
    this.captureId,
    this.captureCount = 0,
    this.journeys = const [],
  });

  final int id;
  final String title;
  final String mode; // owned | participating
  final String organizer;
  final String dateLabel;
  final String location;
  final String commune;
  final String region;
  final String state;
  final String? logoUrl;
  final int? captureId;
  final int captureCount;
  final List<Map<String, dynamic>> journeys;

  bool get isOwned => mode == 'owned';
  bool get isOpen => const {'active', 'open', 'opened'}.contains(state);

  factory DigniEvent.fromJson(Map<String, dynamic> json) => DigniEvent(
    id: int.tryParse((json['id'] ?? '0').toString()) ?? 0,
    title: (json['title'] ?? '').toString(),
    mode: (json['mode'] ?? 'owned').toString(),
    organizer: (json['organizer'] ?? '').toString(),
    dateLabel: (json['date_label'] ?? '').toString(),
    location: (json['location'] ?? '').toString(),
    commune: (json['commune'] ?? json['event_commune'] ?? '').toString(),
    region: (json['region'] ?? '').toString(),
    state: (json['state'] ?? 'active').toString(),
    logoUrl: json['logo_url']?.toString(),
    captureId: (json['capture_id'] as num?)?.toInt(),
    captureCount: (json['capture_count'] as num?)?.toInt() ?? 0,
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
    this.entryNumber,
    this.code,
    this.ticketId,
  });
  final int id;
  /// The API normally returns both `id` and `ticket_id`. Keep them separate
  /// because history/check-in routes address the ticket, not a list row.
  final int? ticketId;
  final String name;
  final String maskedRut;
  final String status;
  final String? checkedAt;
  final int reentries;
  final String? entryNumber;
  final String? code;

  factory DigniAttendee.fromJson(Map<String, dynamic> json) => DigniAttendee(
    id: int.tryParse((json['id'] ?? json['ticket_id'] ?? json['attendee_id'] ?? '0').toString()) ?? 0,
    ticketId: int.tryParse((json['ticket_id'] ?? json['id'] ?? '').toString()),
    name: (json['name'] ?? json['full_name'] ?? '').toString(),
    maskedRut: (json['masked_rut'] ?? '').toString(),
    status: (json['status'] ?? 'pending').toString(),
    checkedAt: json['checked_at']?.toString(),
    reentries: (json['reentries'] as num?)?.toInt() ?? 0,
    entryNumber: (json['entry_number'] ?? json['ticket_number'] ?? json['ticket_code'] ?? json['number'] ?? json['code'])?.toString(),
    code: json['code']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'ticket_id': ticketId ?? id,
    'name': name,
    'masked_rut': maskedRut,
    'status': status,
    if (checkedAt != null) 'checked_at': checkedAt,
    'reentries': reentries,
    if (entryNumber != null) 'entry_number': entryNumber,
    if (code != null) 'code': code,
  };
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
    this.entryNumber,
    this.courtesy = false,
    this.accessNumber,
    this.needsData = false,
    this.usedAt,
    this.usedBy,
    this.status,
  });
  final String outcome;
  final String title;
  final String message;
  final int? ticketId;
  final String? name;
  final String? maskedRut;
  final bool canReenter;
  final bool requiresSupervisor;
  final String? entryNumber;
  final bool courtesy;
  final int? accessNumber;
  final bool needsData;
  final String? usedAt;
  final String? usedBy;
  final String? status;

  factory DigniValidation.fromJson(Map<String, dynamic> json) => DigniValidation(
    outcome: (json['outcome'] ?? 'not_found').toString(),
    title: (json['title'] ?? 'No disponible').toString(),
    message: (json['message'] ?? '').toString(),
    ticketId: int.tryParse((json['ticket_id'] ?? json['id'] ?? '').toString()),
    name: (json['name'] ?? (json['attendee'] is Map
            ? (json['attendee'] as Map)['name']
            : null))?.toString(),
    maskedRut: (json['masked_rut'] ?? (json['attendee'] is Map
            ? (json['attendee'] as Map)['masked_rut']
            : null))?.toString(),
    canReenter: json['can_reenter'] == true,
    requiresSupervisor: json['requires_supervisor'] == true,
    courtesy: json['courtesy'] == true,
    entryNumber: (json['entry_number'] ?? json['ticket_number'] ?? json['number'] ?? (json['ticket'] is Map ? (json['ticket'] as Map)['number'] : null))?.toString(),
    accessNumber: int.tryParse((json['access_number'] ?? '').toString()),
    needsData: json['needs_data'] == true ||
        json['requires_data'] == true ||
        json['data_pending'] == true ||
        json['incomplete'] == true ||
        ['pending_data', 'incomplete', 'courtesy'].contains((json['outcome'] ?? '').toString().toLowerCase()),
    usedAt: (json['used_at'] ?? json['checked_at'] ?? json['last_checkin_at'] ??
            (json['access'] is Map ? (json['access'] as Map)['created_at'] : null))?.toString(),
    usedBy: (json['used_by'] ?? json['operator_name'] ?? json['checked_by'] ??
            (json['access'] is Map ? (json['access'] as Map)['operator_name'] : null))?.toString(),
    status: json['status']?.toString(),
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
    // WordPress REST responses are wrapped as {success:true,data:{...}}.
    // Normalize that envelope once so all client models consume the same
    // fields in both wrapped and legacy responses.
    if (json['success'] == true && json['data'] is Map) {
      json = Map<String, dynamic>.from(json['data'] as Map);
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
    if (json['requires_2fa'] == true) {
      throw DigniTwoFactorRequired(
        (json['challenge_id'] ?? '').toString(),
        'Ingresa el código de verificación de tu autenticador.',
      );
    }
    final session = DigniSession.fromJson(json);
    await sessions.save(session);
    return session;
  }

  Future<DigniSession> verify2fa({
    required String challengeId,
    required String code,
    required String deviceId,
  }) async {
    final json = await _request('POST', '/auth/2fa/verify', authenticated: false,
      body: {
        'challenge_id': challengeId,
        'code': code,
        'device_id': deviceId,
      });
    final session = DigniSession.fromJson(json);
    await sessions.save(session, deviceId: deviceId);
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
    final rows = (json['items'] as List?) ??
        (json['attendees'] as List?) ??
        (json['results'] as List?) ??
        const [];
    return rows
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
    String? rut,
    String? name,
    String? qrData,
    required String deviceId,
  }) async {
    final json = await _request('POST', '/validate', body: {
      'event_id': eventId,
      if (journeyId != null) 'journey_id': journeyId,
      'code': code,
      if (rut != null && rut.trim().isNotEmpty) 'rut': rut.trim(),
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      // Keep the original civil-document payload available to compatible
      // backends while `code` remains the ticket code for the current API.
      if (qrData != null && qrData.trim().isNotEmpty) 'qr_data': qrData.trim(),
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

  Future<Map<String, dynamic>> assignCourtesy({
    required int ticketId,
    required String name,
    required String rut,
    required String email,
    required String phone,
    required String region,
    required String commune,
  }) async {
    final assignment = await _request('POST', '/tickets/$ticketId/assign', body: {
      'ticket_id': ticketId,
      'name': name,
      'rut': rut,
      'email': email,
      'phone': phone,
      'region': region,
      'commune': commune,
      'document_type': 'rut',
      'document_country': 'CL',
      'document_number': rut,
    });
    if (assignment['complete'] == false) {
      throw DigniApiException(
        'La entrada todavía tiene datos pendientes. Revisa nombre, RUT y correo.');
    }
    return assignment;
  }

  Future<DigniValidation> checkout({
    required int eventId,
    int? journeyId,
    required int ticketId,
    required String deviceId,
    required String idempotencyKey,
  }) async {
    final json = await _request('POST', '/check-out', body: {
      'event_id': eventId,
      if (journeyId != null) 'journey_id': journeyId,
      'ticket_id': ticketId,
      'device_id': deviceId,
      'idempotency_key': idempotencyKey,
    });
    return DigniValidation.fromJson(json);
  }

  Future<Map<String, dynamic>> sync(
      List<Map<String, dynamic>> operations) async {
    if (operations.isEmpty) return const {'processed': 0, 'items': []};
    return _request('POST', '/sync', body: {'operations': operations});
  }

  Future<Map<String, dynamic>> deviceStatus() =>
      _request('GET', '/device-status');

  Future<List<Map<String, dynamic>>> captures(int eventId, {String query = ''}) async {
    final json = await _request('GET', '/events/$eventId/captures',
      query: {if (query.isNotEmpty) 'q': query, 'limit': '100'});
    return ((json['items'] as List?) ?? const [])
      .whereType<Map>()
      .map((x) => Map<String, dynamic>.from(x))
      .toList();
  }
}
