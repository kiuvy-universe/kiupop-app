#!/usr/bin/env bash
# Makes ONE real KiuPop AI request through the running API (costs a few cents at most).
# Never prints the API key or the admin token.
source "$(dirname "$0")/lib.sh"
API="http://127.0.0.1:${API_HOST_PORT:-8080}"
json() { python3 -c "import json,sys;d=json.load(sys.stdin);print(eval('d'+sys.argv[1]))" "$1"; }

created="$(curl -fsS -X POST "$API/api/v1/stores" -H 'Content-Type: application/json' \
  -d "{\"name\":\"AI smoke $(date +%s)\",\"whatsapp\":\"+506 0000 0001\"}")" || fail "no pude crear la tienda de prueba (¿make up?)"
[[ "$(json "['features']['ai']" <<<"$created")" == "True" ]] \
  || fail "KiuPop AI está deshabilitada: pon AI_ENABLED=true y ANTHROPIC_API_KEY en .env y corre make up"
token="$(json "['admin_token']" <<<"$created")"

started=$(date +%s%N)
res="$(curl -sS -w '\n%{http_code}' -X POST "$API/api/v1/admin/ai/product-description" \
  -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
  -d '{"text":"Rosa roja natural para regalo, cuesta 2000 colones."}')"
code="${res##*$'\n'}"; body="${res%$'\n'*}"
ms=$(( ($(date +%s%N) - started) / 1000000 ))
[[ $code == 200 ]] || fail "respuesta $code: $body"
ok "Llamada real a Claude en ${ms} ms"
python3 -c "import json,sys;d=json.load(sys.stdin);[print(f'  {k}: {d[k]}') for k in ('name','short_description','marketing_text','generated_by')]" <<<"$body"
python3 -c "
import json,re,sys
d=json.load(sys.stdin); t=' '.join(d[k] for k in ('name','short_description','marketing_text'))
sys.exit(1 if re.search(r'(₡|colones?|precio|descuento|oferta|\d+\s*%)', t, re.I) else 0)" <<<"$body" \
  && ok "sin precios ni promociones inventadas" || fail "la sugerencia menciona precios"
docker compose --env-file "$ENV_FILE" -f infra/compose.yaml logs api --since 2m 2>/dev/null | grep -o '"msg":"ai generation"[^}]*' | tail -1 | sed 's/^/  log: /'
