# api_contracts

Contrato HTTP de KiuPop (OpenAPI 3.1) y ejemplos JSON compartidos.

- `openapi.yaml` — fuente única de endpoints y esquemas.
- `examples/*.json` — respuestas de ejemplo. Las usan **dos** suites:
  - Go: `backend/internal/app/contract_test.go` comprueba que cada path del contrato
    responde y que las respuestas tienen exactamente las claves del ejemplo.
  - Flutter: `apps/web/test/contract_test.dart` parsea los mismos ejemplos con los modelos Dart.

Si cambias un endpoint: actualiza `openapi.yaml` y el ejemplo **en el mismo PR**; ambas suites fallan si divergen.
Cuando haya más de ~10 endpoints evaluaremos generar clientes tipados (Dart/Go) desde este archivo.
