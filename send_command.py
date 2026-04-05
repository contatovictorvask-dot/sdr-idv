#!/usr/bin/env python3
"""
Script para enviar ordens ao Agent Executor
Uso: python3 send_command.py --command navigate --url https://example.com
"""

import json
import requests
import argparse
import sys

def send_command(command_data, port=9999):
    """Envia comando para o agent"""
    try:
        url = f"http://localhost:{port}"
        response = requests.post(url, json=command_data, timeout=30)
        result = response.json()

        if result.get("status") == "ok":
            print(f"✅ {result.get('message', 'Comando executado')}")
            if "result" in result:
                print(f"   Resultado: {result['result']}")
        else:
            print(f"❌ {result.get('message', 'Erro desconhecido')}")
        return result
    except requests.exceptions.ConnectionRefusedError:
        print("❌ Erro: Agent não está rodando")
        print("   Execute: python3 agent_executor.py")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Erro: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Enviar comandos ao Agent Executor")
    parser.add_argument("--port", type=int, default=9999, help="Porta do agent")

    # Comandos
    subparsers = parser.add_subparsers(dest="command", help="Tipo de comando")

    # Navigate
    nav = subparsers.add_parser("navigate", help="Navegar para URL")
    nav.add_argument("--url", required=True, help="URL")

    # Click
    click = subparsers.add_parser("click", help="Clicar em elemento")
    click.add_argument("--selector", required=True, help="CSS selector ou XPath")

    # Type
    type_cmd = subparsers.add_parser("type", help="Digitar em campo")
    type_cmd.add_argument("--selector", required=True, help="CSS selector ou XPath")
    type_cmd.add_argument("--text", required=True, help="Texto a digitar")

    # Wait
    wait = subparsers.add_parser("wait", help="Aguardar segundos")
    wait.add_argument("--seconds", type=int, default=2, help="Segundos")

    # Screenshot
    screenshot = subparsers.add_parser("screenshot", help="Tirar screenshot")
    screenshot.add_argument("--path", default="/tmp/screenshot.png", help="Caminho para salvar")

    # Execute script
    script = subparsers.add_parser("execute_script", help="Executar JavaScript")
    script.add_argument("--script", required=True, help="Código JavaScript")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    # Montar comando
    cmd = {"action": args.command}

    if args.command == "navigate":
        cmd["url"] = args.url
    elif args.command == "click":
        cmd["selector"] = args.selector
    elif args.command == "type":
        cmd["selector"] = args.selector
        cmd["text"] = args.text
    elif args.command == "wait":
        cmd["seconds"] = args.seconds
    elif args.command == "screenshot":
        cmd["path"] = args.path
    elif args.command == "execute_script":
        cmd["script"] = args.script

    send_command(cmd, args.port)

if __name__ == "__main__":
    main()
