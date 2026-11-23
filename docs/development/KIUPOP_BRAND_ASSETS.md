# Identidad KiuPop

## Origen y permisos

El [maestro SVG](../../apps/web/tool/brand/kiupop-mark.svg) conserva la elipse, la rotación, el grosor y el punto del isotipo oficial de Kiuvy. Usa violeta chicle `#8F45CD` sobre blanco puro. La referencia es `kiuvy-pos/public/brand/kiuvy-mark.svg` en el commit `5e0f8c85937d4cc606115c85663b704d9c739c6a`. El brief KPOP-DESIGN-001 autoriza la adaptación del isotipo para KiuPop. Es un recurso de marca Kiuvy y no se le asigna una licencia abierta. El nombre KiuPop se compone en Plus Jakarta Sans por separado del isotipo. La fuente viene con su [licencia SIL OFL 1.1](../../apps/web/assets/fonts/OFL-PlusJakartaSans.txt).

## Exportación

Desde la raíz del repositorio, con Python 3 y Pillow 12.1.1.

```sh
python3 apps/web/tool/brand/export.py
python3 apps/web/tool/brand/export.py --check
```

El script lee el maestro y genera PNG y trazados VectorDrawable con la misma geometría. Usamos los recursos nativos de Android y Web para evitar dependencias en la aplicación. `flutter_launcher_icons` y `flutter_native_splash` son alternativas de generación para proyectos con más plataformas. Los vectores de lanzamiento de esta app mantienen trazos y máscaras separados y tienen recursos por versión de Android.

| Destino | Exportación |
| --- | --- |
| Flutter | `assets/brand/kiupop-mark.png`, 144 × 144 para el encabezado y pantallas de acceso |
| Android 24–25 | PNG legacy de 48, 72, 96, 144 y 192 px |
| Android 26+ | Fondo blanco y VectorDrawable de color para el icono adaptativo |
| Android 33+ | Capa monocromática blanca con transparencia para el icono temático |
| Notificaciones Android | `@drawable/ic_kiupop_notification`, máscara de 24 dp disponible para el icono pequeño |
| Arranque Android | Capa centrada en 24–30 y splash del sistema en 31+, ambos con colores según el sistema |
| Web | Favicon PNG de 32 px e iconos PWA de 192 y 512 px, con variantes maskable |
| Social KiuPop | `web/icons/kiupop-og.png`, portada PNG de 1200 × 630 para la URL pública de la app. Desde KPOP-UX-002 es una losa de arcilla sobre crema con puntos pastel |
| iOS | SVG maestro disponible para exportar cuando se agregue la plataforma |

Cuando exista una URL pública para la portada de KiuPop, el metadato `og:image` de la app debe apuntar a la URL HTTPS absoluta de la imagen. Los enlaces a cada tienda ya reciben metadatos e imagen desde la ruta del comercio en Go.

## Comprobaciones

El exportador verifica un radio de 31,7 dp dentro del círculo seguro Android de 33 dp, 87,5 dp dentro de los 96 dp seguros del splash de Android 12+, y un radio de 38,5 % dentro del 40 % seguro de iconos web maskable. AAPT2 36 compiló y enlazó los recursos con Android SDK 36 y confirmó los recursos del launcher por densidad y versión. Se verificaron los tamaños de los PNG, el blanco del fondo web, la transparencia de las esquinas legacy y los píxeles visibles de ambos iconos maskable. El Infinix X6871 mostró el isotipo completo dentro de la máscara del launcher en Android 15. [Captura física](../specs/KPOP-DESIGN-001/evidence/infinix-launcher.webp)

[Iconos adaptativos Android](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive) · [Splash Android](https://developer.android.com/develop/ui/views/launch/splash-screen) · [Iconos maskable de PWA](https://web.dev/articles/maskable-icon)

## Paleta de arranque (KPOP-UX-002)

El isotipo y el icono no cambian: violeta chicle `#8F45CD` sobre blanco. El splash de Android, `manifest.json`, `theme-color` y el fondo previo al primer frame Web usan crema `#FBF5EB` en claro y noche `#1C1920` en oscuro, los mismos tokens de `AppTheme`. Kiu, las nubes y las superficies cerámicas se dibujan en código Flutter con base en la Character Bible de `kiuvy-character`. Son recursos de marca Kiuvy y no llevan licencia abierta. Plus Jakarta Sans conserva su licencia SIL OFL 1.1.

## Instalación QA junto a la app

`KIUPOP_ID_SUFFIX=.qa flutter build apk …` instala `com.kiuvy.kiupop.qa` con el nombre «KiuPop qa» sin reemplazar la app del teléfono. El valor debe tener la forma `.[a-z0-9]{1,16}`. Sin la variable, el ID y el nombre son los de siempre. No se usa en builds reales.
