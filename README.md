# DIGNI Scanner V3 — Preview Android

Este branch contiene una **versión de demostración nativa** basada en Figma V3:
https://www.figma.com/design/oC0XU6mwh7AoBIBk5rrr91

## Funcionalidades del preview

- Splash, login de demostración con validación, transiciones y temas claro/oscuro.
- Selección de evento **propio** (Makita Power Tour Rescue) o **externo** (Expo Jardines).
- Propio: panel, métricas ficticias, cámara con mobile_scanner, simulación explícita de resultados, búsqueda y confirmación de reingreso.
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

Datos ficticios y banner **PREVIEW**. No registrar ingresos reales.

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

El preview se activa **solo** con DIGNI_PREVIEW=true. Sin ese flag no admite el usuario demo ni valida códigos de muestra. La API y autenticación reales se mantienen bloqueadas hasta revisar el **ZIP vigente del plugin DIGNI E-TICKET**, fijar contrato REST, implementar permisos por empresa y tipo de evento, y validar concurrencia, QR cédula, offline y QA. No use este preview como control de ingreso de público.

Figma permite recorrer transiciones; la versión HTML descargable permite login y simulaciones en navegador. Este APK es para revisión interna en Android.
