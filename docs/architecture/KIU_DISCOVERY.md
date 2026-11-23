# Kiu — diagnóstico antes de construir (KIU_DISCOVERY_ENABLED)

Estado: implementado en local en la rama `feat/kiu-discovery` (sobre `feat/kpop-agent-001`), pendiente de revisión del lead.
Relacionado: [AGENTIC_STORE_BUILDER](AGENTIC_STORE_BUILDER.md).

## Problema
Kiu creaba el borrador con el primer mensaje y solo preguntaba datos (precios, WhatsApp). Asumía que la respuesta era
«una tienda web» sin entender cómo vende el comercio ni qué le duele. Puede que no necesite una página web, sino un
catálogo que comparta por WhatsApp o Instagram.

## Decisión (Idea 2, aprobada por el dueño de producto)
1. **Filtro corto**: qué vendés (se salta si ya lo dijo), por dónde te compran hoy y qué es lo que más te cuesta. Todas
   las preguntas llevan respuestas rápidas y la opción «Ya sé lo que quiero», que salta directo a construir. Cada
   pregunta se hace una sola vez: si la respuesta no se entiende, Kiu sigue adelante sin entrar en bucle.
2. **Recomendación honesta**: un plan con el problema, la recomendación, el porqué, una nota honesta (por ejemplo «no
   necesitás una página web completa») y 3 acciones para la primera semana con una meta.
3. **No se construye nada hasta el visto bueno**: ni borrador ni trabajos en cola, y el progreso queda en 0 %. Con «Sí,
   armemos esto» se crea el borrador y se encola todo lo reunido. «Cambiar algo» repite las preguntas filtro.
4. **Un catálogo, varios canales**: al publicar, Kiu entrega un kit listo para copiar con textos para WhatsApp, la bio de
   Instagram, una publicación fijada de Facebook o un cartel de mostrador, según los canales del comercio.

## Reglas de Kiu que se respetan
- **El modelo propone, Go decide**: la recomendación sale de una matriz determinista (`RecommendPlan`), canales × dolor.
  La IA no participa del diagnóstico y funciona igual en modo local.
- **Nada inventado**: el plan no menciona precios ni montos (lo verifican las pruebas). El kit solo usa el nombre del
  negocio y el enlace publicado.
- **Honestidad sobre los cobros**: si el dolor es cobrar, Kiu aclara que KiuPop todavía no cobra en línea.
- **Sin integraciones con Meta**: el kit son textos para copiar, no hay llamadas a APIs de WhatsApp, Instagram ni Facebook.

## Diseño
- El estado vive en `blueprint.discovery` (JSONB): `status` (`asking` | `proposed` | `accepted` | `skipped`),
  `channels`, `pain`, `asked` y `plan`. **No hay migraciones.** Si `discovery` es `nil`, el flujo es el original: así
  siguen funcionando las sesiones creadas antes y el interruptor apagado.
- Código: `internal/modules/agent/discovery.go`. Puntos de integración: `PostMessage`, `enqueueAffected`, `advance`
  (cubre también los adjuntos), `Publish` (kit) y `ComputeProgress`.
- Contrato: `AgentQuestion.field` suma `channels` y `pain`; `AgentMessage.meta.kind` suma `plan` y `kit`. Son cambios
  aditivos y sin campos nuevos.
- Flutter: las burbujas `plan` y `kit` se resaltan y son más anchas. No hay textos nuevos en la UI: los textos vienen del
  backend.

## Interruptor y rollback
- `KIU_DISCOVERY_ENABLED` está encendido por defecto. Se configura en `.env` y pasa a la API por `infra/compose.yaml`.
- Rollback inmediato: `KIU_DISCOVERY_ENABLED=false` en `.env` y luego `make up`, o `make up KIU_DISCOVERY_ENABLED=false`.
  Kiu vuelve al flujo original sin cambios (verificado con `make smoke`). Las sesiones que ya estaban en diagnóstico
  quedan en ese estado hasta que se acepte el plan.
- Rollback de código: la rama no está mergeada. Si se mergea, `git revert` de sus commits.

## Pruebas
- Unitarias (`discovery_test.go`): lectura de canales y del dolor, que Kiu no lea canales ni dolor sin haberlos
  preguntado, aceptar, cambiar y saltar el plan, la matriz de recomendación, que el plan no mencione dinero, el kit y el
  progreso en 0 % durante el diagnóstico.
- Integración (`agent_discovery_postgres_test.go`): el flujo completo sin borrador ni trabajos hasta aceptar, y luego
  precios → POP → publicar → kit. También el atajo «Ya sé lo que quiero».
- `make smoke` cubre los dos estados del interruptor.

## Pendiente
- Medir abandono y conversión por recomendación (requiere guardar el diagnóstico en columnas: modelo de datos del MVP).
- Imagen o código QR para el cartel de mostrador. Hoy el kit entrega el enlace como texto.
- Redacción de las preguntas filtro con IA (opcional; hoy son textos fijos y deterministas).
