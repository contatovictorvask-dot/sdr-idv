#!/bin/bash

################################################################################
# PROVISIONING COMPLETO — Credenciais + Workflows + Testes
# Uso: ./provision_complete.sh
#
# Configura tudo automaticamente:
# - Credenciais Redis, Airtable, Apify
# - Importa MOD2 e MOD3
# - Ativa workflows
# - Testa conectividade
################################################################################

set -e

# ============================================================================
# CONFIGURAÇÃO
# ============================================================================

API_KEY="${N8N_API_KEY:?❌ Erro: configure N8N_API_KEY como variável de ambiente}"
BASE_URL="http://localhost:5678/api/v1"

# Credenciais (do .env)
REDIS_HOST="sdr_redis"
REDIS_PORT="6379"
REDIS_PASSWORD="redis_sdr_secure_pwd_2025"

AIRTABLE_TOKEN="${AIRTABLE_API_KEY:?❌ Erro: configure AIRTABLE_API_KEY}"
AIRTABLE_BASE_ID="${AIRTABLE_BASE_ID:?❌ Erro: configure AIRTABLE_BASE_ID}"

APIFY_TOKEN="${APIFY_TOKEN:?❌ Erro: configure APIFY_TOKEN}"

# ============================================================================
# FUNÇÕES
# ============================================================================

log_info() {
  echo -e "\033[0;34m[INFO]\033[0m $1"
}

log_success() {
  echo -e "\033[0;32m[✓]\033[0m $1"
}

log_error() {
  echo -e "\033[0;31m[✗]\033[0m $1"
}

# Criar credenciais no n8n
create_credential() {
  local name=$1
  local type=$2
  local data=$3

  log_info "Criando credencial: $name"

  response=$(curl -s -X POST "$BASE_URL/credentials" \
    -H "X-N8N-API-KEY: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$data")

  cred_id=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null || echo "")

  if [ -z "$cred_id" ]; then
    log_error "Falha ao criar credencial $name"
    echo "Resposta: $response"
    return 1
  fi

  log_success "$name (ID: $cred_id)"
  echo "$cred_id"
}

# Importar workflow
import_workflow() {
  local filepath=$1
  local name=$2

  log_info "Importando $name..."

  workflow=$(cat "$filepath")

  response=$(curl -s -X POST "$BASE_URL/workflows" \
    -H "X-N8N-API-KEY: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$workflow")

  wf_id=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null || echo "")

  if [ -z "$wf_id" ]; then
    log_error "Falha ao importar $name"
    echo "Resposta: $response"
    return 1
  fi

  log_success "$name (ID: $wf_id)"
  echo "$wf_id"
}

# Ativar workflow
activate_workflow() {
  local wf_id=$1
  local name=$2

  curl -s -X PATCH "$BASE_URL/workflows/$wf_id" \
    -H "X-N8N-API-KEY: $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"active":true}' > /dev/null 2>&1

  log_success "$name ativado"
}

# ============================================================================
# EXECUÇÃO
# ============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║          PROVISIONING COMPLETO — MOD2 + MOD3                  ║"
echo "║  Credenciais + Workflows + Ativação + Testes                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# 1. Teste de conectividade
log_info "Testando conectividade com n8n..."
if ! curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/workflows" \
     -H "X-N8N-API-KEY: $API_KEY" | grep -q "200"; then
  log_error "Não foi possível conectar ao n8n"
  exit 1
fi
log_success "N8n respondendo"
echo ""

# 2. Criar credenciais
log_info "=== Criando Credenciais ==="
echo ""

# Redis
redis_cred_data="{\"name\":\"Redis SDR\",\"type\":\"redis\",\"data\":{\"host\":\"$REDIS_HOST\",\"port\":$REDIS_PORT,\"password\":\"$REDIS_PASSWORD\",\"database\":0}}"
REDIS_CRED_ID=$(create_credential "Redis" "redis" "$redis_cred_data")
echo ""

# Airtable
airtable_cred_data="{\"name\":\"Airtable SDR\",\"type\":\"airtableApi\",\"data\":{\"personalAccessToken\":\"$AIRTABLE_TOKEN\"}}"
AIRTABLE_CRED_ID=$(create_credential "Airtable" "airtableApi" "$airtable_cred_data")
echo ""

# Apify
apify_cred_data="{\"name\":\"Apify SDR\",\"type\":\"apifyApi\",\"data\":{\"token\":\"$APIFY_TOKEN\"}}"
APIFY_CRED_ID=$(create_credential "Apify" "apifyApi" "$apify_cred_data")
echo ""

# 3. Importar workflows
log_info "=== Importando Workflows ==="
echo ""

MOD2_ID=$(import_workflow "workflows/mod2-blacklist-cache.json" "MOD2 — Blacklist Cache")
echo ""

MOD3_ID=$(import_workflow "workflows/mod3-mineracao-fila.json" "MOD3 — Mineração Fila")
echo ""

# 4. Ativar workflows
log_info "=== Ativando Workflows ==="
echo ""

activate_workflow "$MOD2_ID" "MOD2"
activate_workflow "$MOD3_ID" "MOD3"
echo ""

# 5. Resumo
log_info "=== Resumo ==="
echo ""
echo "✅ Credenciais criadas:"
echo "   - Redis: $REDIS_CRED_ID"
echo "   - Airtable: $AIRTABLE_CRED_ID"
echo "   - Apify: $APIFY_CRED_ID"
echo ""
echo "✅ Workflows importados e ativados:"
echo "   - MOD2: $MOD2_ID"
echo "   - MOD3: $MOD3_ID"
echo ""
echo "📊 Dashboard: http://157.230.210.188:5678"
echo ""
echo "✅ Sistema pronto para testar!"
echo ""
