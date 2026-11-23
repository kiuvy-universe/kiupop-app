# Sistema visual Ceramic Pastel

Fuente única: `apps/web/lib/core/theme/app_theme.dart`. Los componentes viven en `core/widgets/kpop_components.dart` y `settings_sheet.dart`. Kiu vive en `features/agent/presentation/kiu_bubble.dart` y `kiu_illustration.dart`.

## Tokens

| Grupo | Valores |
| --- | --- |
| Color base | Crema `#FBF5EB` (fondo), porcelana `#FFFDF8` (superficie), tinta `#302C33` (texto y acción principal), tinta suave `#5C5560` |
| Tintes | Melocotón `#FFD8AE`, lavanda `#D9C8F4`, chicle `#EFAED4`, menta `#D7EBDC`, celeste `#D5E6F5`, mantequilla `#F8E7A0`, cada uno con su texto (`KPopTint.foreground`) |
| Acento | Violeta `#7E3BB9` para enlaces, precios y foco. El isotipo conserva `#8F45CD` |
| Oscuro | Noche `#1C1920`, superficie `#26222B`, texto `#F4EEE6`. La acción principal pasa a melocotón con texto `#3A2A14` y los tintes se oscurecen |
| Tipografía | Plus Jakarta Sans, títulos 800 con tracking −3 %, display 52/42/34, titular 30/26/22, cuerpo 1,45–1,5 de interlineado |
| Espacio | 4 · 8 · 12 · 16 · 20 (margen móvil) · 24 · 32 · 48 |
| Radios | Control 18, losa 20, tarjeta 28, escenario 36, píldora para botones, chips y navegación |
| Elevación | `KPopElevation.soft` y `.raised`: dos sombras difusas (amplia y tenue + cercana) en lugar de la superposición de Material |
| Movimiento | 160 / 240 / 420 ms con easeOutCubic. Ciclo de respiración de 10 s, saludo de 1,1 s y POP de 960 ms |
| Táctil | Mínimo 48 dp. Los botones principales miden 52 dp de alto |
| Breakpoints | Compacto < 600, medio 840 (dos columnas en la bienvenida), expandido 1000+ (constructor en dos paneles) |

Contraste comprobado por prueba: texto principal 13,5:1, tinta suave sobre lavanda 4,62:1 y cada tinte con su texto ≥ 4,5:1 en ambos temas.

## Componentes

`KPopSurface` es la superficie cerámica: porcelana, borde de un pixel y sombra suave o elevada. `KPopCard` la usa. `KPopClayTile` es una fila con tinte e icono redondo. `KPopIconBubble` es la insignia redonda. `KPopButton` tiene tonos principal (tinta), tonal (melocotón), contorno y texto. `KPopChip` se usa en respuestas rápidas. `KPopBanner` muestra avisos. `KPopInput` tiene una variante sin borde para el compositor. `KPopSettingsButton` abre una hoja con apariencia (automático, claro u oscuro), «Cómo piensa Kiu» y «Salir».

## Pantallas

- **Bienvenida:** marca, escenario de nubes con Kiu, titular, una línea de apoyo, «Crear mi tienda con Kiu» y «Ya tengo tienda». Los pasos, la tienda de ejemplo y la clave del POC pasaron al acceso. La altura usa `IntrinsicHeight` bajo el ancho máximo. Si todo cabe no hay desplazamiento, y si no cabe la página se desplaza.
- **Acceso:** Kiu pequeño, Google tonal, Facebook, separador, correo y contraseña. En escritorio se agregan escenario y pasos.
- **Conversación:** encabezado con logo y Ajustes. El escenario de Kiu es una tarjeta lavanda‑melocotón con estado y pista. Las burbujas de Kiu son de porcelana, las tuyas de tinta, el diagnóstico va en lavanda con su título y el aviso de lista en chicle. Las respuestas rápidas y las tareas son píldoras pastel. El compositor es una píldora elevada con herramientas, campo y botón de enviar redondo. Con teclado abierto en el teléfono, el escenario entra en la lista para darle espacio a la conversación. Los mensajes se desvanecen bajo el escenario.
- **Tienda lista:** Kiu celebra, aparece la miniatura de la tienda y «Ver vista previa» ocupa todo el ancho. Bajo 340 dp se omite la miniatura.
- **Compartir:** tarjeta chicle‑melocotón con el enlace en porcelana y acciones en píldora.
- **Panel del comercio, POC y estados vacíos:** losas cerámicas, acentos violeta y la burbuja de icono con un botón tonal como siguiente paso.

## Kiu

El diseño vigente sale de `kiuvy-character` `205588e` (KCS-002, aprobado por el dueño el 2026-11-11). Lo forman una esfera, ojos grandes con tres destellos, boca pequeña y dos manos que son bolitas flotantes. El dibujo de KiuPop es una figurita de cerámica mate: degradado radial lila, rebote cálido abajo a la derecha, brillo mate difuso, mejillas rosadas y sombra de contacto. No tiene brazos, dedos, venas de plasma ni anillo.

| Estado KiuPop | `KiuMood` | Movimiento |
| --- | --- | --- |
| idle | `idle` | Una respiración y queda quieto |
| saludo | `greeting` | Saluda con la mano derecha una vez |
| listening | `listening` | Respira, se inclina y las manos flotan con ritmos propios en bucle mientras escucha |
| thinking | `thinking` | Mira arriba con una mano en el mentón, en bucle |
| building + bubble_inflate | `processing` | Boca en «o». El chicle crece con el porcentaje del servidor |
| pop | `pop: true` | Hinchazón elástica, anillo y gotas. Solo tras `store.ready` |
| celebrating | `success` | Ojos felices, manos arriba y una respiración |
| error | `error` | Cejas tristes y manos abajo. Nunca hay POP |

Las animaciones repintan solo el `CustomPainter` dentro de un `RepaintBoundary`. Se pausan con la app oculta. Con movimiento reducido el resultado es un fotograma final. No se usó Rive porque no existe un rig `.riv` aprobado y el painter cubre todos los estados con pruebas golden (`test/goldens/kiu_*.png`).

## Marca

El isotipo oficial no cambia: violeta chicle `#8F45CD` sobre blanco en el icono adaptativo, el legacy, el maskable, el favicon y el splash. Cambian el fondo del splash, el manifest y `theme-color`, que pasan a crema `#FBF5EB` y noche `#1C1920`. La portada social es una losa de arcilla. Detalle y licencias en [recursos de marca](../../development/KIUPOP_BRAND_ASSETS.md).
