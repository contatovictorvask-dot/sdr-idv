#!/usr/bin/env python3
"""
AGENT EXECUTOR — Roda no seu PC e executa ordens automaticamente no navegador
Uso: python3 agent_executor.py --port 9999
Depois eu mando ordens via HTTP e ele executa
"""

import json
import time
import sys
import argparse
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread

try:
    from selenium import webdriver
    from selenium.webdriver.common.by import By
    from selenium.webdriver.support.ui import WebDriverWait
    from selenium.webdriver.support import expected_conditions as EC
except ImportError:
    print("❌ Erro: Selenium não instalado")
    print("Execute: pip install selenium")
    sys.exit(1)

class Agent:
    def __init__(self):
        self.driver = None
        self.running = True

    def start_browser(self):
        """Inicia navegador Chrome"""
        try:
            options = webdriver.ChromeOptions()
            # options.add_argument("--headless")  # Comentado para ver a execução
            self.driver = webdriver.Chrome(options=options)
            print("✅ Navegador iniciado")
            return True
        except Exception as e:
            print(f"❌ Erro ao iniciar navegador: {e}")
            return False

    def execute_command(self, cmd):
        """Executa um comando"""
        if not self.driver:
            return {"status": "error", "message": "Navegador não iniciado"}

        try:
            action = cmd.get("action")

            if action == "navigate":
                url = cmd.get("url")
                print(f"🌐 Navegando para {url}...")
                self.driver.get(url)
                return {"status": "ok", "message": f"Navegado para {url}"}

            elif action == "click":
                selector = cmd.get("selector")
                by = By.CSS_SELECTOR if "." in selector or "#" in selector else By.XPATH
                print(f"🖱️ Clicando em {selector}...")
                elem = WebDriverWait(self.driver, 10).until(EC.element_to_be_clickable((by, selector)))
                elem.click()
                return {"status": "ok", "message": f"Clicado em {selector}"}

            elif action == "type":
                selector = cmd.get("selector")
                text = cmd.get("text")
                by = By.CSS_SELECTOR if "." in selector or "#" in selector else By.XPATH
                print(f"⌨️ Digitando em {selector}...")
                elem = self.driver.find_element(by, selector)
                elem.clear()
                elem.send_keys(text)
                return {"status": "ok", "message": f"Digitado em {selector}"}

            elif action == "wait":
                seconds = cmd.get("seconds", 2)
                print(f"⏳ Aguardando {seconds}s...")
                time.sleep(seconds)
                return {"status": "ok", "message": f"Aguardado {seconds}s"}

            elif action == "screenshot":
                path = cmd.get("path", "/tmp/screenshot.png")
                self.driver.save_screenshot(path)
                print(f"📸 Screenshot salvo em {path}")
                return {"status": "ok", "message": f"Screenshot salvo", "path": path}

            elif action == "execute_script":
                script = cmd.get("script")
                print(f"🔧 Executando script JS...")
                result = self.driver.execute_script(script)
                return {"status": "ok", "message": "Script executado", "result": result}

            else:
                return {"status": "error", "message": f"Ação desconhecida: {action}"}

        except Exception as e:
            return {"status": "error", "message": str(e)}

    def close(self):
        """Fecha navegador"""
        if self.driver:
            self.driver.quit()
            print("❌ Navegador fechado")

# Agent global
agent = Agent()

class CommandHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        """Recebe e executa comandos"""
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode()

        try:
            cmd = json.loads(body)
            result = agent.execute_command(cmd)

            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(result).encode())
        except Exception as e:
            self.send_response(400)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "error", "message": str(e)}).encode())

    def do_GET(self):
        """Health check"""
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({
            "status": "running",
            "message": "Agent Executor pronto para receber ordens"
        }).encode())

    def log_message(self, format, *args):
        """Silencia logs do servidor"""
        pass

def start_server(port):
    """Inicia servidor HTTP"""
    server = HTTPServer(('localhost', port), CommandHandler)
    print(f"🚀 Servidor rodando em http://localhost:{port}")
    print(f"   Esperando ordens...")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n⛔ Servidor interrompido")
        agent.close()
        sys.exit(0)

def main():
    parser = argparse.ArgumentParser(description="Agent Executor")
    parser.add_argument("--port", type=int, default=9999, help="Porta do servidor")
    args = parser.parse_args()

    print("")
    print("╔════════════════════════════════════════════════════════════════╗")
    print("║           🤖 AGENT EXECUTOR — Pronto para Ordens              ║")
    print("╚════════════════════════════════════════════════════════════════╝")
    print("")

    # Iniciar navegador
    if not agent.start_browser():
        sys.exit(1)

    # Iniciar servidor
    start_server(args.port)

if __name__ == "__main__":
    main()
