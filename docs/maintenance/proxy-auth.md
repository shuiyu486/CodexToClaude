# Proxy/Auth/Settings 维护专题

本文件记录代理、认证、Claude settings 合并和脱敏规则。跨领域生命周期与测试矩阵见 `../project-guide.md`。

## ProxyMode 语义

`ProxyMode` 支持：

| Mode | 行为 |
|---|---|
| `Auto` | 默认；先按 HTTP 写入 provider config，遇到可恢复 TLS/timeout/长请求卡住时可切换同地址 SOCKS5 |
| `Http` | 显式强制 HTTP，不得被自动切换覆盖 |
| `Socks5` | 显式强制 SOCKS5，不得被自动切换覆盖 |
| `Direct` | 直连；忽略代理地址并删除 provider 代理字段 |

规则：

- `Port` 和代理模式必须由用户显式提供。
- 直连必须显式选择 `ProxyMode Direct` 或提供 `ProxyUrl none/direct`。
- 不要把空 `ProxyUrl` 猜成直连。
- `ProxyUrl` 在 `Auto` / `Http` / `Socks5` 下可以是 `host:port`、`http://...`、`https://...`、`socks5://...`。
- 若已持久化 `Direct`，之后用户显式提供非直连 `ProxyUrl` 且未传 `ProxyMode`，应回到默认 `Auto`，不能静默忽略新代理。

## Provider 配置字段

CLIProxyAPI config：

- 文件：`<repo-root>\cli-proxy-api\config.yaml`。
- 直连时省略 `proxy-url`。
- `auth-dir` 指向 `$InstallDir`。
- 保留 `passthrough-headers: true`。
- 保留 bounded retry 相关默认值的诊断可见性。
- 保留 `payload.filter` 覆盖 `reasoning`、`reasoning.effort`、`thinking`，避免 Claude Code TUI 中文 thinking 流重复字符。

OCC config：

- 文件：`<repo-root>\oc-go-cc\config.json`。
- 直连时省略 `proxy_url`。
- `api_key` 默认写 `${OC_GO_CC_API_KEY}`，避免明文存储。
- `respect_requested_model` 默认 `true`，按请求 model 名匹配 `models` key；最低要求 oc-go-cc v0.1.5，老版本会忽略。
- OCC 不支持 `payload.filter`。

## Auto 切换边界

- `Auto` 先按 HTTP 写入。
- `verify` 遇到上游 TLS/timeout 类错误时，可切换为同地址 `socks5://...`，重写 config、同步 CLIProxy OAuth JSON 的 `proxy_url`、重启并重试。
- Watchdog 在 `Auto` 下可记录 HTTP/SOCKS5 stale 状态，并在短时间多次 stale 后临时固定到更少 stale 的协议。
- `Http` / `Socks5` / `Direct` 是显式模式，不得被 `verify` 或 watchdog 覆盖。

## Direct 清理

`Direct` 必须：

- 省略 CLIProxy `proxy-url`。
- 省略 OCC `proxy_url`。
- 删除 CLIProxy Codex OAuth JSON 中残留的 `proxy_url`。
- 不得删除或覆盖 CLIProxy Codex OAuth JSON 中已有的 `websockets` 字段。

## 认证规则

CLIProxyAPI：

- OAuth JSON 扫描范围是 `$InstallDir` 根目录下的 `*.json`。
- 忽略 settings/test/temp 命名文件。
- 可用 auth 必须满足：JSON 可解析、`type = codex`、`disabled` 不是 `true`。
- `login` 支持普通 OAuth 和设备码登录。
- enabled Codex OAuth JSON 缺少 `websockets` 时补 `true`；已有 `true` / `false` 必须原样保留。

OCC：

- 不支持 OAuth login。
- API key 来自 GUI ApiKey 字段、CLI `-ApiKey` 参数，或运行时 `${OC_GO_CC_API_KEY}` 环境变量。
- `-Provider occ -Command login` 必须给出明确错误消息。

允许输出：文件名、email、expired、usable/issue 状态。

禁止输出：`access_token`、`refresh_token`、`id_token`、真实 API key、bearer token、完整 auth JSON、原始日志。

## Claude Code settings 合并

目标文件：

```text
~/.claude/settings.json
```

规则：

- 只合并更新目标 `env` 键。
- 保留 `statusLine`、`permissions`、`language` 等其它字段。
- `NO_PROXY` / `no_proxy` 必须包含 `127.0.0.1`、`localhost`、`::1`，以及当前 provider 的 `127.0.0.1:<Port>` / `localhost:<Port>`。
- CLIProxy 后端移除 `CLAUDE_CODE_EFFORT_LEVEL`，配合 `payload.filter` 过滤 reasoning/thinking 参数。
- OCC 后端设置 `CLAUDE_CODE_EFFORT_LEVEL = "max"`。
- 自定义 `ANTHROPIC_BASE_URL` 下 Claude Code 默认禁用 ToolSearch；除非 provider 已验证支持 `tool_reference` blocks，否则不要设置 `ENABLE_TOOL_SEARCH=true`。

## 命令行代理环境变量

`set-proxy-env` 和 GUI 诊断按钮只写当前用户级命令行环境变量，供新开的 cmd、PowerShell、Git Bash、git/curl/npm 类工具读取；不得设置 Windows 系统代理、WinHTTP、Machine 作用域、`git config` 或 `npm config`。

- 非 `Direct`：写入 `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY` 及小写同名变量。
- `Direct`：清理上述代理变量。
- `NO_PROXY` / `no_proxy` 必须合并保留用户已有条目，并追加 `127.0.0.1`、`localhost`、`::1`、当前 provider 的 `127.0.0.1:<Port>` / `localhost:<Port>`。
- 写入 User 环境后广播 `Environment` 变更；已打开的终端仍建议重开。

常见目标 env 键：

- `ANTHROPIC_AUTH_TOKEN`
- `ANTHROPIC_BASE_URL`
- `NO_PROXY`
- `no_proxy`
- `ANTHROPIC_DEFAULT_OPUS_MODEL`
- `ANTHROPIC_DEFAULT_SONNET_MODEL`
- `ANTHROPIC_DEFAULT_HAIKU_MODEL`
- `ANTHROPIC_DEFAULT_OPUS_MODEL_NAME`
- `ANTHROPIC_DEFAULT_SONNET_MODEL_NAME`
- `ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME`
- `CLAUDE_CODE_EFFORT_LEVEL`

## 验证要求

修改代理逻辑时测试必须覆盖：

- `ProxyMode Auto` 的 `host:port -> http://...` 归一化。
- `ProxyMode Socks5` 写入 `socks5://...`。
- `ProxyMode Direct` 省略 provider 代理字段。
- `ProxyMode Direct` 清理 CLIProxy auth JSON 的 `proxy_url`。
- 显式 `Http` / `Socks5` / `Direct` 不被自动切换覆盖。

修改 settings 合并时确认：

- 只改目标 env 键。
- 保留非 env 配置。
- 不引入 shell profile 依赖。

高级兼容检查必须保持显式 opt-in，避免普通 `verify` 因 provider 不支持高级 Anthropic 功能而失败：

- `verify -CheckTools` 检查 `tools`、`tool_use`、`tool_result` 基本链路。
- `verify -CheckPromptCaching` 检查 prompt caching 的 `usage` 字段是否保留。

提交前检查：

```powershell
git status
git diff
```

确认 diff 中没有 OAuth JSON、token、真实 API key 或日志。
