

## Funcionalidades

- Splash, login productivo contra la API DIGNI, transiciones y temas claro/oscuro.
- Selección de evento **propio** (Makita Power Tour Rescue) o **externo** (Expo Jardines).
- Propio: panel, métricas, cámara QR/PDF417, validación separada del registro, búsqueda y confirmación de ingreso o reingreso.
- Propio: registro de salida desde el resultado de una entrada ya utilizada, con historial de movimientos.
- Sin conexión: conserva una copia cifrada de asistentes cargados y guarda ingresos, reingresos o salidas pendientes para enviarlos a `POST /sync` al recuperar internet.
- Externo: información y contactos capturados; **sin** acceso a escáner, entradas ni datos de terceros.
- Código desconocido o cualquier QR que no sea de prueba: **entrada no encontrada**; nunca acceso por defecto.
- El escáner abre la cámara solo cuando el operador accede a Validar acceso.

## Acceso de demostración

Correo: demo@digni.cl
PIN: 123456

Códigos de prueba:

| Código | Resultado |
| --- | --- |
| DEMO-OK | válido, segundo uso requiere reingreso |
| DEMO-USED | utilizado |
| DEMO-OTHER | otra jornada |
| DEMO-NO | no encontrado |
| DEMO-ID | identidad discrepante |

El modo demo se activa únicamente con `DIGNI_PREVIEW=true`; la compilación productiva usa `DIGNI_PREVIEW=false`.

## Compilación

En Actions selecciona **Build DIGNI Scanner V3 Preview**. La ejecución también se inicia con cambios en este branch. Descarga el artefacto ZIP y extrae app-debug.apk.

Para compilar localmente:

```bash
flutter pub get
flutter create --platforms=android --org cl.digni --project-name digni_scanner .
flutter build apk --debug --dart-define=DIGNI_PREVIEW=true
```

La configuración Android de cámara e Internet se añade mediante el workflow. Si compilas localmente, agrega esos permisos al manifest.

## Seguridad y requisitos para producción

El modo productivo usa `DIGNI_API_BASE=https://makita.cl` y agrega internamente `/wp-json/digni-scanner/v1/`. La sesión se guarda de forma segura, se renueva con refresh token y la aplicación muestra la última sincronización cuando pierde conectividad. El dispositivo debe estar autorizado por DIGNI E-TICKET 3.8.1. Las operaciones offline se sincronizan con `POST /sync`; la salida online usa `POST /check-out` y la app consulta `GET /device-status` para conocer la ventana disponible.

Figma permite recorrer transiciones; la versión HTML descargable permite login y simulaciones en navegador. Este APK es para revisión interna en Android.
