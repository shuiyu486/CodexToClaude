# CodexToClaude 手动使用说明

## 目标

把 Codex Plus/Pro 订阅通过 CLIProxyAPI 转成本机 Anthropic-compatible API，供 Claude Code 使用。

## 安装

```powershell
.\scripts\CodexToClaude.ps1 install -Port 8317 -ProxyUrl "http://127.0.0.1:7897"
```

如果无需代理：

```powershell
.\scripts\CodexToClaude.ps1 install -Port 8317 -ProxyUrl none
```

`Port` 和 `ProxyUrl` 必须显式提供或在交互提示中确认。不要让脚本猜代理端口，否则安装后的接口测试可能失败。

## 登录

```powershell
.\scripts\CodexToClaude.ps1 login
```

如果普通 OAuth 不方便：

```powershell
.\scripts\CodexToClaude.ps1 login -Device
```

登录后，Codex OAuth JSON 应位于：

```text
%USERPROFILE%\.cli-proxy-api
```

不要把 OAuth JSON 复制到仓库。

## 配置 Claude Code

```powershell
.\scripts\CodexToClaude.ps1 configure -Port 8317 -ProxyUrl "http://127.0.0.1:7897"
```

该命令会合并更新：

```text
%USERPROFILE%\.claude\settings.json
```

只更新 `env` 中 Claude Code 访问本地代理所需字段，不覆盖 `statusLine`、`permissions` 等其它配置。

## 启动、停止、重启

```powershell
.\scripts\CodexToClaude.ps1 start
.\scripts\CodexToClaude.ps1 stop
.\scripts\CodexToClaude.ps1 restart
```

脚本使用显式 `-config` 和正确 `WorkingDirectory` 启动 CLIProxyAPI，避免直接双击 exe 时因当前目录不正确而找不到 `config.yaml`。

## 验证

```powershell
.\scripts\CodexToClaude.ps1 verify
```

验证内容：

- `/v1/models` 返回 Codex 模型列表。
- `/v1/messages` 能返回正常文本。
- 如果本机有 `claude.exe`，额外检查 Claude Code stream-json 中没有 `thinking_delta`。

## thinking 中文重复字符说明

Codex reasoning 流经 Claude Code TUI 时，中文 thinking 片段可能出现字符重复。脚本写入的 `config.yaml` 默认包含：

```yaml
payload:
  filter:
    - models:
        - name: "gpt-*"
          protocol: "codex"
      params:
        - "reasoning"
        - "reasoning.effort"
```

这会过滤上游 Codex reasoning 请求，避免 Claude Code 收到异常 thinking 流；正常回答文本不受影响。

## Web 管理页面

CLIProxyAPI 可能提供：

```text
http://127.0.0.1:<port>/management.html
```

但如果 `remote-management.secret-key` 为空，管理 API 通常不可用。CodexToClaude 以脚本和配置文件为准。
