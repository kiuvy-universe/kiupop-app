# ADR-001 — Monolito modular (Flutter + Go + PostgreSQL)

- **Estado:** aceptado
- **Fecha:** 2026-11-21
- **Decisores:** equipo de KiuPop

## Contexto
KiuPop se construye durante un hackathon de 72 horas con tres personas. Necesitamos velocidad, un entorno local reproducible y la posibilidad de crecer sin reescribir. El ecosistema Kiuvy ya existe, pero KiuPop debe estar aislado de él por seguridad.

## Decisión
- Un único repositorio y un único backend Go (biblioteca estándar `net/http` + pgx). Los módulos se separan por paquete (`internal/modules/*`) y se componen en `internal/app`.
- Una app Flutter Web (con el mismo código podrá compilarse luego a móvil).
- PostgreSQL como única persistencia y migraciones SQL embebidas en el binario.
- Docker Compose solo para PostgreSQL y la API. Flutter corre en el host para tener hot reload.
- Contrato OpenAPI como fuente única, verificado por pruebas en Go y Dart.

## Alternativas descartadas
- **Microservicios:** costo operativo y de coordinación injustificado para 3 personas y un MVP.
- **Framework HTTP (Gin, Echo, Fiber):** la `ServeMux` de Go 1.22+ con patrones por método cubre lo necesario y suma cero dependencias.
- **ORM o generador (sqlc/GORM):** se reevaluará `sqlc` cuando existan modelos reales. Hoy hay una sola consulta.
- **Herramienta de migraciones externa:** un migrador de ~80 líneas con advisory lock basta y evita otro binario.
- **Reutilizar código de Kiuvy:** prohibido por aislamiento. La integración futura va por un puerto con credencial dedicada.

## Consecuencias
- (+) Un solo `make dev` levanta todo. Despliegue futuro simple (una imagen de 21 MB).
- (+) Los límites entre módulos se pueden extraer a servicios si alguna vez hace falta.
- (−) La disciplina de no importar entre módulos depende de la revisión. Si se viola, añadir un linter de dependencias.
