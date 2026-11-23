# KPOP-AGENT-001 — tareas del constructor agéntico

Arquitectura: [AGENTIC_STORE_BUILDER](../architecture/AGENTIC_STORE_BUILDER.md) · Decisión: [ADR-003](../decisions/ADR-agent-orchestration.md).
Estado al 22-nov-2026 (rama `feat/kpop-agent-001`, PR #3 apilado sobre #2).

## P0 — Demostración del hackathon

| Tarea | Estado | Evidencia |
|---|---|---|
| Registro: correo y Google (Firebase Auth de KiuPop; emulador en local) | ✅ | `kiu_flow_test.dart`, Chrome |
| Backend verifica ID tokens (RS256) y deriva el usuario; emulador solo en local | ✅ | `identity_test.go`, `config_test.go` |
| Migración segura de la credencial del POC (`kp_` sigue funcionando; reclamo con prueba de posesión) | ✅ | `POST /api/v1/me/stores/claim` |
| Conversación en texto con Kiu, saludo y reanudación al recargar | ✅ | Postgres + widget tests |
| Extracción a StoreBlueprint versionado | ✅ | `localbrain_test.go`, `claude_test.go` |
| Preguntas socráticas (≤ 3; 4.ª solo imprescindible; con razón; omitir) | ✅ | `TestAgentAsksOnlyMissing…` |
| Herramientas tipadas y validadas (grounding: sin precios ni datos inventados) | ✅ | `claude_test.go` |
| ModelRouter (Haiku/Sonnet/Opus 5.5), structured outputs, caché, presupuestos, uso y costo | ✅ (sin llamada real) | `claude_test.go` con API falsa |
| Tres plantillas parametrizadas con tokens validados (contraste WCAG) | ✅ | `theme_test.go`, `storefront_test.dart` |
| Construcción progresiva en paralelo (cola durable, idempotente, recuperable) | ✅ | `TestAgentJobRecovery…` |
| Vista previa idéntica a la tienda pública; la tienda se ve construir en escritorio | ✅ | Chrome |
| Animación bubblegum ligada al progreso; POP solo con `store.ready`; saltar; reduced motion | ✅ | `storefront_test.dart`, Chrome |
| Publicación con confirmación, snapshot atómico e idempotente | ✅ | Postgres |
| Catálogo compartible: `/p/{slug}` con Open Graph, portada generada, compartir nativo, WhatsApp, Facebook | ✅ | smoke, Chrome |
| Pedidos por WhatsApp y checkout simulado (`MockPaymentGateway`, solo `test_*`) | ✅ | Postgres, smoke, Chrome |
| Prueba real con Claude | ⏳ | Necesita una clave de API dedicada |

## P1 — Multimodal y social

| Tarea | Estado | Nota |
|---|---|---|
| Facebook login | ⏳ | Botón visible y deshabilitado («pronto»). Activar con `FACEBOOK_AUTH_ENABLED=true` cuando exista la app de Meta y sus credenciales de prueba. |
| Google en producción | ⏳ | Requiere proyecto Firebase propio de KiuPop (`AUTH_PROVIDER=firebase`, `FIREBASE_PROJECT_ID`, `FIREBASE_API_KEY`, `FIREBASE_APP_ID`). |
| Voz: dictado con el reconocimiento de voz del navegador (es-CR) detrás del puerto `Dictation`; la transcripción queda en el cuadro de texto para corregirla antes de enviar; KiuPop no guarda audio | ✅ | `kiu_flow_test.dart` (voz) |
| Transcripción del lado del servidor (audio grabado + proveedor configurable, borrar audio) | ⬜ | Para navegadores sin reconocimiento de voz; mismo puerto `Dictation`. |
| Adjuntos (≤ 5, ≤ 50 MB): fotos y catálogos PDF/CSV, tipo por contenido, estados por archivo, procesamiento en paralelo | ✅ | `TestAgentAttachmentsAgainstPostgres`, Chrome |
| Catálogo CSV → productos con precio (determinista, sin IA) | ✅ | Los precios vienen del archivo del comerciante; responde la pregunta de precios |
| Fotos de producto en el flujo de Kiu | ✅ | Sin IA: en orden de mención o portada. Con IA (Haiku visión): se asocia por lo que muestra; nunca precios |
| PDF con IA (Sonnet) | ✅ (sin llamada real) | Propone; el comerciante confirma con un toque y esa confirmación ancla los precios. Sin IA: «necesita revisión» honesto |

## P2 — Preparación comercial

Gateway real en sandbox (QPayments u otro) detrás de `PaymentGateway` con credenciales mínimas y webhooks firmados ·
recuperación de cuenta · métricas de activación · limpieza de eventos · LISTEN/NOTIFY para varias instancias ·
auditoría de seguridad · deploy.

## Asset oficial de Kiu

KPOP-DESIGN-001 adapta la guía canónica de Kiu al pintor nativo de Flutter.
El dibujo conserva el cuerpo de energía violeta, los ojos expresivos, los brazos y el núcleo luminoso.
Los estados visuales siguen a la conversación y el avance confirmado. Ver la [especificación de diseño](../specs/KPOP-DESIGN-001/spec.md).

## Límites conocidos

- **Sin clave de IA dedicada, Kiu corre en modo local**: extractor de reglas en español de Costa Rica. Entiende bien el
  formato «Soy X, vendo A, B y C… entrego en Y», listas de precios y números de WhatsApp; frases más libres pueden
  requerir una pregunta extra. Nunca inventa: lo que no entiende, lo pregunta.
- Las descripciones de producto solo se generan con IA; en modo local quedan vacías (honesto) y la tarea aparece como
  «requiere IA».
- Emulador de Auth: al reiniciarlo invalida los tokens emitidos antes; la app refresca, y si no puede, vuelve al login.
  En local la app habla con el emulador por REST (`EmulatorAuthGateway`), no con el SDK web: el SDK restauraba la
  sesión contra Google antes de conectarse al emulador. «Google» en local es una cuenta de prueba del emulador
  (se pide nombre y correo, claramente rotulado). Producción usa el SDK oficial con el proyecto real.
- En modo local una foto se asigna al primer producto sin foto (o a la portada); con IA se asocia por contenido.
- Tickets SSE en memoria (una instancia). Tokens de administración del POC sin rotación.
- El ID token de Firebase vence en 1 h: la administración del POC abierta desde Kiu usa el token del momento.
- CI de GitHub Actions no corrió en este PR (facturación de la organización bloqueada); la evidencia es `make ci`,
  `make test-integration` y `make smoke` locales.

## Siguiente prioridad

1. Clave dedicada → `make ai-smoke` y `agentbench` con Claude; ajustar prompts con 10 descripciones reales de comercios.
2. Fotos en el chat (P1): son la mayor ganancia de calidad visual de la tienda.
3. Proyecto Firebase de KiuPop para Google real y luego Facebook.
