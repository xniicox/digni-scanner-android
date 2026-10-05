# DIGNI SCANNER 1.2.0 · Android

Aplicación Flutter de DIGNI para teléfonos autorizados. La compilación productiva usa `DIGNI_API_BASE=https://makita.cl`; el cliente añade `/wp-json/digni-scanner/v1/`. Los eventos, jornadas, entradas, historial, ingresos, salidas, reingresos y capturas siguen en DIGNI E-TICKET. El modo de demostración solo se habilita al compilar expresamente con `DIGNI_PREVIEW=true`.

Esta versión añade verificación manual de identidad por evento, apoyo de supervisor, lista de solicitudes y preparación para Firebase Cloud Messaging. En eventos con la opción activa, una APK anterior no puede registrar ingresos. La integración y las pruebas de despliegue están detalladas en [IDENTIDAD-Y-FIREBASE.md](IDENTIDAD-Y-FIREBASE.md).

La app usa los logos DIGNI en claro/oscuro, icono oficial, lectura QR y cédula, búsqueda de asistentes, bitácora, formulario de cortesía, sincronización y bloqueo por inactividad de veinte minutos. La copia offline de identidad se guarda cifrada en el teléfono autorizado, se limita a la jornada y se elimina al cerrarla o cerrar sesión.

El proyecto Firebase `digni-scanner` ya tiene registrada la app Android. El workflow usa los identificadores públicos de `firebase/google-services.json`. Las credenciales de la cuenta de servicio Firebase pertenecen exclusivamente al backend y nunca deben incluirse en el APK.

**Estado:** el código fuente está preparado. No se ha compilado ni probado con Flutter, WordPress productivo, Firebase ni teléfonos reales en este entorno. No instalar como versión final sin ejecutar la matriz de pruebas del documento de integración.
