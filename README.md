# CodexToClaude

CodexToClaude 把用户的 Codex Plus/Pro 订阅通过 CLIProxyAPI 暴露为 Claude Code 可调用的 Anthropic-compatible 本地接口。

默认目标形态：

```text
Claude Code → http://127.0.0.1:<port> → CLIProxyAPI → Codex OAuth
```

## 快速开始

先决定两个值：

- `Port`：CLIProxyAPI 本地监听端口，例如 `8317`。
- `ProxyUrl`：上游代理地址，例如 `http://127.0.0.1:7897`。如果你的网络可直连 Codex 上游，显式使用 `none`。

```powershell
.\scripts\CodexToClaude.ps1 install -Port 8317 -ProxyUrl "http://127.0.0.1:7897"
.\scripts\CodexToClaude.ps1 login
.\scripts\CodexToClaude.ps1 configure -Port 8317 -ProxyUrl "http://127.0.0.1:7897"
.\scripts\CodexToClaude.ps1 restart
.\scripts\CodexToClaude.ps1 verify
```

设备码登录：

```powershell
.\scripts\CodexToClaude.ps1 login -Device
```

直连网络：

```powershell
.\scripts\CodexToClaude.ps1 install -Port 8317 -ProxyUrl none
```

## 常用命令

```powershell
.\scripts\CodexToClaude.ps1 status
.\scripts\CodexToClaude.ps1 start
.\scripts\CodexToClaude.ps1 stop
.\scripts\CodexToClaude.ps1 restart
.\scripts\CodexToClaude.ps1 doctor
```

## 重要安全约束

不要提交 Codex OAuth JSON、日志、真实 token、真实外部 API key。仓库 `.gitignore` 已排除常见敏感文件，但提交前仍应检查 `git status` 和 `git diff`。
