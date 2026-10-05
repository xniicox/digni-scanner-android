# DIGNI SCANNER 1.2.0 · identidad y apoyo de supervisor

La aplicación conserva el flujo anterior en eventos donde `requires_identity_check` es `false`. Cuando el plugin activa esa opción, el primer ingreso y cada reingreso muestran «Verificar identidad». Un operador asignado consulta nombre y RUT completo, los compara visualmente con la cédula y aprueba o solicita ayuda. La aprobación de un supervisor dura cinco minutos, se usa una vez y **el operador debe volver a confirmar la presencia**. El motivo de rechazo se conserva en el servidor.

La copia offline contiene nombre, RUT, número de entrada y un comprobante firmado por el servidor. Se guarda en `flutter_secure_storage` mediante el almacenamiento cifrado de Android, se limita al teléfono, operador, evento y jornada, y vence a los 30 minutos. Se elimina al finalizar la jornada, al cerrar sesión o al cambiar de jornada. Los datos completos no se envían a Firebase. Las solicitudes al supervisor requieren red. Las operaciones offline se guardan cifradas y se sincronizan al reconectar; el servidor rechaza una operación si hay una solicitud de supervisor vigente. Dos teléfonos sin conexión simultánea pueden generar un conflicto que solo se resuelve al sincronizar.

## Firebase de DIGNI

El proyecto `digni-scanner` está administrado por la cuenta Makita Chile y la app Android está registrada como `cl.digni.digni_scanner`. Sus identificadores **públicos** están en `firebase/google-services.json`; el workflow los incorpora al módulo Android y los pasa a Flutter durante la compilación. No incluir la cuenta de servicio de WordPress en la app ni en el repositorio.

El plugin requiere su propia cuenta de servicio con permiso de envío FCM, configurada fuera de la raíz pública de WordPress. Firebase usa HTTP v1 con OAuth; no se utiliza una clave de servidor heredada. En Android 13+ se solicita permiso de notificaciones. Si el usuario lo niega o FCM falla, la pantalla «Solicitudes de identidad» permite revisar y resolver pendientes con conexión.

Para iOS se necesitará registrar por separado el bundle en Firebase y configurar APNs y firma de Apple antes de probar push en un iPhone. Esta versión y el workflow incluidos generan APK Android.

## Secuencia de validación real

1. Instalar plugin 3.9.0 en staging y verificar su migración.
2. Registrar dos teléfonos autorizados para el mismo evento: uno operador y otro supervisor.
3. Configurar Firebase y compilar la APK con los identificadores de ese proyecto.
4. Probar consulta, aprobación directa, solicitud, push, rechazo con motivo, aprobación de cinco minutos y confirmación del operador.
5. Probar primer ingreso, reingreso, cancelación, jornada incorrecta, teléfono revocado y dos confirmaciones simultáneas.
6. Desconectar el operador, verificar en el teléfono y sincronizar. Probar explícitamente que una solicitud al supervisor pendiente no puede aprobarse offline.
7. Comprobar eliminación del RUT local al cerrar sesión y al terminar la jornada.

El análisis de Flutter y el build todavía deben ejecutarse en un entorno con Flutter. La conexión real con WordPress y Firebase no está verificada por este documento.
