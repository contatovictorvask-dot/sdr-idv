#!/bin/bash
# =============================================================================
# FIX MOD2 FINAL — usa Google Sheets nativo (sem executeCommand/crypto)
# Uso: N8N_API_KEY="..." bash fix_mod2_final.sh
# =============================================================================
set -e
cd /opt/sdr-idv

KEY="${N8N_API_KEY}"
BASE="http://localhost:5678/api/v1"

if [ -z "$KEY" ]; then
  KEY=$(grep -m1 "^N8N_API_KEY=" infra/.env | cut -d= -f2- | tr -d '\r"'"'" 2>/dev/null || echo "")
fi
if [ -z "$KEY" ]; then
  echo "ERRO: defina N8N_API_KEY"
  exit 1
fi

AUTH=(-H "X-N8N-API-KEY: $KEY")

echo "======================================"
echo " FIX MOD2 FINAL — Google Sheets nativo"
echo "======================================"

# --------------------------------------------------------
# 1. Extrair Service Account do container n8n
# --------------------------------------------------------
echo ""
echo "[1/5] Extraindo Service Account..."

# Pegar o B64 do container e processar no host (python3 não existe no container n8n)
SA_B64=$(docker exec sdr_n8n printenv GOOGLE_SERVICE_ACCOUNT_B64 2>/dev/null | tr -d '\r\n')

if [ -z "$SA_B64" ]; then
  echo "ERRO: GOOGLE_SERVICE_ACCOUNT_B64 não encontrado no container"
  exit 1
fi

SA_JSON=$(python3 -c "
import base64, json, sys
sa = json.loads(base64.b64decode('$SA_B64').decode())
print(json.dumps({'email': sa['client_email'], 'key': sa['private_key']}))
" 2>/dev/null)

if [ -z "$SA_JSON" ]; then
  echo "ERRO: falha ao decodificar Service Account"
  exit 1
fi

SA_EMAIL=$(echo "$SA_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['email'])")
echo "Service Account: $SA_EMAIL"

# --------------------------------------------------------
# 2. Criar (ou reusar) credencial Google Sheets no n8n
# --------------------------------------------------------
echo ""
echo "[2/5] Criando credencial Google Sheets no n8n..."

# Verificar se já existe
EXISTING_CRED=$(curl -s "${AUTH[@]}" "$BASE/credentials?limit=50" 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for c in d.get('data',[]):
    if c.get('name')=='Google Sheets SDR' and c.get('type')=='googleApi':
        print(c['id'])
        break
" 2>/dev/null || echo "")

if [ -n "$EXISTING_CRED" ]; then
  CRED_ID="$EXISTING_CRED"
  echo "Credencial existente reutilizada: $CRED_ID"
else
  # Montar JSON da credencial — passar B64 via env var para evitar problemas com \n
  CRED_PAYLOAD=$(SA_B64="$SA_B64" python3 -c "
import base64, json, os
sa = json.loads(base64.b64decode(os.environ['SA_B64']).decode())
payload = {
    'name': 'Google Sheets SDR',
    'type': 'googleApi',
    'data': {
        'email': sa['client_email'],
        'privateKey': sa['private_key'],
        'delegatedEmail': '',
        'scopes': 'https://www.googleapis.com/auth/spreadsheets https://www.googleapis.com/auth/drive.file',
        'httpWarning': ''
    }
}
print(json.dumps(payload))
")

  CRED_RESP=$(curl -s -X POST "${AUTH[@]}" \
    -H "Content-Type: application/json" \
    -d "$CRED_PAYLOAD" \
    "$BASE/credentials")

  CRED_ID=$(echo "$CRED_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || echo "")

  if [ -z "$CRED_ID" ]; then
    echo "ERRO ao criar credencial:"
    echo "$CRED_RESP"
    exit 1
  fi
  echo "Credencial criada: $CRED_ID"
fi

# --------------------------------------------------------
# 3. Remover MOD2 existente
# --------------------------------------------------------
echo ""
echo "[3/5] Removendo MOD2 existente..."

curl -s "${AUTH[@]}" "$BASE/workflows?limit=100" | python3 -c "
import json,sys,subprocess
data=json.load(sys.stdin)
key=sys.argv[1]
for wf in data.get('data',[]):
    n=wf.get('name','')
    if 'MOD2' in n or 'Blacklist' in n:
        r=subprocess.run(['curl','-s','-o','/dev/null','-w','%{http_code}','-X','DELETE',
            '-H',f'X-N8N-API-KEY: {key}',
            f'http://localhost:5678/api/v1/workflows/{wf[\"id\"]}'],
            capture_output=True,text=True)
        print(f'  Removido: {n} ({wf[\"id\"]}) HTTP {r.stdout.strip()}')
" "$KEY" 2>/dev/null || true

# --------------------------------------------------------
# 4. Criar e importar workflow v3
# --------------------------------------------------------
echo ""
echo "[4/5] Importando MOD2 v3 (Google Sheets nativo)..."

# Substituir __CRED_ID__ pelo ID real
WF_JSON=$(sed "s/__CRED_ID__/$CRED_ID/g" workflows/mod2-blacklist-cache-v3.json)

IMPORT_RESP=$(curl -s -X POST "$BASE/workflows" \
  "${AUTH[@]}" \
  -H "Content-Type: application/json" \
  -d "$WF_JSON")

NEW_ID=$(echo "$IMPORT_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || echo "")

if [ -z "$NEW_ID" ]; then
  echo "ERRO ao importar:"
  echo "$IMPORT_RESP" | python3 -m json.tool 2>/dev/null || echo "$IMPORT_RESP"
  exit 1
fi

echo "Importado — ID: $NEW_ID"

# --------------------------------------------------------
# 5. Ativar e testar
# --------------------------------------------------------
echo ""
echo "[5/5] Ativando e testando..."

# Ativar via endpoint dedicado
ACT=$(curl -s -X POST "${AUTH[@]}" "$BASE/workflows/$NEW_ID/activate")
ACTIVE=$(echo "$ACT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('active'))" 2>/dev/null || echo "?")
echo "active: $ACTIVE"

if [ "$ACTIVE" = "None" ] || [ "$ACTIVE" = "False" ] || [ "$ACTIVE" = "false" ] || [ "$ACTIVE" = "?" ]; then
  echo "Mensagem: $(echo $ACT | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('message',''))" 2>/dev/null)"
fi

# Executar teste manual
echo ""
echo "Disparando execução de teste..."
EXEC_RESP=$(curl -s -X POST "${AUTH[@]}" \
  -H "Content-Type: application/json" \
  -d '{}' "$BASE/workflows/$NEW_ID/execute")

EXEC_ID=$(echo "$EXEC_RESP" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('executionId', d.get('id','?')))
" 2>/dev/null || echo "?")
echo "Execução ID: $EXEC_ID"
echo "Aguardando 45s..."
sleep 45

EXEC_STATUS=$(curl -s "${AUTH[@]}" "$BASE/executions/$EXEC_ID" 2>/dev/null)
STATUS=$(echo "$EXEC_STATUS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status','?'))" 2>/dev/null || echo "?")
echo "Status: $STATUS"

if [ "$STATUS" = "success" ]; then
  echo ""
  echo "========================================="
  echo " SUCESSO! MOD2 funcionando!"
  echo "========================================="
  REDIS_PASS=$(grep -m1 "^REDIS_PASSWORD=" infra/.env | cut -d= -f2- | tr -d '\r"'"'" 2>/dev/null || echo "")
  docker exec sdr_redis redis-cli -a "$REDIS_PASS" --no-auth-warning GET blacklist_cache | python3 -c "
import sys,json
raw=sys.stdin.read().strip()
if raw and raw not in ('nil','(nil)'):
    try: print(f'  Redis blacklist_cache: {len(json.loads(raw))} entradas — OK')
    except: print('  Redis blacklist_cache: presente —', raw[:60])
else:
    print('  Redis blacklist_cache: nil')
"
else
  echo ""
  echo "Erros:"
  echo "$EXEC_STATUS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
rData=(d.get('data',{}) or {}).get('resultData',{}).get('runData',{}) or {}
for node,runs in rData.items():
    for r in (runs or []):
        e=r.get('error',{})
        if e: print(f'  [{node}]: {e.get(\"message\",str(e))[:300]}')
" 2>/dev/null || echo "$EXEC_STATUS" | head -c 500
fi

echo ""
echo "Workflows:"
curl -s "${AUTH[@]}" "$BASE/workflows?limit=50" | python3 -c "
import json,sys
for wf in json.load(sys.stdin).get('data',[]):
    if any(x in wf.get('name','') for x in ['MOD','Blacklist','Minera']):
        print(f'  [{\"OK\" if wf.get(\"active\") else \"--\"}] {wf[\"name\"]} ({wf[\"id\"]})')
"
echo ""
echo "Novo MOD2 ID: $NEW_ID  |  Credencial Google ID: $CRED_ID"
