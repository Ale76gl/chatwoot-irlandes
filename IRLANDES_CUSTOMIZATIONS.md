# Irlandés Chatwoot — personalizaciones y actualización

Esta rama es la línea estable de Irlandés Underwear.

## Regla principal

No modificar código dentro del contenedor de producción. Toda personalización debe entrar primero a GitHub y luego construirse como imagen Docker versionada.

## Base actual

- Chatwoot: 4.17.1
- Snapshot de producción: 4.17.1-irlandes-20
- Rama snapshot: stable-4.17.1-irlandes-20
- Rama estable viva: irlandes-stable

## Personalizaciones preservadas

- WhatsApp Coexistence: webhooks de messages, history, smb_app_state_sync y smb_message_echoes.
- Manejo de mensajes enviados desde WhatsApp Business App.
- Importador de historial de WhatsApp con idempotencia por wamid/source_id.
- Tabla whatsapp_history_sync_chunks para controlar chunks de sincronización.
- Importación histórica sin disparar callbacks, bots ni notificaciones de mensajes antiguos.
- Compatibilidad de setup manual WhatsApp Cloud con source manual_setup_v2.
- CTA URL en mensajes interactivos de sesión.
- Ajustes propios de Chatwoot Irlandés ya existentes en el fork.

## Proceso de actualización

1. Mantener producción en la imagen estable actual.
2. Crear una rama de upgrade desde irlandes-stable.
3. Incorporar la nueva versión/tag de chatwoot/chatwoot.
4. Resolver conflictos conservando las personalizaciones anteriores.
5. Ejecutar build y pruebas.
6. Publicar una imagen GHCR versionada, por ejemplo:
   ghcr.io/ale76gl/chatwoot-irlandes:4.18.0-irlandes-1
7. Probar contra copia/staging o mediante despliegue controlado.
8. Hacer backup de PostgreSQL y storage.
9. Cambiar la imagen en Coolify.
10. Verificar HTTP, worker, WhatsApp, adjuntos y migraciones.
11. Solo entonces actualizar irlandes-stable.

## Rollback

Conservar siempre la imagen anterior y el backup previo. Si el upgrade falla, volver al tag anterior de GHCR y restaurar DB solo si una migración incompatible lo requiere.

## Coolify

Producción se administra como servicio de Coolify en:

- Proyecto: Chatwoot
- Environment: production
- Servicio: Chatwoot Irlandés

Los datos persistentes viven en volúmenes administrados por el servicio de Coolify. No ejecutar el stack viejo de /opt/chatwoot-production en paralelo.
