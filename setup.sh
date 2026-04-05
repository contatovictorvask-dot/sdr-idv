#!/bin/bash

################################################################################
# SETUP AUTOMÁTICO — Executa tudo sem interação manual
#
# USO (uma linha só):
# curl -sSL https://raw.githubusercontent.com/contatovictorvask-dot/sdr-idv/claude/etapa-3-W7NEA/setup.sh | bash -s -- API_KEY AIRTABLE_KEY BASE_ID APIFY_TOKEN
#
# OU localmente:
# bash setup.sh eyJhbGc... pat6jc... appXXX... apify_api_...
################################################################################

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parâmetros (passados como argumentos)
N8N_API_KEY="${1:?Erro: faltando N8N_API_KEY}"
AIRTABLE_API_KEY="${2:?Erro: faltando AIRTABLE_API_KEY}"
AIRTABLE_BASE_ID="${3:?Erro: faltando AIRTABLE_BASE_ID}"
APIFY_TOKEN="${4:?Erro: faltando APIFY_TOKEN}"

# Configuração
BASE_URL="http://localhost:5678/api/v1"
REDIS_HOST="sdr_redis"
REDIS_PORT="6379"
REDIS_PASSWORD="redis_sdr_secure_pwd_2025"

# ============================================================================
# FUNÇÕES
# ============================================================================

log() { echo -e "${BLUE}[*]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

test_n8n() {
  log "Testando conectividade n8n..."
  if curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/workflows" \
       -H "X-N8N-API-KEY: $N8N_API_KEY" | grep -q "200"; then
    success "N8n respondendo"
    return 0
  else
    error "N8n não acessível"
  fi
}

create_credential() {
  local name=$1
  local type=$2
  local data=$3

  response=$(curl -s -X POST "$BASE_URL/credentials" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$data")

  cred_id=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null || echo "")

  if [ -z "$cred_id" ]; then
    error "Falha ao criar $name"
  fi

  success "$name criado"
  echo "$cred_id"
}

import_and_activate() {
  local filepath=$1
  local name=$2

  # Importar
  workflow=$(cat "$filepath")
  response=$(curl -s -X POST "$BASE_URL/workflows" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$workflow")

  wf_id=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null || echo "")

  if [ -z "$wf_id" ]; then
    error "Falha ao importar $name"
  fi

  # Ativar
  curl -s -X PATCH "$BASE_URL/workflows/$wf_id" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"active":true}' > /dev/null 2>&1

  success "$name importado e ativado (ID: $wf_id)"
  echo "$wf_id"
}

# ============================================================================
# EXECUÇÃO
# ============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║           ⚡ SETUP AUTOMÁTICO — MOD2 + MOD3                   ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# 1. Verificar diretório
if [ ! -d "workflows" ]; then
  error "Executar do diretório /opt/sdr-idv"
fi

# 2. Teste
test_n8n
echo ""

# 3. Credenciais
log "Criando credenciais..."
create_credential "Redis" "redis" "{\"name\":\"Redis SDR\",\"type\":\"redis\",\"data\":{\"host\":\"$REDIS_HOST\",\"port\":$REDIS_PORT,\"password\":\"$REDIS_PASSWORD\",\"database\":0}}" > /dev/null
create_credential "Airtable" "airtableApi" "{\"name\":\"Airtable SDR\",\"type\":\"airtableApi\",\"data\":{\"personalAccessToken\":\"$AIRTABLE_API_KEY\"}}" > /dev/null
create_credential "Apify" "apifyApi" "{\"name\":\"Apify SDR\",\"type\":\"apifyApi\",\"data\":{\"token\":\"$APIFY_TOKEN\"}}" > /dev/null
echo ""

# 4. Workflows
log "Importando workflows..."
import_and_activate "workflows/mod2-blacklist-cache.json" "MOD2 — Blacklist Cache" > /dev/null
import_and_activate "workflows/mod3-mineracao-fila.json" "MOD3 — Mineração Fila" > /dev/null
echo ""

# 5. Sucesso
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    ✅ SETUP CONCLUÍDO!                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "📊 Acesse: http://157.230.210.188:5678"
echo "   Workflows → MOD2 e MOD3 devem estar 🟢 Active"
echo ""
echo "🚀 Próximo: Testar webhook MOD3"
echo ""
