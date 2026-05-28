# 给 Claude Code 的安装维护流程

## 任务目标

在 Windows 机器上使用 CodexToClaude，把 Codex Plus/Pro 订阅通过 CLIProxyAPI 暴露为 Claude Code 可调用的 Anthropic-compatible API。

## 关键原则

- 不要要求用户手工改文件，除 OAuth 浏览器/设备码登录外尽量自动化。
- `Port`、`ProxyMode` 和 `ProxyUrl` 必须由用户显式提供；直连必须显式选择 `Direct` 或确认 `none/direct`。
- 不要把 `access_token`、`refresh_token`、`id_token`、真实 API key 写入仓库或回答中。
- Claude Code 侧只改 `%USERPROFILE%\.claude\settings.json`，不依赖 shell 启动配置。

## 推荐流程

```powershell
.\scripts\CodexToClaude.ps1 install -Port <PORT> -ProxyMode Auto -ProxyUrl "<HOST_PORT_OR_PROXY_URL>"
.\scripts\CodexToClaude.ps1 login
.\scripts\CodexToClaude.ps1 configure -Port <PORT> -ProxyMode Auto -ProxyUrl "<HOST_PORT_OR_PROXY_URL>"
.\scripts\CodexToClaude.ps1 restart
.\scripts\CodexToClaude.ps1 verify
```

`ProxyMode` 可选 `Auto`、`Http`、`Socks5`、`Direct`。推荐代理用户使用 `Auto` 并填写 `127.0.0.1:7897` 这类 `host:port`；`verify` 和后台 watchdog 遇到超时或长请求卡住时可在同地址 HTTP/SOCKS5 间切换，并在短时间多次卡住后临时固定到更少超时的一侧。CLIProxy 登录/配置后会为 enabled Codex OAuth JSON 补齐缺失的 `websockets: true`，保留已有显式值。无代理用户使用 `-ProxyMode Direct`，兼容旧写法 `-ProxyUrl none`；如果之后重新提供非直连 `-ProxyUrl` 且不传 `-ProxyMode`，会回到默认 `Auto`。

如果 OAuth 浏览器登录不方便：

```powershell
.\scripts\CodexToClaude.ps1 login -Device
```

## 版本和模型检查

项目版本号来自仓库根目录 `VERSION` 文件；`project-version` 会同时显示该版本和 git 状态。

首次配置完成后可检查版本与模型：

```powershell
.\scripts\CodexToClaude.ps1 project-version
.\scripts\CodexToClaude.ps1 cliproxy-version
.\scripts\CodexToClaude.ps1 models
```

如果需要更新 CLIProxyAPI，优先使用 `cliproxy-update`；它会停服、替换 exe，并在原服务运行时尝试恢复启动。项目自更新使用 `project-update`，但只会在 git 工作区干净时执行。

如需指定模型：

```powershell
.\scripts\CodexToClaude.ps1 configure-models -OpusModel "<OPUS_MODEL>" -SonnetModel "<SONNET_MODEL>" -HaikuModel "<HAIKU_MODEL>"
```

## 验收标准

- `cli-proxy-api.exe` 正在监听用户指定端口。
- `/v1/models` 返回 Codex 模型列表。
- `/v1/messages` 返回正常文本。
- `%USERPROFILE%\.claude\settings.json` 的 `ANTHROPIC_BASE_URL` 指向 `http://127.0.0.1:<PORT>`。
- Claude Code stream-json 检查能返回 `text_delta`；如果仍出现 `thinking_delta`，工具会提示警告而不是直接判失败。
- Codex 后端的 `config.yaml` 包含 `passthrough-headers: true`，以便把上游 `X-Codex-Primary-*` / `X-Codex-Secondary-*` headers 透传给支持 Codex fallback 的状态栏插件显示 5h/7d usage limits。
- Codex 后端的 `config.yaml` 包含 `codex-header-defaults.user-agent`，作为 Codex OAuth 上游 HTTP/websocket 请求的 UA fallback。

## 排障入口

```powershell
.\scripts\CodexToClaude.ps1 status
.\scripts\CodexToClaude.ps1 doctor
```

如果 `restart` 停止成功但启动失败，重点检查：

- `cli-proxy-api.exe` 是否存在。
- `config.yaml` 是否存在。
- `Start-Process` 是否带了 `-config`。
- `WorkingDirectory` 是否为 `<repo-root>\cli-proxy-api`。
- 目标端口是否被非 CLIProxyAPI 进程占用。
- `status` 是否能通过 `Get-NetTCPConnection` 或 `netstat` fallback 识别当前监听进程。
