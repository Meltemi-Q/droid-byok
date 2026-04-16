"""
install.py - 预设安装/卸载/列表/展示
"""

import json
import os
import sys
import getpass

try:
    import yaml
except ImportError:
    yaml = None

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PRESETS_DIR = os.path.join(os.path.dirname(SCRIPT_DIR), 'presets')
FACTORY_CONFIG = os.path.join(os.path.expanduser('~'), '.factory', 'config.json')


def load_yaml(path):
    if yaml:
        with open(path, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f)
    # 没有 pyyaml 时用简易解析 (只处理本项目的 yaml 结构)
    import re
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()
    # 移除注释行和多行字符串 (notes / docs 等) 简化处理
    # 这是一个非常基础的解析器, 只取顶层 key-value
    data = {}
    current_key = None
    in_multiline = False
    models = []
    current_model = {}

    for line in text.split('\n'):
        stripped = line.strip()
        if stripped.startswith('#') or not stripped:
            continue
        if in_multiline:
            if not line.startswith(' ') and not line.startswith('\t'):
                in_multiline = False
            else:
                continue
        if stripped.endswith('|'):
            in_multiline = True
            continue

        m = re.match(r'^(\w[\w_]*)\s*:\s*(.+)?$', stripped)
        if m and not line.startswith(' '):
            key, val = m.group(1), (m.group(2) or '').strip().strip('"').strip("'")
            if val:
                data[key] = val
            current_key = key
        # 解析 models 列表
        if stripped.startswith('- id:'):
            if current_model:
                models.append(current_model)
            current_model = {'id': stripped.split(':', 1)[1].strip().strip('"')}
        elif stripped.startswith('display:') and current_model:
            current_model['display'] = stripped.split(':', 1)[1].strip().strip('"')
        elif stripped.startswith('max_tokens:') and current_model:
            try:
                current_model['max_tokens'] = int(stripped.split(':', 1)[1].strip())
            except ValueError:
                pass
        elif stripped.startswith('default:') and current_model:
            current_model['default'] = stripped.split(':', 1)[1].strip() == 'true'
        elif stripped.startswith('reasoning:') and current_model:
            current_model['reasoning'] = stripped.split(':', 1)[1].strip() == 'true'

    if current_model:
        models.append(current_model)

    data['_models'] = models

    # 解析 regions
    regions = {}
    in_regions = False
    current_region = None
    for line in text.split('\n'):
        stripped = line.strip()
        if stripped == 'regions:':
            in_regions = True
            continue
        if in_regions:
            if not line.startswith(' ') and not line.startswith('\t') and stripped and not stripped.startswith('#'):
                in_regions = False
                continue
            rm = re.match(r'^\s{2}(\w[\w_]*):\s*$', line)
            if rm:
                current_region = rm.group(1)
                regions[current_region] = {}
            elif current_region:
                bm = re.match(r'^\s+base_url:\s*["\']?(.+?)["\']?\s*$', line)
                if bm:
                    regions[current_region]['base_url'] = bm.group(1)
    data['_regions'] = regions

    return data


def get_all_presets():
    presets = []
    for fn in sorted(os.listdir(PRESETS_DIR)):
        if fn.endswith('.yaml') and not fn.endswith('.tpl'):
            path = os.path.join(PRESETS_DIR, fn)
            data = load_yaml(path)
            data['_file'] = fn
            presets.append(data)
    return presets


def list_presets():
    presets = get_all_presets()
    print(f"{'预设名':<20} {'Provider':<30} {'验证状态':<15} {'默认模型'}")
    print('-' * 85)
    for p in presets:
        name = p.get('name', '?')
        provider = p.get('provider', '?')
        fn = p['_file']
        slug = fn.replace('.yaml', '')

        # 获取验证状态
        verified = p.get('verified', {})
        if isinstance(verified, dict):
            status = verified.get('status', 'unverified')
        else:
            status = 'unverified'

        # 获取默认模型
        models = p.get('models', p.get('_models', []))
        default_model = next((m['id'] for m in models if m.get('default')), models[0]['id'] if models else '?')

        status_icon = 'pass' if status == 'pass' else 'unverified'
        print(f"{slug:<20} {provider:<30} {status_icon:<15} {default_model}")


def show_preset(name):
    path = os.path.join(PRESETS_DIR, f'{name}.yaml')
    if not os.path.exists(path):
        print(f"预设 '{name}' 不存在。使用 'droid-byok list' 查看所有预设。")
        sys.exit(1)
    with open(path, 'r', encoding='utf-8') as f:
        print(f.read())


def load_factory_config():
    if not os.path.exists(FACTORY_CONFIG):
        return {'custom_models': []}
    with open(FACTORY_CONFIG, 'r', encoding='utf-8') as f:
        return json.load(f)


def save_factory_config(config):
    os.makedirs(os.path.dirname(FACTORY_CONFIG), exist_ok=True)
    # 备份
    if os.path.exists(FACTORY_CONFIG):
        bak = FACTORY_CONFIG + '.bak'
        with open(FACTORY_CONFIG, 'r', encoding='utf-8') as f:
            with open(bak, 'w', encoding='utf-8') as fb:
                fb.write(f.read())
    with open(FACTORY_CONFIG, 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=2, ensure_ascii=False)


def main(preset_name, region=None):
    path = os.path.join(PRESETS_DIR, f'{preset_name}.yaml')
    if not os.path.exists(path):
        print(f"预设 '{preset_name}' 不存在。")
        list_presets()
        sys.exit(1)

    data = load_yaml(path)
    name = data.get('name', preset_name)
    provider = data.get('provider', 'generic-chat-completion-api')
    models = data.get('models', data.get('_models', []))
    regions = data.get('regions', data.get('_regions', {}))

    # 选择 region
    region_keys = list(regions.keys()) if isinstance(regions, dict) else []
    if not region and len(region_keys) == 1:
        region = region_keys[0]
    elif not region and region_keys:
        print(f"可用区域: {', '.join(region_keys)}")
        region = input("选择区域: ").strip()

    if region and region in regions:
        base_url = regions[region].get('base_url', '')
    else:
        base_url = input(f"输入 base_url (格式如 https://api.example.com/v1): ").strip()

    # 获取 API key
    key_format = data.get('key_format', 'your-api-key')
    api_key = getpass.getpass(f"输入 API Key ({key_format}): ").strip()
    if not api_key:
        print("API Key 不能为空。")
        sys.exit(1)

    # 加载当前配置
    config = load_factory_config()
    if 'custom_models' not in config:
        config['custom_models'] = []

    # 为每个模型生成条目
    added = 0
    for model in models:
        model_id = model.get('id', '')
        display = model.get('display', model_id)
        max_tokens = model.get('max_tokens', 32000)

        display_name = f"{display} [{name}]"

        # 检查是否已存在
        existing = [m for m in config['custom_models'] if m.get('model') == model_id and name in m.get('model_display_name', '')]
        if existing:
            print(f"  跳过 {display_name} (已存在)")
            continue

        entry = {
            'model_display_name': display_name,
            'model': model_id,
            'base_url': base_url,
            'api_key': api_key,
            'provider': provider,
            'max_tokens': max_tokens,
        }
        config['custom_models'].append(entry)
        added += 1
        print(f"  + {display_name}")

    if added > 0:
        save_factory_config(config)
        print(f"\n已安装 {added} 个模型到 {FACTORY_CONFIG}")
        print("重启 droid 后生效。使用 /model 选择模型。")
    else:
        print("没有新模型需要安装。")


def uninstall_preset(preset_name):
    path = os.path.join(PRESETS_DIR, f'{preset_name}.yaml')
    if not os.path.exists(path):
        print(f"预设 '{preset_name}' 不存在。")
        sys.exit(1)

    data = load_yaml(path)
    name = data.get('name', preset_name)

    config = load_factory_config()
    before = len(config.get('custom_models', []))
    config['custom_models'] = [
        m for m in config.get('custom_models', [])
        if name not in m.get('model_display_name', '')
    ]
    removed = before - len(config['custom_models'])

    if removed > 0:
        save_factory_config(config)
        print(f"已移除 {removed} 个 [{name}] 模型。")
    else:
        print(f"config.json 中没有找到 [{name}] 相关模型。")
