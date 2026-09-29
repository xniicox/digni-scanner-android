import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'api.dart';
import 'session_store.dart';

// A preview binary is explicitly compiled with --dart-define=DIGNI_PREVIEW=true.
// A production binary never accepts demo credentials or demo ticket codes.
const bool preview = bool.fromEnvironment('DIGNI_PREVIEW', defaultValue: false);
const String apiBase = String.fromEnvironment('DIGNI_API_BASE', defaultValue: '');

const teal = Color(0xFF008C98);
const deep = Color(0xFF086874);
const aqua = Color(0xFF57CFCB);
const good = Color(0xFF129E65);
const amber = Color(0xFFDB9119);
const red = Color(0xFFDE4957);

enum View { splash, login, events, own, external, scanner, result, people,
  captures, info, account }
enum Tone { good, warn, bad }

class Decision {
  const Decision(this.tone, this.title, this.message,
    {this.name, this.rut, this.ticketId, this.reenter = false,
      this.supervisor = false});
  final Tone tone;
  final String title, message;
  final String? name, rut;
  final int? ticketId;
  final bool reenter;
  final bool supervisor;
}

class DigniV3App extends StatefulWidget {
  const DigniV3App({super.key});
  @override
  State<DigniV3App> createState() => _DigniV3AppState();
}

class _DigniV3AppState extends State<DigniV3App> {
  final SessionStore sessions = SessionStore();
  final AudioPlayer player = AudioPlayer();
  final email = TextEditingController();
  final pin = TextEditingController();

  late final DigniApi? api = apiBase.trim().isEmpty
      ? null
      : DigniApi(baseUrl: apiBase.trim(), sessions: sessions);

  View view = View.splash;
  bool dark = false, authed = false, own = true, busy = false;
  String message = '', search = '';
  Decision? decision;
  final used = <String>{};
  Timer? autoReturn;

  List<DigniEvent> remoteEvents = const [];
  DigniEvent? selectedEvent;
  Map<String, dynamic> remoteSummary = const {};
  List<DigniAttendee> remotePeople = const [];
  List<Map<String, dynamic>> remoteCaptures = const [];

  int? get journeyId {
    final event = selectedEvent;
    if (event == null || event.journeys.isEmpty) return null;
    final value = event.journeys.first['id'];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Color get bg => dark ? const Color(0xFF10191E) : const Color(0xFFF5F8F9);
  Color get surface => dark ? const Color(0xFF1B292F) : Colors.white;
  Color get ink => dark ? const Color(0xFFF5FAFB) : const Color(0xFF18232A);
  Color get muted => dark ? const Color(0xFFA4B7BF) : const Color(0xFF66767E);
  Color get border => dark ? const Color(0xFF31434B) : const Color(0xFFE5ECEF);
  Color get tint => dark ? const Color(0xFF193D40) : const Color(0xFFE3F5F3);

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final splashDelay =
        Future<void>.delayed(const Duration(milliseconds: 1200));
    var restored = false;

    if (preview) {
      restored = await sessions.previewSessionValid();
    } else if (api != null) {
      if (await sessions.accessStillValid()) {
        restored = true;
      } else if (await sessions.refreshStillValid()) {
        restored = await api!.refresh();
      }
      if (restored) {
        try {
          remoteEvents = await api!.events();
        } catch (_) {
          restored = false;
          await sessions.clear();
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
    player.dispose();
    email.dispose();
    pin.dispose();
    super.dispose();
  }

  void go(View next) {
    autoReturn?.cancel();
    if (!authed && next != View.login && next != View.splash) next = View.login;
    if (!own && (next == View.scanner || next == View.people)) next = View.external;
    if (own && next == View.captures) next = View.own;
    setState(() {
      view = next;
      message = '';
      search = '';
    });
    if (!preview && next == View.people) unawaited(_loadPeople());
    if (!preview && next == View.captures) unawaited(_loadCaptures());
  }

  Future<void> authenticate() async {
    if (busy) return;
    final mail = email.text.trim().toLowerCase();
    if (!RegExp(r'^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$').hasMatch(mail) ||
        !RegExp(r'^\\d{6}$').hasMatch(pin.text)) {
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
        final deviceId = await sessions.ensureDeviceId();
        await client.login(
          email: mail,
          pin: pin.text,
          deviceId: deviceId,
          deviceName: 'Android',
          appVersion: '3.0',
        );
        remoteEvents = await client.events();
      }

      if (!mounted) return;
      setState(() {
        authed = true;
        busy = false;
        view = View.events;
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

  Future<void> logout() async {
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
      remoteEvents = const [];
      remoteSummary = const {};
      remotePeople = const [];
      remoteCaptures = const [];
      used.clear();
      pin.clear();
      view = View.login;
    });
  }

  void event(bool isOwned) {
    setState(() {
      own = isOwned;
      selectedEvent = null;
      remoteSummary = const {};
    });
    go(isOwned ? View.own : View.external);
  }

  Future<void> selectRemoteEvent(DigniEvent event) async {
    setState(() {
      selectedEvent = event;
      own = event.isOwned;
      busy = true;
      remoteSummary = const {};
    });
    try {
      if (api != null) {
        remoteSummary = await api!.summary(event.id, journeyId: journeyId);
      }
    } catch (_) {
      remoteSummary = const {};
    }
    if (!mounted) return;
    setState(() => busy = false);
    go(event.isOwned ? View.own : View.external);
  }

  Future<void> _loadPeople() async {
    final event = selectedEvent;
    final client = api;
    if (preview || event == null || client == null || !event.isOwned) return;
    try {
      final items = await client.attendees(
        event.id,
        journeyId: journeyId,
        query: search,
      );
      if (!mounted) return;
      setState(() => remotePeople = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => message = 'No pudimos cargar la lista de asistentes.');
    }
  }

  Future<void> _loadCaptures() async {
    final event = selectedEvent;
    final client = api;
    if (preview || event == null || client == null || event.isOwned) return;
    try {
      final items = await client.captures(event.id, query: search);
      if (!mounted) return;
      setState(() => remoteCaptures = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => message = 'No pudimos cargar los contactos capturados.');
    }
  }

  String _idempotencyKey(String deviceId) {
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    return '$deviceId-${DateTime.now().microsecondsSinceEpoch}-$random';
  }

  Future<void> _scan(String raw) async {
    if (!authed || !own || view != View.scanner || busy) return;

    if (preview) {
      _checkPreview(raw);
      return;
    }

    final event = selectedEvent;
    final client = api;
    if (event == null || client == null || !event.isOwned) return;

    setState(() => busy = true);
    try {
      final deviceId = await sessions.ensureDeviceId();
      final validation = await client.validate(
        eventId: event.id,
        journeyId: journeyId,
        code: raw,
        deviceId: deviceId,
      );
      if (validation.outcome == 'valid' && validation.ticketId != null) {
        final checked = await client.checkIn(
          eventId: event.id,
          journeyId: journeyId,
          ticketId: validation.ticketId!,
          deviceId: deviceId,
          idempotencyKey: _idempotencyKey(deviceId),
        );
        await _showServerDecision(checked);
      } else {
        await _showServerDecision(validation);
      }
    } on DigniApiException catch (error) {
      _showDecision(Decision(Tone.bad, 'No se pudo validar', error.message));
    } catch (_) {
      _showDecision(const Decision(
        Tone.bad,
        'Sin respuesta del servidor',
        'No se registró ningún acceso. Revisa la conexión e intenta de nuevo.',
      ));
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
        value.outcome == 'checked_in' ||
        value.outcome == 'reentry_approved') {
      tone = Tone.good;
    } else if (value.outcome == 'already_used' ||
        value.outcome == 'other_journey' ||
        value.outcome == 'identity_mismatch' ||
        value.requiresSupervisor) {
      tone = Tone.warn;
    }

    _showDecision(Decision(
      tone,
      value.title,
      value.message,
      name: value.name,
      rut: value.maskedRut,
      ticketId: value.ticketId,
      reenter: value.canReenter,
      supervisor: value.requiresSupervisor,
    ));
    if (tone == Tone.good) await _approvalFeedback();
  }

  void _showDecision(Decision result) {
    setState(() {
      decision = result;
      view = View.result;
    });
    if (result.tone == Tone.good) {
      autoReturn = Timer(const Duration(milliseconds: 3000), () {
        if (mounted && view == View.result) go(View.own);
      });
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
    if (event == null || client == null || current.ticketId == null) return;

    setState(() => busy = true);
    try {
      final deviceId = await sessions.ensureDeviceId();
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
      _showDecision(Decision(Tone.bad, 'No se pudo registrar', error.message));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _approvalFeedback() async {
    await HapticFeedback.mediumImpact();
    try {
      await player.stop();
      await player.play(AssetSource('sounds/check.wav'), volume: 0.9);
    } catch (_) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  Widget brand({bool light = false, double width = 118}) {
    final asset = light
        ? 'assets/brand/DIGNI-BLANCO.png'
        : 'assets/brand/DIGNI-NEGRO.png';
    return Image.asset(
      asset,
      width: width,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: teal,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Text('D', style: TextStyle(
              color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 8),
          Text('DIGNI', style: TextStyle(
            color: light ? Colors.white : ink,
            fontSize: 19, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget label(String value) => Text(value, style: const TextStyle(
    color: teal, fontSize: 10, fontWeight: FontWeight.w800));
  Widget title(String value) => Text(value, style: TextStyle(color: ink,
    fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -.9));
  Widget sub(String value) => Text(value,
    style: TextStyle(color: muted, fontSize: 12, height: 1.5));

  Widget panel(Widget child, {Color? color, EdgeInsets? padding}) => Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(17),
    decoration: BoxDecoration(color: color ?? surface,
      borderRadius: BorderRadius.circular(23),
      border: Border.all(color: color == null ? border : Colors.transparent)),
    child: child);

  Widget badge(String value, Color bgColor, Color fgColor) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(99)),
    child: Text(value, style: TextStyle(color: fgColor,
      fontSize: 10, fontWeight: FontWeight.w800)));

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
        color: isOwn ? Colors.white : const Color(0xFFECEBFF),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        isOwn ? 'MAKITA' : 'EVENTO',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: isOwn ? 9 : 8,
          fontWeight: FontWeight.w900,
          color: isOwn ? const Color(0xFFC6263B) : deep,
        ),
      ),
    );
  }

  Widget content(List<Widget> items) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 26), children: items);

  Widget _drawer() {
    final eventTitle = preview
        ? (own ? 'Power Tour Rescue' : 'Expo Jardines')
        : selectedEvent?.title;

    Widget drawerItem(IconData icon, String text, VoidCallback onTap,
        {Color? color}) {
      return ListTile(
        leading: Icon(icon, color: color ?? muted),
        title: Text(text, style: TextStyle(
          color: color ?? ink, fontWeight: FontWeight.w700)),
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
              brand(width: 142),
              const SizedBox(height: 26),
              panel(Row(children: [
                CircleAvatar(
                  backgroundColor: tint,
                  child: const Text('NO', style: TextStyle(
                    color: deep, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Operador DIGNI', style: TextStyle(
                      color: ink, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    sub('Makita Chile'),
                  ],
                )),
              ])),
              const SizedBox(height: 16),
              drawerItem(Icons.event_outlined, 'Mis eventos', () {
                Navigator.pop(context);
                go(View.events);
              }),
              if (eventTitle != null)
                drawerItem(Icons.home_outlined, eventTitle, () {
                  Navigator.pop(context);
                  go(own ? View.own : View.external);
                }),
              if (own)
                drawerItem(Icons.people_outline, 'Asistentes', () {
                  Navigator.pop(context);
                  go(View.people);
                }),
              if (!own)
                drawerItem(Icons.query_stats_rounded, 'Contactos capturados', () {
                  Navigator.pop(context);
                  go(View.captures);
                }),
              drawerItem(
                dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                dark ? 'Modo claro' : 'Modo oscuro',
                () {
                  Navigator.pop(context);
                  setState(() => dark = !dark);
                },
              ),
              drawerItem(Icons.person_outline, 'Mi cuenta', () {
                Navigator.pop(context);
                go(View.account);
              }),
              const Spacer(),
              const Divider(),
              drawerItem(Icons.logout_rounded, 'Cerrar sesión', () {
                Navigator.pop(context);
                unawaited(logout());
              }, color: red),
            ],
          ),
        ),
      ),
    );
  }

  Widget shell(Widget body,
      {bool back = false, bool nav = false, String active = ''}) {
    final scaffoldKey = GlobalKey<ScaffoldState>();
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
                    ? () => go(own ? View.own : View.external)
                    : () => scaffoldKey.currentState?.openDrawer(),
                icon: Icon(back
                    ? Icons.arrow_back_rounded
                    : Icons.menu_rounded),
              )
            : null,
        title: brand(width: 108),
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
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: CircleAvatar(
                backgroundColor: Color(0xFFE3F5F3),
                child: Text('NO', style: TextStyle(
                  color: deep, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      ),
      body: SafeArea(child: Column(children: [
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
                    ? const Color(0xFFF4C15C)
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
                                        active == item.$2 ? teal : muted),
                                    const SizedBox(height: 4),
                                    Text(item.$2, style: TextStyle(
                                      fontSize: 10,
                                      color: active == item.$2 ? teal : muted)),
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
    backgroundColor: const Color(0xFFB80036),
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
              Image.asset(
                'assets/brand/icono-digni.png',
                width: 188,
                height: 188,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  height: 164,
                  width: 164,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFB80036),
                    borderRadius: BorderRadius.circular(46),
                  ),
                  child: const Text('DIGNI', style: TextStyle(
                    color: Colors.white,
                    fontSize: 33,
                    fontWeight: FontWeight.w900,
                  )),
                ),
              ),
              const SizedBox(height: 68),
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
      if (message.isNotEmpty) Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(message, style: const TextStyle(color: red, fontSize: 12))),
      const SizedBox(height: 9),
      FilledButton(onPressed: busy ? null : authenticate,
        child: busy ? const SizedBox(width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Text('Ingresar a DIGNI')),
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
        isOwn ? const Color(0xFFE1F7E9) : tint,
        isOwn ? good : teal),
      const SizedBox(height: 18),
      sub(isOwn ? '10 dic · 08:30 a 17:00'
        : '15–18 oct · Parque Bicentenario'),
      const SizedBox(height: 18),
      FilledButton(onPressed: () => event(isOwn),
        child: Text(isOwn ? 'Abrir jornada' : 'Ver captación')),
    ])),
  );

  Widget remoteEventCard(DigniEvent event) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: panel(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          logo(event.isOwned, logoUrl: event.logoUrl),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.title, style: TextStyle(
                color: ink, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              sub(event.isOwned
                  ? '${event.organizer} · Evento propio'
                  : 'Makita · Marca participante'),
            ],
          )),
        ]),
        const SizedBox(height: 18),
        badge(
          event.isOwned ? 'CONTROL DE ACCESOS' : 'CAPTACIÓN',
          event.isOwned ? const Color(0xFFE1F7E9) : tint,
          event.isOwned ? good : teal,
        ),
        if (event.dateLabel.isNotEmpty) ...[
          const SizedBox(height: 18),
          sub(event.dateLabel),
        ],
        if (event.location.isNotEmpty) ...[
          const SizedBox(height: 4),
          sub(event.location),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () => selectRemoteEvent(event),
          child: Text(event.isOwned ? 'Abrir jornada' : 'Ver captación'),
        ),
      ],
    )),
  );

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

    return shell(content([
      label('MI JORNADA'), const SizedBox(height: 11),
      title('Todo listo para recibir.'), const SizedBox(height: 25),
      panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          logo(true, logoUrl: selectedEvent?.logoUrl),
          const SizedBox(width: 12),
          badge('JORNADA ABIERTA', const Color(0xFFE1F7E9), good),
        ]),
        const SizedBox(height: 27),
        Text(titleText, style: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.w900,
          fontSize: 22, height: 1.3)),
        const SizedBox(height: 21),
        Text(
          preview ? '10 dic · 08:30 – 17:00' : selectedEvent?.dateLabel ?? '',
          style: const TextStyle(color: Colors.white, fontSize: 12)),
        const SizedBox(height: 11),
        const Divider(color: Color(0xFF75B8BA)),
      ]), color: deep),
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
        onPressed: () => go(View.scanner),
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('Validar acceso'),
      ),
    ]), nav: true, active: 'Inicio');
  }

  Widget externalDashboard() {
    final eventTitle = preview
        ? 'Expo Jardines'
        : selectedEvent?.title ?? 'Evento';
    final captured = preview
        ? 128
        : (remoteSummary['captured'] as num?)?.toInt() ?? 0;

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
        badge('EVENTO EXTERNO', const Color(0xFFE3F5F3), deep),
      ]), color: deep),
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
        const Icon(Icons.shield_outlined, color: teal),
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
    showModalBottomSheet<void>(context: context, showDragHandle: true,
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
              onTap: () { Navigator.of(ctx).pop(); check(item.$1); }),
        ]))));
  }

  Widget scanner() => Scaffold(backgroundColor: const Color(0xFF12242C),
    appBar: AppBar(backgroundColor: const Color(0xFF12242C),
      foregroundColor: Colors.white,
      title: const Text('VALIDAR ACCESO',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      leading: IconButton(icon: const Icon(Icons.close_rounded),
        onPressed: () => go(View.own))),
    body: SafeArea(child: Column(children: [
      if (preview) const Padding(padding: EdgeInsets.all(8),
        child: Text('PREVIEW · NO SON ENTRADAS REALES',
          style: TextStyle(color: Colors.amber, fontSize: 10))),
      Expanded(child: Padding(padding: const EdgeInsets.all(18),
        child: ClipRRect(borderRadius: BorderRadius.circular(26),
          child: MobileScanner(
            onDetect: (capture) {
              if (!preview || view != View.scanner || capture.barcodes.isEmpty) return;
              final raw = capture.barcodes.first.rawValue;
              if (raw != null) check(raw);
            },
            errorBuilder: (_, error) => Container(
              color: const Color(0xFF243840),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(23),
              child: const Text('No se pudo abrir la cámara. Revisa los permisos '
                'o utiliza los códigos de prueba.',
                style: TextStyle(color: Colors.white),
                textAlign: TextAlign.center)),
          )))),
      const Text('QR DIGNI / CÉDULA CHILENA',
        style: TextStyle(color: Colors.white,
          fontSize: 12, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Text('Alinea el código en el recuadro.',
        style: TextStyle(color: Colors.white70, fontSize: 12)),
      if (preview) Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 23),
        child: FilledButton.icon(onPressed: demoCodes,
          icon: const Icon(Icons.science_outlined),
          label: const Text('Probar resultados sin cámara'))),
    ])));

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
          Text(r.name!, style: TextStyle(
            color: ink, fontWeight: FontWeight.w900, fontSize: 19)),
          const SizedBox(height: 9),
          Text('RUT ' + (r.rut ?? ''),
            style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
        ])),
      ],
      const SizedBox(height: 21),
      if (r.reenter) FilledButton(onPressed: () {
        if (!preview || !own) return;
        setState(() => decision = const Decision(Tone.good,
          'Reingreso autorizado', 'Reingreso simulado correctamente.',
          name: 'Carolina Soto', rut: '19.***.**1-2'));
        autoReturn = Timer(const Duration(milliseconds: 2800), () {
          if (mounted && view == View.result) go(View.own);
        });
      }, child: const Text('Confirmar reingreso')),
      const SizedBox(height: 13),
      OutlinedButton(onPressed: () => go(View.own),
        child: const Text('Volver al panel')),
    ]), back: true);
  }

  Widget people() {
    final items = const <(String, String, String)>[
      ('Carolina Soto', '19.***.**1-2', 'Ingresó'),
      ('José Muñoz', '12.***.**8-9', 'Pendiente'),
      ('Ana Pérez', '20.***.**4-3', 'Pendiente'),
      ('Camila Vega', '17.***.**8-1', 'Reingreso'),
    ].where((row) => row.$1.toLowerCase().contains(search.toLowerCase())
      || row.$2.contains(search));
    return shell(content([
      title('Buscar asistente'), const SizedBox(height: 10),
      sub('Consulta la inscripción y el historial.'),
      const SizedBox(height: 19),
      TextField(onChanged: (s) => setState(() => search = s),
        decoration: const InputDecoration(hintText: 'Nombre o RUT',
          prefixIcon: Icon(Icons.search_rounded))),
      const SizedBox(height: 14),
      for (final person in items)
        Padding(padding: const EdgeInsets.only(bottom: 11),
          child: panel(Row(children: [
            CircleAvatar(backgroundColor: tint,
              child: Text(person.$1.substring(0, 1), style:
                const TextStyle(color: teal, fontWeight: FontWeight.w800))),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(person.$1, style: TextStyle(color: ink,
                fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                sub('RUT ' + person.$2)])),
            badge(person.$3, tint, teal),
          ]))),
    ]), back: true, nav: true, active: 'Personas');
  }

  Widget captures() => shell(content([
    title('Captación · Expo Jardines'), const SizedBox(height: 20),
    panel(Row(children: [logo(false), const SizedBox(width: 13),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text('Expo Jardines',
          style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
          sub('Makita · Participante')]))])),
    const SizedBox(height: 16),
    panel(const Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CONTACTOS REGISTRADOS',
          style: TextStyle(color: Colors.white, fontSize: 10)),
        SizedBox(height: 11),
        Text('128', style: TextStyle(color: Colors.white,
          fontSize: 47, fontWeight: FontWeight.w900)),
        Text('Registros de esta activación',
          style: TextStyle(color: Colors.white, fontSize: 11)),
      ]), color: deep),
    const SizedBox(height: 18),
    TextField(onChanged: (s) => setState(() => search = s),
      decoration: const InputDecoration(hintText: 'Buscar contactos',
        prefixIcon: Icon(Icons.search_rounded))),
    const SizedBox(height: 17),
    label('ÚLTIMOS CONTACTOS'), const SizedBox(height: 13),
    for (final name in const ['Carolina Soto','José Muñoz','Ana Pérez','Camila Vega'])
      if (name.toLowerCase().contains(search.toLowerCase()))
        Padding(padding: const EdgeInsets.only(bottom: 9),
          child: panel(Row(children: [
            const Icon(Icons.person_outline, color: teal),
            const SizedBox(width: 12),
            Expanded(child: Text(name, style: TextStyle(color: ink,
              fontWeight: FontWeight.w800))),
            sub('Capturado · Demo'),
          ]))),
  ]), back: true, nav: true, active: 'Captados');

  Widget info() => shell(content([
    title(own ? 'Power Tour Rescue' : 'Expo Jardines'),
    const SizedBox(height: 18),
    panel(Row(children: [logo(own), const SizedBox(width: 14),
      Expanded(child: Text(own ? 'Evento propio · Makita Chile'
        : 'Marca participante · Makita Chile'))])),
    const SizedBox(height: 16),
    panel(Text(own ? 'Control de accesos disponible.'
      : 'Solo información y captación. Sin acceso a entradas de terceros.')),
  ]), back: true, nav: true, active: 'Evento');

  Widget account() => shell(content([
    title('Mi cuenta'), const SizedBox(height: 20),
    panel(const Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text('Operador DIGNI'), SizedBox(height: 8),
        Text('demo@digni.cl'), SizedBox(height: 15),
        Text('Makita Chile')])),
    const SizedBox(height: 16),
    FilledButton.tonal(onPressed: () => setState(() => dark = !dark),
      child: Text(dark ? 'Modo claro' : 'Modo oscuro')),
    const SizedBox(height: 11),
    OutlinedButton(onPressed: () {
      setState(() { authed = false; used.clear(); pin.clear(); });
      go(View.login);
    }, child: const Text('Cerrar sesión')),
  ]), back: true);

  @override
  Widget build(BuildContext context) {
    final screen = switch (view) {
      View.splash => splash(),
      View.login => login(),
      View.events => events(),
      View.own => ownDashboard(),
      View.external => externalDashboard(),
      View.scanner => scanner(),
      View.result => resultView(),
      View.people => people(),
      View.captures => captures(),
      View.info => info(),
      View.account => account(),
    };
    final theme = ThemeData(useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: teal,
        brightness: dark ? Brightness.dark : Brightness.light, surface: surface),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: teal, foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(53),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border))),
    );
    return MaterialApp(debugShowCheckedModeBanner: false, title: 'DIGNI Scanner',
      theme: theme,
      home: AnimatedSwitcher(duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, anim) => FadeTransition(opacity: anim,
          child: SlideTransition(position: Tween(
            begin: const Offset(.03, .018), end: Offset.zero).animate(anim),
            child: child)),
        child: KeyedSubtree(key: ValueKey(view), child: screen)),
    );
  }
}
