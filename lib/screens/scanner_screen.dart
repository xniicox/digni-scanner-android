import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/app_theme.dart';
import '../services/mock_digni_service.dart';
import '../widgets/digni_logo.dart';
import 'result_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool busy = false;
  bool? cameraAllowed;

  @override
  void initState() {
    super.initState();
    _prepareCamera();
  }

  Future<void> _prepareCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() => cameraAllowed = status.isGranted);
  }

  Future<void> _handle(BarcodeCapture capture) async {
    if (busy || capture.barcodes.isEmpty) return;

    final raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;

    setState(() => busy = true);

    try {
      await controller.stop();
      final result = await MockDigniService().validate(raw);

      if (!mounted) return;

      await Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 260),
          pageBuilder: (_, __, ___) => ResultScreen(result: result),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => busy = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos procesar este código. Intenta nuevamente.',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Widget _permissionView() {
    return Container(
      color: const Color(0xFF101415),
      padding: const EdgeInsets.all(28),
      child: SafeArea(
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: DigniLogo(width: 118, light: true),
            ),
            const Spacer(),
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.camera_alt_outlined,
                color: Colors.white,
                size: 38,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Necesitamos acceso a la cámara',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'DIGNI usa la cámara únicamente para leer códigos QR de acceso.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _prepareCamera,
              child: const Text('Permitir cámara'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: openAppSettings,
              child: const Text(
                'Abrir configuración del teléfono',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _cameraError(MobileScannerException error) {
    return Container(
      color: const Color(0xFF101415),
      padding: const EdgeInsets.all(28),
      child: SafeArea(
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: DigniLogo(width: 118, light: true),
            ),
            const Spacer(),
            const Icon(
              Icons.warning_amber_rounded,
              size: 58,
              color: AppColors.warning,
            ),
            const SizedBox(height: 20),
            const Text(
              'No pudimos iniciar la cámara',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Cierra otras aplicaciones que estén usando la cámara y vuelve a intentarlo.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () async {
                try {
                  await controller.stop();
                  await controller.start();
                } catch (_) {}
              },
              child: const Text('Reintentar'),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (cameraAllowed == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF101415),
        body: Center(
          child: CircularProgressIndicator(color: AppColors.tealBright),
        ),
      );
    }

    if (cameraAllowed == false) {
      return Scaffold(
        backgroundColor: const Color(0xFF101415),
        body: _permissionView(),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: controller,
            onDetect: _handle,
            errorBuilder: (_, error) => _cameraError(error),
            placeholderBuilder: (_) => const ColoredBox(
              color: Color(0xFF101415),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.tealBright,
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [
                    Color(0xA8000000),
                    Color(0x00000000),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Row(
                    children: [
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor:
                              Colors.black.withValues(alpha: .42),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      const SizedBox(width: 10),
                      const DigniLogo(width: 108, light: true),
                      const Spacer(),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor:
                              Colors.black.withValues(alpha: .42),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: controller.toggleTorch,
                        icon: const Icon(Icons.flashlight_on_rounded),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: .94, end: 1),
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOutBack,
                  builder: (_, value, child) {
                    return Transform.scale(scale: value, child: child);
                  },
                  child: Container(
                    width: 282,
                    height: 282,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: AppColors.tealBright,
                        width: 3,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x6611C7C6),
                          blurRadius: 30,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: busy
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: .6),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Validando...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  margin: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                  padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .58),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .10),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.qr_code_2_rounded,
                        color: AppColors.tealBright,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Escanea QR DIGNI o QR de cédula. La detección es automática.',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
