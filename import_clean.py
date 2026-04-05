#!/usr/bin/env python3
"""
Importar MOD2 e MOD3 para n8n (limpa JSONs automaticamente)
Uso: python3 import_clean.py
"""

import json
import subprocess
import sys
import os

# Obter chave da variável de ambiente
API_KEY = os.getenv('N8N_API_KEY')
if not API_KEY:
    print("❌ Erro: configure N8N_API_KEY como variável de ambiente")
    print("   export N8N_API_KEY='sua_chave_aqui'")
    sys.exit(1)

BASE_URL = "http://localhost:5678/api/v1"

def clean_workflow(filepath):
    """Remove campos extras que n8n não aceita"""
    with open(filepath) as f:
        data = json.load(f)

    # Remove campos problemáticos
    for key in ['_meta', 'callerPolicy', 'executionOrder', 'pinData']:
        data.pop(key, None)

    # Limpar nodes
    if 'nodes' in data:
        for node in data['nodes']:
            for key in ['_comment', 'executionOrder', 'callerPolicy']:
                node.pop(key, None)

    # Garantir estrutura mínima
    if 'settings' not in data:
        data['settings'] = {}
    if 'connections' not in data:
        data['connections'] = {}

    return data

def import_workflow(filepath, name):
    """Importa e ativa workflow"""
    print(f"📥 Importando {name}...")

    try:
        # Limpar JSON
        workflow = clean_workflow(filepath)

        # POST para n8n
        cmd = [
            'curl', '-s', '-X', 'POST', f'{BASE_URL}/workflows',
            '-H', f'X-N8N-API-KEY: {API_KEY}',
            '-H', 'Content-Type: application/json',
            '-d', json.dumps(workflow)
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        response = json.loads(result.stdout)

        if 'id' in response:
            wf_id = response['id']
            print(f"✓ {name} importado (ID: {wf_id})")

            # Ativar workflow
            activate_cmd = [
                'curl', '-s', '-X', 'PATCH', f'{BASE_URL}/workflows/{wf_id}',
                '-H', f'X-N8N-API-KEY: {API_KEY}',
                '-H', 'Content-Type: application/json',
                '-d', '{"active":true}'
            ]
            subprocess.run(activate_cmd, timeout=10)
            print(f"  🟢 Ativado")
            return True
        else:
            print(f"❌ Erro: {response.get('message', 'Desconhecido')}")
            return False
    except Exception as e:
        print(f"❌ Erro: {e}")
        return False

def main():
    print("🔄 Importando workflows MOD2 e MOD3...\n")

    mod2_ok = import_workflow('/opt/sdr-idv/workflows/mod2-blacklist-cache.json', 'MOD2 — Blacklist Cache')
    print()
    mod3_ok = import_workflow('/opt/sdr-idv/workflows/mod3-mineracao-fila.json', 'MOD3 — Mineração Fila')

    print("\n" + "="*60)
    if mod2_ok and mod3_ok:
        print("✅ Workflows importados com sucesso!")
        print("\nPróximos passos:")
        print("  1. Abra http://157.230.210.188:5678")
        print("  2. Verifique se MOD2 e MOD3 aparecem como 'Active'")
        print("  3. Execute: ./test_mod3.sh")
    else:
        print("⚠️ Alguns workflows falharam. Verifique acima.")
        sys.exit(1)

if __name__ == '__main__':
    main()
