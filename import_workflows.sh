#!/bin/bash

################################################################################
# Importar MOD2 e MOD3 para n8n
# Uso: ./import_workflows.sh
################################################################################

set -e

API_KEY="${N8N_API_KEY:?Erro: configure N8N_API_KEY}"
BASE_URL="http://localhost:5678/api/v1"

echo "🔄 Importando workflows MOD2 e MOD3..."
echo ""

# 1. Importar MOD2
echo "[1/2] Importando MOD2 (Blacklist Cache)..."
MOD2_JSON=$(cat /opt/sdr-idv/workflows/mod2-blacklist-cache.json)

MOD2_RESPONSE=$(curl -s -X POST "$BASE_URL/workflows" \
  -H "X-N8N-API-KEY: $API_KEY" \
  -H "Content-Type: application/json" \
  -d "$MOD2_JSON" 2>/dev/null)

MOD2_ID=$(echo "$MOD2_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('id', ''))" 2>/dev/null || echo "")

if [ -z "$MOD2_ID" ]; then
  echo "❌ Erro ao importar MOD2"
  echo "Resposta: $MOD2_RESPONSE"
  exit 1
fi

echo "✓ MOD2 importado (ID: $MOD2_ID)"
echo ""

# 2. Importar MOD3
echo "[2/2] Importando MOD3 (Mineração Fila)..."
MOD3_JSON=$(cat /opt/sdr-idv/workflows/mod3-mineracao-fila.json)

MOD3_RESPONSE=$(curl -s -X POST "$BASE_URL/workflows" \
  -H "X-N8N-API-KEY: $API_KEY" \
  -H "Content-Type: application/json" \
  -d "$MOD3_JSON" 2>/dev/null)

MOD3_ID=$(echo "$MOD3_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('id', ''))" 2>/dev/null || echo "")

if [ -z "$MOD3_ID" ]; then
  echo "❌ Erro ao importar MOD3"
  echo "Resposta: $MOD3_RESPONSE"
  exit 1
fi

echo "✓ MOD3 importado (ID: $MOD3_ID)"
echo ""

# 3. Ativar workflows
echo "[3/3] Ativando workflows..."

curl -s -X PATCH "$BASE_URL/workflows/$MOD2_ID" \
  -H "X-N8N-API-KEY: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"active":true}' > /dev/null

curl -s -X PATCH "$BASE_URL/workflows/$MOD3_ID" \
  -H "X-N8N-API-KEY: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"active":true}' > /dev/null

echo "✓ Workflows ativados"
echo ""

# 4. Listar workflows
echo "📋 Workflows disponíveis:"
curl -s "$BASE_URL/workflows" \
  -H "X-N8N-API-KEY: $API_KEY" | python3 << 'EOF'
import sys, json
data = json.load(sys.stdin)
for wf in data.get('data', []):
    status = "🟢 Ativo" if wf.get('active') else "⚪ Inativo"
    print(f"  {status} — {wf.get('name')} (ID: {wf.get('id')})")
EOF

echo ""
echo "✅ Importação concluída!"
echo ""
echo "Próximos passos:"
echo "  1. Acesse http://157.230.210.188:5678"
echo "  2. Vá em Workflows"
echo "  3. Verifique MOD2 e MOD3 aparecem como 'Active'"
echo "  4. Execute ./test_mod3.sh para testar"
