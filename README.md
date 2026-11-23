# KiuPop

**Tu tienda online en minutos.** KiuPop es un producto de [Kiuvy](https://kiuvy.com) para que cualquier pequeño comercio cree una tienda online, agregue productos y reciba pedidos por WhatsApp en menos de cinco minutos, mucho más simple que un POS.

> Estado: **Kiu, el creador agéntico de tiendas** (KPOP-AGENT-001, Dojo AI Hackathon 2026, *Build for Business*): registrarse → contarle a Kiu sobre el negocio → responder unas pocas preguntas → ver la tienda construirse → **POP** → publicar y compartir.

## Recorrido con Kiu (KPOP-AGENT-001)
1. `make setup && make up && make web` (o `make build` y servir `apps/web/build/web` en el puerto 3000). Abre http://localhost:3000.
2. **Crear mi tienda con Kiu** → entra con Google o correo. En local es el **emulador de Firebase Auth** (cuentas de prueba; no uses contraseñas reales).
3. Escríbele a Kiu, por ejemplo: *«Soy Florería Bella, vendo flores, arreglos y regalos. Quiero algo elegante y romántico, con colores rosados. Entrego en Naranjo y San Ramón.»*
4. Kiu pregunta solo lo que falta, con la razón: precios (*«Ramo de rosas 15000, arreglo de girasoles 18 mil…»*) y tu WhatsApp. Mientras tanto la tienda se arma: la burbuja de chicle crece con el progreso real del backend.
5. **¡POP!** cuando el backend confirma que la tienda está lista. Probá otro estilo (Bubblegum Pink, Mint Fresh, Peach Pop) o **Publicar mi tienda** (pide confirmación).
6. Compartí el enlace `/p/<slug>` (vista previa para WhatsApp y Facebook), copialo o usá el menú nativo. En la tienda pública: carrito, pedido por WhatsApp y **pago de prueba** (nunca cobra dinero real).

Sin clave de IA, Kiu trabaja en **modo local** (reglas en español, sin inventar datos). Con `AI_ENABLED=true` y una clave dedicada usa Claude con el `ModelRouter` (Haiku 5.5 / Sonnet 5.5 / Opus 5.5). Detalle: [AGENTIC_STORE_BUILDER](docs/architecture/AGENTIC_STORE_BUILDER.md) · [ADR-003](docs/decisions/ADR-agent-orchestration.md) · [tareas y límites](docs/development/AGENTIC_TASKS.md).

Medir: `cd backend && go run ./cmd/agentbench -n 30` (p50/p95 por fase contra el stack local).

## Recorrido del POC (formulario clásico, se mantiene)
1. `make setup && make dev` y abre http://localhost:3000.
2. Abrí `/#/crear` y crea la tienda con nombre y WhatsApp. Guarda la clave `kp_…`: se muestra una sola vez (ver [ADR-002](docs/decisions/ADR-002-poc-admin-credential.md)).
3. **Agregar producto**: foto, nombre y precio en colones. Con KiuPop AI activa, escribe una nota y toca **Mejorar con IA**; revisa la propuesta antes de usarla.
4. **Mi tienda** → *Ver mi tienda* o *Copiar enlace* (`http://localhost:3000/#/s/<slug>`).
5. En otra pestaña, sin sesión: agrega productos y toca **Pedir por WhatsApp**. Se abre `wa.me` con el pedido. Los precios los calcula el servidor y no se confirma ni se cobra nada.

Hay una tienda de ejemplo en `/#/s/tienda-demo`, solo con `MOCK_MODE`.

### KiuPop AI (opcional)
En tu `.env` local (nunca en Git ni en Flutter): `AI_ENABLED=true` y `ANTHROPIC_API_KEY=...`; opcionalmente `ANTHROPIC_MODEL` (por defecto `claude-opus-5-5`). Luego `make up && make ai-smoke`. Sin clave la app funciona igual y el botón explica que la IA no está disponible.

## 1. Objetivo
Una base pequeña, segura y reproducible para que tres personas desarrollen en paralelo con agentes de IA, **sin ninguna dependencia de producción de Kiuvy**.

## 2. Arquitectura resumida
Monolito modular: **un** backend Go, **una** app Flutter Web y **una** base PostgreSQL.

```
Flutter Web (host, :3000) ──HTTP/JSON + SSE──▶ Go API (Docker, 127.0.0.1:8080) ──pgx──▶ PostgreSQL (Docker, 127.0.0.1:5433)
        └── Firebase Auth SDK ──▶ Auth emulator (Docker, 127.0.0.1:9199) ◀── verificación de tokens ──┘
                     contrato: packages/api_contracts/openapi.yaml
```
Detalle: [docs/architecture/OVERVIEW.md](docs/architecture/OVERVIEW.md) · Decisión: [ADR-001](docs/decisions/ADR-001-modular-monolith.md)

## 3. Stack
| Capa | Tecnología |
|---|---|
| Frontend | Flutter 3.47 (stable) · Dart 3.13 · Material 3 · `http` · `intl`/gen-l10n |
| Backend | Go 1.26+ · `net/http` (sin framework) · `log/slog` · pgx v5 |
| Datos | PostgreSQL 18.6 (alpine) con migraciones SQL embebidas |
| Local | Docker Compose · Make |
| CI | GitHub Actions (sin secretos, solo lectura) |

## 4. Requisitos locales
Git, Go ≥ 1.26, Flutter stable con Chrome, Docker Engine o Desktop con Compose v2, Make y curl.
Linux y macOS funcionan de forma nativa. En Windows usa **WSL2** con Docker Desktop (integración WSL activada).

## 5. Instalación
```bash
git clone https://github.com/kiuvy-universe/kiupop.git
cd kiupop
make setup      # verifica herramientas, crea .env sin sobrescribir, deps, imágenes
```

## 6. Ejecución
```bash
make dev        # PostgreSQL + API en Docker y Flutter Web en Chrome con hot reload
```
`Ctrl+C` detiene solo Flutter. Los servicios y datos siguen arriba. `make down` los detiene y conserva el volumen.
Otros: `make up`, `make web`, `make logs`, `make api-host` (Go en el host, sin rebuild), `make help`.

## 7. Puertos
| Servicio | URL | Expuesto en |
|---|---|---|
| Flutter Web | http://localhost:3000 | host |
| API | http://localhost:8080/healthz | 127.0.0.1 únicamente |
| PostgreSQL | `127.0.0.1:5433` (db `kiupop`) | 127.0.0.1 únicamente (5433 para no chocar con un Postgres en 5432) |

## 8. Variables de entorno
Ver [`.env.example`](.env.example). Lo esencial: `APP_ENV` (`local`/`development`), `MOCK_MODE` (endpoints demo, **falla cerrado** fuera de local/development), `KIUVY_INTEGRATION_ENABLED` (`false`, y `true` aborta el arranque), `CORS_ALLOWED_ORIGINS` (lista exacta, sin `*`).
Flutter **no** lee `.env`: recibe `API_BASE_URL` por `--dart-define`.

## 9. Pruebas
```bash
make test              # Go (unit + contrato) y Flutter (widget + contrato)
make lint              # gofmt, go vet, dart format, flutter analyze, compose, gitleaks
make smoke             # stack corriendo: health, readiness, CORS, puertos + flujo POC (tienda, foto, catálogo, pedido)
make ai-smoke          # una llamada REAL a KiuPop AI (requiere clave en .env)
make test-integration  # Go contra una base kiupop_test separada en el PostgreSQL de Compose
make ci                # todo lo que corre CI, en local
```

## 10. Estructura
```
apps/web/                 Flutter Web (core/config, core/network, core/theme, features/home, l10n)
backend/cmd/server/       entrypoint (server | server migrate | server healthcheck)
backend/internal/app/     composición de módulos (router único)
backend/internal/platform config, database (pool + migraciones), httpserver, observability
backend/internal/modules/ stores, products (incl. catálogo público), orders, ai, demo
backend/internal/integrations/kiuvy/  puerto + adaptador deshabilitado
backend/migrations/       SQL embebido en el binario
packages/api_contracts/   OpenAPI 3.1 + ejemplos compartidos por pruebas Go y Dart
infra/compose.yaml        PostgreSQL + API
scripts/                  setup, dev, lint, smoke
docs/                     arquitectura, ADRs, desarrollo, hackathon
```

## 11. Contribución
Ramas `feat/…`, `fix/…`, `docs/…` → PR a `main` → CI verde y revisión. Ver [CONTRIBUTING](docs/development/CONTRIBUTING.md) y las asignaciones en `docs/development/*_TASKS.md`.

## 12. Seguridad
- KiuPop es independiente: no usa bases, credenciales, tokens ni endpoints de Kiuvy.
- Sin secretos en Git (`.env` ignorado, gitleaks en CI y en `make lint`).
- Puertos solo en loopback, CORS con lista exacta, API sin root sobre distroless.
- CI con token de solo lectura, sin `pull_request_target` y sin despliegues.

## 13. Hackathon
Qué existía antes, qué se construyó entre el 20 y el 22 de noviembre y cómo usamos IA: [HACKATHON.md](HACKATHON.md).

## 14. Problemas frecuentes
| Síntoma | Solución |
|---|---|
| `port is already allocated` | Cambia `POSTGRES_HOST_PORT` / `API_HOST_PORT` en `.env` y actualiza `API_BASE_URL`. |
| «API local no disponible» en la app | `make up` y luego `make smoke`. Revisa `make logs`. |
| `invalid configuration: MOCK_MODE=true is not allowed` | Estás usando `APP_ENV` distinto de local/development. Es intencional. |
| Flutter no encuentra Chrome | Define `CHROME_EXECUTABLE` o usa `flutter run -d web-server --web-port=3000`. |
| Permiso denegado al socket de Docker (Linux) | Agrega tu usuario al grupo `docker` (requiere cerrar sesión). Los scripts no usan sudo. |
| Quiero una base limpia | `make reset-db` (pide confirmación y solo borra el volumen `kiupop_pgdata`). |

---
© 2026 Kiuvy. Código bajo licencia Apache-2.0 (ver `LICENSE`). Kiuvy, KiuPop y el personaje Kiu son marcas de Kiuvy (ver `TRADEMARKS.md`).
