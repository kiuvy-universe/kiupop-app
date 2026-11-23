# Sistema visual KiuPop

| Grupo | Tokens |
| --- | --- |
| Color claro | Fondo `#FAF8FC`, papel `#FFFFFF`, lavanda `#F1E8FA`, tinta `#30253D`, primario `#7130AD`, acento rosa `#F5B9D9`, borde decorativo `#EBE4F0`. El isotipo usa `#8F45CD`. |
| Color oscuro | Fondo `#1B1322`, superficie `#211729`, tinta `#F7EFFC`, primario `#DBAEFF`, contenedores lavanda y rosa oscuros. |
| Tipografía | Plus Jakarta Sans local, pesos 700–800 para títulos y acciones. El wordmark se compone como texto y se apoya en el maestro del isotipo. |
| Espacio y geometría | Base de 4 y 8 dp, controles de al menos 48 dp, radios 14/24/32 dp, tarjetas de elevación 0. |
| Estados y foco | Borde de control más oscuro que el contorno decorativo, anillo de 2–2,5 dp para teclado, progreso y avisos en regiones semánticas. Los colores se comprueban con luminancia relativa WCAG. |
| Movimiento | 160/240/420 ms para interacción y progreso, saludo de 1100 ms, ciclo de escucha con parpadeo de 10 s, POP y celebración de 960 ms. |

El texto principal mide 14,41:1 sobre papel claro y 15,34:1 sobre la superficie oscura. El texto del CTA mide 7,70:1 en claro y 8,07:1 en oscuro. El borde de los campos mide 4,11:1 y 5,71:1 sobre cada superficie. El isotipo violeta mide 5,38:1 sobre blanco.

Los formularios y el chat usan `KPopScaffold`, `KPopCard`, `KPopButton`, `KPopInput` y `KPopSheet`. El constructor usa dos paneles desde 1000 px y mantiene el compositor accesible con teclado abierto. En móvil, el POP revela la acción de vista previa en la misma pantalla. El usuario decide cuándo abrirla. El catálogo conserva la configuración visual por comercio y sus cálculos de carrito y checkout.

## Kiu

El dibujo Flutter adapta el cuerpo, núcleo, ojos, brazos y poses a partir de la Character Bible, Motion Bible y UX Guidelines de `kiuvy-character`, referencia `8ce2647`. El avatar compacto es estático. El personaje grande usa `CustomPainter` y `RepaintBoundary`. Sus controladores repintan el lienzo sin reconstruir el chat. Las animaciones se detienen al ocultar la app o la ruta. Cuando el sistema pide movimiento reducido, se muestra un Kiu estático y la vista previa se habilita en el siguiente frame después de confirmar readiness.

La burbuja empieza a inflarse cuando la sesión está construyendo y crece según el porcentaje confirmado por el servidor. El estallido es único por sesión y requiere recibir `store.ready` y una respuesta de sesión lista. El evento y la lectura inicial pueden llegar en distinto orden. Si la lectura posterior al evento falla dos veces, la app ofrece reintentar. Una sesión abierta cuando ya estaba lista revela su estado sin repetir la animación.

Se eligió el motor de Flutter porque ya admite el dibujo y su línea de tiempo en Android y Web, con pruebas y un fallback estático. El sistema canónico todavía no ofrece un rig `.riv` aprobado. La documentación del pack de marca registra geometría, licencia y reproducción. [Recursos de marca](../../development/KIUPOP_BRAND_ASSETS.md)
