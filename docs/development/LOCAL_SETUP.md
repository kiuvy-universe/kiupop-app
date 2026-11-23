# Setup local

## 1. Herramientas
| Herramienta | Versión probada | Verificar |
|---|---|---|
| Go | 1.26+ (probado 1.27.3 host / 1.26.10 imagen) | `go version` |
| Flutter | 3.47.x stable (Dart 3.13) | `flutter --version` |
| Docker + Compose v2 | 29.x / 2.40 | `docker compose version` |
| Make, curl, git | cualquiera reciente | — |
| Chrome | estable | `flutter devices` |

`make setup` detecta lo que falta, pero no instala nada global ni usa sudo.

**Windows:** trabaja dentro de WSL2 (Ubuntu). Clona el repo en el filesystem de Linux (`~/code`), no en `/mnt/c`. Docker Desktop con integración WSL. Flutter para web puede correr dentro de WSL con `make web` si defines `CHROME_EXECUTABLE`, o usa `flutter run -d web-server --web-port=3000` y abre la URL en el Chrome de Windows.

**macOS:** Docker Desktop u OrbStack. Todo lo demás es igual.

## 2. Primer arranque
```bash
git clone https://github.com/kiuvy-universe/kiupop.git && cd kiupop
make setup
make dev
```
Verás KiuPop en http://localhost:3000 con «API local conectada · 3 productos de demostración desde PostgreSQL».

## 3. Día a día
| Quiero… | Comando |
|---|---|
| Levantar o actualizar API y DB | `make up` (reconstruye la imagen si cambió Go) |
| Iterar Go sin rebuild de Docker | `make up` y luego `docker compose -p kiupop stop api` y `make api-host` |
| Hot reload de Flutter | `make web` y luego `r` en la terminal (`R` = restart) |
| App nativa en un teléfono Android por USB | `make android` (ver abajo) |
| Ver logs | `make logs` |
| Verificar todo | `make smoke` |
| Detener (conserva datos) | `make down` |
| Base desde cero | `make reset-db` (confirma escribiendo `borrar`) |
| Conectarme con psql | `psql postgres://kiupop:kiupop_local_only@127.0.0.1:5433/kiupop` |

### App Android en un teléfono físico
La misma app Flutter compila para Android (`com.kiuvy.kiupop`). Requisitos: Android SDK 36 (`flutter doctor`),
depuración USB activada y el teléfono autorizado (`adb devices` debe decir `device`, no `unauthorized`).

`make up` y luego `make android`: hace `adb reverse` de los puertos 3000, 8080 y 9199 (el teléfono ve `localhost`
igual que la PC, nada se expone en la red Wi‑Fi) y corre la app en modo debug con hot reload.
Solo el build debug permite HTTP, y solo hacia `localhost` (`android/app/src/debug/res/xml/network_security_config.xml`);
release exige HTTPS. Al desconectar el cable se pierde el `adb reverse`: vuelve a correr `make android`.

En Android: sesión en SharedPreferences, selector de archivos del sistema, menú de compartir nativo y dictado
con el reconocedor de voz del teléfono (pide el micrófono la primera vez; KiuPop no guarda audio). Los enlaces
públicos usan `PUBLIC_WEB_BASE` (por defecto `http://localhost:3000`). Las actualizaciones en vivo usan long-poll
(en el navegador, SSE).

## 4. Aislamiento
El proyecto Compose se llama `kiupop`: contenedores `kiupop-*`, red `kiupop_backend` y volumen `kiupop_pgdata`. `make down` y `make reset-db` solo tocan esos recursos. Si ya usas los puertos 5433, 8080 o 3000, cámbialos en `.env` (y `API_BASE_URL` si cambias la API).
