# MOD3 — Teste End-to-End: Lead Mining via Webhook

**Data:** 2026-04-05  
**Status:** Pronto para teste  
**API Key n8n:** Configure em `Settings → API` dentro do n8n (não commitir em git)

## Arquitetura MOD3 v2.2

```
Webhook Payload
    ↓
Redis GET (Blacklist Cache)
    ↓
Prepare Payload (Instagram Search)
    ↓
Apify Instagram Search Actor
    ↓
Fetch Dataset Results
    ↓
Filter B2B + Lead Score ≥ 40
    ↓
IF Check (tem leads?)
    ↓
Loop: Split resultados em lotes de 10
    ↓
Airtable Bulk Create (n8n-nodes-base.airtable)
    ↓
Responder ao webhook (200 OK)
```

## Pré-requisitos

✅ Docker Compose stack rodando (n8n + Redis + Apify)  
✅ MOD2 (blacklist-cache) executado pelo menos 1x (popula Redis)  
✅ n8n API Key criado (Settings → API)  
✅ Airtable API Key válido (.env)  
✅ Apify FREE plan com ≥600 CUs (625/mês)  

## Passo 1: Verificar status dos workflows

```bash
cd /opt/sdr-idv/infra

# Configure sua API Key de Settings → API → n8n API
API_KEY="<seu_n8n_api_key_aqui>"

curl -s http://localhost:5678/api/v1/workflows \
  -H "X-N8N-API-KEY: $API_KEY" | jq '.data[] | {id, name, active}'
```

**Esperado:**
```json
{
  "id": "<workflow-id>",
  "name": "MOD2 — Blacklist Cache (24h)",
  "active": true
}
{
  "id": "<workflow-id>",
  "name": "MOD3 — Mineração Fila (Instagram)",
  "active": true
}
```

## Passo 2: Executar MOD2 (Blacklist Cache)

Se nunca foi executado, rode uma vez para popular o Redis:

```bash
# Trigger manual de MOD2
MOD2_ID="<seu-workflow-id>"

curl -X POST http://localhost:5678/api/v1/workflows/$MOD2_ID/execute \
  -H "X-N8N-API-KEY: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{}'

echo "MOD2 rodando... aguarde ~30s"
sleep 30
```

**Verificar Redis:**
```bash
docker exec sdr_redis redis-cli -n 0 KEYS "blacklist:*"
# Deve retornar: blacklist:global
```

## Passo 3: Gatilhar MOD3 via Webhook

### Opção A: Via n8n API (recomendado)

```bash
# Copie sua API Key de Settings → API → n8n API
API_KEY="<seu_n8n_api_key>"

# Encontrar MOD3 workflow ID
MOD3_ID=$(curl -s http://localhost:5678/api/v1/workflows \
  -H "X-N8N-API-KEY: $API_KEY" | jq -r '.data[] | select(.name | contains("Mineracao")) | .id' | head -1)

# Ou use a chave criada em n8n Settings → API
# (copie e cole aqui, não commita em git!)

echo "MOD3 ID: $MOD3_ID"

# Executar com dados de teste
curl -X POST http://localhost:5678/api/v1/workflows/$MOD3_ID/execute \
  -H "X-N8N-API-KEY: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "body": {
        "nicho": "restaurante",
        "cidades": ["Sao Paulo"],
        "meta_semanal": 50
      }
    }
  }'

echo ""
echo "Webhook disparado. Aguardando Apify (~5-10min)..."
```

### Opção B: Via curl direto no webhook

```bash
# Encontrar webhook ID no n8n
WEBHOOK_URL="http://localhost:5678/webhook/mod3-mineracao"

curl -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "nicho": "restaurante",
    "cidades": ["Sao Paulo"],
    "meta_semanal": 50
  }'
```

## Passo 4: Monitorar execução

### Via Dashboard n8n
Abra: http://157.230.210.188:5678 → Workflows → MOD3 → Executions

### Via API
```bash
# Listar últimas execuções
MOD3_ID="<seu-workflow-id>"

curl -s http://localhost:5678/api/v1/workflows/$MOD3_ID/executions \
  -H "X-N8N-API-KEY: $API_KEY" | jq '.data[0] | {id, status, startedAt, stoppedAt}'
```

### Via Redis (verificar etapa 7: "Split em lotes")
```bash
docker exec sdr_redis redis-cli -n 0 GET "lote_diario"
# Deve retornar número de leads processados
```

## Passo 5: Verificar resultados em Airtable

```bash
# Baixar últimas 50 linhas da tabela SDR_Operacional
AIRTABLE_TOKEN="<seu_airtable_api_key>"
BASE_ID="<seu_base_id>"

curl -s "https://api.airtable.com/v0/$BASE_ID/SDR_Operacional?maxRecords=50&sort[0][field]=criado_em&sort[0][direction]=desc" \
  -H "Authorization: Bearer $AIRTABLE_TOKEN" | jq '.records[0:5] | .[] | {Nome, Status, Score}'
```

**Esperado:**
- `Status`: "Curadoria" (novo lead)
- `Score`: ≥ 40
- `criado_em`: data/hora recente

## Passo 6: Analisar custos Apify

Após execução, verificar em: https://console.apify.com → Billing

**Custos esperados:**
- Search Instagram actor: 1-3 CUs / execução
- **Taxa de sucesso**: ≥75% (leads válidos vs total scrapeado)
- **Budget mensal**: 625 CUs FREE = ~150-200 execuções

## Troubleshooting

### ❌ "Redis blacklist empty"
```bash
# Re-executar MOD2
# ou popular manualmente:
docker exec sdr_redis redis-cli -n 0 SET blacklist:global '["email@concorrente.com.br"]'
```

### ❌ "Airtable 401 Unauthorized"
```bash
# Verificar .env
cat /opt/sdr-idv/infra/.env | grep AIRTABLE_API_KEY
# Regenerar em: https://airtable.com/account/tokens
```

### ❌ "Apify token invalid"
```bash
# Verificar .env
cat /opt/sdr-idv/infra/.env | grep APIFY_TOKEN
# Regenerar em: https://console.apify.com/account/integrations/api
```

### ❌ "n8n webhook timeout (5+ min)"
- Apify ainda processando (Instagram scraping é lento)
- Aumentar timeout: n8n Settings → Execution → Timeout
- Ou rodar em background check (não wait)

## Success Criteria

✅ Webhook retorna 200 OK dentro de 30s  
✅ Airtable recebe N leads com Status="Curadoria"  
✅ Lead Score ≥ 40 para todos os registros  
✅ B2B filtering elimina 60-70% de resultados brutos  
✅ Apify consome ≤ 5 CUs por execução  
✅ Tempo total: 5-15 min (Apify scraping)

## Next Steps (MOD5-6)

1. **MOD5 — Pipeline Temporal**: Aquecimento D1-D4, Pitch, Cleanup, Upsell
2. **MOD6 — Cockpit Front-end**: SPA React/Tailwind com Dashboard local

---

**Documentação completa**: `/opt/sdr-idv/README.md`  
**Fluxo JSON**: `/opt/sdr-idv/workflows/mod3-mineracao-fila.json`  
**Logs Docker**: `docker compose logs -f n8n`
