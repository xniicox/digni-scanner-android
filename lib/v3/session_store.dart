import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';

class SessionStore {
  SessionStore({FlutterSecureStorage? storage})
      : storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  final FlutterSecureStorage storage;

  static const _access = 'digni_access_token';
  static const _refresh = 'digni_refresh_token';
  static const _accessExpiry = 'digni_access_expires_at';
  static const _refreshExpiry = 'digni_refresh_expires_at';
  static const _operatorId = 'digni_operator_id';
  static const _operatorName = 'digni_operator_name';
  static const _email = 'digni_operator_email';
  static const _device = 'digni_device_id';
  static const _preview = 'digni_preview_session';
  static const _lastSync = 'digni_last_sync_at';
  static const _pending = 'digni_pending_operations';

  Future<String?> get accessToken => storage.read(key: _access);
  Future<String?> get refreshToken => storage.read(key: _refresh);
  Future<String?> get deviceId => storage.read(key: _device);

  Future<DateTime?> get lastSyncAt async {
    final value = await storage.read(key: _lastSync);
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> markSynced() async {
    await storage.write(
      key: _lastSync,
      value: DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<List<Map<String, dynamic>>> pendingOperations() async {
    final raw = await storage.read(key: _pending);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<int> pendingOperationCount() async =>
      (await pendingOperations()).length;

  Future<void> savePendingOperations(
      List<Map<String, dynamic>> operations) async {
    if (operations.isEmpty) {
      await storage.delete(key: _pending);
      return;
    }
    await storage.write(key: _pending, value: jsonEncode(operations));
  }

  Future<void> queueOperation(Map<String, dynamic> operation) async {
    final current = await pendingOperations();
    final localId = operation['local_id']?.toString();
    current.removeWhere((item) => item['local_id']?.toString() == localId);
    current.add(Map<String, dynamic>.from(operation));
    await savePendingOperations(current);
  }

  Future<void> saveAttendeeCache(
      int eventId, int? journeyId, List<Map<String, dynamic>> items) async {
    final key = 'digni_attendees_${eventId}_${journeyId ?? 0}';
    await storage.write(key: key, value: jsonEncode(items));
  }

  Future<List<Map<String, dynamic>>> attendeeCache(
      int eventId, int? journeyId) async {
    final key = 'digni_attendees_${eventId}_${journeyId ?? 0}';
    final raw = await storage.read(key: key);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<String> ensureDeviceId() async {
    final current = await deviceId;
    if (current != null && current.isNotEmpty) return current;
    final random = Random.secure();
    final bytes = List<int>.generate(20, (_) => random.nextInt(256));
    final id = bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    await storage.write(key: _device, value: id);
    return id;
  }

  Future<void> save(DigniSession session, {String? deviceId}) async {
    await Future.wait([
      storage.write(key: _access, value: session.accessToken),
      storage.write(key: _refresh, value: session.refreshToken),
      storage.write(key: _accessExpiry, value: session.accessExpiresAt.toIso8601String()),
      storage.write(key: _refreshExpiry, value: session.refreshExpiresAt.toIso8601String()),
      storage.write(key: _operatorId, value: session.operatorId.toString()),
      storage.write(key: _operatorName, value: session.operatorName),
      storage.write(key: _email, value: session.email),
      if (deviceId != null) storage.write(key: _device, value: deviceId),
      storage.delete(key: _preview),
    ]);
  }

  Future<void> savePreviewSession({Duration duration = const Duration(minutes: 30)}) async {
    final device = await ensureDeviceId();
    final now = DateTime.now().toUtc();
    await Future.wait([
      storage.write(key: _access, value: 'preview'),
      storage.write(key: _refresh, value: 'preview-refresh'),
      storage.write(key: _accessExpiry, value: now.add(duration).toIso8601String()),
      storage.write(key: _refreshExpiry, value: now.add(duration).toIso8601String()),
      storage.write(key: _operatorId, value: '1'),
      storage.write(key: _operatorName, value: 'Operador DIGNI'),
      storage.write(key: _email, value: 'demo@digni.cl'),
      storage.write(key: _device, value: device),
      storage.write(key: _preview, value: '1'),
    ]);
  }

  Future<bool> previewSessionValid() async {
    final marker = await storage.read(key: _preview);
    if (marker != '1') return false;
    return refreshStillValid();
  }

  Future<bool> accessStillValid({Duration margin = const Duration(seconds: 30)}) async {
    final value = await storage.read(key: _accessExpiry);
    if (value == null) return false;
    final expiry = DateTime.tryParse(value);
    return expiry != null && expiry.isAfter(DateTime.now().toUtc().add(margin));
  }

  Future<bool> refreshStillValid() async {
    final value = await storage.read(key: _refreshExpiry);
    if (value == null) return false;
    final expiry = DateTime.tryParse(value);
    return expiry != null && expiry.isAfter(DateTime.now().toUtc());
  }

  Future<Map<String, String?>> operator() async => {
    'id': await storage.read(key: _operatorId),
    'name': await storage.read(key: _operatorName),
    'email': await storage.read(key: _email),
  };

  Future<void> clear() async {
    // Device id is intentionally retained to keep a stable revocable device identity.
    await Future.wait([
      storage.delete(key: _access),
      storage.delete(key: _refresh),
      storage.delete(key: _accessExpiry),
      storage.delete(key: _refreshExpiry),
      storage.delete(key: _operatorId),
      storage.delete(key: _operatorName),
      storage.delete(key: _email),
      storage.delete(key: _preview),
    ]);
  }
}
