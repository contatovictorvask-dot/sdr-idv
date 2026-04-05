#!/usr/bin/env bash
# =============================================================================
# SDR PERPÉTUO B2B v2.0 — ATIVAÇÃO ETAPA 3
# Roda no servidor: bash scripts/ativar-etapa3.sh
# Pré-requisito: .env preenchido em infra/.env
# =============================================================================

set -euo pipefail

# ── Carrega variáveis do .env ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../infra/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Arquivo infra/.env não encontrado. Copie infra/.env.example e preencha."
  exit 1
fi

source "$ENV_FILE"

N8N_BASE_URL="http://localhost:5678"
N8N_AUTH_HEADER="X-N8N-API-KEY"

# ── Verifica API Key ──────────────────────────────────────────────────────────
if [[ -z "${N8N_API_KEY:-}" ]]; then
  echo ""
  echo "⚠️  N8N_API_KEY não encontrada no .env."
  echo "   Para gerar: n8n UI → Settings → API → Create API Key"
  echo ""
  read -rp "Cole aqui a API Key do n8n: " N8N_API_KEY
fi

# ── Função de requisição n8n ──────────────────────────────────────────────────
n8n_api() {
  local method="$1"
  local endpoint="$2"
  local body="${3:-}"
  local args=(-s -X "$method" "$N8N_BASE_URL/api/v1$endpoint" \
    -H "$N8N_AUTH_HEADER: $N8N_API_KEY" \
    -H "Content-Type: application/json")
  [[ -n "$body" ]] && args+=(-d "$body")
  curl "${args[@]}"
}

echo ""
echo "═══════════════════════════════════════════════"
echo "  SDR PERPÉTUO — Ativação Etapa 3"
echo "═══════════════════════════════════════════════"
echo ""

# ── 1. Verifica conexão com n8n ───────────────────────────────────────────────
echo "▶ Verificando conexão com n8n..."
HEALTH=$(curl -s --max-time 5 "$N8N_BASE_URL/healthz" || echo "ERRO")
if [[ "$HEALTH" != *"ok"* ]]; then
  echo "❌ n8n não responde em $N8N_BASE_URL"
  echo "   Verifique: docker compose ps"
  exit 1
fi
echo "✅ n8n acessível"
echo ""

# ── 2. Lista todos os workflows ───────────────────────────────────────────────
echo "▶ Buscando workflows importados..."
WORKFLOWS=$(n8n_api GET "/workflows?limit=50")
echo "$WORKFLOWS" | python3 -c "
import json, sys
data = json.load(sys.stdin)
wfs = data.get('data', [])
print(f'   Total encontrados: {len(wfs)}')
for w in wfs:
    status = '✅ ATIVO' if w.get('active') else '⏸  INATIVO'
    print(f'   {status} | {w[\"id\"]:20} | {w[\"name\"]}')
" 2>/dev/null || echo "   $WORKFLOWS"
echo ""

# ── 3. Ativa MOD2 e MOD3 ─────────────────────────────────────────────────────
echo "▶ Ativando workflows MOD2 e MOD3..."

activate_workflow() {
  local name_pattern="$1"
  local wf_id
  wf_id=$(echo "$WORKFLOWS" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for w in data.get('data', []):
    if '$name_pattern' in w.get('name',''):
        print(w['id'])
        break
" 2>/dev/null)

  if [[ -z "$wf_id" ]]; then
    echo "   ⚠️  Workflow '$name_pattern' não encontrado — importe o JSON no n8n primeiro."
    return 1
  fi

  RESULT=$(n8n_api PATCH "/workflows/$wf_id" '{"active": true}')
  if echo "$RESULT" | grep -q '"active":true'; then
    echo "   ✅ $name_pattern (ID: $wf_id) → ATIVADO"
  else
    echo "   ❌ Falha ao ativar $name_pattern: $RESULT"
    return 1
  fi
}

activate_workflow "MOD2" || true
activate_workflow "MOD3" || true

echo ""

# ── 4. Verifica credenciais configuradas ─────────────────────────────────────
echo "▶ Verificando credenciais no n8n..."
CREDS=$(n8n_api GET "/credentials")
echo "$CREDS" | python3 -c "
import json, sys
data = json.load(sys.stdin)
creds = data.get('data', [])
print(f'   Total de credenciais: {len(creds)}')
for c in creds:
    print(f'   ✅ {c[\"name\"]:30} | tipo: {c[\"type\"]}')
" 2>/dev/null || echo "   $CREDS"
echo ""

# ── 5. Verifica conectividade Redis ──────────────────────────────────────────
echo "▶ Verificando Redis..."
if docker exec sdr_redis redis-cli -a "${REDIS_PASSWORD:-}" ping 2>/dev/null | grep -q PONG; then
  echo "✅ Redis respondendo"
else
  echo "⚠️  Redis não acessível via docker exec — verifique: docker compose ps redis"
fi
echo ""

# ── 6. Verifica conectividade Airtable ───────────────────────────────────────
echo "▶ Verificando Airtable..."
if [[ -n "${AIRTABLE_API_KEY:-}" ]]; then
  AT_RESP=$(curl -s --max-time 10 \
    "https://api.airtable.com/v0/${AIRTABLE_BASE_ID:-app9BlRhuDFuRfyHi}/SDR_Operacional?maxRecords=1" \
    -H "Authorization: Bearer $AIRTABLE_API_KEY")
  if echo "$AT_RESP" | grep -q '"records"'; then
    TOTAL=$(echo "$AT_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('records',[])))" 2>/dev/null)
    echo "✅ Airtable acessível — ${TOTAL} registro(s) retornado(s) da tabela SDR_Operacional"
  else
    echo "❌ Erro Airtable: $AT_RESP"
  fi
else
  echo "⚠️  AIRTABLE_API_KEY não definida no .env"
fi
echo ""

# ── 7. Verifica Evolution API ─────────────────────────────────────────────────
echo "▶ Verificando Evolution API..."
EVO_RESP=$(curl -s --max-time 5 \
  "http://localhost:8080/instance/fetchInstances" \
  -H "apikey: ${EVOLUTION_API_KEY:-}" 2>/dev/null || echo "ERRO")
if echo "$EVO_RESP" | grep -qiE '"instance"|"instanceName"'; then
  echo "✅ Evolution API respondendo"
  echo "$EVO_RESP" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    instances = data if isinstance(data, list) else data.get('data', [])
    for i in instances:
        name = i.get('instance',{}).get('instanceName', i.get('instanceName','?'))
        state = i.get('instance',{}).get('connectionStatus', i.get('state','?'))
        print(f'   Instância: {name} | Status: {state}')
except: pass
" 2>/dev/null
else
  echo "⚠️  Evolution API sem resposta — instância WhatsApp pode não estar conectada"
fi
echo ""

# ── Resumo ────────────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════"
echo "  RESUMO ETAPA 3"
echo "═══════════════════════════════════════════════"
echo ""
echo "✅ Verificação concluída."
echo ""
echo "Próximo passo obrigatório (manual):"
echo "  → No n8n UI, em MOD2, clique em 'Set up credential' no nó"
echo "    'GET Blacklist (Sheets)' e autorize a conta Google."
echo "    (necessário para blacklist funcionar — não afeta MOD3 se Redis já tiver cache)"
echo ""
echo "Para testar o webhook MOD3, execute:"
echo "  bash scripts/testar-webhook.sh"
echo ""
