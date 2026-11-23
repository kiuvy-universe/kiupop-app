#!/usr/bin/env bash
# Verifies the running stack end to end. Exit code != 0 on any failure.
source "$(dirname "$0")/lib.sh"
API="http://127.0.0.1:${API_HOST_PORT:-8080}"

body="$(curl -fsS "$API/healthz")" || fail "/healthz no responde (¿make up?)"
[[ $body == *'"status":"ok"'* ]] && ok "/healthz → $body" || fail "/healthz inesperado: $body"

body="$(curl -fsS "$API/readyz")" || fail "/readyz no está listo"
[[ $body == *'"database":"up"'* ]] && ok "/readyz → base de datos arriba" || fail "/readyz: $body"

body="$(curl -fsS "$API/api/v1/demo/info")" || fail "/api/v1/demo/info no responde"
[[ $body == *'"kiuvy_integration":"disabled"'* ]] && ok "/api/v1/demo/info → integración Kiuvy deshabilitada" || fail "info: $body"

body="$(curl -fsS "$API/api/v1/demo/products")" || fail "/api/v1/demo/products no responde"
[[ $body == *'"source":"postgres"'* ]] || fail "products no viene de postgres: $body"
api_count="$(grep -o '"id":' <<<"$body" | wc -l | tr -d ' ')"
db_count="$("${COMPOSE[@]}" exec -T postgres psql -U "${POSTGRES_USER:-kiupop}" -d "${POSTGRES_DB:-kiupop}" -tAc 'SELECT count(*) FROM demo_products')"
[[ "$api_count" == "$db_count" && "$db_count" -ge 1 ]] \
  && ok "/api/v1/demo/products → $api_count productos = $db_count filas en PostgreSQL" \
  || fail "API devolvió $api_count productos pero PostgreSQL tiene $db_count"

origin="http://localhost:${WEB_PORT:-3000}"
allow="$(curl -fsS -o /dev/null -D - -H "Origin: $origin" "$API/healthz" | tr -d '\r' | awk -F': ' 'tolower($1)=="access-control-allow-origin"{print $2}')"
[[ "$allow" == "$origin" ]] && ok "CORS permite $origin" || fail "CORS no permite $origin"
code="$(curl -s -o /dev/null -w '%{http_code}' -X OPTIONS -H 'Origin: https://evil.example' -H 'Access-Control-Request-Method: GET' "$API/healthz")"
[[ "$code" == "403" ]] && ok "CORS rechaza orígenes ajenos (403)" || fail "preflight ajeno devolvió $code"

for svc in api postgres auth-emulator; do
  ports="$("${COMPOSE[@]}" ps "$svc" --format '{{.Ports}}')"
  [[ "$ports" == 127.0.0.1:* ]] && ok "$svc publicado solo en loopback ($ports)" || fail "$svc expuesto fuera de loopback: $ports"
done
# --- POC flow: store → product → photo → catalog → WhatsApp preview -----------
json() { python3 -c "import json,sys;d=json.load(sys.stdin);print(eval('d'+sys.argv[1]))" "$1"; }
created="$(curl -fsS -X POST "$API/api/v1/stores" -H 'Content-Type: application/json' \
  -d "{\"name\":\"Smoke $(date +%s%N)\",\"whatsapp\":\"+506 0000 0001\"}")" || fail "POST /api/v1/stores falló"
token="$(json "['admin_token']" <<<"$created")"; slug="$(json "['store']['slug']" <<<"$created")"
[[ $token == kp_* ]] && ok "tienda creada ($slug) con credencial de un solo uso" || fail "sin credencial"
auth=(-H "Authorization: Bearer $token")
pid="$(curl -fsS -X POST "$API/api/v1/admin/products" "${auth[@]}" -H 'Content-Type: application/json' \
  -d '{"name":"Rosa roja","price_minor":100000}' | json "['id']")" || fail "crear producto falló"
png="$(mktemp)"; printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' | base64 -d > "$png"
img="$(curl -fsS -X POST "$API/api/v1/admin/products/$pid/image" "${auth[@]}" -F "image=@$png;type=image/png" | json "['image_url']")" || fail "subir foto falló"
rm -f "$png"
[[ "$(curl -s -o /dev/null -w '%{http_code}' "$API$img")" == 200 ]] && ok "foto guardada en el volumen y servida" || fail "foto no servida"
cat_body="$(curl -fsS "$API/api/v1/public/stores/$slug/products")"
[[ $cat_body == *'Rosa roja'* && $cat_body != *"$token"* ]] && ok "catálogo público sin credencial" || fail "catálogo: $cat_body"
preview="$(curl -fsS -X POST "$API/api/v1/public/stores/$slug/orders/preview" -H 'Content-Type: application/json' \
  -d "{\"items\":[{\"product_id\":\"$pid\",\"quantity\":2}]}")" || fail "preview falló"
[[ "$(json "['total_minor']" <<<"$preview")" == 200000 && $preview == *'https://wa.me/50600000001?text='* ]] \
  && ok "pedido calculado en el servidor (₡2.000) con enlace wa.me" || fail "preview: $preview"
[[ "$(curl -s -o /dev/null -w '%{http_code}' "$API/api/v1/admin/products")" == 401 ]] && ok "admin sin credencial → 401" || fail "admin abierto"

# --- KPOP-AGENT-001: sign-up (emulator) → Kiu → POP → publish → share → test checkout ---
EMU="http://localhost:${AUTH_EMULATOR_HOST_PORT:-9199}"
idtok="$(curl -fsS -X POST "$EMU/identitytoolkit.googleapis.com/v1/accounts:signUp?key=smoke" -H 'Content-Type: application/json' \
  -d "{\"email\":\"smoke-$(date +%s%N)@example.test\",\"password\":\"smoke-secret\",\"returnSecureToken\":true}" | json "['idToken']")" \
  || fail "registro en el emulador falló"
ua=(-H "Authorization: Bearer $idtok" -H 'Content-Type: application/json')
[[ "$(curl -s -o /dev/null -w '%{http_code}' "$API/api/v1/me" -H 'Authorization: Bearer eyJhbGciOiJub25lIn0.eyJzdWIiOiJ4In0.x')" == 401 ]] \
  && ok "token falsificado → 401" || fail "token falsificado aceptado"
sid="$(curl -fsS -X POST "$API/api/v1/agent/sessions" "${ua[@]}" | json "['id']")" || fail "iniciar Kiu falló"
say() { curl -fsS -X POST "$API/api/v1/agent/sessions/$sid/messages" "${ua[@]}" -d "{\"text\":\"$1\",\"client_message_id\":\"smoke-$2-$sid\"}"; }
q1="$(say "Soy Smoke Flores $(date +%s), vendo flores y arreglos. Quiero algo elegante en rosado. Entrego en Naranjo." 1 | json "['pending_question']['field']")"
if [[ $q1 == channels ]]; then
  # KIU_DISCOVERY_ENABLED=true: diagnóstico antes de construir (canal → dolor → plan → aceptar).
  ok "Kiu diagnostica antes de construir: ¿por dónde te compran?"
  q1b="$(say "Me compran por WhatsApp" 1b | json "['pending_question']['field']")"
  [[ $q1b == pain ]] && ok "luego pregunta qué es lo que más cuesta" || fail "pregunta de dolor: $q1b"
  kind="$(say "Responder precios uno por uno" 1c | json "['messages'][-1]['meta']['kind']")"
  [[ $kind == plan ]] && ok "Kiu recomienda un plan y espera tu visto bueno" || fail "plan: $kind"
  q1="$(say "Sí, armemos esto" 1d | json "['pending_question']['field']")"
fi
[[ $q1 == prices ]] && ok "Kiu entendió el negocio y preguntó solo lo que falta (precios)" || fail "primera pregunta: $q1"
q2="$(say "Ramo de rosas 15000 y arreglo de girasoles 18 mil" 2 | json "['pending_question']['field']")"
[[ $q2 == whatsapp ]] && ok "precios tomados de tus palabras; siguiente: WhatsApp" || fail "segunda pregunta: $q2"
say "Mi WhatsApp es 8888-1234" 3 >/dev/null
for _ in $(seq 1 50); do
  st="$(curl -fsS "$API/api/v1/agent/sessions/$sid" "${ua[@]}" | json "['status']")"; [[ $st == ready ]] && break; sleep 0.1
done
[[ $st == ready ]] && ok "tienda lista (POP) tras validar readiness en el backend" || fail "estado: $st"
[[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API/api/v1/agent/sessions/$sid/publish" "${ua[@]}" -d '{"confirm":false}')" == 400 ]] \
  && ok "publicar exige confirmación explícita" || fail "publicó sin confirmar"
paywall="$(curl -fsS "$API/api/v1/agent/sessions/$sid" "${ua[@]}" | json "['paywall']['required']")"
if [[ $paywall == True ]]; then
  [[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API/api/v1/agent/sessions/$sid/publish" "${ua[@]}" -d '{"confirm":true}')" == 402 ]] \
    && ok "paywall: sin plan no se publica (402 plan_required)" || fail "publicó sin plan"
  plan="$(curl -fsS -X POST "$API/api/v1/agent/sessions/$sid/plan" "${ua[@]}" -d '{"confirm":true}')" || fail "activar plan falló"
  [[ "$(json "['plan']['price_minor']" <<<"$plan")" == 500 && "$(json "['mode']" <<<"$plan")" == test ]] \
    && ok "plan US\$5/mes activo con pago de prueba (sin dinero real)" || fail "plan: $plan"
fi
pub="$(curl -fsS -X POST "$API/api/v1/agent/sessions/$sid/publish" "${ua[@]}" -d '{"confirm":true}')" || fail "publicar falló"
pslug="$(json "['slug']" <<<"$pub")"
sf="$(curl -fsS "$API/api/v1/public/stores/$pslug/storefront")" || fail "tienda pública falló"
[[ $sf == *'"price_minor":1500000'* && $sf == *'"real_payments_enabled":false'* ]] && ok "tienda pública con precios del comercio y pagos reales apagados" || fail "storefront: $sf"
og="$(curl -fsS "$API/p/$pslug")"; [[ $og == *'og:title'* ]] && ok "enlace para compartir con Open Graph (/p/$pslug)" || fail "OG"
[[ "$(curl -s -o /dev/null -w '%{content_type}' "$API/og/$pslug.png")" == image/png ]] && ok "portada OG generada" || fail "OG png"
ppid="$(json "['products'][0]['id']" <<<"$sf")"
pay="$(curl -fsS -X POST "$API/api/v1/public/stores/$pslug/checkout" -H 'Content-Type: application/json' \
  -d "{\"items\":[{\"product_id\":\"$ppid\",\"quantity\":1}],\"idempotency_key\":\"smoke-$sid\"}")" || fail "checkout falló"
[[ "$(json "['mode']" <<<"$pay")" == test ]] && ok "checkout en modo de prueba (sin dinero real)" || fail "checkout: $pay"

echo; ok "Smoke OK: flujo KiuPop completo sobre Go API ↔ PostgreSQL"
