#!/usr/bin/env python3
"""
AUTO SETUP — Acessa navegador, extrai dados, executa tudo automaticamente
Requer: pip install selenium playwright paramiko requests
"""

import os
import sys
import json
import time
import subprocess
from urllib.parse import urlparse
import requests

class AutoSetup:
    def __init__(self):
        self.vps_ip = "157.230.210.188"
        self.vps_user = "root"
        self.n8n_api_key = None
        self.airtable_token = None
        self.airtable_base_id = None
        self.apify_token = None

    def log(self, msg, level="INFO"):
        colors = {"INFO": "\033[34m", "SUCCESS": "\033[32m", "ERROR": "\033[31m"}
        reset = "\033[0m"
        print(f"{colors.get(level, '')}{level}{reset} {msg}")

    def ask_user(self, prompt, is_secret=False):
        """Pedir informação ao usuário"""
        if is_secret:
            import getpass
            return getpass.getpass(f"🔐 {prompt}: ")
        return input(f"❓ {prompt}: ")

    def open_browser(self, url):
        """Abre navegador em uma URL"""
        self.log(f"Abrindo {url}...", "INFO")
        import webbrowser
        webbrowser.open(url)
        time.sleep(3)

    def extract_airtable_base_id(self):
        """Tenta extrair Base ID do Airtable via Selenium"""
        try:
            from selenium import webdriver
            from selenium.webdriver.common.by import By
            from selenium.webdriver.support.ui import WebDriverWait
            from selenium.webdriver.support import expected_conditions as EC

            self.log("Abrindo Airtable...", "INFO")
            driver = webdriver.Chrome()
            driver.get("https://airtable.com/api")

            self.log("Aguardando você selecionar um base... (máx 60s)", "INFO")
            WebDriverWait(driver, 60).until(
                lambda d: "app" in d.current_url
            )

            # Extrair Base ID da URL
            url = driver.current_url
            if "app" in url:
                base_id = url.split("/")[4] if "/" in url else None
                if base_id and base_id.startswith("app"):
                    self.log(f"Base ID extraído: {base_id}", "SUCCESS")
                    driver.quit()
                    return base_id

            driver.quit()
        except Exception as e:
            self.log(f"Falha ao extrair do navegador: {e}", "ERROR")

        return None

    def collect_credentials(self):
        """Coleta credenciais do usuário"""
        self.log("=== COLETA DE CREDENCIAIS ===", "INFO")
        print("")

        self.n8n_api_key = self.ask_user("N8N API Key", is_secret=True)
        self.airtable_token = self.ask_user("Airtable API Key", is_secret=True)

        # Tentar extrair Base ID automaticamente
        self.log("Tentando extrair Base ID automaticamente...", "INFO")
        self.airtable_base_id = self.extract_airtable_base_id()

        if not self.airtable_base_id:
            self.airtable_base_id = self.ask_user("Airtable Base ID (appXXXXXXXX)")

        self.apify_token = self.ask_user("Apify Token", is_secret=True)

        print("")

    def execute_vps_command(self, cmd):
        """Executa comando no VPS via SSH"""
        try:
            import paramiko

            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(self.vps_ip, username=self.vps_user)

            stdin, stdout, stderr = ssh.exec_command(cmd)
            output = stdout.read().decode()
            error = stderr.read().decode()

            ssh.close()

            if error and "warning" not in error.lower():
                self.log(f"Erro: {error}", "ERROR")
                return False

            return True, output
        except Exception as e:
            self.log(f"Falha SSH: {e}", "ERROR")
            return False

    def provision_n8n(self):
        """Provisiona n8n com credenciais e workflows"""
        self.log("=== PROVISIONANDO N8N ===", "INFO")

        # Montar comando setup.sh
        cmd = f"""
        cd /opt/sdr-idv && \
        git pull && \
        bash setup.sh "{self.n8n_api_key}" "{self.airtable_token}" "{self.airtable_base_id}" "{self.apify_token}"
        """

        self.log("Executando setup no VPS...", "INFO")
        result = self.execute_vps_command(cmd)

        if result:
            self.log("N8N provisionado com sucesso!", "SUCCESS")
            return True
        else:
            self.log("Falha ao provisionar N8N", "ERROR")
            return False

    def run(self):
        """Executa todo o processo"""
        print("")
        print("╔════════════════════════════════════════════════════════════════╗")
        print("║         ⚡ AUTO SETUP — Provisioning Completamente Automático ║")
        print("╚════════════════════════════════════════════════════════════════╝")
        print("")

        # 1. Coletar credenciais
        self.collect_credentials()

        # 2. Provisionar
        if not self.provision_n8n():
            self.log("Setup falhou!", "ERROR")
            sys.exit(1)

        # 3. Sucesso
        print("")
        print("╔════════════════════════════════════════════════════════════════╗")
        print("║                  ✅ SETUP CONCLUÍDO COM SUCESSO!              ║")
        print("╚════════════════════════════════════════════════════════════════╝")
        print("")
        print(f"📊 N8N Dashboard: http://{self.vps_ip}:5678")
        print("   Workflows MOD2 e MOD3 devem estar 🟢 Active")
        print("")
        print("🚀 Próximo: Testar webhook MOD3")
        print("")

if __name__ == "__main__":
    try:
        setup = AutoSetup()
        setup.run()
    except KeyboardInterrupt:
        print("\n❌ Setup cancelado pelo usuário")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Erro: {e}")
        sys.exit(1)
