#!/usr/bin/env python3
"""
Limpar workflows MOD2 e MOD3 removendo todos os campos não-permitidos
"""
import json
import sys

FIELDS_TO_REMOVE = [
    '_meta', '_comment', '_credentials', 'callerPolicy',
    'executionOrder', 'pinData', 'ui'
]

def clean_workflow(filepath):
    """Remove campos extras que n8n não aceita"""
    with open(filepath) as f:
        data = json.load(f)

    # Remover campos do root
    for field in FIELDS_TO_REMOVE:
        data.pop(field, None)

    # Remover campos de cada nó
    if 'nodes' in data:
        for node in data['nodes']:
            for field in FIELDS_TO_REMOVE:
                node.pop(field, None)

            # Limpar parameters também
            if 'parameters' in node:
                params = node['parameters']
                if isinstance(params, dict):
                    for field in FIELDS_TO_REMOVE:
                        params.pop(field, None)

    # Garantir estrutura mínima
    if 'settings' not in data:
        data['settings'] = {}
    if 'connections' not in data:
        data['connections'] = {}

    return data

def save_clean_workflow(filepath):
    """Salva workflow limpo"""
    workflow = clean_workflow(filepath)
    with open(filepath, 'w') as f:
        json.dump(workflow, f, indent=2)
    return workflow

# Processar ambos
print("🧹 Limpando workflows...")

for name, path in [
    ('MOD2', 'workflows/mod2-blacklist-cache.json'),
    ('MOD3', 'workflows/mod3-mineracao-fila.json')
]:
    try:
        wf = save_clean_workflow(path)
        print(f"✓ {name}: {len(wf.get('nodes', []))} nós, {len(wf.get('connections', {}))} conexões")
    except Exception as e:
        print(f"❌ {name}: {e}")
        sys.exit(1)

print("\n✅ Workflows limpos com sucesso!")
print("Agora execute: python3 import_clean.py")
