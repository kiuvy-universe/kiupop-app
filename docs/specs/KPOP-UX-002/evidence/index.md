# Evidencia de KPOP-UX-002

Capturas reales con datos sintéticos contra un stack local aislado (API en 127.0.0.1:8090 con base `kiupop_ux002` y emulador de Auth). Las capturas «antes» son las «después» de KPOP-DESIGN-001 (`8213b33`).

## Antes y después

[Bienvenida móvil](compare-welcome-mobile.webp) · [Acceso móvil](compare-login-mobile.webp) · [Conversación móvil](compare-chat-mobile.webp) · [Bienvenida escritorio](compare-welcome-desktop.webp) · [Tienda lista en escritorio](compare-ready-desktop.webp) · [Bienvenida en el Infinix](compare-infinix-welcome.webp)

Referencias del brief: [cerámica](../references/ref-1-ceramic-ui.png) · [kawaii pastel](../references/ref-2-pastel-kawaii.png) · [minimal premium](../references/ref-3-premium-minimal.png) · [degradado suave](../references/ref-4-soft-gradient.png)

## Kiu

[Estados de Kiu](kiu-states.webp): reposo, escucha, piensa, construye al 30 % y al 85 %, burbuja, POP, celebración, error, movimiento reducido y oscuro. Las imágenes son las goldens de `apps/web/test/goldens/`.

[Secuencia real del POP en el Infinix](infinix-pop-sequence.webp): cuadros a 10 por segundo de una grabación de pantalla. Muestra «Kiu te escucha», el chicle que se hincha, el anillo con gotas, la celebración y la miniatura de la tienda.

## Chrome

| Pantalla | Capturas |
| --- | --- |
| Bienvenida | [320](after-welcome-320.webp) · [360 × 640](after-welcome-360x640.webp) · [390](after-welcome-390.webp) · [412](after-welcome-412.webp) · [768](after-welcome-768.webp) · [1024](after-welcome-1024.webp) · [1440](after-welcome-1440.webp) · [paisaje 568 × 320](after-welcome-landscape.webp) · [oscuro 390](after-welcome-dark-390.webp) · [oscuro 1440](after-welcome-dark-1440.webp) |
| Acceso | [360](after-login-360.webp) · [1440](after-login-1440.webp) |
| Conversación | [inicio 360](after-chat-360.webp) · [preguntas 390](after-questions-390.webp) · [diagnóstico 390](after-diagnostico-390.webp) · [construyendo 1440](after-chat-building-1440.webp) · [Ajustes 1440](after-settings-1440.webp) |
| Tienda lista | [320](after-ready-320.webp) · [390](after-ready-390.webp) · [1024](after-ready-1024.webp) · [1440](after-ready-1440.webp) · [oscuro 1440](after-ready-dark-1440.webp) |
| Publicar y compartir | [vista previa](after-preview-390.webp) · [confirmación](after-publish-confirm-390.webp) · [paywall de prueba](after-paywall-390.webp) · [compartir](after-share-390.webp) |
| Comprador | [tienda](after-store-390.webp) · [carrito](after-cart-390.webp) · [checkout de prueba](after-checkout-390.webp) |

Las capturas de preguntas, diagnóstico, vista previa, confirmación, compartir, tienda, carrito, checkout y Ajustes son de la build de las 02:43 UTC. En esa build el botón de enviar aún no tenía la flecha explícita, la acción «Ver vista previa» estaba en la columna y las burbujas tenían sombra. El resto de esas pantallas no cambió después.

## Infinix X6871 físico

Android 15, 1080 × 2436 px a 60 Hz. La build QA de perfil se instaló junto a la app con el sufijo `.ux002`, sin reemplazar la sesión `flutter run` del dueño. Al terminar se devolvió al frente la app original, que conservó el mismo PID, y se desinstalaron la variante y el puerto ADB 8090.

[Bienvenida](infinix-welcome.webp) · [Acceso](infinix-login.webp) · [Conversación](infinix-chat-start.webp) · [Con teclado](infinix-chat-keyboard.webp) · [Tareas](infinix-chat-plan.webp) · [Tienda lista](infinix-final-ready.webp) · [Vista previa](infinix-final-preview.webp)

## Mediciones

| Caso | Resultado |
| --- | --- |
| Infinix, Kiu escuchando (bucle activo), SurfaceFlinger, últimos 126 cuadros | **59,7 fps**, intervalo p95 17,0 ms, 0 intervalos > 20 ms |
| Infinix, POP | Grabado en video. La medición de cuadros durante la grabación no fue válida (3 cuadros), así que no se reporta fps del POP |
| Infinix, apertura en frío (perfil) | 526 ms (`am start -W`, segunda apertura en frío) |
| Infinix, memoria tras abrir la vista previa | 249 MB PSS |
| Bundle Web `main.dart.js` | 3 605 912 B (antes 3 551 526 B, +1,5 %) |
| APK perfil arm64 | 32,7 MB |

## Verificación automatizada

- 80 pruebas Flutter en verde tras integrar el paywall de la base (50 antes de este trabajo y 4 del paywall). Las nuevas cubren:
  - la bienvenida sin scroll en seis tamaños;
  - Ajustes a 320 y 360 dp con texto al 200 %, y la salida con error visible;
  - las rutas que pasaron de la bienvenida al acceso;
  - la miniatura tras el POP, y un POP que llega con la pantalla cubierta y se reproduce al volver;
  - Kiu en reposo, que no anima en bucle mientras espera;
  - los tintes con AA en ambos temas y nueve goldens de Kiu.
- Cobertura de líneas Dart modificadas respecto de la base actualizada: **95,51 %** (1043 de 1092).
- `make lint` (gofmt, go vet, dart format, flutter analyze, compose, gitleaks) y `make test` (Go con race detector + Flutter) en verde.
- `python3 apps/web/tool/brand/export.py --check`: 16 exportaciones al día.
- Matriz de 200 % de texto en 320 a 1440 y paisaje, con teclado abierto: entrada y envío alcanzables y sin desbordes.

El paywall de prueba llegó a la base durante este trabajo (`6f32c26`). Se integró por merge y hereda el sistema cerámico sin estilos propios. La captura usa el API aislado con el código integrado. No se simuló ningún pago.
