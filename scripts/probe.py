"""
probe.py - Level 3 探测: 用假 key 验证 endpoint 路径正确性

核心技巧: 发送一个故意错误的 key (sk-fake-probe), 根据返回码区分:
  - 401/403 = endpoint 路径正确, key 被拒 (预期行为)
  - 404 = path 写错了
  - 405 = HTTP method 不对
  - DNS/TLS 失败 = base_url 域名错误
"""

import json
import os
import sys
import urllib.request
import urllib.error
import ssl

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)
from install import get_all_presets

FAKE_KEY = "sk-fake-probe-droid-byok-00000"


def probe_endpoint(base_url, provider):
    if provider == 'anthropic':
        url = base_url.rstrip('/') + '/v1/messages'
        headers = {
            'x-api-key': FAKE_KEY,
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
        }
        body = json.dumps({
            'model': 'probe-test',
            'max_tokens': 1,
            'messages': [{'role': 'user', 'content': 'probe'}]
        }).encode()
    else:
        url = base_url.rstrip('/') + '/chat/completions'
        headers = {
            'Authorization': f'Bearer {FAKE_KEY}',
            'Content-Type': 'application/json',
        }
        body = json.dumps({
            'model': 'probe-test',
            'max_tokens': 1,
            'messages': [{'role': 'user', 'content': 'probe'}]
        }).encode()

    req = urllib.request.Request(url, data=body, headers=headers, method='POST')

    try:
        ctx = ssl.create_default_context()
        with urllib.request.urlopen(req, timeout=15, context=ctx) as resp:
            return resp.status, "意外成功 (probe key 不应该被接受!)"
    except urllib.error.HTTPError as e:
        code = e.code
        try:
            resp_body = e.read().decode('utf-8', errors='replace')[:300]
        except Exception:
            resp_body = ''

        if code in (401, 403):
            return code, f"PASS - endpoint 路径正确 (key 被正确拒绝)"
        elif code == 404:
            return code, f"FAIL - 路径不存在 ({url})"
        elif code == 405:
            return code, f"FAIL - 不接受 POST ({url})"
        elif code == 400:
            return code, f"PASS - endpoint 存在 (400 Bad Request 可能是 body 格式)"
        else:
            return code, f"WARN - 非预期状态码 ({resp_body[:100]})"
    except urllib.error.URLError as e:
        return 0, f"FAIL - 网络错误: {e.reason}"
    except Exception as e:
        return 0, f"FAIL - 未知错误: {e}"


def main(target='--all'):
    presets = get_all_presets()

    if target != '--all':
        presets = [p for p in presets if p['_file'].replace('.yaml', '') == target]
        if not presets:
            print(f"预设 '{target}' 不存在。")
            sys.exit(1)

    total_pass = 0
    total_fail = 0

    for p in presets:
        fn = p['_file']
        slug = fn.replace('.yaml', '')
        name = p.get('name', slug)
        provider = p.get('provider', 'generic-chat-completion-api')

        print(f"\n--- {slug} ({name}) ---")

        regions = p.get('regions', p.get('_regions', {}))
        if isinstance(regions, dict):
            for region_name, region_data in regions.items():
                if not isinstance(region_data, dict):
                    continue
                base_url = region_data.get('base_url', '')
                if not base_url or 'your-' in base_url or 'example' in base_url:
                    print(f"  SKIP [{region_name}] 占位符 URL")
                    continue

                code, msg = probe_endpoint(base_url, provider)
                is_pass = code in (401, 403, 400)
                status = "PASS" if is_pass else "FAIL"
                print(f"  {status} [{region_name}] HTTP {code}: {msg}")

                if is_pass:
                    total_pass += 1
                else:
                    total_fail += 1

    print(f"\n{'='*50}")
    print(f"探测结果: {total_pass} 通过, {total_fail} 失败")
    sys.exit(0 if total_fail == 0 else 1)
