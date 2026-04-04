# Cold Storage — Google Sheets: SDR_Master_Log

## Estrutura da Planilha

Criar uma planilha chamada **`SDR_Master_Log`** no Google Drive e compartilhá-la com a Service Account do GCP.

---

### Aba 1: `Blacklist_Permanente`

Leads que jamais devem ser contatados novamente (concorrentes, clientes atuais, desqualificados definitivamente).

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| A — `username` | Texto | Handle do Instagram (sem @) — **chave de lookup** |
| B — `motivo` | Texto | `concorrente` / `cliente_ativo` / `solicitou_remocao` / `manual` |
| C — `data_inclusao` | Data | Data em que foi incluído (ISO: YYYY-MM-DD) |
| D — `origem` | Texto | `expurgo_automatico` / `manual` |

**Linha 1 = cabeçalho fixo.** Dados a partir da linha 2.

---

### Aba 2: `Quarentena_90_Dias`

Leads que não responderam após 30 dias em `Proposta_Enviada`. Podem ser reativados após 90 dias.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| A — `username` | Texto | Handle do Instagram |
| B — `data_quarentena` | Data | Data de entrada na quarentena |
| C — `data_reativacao` | Data | `data_quarentena` + 90 dias — n8n verifica diariamente |
| D — `lead_score` | Número | Score original para priorização na reativação |
| E — `pitch_original` | Texto | Copy que foi enviada antes da quarentena |

---

### Aba 3: `Clientes_Ativos_SDR`

Espelho simplificado dos clientes fechados (Won) para controle de blacklist — impede recontato acidental.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| A — `username` | Texto | Handle do Instagram |
| B — `nome_empresa` | Texto | Nome da empresa |
| C — `data_fechamento` | Data | Data do fechamento |
| D — `valor_contrato` | Número | Valor em R$ |

---

## Configuração da Service Account (GCP)

```bash
# 1. Acessar: console.cloud.google.com
# 2. Criar projeto: sdr-perpetuo (ou usar existente)
# 3. Ativar APIs:
#    - Google Sheets API
#    - Google Drive API

# 4. Criar Service Account:
#    IAM & Admin → Service Accounts → Create
#    Nome: sdr-sheets-bot
#    Papel: Editor

# 5. Gerar chave JSON:
#    Service Account → Keys → Add Key → JSON
#    Salvar como: service-account.json

# 6. Compartilhar a planilha SDR_Master_Log com o e-mail da Service Account
#    (formato: sdr-sheets-bot@<projeto>.iam.gserviceaccount.com)
#    Permissão: Editor

# 7. Encodar em Base64 para o .env:
base64 -w 0 service-account.json
# Cole o resultado em GOOGLE_SERVICE_ACCOUNT_B64 no infra/.env
```

---

## Lógica de Caching da Blacklist no n8n

O n8n **não** consulta o Sheets para cada lead. O fluxo de caching funciona assim:

```
[Cron: início do job diário]
        ↓
[Google Sheets: Get All — aba Blacklist_Permanente]
        ↓
[Code Node: extrai array de usernames]
  const blacklist = items.map(i => i.json.username.toLowerCase().trim());
  $workflow.staticData.blacklistCache = blacklist;
  $workflow.staticData.blacklistCachedAt = Date.now();
        ↓
[Redis SET: key="blacklist_cache" | value=JSON.stringify(blacklist) | TTL=86400s]
        ↓
[Prossegue para mineração]
```

### Verificação por lead (zero requisições HTTP adicionais):

```javascript
// Nó de Code — filtro em memória
const blacklist = JSON.parse(await $redis.get('blacklist_cache') || '[]');
const leadsAprovados = items.filter(item => {
  const username = item.json.username?.toLowerCase().trim();
  return !blacklist.includes(username);
});
return leadsAprovados;
```

---

## Variáveis de Ambiente necessárias

Adicionar ao `infra/.env`:

```env
# ID da planilha SDR_Master_Log (extrair da URL do Google Sheets)
SHEETS_SPREADSHEET_ID=1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Abas
SHEETS_TAB_BLACKLIST=Blacklist_Permanente
SHEETS_TAB_QUARENTENA=Quarentena_90_Dias
SHEETS_TAB_CLIENTES=Clientes_Ativos_SDR
```
