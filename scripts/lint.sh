#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
unformatted="$(cd backend && gofmt -l .)"
[[ -z "$unformatted" ]] && ok "gofmt" || fail "gofmt: corre 'make fmt' → $unformatted"
(cd backend && go vet ./...) && ok "go vet"
(cd apps/web && dart format --output=none --set-exit-if-changed lib test >/dev/null) && ok "dart format" || fail "dart format: corre 'make fmt'"
(cd apps/web && flutter analyze --no-pub >/dev/null) && ok "flutter analyze" || { (cd apps/web && flutter analyze --no-pub); fail "flutter analyze"; }
"${COMPOSE[@]}" config -q && ok "compose config"
# Secret scan over git history (what gets published), not build artifacts.
if ! command -v gitleaks >/dev/null 2>&1; then
  warn "gitleaks no instalado: escaneo de secretos omitido localmente (CI sí lo corre)"
elif ! git rev-parse --git-dir >/dev/null 2>&1 || ! git rev-parse HEAD >/dev/null 2>&1; then
  warn "sin commits todavía: escaneo de secretos omitido"
else
  gitleaks detect --no-banner --redact --source . >/dev/null 2>&1 \
    && ok "gitleaks: historial sin secretos" \
    || fail "gitleaks encontró posibles secretos (gitleaks detect --redact -v)"
fi
