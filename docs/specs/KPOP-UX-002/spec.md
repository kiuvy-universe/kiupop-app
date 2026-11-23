# KPOP-UX-002 · Rediseño Premium Ceramic Pastel

Base: `feat/kpop-dojo-delivery` en `8213b33` (KPOP-DESIGN-001, PR #10). El brief del dueño del 2026-11-22 define el alcance y autoriza la implementación en una rama de revisión. No se despliega ni se fusiona automáticamente.

## Referencias

Las [cuatro imágenes del brief](references/) son la autoridad estética. La referencia 3 define estructura y jerarquía: una intención por pantalla, espacio negativo, navegación compacta. Las referencias 1 y 2 definen material, color y personalidad: cerámica mate, arcilla pastel, nubes, melocotón, lavanda, menta y rosa chicle. La cuarta imagen se usó solo para los degradados suaves.

## Auditoría (antes)

- La bienvenida apilaba titular, párrafo, escenario, dos botones, tres pasos y dos enlaces. En 390 × 844 hacía falta desplazarse.
- Kiu tenía brazos de plasma. La identidad vigente (`kiuvy-character` `205588e`, KCS-002) usa manos que son bolitas flotantes.
- El encabezado del constructor tenía cuatro acciones (IA, tema, salir y logo) en un ancho de 360 dp.
- Las superficies eran tarjetas planas con borde. No había volumen, tintes pastel ni sistema de elevación.

## Aceptación

- AC-01 · CUANDO alguien abre KiuPop en un móvil habitual (360 × 640 a 412 × 915), EL SISTEMA DEBE mostrar marca, Kiu, mensaje, «Crear mi tienda con Kiu» y «Ya tengo tienda» sin desplazamiento. Con teclado, paisaje o texto grande DEBE permitir desplazarse en lugar de recortar.
- AC-02 · CUANDO aparece Kiu, EL SISTEMA DEBE dibujarlo con cuerpo cerámico, ojos expresivos y manos‑bolita, sin brazos ni dedos. Sus estados son reposo, escucha, piensa, construye, burbuja, POP y celebración.
- AC-03 · CUANDO se genera la tienda, la burbuja DEBE crecer con el porcentaje confirmado. El POP DEBE ocurrir una sola vez tras `store.ready`. Con error Kiu no celebra. Con movimiento reducido el resultado es inmediato y estático. Ninguna animación en reposo DEBE correr indefinidamente.
- AC-04 · CUANDO la tienda está lista en un teléfono, EL SISTEMA DEBE revelarla con una miniatura y una acción a ancho completo para abrir la vista previa.
- AC-05 · CUANDO alguien usa la app, todos los componentes DEBEN salir de un sistema de tokens común (color, tipo, espacio, radio, elevación, movimiento, tamaños táctiles y breakpoints), con contraste AA en claro y oscuro.
- AC-06 · CUANDO se usan autenticación, diagnóstico, adjuntos, dictado, publicación, compartir, catálogo, carrito y checkout de prueba, EL SISTEMA DEBE conservar contratos, claves de prueba y comportamiento.
- AC-07 · CUANDO se instala o abre KiuPop, splash, manifest, favicon, PWA e icono DEBEN usar el isotipo oficial en violeta chicle sobre blanco y la paleta crema y noche.

## Fuera de alcance

Backend, contratos, base de datos y seguridad. Los tokens del comercio en el catálogo público, carrito y checkout se conservan tal cual (AC-05 de KPOP-DESIGN-001).
