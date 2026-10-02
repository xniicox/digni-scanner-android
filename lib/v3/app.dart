import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'civil_qr.dart';
import 'session_store.dart';

// A preview binary is explicitly compiled with --dart-define=DIGNI_PREVIEW=true.
// A production binary never accepts demo credentials or demo ticket codes.
const bool preview = bool.fromEnvironment('DIGNI_PREVIEW', defaultValue: false);
const String apiBase = String.fromEnvironment('DIGNI_API_BASE', defaultValue: '');

const brandRed = Color(0xFFDF002E); // DIGNI red
const deep = Color(0xFFA4002F);

const space = Color(0xFF12242C);
const spaceDark = Color(0xFF0D151A);
const good = Color(0xFF0CA73D);
const amber = Color(0xFFF9A700);
const red = Color(0xFFEB2217);

enum View { splash, signingOut, login, events, own, external, scanner, result, courtesy, people,
  captures, info, account }
enum Tone { good, warn, bad }

class Decision {
  const Decision(this.tone, this.title, this.message,
    {this.name, this.rut, this.ticketId, this.reenter = false,
      this.supervisor = false, this.confirmEntry = false,
      this.checkout = false, this.entryNumber, this.courtesy = false,
      this.accessNumber, this.usedAt, this.usedBy});
  final Tone tone;
  final String title, message;
  final String? name, rut;
  final int? ticketId;
  final bool reenter;
  final bool supervisor;
  final bool confirmEntry;
  final bool checkout;
  final String? entryNumber;
  final bool courtesy;
  final int? accessNumber;
  final String? usedAt, usedBy;
}

class DigniV3App extends StatefulWidget {
  const DigniV3App({super.key});
  @override
  State<DigniV3App> createState() => _DigniV3AppState();
}

class _DigniV3AppState extends State<DigniV3App> {
  final SessionStore sessions = SessionStore();
  final AudioPlayer player = AudioPlayer();
  final MobileScannerController scannerController = MobileScannerController(
    formats: const [
      BarcodeFormat.qrCode,
      BarcodeFormat.pdf417,
      BarcodeFormat.dataMatrix,
    ],
  );
  final email = TextEditingController();
  final pin = TextEditingController();
  final searchController = TextEditingController();
  final twoFactorCode = TextEditingController();
  final courtesyName = TextEditingController();
  final courtesyRut = TextEditingController();
  final courtesyEmail = TextEditingController();
  final courtesyPhone = TextEditingController();
  final courtesyRegion = TextEditingController(text: 'Región Metropolitana');
  final courtesyCommune = TextEditingController(text: 'Santiago');
  final courtesyFormKey = GlobalKey<FormState>();
  final peopleSearchFocus = FocusNode();
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final navigatorKey = GlobalKey<NavigatorState>();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();

  late final DigniApi? api = apiBase.trim().isEmpty
      ? null
      : DigniApi(baseUrl: apiBase.trim(), sessions: sessions);

  View view = View.splash;
  bool dark = false, authed = false, own = true, busy = false;
  bool recentlyReconnected = false;
  Timer? reconnectTimer;
  String message = '', search = '';
  String courtesyError = '';
  Decision? decision;
  final used = <String>{};
  Timer? autoReturn;
  Timer? refreshTimer;
  Timer? inactivityTimer;
  StreamSubscription<List<ConnectivityResult>>? connectivitySubscription;
  bool online = true;
  DateTime? lastSyncAt;
  int pendingOperations = 0;
  int offlineMaxMinutes = 30;
  String? twoFactorChallenge;

  List<DigniEvent> remoteEvents = const [];
  DigniEvent? selectedEvent;
  Map<String, dynamic>? selectedJourney;
  final Map<int, int?> journeyChoices = {};
  Map<String, dynamic> remoteSummary = const {};
  List<DigniAttendee> remotePeople = const [];
  List<Map<String, dynamic>> remoteCaptures = const [];
  Timer? searchDebounce;
  int peopleRequest = 0;
  bool peopleLoading = false;
  bool syncing = false;
  DigniAttendee? activePerson;
  String operatorName = 'Operador DIGNI';
  String operatorRole = 'operator';
  bool profileChanged = false;
  String? _cachedDeviceName;

  int? get journeyId {
    final value = selectedJourney?['id'];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<String> _deviceName() async {
    if (_cachedDeviceName != null && _cachedDeviceName!.isNotEmpty) {
      return _cachedDeviceName!;
    }
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final maker = info.manufacturer.trim();
      final model = info.model.trim();
      final value = [maker, model]
          .where((part) => part.isNotEmpty)
          .join(' ')
          .trim();
      _cachedDeviceName = value.isEmpty ? 'Android' : value;
    } catch (_) {
      _cachedDeviceName = 'Android';
    }
    return _cachedDeviceName!;
  }

  int? _journeyMapId(Map<String, dynamic> journey) {
    final value = journey['id'];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  bool _journeyIsToday(Map<String, dynamic> journey) {
    final raw = journey['date']?.toString() ?? '';
    // The API returns a calendar date (YYYY-MM-DD), not an instant in UTC.
    // Compare the date directly so timezone conversion cannot change the day.
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw) &&
        raw == _dateKey(DateTime.now());
  }

  String _journeyDate(Map<String, dynamic>? journey) {
    final raw = journey?['date']?.toString() ?? '';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return '';
    return '${raw.substring(8, 10)}/${raw.substring(5, 7)}/${raw.substring(0, 4)}';
  }

  String _journeySchedule(Map<String, dynamic>? journey, String fallback) {
    final date = _journeyDate(journey);
    final starts = journey?['starts']?.toString() ?? '';
    final ends = journey?['ends']?.toString() ?? '';
    if (date.isEmpty) return fallback;
    return '$date${starts.isEmpty ? '' : ' · $starts${ends.isEmpty ? '' : '–$ends'}'}';
  }

  String _journeyStatusFor(Map<String, dynamic>? journey, DigniEvent? event) {
    if (journey == null || !_journeyIsToday(journey) || journey['enabled'] == false ||
        event?.isOpen != true) return 'EVENTO CERRADO';
    final now = DateTime.now();
    final clock = now.hour * 60 + now.minute;
    int? minutes(String? value) {
      final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value ?? '');
      if (match == null) return null;
      return int.parse(match[1]!) * 60 + int.parse(match[2]!);
    }
    final starts = journey['starts']?.toString() ?? '';
    final opening = minutes(starts);
    final closing = minutes(journey['ends']?.toString());
    if (opening != null && clock < opening) return 'ABRE A LAS $starts';
    if (closing != null && clock > closing) return 'JORNADA FINALIZADA';
    return 'JORNADA ABIERTA';
  }

  String _journeyStatus() => _journeyStatusFor(selectedJourney, selectedEvent);

  String _selectedJourneyNumber() {
    final event = selectedEvent;
    if (event == null) return '';
    final index = event.journeys.indexWhere((item) => _journeyMapId(item) == journeyId);
    return index < 0 ? '' : 'JORNADA ${index + 1}';
  }

  int? _todayJourneyId(DigniEvent event) {
    int? firstToday;
    int? upcomingToday;
    for (final journey in event.journeys) {
      if (journey['enabled'] == false) continue;
      if (!_journeyIsToday(journey)) continue;
      final id = _journeyMapId(journey);
      firstToday ??= id;
      final status = _journeyStatusFor(journey, event);
      if (status == 'JORNADA ABIERTA') return id;
      if (status.startsWith('ABRE A LAS')) upcomingToday ??= id;
    }
    return upcomingToday ?? firstToday;
  }

  bool _hasTodayJourney(DigniEvent event) => _todayJourneyId(event) != null;

  bool _eventAvailableToday(DigniEvent event) =>
      !event.isOwned || (event.isOpen && _hasTodayJourney(event));

  String _journeyLabel(Map<String, dynamic> journey, [int? index]) {
    final name = journey['name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    return 'Jornada ${(index ?? 0) + 1}';
  }

  Map<String, dynamic>? _journeyForId(DigniEvent event, int? id) {
    if (id == null) return null;
    for (final journey in event.journeys) {
      if (_journeyMapId(journey) == id) return journey;
    }
    return null;
  }

  Color get bg => dark ? spaceDark : const Color(0xFFF7F7F8);
  Color get surface => dark ? space : Colors.white;
  Color get ink => dark ? const Color(0xFFF7F7F7) : const Color(0xFF232323);
  Color get muted => dark ? const Color(0xFFB8B8B8) : const Color(0xFF696969);
  Color get border => dark ? const Color(0xFF484848) : const Color(0xFFE7E7E9);
  Color get tint => dark ? const Color(0xFF35141E) : const Color(0xFFFDE7EC);

  Color get actionInk => dark ? Colors.white : brandRed;
  Color statusInk(Color color) {
    if (!dark) {
      if (color == good) return const Color(0xFF087A45);
      if (color == amber) return const Color(0xFF805600);
      if (color == red) return const Color(0xFFB3261E);
      return color;
    }
    if (color == good) return const Color(0xFF5BDD80);
    if (color == amber) return amber;
    if (color == red) return const Color(0xFFFFB4AB);
    if (color == brandRed || color == deep) return Colors.white;
    return color;
  }

  String _initials() {
    final words = operatorName.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    if (words.isEmpty) return 'DG';
    if (words.length == 1) return words.first.substring(0, words.first.length >= 2 ? 2 : 1).toUpperCase();
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  void _touchActivity() {
    inactivityTimer?.cancel();
    if (!authed) return;
    inactivityTimer = Timer(const Duration(minutes: 20), _expireForInactivity);
  }

  Future<void> _expireForInactivity() async {
    inactivityTimer?.cancel();
    await sessions.clear();
    if (!mounted) return;
    setState(() {
      authed = false;
      pin.clear();
      twoFactorChallenge = null;
      view = View.login;
      message = 'La sesión se cerró por 20 minutos de inactividad. Ingresa tu PIN nuevamente.';
    });
  }

  @override
  void initState() {
    super.initState();
    _touchActivity();
    refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refreshRemoteData());
    });
    unawaited(_watchConnectivity());
    unawaited(_bootstrap());
  }

  Future<void> _watchConnectivity() async {
    final connectivity = Connectivity();
    final current = await connectivity.checkConnectivity();
    if (mounted) setState(() => online = _hasConnection(current));
    connectivitySubscription = connectivity.onConnectivityChanged.listen((value) {
      if (!_hasConnection(value)) {
        reconnectTimer?.cancel();
        if (mounted) setState(() { online = false; recentlyReconnected = false; });
      } else {
        // A Wi-Fi/mobile link alone does not prove that WordPress is reachable.
        unawaited(_refreshRemoteData());
      }
    });
  }

  bool _hasConnection(List<ConnectivityResult> values) =>
      values.any((value) => value != ConnectivityResult.none);

  Future<void> _syncPending() async {
    final client = api;
    if (preview || client == null || !online) {
      pendingOperations = await sessions.pendingOperationCount();
      return;
    }
    final pending = await sessions.pendingOperations();
    if (pending.isEmpty) {
      if (mounted) setState(() => pendingOperations = 0);
      return;
    }
    try {
      final result = await client.sync(pending);
      final items = (result['items'] as List?) ?? const [];
      final rejected = <String>{};
      for (final item in items.whereType<Map>()) {
        if (item['success'] != true) continue;
        final localId = item['local_id']?.toString();
        if (localId != null && localId.isNotEmpty) rejected.add(localId);
      }
      final remaining = pending
          .where((item) => !rejected.contains(item['local_id']?.toString()))
          .toList();
      await sessions.savePendingOperations(remaining);
      await sessions.markSynced();
      final synced = await sessions.lastSyncAt;
      if (mounted) {
        setState(() {
          pendingOperations = remaining.length;
          lastSyncAt = synced;
          online = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => pendingOperations = pending.length);
    }
  }

  Future<void> _manualSync() async {
    if (!online) {
      if (mounted) {
        messengerKey.currentState?.showSnackBar(const SnackBar(
          content: Text('Sin conexión. La sincronización se reintentará automáticamente.'),
        ));
      }
      return;
    }
    setState(() {
      busy = true;
      syncing = true;
    });
    await _refreshRemoteData();
    if (mounted) {
      setState(() {
        busy = false;
        syncing = false;
      });
      messengerKey.currentState?.showSnackBar(SnackBar(
        content: Text(pendingOperations == 0
            ? 'Sincronización completada.'
            : '$pendingOperations operación(es) siguen pendientes.'),
      ));
    }
    if (!mounted) syncing = false;
  }

  Future<void> _queueOfflineOperation({
    required int eventId,
    required int? journeyId,
    required int ticketId,
    required String action,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc();
    final localId = 'local-${now.microsecondsSinceEpoch}';
    await sessions.queueOperation({
      'local_id': localId,
      'event_id': eventId,
      if (journeyId != null) 'journey_id': journeyId,
      'ticket_id': ticketId,
      'action': action,
      'idempotency_key': _idempotencyKey(deviceId),
      'client_created_at': now.toIso8601String(),
    });
    final count = await sessions.pendingOperationCount();
    if (mounted) {
      setState(() {
        pendingOperations = count;
        online = false;
      });
    }
  }

  Future<Decision?> _offlineScan(String raw) async {
    final event = selectedEvent;
    if (event == null || !event.isOwned) return null;
    final cached = await sessions.attendeeCache(event.id, journeyId);
    final needle = raw.trim().toUpperCase();
    Map<String, dynamic>? match;
    for (final item in cached) {
      final code = (item['code'] ?? item['entry_number'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      if (code.isNotEmpty && code == needle) {
        match = item;
        break;
      }
    }
    if (match == null) {
      return const Decision(
        Tone.bad,
        'Entrada no disponible sin conexión',
        'No existe una copia local de este QR. Conéctate para validarlo.',
      );
    }
    final status = (match['status'] ?? 'registered').toString();
    final alreadyIn = status == 'checked_in' || status == 'reentry';
    final ticketId = int.tryParse(
      (match['ticket_id'] ?? match['id'] ?? '').toString(),
    );
    return Decision(
      Tone.warn,
      alreadyIn ? 'Entrada registrada localmente' : 'Entrada disponible offline',
      alreadyIn
          ? 'Puedes registrar una salida cuando se recupere la conexión.'
          : 'El ingreso quedará pendiente de sincronización.',
      name: match['name']?.toString(),
      rut: match['masked_rut']?.toString(),
      ticketId: ticketId,
      checkout: alreadyIn,
      confirmEntry: !alreadyIn,
    );
  }

  Future<void> _refreshRemoteData() async {
    if (preview || !authed || api == null) return;
    final wasOffline = !online;
    try {
      await _syncPending();
      final events = await api!.events();
      if (!mounted) return;
      setState(() {
        remoteEvents = events;
        for (final item in events) {
          if (item.id == selectedEvent?.id) {
            selectedEvent = item;
            selectedJourney = _journeyForId(item, journeyId);
            break;
          }
        }
      });
      final event = selectedEvent;
      if (event != null) {
        if (event.isOwned) {
          final summary = await api!.summary(event.id, journeyId: journeyId);
          if (!mounted) return;
          setState(() => remoteSummary = summary);
          if (view == View.people) await _loadPeople();
        } else if (view == View.captures) {
          await _loadCaptures();
        }
      }
      await sessions.markSynced();
      final synced = await sessions.lastSyncAt;
      // Device metadata is optional for older plugin installations. A 404
      // must never turn a successful event sync into an offline state.
      try {
        final status = await api!.deviceStatus();
        final statusOperator = status['operator'] is Map
            ? Map<String, dynamic>.from(status['operator'] as Map)
            : const <String, dynamic>{};
        final remoteRole = (status['role'] ?? status['user_role'] ?? statusOperator['role'])?.toString();
        if (remoteRole != null && remoteRole.isNotEmpty && remoteRole != operatorRole && mounted) {
          setState(() { operatorRole = remoteRole; profileChanged = true; });
        }
        offlineMaxMinutes = (status['max_offline_age_minutes'] as num?)?.toInt() ?? 30;
      } on DigniApiException catch (error) {
        if (error.statusCode != 404) rethrow;
      }
      final pendingCount = await sessions.pendingOperationCount();
      if (mounted) {
        setState(() {
          online = true;
          lastSyncAt = synced;
          pendingOperations = pendingCount;
          if (wasOffline) recentlyReconnected = true;
        });
        if (wasOffline) {
          reconnectTimer?.cancel();
          reconnectTimer = Timer(const Duration(seconds: 6), () {
            if (mounted) setState(() => recentlyReconnected = false);
          });
          unawaited(_syncPending());
        }
      }
    } on DigniApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode != null) {
        // An HTTP error is a response from the server, not loss of internet.
        setState(() { online = true; message = error.message; });
      } else {
        final synced = await sessions.lastSyncAt;
        if (mounted) setState(() { online = false; lastSyncAt = synced; });
      }
    } catch (_) {
      if (!mounted) return;
      final synced = await sessions.lastSyncAt;
      setState(() { online = false; lastSyncAt = synced; });
    }
  }

  Future<void> _bootstrap() async {
    final splashDelay =
        Future<void>.delayed(const Duration(milliseconds: 1200));
    var restored = false;
    pendingOperations = await sessions.pendingOperationCount();

    if (preview) {
      restored = await sessions.previewSessionValid();
      operatorName = 'Operador DIGNI';
      operatorRole = 'operator';
    } else if (api != null) {
      if (await sessions.accessStillValid()) {
        restored = true;
      } else if (await sessions.refreshStillValid()) {
        restored = await api!.refresh();
      }
      if (restored) {
        final savedOperator = await sessions.operator();
        operatorName = savedOperator['name'] ?? operatorName;
        operatorRole = savedOperator['role'] ?? operatorRole;
        try {
          remoteEvents = await api!.events();
          await sessions.markSynced();
          lastSyncAt = await sessions.lastSyncAt;
        } catch (_) {
          // Keep the valid local session and show a stale/offline banner while
          // the network recovers.
          online = false;
          lastSyncAt = await sessions.lastSyncAt;
        }
      }
    }

    await splashDelay;
    if (!mounted) return;
    setState(() {
      authed = restored;
      view = restored ? View.events : View.login;
    });
  }

  @override
  void dispose() {
    autoReturn?.cancel();
    refreshTimer?.cancel();
    inactivityTimer?.cancel();
    reconnectTimer?.cancel();
    searchDebounce?.cancel();
    connectivitySubscription?.cancel();
    scannerController.dispose();
    player.dispose();
    email.dispose();
    pin.dispose();
    searchController.dispose();
    peopleSearchFocus.dispose();
    twoFactorCode.dispose();
    courtesyName.dispose();
    courtesyRut.dispose();
    courtesyEmail.dispose();
    courtesyPhone.dispose();
    courtesyRegion.dispose();
    courtesyCommune.dispose();
    super.dispose();
  }

  void go(View next) {
    _touchActivity();
    autoReturn?.cancel();
    if (!authed && next != View.login && next != View.splash) next = View.login;
    if (!own && (next == View.scanner || next == View.people)) next = View.external;
    if (own && next == View.captures) next = View.own;
    if (own && next == View.scanner &&
        (selectedEvent == null || !_eventAvailableToday(selectedEvent!) ||
            _journeyStatus() != 'JORNADA ABIERTA')) {
      next = View.own;
    }
    if (next != View.result && next != View.courtesy) activePerson = null;
    setState(() {
      view = next;
      message = '';
      search = '';
      searchController.clear();
    });
    if (!preview && next == View.people) unawaited(_loadPeople());
    if (!preview && next == View.captures) unawaited(_loadCaptures());
  }

  Future<void> authenticate() async {
    if (busy) return;
    if (twoFactorChallenge != null) {
      await _verifyTwoFactor();
      return;
    }
    final mail = email.text.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(mail) ||
        !RegExp(r'^\d{6}$').hasMatch(pin.text)) {
      setState(() =>
          message = 'Ingresa un correo válido y un PIN de seis dígitos.');
      return;
    }

    setState(() {
      busy = true;
      message = '';
    });

    try {
      if (preview) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (mail != 'demo@digni.cl' || pin.text != '123456') {
          throw DigniApiException('Credenciales de preview incorrectas.');
        }
        await sessions.savePreviewSession(
          duration: const Duration(minutes: 30),
        );
      } else {
        final client = api;
        if (client == null) {
          throw DigniApiException(
            'Servidor DIGNI no configurado en esta compilación.',
          );
        }
        final previousRole = (await sessions.operator())['role'];
        final deviceId = await sessions.ensureDeviceId();
        final session = await client.login(
          email: mail,
          pin: pin.text,
          deviceId: deviceId,
          deviceName: await _deviceName(),
          appVersion: '1.1.4',
        );
        operatorName = session.operatorName;
        operatorRole = session.operatorRole;
        profileChanged = previousRole != null && previousRole != session.operatorRole;
        remoteEvents = await client.events();
        await sessions.markSynced();
        lastSyncAt = await sessions.lastSyncAt;
        online = true;
      }

      if (!mounted) return;
      setState(() {
        authed = true;
        busy = false;
        view = View.events;
      });
      _touchActivity();
    } on DigniTwoFactorRequired catch (error) {
      if (!mounted) return;
      setState(() {
        twoFactorChallenge = error.challengeId;
        busy = false;
        message = error.message;
      });
    } on DigniApiException catch (error) {
      if (!mounted) return;
      setState(() {
        busy = false;
        message = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        busy = false;
        message = 'No fue posible conectar con DIGNI. Intenta nuevamente.';
      });
    }
  }

  Future<void> _verifyTwoFactor() async {
    final client = api;
    final challenge = twoFactorChallenge;
    if (client == null || challenge == null ||
        !RegExp(r'^\d{6}$').hasMatch(twoFactorCode.text.trim())) {
      setState(() => message = 'Ingresa un código de seis dígitos.');
      return;
    }
    setState(() { busy = true; message = ''; });
    try {
      final deviceId = await sessions.ensureDeviceId();
      final session = await client.verify2fa(
        challengeId: challenge,
        code: twoFactorCode.text.trim(),
        deviceId: deviceId,
      );
      operatorName = session.operatorName;
      operatorRole = session.operatorRole;
      profileChanged = true;
      remoteEvents = await client.events();
      await sessions.markSynced();
      if (!mounted) return;
      setState(() {
        twoFactorChallenge = null;
        twoFactorCode.clear();
        authed = true;
        busy = false;
        view = View.events;
      });
      _touchActivity();
    } on DigniApiException catch (error) {
      if (!mounted) return;
      setState(() { busy = false; message = error.message; });
    } catch (_) {
      if (!mounted) return;
      setState(() { busy = false; message = 'No fue posible verificar el código.'; });
    }
  }

  Future<void> logout() async {
    if (view == View.signingOut) return;
    if (mounted) setState(() => view = View.signingOut);
    inactivityTimer?.cancel();
    if (preview) {
      await sessions.clear();
    } else if (api != null) {
      await api!.logout();
    } else {
      await sessions.clear();
    }
    if (!mounted) return;
    setState(() {
      authed = false;
      selectedEvent = null;
      selectedJourney = null;
      journeyChoices.clear();
      remoteEvents = const [];
      operatorName = 'Operador DIGNI';
      operatorRole = 'operator';
      profileChanged = false;
      remoteSummary = const {};
      remotePeople = const [];
      remoteCaptures = const [];
      used.clear();
      pin.clear();
      twoFactorCode.clear();
      twoFactorChallenge = null;
      view = View.login;
    });
  }

  void event(bool isOwned) {
    setState(() {
      own = isOwned;
      selectedEvent = null;
      selectedJourney = null;
      remoteSummary = const {};
    });
    go(isOwned ? View.own : View.external);
  }

  Future<void> selectRemoteEvent(DigniEvent event) async {
    final chosenId = journeyChoices[event.id] ?? _todayJourneyId(event);
    setState(() {
      selectedEvent = event;
      selectedJourney = _journeyForId(event, chosenId);
      journeyChoices[event.id] = chosenId;
      own = event.isOwned;
      busy = true;
      remoteSummary = const {};
      remoteCaptures = const [];
      message = '';
    });
    if (event.isOwned && !_eventAvailableToday(event)) {
      if (!mounted) return;
      setState(() => busy = false);
      go(View.own);
      return;
    }
    try {
      if (api != null) {
        if (event.isOwned) {
          remoteSummary = await api!.summary(event.id, journeyId: journeyId);
        }
        await sessions.markSynced();
        lastSyncAt = await sessions.lastSyncAt;
        online = true;
      }
    } catch (_) {
      remoteSummary = const {};
      online = false;
      lastSyncAt = await sessions.lastSyncAt;
    }
    if (!mounted) return;
    setState(() => busy = false);
    go(event.isOwned ? View.own : View.external);
    if (!preview && event.isOwned) unawaited(_loadPeople());
    if (!preview && !event.isOwned) unawaited(_loadCaptures());
  }

  Future<void> _loadPeople() async {
    final event = selectedEvent;
    final client = api;
    if (preview || event == null || client == null || !event.isOwned) return;
    final request = ++peopleRequest;
    if (mounted) setState(() => peopleLoading = true);
    try {
      final items = await client.attendees(
        event.id,
        journeyId: journeyId,
        query: search,
      );
      if (!mounted || request != peopleRequest) return;
      setState(() {
        remotePeople = items;
        peopleLoading = false;
      });
      if (search.isEmpty) {
        await sessions.saveAttendeeCache(
          event.id,
          journeyId,
          items.map((item) => item.toJson()).toList(),
        );
      }
    } on DigniApiException catch (error) {
      if (!mounted || request != peopleRequest) return;
      setState(() { message = error.message; online = true; peopleLoading = false; });
    } catch (_) {
      if (!mounted || request != peopleRequest) return;
      setState(() { message = 'No pudimos cargar la lista de asistentes.'; online = false; peopleLoading = false; });
    }
  }

  Future<void> _loadCaptures() async {
    final event = selectedEvent;
    final client = api;
    if (preview || event == null || client == null || event.isOwned) return;
    try {
      final items = await client.captures(event.id, query: search);
      if (!mounted) return;
      setState(() { remoteCaptures = items; message = ''; online = true; });
    } on DigniApiException catch (error) {
      if (!mounted) return;
      setState(() { message = error.message; online = true; });
    } catch (_) {
      if (!mounted) return;
      setState(() { message = 'No pudimos cargar los contactos capturados.'; online = false; });
    }
  }

  String _idempotencyKey(String deviceId) {
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    return '$deviceId-${DateTime.now().microsecondsSinceEpoch}-$random';
  }

  bool _needsEntryData(DigniValidation value) {
    if (value.needsData || value.courtesy || value.outcome == 'pending_data') return true;
    if (value.outcome == 'requires_supervisor' && value.status == 'confirmed') return true;
    if (value.status != 'confirmed') return false;
    final text = '${value.outcome} ${value.title} ${value.message}'.toLowerCase();
    return text.contains('dato') || text.contains('cortes') ||
        text.contains('sin asign') || text.contains('incomplet') ||
        text.contains('pendiente');
  }

  String _displayAccessTime(String raw) {
    var value = raw.trim().replaceFirst(' ', 'T');
    // WordPress stores audit/access timestamps in UTC without an offset.
    // Treat that explicit server format as UTC, then let Android apply the
    // device timezone (including Santiago summer/winter changes).
    if (value.isNotEmpty &&
        !value.endsWith('Z') &&
        !RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value)) {
      value = '${value}Z';
    }
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return raw;
    final hh = parsed.hour.toString().padLeft(2, '0');
    final mm = parsed.minute.toString().padLeft(2, '0');
    final dd = parsed.day.toString().padLeft(2, '0');
    final mo = parsed.month.toString().padLeft(2, '0');
    return '$hh:$mm · $dd/$mo/${parsed.year}';
  }

  Future<void> _scan(String raw) async {
    if (!authed || !own || view != View.scanner || busy) return;
    activePerson = null;
    if (selectedEvent == null || !_eventAvailableToday(selectedEvent!) ||
        _journeyStatus() != 'JORNADA ABIERTA') {
      _showDecision(const Decision(Tone.bad, 'Evento cerrado',
        'El escaneo está disponible solo durante el horario de la jornada.'));
      return;
    }

    if (preview) {
      _checkPreview(raw);
      return;
    }

    final event = selectedEvent;
    final client = api;
    if (event == null || client == null || !event.isOwned) return;

    await HapticFeedback.mediumImpact();
    setState(() => busy = true);
    try {
      if (!online) {
        final offline = await _offlineScan(CivilQr.normalizePayload(raw));
        if (offline != null) {
          _showDecision(offline);
          if (offline.tone == Tone.bad) await _rejectionFeedback();
        }
        return;
      }
      final deviceId = await sessions.ensureDeviceId();
      final civil = CivilQr.identity(raw);
      final payload = CivilQr.normalizePayload(raw);
      final validation = await client.validate(
        eventId: event.id,
        journeyId: journeyId,
        code: payload,
        rut: civil['rut'],
        name: civil['name'],
        qrData: civil.isEmpty ? null : raw,
        deviceId: deviceId,
      );
      if ((validation.outcome == 'valid' ||
              validation.outcome == 'approved') &&
          validation.ticketId != null) {
        // A first valid scan is an admission, not a second confirmation step.
        // Register it immediately so the operator receives the green ticket,
        // sound and access number in the same flow.
        _showDecision(Decision(
          Tone.good,
          validation.title.isEmpty ? 'Entrada válida' : validation.title,
          validation.message.isEmpty ? 'Registrando ingreso…' : validation.message,
          name: validation.name,
          rut: validation.maskedRut,
          ticketId: validation.ticketId,
          entryNumber: validation.entryNumber,
          confirmEntry: true,
        ));
        await confirmEntry();
      } else {
        await _showServerDecision(validation);
      }
    } on DigniApiException catch (error) {
      if (error.statusCode == null || !online) {
        if (mounted) setState(() => online = false);
        final offline = await _offlineScan(CivilQr.normalizePayload(raw));
        if (offline != null) {
          _showDecision(offline);
          if (offline.tone == Tone.bad) await _rejectionFeedback();
        }
        return;
      }
      _showDecision(Decision(Tone.bad, 'No se pudo validar', error.message));
      await _rejectionFeedback();
    } catch (_) {
      _showDecision(const Decision(Tone.bad, 'No se pudo validar',
        'Revisa la conexión e inténtalo nuevamente.'));
      await _rejectionFeedback();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _checkPreview(String raw) {
    final v = raw.trim().toUpperCase();
    late final Decision result;
    if (v == 'DEMO-OK') {
      result = used.add(v)
          ? const Decision(Tone.good, 'Acceso autorizado',
              'Ingreso registrado en la simulación.',
              name: 'Carolina Soto', rut: '19.***.**1-2', ticketId: 10001)
          : const Decision(Tone.warn, 'Entrada ya utilizada',
              'El primer ingreso ya figura en el preview.',
              name: 'Carolina Soto', rut: '19.***.**1-2',
              ticketId: 10001, reenter: true);
    } else if (v == 'DEMO-USED') {
      result = const Decision(Tone.warn, 'Entrada ya utilizada',
        'Primer ingreso a las 10:32. Requiere confirmar el reingreso.',
        name: 'Carolina Soto', rut: '19.***.**1-2',
        ticketId: 10001, reenter: true);
    } else if (v == 'DEMO-OTHER') {
      result = const Decision(Tone.warn, 'Otra jornada',
        'Corresponde a otra fecha. No se registró el ingreso.',
        name: 'Carolina Soto', rut: '19.***.**1-2', ticketId: 10001);
    } else if (v == 'DEMO-ID') {
      result = const Decision(Tone.warn, 'Verificar identidad',
        'El documento no coincide. Requiere revisión de supervisor.',
        name: 'Carolina Soto', rut: '19.***.**1-2',
        ticketId: 10001, supervisor: true);
    } else {
      result = const Decision(Tone.bad, 'Entrada no encontrada',
        'Favor verifique con soporte.');
    }
    _showDecision(result);
    if (result.tone == Tone.good) unawaited(_approvalFeedback());
  }

  Future<void> _showServerDecision(DigniValidation value) async {
    var tone = Tone.bad;
    if (value.outcome == 'approved' ||
        value.outcome == 'checked_out' ||
        value.outcome == 'checked_in' ||
        value.outcome == 'reentry_approved') {
      tone = Tone.good;
    } else if (value.outcome == 'pending_data' ||
        value.needsData ||
        value.courtesy ||
        value.outcome == 'already_used' ||
        value.outcome == 'other_journey' ||
        value.outcome == 'identity_mismatch' ||
        value.outcome == 'identity_review' ||
        value.requiresSupervisor) {
      tone = Tone.warn;
    }

    final needsData = _needsEntryData(value);
    String? usedAt = value.usedAt;
    String? usedBy = value.usedBy;
    if (value.outcome == 'already_used' && value.ticketId != null) {
      try {
        final history = await api?.attendeeHistory(value.ticketId!);
        final prior = (history ?? const <Map<String, dynamic>>[])
            .where((item) {
              final action = (item['action'] ?? item['type'] ?? '').toString();
              return action == 'checkin' || action == 'entered' ||
                  action == 'scanner_checkin';
            })
            .toList();
        if (prior.isNotEmpty) {
          final item = prior.last;
          usedAt = (item['created_at'] ?? '').toString();
          usedBy = (item['operator_name'] ?? '').toString();
        }
      } catch (_) {
        // History is role-protected by the plugin; the validation result is
        // still useful even when the operator cannot read the audit trail.
      }
    }
    var message = value.message;
    if (usedAt != null && usedAt!.isNotEmpty) {
      final by = usedBy == null || usedBy!.isEmpty ? '' : ' · $usedBy';
      message = '$message\nIngresó a las ${_displayAccessTime(usedAt!)}$by';
    }
    _showDecision(Decision(
      tone,
      value.title,
      message,
      name: value.name,
      rut: value.maskedRut,
      ticketId: value.ticketId,
      reenter: value.canReenter,
      supervisor: value.requiresSupervisor && !needsData,
      courtesy: needsData,
      checkout: value.outcome == 'already_used',
      entryNumber: value.entryNumber ?? value.accessNumber?.toString(),
      accessNumber: value.accessNumber,
      confirmEntry: false,
      usedAt: usedAt,
      usedBy: usedBy,
    ));
    if (tone == Tone.good) {
      await _approvalFeedback();
    } else if (tone == Tone.bad) {
      await _rejectionFeedback();
    }
  }

  void _showDecision(Decision result) {
    setState(() {
      decision = result;
      view = View.result;
    });
  }

  void _openCourtesyForm() {
    courtesyName.text = decision?.name ?? '';
    courtesyRut.clear();
    courtesyEmail.clear();
    courtesyPhone.clear();
    courtesyRegion.text = 'Región Metropolitana';
    courtesyCommune.text = 'Santiago';
    courtesyError = '';
    go(View.courtesy);
  }

  Future<void> _submitCourtesyForm() async {
    if (busy || courtesyFormKey.currentState?.validate() != true) return;
    final event = selectedEvent;
    final client = api;
    if (event == null || client == null || decision?.ticketId == null) {
      setState(() => courtesyError = 'No encontramos la entrada. Vuelve a escanearla.');
      return;
    }
    if (!online) {
      setState(() => courtesyError = 'Necesitas conexión para guardar los datos de esta entrada.');
      return;
    }
    setState(() { busy = true; courtesyError = ''; });
    try {
      final deviceId = await sessions.ensureDeviceId();
      final assignment = await client.assignCourtesy(
        ticketId: decision!.ticketId!, name: courtesyName.text.trim(),
        email: courtesyEmail.text.trim(), phone: courtesyPhone.text.trim(), rut: courtesyRut.text.trim(), region: courtesyRegion.text.trim(),
        commune: courtesyCommune.text.trim(),
      );
      if (!mounted) return;
      if (_journeyStatus() == 'JORNADA ABIERTA') {
        final result = await client.checkIn(
          eventId: event.id, journeyId: journeyId,
          ticketId: decision!.ticketId!, deviceId: deviceId,
          idempotencyKey: _idempotencyKey(deviceId),
        );
        await _showServerDecision(result);
      } else {
        _showDecision(Decision(Tone.warn, 'Datos guardados',
          'La entrada quedó completa. El ingreso podrá registrarse cuando abra la jornada.',
          name: courtesyName.text.trim(), ticketId: decision!.ticketId!,
          entryNumber: (assignment['entry_number'] ?? decision?.entryNumber)?.toString()));
      }
      unawaited(_loadPeople());
    } on DigniApiException catch (error) {
      if (mounted) setState(() => courtesyError = error.message);
      await _rejectionFeedback();
    } catch (_) {
      if (mounted) setState(() => courtesyError = 'No se pudo conectar. Los datos siguen en el formulario para reintentar.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirmEntry() async {
    final current = decision;
    final event = selectedEvent;
    final client = api;
    if (current == null || !current.confirmEntry || event == null ||
        current.ticketId == null || !_eventAvailableToday(event)) return;
    final deviceId = await sessions.ensureDeviceId();
    if (!online || client == null) {
      await _queueOfflineOperation(
        eventId: event.id,
        journeyId: journeyId,
        ticketId: current.ticketId!,
        action: 'checkin',
        deviceId: deviceId,
      );
      _showDecision(Decision(
        Tone.warn,
        'Ingreso guardado sin conexión',
        'Quedó pendiente de sincronización. Se enviará al recuperar internet.',
        name: current.name,
        rut: current.rut,
        ticketId: current.ticketId,
      ));
      return;
    }
    setState(() => busy = true);
    try {
      final result = await client.checkIn(
        eventId: event.id,
        journeyId: journeyId,
        ticketId: current.ticketId!,
        deviceId: deviceId,
        idempotencyKey: _idempotencyKey(deviceId),
      );
      await _showServerDecision(result);
    } on DigniApiException catch (error) {
      if (error.statusCode == null || !online) {
        await _queueOfflineOperation(
          eventId: event.id,
          journeyId: journeyId,
          ticketId: current.ticketId!,
          action: 'checkin',
          deviceId: deviceId,
        );
        _showDecision(Decision(
          Tone.warn,
          'Ingreso guardado sin conexión',
          'Quedó pendiente de sincronización. Se enviará al recuperar internet.',
          name: current.name,
          rut: current.rut,
          ticketId: current.ticketId,
        ));
        return;
      }
      _showDecision(Decision(Tone.bad, 'No se pudo registrar', error.message));
      await _rejectionFeedback();
    } catch (_) {
      await _queueOfflineOperation(
        eventId: event.id,
        journeyId: journeyId,
        ticketId: current.ticketId!,
        action: 'checkin',
        deviceId: deviceId,
      );
      _showDecision(Decision(
        Tone.warn,
        'Ingreso guardado sin conexión',
        'Quedó pendiente de sincronización. Se enviará al recuperar internet.',
        name: current.name,
        rut: current.rut,
        ticketId: current.ticketId,
      ));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirmCheckout() async {
    final current = decision;
    final event = selectedEvent;
    if (current == null || !current.checkout || event == null ||
        current.ticketId == null || !_eventAvailableToday(event)) return;
    final client = api;
    final deviceId = await sessions.ensureDeviceId();
    if (!online || client == null) {
      await _queueOfflineOperation(
        eventId: event.id,
        journeyId: journeyId,
        ticketId: current.ticketId!,
        action: 'checkout',
        deviceId: deviceId,
      );
      _showDecision(Decision(
        Tone.warn,
        'Salida guardada sin conexión',
        'Quedó pendiente de sincronización. Se enviará al recuperar internet.',
        name: current.name,
        rut: current.rut,
        ticketId: current.ticketId,
      ));
      return;
    }
    setState(() => busy = true);
    try {
      final result = await client.checkout(
        eventId: event.id,
        journeyId: journeyId,
        ticketId: current.ticketId!,
        deviceId: deviceId,
        idempotencyKey: _idempotencyKey(deviceId),
      );
      await _showServerDecision(result);
    } on DigniApiException catch (error) {
      if (error.statusCode == null || !online) {
        await _queueOfflineOperation(
          eventId: event.id,
          journeyId: journeyId,
          ticketId: current.ticketId!,
          action: 'checkout',
          deviceId: deviceId,
        );
        _showDecision(Decision(
          Tone.warn,
          'Salida guardada sin conexión',
          'Quedó pendiente de sincronización. Se enviará al recuperar internet.',
          name: current.name,
          rut: current.rut,
          ticketId: current.ticketId,
        ));
        return;
      }
      _showDecision(Decision(Tone.bad, 'No se pudo registrar la salida', error.message));
      await _rejectionFeedback();
    } catch (_) {
      await _queueOfflineOperation(
        eventId: event.id,
        journeyId: journeyId,
        ticketId: current.ticketId!,
        action: 'checkout',
        deviceId: deviceId,
      );
      _showDecision(Decision(
        Tone.warn,
        'Salida guardada sin conexión',
        'Quedó pendiente de sincronización. Se enviará al recuperar internet.',
        name: current.name,
        rut: current.rut,
        ticketId: current.ticketId,
      ));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirmReentry() async {
    final current = decision;
    if (current == null || !current.reenter || !own) return;

    if (preview) {
      _showDecision(Decision(
        Tone.good,
        'Reingreso autorizado',
        'Reingreso simulado correctamente.',
        name: current.name,
        rut: current.rut,
        ticketId: current.ticketId,
      ));
      await _approvalFeedback();
      return;
    }

    final event = selectedEvent;
    final client = api;
    if (event == null || current.ticketId == null || !_eventAvailableToday(event)) return;
    final deviceId = await sessions.ensureDeviceId();
    if (!online || client == null) {
      await _queueOfflineOperation(
        eventId: event.id,
        journeyId: journeyId,
        ticketId: current.ticketId!,
        action: 'reentry',
        deviceId: deviceId,
      );
      _showDecision(Decision(
        Tone.warn,
        'Reingreso guardado sin conexión',
        'Quedó pendiente de sincronización. Se enviará al recuperar internet.',
        name: current.name,
        rut: current.rut,
        ticketId: current.ticketId,
      ));
      return;
    }

    setState(() => busy = true);
    try {
      final result = await client.checkIn(
        eventId: event.id,
        journeyId: journeyId,
        ticketId: current.ticketId!,
        deviceId: deviceId,
        idempotencyKey: _idempotencyKey(deviceId),
        reentry: true,
      );
      await _showServerDecision(result);
    } on DigniApiException catch (error) {
      if (error.statusCode == null || !online) {
        await _queueOfflineOperation(
          eventId: event.id,
          journeyId: journeyId,
          ticketId: current.ticketId!,
          action: 'reentry',
          deviceId: deviceId,
        );
        _showDecision(Decision(
          Tone.warn,
          'Reingreso guardado sin conexión',
          'Quedó pendiente de sincronización. Se enviará al recuperar internet.',
          name: current.name,
          rut: current.rut,
          ticketId: current.ticketId,
        ));
        return;
      }
      _showDecision(Decision(Tone.bad, 'No se pudo registrar', error.message));
      await _rejectionFeedback();
    } catch (_) {
      await _queueOfflineOperation(
        eventId: event.id,
        journeyId: journeyId,
        ticketId: current.ticketId!,
        action: 'reentry',
        deviceId: deviceId,
      );
      _showDecision(Decision(
        Tone.warn,
        'Reingreso guardado sin conexión',
        'Quedó pendiente de sincronización. Se enviará al recuperar internet.',
        name: current.name,
        rut: current.rut,
        ticketId: current.ticketId,
      ));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _approvalFeedback() async {
    await HapticFeedback.mediumImpact();
    try {
      await player.stop();
      await player.play(AssetSource('sounds/approved.wav'), volume: 0.9);
    } catch (_) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  Future<void> _rejectionFeedback() async {
    await HapticFeedback.heavyImpact();
    try {
      await player.stop();
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  Widget brand({bool light = false, double width = 118}) {
    final asset = light
        ? 'assets/brand/DIGNI_BLANCO.png'
        : 'assets/brand/DIGNI-NEGRO.png';
    return Image.asset(
      asset,
      key: ValueKey(asset),
      width: width,
      fit: BoxFit.contain,
      // Do not revive the obsolete square-D wordmark when an asset lookup
      // fails. The production bundle includes both official wordmarks.
      errorBuilder: (_, __, ___) => SizedBox(width: width, height: 34),
    );
  }

  Widget label(String value) => Text(value, style: TextStyle(
    color: actionInk, fontSize: 10, fontWeight: FontWeight.w800));
  Widget title(String value) => Text(value, style: TextStyle(color: ink,
    fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -.9));
  Widget sub(String value) => Text(value,
    style: TextStyle(color: muted, fontSize: 12, height: 1.5));

  Widget panel(Widget child, {Color? color, Gradient? gradient, EdgeInsets? padding}) => Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(17),
    decoration: BoxDecoration(color: gradient == null ? (color ?? surface) : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(23),
      border: Border.all(color: color == null ? border : Colors.transparent)),
    child: child);

  Widget badge(String value, Color bgColor, Color fgColor) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(99)),
    child: Text(value, style: TextStyle(color: fgColor,
      fontSize: 10, fontWeight: FontWeight.w800)));

  Widget attendeeBadge(String value) {
    final success = value == 'Ingresó' || value == 'Reingreso';
    final cancelled = value == 'Anulada';
    final foreground = success ? statusInk(good) : cancelled ? statusInk(red) : muted;
    final background = success
        ? (dark ? const Color(0xFF173B2C) : const Color(0xFFE1F7E9))
        : cancelled
            ? (dark ? const Color(0xFF4B211E) : const Color(0xFFFCEAE8))
            : surface;
    return badge(value, background, foreground);
  }

  Widget logo(bool isOwn, {String? logoUrl}) {
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: 50,
          height: 50,
          color: Colors.white,
          child: Image.network(
            logoUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => logo(isOwn),
          ),
        ),
      );
    }
    return Container(
      width: 50,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isOwn ? Colors.white : const Color(0xFFF4F4F5),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        isOwn ? 'MAKITA' : 'EVENTO',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: isOwn ? 9 : 8,
          fontWeight: FontWeight.w900,
          color: isOwn ? brandRed : deep,
        ),
      ),
    );
  }

  Widget content(List<Widget> items) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 26), children: items);

  String _offlineLabel() {
    final value = lastSyncAt;
    final pending = pendingOperations > 0 ? ' · $pendingOperations pendiente(s)' : '';
    if (value == null) return 'Sin conexión · todavía no hay una sincronización registrada$pending';
    final local = value.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return 'Sin conexión · datos hasta las $hh:$mm del $dd/$mo/${local.year}$pending';
  }

  Widget _offlineBanner() => Container(
    width: double.infinity,
    color: dark ? const Color(0xFF3D3017) : const Color(0xFFFFF2D9),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    child: Row(children: [
      Icon(Icons.cloud_off_rounded, size: 17, color: statusInk(amber)),
      const SizedBox(width: 8),
      Expanded(child: Text(_offlineLabel(), style: TextStyle(
        color: statusInk(amber), fontSize: 11, fontWeight: FontWeight.w800))),
    ]),
  );

  Widget _reconnectedBanner() => Container(
    width: double.infinity,
    color: dark ? const Color(0xFF123D25) : const Color(0xFFE6F6EC),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    child: Row(children: [
      Icon(Icons.cloud_done_rounded, size: 17, color: statusInk(good)),
      const SizedBox(width: 8),
      Expanded(child: Text('Conexión recuperada · datos actualizados',
        style: TextStyle(color: statusInk(good), fontSize: 11,
          fontWeight: FontWeight.w800))),
    ]),
  );

  Future<void> launchLegalTerms() async {
    final uri = Uri.parse('https://www.makita.cl/terminos-y-privacidad-digni');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _roleLabel() {
    final value = operatorRole.toLowerCase();
    if (value.contains('super')) return 'Supervisor';
    if (value.contains('admin')) return 'Administrador';
    return 'Operador';
  }

  void _drawerAction(VoidCallback action) {
    final drawer = scaffoldKey.currentState;
    if (drawer?.isDrawerOpen == true) drawer!.closeDrawer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  Widget _drawer() {
    final eventTitle = preview
        ? (own ? 'Power Tour Rescue' : 'Expo Jardines')
        : selectedEvent?.title;

    Widget drawerItem(IconData icon, String text, VoidCallback onTap,
        {Color? color}) {
      return ListTile(
        leading: Icon(icon, color: color == null ? muted : statusInk(color)),
        title: Text(text, style: TextStyle(
          color: color == null ? ink : statusInk(color), fontWeight: FontWeight.w700)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: onTap,
      );
    }

    return Drawer(
      backgroundColor: surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              brand(light: dark, width: 142),
              const SizedBox(height: 26),
              panel(Row(children: [
                CircleAvatar(
                  backgroundColor: tint,
                  child: Text(_initials(), style: TextStyle(
                    color: actionInk, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(operatorName, style: TextStyle(
                      color: ink, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    sub('${_roleLabel()} · Makita Chile'),
                  ],
                )),
              ])),
              const SizedBox(height: 16),
              drawerItem(Icons.event_outlined, 'Mis eventos', () {
                _drawerAction(() => go(View.events));
              }),
              if (eventTitle != null)
                drawerItem(Icons.home_outlined, 'Evento activo', () {
                  _drawerAction(() => go(own ? View.own : View.external));
                }),
              if (own)
                drawerItem(Icons.people_outline, 'Asistentes', () {
                  _drawerAction(() => go(View.people));
                }),
              if (!own)
                drawerItem(Icons.query_stats_rounded, 'Contactos capturados', () {
                  _drawerAction(() => go(View.captures));
                }),
              drawerItem(
                Icons.sync_rounded,
                pendingOperations > 0
                    ? 'Sincronizar ($pendingOperations)'
                    : 'Sincronizar',
                () {
                  _drawerAction(() => unawaited(_manualSync()));
                },
                color: pendingOperations > 0 ? amber : null,
              ),
              drawerItem(
                dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                dark ? 'Modo claro' : 'Modo oscuro',
                () {
                  _drawerAction(() => setState(() => dark = !dark));
                },
              ),
              drawerItem(Icons.person_outline, 'Mi cuenta', () {
                _drawerAction(() => go(View.account));
              }),
              const Spacer(),
              const Divider(),
              const Divider(),
              drawerItem(Icons.logout_rounded, 'Cerrar sesión', () {
                _drawerAction(() => unawaited(logout()));
              }, color: red),
            ],
          ),
        ),
      ),
    );
  }

  Widget shell(Widget body,
      {bool back = false, View? backTarget, bool nav = false, String active = ''}) {
    return Scaffold(
      key: scaffoldKey,
      drawer: authed ? _drawer() : null,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 12,
        backgroundColor: bg,
        leading: authed
            ? IconButton(
                tooltip: back ? 'Volver' : 'Menú',
                onPressed: back
                    ? () => go(backTarget ?? (own ? View.own : View.external))
                    : () => scaffoldKey.currentState?.openDrawer(),
                icon: Icon(back
                    ? Icons.arrow_back_rounded
                    : Icons.menu_rounded),
              )
            : null,
        title: brand(light: dark, width: 108),
        actions: [
          IconButton(
            tooltip: dark ? 'Modo claro' : 'Modo oscuro',
            onPressed: () => setState(() => dark = !dark),
            icon: Icon(dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined),
          ),
          if (back && authed)
            IconButton(
              tooltip: 'Menú',
              onPressed: () => scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.menu_rounded),
            )
          else if (authed)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: CircleAvatar(
                backgroundColor: Color(0xFFFDE7EC),
                child: Text(_initials(), style: TextStyle(
                  color: deep, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      ),
      body: SafeArea(child: Column(children: [
        if (!preview && !online) _offlineBanner(),
        if (!preview && online && recentlyReconnected) _reconnectedBanner(),
        if (syncing)
          Container(
            width: double.infinity,
            color: dark ? const Color(0xFF35141E) : const Color(0xFFFDE7EC),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(children: [
              const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: brandRed)),
              const SizedBox(width: 10),
              Text('Sincronizando con DIGNI…', style: TextStyle(
                color: actionInk, fontWeight: FontWeight.w800, fontSize: 12)),
            ]),
          ),
        if (preview)
          Container(
            width: double.infinity,
            color: dark
                ? const Color(0xFF504126)
                : const Color(0xFFFFF2D9),
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text(
              'PREVIEW · DATOS FICTICIOS · SIN INGRESOS REALES',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: dark
                    ? const Color(0xFFF9A700)
                    : const Color(0xFF9B6113),
              ),
            ),
          ),
        Expanded(child: body),
      ])),
      bottomNavigationBar: nav
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(15, 0, 15, 12),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: surface,
                    border: Border.all(color: border),
                    borderRadius: BorderRadius.circular(23),
                  ),
                  child: Row(
                    children: (own
                            ? <(IconData, String, View)>[
                                (Icons.home_outlined, 'Inicio', View.own),
                                (Icons.qr_code_scanner_rounded, 'Escanear', View.scanner),
                                (Icons.people_outline, 'Personas', View.people),
                              ]
                            : <(IconData, String, View)>[
                                (Icons.home_outlined, 'Inicio', View.external),
                                (Icons.query_stats_rounded, 'Captados', View.captures),
                                (Icons.event_outlined, 'Evento', View.info),
                              ])
                        .map((item) => Expanded(
                              child: TextButton(
                                onPressed: () => go(item.$3),
                                style: TextButton.styleFrom(
                                  backgroundColor:
                                      active == item.$2 ? tint : Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(item.$1, color:
                                        active == item.$2 ? actionInk : muted),
                                    const SizedBox(height: 4),
                                    Text(item.$2, style: TextStyle(
                                      fontSize: 10,
                                      color: active == item.$2 ? actionInk : muted)),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget splash() => Scaffold(
    backgroundColor: const Color(0xFFDF002E),
    body: SafeArea(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: .72, end: 1),
          duration: const Duration(milliseconds: 950),
          curve: Curves.easeOutBack,
          builder: (_, factor, child) => Opacity(
            opacity: factor.clamp(0, 1),
            child: Transform.scale(scale: factor, child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              brand(light: true, width: 220),
              const SizedBox(height: 10),
              const Text('DEVELOPED BY MAKITA CHILE', style: TextStyle(
                color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              )),
              const SizedBox(height: 39),
              const SizedBox(
                width: 106,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  color: Colors.white,
                  backgroundColor: Color(0x44FFFFFF),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget signingOut() => Scaffold(
    backgroundColor: spaceDark,
    body: SafeArea(child: Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        brand(light: true, width: 190),
        const SizedBox(height: 32),
        const CircularProgressIndicator(color: Colors.white),
        const SizedBox(height: 18),
        const Text('Cerrando sesión…', style: TextStyle(
          color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    ))),
  );

  Widget login() => shell(content([
    const SizedBox(height: 45), title('Qué bueno verte.'),
    const SizedBox(height: 7), sub('Ingresa para preparar tu jornada.'),
    const SizedBox(height: 30),
    panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      label('TU CUENTA DIGNI'), const SizedBox(height: 15),
      TextField(controller: email, keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Correo electrónico',
          prefixIcon: Icon(Icons.alternate_email_rounded))),
      const SizedBox(height: 12),
      TextField(controller: pin, obscureText: true,
        maxLength: 6, keyboardType: TextInputType.number,
        onSubmitted: (_) => authenticate(),
        decoration: const InputDecoration(labelText: 'PIN de seis dígitos',
          counterText: '', prefixIcon: Icon(Icons.lock_outline_rounded))),
      if (twoFactorChallenge != null) ...[
        const SizedBox(height: 12),
        TextField(controller: twoFactorCode, autofocus: true,
          maxLength: 6, keyboardType: TextInputType.number,
          onSubmitted: (_) => authenticate(),
          decoration: const InputDecoration(
            labelText: 'Código de autenticación',
            counterText: '', prefixIcon: Icon(Icons.verified_user_outlined))),
      ],
      if (message.isNotEmpty) Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(message, style: TextStyle(color: statusInk(red), fontSize: 12))),
      const SizedBox(height: 9),
      FilledButton(onPressed: busy ? null : authenticate,
        child: busy ? const SizedBox(width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text(twoFactorChallenge == null
              ? 'Ingresar a DIGNI' : 'Verificar código')),
    ])),
    if (preview) ...[
      const SizedBox(height: 20),
      panel(const Text('PREVIEW: demo@digni.cl · PIN 123456. '
        'La sesión se mantiene 30 minutos aunque cierres la app.')),
    ] else ...[
      const SizedBox(height: 20),
      panel(const Text('La sesión se guarda de forma segura y se renueva '
        'mientras el dispositivo siga autorizado.')),
    ],
  ]));

  Widget eventCard(bool isOwn) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [logo(isOwn), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isOwn ? 'Power Tour Rescue' : 'Expo Jardines',
              style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            sub(isOwn ? 'Makita Chile · Evento propio'
              : 'Makita · Marca participante'),
          ]))]),
      const SizedBox(height: 18),
      badge(isOwn ? 'CONTROL DE ACCESOS' : 'CAPTACIÓN',
        tint, actionInk),
      const SizedBox(height: 18),
      sub(isOwn ? '10 dic · 08:30 a 17:00'
        : '15–18 oct · Parque Bicentenario'),
      const SizedBox(height: 18),
      FilledButton(onPressed: () => event(isOwn),
        child: Text(isOwn ? 'Abrir jornada' : 'Ver captación')),
    ])),
  );

  Widget remoteEventCard(DigniEvent event) {
    final todayId = _todayJourneyId(event);
    final chosenId = journeyChoices.containsKey(event.id)
        ? journeyChoices[event.id] : todayId;
    final chosenJourney = _journeyForId(event, chosenId);
    final available = !event.isOwned || (event.isOpen &&
        chosenJourney != null && chosenJourney['enabled'] != false &&
        _journeyIsToday(chosenJourney));
    final journeyStatus = event.isOwned
        ? _journeyStatusFor(chosenJourney, event) : 'CAPTACIÓN';
    final metadata = <String>[
      if (_journeySchedule(chosenJourney, event.dateLabel).isNotEmpty)
        _journeySchedule(chosenJourney, event.dateLabel),
      '${event.journeys.length} jornada${event.journeys.length == 1 ? '' : 's'}',
      if (event.commune.isNotEmpty) event.commune,
      if (event.region.isNotEmpty) event.region,
      if (event.location.isNotEmpty && event.commune.isEmpty) event.location,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          logo(event.isOwned, logoUrl: event.logoUrl),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(event.title, style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            sub(event.isOwned ? '${event.organizer} · Evento propio' : 'Makita · Marca participante'),
          ])),
          Icon(available ? Icons.check_circle_rounded : Icons.lock_outline,
            color: available ? good : statusInk(red), size: 21),
        ]),
        const SizedBox(height: 15),
        Row(children: [
          Icon(available ? Icons.event_available_rounded : Icons.event_busy_rounded,
            color: available ? statusInk(good) : statusInk(red), size: 17),
          const SizedBox(width: 6),
          badge(event.isOwned
              ? journeyStatus
              : 'CAPTACIÓN',
            journeyStatus == 'JORNADA ABIERTA'
                ? const Color(0xFFE6F6EC) : const Color(0xFFFFF2D9),
            journeyStatus == 'JORNADA ABIERTA'
                ? statusInk(good) : statusInk(amber)),
        ]),
        if (event.journeys.isNotEmpty) ...[
          const SizedBox(height: 13),
          Text('Jornada', style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w700)),
          DropdownButton<int>(
            isExpanded: true,
            value: event.journeys.any((j) => _journeyMapId(j) == chosenId) ? chosenId : null,
            hint: Text(todayId == null ? 'No hay jornada para hoy' : 'Selecciona una jornada',
              style: TextStyle(color: muted, fontSize: 13)),
            items: [for (var index = 0; index < event.journeys.length; index++)
              if (_journeyMapId(event.journeys[index]) != null)
                DropdownMenuItem<int>(
                  value: _journeyMapId(event.journeys[index]),
                  child: Text(_journeyLabel(event.journeys[index], index)),
                )],
            onChanged: (value) => setState(() => journeyChoices[event.id] = value),
          ),
        ],
        const SizedBox(height: 4),
        for (final item in metadata) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: sub(item),
        ),
        const SizedBox(height: 17),
        SizedBox(width: double.infinity, child: FilledButton(
          onPressed: available ? () => selectRemoteEvent(event) : null,
          child: Text(event.isOwned ? (available ? 'Abrir jornada' : 'NO DISPONIBLE') : 'Ver captación'),
        )),
      ])),
    );
  }

  Widget events() => shell(content([
    const SizedBox(height: 19), label('EVENTOS DISPONIBLES'),
    const SizedBox(height: 12), title('¿Dónde estás hoy?'),
    const SizedBox(height: 8), sub('Selecciona un evento para continuar.'),
    const SizedBox(height: 16),
    if (preview) ...[
      eventCard(true),
      eventCard(false),
    ] else if (remoteEvents.isEmpty)
      panel(const Text('No hay eventos disponibles para este operador.'))
    else
      for (final event in remoteEvents) remoteEventCard(event),
  ]));

  Widget metric(String count, String caption) => Expanded(child: panel(
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(count, style: TextStyle(color: ink, fontWeight: FontWeight.w900,
        fontSize: 19)),
      const SizedBox(height: 12),
      Text(caption, style: TextStyle(color: muted, fontSize: 10)),
    ]), padding: const EdgeInsets.all(11)));

  Widget ownDashboard() {
    final titleText = preview
        ? 'Power Tour\\nRescue Edition'
        : selectedEvent?.title ?? 'Evento DIGNI';
    final ingress = preview
        ? 181 + used.length
        : (remoteSummary['checked_in'] as num?)?.toInt() ?? 0;
    final registered = preview
        ? 350
        : (remoteSummary['registered'] as num?)?.toInt() ?? 0;
    final reentries = preview
        ? 12
        : (remoteSummary['reentries'] as num?)?.toInt() ?? 0;
    final ratio = registered > 0 ? ingress / registered * 100 : 0.0;
    final journeyStatus = preview ? 'JORNADA ABIERTA' : _journeyStatus();
    final canScan = preview || journeyStatus == 'JORNADA ABIERTA';
    final place = [selectedEvent?.commune ?? '', selectedEvent?.region ?? '']
        .where((value) => value.isNotEmpty).join(' · ');

    return shell(content([
      label('MI JORNADA'), const SizedBox(height: 11),
      title('Todo listo para recibir.'), const SizedBox(height: 25),
      panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          logo(true, logoUrl: selectedEvent?.logoUrl),
          const SizedBox(width: 12),
          Icon(canScan ? Icons.check_circle_rounded : Icons.schedule_rounded,
            color: canScan ? good : amber,
            size: 20),
          const SizedBox(width: 6),
          Expanded(child: Align(alignment: Alignment.centerLeft,
            child: badge(journeyStatus,
              canScan ? const Color(0xFFE6F6EC) : const Color(0xFFFFF2D9),
              canScan ? const Color(0xFF087A45) : const Color(0xFF805600)))),
        ]),
        const SizedBox(height: 27),
        if (!preview && _selectedJourneyNumber().isNotEmpty) ...[
          Text(_selectedJourneyNumber(), style: const TextStyle(
            color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800,
            letterSpacing: 1.5)),
          const SizedBox(height: 7),
        ],
        Text(titleText, style: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.w900,
          fontSize: 22, height: 1.3)),
        const SizedBox(height: 21),
        Text(
          preview ? '10 dic · 08:30 – 17:00'
              : _journeySchedule(selectedJourney, selectedEvent?.dateLabel ?? ''),
          style: const TextStyle(color: Colors.white, fontSize: 12)),
        if (place.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(children: [const Icon(Icons.place_outlined,
            size: 15, color: Colors.white70), const SizedBox(width: 6),
            Expanded(child: Text(place, style: const TextStyle(
              color: Colors.white70, fontSize: 11)))]),
        ],
        const SizedBox(height: 15),
        LinearProgressIndicator(value: registered > 0
            ? (ingress / registered).clamp(0.0, 1.0).toDouble() : 0.0,
          minHeight: 5, borderRadius: BorderRadius.circular(8),
          color: good, backgroundColor: Colors.white24),
        const SizedBox(height: 7),
        Text('${ratio.toStringAsFixed(1).replaceAll('.', ',')}% de asistentes ingresados',
          style: const TextStyle(color: Colors.white70, fontSize: 10)),
        const SizedBox(height: 11),
        const Divider(color: Color(0xFF696969)),
      ],),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF1B3742), Color(0xFF0D151A)]
              : const [Color(0xFF2A4A56), Color(0xFF12242C)],
        )),
      const SizedBox(height: 16),
      Row(children: [
        metric('$ingress', 'Ingresados'),
        const SizedBox(width: 8),
        metric('$registered', 'Inscritos'),
        const SizedBox(width: 8),
        metric('${ratio.toStringAsFixed(1).replaceAll('.', ',')}%', 'Asistencia'),
      ]),
      const SizedBox(height: 15),
      panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$reentries reingresos', style: TextStyle(
          color: ink, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        sub(preview
            ? '73 registrados por ti'
            : '${remoteSummary['operator_checkins'] ?? 0} registrados por ti'),
      ])),
      const SizedBox(height: 21),
      FilledButton.icon(
        onPressed: canScan ? () => go(View.scanner) : null,
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: Text(canScan ? 'Validar acceso' : journeyStatus),
      ),
    ]), nav: true, active: 'Inicio');
  }

  Widget externalDashboard() {
    final eventTitle = preview
        ? 'Expo Jardines'
        : selectedEvent?.title ?? 'Evento';
    final captured = preview
        ? 128
        : selectedEvent?.captureCount ?? 0;

    return shell(content([
      label('CAPTACIÓN EN TERRENO'), const SizedBox(height: 11),
      title(eventTitle), const SizedBox(height: 8),
      sub('Makita participa en este evento.'), const SizedBox(height: 20),
      panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          logo(false, logoUrl: selectedEvent?.logoUrl),
          const SizedBox(width: 12),
          Expanded(child: Text(eventTitle, style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w800, fontSize: 19))),
        ]),
        const SizedBox(height: 21),
        Text(
          preview ? 'Parque Bicentenario · Vitacura'
              : selectedEvent?.location ?? '',
          style: const TextStyle(color: Colors.white, fontSize: 12)),
        const SizedBox(height: 12),
        Text(
          preview ? '15–18 octubre 2026'
              : selectedEvent?.dateLabel ?? '',
          style: const TextStyle(color: Colors.white, fontSize: 12)),
        const SizedBox(height: 18),
        badge('EVENTO EXTERNO', const Color(0xFFFDE7EC), deep),
      ]), color: space),
      const SizedBox(height: 17),
      InkWell(
        onTap: () => go(View.captures),
        borderRadius: BorderRadius.circular(23),
        child: panel(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sub('CONTACTOS CAPTURADOS'),
            Text('$captured', style: TextStyle(
              color: ink, fontSize: 50, fontWeight: FontWeight.w900)),
            sub('Registros asociados a Makita'),
          ],
        )),
      ),
      const SizedBox(height: 17),
      panel(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.shield_outlined, color: actionInk),
        const SizedBox(width: 11),
        Expanded(child: Text(
          'Solo captación e información. Este evento no permite validar '
          'entradas ni controlar accesos de terceros.',
          style: TextStyle(color: ink, height: 1.5))),
      ]), color: tint),
    ]), nav: true, active: 'Inicio');
  }

  void demoCodes() {
    if (!preview || !own) return;
    showModalBottomSheet<void>(context: navigatorKey.currentState!.overlay!.context, showDragHandle: true,
      builder: (ctx) => SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 5, 20, 18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Resultados de prueba',
            style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 11),
          const Text('No registra accesos reales.',
            style: TextStyle(fontSize: 12)),
          for (final item in const <(String, String)>[
            ('DEMO-OK', 'Acceso autorizado'),
            ('DEMO-USED', 'Entrada utilizada'),
            ('DEMO-OTHER', 'Otra jornada'),
            ('DEMO-NO', 'Entrada no encontrada'),
            ('DEMO-ID', 'Verificar identidad'),
          ])
            ListTile(title: Text(item.$2), subtitle: Text(item.$1),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () { Navigator.of(ctx).pop(); unawaited(_scan(item.$1)); }),
        ]))));
  }

  Widget scanner() {
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: const Color(0xFF12242C),
      drawer: _drawer(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12242C),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => go(View.own),
        ),
        title: brand(light: true, width: 108),
        actions: [
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Activar o apagar flash',
            onPressed: () => scannerController.toggleTorch(),
            icon: const Icon(Icons.flash_on_rounded),
          ),
          IconButton(
            tooltip: 'Menú',
            onPressed: () => scaffoldKey.currentState?.openDrawer(),
            icon: const Icon(Icons.menu_rounded),
          ),
        ],
      ),
      body: SafeArea(child: Column(children: [
        if (!preview && !online) _offlineBanner(),
        if (preview)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'PREVIEW · NO SON ENTRADAS REALES',
              style: TextStyle(color: amber, fontSize: 10),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: MobileScanner(
                controller: scannerController,
                onDetect: (capture) {
                  if (busy || view != View.scanner || capture.barcodes.isEmpty) {
                    return;
                  }
                  final raw = capture.barcodes.first.rawValue;
                  if (raw != null && raw.isNotEmpty) {
                    unawaited(_scan(raw));
                  }
                },
                errorBuilder: (_, error) => Container(
                  color: const Color(0xFF12242C),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(23),
                  child: const Text(
                    'No se pudo abrir la cámara. Revisa el permiso e intenta '
                    'nuevamente.',
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
        const Text(
          'QR DIGNI / CÉDULA CHILENA',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Alinea el código en el recuadro.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        if (preview)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 23),
            child: FilledButton.icon(
              onPressed: demoCodes,
              icon: const Icon(Icons.science_outlined),
              label: const Text('Probar resultados sin cámara'),
            ),
          )
        else
          const SizedBox(height: 24),
      ])),
    );
  }

  Widget courtesyForm() => shell(content([
    label('COMPLETAR ENTRADA'),
    const SizedBox(height: 10),
    title('Datos del asistente'),
    const SizedBox(height: 10),
    sub('Completa los datos. El ingreso se registra durante el horario de la jornada.'),
    if (decision?.entryNumber != null) ...[
      const SizedBox(height: 18),
      panel(Text('ENTRADA ${decision!.entryNumber}',
        style: TextStyle(color: actionInk, fontWeight: FontWeight.w900))),
    ],
    const SizedBox(height: 18),
    Form(
      key: courtesyFormKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(children: [
        TextFormField(
          controller: courtesyName,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nombre completo'),
          validator: (value) => (value ?? '').trim().isEmpty ? 'Ingresa el nombre completo.' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: courtesyRut,
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(labelText: 'RUT', hintText: '12345678-9'),
          validator: (value) {
            final normalized = (value ?? '').toUpperCase().replaceAll(RegExp(r'[.\-\s]'), '');
            return RegExp(r'^[1-9][0-9]{6,7}[0-9K]$').hasMatch(normalized)
                ? null : 'Ingresa un RUT válido.';
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: courtesyEmail,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Correo electrónico'),
          validator: (value) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((value ?? '').trim())
              ? null : 'Ingresa un correo válido.'),
        const SizedBox(height: 12),
        TextFormField(
          controller: courtesyPhone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Teléfono'),
          validator: (value) => (value ?? '').trim().isEmpty ? 'Ingresa un teléfono.' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(controller: courtesyRegion,
          decoration: const InputDecoration(labelText: 'Región')),
        const SizedBox(height: 12),
        TextFormField(controller: courtesyCommune,
          decoration: const InputDecoration(labelText: 'Comuna')),
        if (courtesyError.isNotEmpty) ...[
          const SizedBox(height: 16),
          panel(Text(courtesyError, style: TextStyle(color: statusInk(red),
            fontWeight: FontWeight.w700))),
        ],
        const SizedBox(height: 22),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: busy ? null : _submitCourtesyForm,
          icon: busy
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2,
                    color: Colors.white))
              : const Icon(Icons.how_to_reg_rounded),
          label: Text(busy ? 'Guardando…' : 'Guardar datos'),
        )),
      ]),
    ),
  ]), back: true, backTarget: View.result);

  Widget resultView() {
    final r = decision;
    if (r == null) return const SizedBox.shrink();
    final col = switch (r.tone) {Tone.good => good,
      Tone.warn => amber, Tone.bad => red};
    final glyph = switch (r.tone) {Tone.good => Icons.check_rounded,
      Tone.warn => Icons.priority_high_rounded, Tone.bad => Icons.close_rounded};
    return shell(content([
      const SizedBox(height: 34),
      TweenAnimationBuilder<double>(tween: Tween(begin: .7, end: 1),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutBack,
        builder: (_, x, child) => Transform.scale(scale: x, child: child),
        child: Container(width: 164, height: 164,
          alignment: Alignment.center,
          margin: const EdgeInsets.symmetric(horizontal: 80),
          decoration: BoxDecoration(shape: BoxShape.circle,
            color: col.withValues(alpha: .19)),
          child: CircleAvatar(radius: 54, backgroundColor: col,
            child: Icon(glyph, color: Colors.white, size: 53)))),
      const SizedBox(height: 24),
      Center(child: title(r.title)), const SizedBox(height: 11),
      Center(child: sub(r.message)),
      if (r.name != null) ...[
        const SizedBox(height: 28),
        panel(Column(children: [
          sub('ASISTENTE'), const SizedBox(height: 12),
          Text(r.name!, textAlign: TextAlign.center, softWrap: true, style: TextStyle(
            color: ink, fontWeight: FontWeight.w900, fontSize: 19)),
          const SizedBox(height: 9),
          Text('RUT ' + (r.rut ?? ''),
            style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
          if (r.entryNumber != null && r.entryNumber!.isNotEmpty) ...[
            const SizedBox(height: 15),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: r.tone == Tone.good
                    ? (dark ? const Color(0xFF173B2C) : const Color(0xFFE1F7E9))
                    : tint,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: (r.tone == Tone.good ? good : brandRed)
                    .withValues(alpha: .35)),
              ),
              child: Row(children: [
                Icon(Icons.confirmation_number_rounded,
                    color: statusInk(r.tone == Tone.good ? good : brandRed)),
                const SizedBox(width: 9),
                Expanded(child: Text(r.accessNumber != null
                    ? 'TICKET DE INGRESO #${r.accessNumber}'
                    : 'ENTRADA ${r.entryNumber}', softWrap: true, style: TextStyle(
                  color: statusInk(r.tone == Tone.good ? good : brandRed),
                  fontWeight: FontWeight.w900, fontSize: 14))),
              ]),
            ),
          ],
        ])),
      ],
      if (r.supervisor) ...[
        const SizedBox(height: 14),
        panel(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.admin_panel_settings_outlined, color: statusInk(amber)),
            SizedBox(width: 10),
            Expanded(child: Text(
              'La entrada requiere revisión de supervisor autorizado.')),
          ],
        )),
      ],
      if (r.courtesy) ...[
        const SizedBox(height: 14),
        panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.person_add_alt_1_rounded, color: statusInk(amber)),
            const SizedBox(width: 9), Expanded(child: Text(
              'Puedes registrar esta cortesía desde la app.', style: TextStyle(fontWeight: FontWeight.w800))) ]),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: busy ? null : _openCourtesyForm,
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('Completar datos de cortesía'),
          )),
        ])),
      ],
      const SizedBox(height: 21),
      if (r.confirmEntry) FilledButton(
        onPressed: busy ? null : confirmEntry,
        child: const Text('Confirmar ingreso'),
      ),
      if (r.checkout) ...[
        FilledButton.icon(
          onPressed: busy ? null : confirmCheckout,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Registrar salida'),
        ),
        const SizedBox(height: 9),
      ],
      if (r.reenter) FilledButton(
        onPressed: busy ? null : confirmReentry,
        child: const Text('Confirmar reingreso'),
      ),
      if (r.ticketId != null) ...[
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _showRemoteHistory(activePerson ?? DigniAttendee(
            id: r.ticketId!, ticketId: r.ticketId, name: r.name ?? 'Asistente',
            maskedRut: r.rut ?? '',
            status: r.checkout || (r.tone == Tone.good && !r.confirmEntry)
                ? 'checked_in' : 'registered',
            entryNumber: r.entryNumber)),
          icon: const Icon(Icons.history_rounded),
          label: const Text('Ver historial de entrada'),
        ),
      ],
      const SizedBox(height: 13),
      OutlinedButton(
        onPressed: () => go(activePerson != null
            ? View.people
            : (own ? View.own : View.events)),
        child: Text(activePerson != null
            ? 'Volver a asistentes'
            : (own ? 'Volver a la jornada' : 'Volver a mis eventos')),
      ),
    ]), back: true,
      backTarget: activePerson != null
          ? View.people
          : (own ? View.own : View.events));
  }

  Future<void> _historySheet({
    required String personName,
    required String rut,
    required List<(IconData, String, String, Color)> entries,
  }) async {
    await showModalBottomSheet<void>(
      context: navigatorKey.currentState!.overlay!.context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(personName, style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 5),
              Text('RUT $rut', style: TextStyle(color: muted, fontSize: 12)),
              const SizedBox(height: 22),
              for (var index = 0; index < entries.length; index++)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: entries[index].$4.withValues(alpha: .14),
                          child: Icon(entries[index].$1,
                              color: statusInk(entries[index].$4), size: 19),
                        ),
                        if (index != entries.length - 1)
                          Container(width: 2, height: 34, color: border),
                      ],
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entries[index].$2,
                              style: TextStyle(
                                color: ink, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            sub(entries[index].$3),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDemoHistory(
      String name, String rut, String state) async {
    final entries = <(IconData, String, String, Color)>[
      (
        Icons.confirmation_number_outlined,
        'Entrada emitida',
        'Registro habilitado para el evento',
        brandRed,
      ),
    ];
    if (state == 'Ingresó' || state == 'Reingreso') {
      entries.add((
        Icons.login_rounded,
        'Ingreso registrado',
        state == 'Ingresó' ? '10:32 · Puerta principal' : '09:58 · Puerta principal',
        good,
      ));
      if (state == 'Reingreso') {
        entries.add((
          Icons.replay_rounded,
          'Reingreso registrado',
          '10:41 · Operador DIGNI',
          brandRed,
        ));
      }
    } else {
      entries.add((
        Icons.schedule_rounded,
        'Sin ingreso registrado',
        'La entrada continúa pendiente',
        muted,
      ));
    }
    await _historySheet(
      personName: name,
      rut: rut,
      entries: entries,
    );
  }

  void _preparePersonAction(DigniAttendee person, String action) {
    final event = selectedEvent;
    if (event == null || !_eventAvailableToday(event)) return;
    final alreadyIn = person.status == 'checked_in' || person.status == 'reentry';
    activePerson = person;
    final result = switch (action) {
      'checkin' => Decision(
          Tone.warn, 'Confirmar ingreso',
          'Revisa los datos y confirma el ingreso de esta persona.',
          name: person.name, rut: person.maskedRut, ticketId: person.ticketId ?? person.id, entryNumber: person.entryNumber,
          confirmEntry: !alreadyIn),
      'checkout' => Decision(
          Tone.warn, 'Registrar salida',
          'Confirma que la persona está saliendo del evento.',
          name: person.name, rut: person.maskedRut, ticketId: person.ticketId ?? person.id, entryNumber: person.entryNumber,
          checkout: alreadyIn),
      _ => Decision(
          Tone.warn, 'Confirmar reingreso',
          'Confirma el reingreso de esta persona.',
          name: person.name, rut: person.maskedRut, ticketId: person.ticketId ?? person.id, entryNumber: person.entryNumber,
          reenter: alreadyIn || person.status == 'checked_out'),
    };
    setState(() { decision = result; view = View.result; });
  }

  Future<void> _showRemoteHistory(DigniAttendee person) async {
    final client = api;
    if (client == null) return;
    final historyFuture = client.attendeeHistory(person.ticketId ?? person.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: navigatorKey.currentState!.overlay!.context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: historyFuture,
            builder: (context, snapshot) {
              final entries = <(IconData, String, String, Color)>[];
              if (snapshot.hasData) {
                for (final item in snapshot.data!) {
                  final action = (item['action'] ?? 'event').toString();
                  final outcome = (item['outcome'] ?? '').toString();
                  final created = (item['created_at'] ?? '').toString();
                  var icon = Icons.history_rounded;
                  var color = brandRed;
                  if (outcome.contains('denied') || outcome.contains('reject')) {
                    icon = Icons.block_rounded; color = red;
                  } else if (action == 'checkin') {
                    icon = Icons.login_rounded; color = good;
                  } else if (action == 'checkout') {
                    icon = Icons.logout_rounded; color = amber;
                  } else if (action == 'reentry') icon = Icons.replay_rounded;
                  final operator = (item['operator_name'] ?? '').toString();
                  final detail = [
                    if (created.isNotEmpty) _displayAccessTime(created),
                    if (operator.isNotEmpty) operator,
                  ].join(' · ');
                  entries.add((icon, (item['label'] ?? action).toString(), detail, color));
                }
              }
              if (snapshot.hasError) {
                entries.add((Icons.cloud_off_rounded, 'Historial no disponible',
                  'No pudimos cargarla ahora. Las acciones siguen disponibles.', amber));
              } else if (snapshot.connectionState == ConnectionState.waiting) {
                entries.add((Icons.sync_rounded, 'Cargando historial…', 'Puedes elegir una acción mientras termina.', amber));
              } else if (entries.isEmpty) {
                entries.add((Icons.schedule_rounded, 'Sin movimientos registrados',
                  'No hay ingresos ni reingresos en el historial.', muted));
              }
              final alreadyIn = person.status == 'checked_in' || person.status == 'reentry';
              final checkedOut = person.status == 'checked_out';
              final canOperate = selectedEvent != null && _eventAvailableToday(selectedEvent!);
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Historial de entrada', style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(person.name, style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 5),
                Text('RUT ${person.maskedRut}', style: TextStyle(color: muted, fontSize: 12)),
                if (person.entryNumber != null && person.entryNumber!.isNotEmpty) ...[
                  const SizedBox(height: 13),
                  Container(width: double.infinity, padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: brandRed.withValues(alpha: .35))),
                    child: Text('ENTRADA ${person.entryNumber}', softWrap: true,
                      style: TextStyle(
                      color: actionInk, fontWeight: FontWeight.w900, fontSize: 14))),
                ],
                const SizedBox(height: 18),
                for (var index = 0; index < entries.length; index++) Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    CircleAvatar(radius: 17, backgroundColor: entries[index].$4.withValues(alpha: .14),
                      child: Icon(entries[index].$1, color: statusInk(entries[index].$4), size: 18)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(entries[index].$2, style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3), sub(entries[index].$3),
                    ])),
                  ]),
                ),
                const SizedBox(height: 7),
                Text('Acciones', style: TextStyle(color: ink, fontWeight: FontWeight.w900)),
                const SizedBox(height: 9),
                if (canOperate && !alreadyIn && !checkedOut) SizedBox(width: double.infinity, child: FilledButton.icon(
                  icon: const Icon(Icons.login_rounded), label: const Text('Registrar ingreso'),
                  onPressed: () { Navigator.pop(sheetContext); _preparePersonAction(person, 'checkin'); })),
                if (canOperate && checkedOut) SizedBox(width: double.infinity, child: FilledButton.icon(
                  icon: const Icon(Icons.replay_rounded), label: const Text('Registrar reingreso'),
                  onPressed: () { Navigator.pop(sheetContext); _preparePersonAction(person, 'reentry'); })),
                if (canOperate && alreadyIn) ...[
                  SizedBox(width: double.infinity, child: FilledButton.icon(
                    icon: const Icon(Icons.logout_rounded), label: const Text('Registrar salida'),
                    onPressed: () { Navigator.pop(sheetContext); _preparePersonAction(person, 'checkout'); })),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: OutlinedButton.icon(
                    icon: const Icon(Icons.replay_rounded), label: const Text('Registrar reingreso'),
                    onPressed: () { Navigator.pop(sheetContext); _preparePersonAction(person, 'reentry'); })),
                ],
              ]);
            },
          ),
        ),
      ),
    );
  }

  String _humanStatus(String status) {
    if (status == 'checked_in') return 'Ingresó';
    if (status == 'reentry') return 'Reingreso';
    if (status == 'checked_out') return 'Salió';
    if (status == 'cancelled') return 'Anulada';
    return 'Pendiente';
  }

  Widget people() {
    final demoItems = const <(String, String, String)>[
      ('Carolina Soto', '19.***.**1-2', 'Ingresó'),
      ('José Muñoz', '12.***.**8-9', 'Pendiente'),
      ('Ana Pérez', '20.***.**4-3', 'Pendiente'),
      ('Camila Vega', '17.***.**8-1', 'Reingreso'),
    ].where((row) =>
      row.$1.toLowerCase().contains(search.toLowerCase()) ||
      row.$2.contains(search));

    return shell(
      Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title('Buscar asistente'),
              const SizedBox(height: 10),
              sub('Toca una persona para revisar su historial.'),
              const SizedBox(height: 19),
              TextField(
                controller: searchController,
                focusNode: peopleSearchFocus,
                textInputAction: TextInputAction.search,
                onChanged: (value) {
                  setState(() => search = value);
                  searchDebounce?.cancel();
                  if (!preview) {
                    searchDebounce = Timer(const Duration(milliseconds: 280), () {
                      if (mounted) unawaited(_loadPeople());
                    });
                  }
                },
                decoration: const InputDecoration(
                  hintText: 'Nombre, RUT o número de entrada',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            children: preview
                ? [
                    for (final person in demoItems)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 11),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(23),
                          onTap: () => _showDemoHistory(
                            person.$1, person.$2, person.$3),
                          child: panel(Row(children: [
                            CircleAvatar(
                              backgroundColor: tint,
                              child: Text(person.$1.substring(0, 1),
                                style: TextStyle(
                                  color: actionInk, fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 13),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(person.$1, style: TextStyle(
                                  color: ink, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 5),
                                sub('RUT ${person.$2}'),
                              ],
                            )),
                            attendeeBadge(person.$3),
                            const SizedBox(width: 3),
                            Icon(Icons.chevron_right_rounded, color: muted),
                          ])),
                        ),
                      ),
                  ]
                : [
                    if (peopleLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (!peopleLoading && remotePeople.isEmpty)
                      panel(const Text('No hay asistentes para mostrar.')),
                    for (final person in remotePeople)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 11),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(23),
                          onTap: () => _showRemoteHistory(person),
                          child: panel(Row(children: [
                            CircleAvatar(
                              backgroundColor: tint,
                              child: Text(
                                person.name.isEmpty ? '?' : person.name[0].toUpperCase(),
                                style: TextStyle(
                                  color: actionInk, fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 13),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(person.name, style: TextStyle(
                                  color: ink, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 5),
                                sub('RUT ${person.maskedRut}'
                                    '${person.entryNumber == null ? '' : ' · Entrada ${person.entryNumber}'}'),
                              ],
                            )),
                            attendeeBadge(_humanStatus(person.status)),
                            const SizedBox(width: 3),
                            Icon(Icons.chevron_right_rounded, color: muted),
                          ])),
                        ),
                      ),
                  ],
          ),
        ),
      ]),
      back: true,
      nav: true,
      active: 'Personas',
    );
  }

  Widget captures() {
    final previewNames = const [
      'Carolina Soto',
      'José Muñoz',
      'Ana Pérez',
      'Camila Vega',
    ].where((name) => name.toLowerCase().contains(search.toLowerCase()));

    return shell(content([
      title(preview
          ? 'Captación · Expo Jardines'
          : 'Captación · ${selectedEvent?.title ?? 'Evento'}'),
      const SizedBox(height: 20),
      panel(Row(children: [
        logo(false, logoUrl: selectedEvent?.logoUrl),
        const SizedBox(width: 13),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(preview ? 'Expo Jardines'
                : selectedEvent?.title ?? 'Evento',
              style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
            sub('Makita · Participante'),
          ],
        )),
      ])),
      const SizedBox(height: 16),
      panel(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CONTACTOS REGISTRADOS',
            style: TextStyle(color: Colors.white, fontSize: 10)),
          const SizedBox(height: 11),
          Text(preview ? '128' : '${selectedEvent?.captureCount ?? 0}',
            style: const TextStyle(
              color: Colors.white, fontSize: 47, fontWeight: FontWeight.w900)),
          const Text('Registros de esta activación',
            style: TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ), color: deep),
      const SizedBox(height: 18),
      TextField(
        onChanged: (value) {
          setState(() => search = value);
          if (!preview) unawaited(_loadCaptures());
        },
        decoration: const InputDecoration(
          hintText: 'Buscar contactos',
          prefixIcon: Icon(Icons.search_rounded),
        ),
      ),
      const SizedBox(height: 17),
      label('ÚLTIMOS CONTACTOS'),
      const SizedBox(height: 13),
      if (!preview && message.isNotEmpty) ...[
        panel(Text(message, style: TextStyle(color: ink))),
        const SizedBox(height: 13),
      ],
      if (preview)
        for (final name in previewNames)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: panel(Row(children: [
              Icon(Icons.person_outline, color: actionInk),
              const SizedBox(width: 12),
              Expanded(child: Text(name, style: TextStyle(
                color: ink, fontWeight: FontWeight.w800))),
              sub('Capturado · Demo'),
            ])),
          )
      else ...[
        if (busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 25),
            child: Center(child: CircularProgressIndicator()),
          ),
        for (final item in remoteCaptures)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: panel(Row(children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFFDE7EC),
                child: Icon(Icons.person_outline, color: brandRed),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(
                (item['name'] ?? '').toString(),
                style: TextStyle(color: ink, fontWeight: FontWeight.w800))),
              sub((item['created_at'] ?? '').toString()),
            ])),
          ),
      ],
    ]), back: true, nav: true, active: 'Captados');
  }

  Widget info() => shell(content([
    title(preview
        ? (own ? 'Power Tour Rescue' : 'Expo Jardines')
        : selectedEvent?.title ?? 'Evento'),
    const SizedBox(height: 18),
    panel(Row(children: [
      logo(own, logoUrl: selectedEvent?.logoUrl),
      const SizedBox(width: 14),
      Expanded(child: Text(own
          ? 'Evento propio · Makita Chile'
          : 'Marca participante · Makita Chile')),
    ])),
    const SizedBox(height: 16),
    panel(Text(own
        ? 'Control de accesos habilitado para operadores autorizados.'
        : 'Solo información y captación. Sin acceso a entradas de terceros.')),
    if (!preview && selectedEvent?.location.isNotEmpty == true) ...[
      const SizedBox(height: 16),
      panel(Row(children: [
        Icon(Icons.location_on_outlined, color: actionInk),
        const SizedBox(width: 10),
        Expanded(child: Text(selectedEvent!.location)),
      ])),
    ],
  ]), back: true, nav: true, active: 'Evento');

  Widget account() => shell(content([
    title('Mi cuenta'),
    const SizedBox(height: 20),
    panel(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(operatorName, style: const TextStyle(fontWeight: FontWeight.w800)),
          if (profileChanged) ...[
            const SizedBox(width: 7),
            const Icon(Icons.star_rounded, color: amber, size: 18),
          ],
        ]),
        const SizedBox(height: 8),
        Text(preview
            ? 'demo@digni.cl'
            : (email.text.trim().isEmpty ? 'Sesión activa' : email.text.trim())),
        const SizedBox(height: 15),
        Text('${_roleLabel()} · Makita Chile', style: TextStyle(color: muted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        sub('La sesión permanece activa mientras el token o su renovación '
            'sigan autorizados.'),
      ],
    )),
    const SizedBox(height: 16),
    FilledButton.tonal(
      onPressed: () => setState(() => dark = !dark),
      child: Text(dark ? 'Modo claro' : 'Modo oscuro'),
    ),
    const SizedBox(height: 11),
    OutlinedButton.icon(
      onPressed: launchLegalTerms,
      icon: const Icon(Icons.privacy_tip_outlined),
      label: const Text('Términos y privacidad DIGNI'),
    ),
    const SizedBox(height: 11),
    OutlinedButton(
      onPressed: busy ? null : logout,
      child: const Text('Cerrar sesión'),
    ),
  ]), back: true);

  @override
  Widget build(BuildContext context) {
    final screen = switch (view) {
      View.splash => splash(),
      View.signingOut => signingOut(),
      View.login => login(),
      View.events => events(),
      View.own => ownDashboard(),
      View.external => externalDashboard(),
      View.scanner => scanner(),
      View.result => resultView(),
      View.courtesy => courtesyForm(),
      View.people => people(),
      View.captures => captures(),
      View.info => info(),
      View.account => account(),
    };
    final theme = ThemeData(useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness: dark ? Brightness.dark : Brightness.light,
        primary: brandRed, onPrimary: Colors.white,
        primaryContainer: tint, onPrimaryContainer: actionInk,
        secondary: actionInk, onSecondary: dark ? spaceDark : Colors.white,
        secondaryContainer: tint, onSecondaryContainer: actionInk,
        tertiary: muted, onTertiary: dark ? spaceDark : Colors.white,
        tertiaryContainer: surface, onTertiaryContainer: ink,
        error: statusInk(red), onError: dark ? spaceDark : Colors.white,
        errorContainer: dark ? const Color(0xFF4B211E) : const Color(0xFFFCEAE8),
        onErrorContainer: statusInk(red),
        surface: surface, onSurface: ink, onSurfaceVariant: muted,
        surfaceDim: bg, surfaceBright: surface,
        surfaceContainerLowest: bg, surfaceContainerLow: surface,
        surfaceContainer: surface, surfaceContainerHigh: surface,
        surfaceContainerHighest: surface,
        outline: muted, outlineVariant: border,
        inverseSurface: dark ? Colors.white : spaceDark,
        onInverseSurface: dark ? const Color(0xFF232323) : Colors.white,
        inversePrimary: dark ? brandRed : Colors.white,
        surfaceTint: Colors.transparent, shadow: Colors.black, scrim: Colors.black,
      ),
      textTheme: (dark ? ThemeData.dark() : ThemeData.light())
          .textTheme.apply(bodyColor: ink, displayColor: ink),
      iconTheme: IconThemeData(color: muted),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
        foregroundColor: actionInk)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor: actionInk, side: BorderSide(color: muted))),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: actionInk),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: actionInk, selectionColor: brandRed.withValues(alpha: .25),
        selectionHandleColor: actionInk),
      appBarTheme: AppBarTheme(backgroundColor: bg, foregroundColor: ink,
        surfaceTintColor: Colors.transparent),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: surface,
        surfaceTintColor: Colors.transparent),
      snackBarTheme: SnackBarThemeData(backgroundColor: spaceDark,
        contentTextStyle: const TextStyle(color: Colors.white),
        actionTextColor: Colors.white),
      dividerTheme: DividerThemeData(color: border),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: brandRed, foregroundColor: Colors.white,
        disabledBackgroundColor: dark ? const Color(0xFF484848) : const Color(0xFFE7E7E9),
        disabledForegroundColor: muted,
        minimumSize: const Size.fromHeight(53),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: surface,
        labelStyle: TextStyle(color: muted), hintStyle: TextStyle(color: muted),
        prefixIconColor: muted, suffixIconColor: muted,
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: actionInk, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border))),
    );
    return MaterialApp(debugShowCheckedModeBanner: false, title: 'DIGNI Scanner',
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      theme: theme,
      home: Listener(
        onPointerDown: (_) => _touchActivity(),
        onPointerMove: (_) => _touchActivity(),
        child: AnimatedSwitcher(duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, anim) => FadeTransition(opacity: anim,
            child: SlideTransition(position: Tween(
              begin: const Offset(.03, .018), end: Offset.zero).animate(anim),
              child: child)),
          child: KeyedSubtree(key: ValueKey(view), child: screen)),
      ),
    );
  }
}
