#!/bin/bash
# =============================================================================
# SDR PERPÉTUO B2B v2.0 — Setup Inicial no Ubuntu (DigitalOcean)
# Execute como root: bash setup.sh
# =============================================================================

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Verifica root ---
[ "$EUID" -ne 0 ] && err "Execute como root: sudo bash setup.sh"

log "=== SDR PERPÉTUO B2B v2.0 — Setup Módulo 1 ==="

# --- 1. Atualiza SO ---
log "Atualizando pacotes..."
apt-get update -qq && apt-get upgrade -y -qq

# --- 2. Instala dependências base ---
log "Instalando dependências..."
apt-get install -y -qq \
  curl wget git ufw fail2ban \
  apt-transport-https ca-certificates gnupg lsb-release

# --- 3. Instala Docker ---
if ! command -v docker &> /dev/null; then
  log "Instalando Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
  log "Docker instalado: $(docker --version)"
else
  log "Docker já instalado: $(docker --version)"
fi

# --- 4. Instala Docker Compose v2 plugin ---
if ! docker compose version &> /dev/null; then
  log "Instalando Docker Compose plugin..."
  COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
  curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  log "Docker Compose: $(docker compose version)"
else
  log "Docker Compose já instalado: $(docker compose version)"
fi

# --- 5. Firewall UFW ---
log "Configurando firewall UFW..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp    # HTTP (Nginx)
ufw allow 443/tcp   # HTTPS (Nginx)
ufw allow 81/tcp    # Nginx Proxy Manager Admin (remover após setup)
ufw --force enable
log "UFW ativo. Portas: SSH, 80, 443, 81"
warn "IMPORTANTE: remova a porta 81 após configurar o Nginx Proxy Manager!"
warn "Comando: ufw delete allow 81/tcp && ufw reload"

# --- 6. Fail2Ban ---
log "Habilitando Fail2Ban..."
systemctl enable fail2ban
systemctl start fail2ban

# --- 7. Swap (segurança para Droplets 2GB) ---
if [ ! -f /swapfile ]; then
  log "Criando swap de 2GB..."
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  sysctl vm.swappiness=10
  echo 'vm.swappiness=10' >> /etc/sysctl.conf
  log "Swap criado e ativado."
else
  log "Swap já configurado."
fi

# --- 8. Cria .env a partir do exemplo ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  if [ -f "$SCRIPT_DIR/.env.example" ]; then
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    warn "Arquivo .env criado a partir do .env.example."
    warn "EDITE O .env AGORA antes de subir os containers!"
    warn "  nano $SCRIPT_DIR/.env"
  else
    err ".env.example não encontrado. Verifique o repositório."
  fi
else
  log ".env já existe."
fi

# --- 9. Ajusta permissões dos volumes ---
log "Ajustando permissões de dados..."
mkdir -p /opt/sdr-idv/{n8n,redis,evolution,nginx}
chmod 777 /opt/sdr-idv/n8n   # n8n roda como uid 1000

log ""
log "========================================"
log "  Setup concluído com sucesso!"
log "========================================"
log ""
log "PRÓXIMOS PASSOS:"
log "  1. Edite o arquivo .env:"
log "       nano $SCRIPT_DIR/.env"
log ""
log "  2. Suba os containers:"
log "       cd $SCRIPT_DIR && docker compose up -d"
log ""
log "  3. Acesse o Nginx Proxy Manager:"
log "       http://<IP_DO_SERVIDOR>:81"
log "       Login padrão: admin@example.com / changeme"
log ""
log "  4. Configure os Proxy Hosts no Nginx para:"
log "       n8n.seudominio.com  → sdr_n8n:5678"
log "       evo.seudominio.com  → sdr_evolution:8080"
log ""
log "  5. Após SSL configurado, remova a porta 81:"
log "       ufw delete allow 81/tcp && ufw reload"
log ""
warn "Lembre-se: NUNCA comite o .env no repositório!"
