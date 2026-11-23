# Arquitectura — visión general

## Forma
Un **monolito modular**: un binario Go, una app Flutter Web y una base PostgreSQL. No hay microservicios, colas ni caches (ver [ADR-001](../decisions/ADR-001-modular-monolith.md)).

```
┌──────────────── host ────────────────┐      ┌──────────── Docker (proyecto "kiupop") ────────────┐
│ Flutter Web  :3000 (flutter run)     │ HTTP │ api  127.0.0.1:8080 → :8080 (distroless, nonroot)  │
│  core/config   API_BASE_URL (define) │─────▶│  └─ pgx ──▶ postgres 127.0.0.1:5433 → :5432          │
│  core/network  ApiClient (timeout)   │ CORS │            volumen kiupop_pgdata · red privada       │
│  features/home HomePage              │      └─────────────────────────────────────────────────────┘
└──────────────────────────────────────┘
```

## Backend (hexagonal pragmático)
| Paquete | Rol | Puede depender de |
|---|---|---|
| `cmd/server` | Entrypoint: config → pool → migraciones → router → `http.Server` con graceful shutdown | todo |
| `internal/app` | Compone módulos e integraciones en un único `http.Handler` | módulos, platform, integrations |
| `internal/modules/stores` | Tiendas, slug único, validación de WhatsApp, credencial (crea y resuelve el hash) | platform |
| `internal/modules/products` | CRUD del administrador, fotos y catálogo público (solo productos disponibles) | platform |
| `internal/modules/orders` | Vista previa del pedido: precios **desde PostgreSQL**, mensaje y enlace `wa.me`. No persiste | platform |
| `internal/modules/ai` | KiuPop AI: puerto `ProductDescriptionGenerator`, adaptador Claude, versión `Disabled`, validación de la salida | platform |
| `internal/modules/agent` | **Kiu** (KPOP-AGENT-001): StoreBlueprint, Brain (Claude/local), herramientas validadas, planner, ModelRouter, cola `agent_jobs`, eventos y SSE. Ver [AGENTIC_STORE_BUILDER](AGENTIC_STORE_BUILDER.md) | platform |
| `internal/modules/storefront` | Borradores, publicación por snapshot, vista pública, `/p/{slug}` (Open Graph) y portada | platform |
| `internal/integrations/payments` | Puerto `PaymentGateway` + `MockPaymentGateway` (solo modo prueba) | stdlib |
| `internal/platform/identity` | Verificación de ID tokens (Firebase RS256 / emulador local) y usuarios | pgx |
| `internal/platform/storefront` | Plantillas, tokens, contraste WCAG, tipos de vista compartidos | stdlib |
| `internal/modules/demo` | Endpoints demo y tienda `tienda-demo` (solo con `MOCK_MODE`) | platform |
| `internal/platform/auth` | Credencial `kp_…`: generación, SHA-256, middleware `RequireStoreAdmin` | stdlib |
| `internal/platform/storage` | Fotos en un volumen local; valida JPEG, PNG y WebP por contenido; claves generadas por el servidor | stdlib |
| `internal/platform/ratelimit` | Límite en memoria (registro por IP, IA por tienda y global) | stdlib |
| `internal/platform/config` | Env → `Config` validada. **Fail-closed** para mock e integración | stdlib |
| `internal/platform/database` | Pool pgx y migrador embebido (advisory lock, una tx por migración) | pgx |
| `internal/platform/httpserver` | JSON/errores, middleware (request id, log, recover, headers, CORS), `/healthz` y `/readyz` | stdlib |
| `internal/platform/observability` | Logger `slog` JSON | stdlib |
| `internal/integrations/kiuvy` | Puerto `Client` + adaptador `Disabled` | stdlib |

Regla: los módulos no se importan entre sí. Si dos módulos necesitan colaborar, se define un puerto en el consumidor y se cablea en `internal/app`.

## Flujo del POC (KPOP-POC-001)
```
Comerciante                          API Go                                   PostgreSQL / volumen
POST /api/v1/stores  ─────────────▶ valida, slug único, kp_… (hash) ───────▶ stores, store_admin_credentials
  ◀── credencial mostrada una vez
POST /admin/products (Bearer) ────▶ RequireStoreAdmin → store_id ──────────▶ products (store_id)
POST /admin/products/{id}/image ──▶ sniff JPEG/PNG/WebP, uuid.ext ─────────▶ /data/uploads (volumen)
POST /admin/ai/product-description ▶ límite → Claude (salida JSON con esquema) → valida, quita precios

Comprador (sin sesión)
GET  /api/v1/stores/{slug} + /public/stores/{slug}/products ──▶ solo los productos available de esa tienda
POST /public/stores/{slug}/orders/preview {product_id, quantity} ──▶ precios desde la base → mensaje → wa.me
```
Flutter usa rutas con hash (`/#/s/{slug}`) para que los enlaces profundos funcionen en cualquier hosting estático.

## KiuPop AI
- El puerto `ai.ProductDescriptionGenerator` tiene dos implementaciones: `AnthropicProductDescriptionGenerator`, que usa el SDK oficial de Go y `ANTHROPIC_MODEL` (por defecto `claude-opus-5-5`, effort `low`, salida estructurada con JSON Schema y fallback ante rechazos del lado del servidor), y `Disabled`.
- La nota del comerciante va **solo** en el turno de usuario, como datos, entre delimitadores que no se pueden cerrar desde el texto. El prompt del sistema prohíbe precios, promociones y características inventadas.
- La salida se valida en el servidor: longitudes, JSON válido, y las oraciones con montos, monedas, descuentos u ofertas se eliminan. Un nombre con precio se rechaza. El modelo **nunca** ve ni fija el precio.
- Costos: timeout de 25 s, 1 reintento, `max_tokens` 2048, 30 llamadas por tienda por hora y 300 al día en total. Sin clave, la API responde `503 ai_disabled` y Flutter lo explica. **Nunca se simula una respuesta.**
- `make ai-smoke` hace una llamada real de punta a punta cuando hay clave.

## Flujo Flutter → Go → PostgreSQL
1. `main.dart` construye `AppConfig` desde `--dart-define=API_BASE_URL` y crea `ApiClient` y `DemoApi`.
2. `HomePage` llama `GET /healthz`. Si falla (red, timeout o un código distinto de 2xx), muestra «API local no disponible» y un botón **Reintentar**, sin excepción.
3. Si está sana, llama `GET /api/v1/demo/products`. El handler usa `demo.PostgresRepo`, que lee la tabla `demo_products` (sembrada por la migración `0002`) y responde con `source: "postgres"`.
4. `/readyz` hace `Ping` a PostgreSQL con un timeout de 2 s y responde 503 si la base está caída.

## Contrato
`packages/api_contracts/openapi.yaml` (OpenAPI 3.1) es la fuente única. `examples/*.json` se verifica en las dos puntas:
- Go (`internal/app/contract_test.go`): cada path del contrato responde 200 y las claves del JSON coinciden exactamente con el ejemplo.
- Dart (`test/contract_test.dart`): los modelos parsean los mismos ejemplos.
Cuando haya suficientes endpoints, se evaluará generar clientes tipados desde el contrato.

## Configuración por entorno
| `APP_ENV` | `MOCK_MODE` | Demo `/api/v1/demo/*` | Migrar al iniciar |
|---|---|---|---|
| local / development | permitido | sí si `MOCK_MODE=true` | sí (por defecto) |
| staging / production | **rechazado al iniciar** | nunca | no (por defecto) |

## Integración futura con Kiuvy
Hoy: `kiuvy.Disabled` (no hace llamadas de red) y `KIUVY_INTEGRATION_ENABLED=true` aborta el arranque.
Cuando exista una spec aprobada:
1. Definir en la spec el caso de uso exacto (p. ej. «importar catálogo de un negocio Kiuvy con su consentimiento»).
2. Kiuvy emite **una credencial dedicada a KiuPop** con el mínimo alcance (solo lectura de ese recurso), nunca credenciales compartidas ni de servicio de Kiuvy.
3. Implementar `kiuvy.HTTPClient` en `internal/integrations/kiuvy` con timeouts, reintentos acotados, sin registrar tokens en logs y con pruebas contra un servidor falso (`httptest`).
4. Habilitar con `KIUVY_INTEGRATION_ENABLED=true` + `KIUVY_API_BASE_URL` + secreto inyectado por el entorno (nunca en Git). `config` valida que los tres estén presentes.
5. Revisión de seguridad obligatoria (CODEOWNERS sobre `internal/integrations/` y `config/`).
