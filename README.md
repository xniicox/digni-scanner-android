# DIGNI Scanner Android

DIGNI Scanner v1.0.0 — aplicación interna Android para control de acceso a eventos.

## Estado actual

Esta primera compilación incluye el flujo visual y operativo base:

- Splash moderno.
- Login de demostración.
- Selección de evento.
- Mini dashboard.
- Scanner QR con cámara.
- Estados verde, naranja y rojo.
- Reingreso.
- Identidad visible cuando DIGNI reconoce a la persona.
- Máscara oficial solicitada para RUT:
  - `19.000.000-6` → `19.***.**1-6`.

La integración con la API productiva de DIGNI se incorporará sobre el plugin vigente.

## Compilación

GitHub Actions genera automáticamente un APK release de prueba en cada push a `main`.
