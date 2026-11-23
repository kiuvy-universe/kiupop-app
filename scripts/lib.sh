# Shared helpers for KiuPop scripts. Source it; do not execute.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [[ -t 1 ]]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; N=$'\033[0m'; else G=; R=; Y=; N=; fi
ok()   { echo "${G}✓${N} $*"; }
warn() { echo "${Y}!${N} $*"; }
fail() { echo "${R}✗${N} $*" >&2; exit 1; }
ENV_FILE=".env"; [[ -f $ENV_FILE ]] || ENV_FILE=".env.example"
COMPOSE=(docker compose --env-file "$ENV_FILE" -f infra/compose.yaml)
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
