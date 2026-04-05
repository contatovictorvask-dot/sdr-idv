# ETAPA 3 — Status Final MOD3 v2.2

**Data:** 2026-04-05  
**Branch:** `claude/etapa-3-W7NEA`  
**Status:** ✅ Pronto para teste  

---

## 📋 Resumo Executivo

MOD3 (Mineração de Leads) foi redesenhado e otimizado para o plano FREE do Apify (625 CUs/mês). O fluxo agora:

1. **Webhook** recebe payload (nicho, cidades, meta)
2. **Redis** busca blacklist (leads já descartados)
3. **Apify Instagram Search** faz scraping gratuito
4. **Filtro B2B + Score** elimina resultados não-qualificados
5. **Airtable Bulk Create** alimenta a tabela `SDR_Operacional`

### Arquitetura v2.2

```
13 nós em n8n (reduzido de 18)
├─ Webhook
├─ Redis GET blacklist
├─ Prepare payload
├─ Apify Instagram Search
├─ Fetch dataset
├─ Filter B2B + Score ≥ 40
├─ IF check (tem leads?)
├─ Loop split 10
├─ Airtable Bulk Create
└─ Respond (200 OK)
```

---

## 🔑 Chave n8n API (Novo)

A chave criada em Settings → API está documentada em:
- **MOD3_TEST_GUIDE.md** (linha 8)
- **test_mod3.sh** (linha 31)

**Nunca commitar tokens em git.** Use variáveis de ambiente ou `.env.local`.

---

## 🚀 Como Testar

### Opção 1: Via script automatizado (recomendado)

```bash
cd /opt/sdr-idv

# Execute no VPS:
./test_mod3.sh

# Ou especifique o IP:
./test_mod3.sh --vps-ip 157.230.210.188
```

**O que faz:**
- ✓ Verifica conectividade
- ✓ Encontra IDs dos workflows
- ✓ Executa MOD2 (blacklist cache)
- ✓ Dispara webhook MOD3 com payload de teste
- ✓ Aguarda 30s e verifica Airtable

### Opção 2: Manual (via curl)

```bash
cd /opt/sdr-idv/infra

# 1. Listar workflows
curl -s http://localhost:5678/api/v1/workflows \
  -H "X-N8N-API-KEY: $API_KEY" | jq '.data[] | {id, name}'

# 2. Disparar webhook
curl -X POST http://localhost:5678/webhook/mod3-mineracao \
  -H "Content-Type: application/json" \
  -d '{
    "nicho": "restaurante",
    "cidades": ["Sao Paulo"],
    "meta_semanal": 50
  }'

# 3. Aguardar 5-15min (Apify scraping)

# 4. Verificar Airtable
AIRTABLE_TOKEN="<seu_airtable_api_key>"
BASE_ID="<seu_base_id>"
curl -s "https://api.airtable.com/v0/$BASE_ID/SDR_Operacional" \
  -H "Authorization: Bearer $AIRTABLE_TOKEN" \
  | jq '.records[] | {Nome, Status, Score}'
```

---

## 📊 Critérios de Sucesso

✅ **Webhook responde** 200 OK em <30s  
✅ **Airtable recebe leads** com Status="Curadoria"  
✅ **Lead Score ≥ 40** para todos os registros  
✅ **B2B filtering** remove 60-70% de resultados brutos  
✅ **Apify consome ≤5 CUs** por execução  
✅ **Tempo total** 5-15 min (esperado: Apify é lento)  

---

## 🔍 Variáveis de Ambiente (Confirmadas)

Arquivo: `/opt/sdr-idv/infra/.env`

```
REDIS_PASSWORD=<redis_secure_password>
AIRTABLE_API_KEY=<seu_airtable_personal_access_token>
APIFY_TOKEN=<seu_apify_api_token>
N8N_BLOCK_ENV_ACCESS_IN_NODE=false
```

**⚠️ Nota:** `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` é crítico para acessar `$env.AIRTABLE_API_KEY` em nós.

Veja `/opt/sdr-idv/infra/.env` para valores reais (não em git).

---

## 📁 Arquivos Entregues

```
sdr-idv/
├── MOD3_TEST_GUIDE.md              # Guia completo de teste (7 passos)
├── test_mod3.sh                     # Script automatizado (bash)
├── ETAPA3_STATUS.md                 # Este arquivo
├── workflows/mod3-mineracao-fila.json    # Workflow final v2.2 (13 nós)
├── workflows/mod2-blacklist-cache.json   # Cache Redis (pré-requisito)
└── README.md                        # Status geral dos módulos
```

---

## 🧪 Algoritmo de Scoring (Embedding em MOD3)

```javascript
// Nó: "Filter: B2B + Lead Score >= 40"
// Cada lead precisa:

1. B2B: isBusinessAccount=true OR url externo
2. Score ≥ 40 pontos:
   - Followers 1k-15k: +20
   - Posts últimos 7 dias: +15
   - URL amador (Instagram Shop, linktree): +15
   - Business account: +10
```

**Exemplo:** 
- Conta com 5k seguidores + 3 posts recentes + Shop = 20+15+15 = 50 ✅

---

## 🚨 Troubleshooting Comum

### ❌ "Redis: blacklist not found"
**Solução:** Execute MOD2 uma vez
```bash
curl -X POST http://localhost:5678/api/v1/workflows/$MOD2_ID/execute \
  -H "X-N8N-API-KEY: $API_KEY" -d '{}'
```

### ❌ "Airtable: 401 Unauthorized"
**Solução:** Regenerar token em https://airtable.com/account/tokens

### ❌ "Apify: invalid token"
**Solução:** Verificar em https://console.apify.com/account/integrations/api

### ❌ "Webhook timeout (>5 min)"
**Motivo:** Apify ainda processando (normal, Instagram é lento)  
**Solução:** Aumentar timeout ou usar execução assíncrona

---

## 📈 Próximos Passos (MOD5-6)

- [ ] **MOD5** — Pipeline Temporal (D1→D4, Pitch, Cleanup, Upsell)
- [ ] **MOD6** — Cockpit Front-end (SPA React/Tailwind)

---

## 📞 Suporte

**Documentação:**
- Guia completo: `MOD3_TEST_GUIDE.md`
- Script automático: `test_mod3.sh`
- Workflow JSON: `workflows/mod3-mineracao-fila.json`

**Logs em tempo real:**
```bash
docker compose logs -f n8n
docker compose logs -f n8n-worker
```

**Verificar status da stack:**
```bash
docker compose ps
docker compose exec redis redis-cli PING
```

---

**Última atualização:** 2026-04-05  
**Desenvolvido para:** SDR PERPÉTUO B2B v2.0  
**Deploy:** DigitalOcean Droplet (Ubuntu 22.04, 2-4GB RAM)
