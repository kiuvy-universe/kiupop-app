# ADR-002 — Credencial de administrador del POC (sin proveedor de identidad)

- **Estado:** aceptado (solo POC / hackathon)
- **Fecha:** 2026-11-21
- **Decisores:** equipo de KiuPop

## Contexto
El POC (KPOP-POC-001) necesita que un comerciante cree su tienda y la edite sin registrarse en un proveedor de identidad, para que el flujo completo quepa en menos de 5 minutos durante la demo.

## Decisión
- Al crear la tienda, el servidor genera una credencial aleatoria de 256 bits (`kp_` + base64url, `crypto/rand`) y la **muestra una sola vez**.
- En la base solo se guarda `SHA-256(token)` (`store_admin_credentials.token_hash`). Con 256 bits de entropía no hay diccionario que atacar, así que no hace falta un KDF lento como bcrypt.
- La credencial viaja **solo** en `Authorization: Bearer` y nunca en la URL ni en los logs. Las respuestas públicas no la incluyen (lo verifican las pruebas).
- Cada consulta de administración filtra por el `store_id` resuelto desde el hash (aislamiento entre tiendas). Un producto ajeno responde 404, sin revelar que existe.
- Flutter guarda la credencial **solo en memoria** (`AdminSession`): nada de localStorage, sessionStorage ni cookies. Al recargar se vuelve a pedir.
- La creación anónima de tiendas (`STORE_SIGNUP_ENABLED`) solo se permite en `local` y `development`; en otro entorno la API no arranca. Además hay un límite de 20 tiendas por hora por IP.

## Fuera de alcance (deuda explícita)
- No hay recuperación: si se pierde la clave, se pierde el acceso a la tienda.
- No hay rotación ni revocación desde la UI (la columna `revoked_at` ya existe).
- El límite de intentos de credencial es solo el que da el propio hash de 256 bits.

## Antes de producción
Reemplazar por identidad real (enlace mágico, OTP por WhatsApp o un proveedor OIDC), con controles contra abuso (captcha o verificación del teléfono) y recuperación. Mientras tanto la API **rechaza** el registro anónimo fuera de desarrollo.
