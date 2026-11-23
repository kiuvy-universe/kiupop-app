# Evidencia de KPOP-DESIGN-001

## Comparación en Chrome

Capturas con datos sintéticos sobre el stack local. La app anterior corresponde al candidato Android + Dojo `ae0cbc7`. La captura móvil usa 390 × 844 px y la de escritorio, 1440 × 900 px.

| Pantalla | Móvil antes | Móvil después | Escritorio antes | Escritorio después |
| --- | --- | --- | --- | --- |
| Bienvenida | [Ver](before-welcome-mobile.webp) | [Ver](after-welcome-mobile.webp) | [Ver](before-welcome-desktop.webp) | [Ver](after-welcome-desktop.webp) |
| Acceso | [Ver](before-login-mobile.webp) | [Ver](after-login-mobile.webp) | [Ver](before-login-desktop.webp) | [Ver](after-login-desktop.webp) |
| Conversación | [Ver](before-chat-mobile.webp) | [Ver](after-chat-mobile.webp) | [Ver](before-chat-desktop.webp) | [Claro](after-chat-desktop.webp) · [Oscuro](after-chat-desktop-dark.webp) |
| Catálogo | [Ver](before-catalog-mobile.webp) | [Ver](after-catalog-mobile.webp) | [Ver](before-catalog-desktop.webp) | [Ver](after-catalog-desktop.webp) |

El recorrido en Chrome comprobó registro, diagnóstico, POP, confirmación de publicación, compartir, carrito, checkout de prueba, acceso a otra tienda y carga de CSV, Excel y PDF. La prueba usó un navegador temporal contra el stack en loopback y el smoke comprobó la política CORS del API por separado.

[Diagnóstico](after-diagnostico-desktop.webp) · [POP](after-pop-desktop.webp) · [Vista previa](after-preview-desktop.webp) · [Compartir](after-compartir-desktop.webp) · [Carrito](after-carrito-desktop.webp) · [Checkout de prueba](after-checkout-desktop.webp) · [Adjuntos CSV, Excel y PDF](after-adjunto-desktop.webp)

## Infinix X6871 físico

Android 15, 1080 × 2436 px y pantalla a 60 Hz durante la medición. La variante instrumentada de perfil se instaló con un ID de aplicación distinto y usó dos puertos ADB de QA. Se completaron el registro, el diagnóstico, la construcción, el POP con el teclado abierto y la vista previa. Después se restauró al frente la instalación original con el mismo PID y se retiraron la variante y los puertos de QA.

[Launcher antes y después](infinix-launcher.webp) · [Bienvenida](infinix-welcome.webp) · [Diagnóstico](infinix-diagnostico.webp) · [POP con teclado](infinix-pop.webp) · [Vista previa](infinix-preview.webp)

## Mediciones

| Caso | Muestra | Resultado |
| --- | --- | --- |
| Infinix, Kiu escuchando | 363 frames en 6,07 s, Flutter `FrameTiming` en perfil | **59,7 fps**, intervalo p95 16,81 ms, build p95 1,54 ms, raster p95 7,56 ms, 0 intervalos >20 ms |
| Infinix, envío final y POP | 400 frames en 6,77 s, teclado visible y capturas durante la transición | **58,9 fps**, intervalo p95 16,83 ms, build p95 3,67 ms, raster p95 20,31 ms, 5 intervalos >20 ms |
| Infinix, memoria | `dumpsys meminfo`, una lectura después de abrir la vista previa | **298 MiB PSS** |
| Infinix, apertura en frío | Android `am start -W`, una apertura de perfil | **1,29 s** de `TotalTime` |
| Chrome 157 headless, viewport móvil | `requestAnimationFrame`, 5 s de escucha, con y sin movimiento reducido | **60,0 fps**, rAF p95 16,7 ms y 0 intervalos >20 ms en ambos casos. CDP registró 3618 ms de tareas de hilo principal con animación y 65 ms con movimiento reducido. |
| Chrome, primer frame de bienvenida | Evento `flutter-first-frame`, una navegación inicial por viewport | Móvil 1,14 → 0,66 s. Escritorio 0,92 → 0,60 s. El build de referencia cargaba CanvasKit desde CDN y el final lo sirvió localmente, así que estas cifras no aíslan la contribución del rediseño. |
| Bundle Web | `main.dart.js` sin compresión | 3 528 668 → 3 551 526 B (**+0,65 %**). El PNG añadido al bundle Flutter mide 5,6 KiB. |
| APK Android | Debug universal y perfil arm64 de QA | 207,8 MB debug, 32,5 MB perfil. |

La medición de Chrome refleja el navegador de la estación y su renderizado headless. El tramo de transición del Infinix incluye teclado, actualización de la vista previa y capturas ADB. La muestra de escucha aislada quedó cerca del objetivo de 60 fps y el tramo de transición registró cinco intervalos por encima de 20 ms.

## Verificación automatizada

- Base `ae0cbc7` con 34 pruebas Flutter y Go con race detector en verde.
- Versión final con 50 pruebas Flutter en verde y 90,29 % de cobertura sobre 1123 líneas ejecutables de Dart modificadas.
- Matriz a 200 % en 320, 360, 390, 412, 768, 1024 y 1440 px, más 568 × 320 en paisaje. Comprueba teclado, acceso al compositor y controles de carrito y checkout. Las pruebas también cubren dictado, adjuntos, sesión reanudada, error con reintento, POP con y sin movimiento y publicación explícita.
- `make lint`, `make test`, `make test-integration`, `make smoke`, build Web release, APK Android debug y verificación de los 16 exports de marca.
- Revisión independiente volvió a probar los casos de evento de readiness al abrir la sesión, POP con teclado abierto y recuperación tras fallos de red.
