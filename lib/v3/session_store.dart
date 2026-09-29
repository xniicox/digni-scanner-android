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

  Future<String?> get accessToken => storage.read(key: _access);
  Future<String?> get refreshToken => storage.read(key: _refresh);
  Future<String?> get deviceId => storage.read(key: _device);

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
