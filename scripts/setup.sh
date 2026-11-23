#!/usr/bin/env bash
# Idempotent: safe to run any number of times. Never uses sudo, never installs global software.
source "$(dirname "$0")/lib.sh"

missing=0
need() { # tool, hint
  if command -v "$1" >/dev/null 2>&1; then ok "$1 encontrado"; else warn "$1 no encontrado — $2"; missing=1; fi
}
need git     "https://git-scm.com/downloads"
need go      "Go 1.26+: https://go.dev/dl/"
need flutter "Flutter stable: https://docs.flutter.dev/get-started/install"
need docker  "Docker Engine/Desktop: https://docs.docker.com/get-docker/"
need curl    "instala curl con el gestor de paquetes de tu sistema"
if command -v docker >/dev/null 2>&1; then
  docker compose version >/dev/null 2>&1 && ok "docker compose disponible" || { warn "docker compose v2 no disponible"; missing=1; }
  docker info >/dev/null 2>&1 && ok "Docker daemon activo" || { warn "Docker daemon no responde (¿está iniciado? ¿tu usuario está en el grupo docker?)"; missing=1; }
fi
[[ $missing -eq 0 ]] || fail "Faltan herramientas. Instálalas y vuelve a correr 'make setup'."

if [[ -f .env ]]; then ok ".env ya existe (no se sobrescribe)"; else cp .env.example .env; ok ".env creado desde .env.example"; fi
ENV_FILE=.env; COMPOSE=(docker compose --env-file .env -f infra/compose.yaml)

go_ver="$(go env GOVERSION | sed 's/^go//')"
[[ "$(printf '%s\n1.26\n' "$go_ver" | sort -V | head -1)" == "1.26" ]] || fail "Go $go_ver es muy viejo; se requiere 1.26+"

(cd backend && go mod download) && ok "dependencias Go"
(cd apps/web && flutter pub get >/dev/null) && ok "dependencias Flutter"
"${COMPOSE[@]}" config -q && ok "compose válido"
"${COMPOSE[@]}" pull --quiet postgres && "${COMPOSE[@]}" build --quiet api && ok "imágenes listas"

for port in "${POSTGRES_HOST_PORT:-5433}" "${API_HOST_PORT:-8080}" "${WEB_PORT:-3000}"; do
  if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
    if ! "${COMPOSE[@]}" ps --format '{{.Ports}}' 2>/dev/null | grep -q ":$port->"; then
      warn "el puerto $port ya está en uso por otro proceso; cámbialo en .env"
    fi
  fi
done
echo; ok "Listo. Siguiente paso: make dev"
