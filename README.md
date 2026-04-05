# SDR PERPÉTUO B2B v2.0

Sistema de Prospecção Perpétuo B2B Semi-Automático — Identidade Visual (Ticket R$2.000+)

## Módulos

| Módulo | Status | Descrição |
|--------|--------|-----------|
| 1 — Infra Cloud | ✅ | Docker Compose: n8n + Redis + Evolution API + Nginx |
| 2 — Arquitetura de Dados | ✅ | Google Sheets (Cold) + Airtable (Hot CRM) + Redis Cache |
| 3 — Mineração de Leads | ✅ | Pré-filtro SERP (barato) → Profile Scraper → Score → Airtable |
| 4 — Scoring & Qualificação | ✅ | Embutido no MOD3: Lead Score JS, filtro B2B/anti-concorrente |
| 5 — Pipeline Temporal | 🔜 | Aquecimento D1→D4, Pitch, Limpeza, Upsell |
| 6 — Cockpit Front-end | 🔜 | SPA HTML/JS/Tailwind, Dashboard local |

## Deploy Rápido (Módulo 1)

```bash
# 1. Clone o repo no servidor
git clone <repo> /opt/sdr-idv
cd /opt/sdr-idv/infra

# 2. Execute o setup do servidor (como root)
sudo bash setup.sh

# 3. Configure as variáveis
nano .env

# 4. Suba a stack
docker compose up -d

# 5. Verifique os containers
docker compose ps
docker compose logs -f
```

## Estrutura

```
sdr-idv/
├── infra/
│   ├── docker-compose.yml   # Stack completa
│   ├── .env.example         # Template de variáveis
│   ├── setup.sh             # Provisionamento Ubuntu
│   └── nginx/               # Configs customizadas Nginx (opcional)
├── workflows/               # Exports JSON dos fluxos n8n (módulos 3-5)
├── frontend/                # Cockpit SPA (módulo 6)
└── .gitignore
```
