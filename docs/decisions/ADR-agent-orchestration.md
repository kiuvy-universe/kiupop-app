# ADR-003 — Orquestación del agente Kiu dentro del monolito

- Estado: aceptado (KPOP-AGENT-001, 22-nov-2026)
- Relacionado: [ADR-001 monolito modular](ADR-001-modular-monolith.md), [AGENTIC_STORE_BUILDER](../architecture/AGENTIC_STORE_BUILDER.md)

## Contexto

Kiu debe construir la tienda **mientras** conversa: crear el borrador con el primer mensaje, elegir estilo, escribir
descripciones y preparar la vista previa en paralelo, actualizar solo lo afectado por cada respuesta, sobrevivir a
reinicios, no duplicar trabajo ni publicaciones, y avisar el progreso a Flutter en vivo. Restricciones: un binario Go,
PostgreSQL, Docker Compose; nada de Kafka, Kubernetes ni microservicios; costo mínimo.

## Decisión

1. **Estado** en PostgreSQL: `agent_sessions` (StoreBlueprint JSONB + `revision`), `agent_messages`, `agent_events`,
   `agent_actions`, `ai_usage`. Los cambios al blueprint se hacen con la fila bloqueada (`SELECT … FOR UPDATE`) y
   suben `revision`. Una sola sesión viva por usuario (índice único parcial): recargar reanuda.
2. **Cola** `agent_jobs` en la misma base:
   - `idempotency_key` único (`theme:{sesión}:{hash de branding}`, `copy:{sesión}:{producto}:{hash del nombre}`,
     `preview:{sesión}:{revisión}`): encolar dos veces es inofensivo.
   - `depends_on uuid[]`: un trabajo corre cuando sus dependencias terminaron (con éxito o no); la vista previa
     depende del estilo, no de las descripciones (opcionales).
   - Reclamo con `FOR UPDATE SKIP LOCKED` y **lease** de 30 s; `RecoverExpired` reencola leases vencidos al arrancar
     y cada 5 s (o los marca `failed` al agotar `max_attempts`). Backoff lineal, timeout de 20 s por trabajo.
   - N workers en goroutines (`AGENT_WORKERS`, 4 por defecto) despertados por un bus en memoria o por sondeo de 400 ms.
   - Trabajos obsoletos (revisión vieja, producto renombrado) terminan como `noop`. Al publicar se cancelan los pendientes.
3. **Eventos** en `agent_events` con id creciente; `dedupe_key` hace que `store.ready` y `store.published` se emitan
   una sola vez (restricción única). Entrega por **SSE** (ticket opaco de 10 min porque `EventSource` no envía
   encabezados; reanuda con `Last-Event-ID`) y por **long-poll** (`after`, `wait ≤ 10 s`) como alternativa. El bus
   en memoria solo acelera; la fuente de verdad es la tabla.
4. **Turno síncrono, trabajo asíncrono**: el mensaje se entiende y se aplica dentro de la petición (el modelo tiene
   12 s; si falla, extractor local) y todo lo demás va a la cola. La respuesta HTTP trae la siguiente pregunta de inmediato.
5. **Publicación** fuera de la cola, pedida por el comerciante con confirmación explícita: el módulo `storefront`
   escribe tienda + productos + snapshot en una transacción; publicar el mismo snapshot devuelve la misma versión.

## Alternativas descartadas

- **Kafka / NATS / Redis streams**: infraestructura y costo extra sin necesidad a esta escala.
- **Goroutines sin persistencia**: se pierde el trabajo al reiniciar y no hay idempotencia ni auditoría.
- **Bucle agéntico con tool use libre (el modelo decide qué herramienta llamar, varias vueltas)**: más lento y caro
  por turno y menos predecible. Elegimos una sola llamada con salida estructurada por turno; las herramientas son
  funciones Go que el backend ejecuta y valida. El modelo propone, Go decide.
- **WebSockets**: SSE alcanza (servidor → cliente) y funciona detrás de proxies HTTP simples.
- **LISTEN/NOTIFY**: útil con varias instancias; con una instancia el bus en memoria + sondeo basta. Es el siguiente
  paso si se escala horizontalmente.

## Consecuencias

- Una instancia procesa todo; con varias instancias la cola ya es segura (SKIP LOCKED), pero los tickets SSE viven
  en memoria (usar sesión pegajosa o moverlos a la base).
- La tabla de eventos crece: falta una tarea de limpieza (eventos de sesiones publicadas > 30 días).
- Probado en `TestAgentJobRecoveryAgainstPostgres` (lease vencido → reencolado → ejecuta una vez) y en la prueba de
  flujo (POP y publicación emitidos exactamente una vez, publicación idempotente).
