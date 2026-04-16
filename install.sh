#!/usr/bin/env bash
# droid-byok: 一键配置 AI 模型到 Factory Droid
# 用法: curl -fsSL https://raw.githubusercontent.com/Meltemi-Q/droid-byok/main/install.sh | bash

set -e

FACTORY_CONFIG="${HOME}/.factory/config.json"

if [ ! -d "${HOME}/.factory" ]; then
    echo "[ERROR] ~/.factory/ 不存在，请先安装 Factory Droid"
    exit 1
fi

PY=$(command -v python3 2>/dev/null || command -v python 2>/dev/null)
if [ -z "$PY" ]; then
    echo "[ERROR] 需要 python3"
    exit 1
fi

echo "====================================="
echo "  droid-byok 一键配置"
echo "====================================="
echo ""
echo "选择要配置的模型厂商:"
echo ""
echo "  1) MiniMax M2.7        (国产推理模型, Token Plan)"
echo "  2) DeepSeek R1 / V3    (国产推理模型)"
echo "  3) Moonshot Kimi       (长上下文)"
echo "  4) 智谱 GLM-4.7        (国产大模型)"
echo "  5) 阿里 Qwen           (通义千问)"
echo "  6) OpenRouter           (一个 key 用所有模型)"
echo "  7) 自定义 OpenAI 兼容   (任意 base_url)"
echo ""
read -p "选择 (1-7): " CHOICE

case $CHOICE in
    1)
        PROVIDER="minimax"
        DISPLAY_PREFIX="MiniMax"
        DEFAULT_URL="https://api.minimaxi.com/anthropic"
        DRIVER="anthropic"
        MODELS='[
            {"id":"MiniMax-M2.7","name":"MiniMax M2.7","max":131072}
        ]'
        KEY_HINT="sk-cp-..."
        ;;
    2)
        PROVIDER="deepseek"
        DISPLAY_PREFIX="DeepSeek"
        DEFAULT_URL="https://api.deepseek.com/v1"
        DRIVER="generic-chat-completion-api"
        MODELS='[
            {"id":"deepseek-reasoner","name":"DeepSeek R1","max":8192},
            {"id":"deepseek-chat","name":"DeepSeek V3","max":8192}
        ]'
        KEY_HINT="sk-..."
        ;;
    3)
        PROVIDER="kimi"
        DISPLAY_PREFIX="Kimi"
        DEFAULT_URL="https://api.moonshot.cn/v1"
        DRIVER="generic-chat-completion-api"
        MODELS='[
            {"id":"moonshot-v1-128k","name":"Kimi 128K","max":8192},
            {"id":"moonshot-v1-32k","name":"Kimi 32K","max":8192}
        ]'
        KEY_HINT="sk-..."
        ;;
    4)
        PROVIDER="glm"
        DISPLAY_PREFIX="GLM"
        DEFAULT_URL="https://open.bigmodel.cn/api/anthropic"
        DRIVER="anthropic"
        MODELS='[
            {"id":"glm-4.7","name":"GLM-4.7","max":16384}
        ]'
        KEY_HINT="your-api-key"
        ;;
    5)
        PROVIDER="qwen"
        DISPLAY_PREFIX="Qwen"
        DEFAULT_URL="https://dashscope.aliyuncs.com/compatible-mode/v1"
        DRIVER="generic-chat-completion-api"
        MODELS='[
            {"id":"qwen3-235b-a22b","name":"Qwen3 235B","max":8192},
            {"id":"qwen-plus-latest","name":"Qwen Plus","max":8192}
        ]'
        KEY_HINT="sk-..."
        ;;
    6)
        PROVIDER="openrouter"
        DISPLAY_PREFIX="OpenRouter"
        DEFAULT_URL="https://openrouter.ai/api/v1"
        DRIVER="generic-chat-completion-api"
        MODELS='[
            {"id":"anthropic/claude-sonnet-4","name":"Claude Sonnet 4","max":16384},
            {"id":"openai/gpt-5.4","name":"GPT-5.4","max":32000},
            {"id":"deepseek/deepseek-r1","name":"DeepSeek R1","max":8192},
            {"id":"google/gemini-2.5-pro","name":"Gemini 2.5 Pro","max":65536}
        ]'
        KEY_HINT="sk-or-v1-..."
        ;;
    7)
        PROVIDER="custom"
        DISPLAY_PREFIX=""
        DEFAULT_URL=""
        DRIVER=""
        MODELS=""
        KEY_HINT=""
        ;;
    *)
        echo "[ERROR] 无效选择"
        exit 1
        ;;
esac

echo ""

if [ "$CHOICE" = "7" ]; then
    read -p "显示名称前缀 (如 MyProxy): " DISPLAY_PREFIX
    read -p "Base URL (如 https://api.example.com/v1): " DEFAULT_URL
    read -p "Provider (anthropic / openai / generic-chat-completion-api): " DRIVER
    read -p "模型 ID: " MODEL_ID
    read -p "模型显示名: " MODEL_NAME
    read -p "max_tokens (默认 32000): " MAX_TOK
    MAX_TOK="${MAX_TOK:-32000}"
    MODELS="[{\"id\":\"$MODEL_ID\",\"name\":\"$MODEL_NAME\",\"max\":$MAX_TOK}]"
fi

read -p "Base URL (回车用默认 $DEFAULT_URL): " INPUT_URL
BASE_URL="${INPUT_URL:-$DEFAULT_URL}"

read -p "API Key ($KEY_HINT): " API_KEY
if [ -z "$API_KEY" ]; then
    echo "[ERROR] API Key 不能为空"
    exit 1
fi

# 备份
if [ -f "$FACTORY_CONFIG" ]; then
    cp "$FACTORY_CONFIG" "${FACTORY_CONFIG}.bak.$(date +%s)"
fi

# 写入
$PY -c "
import json, os

config_path = os.path.expanduser('~/.factory/config.json')
base_url = '''$BASE_URL'''
api_key = '''$API_KEY'''
provider = '''$DRIVER'''
prefix = '''$DISPLAY_PREFIX'''
models = json.loads('''$MODELS''')

if os.path.exists(config_path):
    with open(config_path, 'r', encoding='utf-8') as f:
        config = json.load(f)
else:
    config = {}

if 'custom_models' not in config:
    config['custom_models'] = []

added = 0
for m in models:
    mid = m['id']
    exists = any(x.get('model') == mid for x in config['custom_models'])
    if exists:
        print(f'  skip {m[\"name\"]} (already exists)')
        continue
    config['custom_models'].append({
        'model_display_name': f'{m[\"name\"]} [{prefix}]',
        'model': mid,
        'base_url': base_url,
        'api_key': api_key,
        'provider': provider,
        'max_tokens': m['max'],
    })
    added += 1
    print(f'  + {m[\"name\"]} [{prefix}]')

with open(config_path, 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print(f'\n[OK] {added} models added')
"

echo ""
echo "====================================="
echo "  完成! 运行 droid, 按 /model 选择"
echo "====================================="
