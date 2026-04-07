#!/bin/bash
# =============================================================================
# FIX MOD2 — Blacklist Cache
# Rodar em: /opt/sdr-idv na VPS como root
# Uso: N8N_API_KEY="..." bash fix_mod2.sh
# =============================================================================
set -e

cd /opt/sdr-idv

echo "======================================"
echo " FIX MOD2 — Blacklist Cache"
echo "======================================"

# Localizar .env
ENV_FILE=""
if [ -f .env ]; then
  ENV_FILE=".env"
elif [ -f infra/.env ]; then
  ENV_FILE="infra/.env"
else
  echo "ERRO: .env não encontrado"
  exit 1
fi

_get_env() {
  grep -m1 "^${1}=" "$ENV_FILE" | cut -d= -f2- | tr -d '\r' \
    | sed 's/^"//;s/"$//;s/^'"'"'//;s/'"'"'$//'
}

REDIS_PASSWORD=$(_get_env REDIS_PASSWORD)
[ -z "$REDIS_PASSWORD" ] && REDIS_PASSWORD=$(docker exec sdr_redis printenv REQUIREPASS 2>/dev/null | tr -d '\r' || echo "")

N8N_BASE="http://localhost:5678/api/v1"

# Configurar autenticação — prioridade: variável de ambiente > .env > Basic Auth
if [ -z "$N8N_API_KEY" ]; then
  N8N_API_KEY=$(_get_env N8N_API_KEY)
fi

if [ -n "$N8N_API_KEY" ]; then
  echo "Auth: API Key (${N8N_API_KEY:0:20}...)"
  AUTH_ARGS=(-H "X-N8N-API-KEY: $N8N_API_KEY")
  AUTH_FOR_PY="apikey:$N8N_API_KEY"
else
  N8N_USER=$(_get_env N8N_BASIC_AUTH_USER)
  N8N_PASS=$(_get_env N8N_BASIC_AUTH_PASSWORD)
  [ -z "$N8N_USER" ] && N8N_USER=$(docker exec sdr_n8n printenv N8N_BASIC_AUTH_USER 2>/dev/null | tr -d '\r' || echo "admin")
  [ -z "$N8N_PASS" ] && N8N_PASS=$(docker exec sdr_n8n printenv N8N_BASIC_AUTH_PASSWORD 2>/dev/null | tr -d '\r' || echo "")
  echo "Auth: Basic user=${N8N_USER}"
  AUTH_ARGS=(-u "${N8N_USER}:${N8N_PASS}")
  AUTH_FOR_PY="basic:${N8N_USER}:${N8N_PASS}"
fi

# Salvar API key no .env se ainda não tiver
if [ -n "$N8N_API_KEY" ] && ! grep -q "^N8N_API_KEY=" "$ENV_FILE" 2>/dev/null; then
  echo "N8N_API_KEY=$N8N_API_KEY" >> "$ENV_FILE"
  echo "API key salva em $ENV_FILE"
fi

# --------------------------------------------------------
# 1. Puxar código mais recente
# --------------------------------------------------------
echo ""
echo "[1/6] Atualizando repositório..."
git pull origin claude/etapa-3-W7NEA || true
echo "OK"

# --------------------------------------------------------
# 2. Reiniciar n8n com N8N_ALLOW_EXEC=true
# --------------------------------------------------------
echo ""
echo "[2/6] Reiniciando n8n (N8N_ALLOW_EXEC=true)..."
cd infra
docker compose down n8n n8n-worker
docker compose up -d n8n
echo "Aguardando n8n (45s)..."
sleep 45

for i in {1..10}; do
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5678/healthz)
  if [ "$HTTP" = "200" ]; then echo "n8n OK"; break; fi
  echo "  aguardando... ($i/10)"; sleep 10
done

docker compose up -d n8n-worker
echo "Worker OK"
cd ..

# --------------------------------------------------------
# 3. Testar autenticação
# --------------------------------------------------------
echo ""
echo "[2.5] Testando autenticação..."
AUTH_TEST=$(curl -s "${AUTH_ARGS[@]}" "$N8N_BASE/workflows?limit=1")
if echo "$AUTH_TEST" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if 'data' in d else 1)" 2>/dev/null; then
  echo "Autenticação OK"
else
  echo "ERRO de autenticação:"
  echo "$AUTH_TEST"
  exit 1
fi

# --------------------------------------------------------
# 4. Remover MOD2 antigo
# --------------------------------------------------------
echo ""
echo "[3/6] Removendo MOD2 antigo..."

# Listar e remover todos com MOD2/Blacklist no nome
curl -s "${AUTH_ARGS[@]}" "$N8N_BASE/workflows?limit=100" | python3 -c "
import json,sys,subprocess
data=json.load(sys.stdin)
auth_for_py='$AUTH_FOR_PY'
parts=auth_for_py.split(':',1)
if parts[0]=='apikey':
    curl_auth=['-H',f'X-N8N-API-KEY: {parts[1]}']
else:
    _,user,pw=auth_for_py.split(':',2)
    curl_auth=['-u',f'{user}:{pw}']
removed=0
for wf in data.get('data',[]):
    n=wf.get('name','')
    if 'MOD2' in n or 'Blacklist' in n or wf['id']=='nDfthw7vChvdbF62':
        r=subprocess.run(['curl','-s','-o','/dev/null','-w','%{http_code}','-X','DELETE']+curl_auth+[f'http://localhost:5678/api/v1/workflows/{wf[\"id\"]}'],capture_output=True,text=True)
        print(f'  Removido: {n} ({wf[\"id\"]}) — HTTP {r.stdout.strip()}')
        removed+=1
if not removed:
    print('  Nenhum MOD2 encontrado para remover')
" 2>/dev/null || echo "  (erro ao listar — continuando)"

# --------------------------------------------------------
# 5. Importar MOD2 v2
# --------------------------------------------------------
echo ""
echo "[4/6] Importando MOD2 (executeCommand + Python/openssl)..."

IMPORT_RESP=$(curl -s -X POST "$N8N_BASE/workflows" \
  "${AUTH_ARGS[@]}" \
  -H "Content-Type: application/json" \
  -d @workflows/mod2-blacklist-cache-v2.json)

NEW_ID=$(echo "$IMPORT_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || echo "")

if [ -z "$NEW_ID" ]; then
  echo "ERRO ao importar:"
  echo "$IMPORT_RESP" | python3 -m json.tool 2>/dev/null || echo "$IMPORT_RESP"
  exit 1
fi

echo "Importado — ID: $NEW_ID"

# --------------------------------------------------------
# 6. Ativar MOD2
# --------------------------------------------------------
echo ""
echo "[5/6] Ativando MOD2..."

ACTIVATE_RESP=$(curl -s -X PATCH "$N8N_BASE/workflows/$NEW_ID" \
  "${AUTH_ARGS[@]}" \
  -H "Content-Type: application/json" \
  -d '{"active": true}')

ACTIVE=$(echo "$ACTIVATE_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('active'))" 2>/dev/null || echo "?")
echo "active: $ACTIVE"

# --------------------------------------------------------
# 7. Executar teste
# --------------------------------------------------------
echo ""
echo "[6/6] Executando teste manual..."

EXEC_RESP=$(curl -s -X POST "$N8N_BASE/workflows/$NEW_ID/execute" \
  "${AUTH_ARGS[@]}" \
  -H "Content-Type: application/json" \
  -d '{}')

EXEC_ID=$(echo "$EXEC_RESP" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('executionId', d.get('id','?')))
" 2>/dev/null || echo "?")
echo "Execução: ID=$EXEC_ID"
echo "Aguardando 55s..."
sleep 55

EXEC_STATUS=$(curl -s "${AUTH_ARGS[@]}" "$N8N_BASE/executions/$EXEC_ID" 2>/dev/null)
STATUS=$(echo "$EXEC_STATUS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status','?'))" 2>/dev/null || echo "?")
echo "Status: $STATUS"

if [ "$STATUS" = "success" ]; then
  echo ""
  echo "======================================"
  echo " SUCESSO! MOD2 funcionando!"
  echo "======================================"
  echo ""
  echo "Redis blacklist_cache:"
  docker exec sdr_redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning GET blacklist_cache | python3 -c "
import sys,json
raw=sys.stdin.read().strip()
if raw and raw not in ('nil','(nil)'):
    try:
        d=json.loads(raw)
        print(f'  {len(d)} entradas — OK')
    except:
        print('  presente (raw):', raw[:60])
else:
    print('  nil (vazio — verificar logs)')
"
else
  echo ""
  echo "Status = $STATUS"
  echo "$EXEC_STATUS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
runData=(d.get('data',{}) or {}).get('resultData',{}).get('runData',{}) or {}
for node,runs in runData.items():
    for run in (runs or []):
        err=run.get('error',{})
        if err:
            print(f'  ERRO [{node}]: {err.get(\"message\",str(err))[:300]}')
" 2>/dev/null || echo "$EXEC_STATUS" | head -c 500
fi

echo ""
echo "Workflows ativos:"
curl -s "${AUTH_ARGS[@]}" "$N8N_BASE/workflows?limit=50" | python3 -c "
import json,sys
data=json.load(sys.stdin)
for wf in data.get('data',[]):
    if any(x in wf.get('name','') for x in ['MOD','Blacklist','Minera']):
        icon='[OK]' if wf.get('active') else '[--]'
        print(f'  {icon} {wf[\"name\"]} ({wf[\"id\"]})')
"
echo ""
echo "MOD2 novo ID: $NEW_ID"
