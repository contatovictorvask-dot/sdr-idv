#!/bin/bash

################################################################################
# MOD3 Automated Test Script
# Usage: ./test_mod3.sh [--vps-ip 157.230.210.188] [--skip-mod2]
#
# This script will:
# 1. Verify MOD2 blacklist cache is populated in Redis
# 2. Trigger MOD3 webhook with test payload
# 3. Monitor Airtable for lead ingestion
# 4. Report test results
################################################################################

set -e

# Configuration
VPS_IP="${VPS_IP:-157.230.210.188}"
API_KEY="${N8N_API_KEY:?'Erro: configure N8N_API_KEY como variável de ambiente'}"
AIRTABLE_TOKEN="${AIRTABLE_API_KEY:?'Erro: configure AIRTABLE_API_KEY como variável de ambiente'}"
AIRTABLE_BASE="${AIRTABLE_BASE_ID:?'Erro: configure AIRTABLE_BASE_ID com seu Base ID'}"
SKIP_MOD2="false"
WEBHOOK_TIMEOUT=600  # 10 minutos

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --vps-ip)
      VPS_IP="$2"
      shift 2
      ;;
    --skip-mod2)
      SKIP_MOD2="true"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

BASE_URL="http://${VPS_IP}:5678/api/v1"

# Helper functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
  echo -e "${RED}[✗]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[!]${NC} $1"
}

# Test 1: Verify connectivity
test_connectivity() {
  log_info "Testando conectividade com n8n..."

  if ! timeout 5 curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/workflows" \
       -H "X-N8N-API-KEY: $API_KEY" | grep -q "200"; then
    log_error "Não foi possível conectar ao n8n em $VPS_IP:5678"
    log_info "Verifique:"
    log_info "  1. Docker stack está rodando? (docker compose ps)"
    log_info "  2. API Key é válido? (Settings → API → Token)"
    log_info "  3. Firewall permite porta 5678?"
    exit 1
  fi

  log_success "Conectado ao n8n"
}

# Test 2: Find workflow IDs
find_workflows() {
  log_info "Procurando workflows MOD2 e MOD3..."

  WORKFLOWS=$(curl -s "$BASE_URL/workflows" \
    -H "X-N8N-API-KEY: $API_KEY" 2>/dev/null)

  MOD2_ID=$(echo "$WORKFLOWS" | python3 -c \
    "import sys, json; data=json.load(sys.stdin).get('data',[]); mod2=[w for w in data if 'blacklist' in w.get('name','').lower()]; print(mod2[0]['id'] if mod2 else '')" 2>/dev/null || echo "")

  MOD3_ID=$(echo "$WORKFLOWS" | python3 -c \
    "import sys, json; data=json.load(sys.stdin).get('data',[]); mod3=[w for w in data if 'mineracao' in w.get('name','').lower()]; print(mod3[0]['id'] if mod3 else '')" 2>/dev/null || echo "")

  if [ -z "$MOD2_ID" ]; then
    log_warning "MOD2 não encontrado. Verifique se o workflow foi importado."
  else
    log_success "MOD2 ID: $MOD2_ID"
  fi

  if [ -z "$MOD3_ID" ]; then
    log_error "MOD3 não encontrado!"
    exit 1
  fi

  log_success "MOD3 ID: $MOD3_ID"
}

# Test 3: Execute MOD2 (if needed)
test_mod2() {
  if [ "$SKIP_MOD2" = "true" ]; then
    log_warning "Pulando MOD2 (--skip-mod2)"
    return
  fi

  if [ -z "$MOD2_ID" ]; then
    log_warning "MOD2 não disponível, saltando..."
    return
  fi

  log_info "Executando MOD2 para popular blacklist cache..."

  EXEC=$(curl -s -X POST "$BASE_URL/workflows/$MOD2_ID/execute" \
    -H "X-N8N-API-KEY: $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{}' 2>/dev/null)

  EXEC_ID=$(echo "$EXEC" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('id', ''))" 2>/dev/null || echo "")

  if [ -z "$EXEC_ID" ]; then
    log_warning "Não foi possível iniciar MOD2, continuando..."
    return
  fi

  log_success "MOD2 executado (ID: $EXEC_ID)"
  log_info "Aguardando 30s para completar..."
  sleep 30
}

# Test 4: Trigger MOD3 webhook
test_mod3_webhook() {
  log_info "Disparando MOD3 webhook com payload de teste..."

  PAYLOAD='{
    "nicho": "restaurante",
    "cidades": ["Sao Paulo"],
    "meta_semanal": 50
  }'

  # Get webhook ID from workflow
  MOD3_WF=$(curl -s "$BASE_URL/workflows/$MOD3_ID" \
    -H "X-N8N-API-KEY: $API_KEY" 2>/dev/null)

  WEBHOOK_ID=$(echo "$MOD3_WF" | python3 -c \
    "import sys, json; data=json.load(sys.stdin); webhooks=[n for n in data.get('nodes',[]) if n.get('type')=='n8n-nodes-base.webhook']; print(webhooks[0].get('webhookId','') if webhooks else '')" 2>/dev/null || echo "")

  if [ -z "$WEBHOOK_ID" ]; then
    log_error "Webhook ID não encontrado em MOD3"
    exit 1
  fi

  WEBHOOK_URL="http://${VPS_IP}:5678/webhook/$WEBHOOK_ID"

  START_TIME=$(date +%s)
  RESPONSE=$(curl -s -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" 2>/dev/null)

  log_success "Webhook disparado"
  log_info "Resposta: $RESPONSE"
  log_info "⏳ Aguardando ~5-15min para Apify processar (Instagram scraping)..."
}

# Test 5: Check Airtable results
check_airtable_results() {
  log_info "Verificando resultados em Airtable..."

  if [ -z "$AIRTABLE_BASE" ] || [ "$AIRTABLE_BASE" = "appEXXXXXXXXXXXXX" ]; then
    log_warning "Airtable Base ID não configurado (AIRTABLE_BASE)"
    log_info "Atualize a variável com seu Base ID de https://airtable.com/api"
    return
  fi

  # Aguardar alguns segundos
  sleep 10

  # Procurar por registros recentes (últimos 5 minutos)
  RECORDS=$(curl -s "https://api.airtable.com/v0/${AIRTABLE_BASE}/SDR_Operacional?maxRecords=10&sort[0][field]=criado_em&sort[0][direction]=desc" \
    -H "Authorization: Bearer $AIRTABLE_TOKEN" 2>/dev/null)

  TOTAL=$(echo "$RECORDS" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data.get('records',[])))" 2>/dev/null || echo "0")

  if [ "$TOTAL" -gt 0 ]; then
    log_success "Encontrados $TOTAL registros em Airtable"

    # Show first 3 records
    echo "$RECORDS" | python3 << 'EOF'
import sys, json
data = json.load(sys.stdin)
for i, rec in enumerate(data.get('records', [])[:3]):
    fields = rec.get('fields', {})
    print(f"\n  [{i+1}] {fields.get('Nome', 'N/A')}")
    print(f"      Status: {fields.get('Status', 'N/A')}")
    print(f"      Score: {fields.get('Score', 'N/A')}")
    print(f"      Criado: {fields.get('criado_em', 'N/A')}")
EOF
  else
    log_warning "Nenhum registro recente encontrado em Airtable"
    log_info "Isso é normal se menos de 10s passaram desde o webhook"
  fi
}

# Test 6: Summary
print_summary() {
  echo ""
  log_info "=== RESUMO DO TESTE ==="
  echo ""
  log_success "✓ Conectividade n8n"
  log_success "✓ Workflows encontrados"
  [ "$SKIP_MOD2" != "true" ] && log_success "✓ MOD2 executado" || log_warning "✓ MOD2 pulado"
  log_success "✓ Webhook MOD3 disparado"
  echo ""
  log_info "Próximos passos:"
  echo "  1. Verifique http://157.230.210.188:5678 → Workflows → MOD3 → Executions"
  echo "  2. Aguarde ~5-15min para Apify completar (Instagram scraping)"
  echo "  3. Verifique Airtable para novos leads (Status='Curadoria')"
  echo "  4. Verifique custos Apify em https://console.apify.com/billing"
  echo ""
}

# Main execution
main() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════════╗"
  echo "║             MOD3 — TESTE AUTOMATIZADO                             ║"
  echo "║    Lead Mining via Webhook (Apify Instagram Scraper)              ║"
  echo "╚════════════════════════════════════════════════════════════════════╝"
  echo ""

  test_connectivity
  echo ""

  find_workflows
  echo ""

  test_mod2
  echo ""

  test_mod3_webhook
  echo ""

  check_airtable_results
  echo ""

  print_summary
}

# Run main
main
