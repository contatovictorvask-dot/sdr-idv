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
  echo "ERRO: .env não encontrado"
  exit 1
fi

_get_env() {
  grep -m1 "^${1}=" "$ENV_FILE" | cut -d= -f2- | tr -d '\r' \
    | sed 's/^"//;s/"$//;s/^'"'"'//;s/'"'"'$//'
}

# n8n usa Basic Auth (não API key)
N8N_USER=$(_get_env N8N_BASIC_AUTH_USER)
N8N_PASS=$(_get_env N8N_BASIC_AUTH_PASSWORD)
REDIS_PASSWORD=$(_get_env REDIS_PASSWORD)

# Fallback via docker se .env não tem
[ -z "$N8N_USER" ] && N8N_USER=$(docker exec sdr_n8n printenv N8N_BASIC_AUTH_USER 2>/dev/null | tr -d '\r' || echo "admin")
[ -z "$N8N_PASS" ] && N8N_PASS=$(docker exec sdr_n8n printenv N8N_BASIC_AUTH_PASSWORD 2>/dev/null | tr -d '\r' || echo "")
[ -z "$REDIS_PASSWORD" ] && REDIS_PASSWORD=$(docker exec sdr_redis printenv REQUIREPASS 2>/dev/null | tr -d '\r' || echo "")

echo "N8N auth: user=${N8N_USER}, pass=${N8N_PASS:0:4}... (${#N8N_PASS} chars)"

N8N_BASE="http://localhost:5678/api/v1"
N8N_AUTH="-u ${N8N_USER}:${N8N_PASS}"

# --------------------------------------------------------
# 1. Puxar código mais recente
# --------------------------------------------------------
echo ""
echo "[1/6] Atualizando código do repositório..."
git pull origin claude/etapa-3-W7NEA || true
echo "OK"

# --------------------------------------------------------
# 2. Reiniciar containers (N8N_ALLOW_EXEC já está no docker-compose)
# --------------------------------------------------------
echo ""
echo "[2/6] Reiniciando n8n com N8N_ALLOW_EXEC=true..."
cd infra
docker compose down n8n n8n-worker
docker compose up -d n8n
echo "Aguardando n8n inicializar (45s)..."
sleep 45

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
# 3. Testar autenticação
# --------------------------------------------------------
echo ""
echo "[2.5] Testando autenticação n8n..."
AUTH_TEST=$(curl -s $N8N_AUTH "$N8N_BASE/workflows?limit=1")
if echo "$AUTH_TEST" | grep -q "Unauthorized\|unauthorized\|401"; then
  echo "ERRO: Autenticação falhou!"
  echo "Resposta: $AUTH_TEST"
  echo ""
  echo "Tente: export N8N_PASS='sua_senha' && N8N_AUTH=\"-u admin:\$N8N_PASS\" bash fix_mod2.sh"
  exit 1
fi
echo "Autenticação OK"

# --------------------------------------------------------
# 4. Deletar MOD2 antigo (se existir)
# --------------------------------------------------------
echo ""
echo "[3/6] Removendo MOD2 antigo..."
OLD_ID="nDfthw7vChvdbF62"

DEL_RESP=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
  $N8N_AUTH "$N8N_BASE/workflows/$OLD_ID")

if [ "$DEL_RESP" = "200" ] || [ "$DEL_RESP" = "204" ]; then
  echo "Removido (ID: $OLD_ID)"
else
  echo "ID $OLD_ID não encontrado (HTTP $DEL_RESP) — ok"
fi

# Deletar qualquer outro MOD2 duplicado
echo "Verificando duplicatas..."
curl -s $N8N_AUTH "$N8N_BASE/workflows?limit=50" | python3 -c "
import json,sys,subprocess
data=json.load(sys.stdin)
user=sys.argv[1]; pw=sys.argv[2]
for wf in data.get('data',[]):
    if 'MOD2' in wf.get('name','') or 'Blacklist' in wf.get('name',''):
        wid=wf['id']
        subprocess.run(['curl','-s','-o','/dev/null','-X','DELETE',
            '-u',f'{user}:{pw}',
            f'http://localhost:5678/api/v1/workflows/{wid}'])
        print(f'  Removido: {wf[\"name\"]} ({wid})')
" "$N8N_USER" "$N8N_PASS" 2>/dev/null || true

# --------------------------------------------------------
# 5. Importar MOD2 fresco (v2 com executeCommand)
# --------------------------------------------------------
echo ""
echo "[4/6] Importando MOD2 (executeCommand + Python/openssl)..."

IMPORT_RESP=$(curl -s -X POST "$N8N_BASE/workflows" \
  $N8N_AUTH \
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
# 6. Ativar MOD2
# --------------------------------------------------------
echo ""
echo "[5/6] Ativando MOD2..."

ACTIVATE_RESP=$(curl -s -X PATCH "$N8N_BASE/workflows/$NEW_ID" \
  $N8N_AUTH \
  -H "Content-Type: application/json" \
  -d '{"active": true}')

ACTIVE=$(echo "$ACTIVATE_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('active','?'))" 2>/dev/null || echo "?")
echo "active: $ACTIVE"

# --------------------------------------------------------
# 7. Disparar execução de teste
# --------------------------------------------------------
echo ""
echo "[6/6] Disparando execução de teste..."

EXEC_RESP=$(curl -s -X POST "$N8N_BASE/workflows/$NEW_ID/execute" \
  $N8N_AUTH \
  -H "Content-Type: application/json" \
  -d '{}')

EXEC_ID=$(echo "$EXEC_RESP" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('executionId', d.get('id','?')))
" 2>/dev/null || echo "?")
echo "Execução iniciada: ID=$EXEC_ID"

echo "Aguardando 50s para execução concluir..."
sleep 50

EXEC_STATUS=$(curl -s $N8N_AUTH "$N8N_BASE/executions/$EXEC_ID" 2>/dev/null)
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
if raw and raw not in ('nil','(nil)'):
    try:
        data=json.loads(raw)
        print(f'  blacklist_cache: {len(data)} entradas em Redis — OK')
    except:
        print('  blacklist_cache: presente no Redis (raw):', raw[:80])
else:
    print('  blacklist_cache: nil (vazio)')
"
else
  echo ""
  echo "Status = $STATUS — verificando erros:"
  echo "$EXEC_STATUS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
runData=(d.get('data',{}) or {}).get('resultData',{}).get('runData',{}) or {}
erros=0
for node,runs in runData.items():
    for run in (runs or []):
        err=run.get('error',{})
        if err:
            print(f'  ERRO [{node}]: {err.get(\"message\",str(err))[:200]}')
            erros+=1
if not erros:
    print('  Nenhum erro encontrado nos nós')
    print('  Status raw:', d.get('status'))
" 2>/dev/null || echo "$EXEC_STATUS" | head -c 400
fi

echo ""
echo "Status final dos workflows:"
curl -s $N8N_AUTH "$N8N_BASE/workflows?limit=50" | python3 -c "
import json,sys
data=json.load(sys.stdin)
for wf in data.get('data',[]):
    if any(x in wf.get('name','') for x in ['MOD','Blacklist','Minera']):
        icon='OK' if wf.get('active') else '--'
        print(f'  [{icon}] {wf[\"name\"]} (ID: {wf[\"id\"]})')
"

echo ""
echo "ID do novo MOD2: $NEW_ID"
