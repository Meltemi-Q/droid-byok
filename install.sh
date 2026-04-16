#!/usr/bin/env bash
# droid-byok: 一键配置 AI 模型到 Factory Droid
# 用法: curl -fsSL -o /tmp/droid-byok.sh https://raw.githubusercontent.com/Meltemi-Q/droid-byok/main/install.sh && bash /tmp/droid-byok.sh
#
# 特性:
#   - 重复运行自动清理同厂商旧条目 (clean reinstall)
#   - 自动探测不可用模型并剔除
#   - 支持 7 家厂商 + 自定义

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
echo "  droid-byok 一键配置 v2"
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
echo "  7) CLIProxyAPI 网关     (自建 Codex/Claude OAuth 代理)"
echo "  8) 自定义 OpenAI 兼容   (任意 base_url)"
echo ""
echo "  重复运行会自动清理同厂商旧条目并重建"
echo ""
read -p "选择 (1-8): " CHOICE < /dev/tty

case $CHOICE in
    1)
        TAG="minimax"
        DISPLAY_PREFIX="MiniMax"
        DEFAULT_URL="https://api.minimaxi.com/anthropic"
        DRIVER="anthropic"
        MODELS='[
            {"id":"MiniMax-M2.7","name":"MiniMax M2.7","max":131072}
        ]'
        KEY_HINT="sk-cp-..."
        PROBE_PATH="/v1/messages"
        PROBE_STYLE="anthropic"
        ;;
    2)
        TAG="deepseek"
        DISPLAY_PREFIX="DeepSeek"
        DEFAULT_URL="https://api.deepseek.com/v1"
        DRIVER="generic-chat-completion-api"
        MODELS='[
            {"id":"deepseek-reasoner","name":"DeepSeek R1","max":8192},
            {"id":"deepseek-chat","name":"DeepSeek V3","max":8192}
        ]'
        KEY_HINT="sk-..."
        PROBE_PATH="/chat/completions"
        PROBE_STYLE="openai"
        ;;
    3)
        TAG="kimi"
        DISPLAY_PREFIX="Kimi"
        DEFAULT_URL="https://api.moonshot.cn/v1"
        DRIVER="generic-chat-completion-api"
        MODELS='[
            {"id":"moonshot-v1-128k","name":"Kimi 128K","max":8192},
            {"id":"moonshot-v1-32k","name":"Kimi 32K","max":8192}
        ]'
        KEY_HINT="sk-..."
        PROBE_PATH="/chat/completions"
        PROBE_STYLE="openai"
        ;;
    4)
        TAG="glm"
        DISPLAY_PREFIX="GLM"
        DEFAULT_URL="https://open.bigmodel.cn/api/anthropic"
        DRIVER="anthropic"
        MODELS='[
            {"id":"glm-4.7","name":"GLM-4.7","max":16384}
        ]'
        KEY_HINT="your-api-key"
        PROBE_PATH="/v1/messages"
        PROBE_STYLE="anthropic"
        ;;
    5)
        TAG="qwen"
        DISPLAY_PREFIX="Qwen"
        DEFAULT_URL="https://dashscope.aliyuncs.com/compatible-mode/v1"
        DRIVER="generic-chat-completion-api"
        MODELS='[
            {"id":"qwen3-235b-a22b","name":"Qwen3 235B","max":8192},
            {"id":"qwen-plus-latest","name":"Qwen Plus","max":8192}
        ]'
        KEY_HINT="sk-..."
        PROBE_PATH="/chat/completions"
        PROBE_STYLE="openai"
        ;;
    6)
        TAG="openrouter"
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
        PROBE_PATH="/chat/completions"
        PROBE_STYLE="openai"
        ;;
    7)
        TAG="codex-gateway"
        DISPLAY_PREFIX="Codex Gateway"
        DEFAULT_URL=""
        DRIVER="openai"
        MODELS='[]'
        KEY_HINT="your-gateway-api-key"
        PROBE_PATH=""
        PROBE_STYLE="auto-discover"
        echo ""
        echo "  CLIProxyAPI 网关会自动发现可用模型 (通过 /v1/models)。"
        echo "  GPT 模型 ID 会自动加 cgw- 前缀防止 Factory 劫持。"
        echo "  参考: https://github.com/router-for-me/CLIProxyAPI"
        ;;
    8)
        TAG="custom"
        DISPLAY_PREFIX=""
        DEFAULT_URL=""
        DRIVER=""
        MODELS=""
        KEY_HINT=""
        PROBE_PATH=""
        PROBE_STYLE=""
        ;;
    *)
        echo "[ERROR] 无效选择"
        exit 1
        ;;
esac

echo ""

if [ "$CHOICE" = "8" ]; then
    read -p "厂商标签 (英文, 如 myproxy): " TAG < /dev/tty
    read -p "显示名称前缀 (如 MyProxy): " DISPLAY_PREFIX < /dev/tty
    read -p "Base URL (如 https://api.example.com/v1): " DEFAULT_URL < /dev/tty
    read -p "Provider (anthropic / openai / generic-chat-completion-api): " DRIVER < /dev/tty
    read -p "模型 ID: " MODEL_ID < /dev/tty
    read -p "模型显示名: " MODEL_NAME < /dev/tty
    read -p "max_tokens (默认 32000): " MAX_TOK < /dev/tty
    MAX_TOK="${MAX_TOK:-32000}"
    MODELS="[{\"id\":\"$MODEL_ID\",\"name\":\"$MODEL_NAME\",\"max\":$MAX_TOK}]"
    PROBE_STYLE="openai"
fi

if [ -z "$DEFAULT_URL" ] && [ "$CHOICE" != "7" ]; then
    read -p "Base URL: " DEFAULT_URL < /dev/tty
fi
if [ -n "$DEFAULT_URL" ]; then
    read -p "Base URL (回车用默认 $DEFAULT_URL): " INPUT_URL < /dev/tty
    BASE_URL="${INPUT_URL:-$DEFAULT_URL}"
else
    read -p "Base URL (如 https://your-gateway.com/v1): " BASE_URL < /dev/tty
fi

read -p "API Key ($KEY_HINT): " API_KEY < /dev/tty
if [ -z "$API_KEY" ]; then
    echo "[ERROR] API Key 不能为空"
    exit 1
fi

# 备份
if [ -f "$FACTORY_CONFIG" ]; then
    cp "$FACTORY_CONFIG" "${FACTORY_CONFIG}.bak.$(date +%s)"
fi

echo ""
echo "配置中..."

# 核心逻辑: 清理旧条目 + 自动发现模型 + 探测可用性 + 写入
$PY << PYEOF
import json, os, sys, urllib.request, urllib.error, ssl

config_path = os.path.expanduser('~/.factory/config.json')
base_url = '''$BASE_URL'''
api_key = '''$API_KEY'''
provider = '''$DRIVER'''
prefix = '''$DISPLAY_PREFIX'''
tag = '''$TAG'''
probe_style = '''$PROBE_STYLE'''
static_models = json.loads('''${MODELS:-[]}''')

if os.path.exists(config_path):
    with open(config_path, 'r', encoding='utf-8') as f:
        config = json.load(f)
else:
    config = {}

if 'custom_models' not in config:
    config['custom_models'] = []

# Step 1: 清理同厂商旧条目 (按 display_name 里的 [prefix] 标签匹配)
before = len(config['custom_models'])
config['custom_models'] = [
    m for m in config['custom_models']
    if f'[{prefix}]' not in m.get('model_display_name', '')
]
removed = before - len(config['custom_models'])
if removed:
    print(f'  清理 {removed} 个旧的 [{prefix}] 条目')

# Step 2: 自动发现模型 (CLIProxyAPI 模式)
if probe_style == 'auto-discover' and base_url:
    print(f'  从 {base_url}/models 自动发现模型...')
    try:
        ctx = ssl.create_default_context()
        req = urllib.request.Request(
            base_url.rstrip('/') + '/models',
            headers={'Authorization': f'Bearer {api_key}'}
        )
        with urllib.request.urlopen(req, timeout=15, context=ctx) as resp:
            data = json.loads(resp.read().decode())
            discovered = []
            for m in data.get('data', []):
                mid = m['id']
                # 跳过已有 cgw- 前缀的 (alias), 只用原始名
                if mid.startswith('cgw-'):
                    continue
                # GPT 模型加 cgw- 前缀防 Factory 劫持
                display_id = f'cgw-{mid}' if mid.startswith('gpt-') else mid
                ctx_win = m.get('context_window', '')
                reasoning = m.get('supported_reasoning_levels', [])
                r_tag = ' (reasoning)' if reasoning else ''
                discovered.append({
                    'id': display_id,
                    'name': mid + r_tag,
                    'max': 32000
                })
            if discovered:
                static_models = discovered
                print(f'  发现 {len(discovered)} 个模型')
            else:
                print('  [WARN] 未发现模型，使用默认列表')
    except Exception as e:
        print(f'  [WARN] 自动发现失败: {e}')
        # fallback 默认列表
        if not static_models:
            static_models = [
                {"id":"cgw-gpt-5.4","name":"GPT-5.4","max":32000},
                {"id":"cgw-gpt-5.4-mini","name":"GPT-5.4 Mini","max":32000},
                {"id":"cgw-gpt-5.3-codex","name":"GPT-5.3 Codex","max":32000},
                {"id":"cgw-gpt-5.3-codex-spark","name":"GPT-5.3 Spark","max":32000},
                {"id":"cgw-gpt-5.2","name":"GPT-5.2","max":32000},
            ]

# Step 3: 探测每个模型是否可用 (快速 HTTP 请求)
live_models = []
for m in static_models:
    mid = m['id']
    # 对 auto-discover 模式做实际请求探测
    if probe_style == 'auto-discover' and base_url:
        try:
            # 用原始模型名 (去掉 cgw- 前缀) 发送探测
            probe_model = mid[4:] if mid.startswith('cgw-') else mid
            body = json.dumps({
                'model': probe_model,
                'messages': [{'role':'user','content':'hi'}],
                'max_tokens': 1
            }).encode()
            req = urllib.request.Request(
                base_url.rstrip('/') + '/chat/completions',
                data=body,
                headers={
                    'Authorization': f'Bearer {api_key}',
                    'Content-Type': 'application/json'
                },
                method='POST'
            )
            ctx2 = ssl.create_default_context()
            with urllib.request.urlopen(req, timeout=30, context=ctx2) as resp:
                if resp.status == 200:
                    live_models.append(m)
                    print(f'  ✓ {mid}')
                else:
                    print(f'  ✗ {mid} (HTTP {resp.status})')
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                # auth error = endpoint exists, model might work with right key
                live_models.append(m)
                print(f'  ? {mid} (auth error, keeping)')
            elif e.code == 429:
                # rate limited = model exists
                live_models.append(m)
                print(f'  ✓ {mid} (rate limited but exists)')
            else:
                print(f'  ✗ {mid} (HTTP {e.code}, removed)')
        except Exception as e:
            print(f'  ✗ {mid} ({e}, removed)')
    else:
        # 非 auto-discover 模式直接添加
        live_models.append(m)

# Step 4: 写入
added = 0
for m in live_models:
    config['custom_models'].append({
        'model_display_name': f'{m["name"]} [{prefix}]',
        'model': m['id'],
        'base_url': base_url,
        'api_key': api_key,
        'provider': provider,
        'max_tokens': m['max'],
    })
    added += 1

with open(config_path, 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print(f'\n[OK] 清理 {removed} 旧 + 添加 {added} 新 = {len(config["custom_models"])} 个模型')
PYEOF

echo ""
echo "====================================="
echo "  完成! 运行 droid, 按 /model 选择"
echo "====================================="
