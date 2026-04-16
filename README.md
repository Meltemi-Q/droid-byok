# droid-byok

Factory Droid CLI 的 BYOK (Bring Your Own Key) 模型预设集合。

一行命令，把 MiniMax / DeepSeek / Kimi / 智谱 GLM / Qwen / OpenRouter 等模型接入 [Factory Droid](https://docs.factory.ai/cli/getting-started/overview)。

## 为什么需要这个项目

Droid 原生支持 BYOK，但配置过程有几个痛点：

1. **每家 API 的 `base_url` / `provider` / `model` 名不一样**，查文档 + 试错浪费时间
2. **有些厂商有隐藏坑**（比如 MiniMax Token Plan 的 `sk-api-` key 不能调 chat，要用 `sk-cp-`；再比如推理模型的 `<think>` 标签在错误的 provider 下会泄漏到聊天里）
3. **没有一个集中的地方**能列出"哪些模型已经被验证能跑在 droid 上"

本项目解决这三个问题。

## 快速开始

### 方式一：用 CLI 工具安装

```bash
git clone https://github.com/Meltemi-Q/droid-byok.git
cd droid-byok

# 列出所有可用预设
python scripts/droid-byok list

# 安装 MiniMax M2.7 (会提示你输入 API Key)
python scripts/droid-byok install minimax --region cn

# 安装 DeepSeek
python scripts/droid-byok install deepseek --region global

# 查看某个预设的详细信息
python scripts/droid-byok show minimax
```

安装后重启 droid，按 `/model` 即可在底部 Custom Models 区域看到新模型。

### 方式二：手动复制

打开 `presets/` 目录，找到你需要的预设文件（如 `minimax.yaml`），参考里面的配置手动编辑 `~/.factory/config.json`：

```json
{
  "custom_models": [
    {
      "model_display_name": "MiniMax M2.7 [MiniMax]",
      "model": "MiniMax-M2.7",
      "base_url": "https://api.minimaxi.com/anthropic",
      "api_key": "你的 sk-cp- key",
      "provider": "anthropic",
      "max_tokens": 131072
    }
  ]
}
```

## 预设列表

| 预设 | 厂商 | 默认模型 | Provider | 验证状态 |
|------|------|----------|----------|----------|
| `minimax` | MiniMax | MiniMax-M2.7 | anthropic | **已验证** |
| `codex-gateway` | 自建网关 | gpt-5.4 | generic-chat-completion-api | **已验证** |
| `deepseek` | DeepSeek | deepseek-reasoner (R1) | generic-chat-completion-api | 文档来源 |
| `moonshot-kimi` | 月之暗面 | moonshot-v1-128k | generic-chat-completion-api | 文档来源 |
| `zhipu-glm` | 智谱 AI | glm-4.7 | anthropic | 文档来源 |
| `dashscope-qwen` | 阿里云 | qwen3-235b-a22b | generic-chat-completion-api | 文档来源 |
| `openrouter` | OpenRouter | (多模型) | generic-chat-completion-api | 文档来源 |

**"已验证"** = 用真实 key 端到端跑通 `droid exec -m <model> "hi"`
**"文档来源"** = 配置来自官方文档，通过了 schema 校验 + endpoint 探测，但未用真 key 测试

## 验证体系

本项目对每个预设做四级验证：

| 级别 | 内容 | 需要 key 吗 | 何时执行 |
|------|------|-------------|----------|
| Level 1 | YAML schema 静态校验 | 不需要 | CI 每次 PR |
| Level 2 | DNS + TLS 握手 | 不需要 | CI 每次 PR |
| Level 3 | 假 key 探测 endpoint 路径 | **不需要** (用假 key) | CI 每次 PR |
| Level 4 | 真 key 端到端对话 | **需要** | 贡献者手动 |

Level 3 的核心技巧：用 `sk-fake-probe` 打目标 endpoint，如果返回 `401 invalid api key` 就说明路径正确（只是 key 是假的），如果返回 `404` 就说明路径写错了。**这样不花一分钱就能验证 99% 的配置正确性。**

### 本地运行验证

```bash
# Level 1 + Level 2
python scripts/validate.py

# Level 3
python scripts/probe.py --all

# 只探测某个预设
python scripts/probe.py minimax

# pytest (Level 1)
python -m pytest tests/ -v
```

## 踩坑记录

### MiniMax: sk-cp- vs sk-api- 的区别

这是我们实际调试中发现的，官方文档没有写清楚：

| | `sk-cp-...` | `sk-api-...` |
|---|---|---|
| 用途 | Coding Plan / Token Plan 订阅 key | 通用 MaaS 开发者 key |
| 计费 | 固定月费 + 按次数配额 | 按 token 量从账户余额扣 |
| 能调 chat API 吗 | **能** | 取决于余额 |
| 扣 Token Plan 额度吗 | **是** | **否** |

如果你在 MiniMax 控制台的 Token Plan 页面看到一个 key，它的前缀是 `sk-cp-`，直接拿来用。如果是 `sk-api-`，那是另一个计费体系。

### Provider 选择: anthropic vs generic-chat-completion-api

这个选择**不只是协议差异**，还影响 droid 是否能折叠推理模型的 `<think>` 输出：

| Provider | 协议 | 推理折叠 | 推荐场景 |
|----------|------|----------|----------|
| `anthropic` | Anthropic Messages API | **droid 自动折叠 thinking block** | MiniMax / 智谱 GLM 等提供 /anthropic 路由的厂商 |
| `generic-chat-completion-api` | OpenAI Chat Completions | `<think>` 标签直接显示在聊天里 | DeepSeek / Kimi / OpenRouter |

如果厂商同时提供两种接口（如 MiniMax、智谱），**优先选 `anthropic`** 可以获得更干净的输出。

## 贡献指南

欢迎 PR 新的预设！提交时需要：

1. 在 `presets/` 下新建 `<provider>.yaml`，格式参考已有文件
2. 确保 `python scripts/validate.py` 通过
3. 确保 `python scripts/probe.py <your-preset>` 返回 PASS
4. 如果你有真 key 且测试通过，在 `verified` 字段标注
5. 在 README 的预设列表中添加一行

### 如何调试一个新厂商的配置

以下是我们调试 MiniMax 时总结的方法论：

```bash
# 1. 先查官方文档找 base_url 和 model 名
# 2. 用假 key 探测 endpoint 是否存在
curl -s -X POST https://api.example.com/v1/chat/completions \
  -H "Authorization: Bearer sk-fake-test" \
  -H "Content-Type: application/json" \
  -d '{"model":"model-name","messages":[{"role":"user","content":"hi"}],"max_tokens":1}'
# 期望返回 401 (key 被拒) 而不是 404 (路径不存在)

# 3. 换真 key 测试
curl -s -X POST ... -H "Authorization: Bearer YOUR_REAL_KEY" ...
# 期望返回 200 + 正常回复

# 4. 测通后写 preset 文件, 跑 validate + probe
# 5. 用 droid exec 做端到端验证
droid exec -m "model-name" "只回复 OK"
```

## 卸载

```bash
# 从 config.json 移除某个预设安装的所有模型
python scripts/droid-byok uninstall minimax
```

## 许可证

MIT
