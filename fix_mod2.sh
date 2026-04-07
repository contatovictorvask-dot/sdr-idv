#!/bin/bash
# =============================================================================
# FIX MOD2 — Blacklist Cache
# Resolve: N8N_ALLOW_EXEC + reimporta + ativa MOD2
# Rodar em: /opt/sdr-idv na VPS como root
# =============================================================================
set -e

cd /opt/sdr-idv

echo "======================================"
echo " FIX MOD2 — Blacklist Cache"
echo "======================================"

# Carregar variáveis
ENV_FILE=""
if [ -f .env ]; then
  ENV_FILE=".env"
elif [ -f infra/.env ]; then
  ENV_FILE="infra/.env"
else
  echo "ERRO: .env não encontrado em /opt/sdr-idv nem em infra/"
  exit 1
fi

# Extrair variáveis via grep com suporte a Windows line endings e aspas
_get_env() {
  local key="$1"
  grep -m1 "^${key}=" "$ENV_FILE" \
    | cut -d= -f2- \
    | tr -d '\r' \
    | sed 's/^"//;s/"$//;s/^'"'"'//;s/'"'"'$//'
}

# Tentar arquivo; se falhar, tentar via docker container
N8N_API_KEY=$(_get_env N8N_API_KEY)
if [ -z "$N8N_API_KEY" ]; then
  N8N_API_KEY=$(docker exec sdr_n8n printenv N8N_API_KEY 2>/dev/null | tr -d '\r' || true)
fi
if [ -z "$N8N_API_KEY" ]; then
  # Última tentativa: pegar de variável de ambiente já definida no shell
  N8N_API_KEY="${N8N_API_KEY:-}"
fi

REDIS_PASSWORD=$(_get_env REDIS_PASSWORD)
if [ -z "$REDIS_PASSWORD" ]; then
  REDIS_PASSWORD=$(docker exec sdr_redis printenv REDIS_PASSWORD 2>/dev/null | tr -d '\r' || true)
fi

if [ -z "$N8N_API_KEY" ]; then
  echo ""
  echo "ERRO: N8N_API_KEY não encontrado. Verifique $ENV_FILE"
  echo "Conteúdo da linha N8N_API_KEY no .env:"
  grep "N8N_API_KEY" "$ENV_FILE" | cat -A | head -3
  echo ""
  echo "Defina manualmente: export N8N_API_KEY=sua_chave && bash fix_mod2.sh"
  exit 1
fi

echo "DEBUG: N8N_API_KEY=${N8N_API_KEY:0:8}... (${#N8N_API_KEY} chars)"

N8N_BASE="http://localhost:5678/api/v1"

# --------------------------------------------------------
# 1. Puxar código mais recente
# --------------------------------------------------------
echo ""
echo "[1/6] Atualizando código do repositório..."
git pull origin claude/etapa-3-W7NEA || true
echo "OK"

# --------------------------------------------------------
# 2. Reiniciar containers com N8N_ALLOW_EXEC=true
# --------------------------------------------------------
echo ""
echo "[2/6] Reiniciando n8n com N8N_ALLOW_EXEC=true..."
cd infra
docker compose down n8n n8n-worker
docker compose up -d n8n
echo "Aguardando n8n inicializar (45s)..."
sleep 45

# Verificar se n8n subiu
for i in {1..10}; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5678/healthz)
  if [ "$STATUS" = "200" ]; then
    echo "n8n OK"
    break
  fi
  echo "Aguardando n8n... ($i/10)"
  sleep 10
done

docker compose up -d n8n-worker
echo "Worker reiniciado"
cd ..

# --------------------------------------------------------
# 3. Deletar MOD2 antigo (se existir)
# --------------------------------------------------------
echo ""
echo "[3/6] Removendo MOD2 antigo..."
OLD_ID="nDfthw7vChvdbF62"

DEL_RESP=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
  -H "X-N8N-API-KEY: $N8N_API_KEY" \
  "$N8N_BASE/workflows/$OLD_ID")

if [ "$DEL_RESP" = "200" ] || [ "$DEL_RESP" = "204" ]; then
  echo "Removido (ID: $OLD_ID)"
else
  echo "ID $OLD_ID não encontrado ou já removido (HTTP $DEL_RESP) — ok"
fi

# Deletar qualquer outro MOD2 duplicado
echo "Verificando duplicatas..."
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_BASE/workflows?limit=50" | python3 -c "
import json,sys,subprocess,os
data=json.load(sys.stdin)
key=os.environ.get('N8N_API_KEY','')
for wf in data.get('data',[]):
    if 'MOD2' in wf.get('name','') or 'Blacklist' in wf.get('name',''):
        wid=wf['id']
        name=wf['name']
        subprocess.run(['curl','-s','-o','/dev/null','-X','DELETE',
            '-H',f'X-N8N-API-KEY: {key}',
            f'http://localhost:5678/api/v1/workflows/{wid}'])
        print(f'  Removido: {name} ({wid})')
" N8N_API_KEY="$N8N_API_KEY"

# --------------------------------------------------------
# 4. Importar MOD2 fresco (v2 com executeCommand)
# --------------------------------------------------------
echo ""
echo "[4/6] Importando MOD2 (executeCommand + Python/openssl)..."

IMPORT_RESP=$(curl -s -X POST "$N8N_BASE/workflows" \
  -H "X-N8N-API-KEY: $N8N_API_KEY" \
  -H "Content-Type: application/json" \
  -d @workflows/mod2-blacklist-cache-v2.json)

NEW_ID=$(echo "$IMPORT_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || echo "")

if [ -z "$NEW_ID" ]; then
  echo "ERRO ao importar MOD2:"
  echo "$IMPORT_RESP" | python3 -m json.tool 2>/dev/null || echo "$IMPORT_RESP"
  exit 1
fi

echo "Importado — novo ID: $NEW_ID"

# --------------------------------------------------------
# 5. Ativar MOD2
# --------------------------------------------------------
echo ""
echo "[5/6] Ativando MOD2..."

# Usar PATCH para ativar (mais confiável que /activate)
ACTIVATE_RESP=$(curl -s -X PATCH "$N8N_BASE/workflows/$NEW_ID" \
  -H "X-N8N-API-KEY: $N8N_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"active": true}')

ACTIVE=$(echo "$ACTIVATE_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('active','?'))" 2>/dev/null || echo "?")
echo "active: $ACTIVE"

if [ "$ACTIVE" != "True" ] && [ "$ACTIVE" != "true" ]; then
  # Tentar via endpoint dedicado
  echo "Tentando endpoint /activate..."
  curl -s -X POST \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    "$N8N_BASE/workflows/$NEW_ID/activate" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('active via endpoint:', d.get('active','?'))
" 2>/dev/null || true
fi

# --------------------------------------------------------
# 6. Disparar execução manual de teste
# --------------------------------------------------------
echo ""
echo "[6/6] Disparando execução de teste (POST /execute)..."

EXEC_RESP=$(curl -s -X POST "$N8N_BASE/workflows/$NEW_ID/execute" \
  -H "X-N8N-API-KEY: $N8N_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{}')

EXEC_ID=$(echo "$EXEC_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('executionId', d.get('id','?')))" 2>/dev/null || echo "?")
echo "Execução iniciada: ID=$EXEC_ID"

echo "Aguardando 40s para execução concluir..."
sleep 40

# Verificar resultado
EXEC_STATUS=$(curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_BASE/executions/$EXEC_ID" 2>/dev/null)
STATUS=$(echo "$EXEC_STATUS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status','?'))" 2>/dev/null || echo "?")
echo "Status da execução: $STATUS"

if [ "$STATUS" = "success" ]; then
  echo ""
  echo "======================================"
  echo " SUCESSO! MOD2 funcionando!"
  echo "======================================"
  echo ""
  echo "Verificando Redis..."
  docker exec sdr_redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning GET blacklist_cache | python3 -c "
import sys,json
raw=sys.stdin.read().strip()
if raw and raw!='nil':
    try:
        data=json.loads(raw)
        print(f'Redis blacklist_cache: {len(data)} entradas OK')
    except:
        print('Redis blacklist_cache: dados presentes (não-JSON?)',raw[:100])
else:
    print('Redis blacklist_cache: vazio ou nil')
"
else
  echo ""
  echo "ATENÇÃO: Status = $STATUS"
  echo "Detalhes:"
  echo "$EXEC_STATUS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
data=d.get('data',{}) or {}
result=data.get('resultData',{}) or {}
runData=result.get('runData',{}) or {}
for node,runs in runData.items():
    for run in runs:
        err=run.get('error',{})
        if err:
            print(f'  ERRO [{node}]: {err.get(\"message\",err)}')
" 2>/dev/null || echo "$EXEC_STATUS" | head -c 500
fi

echo ""
echo "Status final dos workflows:"
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_BASE/workflows?limit=50" | python3 -c "
import json,sys
data=json.load(sys.stdin)
for wf in data.get('data',[]):
    if 'MOD' in wf.get('name','') or 'Blacklist' in wf.get('name','') or 'Minera' in wf.get('name',''):
        icon='🟢' if wf.get('active') else '⚪'
        print(f'  {icon} {wf[\"name\"]} (ID: {wf[\"id\"]})')
"

echo ""
echo "ID do novo MOD2: $NEW_ID"
echo "Salvar esse ID para referência futura."
