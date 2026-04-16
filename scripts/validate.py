"""
validate.py - Level 1+2 校验: schema 静态校验 + DNS/TLS 可达性
"""

import os
import sys
import ssl
import socket

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)
from install import get_all_presets, PRESETS_DIR

REQUIRED_FIELDS = ['name', 'provider']
VALID_PROVIDERS = ['generic-chat-completion-api', 'anthropic', 'openai', 'zai']


def validate_schema(preset, filename):
    errors = []
    for field in REQUIRED_FIELDS:
        if field not in preset:
            errors.append(f"缺少必需字段: {field}")

    provider = preset.get('provider', '')
    if provider and provider not in VALID_PROVIDERS:
        errors.append(f"provider '{provider}' 不在已知列表 {VALID_PROVIDERS} 中")

    # 检查 regions 中的 base_url
    regions = preset.get('regions', preset.get('_regions', {}))
    if isinstance(regions, dict):
        for region_name, region_data in regions.items():
            if isinstance(region_data, dict):
                url = region_data.get('base_url', '')
                if url and not url.startswith('https://'):
                    errors.append(f"region '{region_name}' 的 base_url 不是 HTTPS: {url}")

    # 检查 models
    models = preset.get('models', preset.get('_models', []))
    if not models:
        errors.append("没有定义任何 model")
    for m in models:
        if not m.get('id'):
            errors.append("model 缺少 id 字段")

    return errors


def check_tls(host, port=443, timeout=10):
    try:
        context = ssl.create_default_context()
        with socket.create_connection((host, port), timeout=timeout) as sock:
            with context.wrap_socket(sock, server_hostname=host) as ssock:
                cert = ssock.getpeercert()
                return True, f"TLS OK, cert subject: {cert.get('subject', '?')}"
    except socket.timeout:
        return False, "连接超时"
    except socket.gaierror as e:
        return False, f"DNS 解析失败: {e}"
    except ssl.SSLError as e:
        return False, f"TLS 错误: {e}"
    except Exception as e:
        return False, f"连接错误: {e}"


def main():
    presets = get_all_presets()
    total_pass = 0
    total_fail = 0

    for p in presets:
        fn = p['_file']
        slug = fn.replace('.yaml', '')
        name = p.get('name', slug)

        print(f"\n--- {slug} ({name}) ---")

        # Level 1: Schema
        errors = validate_schema(p, fn)
        if errors:
            for e in errors:
                print(f"  FAIL schema: {e}")
            total_fail += 1
            continue
        print(f"  PASS schema")

        # Level 2: TLS
        regions = p.get('regions', p.get('_regions', {}))
        if isinstance(regions, dict):
            all_tls_ok = True
            for region_name, region_data in regions.items():
                if not isinstance(region_data, dict):
                    continue
                url = region_data.get('base_url', '')
                if not url:
                    continue
                host = url.replace('https://', '').replace('http://', '').split('/')[0]
                ok, msg = check_tls(host)
                status = "PASS" if ok else "FAIL"
                print(f"  {status} TLS [{region_name}] {host}: {msg}")
                if not ok:
                    all_tls_ok = False

            if all_tls_ok:
                total_pass += 1
            else:
                total_fail += 1
        else:
            print(f"  SKIP TLS (无 region 定义)")
            total_pass += 1

    print(f"\n{'='*50}")
    print(f"结果: {total_pass} 通过, {total_fail} 失败, 共 {len(presets)} 个预设")
    sys.exit(0 if total_fail == 0 else 1)
