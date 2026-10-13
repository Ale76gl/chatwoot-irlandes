# Irlandés Chatwoot — línea estable

Esta rama parte de una versión oficial de Chatwoot y contiene solo las personalizaciones necesarias para Irlandés Underwear.

## Base
- Upstream: Chatwoot v4.18.0
- Imagen objetivo: ghcr.io/ale76gl/chatwoot-irlandes:4.18.0-irlandes-1

## Personalizaciones
- WhatsApp Coexistence: suscripción a messages, history, smb_app_state_sync y smb_message_echoes.
- Mensajes enviados desde WhatsApp Business App reflejados en Chatwoot.
- Ajustes de Embedded Signup para self-hosted.
- Importador de historial WhatsApp con control de chunks e idempotencia.
- Importación histórica sin disparar bots/notificaciones de mensajes antiguos.
- CTA URL para mensajes interactivos de sesión.

## Regla de actualización
1. Crear rama nueva desde el tag oficial de Chatwoot.
2. Reaplicar solo los commits Irlandés.
3. Compilar y probar fuera de producción.
4. Publicar imagen versionada en GHCR.
5. Backup de DB y storage.
6. Cambiar imagen en Coolify.
7. Verificar web, worker, WhatsApp, adjuntos y migraciones.
8. Recién entonces actualizar la rama irlandes-stable.

No editar código directamente dentro del contenedor de producción.
