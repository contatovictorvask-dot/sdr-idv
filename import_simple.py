#!/usr/bin/env python3
"""
Importador simples - remove TUDO que não seja essencial
"""
import json
import subprocess
import os

API_KEY = os.getenv('N8N_API_KEY', '')
if not API_KEY:
    print("Erro: configure N8N_API_KEY")
    exit(1)

def super_clean(filepath):
    with open(filepath) as f:
        data = json.load(f)

    # Manter APENAS campos obrigatórios
    clean_data = {
        'name': data.get('name'),
        'nodes': data.get('nodes', []),
        'connections': data.get('connections', {}),
        'settings': {'saveManualExecutions': True}
    }

    # Limpar cada nó AGRESSIVAMENTE
    for node in clean_data['nodes']:
        # Manter apenas esses campos
        keep = {'id', 'name', 'type', 'typeVersion', 'position', 'parameters'}
        for key in list(node.keys()):
            if key not in keep:
                del node[key]

    return clean_data

print("🧹 Super-limpando...")

for name, path in [
    ('MOD2', 'workflows/mod2-blacklist-cache.json'),
    ('MOD3', 'workflows/mod3-mineracao-fila.json')
]:
    print(f"\n📥 {name}...")

    try:
        workflow = super_clean(path)

        # POST
        result = subprocess.run([
            'curl', '-s', '-X', 'POST', 'http://localhost:5678/api/v1/workflows',
            '-H', f'X-N8N-API-KEY: {API_KEY}',
            '-H', 'Content-Type: application/json',
            '-d', json.dumps(workflow)
        ], capture_output=True, text=True, timeout=10)

        try:
            resp = json.loads(result.stdout)
            if 'id' in resp:
                print(f"✓ Importado (ID: {resp['id']})")

                # Ativar com PUT em vez de PATCH
                subprocess.run([
                    'curl', '-s', '-X', 'PUT', f"http://localhost:5678/api/v1/workflows/{resp['id']}",
                    '-H', f'X-N8N-API-KEY: {API_KEY}',
                    '-H', 'Content-Type: application/json',
                    '-d', '{"active":true}'
                ], timeout=10)
            else:
                print(f"❌ {resp.get('message', 'Erro desconhecido')}")
                if 'details' in resp:
                    print(f"   Details: {resp['details']}")
        except json.JSONDecodeError:
            print(f"❌ Resposta inválida: {result.stdout[:100]}")
    except Exception as e:
        print(f"❌ {e}")

print("\n✅ Feito!")
