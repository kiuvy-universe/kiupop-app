# API

El contrato vive en [`packages/api_contracts/openapi.yaml`](../../packages/api_contracts/openapi.yaml). Esta carpeta es para notas de diseño de la API (versionado, errores, paginación) a medida que crezca.

## Convenciones v1
- Prefijo `/api/v1`. Los cambios incompatibles van en `/api/v2`.
- Errores: `{"error":{"code":"snake_case","message":"texto para humanos"}}`. Los `code` son estables y se documentan en el contrato.
- Dinero: `*_minor` entero + `currency` ISO-4217.
- Listas: `{"data":[...]}` (la paginación se agregará con `next_cursor` cuando haga falta).
- Endpoints solo de desarrollo: bajo `/api/v1/demo/*` y únicamente con `MOCK_MODE=true`.
