# Irlandés: cuerpo de notificación (backend; Android pendiente)

La ingestión WhatsApp nativa ya convierte texto, botón/lista interactiva y caption a `Message#content`. Los templates renderizados se guardan como texto. Se conserva esa prioridad; no se serializa JSON de proveedor, no se muestra IDs técnicos ni se renderizan parámetros de template para adivinar contenido.

Antes, `Notification#message_content` solo consultaba `content` y devolvía «Attachment» o «No content». Ahora reutiliza el texto procesado si falta el original; para adjuntos usa descripción `fallback_title`, nombre de archivo existente y etiqueta localizada por tipo. No descarga medios. Las menciones y el límite previo de diez palabras se mantienen en el modelo. Los productores FCM/relay y los IDs de navegación no cambian. Solo se agregan strings fuente en inglés, según la política de traducciones del proyecto; Crowdin debe completar traducciones específicas por tipo.

Contratos sintéticos cubren texto, interacción ya normalizada, template/caption nativos, texto procesado, descripción, filename y cuatro tipos; sin Rails/FCM/dispositivo. La especificación Rails existente se actualiza para filename y agrega fallback procesado; su ejecución se delega al CI nativo del repositorio y no se confunde con el test puro. No se modificó UI, por lo que no hay pantalla visual que declarar verificada.

Rama basada en `develop` 5e4da65 (referencia pública, **no** versión productiva confirmada). No se desplegó ni se mandó push real. La reproducción de una notificación Android completa todavía requiere staging/app/dispositivo controlados y payload sintético. No se declara finalizado el punto 18 con estos contratos de backend.
