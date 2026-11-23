# KPOP-DESIGN-001 · Identidad, tienda y movimiento

Base `local/android-dojo` en `ae0cbc7`. El brief del propietario define el alcance y autoriza la implementación en una rama de revisión.

## Auditoría

- Bienvenida y acceso usaban una columna angosta en escritorio, el mismo fondo en toda la pantalla y un isotipo temporal.
- El constructor ponía el escenario fuera del scroll, reduciendo el espacio para mensajes y teclado. La animación usaba un personaje provisional.
- El catálogo conserva las plantillas, colores y datos de cada comercio. Las tarjetas de altura fija necesitan espacio adicional a escala de texto aumentada.

## Aceptación

- AC-01 · CUANDO alguien abre KiuPop, EL SISTEMA DEBE mostrar la identidad pastel, el isotipo Kiuvy y Plus Jakarta Sans, con tema claro, oscuro y del sistema.
- AC-02 · CUANDO cambia el ancho, se abre el teclado o el texto se amplía, EL SISTEMA DEBE mantener visibles o alcanzables los controles de acceso, conversación, publicación y compra.
- AC-03 · CUANDO se genera la tienda, EL SISTEMA DEBE mostrar el avance confirmado y disparar un único POP por sesión al recibir `store.ready`. Si ya estaba lista al entrar, el resultado está disponible sin ceremonia. Si hay error, Kiu no celebra. Con movimiento reducido el resultado se revela de inmediato.
- AC-04 · CUANDO el comercio responde una pregunta, dicta, adjunta un catálogo o confirma la publicación, EL SISTEMA DEBE conservar los contratos, límites, datos y pasos existentes.
- AC-05 · CUANDO un visitante abre un catálogo o un carrito, EL SISTEMA DEBE conservar los tokens validados del comercio y la semántica existente del checkout de prueba.
- AC-06 · CUANDO se instala KiuPop, EL SISTEMA DEBE usar los recursos de marca documentados en las superficies Android y Web configuradas.

## Diseño

Componentes Flutter de presentación y recursos reproducibles. Se conserva el stack y la arquitectura. Se elige un `CustomPainter` aislado con una línea de tiempo nativa porque ya existe el punto de integración y el sistema de personaje carece de un rig Rive aprobado. La rama permite revisar y revertir de forma aislada.

Referencias: [Flutter adaptable](https://docs.flutter.dev/ui/adaptive-responsive/general), [accesibilidad](https://docs.flutter.dev/ui/accessibility), [rendimiento](https://docs.flutter.dev/perf/best-practices), [runtime Flutter de Rive](https://rive.app/docs/runtimes/flutter/flutter).
