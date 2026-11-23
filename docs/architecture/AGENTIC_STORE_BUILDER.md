# Kiu — constructor agéntico de tiendas (KPOP-AGENT-001)

> El comerciante conversa con Kiu y Kiu construye, en paralelo, una tienda real, validada y compartible.
> La magia está en la experiencia. La ingeniería es determinista, medible, segura y económica.

## Flujo

```
Registro (Google · correo · Facebook cuando exista la app de Meta)
   │  ID token de Firebase Auth (proyecto de KiuPop; emulador en local)
   ▼
POST /agent/sessions ──► sesión viva (se reanuda al recargar)
   │
   │  "Soy Florería Bella, vendo flores… colores rosados… entrego en Naranjo"
   ▼
POST /agent/sessions/{id}/messages            (un turno, ~10 ms en modo local)
   1. Brain.Understand  → Extraction (propuesta, no confiable)
   2. Apply: herramientas Go tipadas que validan y anclan cada valor en el texto del comerciante
   3. create_store_draft (primer mensaje)  · encola trabajos afectados (estilo, copy por producto, vista previa)
   4. Planner: ¿qué falta? → una pregunta con razón y respuestas rápidas (o ninguna)
   ▼
Workers (PostgreSQL, SKIP LOCKED, leases)          eventos → SSE / long-poll → burbuja de Kiu
   suggest_store_theme ─┐
   generate_product_copy (por producto, opcional) ─┤
                        └► generate_store_preview + validate_store_readiness ─► store.ready (una vez) ─► POP
   ▼
POST /publish {confirm:true}  → snapshot validado, atómico e idempotente → store.published (una vez)
   ▼
/p/{slug} (Open Graph) · compartir nativo · WhatsApp · Facebook · copiar
```

## Módulos (monolito modular)

| Paquete | Responsabilidad |
|---|---|
| `internal/modules/agent` | Kiu: `StoreBlueprint` versionado, `Brain` (Claude o local), herramientas, planner socrático, `ModelRouter`, cola de trabajos, eventos, SSE, publicación. No importa otros módulos: habla con las tiendas por el puerto `StoreDrafts`. |
| `internal/modules/storefront` | Modelo de lectura y publicación: borradores, snapshot validado (tienda + productos en una transacción), vista pública, página `/p/{slug}` y portada `/og/{slug}.png`. |
| `internal/platform/storefront` | Plantillas aprobadas y tokens (`Theme`, `Normalize`, contraste WCAG), tipos compartidos (`View`, `Snapshot`). |
| `internal/platform/identity` | Verificación de ID tokens: Firebase (RS256 con llaves de Google) o emulador (solo local/development, confirmado con el propio emulador). `users` se deriva del token, nunca del cliente. |
| `internal/integrations/payments` | Puerto `PaymentGateway` + `MockPaymentGateway` (modo prueba, estados `test_*`). |
| `internal/modules/orders` | Pedido por WhatsApp y checkout de prueba, ambos con precios del servidor. |

Flutter: `core/auth` (puerto `AuthGateway` + Firebase), `features/auth` (login), `features/agent` (controlador, SSE con ticket y long-poll, burbuja de Kiu, página del constructor), `features/storefront` (renderizador parametrizado, tienda pública, checkout de prueba).

## StoreBlueprint (schema_version 1)

Persistido como JSONB en `agent_sessions.blueprint`, con `revision` que sube en cada cambio:
`business` (nombre, categoría, tagline, descripción, zonas, moneda) · `contact` (WhatsApp E.164, Instagram) ·
`products[]` (id estable, nombre, descripción, `price_minor` o 0 = sin precio, destacado, estado del copy) ·
`delivery` (modos `delivery`/`pickup`, zonas) · `branding` (estilos y colores de listas cerradas) ·
`template` (id, razón, si lo eligió el comerciante) · `theme` (tokens normalizados) ·
`payment` (`checkout: none|test`, `real_payments_enabled: false` siempre) · `publication` · `asked` · `skipped` · `pending`.

## Anti-invención (grounding)

El modelo propone; Go decide. Cada herramienta rechaza lo que no esté en las palabras del comerciante:

| Dato | Regla |
|---|---|
| Precio | Solo si ese monto aparece en el mensaje (`15000`, `15.000`, `15 mil`, `₡12.500`). Los dígitos del nombre del negocio nunca son precios. |
| WhatsApp | Los dígitos deben estar en el mensaje; se normaliza a E.164 (506 por defecto). |
| Zonas, nombre | Deben aparecer en el mensaje (comparación sin tildes). |
| Productos | Al menos una palabra (raíz) del nombre en el mensaje. |
| Copy (tagline, descripción, descripciones de producto) | Se eliminan oraciones con precios, descuentos, "gratis", garantías, superlativos o URLs. |
| Estilos, colores, categoría, plantilla | Listas cerradas. |
| Tokens visuales | `Normalize`: rangos fijos y contraste WCAG (texto 4.5:1, UI 3:1); si falla, tokens auditados de la plantilla. |

Productos sin precio se quedan en borrador: nunca se publican. Publicar exige `{confirm:true}`; los cobros reales no existen en el esquema (`payment_requests.mode = 'test'`).

## Preguntas socráticas adaptativas

`NextField` recorre `name → products → prices → whatsapp → delivery → style` y salta lo conocido u omitido.
Máximo 3 preguntas; una 4.ª (y más) solo para datos imprescindibles (nombre, productos, precios, WhatsApp).
Cada pregunta lleva su **razón** visible y, cuando aplica, respuestas rápidas y «Omitir». El modelo puede redactar la
pregunta, pero el campo lo decide el planner; si la redacción no pasa la validación (sin montos de ejemplo, con «?»,
≤ 200 caracteres) se usa la variante local. En el demo de la Florería Bella Kiu pregunta 2 veces (precios y WhatsApp).

## ModelRouter y costos

| Propósito | Modelo | Por qué |
|---|---|---|
| Primer turno (comprensión profunda del negocio) | `claude-sonnet-5-5`, effort low | Mejor juicio en el mensaje más rico. US$2 / US$10 por MTok. |
| Turnos siguientes (respuestas cortas), descripciones | `claude-haiku-5-5`, effort low | Extracción y copy breve. US$0,10 / US$0,50 por MTok. |
| Escalamiento (salida inválida) | `claude-opus-5-5`, effort low | Un solo reintento excepcional. US$4 / US$20 por MTok. |
| Planner, plantillas, tokens, readiness, publicación | ninguno | Determinista. |

Precios verificados el 22-nov-2026. Todas las llamadas usan structured outputs (JSON schema estricto), prompt de
sistema fijo con `cache_control`, `max_tokens` acotado, timeout de 12 s, `fallbacks: "default"` en Sonnet/Opus,
y registran tokens, caché, latencia y costo en `ai_usage`. Presupuesto por sesión: US$0,06 y 40 llamadas
(`AI_SESSION_BUDGET_MICROS`); al agotarse, o si el proveedor falla, Kiu sigue con el extractor local (etiquetado
«Modo local» en la UI) y nunca inventa.

**Costo estimado por tienda con Claude (no medido: falta la clave dedicada):** primer turno Sonnet
≈ 1.500 tokens de entrada + 550 de salida ≈ US$0,0085; dos turnos Haiku ≈ US$0,0007; tres descripciones Haiku
≈ US$0,0004. **Total ≈ US$0,01 por tienda.** Con la clave se mide con `make ai-smoke` y `go run ./cmd/agentbench`.

## Orquestación

Ver [ADR-agent-orchestration](../decisions/ADR-agent-orchestration.md). Resumen: cola en PostgreSQL (`agent_jobs`)
con `idempotency_key` único, dependencias (`depends_on`), `SELECT … FOR UPDATE SKIP LOCKED`, leases de 30 s,
reintentos con backoff, recuperación de leases vencidos al arrancar y cada 5 s, timeouts de 20 s por trabajo, y
cancelación al publicar. Cada respuesta solo encola lo afectado: un cambio de estilo no regenera descripciones; un
producto renombrado sí regenera su copy (la llave incluye el hash del nombre); una vista previa obsoleta (revisión
vieja) termina como `noop`.

## Progreso y POP

`ComputeProgress` deriva 8 tareas del estado durable (no hay contadores en memoria). El porcentaje solo llega a
100 cuando el backend validó readiness para la revisión actual. `store.ready` tiene `dedupe_key = 'ready'`: se emite
una vez por sesión, aunque luego cambie el estilo. La app solo hace POP al recibir ese evento en vivo (al recargar
no se repite), permite saltar la animación y respeta `prefers-reduced-motion`.

Eventos: SSE en `/api/v1/agent/stream?ticket=…` (ticket opaco de 10 min, ligado a usuario y sesión, porque
`EventSource` no envía encabezados) con reanudación por `Last-Event-ID`; alternativa `GET …/events?after=&wait=`.

## Seguridad

- Identidad propia de KiuPop; el backend verifica cada token. El emulador (tokens sin firma) solo arranca con
  `APP_ENV=local|development` y además se confirma contra el propio emulador. Un 401 hace un refresh forzado y,
  si persiste, cierra la sesión local.
- Aislamiento: todas las consultas de sesión filtran por `user_id`; los borradores y la publicación por
  `owner_user_id`; un producto publicado no puede reasignarse a otra tienda (`ON CONFLICT … WHERE store_id`).
- Los administradores del POC (`kp_…`) siguen funcionando y pueden **reclamar** su tienda con la clave (prueba de
  posesión); la clave se revoca al reclamar y una tienda con dueño no puede reclamarse.
- Prompt injection: el texto del comerciante va entre etiquetas con `<`/`>` neutralizados, el prompt declara que
  es solo información, y lo que el modelo diga pasa por herramientas que validan. El modelo nunca publica, no toca
  SQL ni cobros.
- Abuso y costo: 120 mensajes/hora por usuario, presupuesto IA por sesión, idempotencia por `client_message_id`.
- Auditoría: `agent_actions` registra herramienta, actor, resultado y duración (sin texto del comerciante ni secretos).

## Medición (22-nov-2026 tras las correcciones de la revisión, stack local, cerebro local, 30 corridas: `go run ./cmd/agentbench -n 30`)

| Fase | p50 | p95 |
|---|---|---|
| Registro (emulador) + sesión | 6 ms | 11 ms |
| Turno de conversación | 10 ms | 16 ms |
| Conversación (3 mensajes, sin tiempo de tipeo) | 30 ms | 43 ms |
| Último mensaje → POP | 53 ms | 56 ms |
| Publicación | 7 ms | 10 ms |
| **Total de sistema (registro → publicada)** | **100 ms** | **123 ms** |

Son tiempos del sistema; no incluyen lo que tarda la persona en escribir ni la latencia de Claude. Con Claude, cada
turno suma la latencia del modelo (pendiente de medir con la clave dedicada). El objetivo de 300 s queda dominado por
el tipeo del comerciante: con 3 mensajes y 2 preguntas, el camino es corto.

## Límites conocidos

Ver [AGENTIC_TASKS](../development/AGENTIC_TASKS.md#límites-conocidos).
