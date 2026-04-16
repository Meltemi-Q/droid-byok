#!/usr/bin/env bash
# droid-byok: 一键配置 Codex Gateway (gpt.meltemi.fun) 到 Factory Droid
# 用法: curl -fsSL https://raw.githubusercontent.com/Meltemi-Q/droid-byok/main/install-codex-gateway.sh | bash
#
# 需要: python3 (或 python), ~/.factory/ 目录存在 (droid 已安装)

set -e

FACTORY_CONFIG="${HOME}/.factory/config.json"
BACKUP="${FACTORY_CONFIG}.bak.$(date +%s)"

# 检查 droid 是否安装
if [ ! -d "${HOME}/.factory" ]; then
    echo "[ERROR] ~/.factory/ 不存在，请先安装 Factory Droid: https://docs.factory.ai/cli/getting-started/overview"
    exit 1
fi

# 提示输入
echo "====================================="
echo "  Codex Gateway → Droid BYOK 配置"
echo "====================================="
echo ""

read -p "Codex Gateway URL (默认 https://gpt.meltemi.fun/v1): " BASE_URL
BASE_URL="${BASE_URL:-https://gpt.meltemi.fun/v1}"

read -p "API Key: " API_KEY
if [ -z "$API_KEY" ]; then
    echo "[ERROR] API Key 不能为空"
    exit 1
fi

echo ""
echo "将添加以下模型到 droid:"
echo "  - cgw-gpt-5.4"
echo "  - cgw-gpt-5.4-mini"
echo "  - cgw-gpt-5.3-codex"
echo "  - cgw-gpt-5.3-codex-spark"
echo "  - cgw-gpt-5.2"
echo ""
read -p "确认? (y/N): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "已取消"
    exit 0
fi

# 找 python
PY=$(command -v python3 2>/dev/null || command -v python 2>/dev/null)
if [ -z "$PY" ]; then
    echo "[ERROR] 需要 python3 或 python"
    exit 1
fi

# 备份
if [ -f "$FACTORY_CONFIG" ]; then
    cp "$FACTORY_CONFIG" "$BACKUP"
    echo "[OK] 备份: $BACKUP"
fi

# 写入配置
$PY -c "
import json, os, sys

config_path = os.path.expanduser('~/.factory/config.json')
base_url = '''$BASE_URL'''
api_key = '''$API_KEY'''

# 读取现有配置
if os.path.exists(config_path):
    with open(config_path, 'r', encoding='utf-8') as f:
        config = json.load(f)
else:
    config = {}

if 'custom_models' not in config:
    config['custom_models'] = []

models = [
    ('cgw-gpt-5.4',             'GPT-5.4 [Codex Gateway]',             32000),
    ('cgw-gpt-5.4-mini',        'GPT-5.4 Mini [Codex Gateway]',        32000),
    ('cgw-gpt-5.3-codex',       'GPT-5.3 Codex [Codex Gateway]',       32000),
    ('cgw-gpt-5.3-codex-spark', 'GPT-5.3 Codex Spark [Codex Gateway]', 32000),
    ('cgw-gpt-5.2',             'GPT-5.2 [Codex Gateway]',             32000),
]

added = 0
for model_id, display, max_tok in models:
    exists = any(m.get('model') == model_id for m in config['custom_models'])
    if exists:
        print(f'  skip {display} (already exists)')
        continue
    config['custom_models'].append({
        'model_display_name': display,
        'model': model_id,
        'base_url': base_url,
        'api_key': api_key,
        'provider': 'openai',
        'max_tokens': max_tok,
    })
    added += 1
    print(f'  + {display}')

with open(config_path, 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print(f'\n[OK] {added} models added to {config_path}')
print('重启 droid 后用 /model 选择模型')
"

echo ""
echo "====================================="
echo "  完成! 运行 droid 后按 /model 选择"
echo "====================================="
