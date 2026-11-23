#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
"${COMPOSE[@]}" up -d --build --wait
ok "PostgreSQL y API arriba (http://localhost:${API_HOST_PORT:-8080}/healthz)"
cat <<MSG

  KiuPop Web → http://localhost:${WEB_PORT:-3000}
  Hot reload: tecla r en esta terminal · Hot restart: R · Salir: q o Ctrl+C
  Ctrl+C detiene solo Flutter. Los servicios y los datos siguen arriba.
  Para detenerlos: make down   ·   Logs: make logs

MSG
cd apps/web
exec flutter run -d chrome --web-port="${WEB_PORT:-3000}" --dart-define=API_BASE_URL="${API_BASE_URL:-http://localhost:8080}"
