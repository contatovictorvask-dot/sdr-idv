#!/usr/bin/env bash
# =============================================================================
# SDR PERPÉTUO B2B v2.0 — TESTE DO WEBHOOK MOD3
# Roda no servidor: bash scripts/testar-webhook.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../infra/.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

N8N_HOST="${N8N_HOST:-localhost}"
WEBHOOK_URL="http://${N8N_HOST}:5678/webhook/missao-semanal"

echo ""
echo "═══════════════════════════════════════════════"
echo "  SDR PERPÉTUO — Teste Webhook MOD3"
echo "═══════════════════════════════════════════════"
echo ""
echo "Endpoint: $WEBHOOK_URL"
echo ""

# Payload de teste — nicho + cidade + meta pequena para não gastar cota Apify
PAYLOAD='{
  "nicho": "Salão de Beleza",
  "cidades": ["São Paulo"],
  "meta_semanal": 10
}'

echo "▶ Enviando missão de teste..."
echo "  Payload: $PAYLOAD"
echo ""

RESPONSE=$(curl -s --max-time 120 \
  -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

echo "▶ Resposta do webhook:"
echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
echo ""

# ── Verifica resultado no Airtable ───────────────────────────────────────────
if [[ -n "${AIRTABLE_API_KEY:-}" ]]; then
  echo "▶ Verificando leads criados no Airtable (Status=Curadoria)..."
  sleep 3  # aguarda processamento assíncrono

  AT_RESP=$(curl -s --max-time 15 \
    "https://api.airtable.com/v0/${AIRTABLE_BASE_ID:-app9BlRhuDFuRfyHi}/SDR_Operacional?filterByFormula=%7BStatus%7D%3D%22Curadoria%22&maxRecords=5&sort[0][field]=Data_Entrada&sort[0][direction]=desc" \
    -H "Authorization: Bearer $AIRTABLE_API_KEY")

  echo "$AT_RESP" | python3 -c "
import json, sys
data = json.load(sys.stdin)
records = data.get('records', [])
print(f'   Leads em Curadoria (últimos 5): {len(records)}')
for r in records:
    f = r.get('fields', {})
    print(f'   @{f.get(\"Username\",\"?\")} | Score: {f.get(\"Lead_Score\",0)} | Nicho: {f.get(\"Nicho\",\"?\")}')
" 2>/dev/null || echo "   $AT_RESP"
fi

echo ""
echo "═══════════════════════════════════════════════"
echo "Se apareceram leads acima: MOD3 funcionando ✅"
echo "Se retornou erro: verifique logs em n8n UI"
echo "   → http://\${N8N_HOST}:5678"
echo "═══════════════════════════════════════════════"
echo ""
