# CodexToClaude 项目维护指南

## 目标

CodexToClaude 的目标是把用户的 Codex Plus/Pro 订阅通过 CLIProxyAPI 暴露为 Claude Code 可调用的 Anthropic-compatible 本地接口。

```text
Claude Code → http://127.0.0.1:<Port> → CLIProxyAPI → Codex OAuth
```

## 项目边界

- Windows 优先。
- 以 PowerShell 脚本为主，不引入 Node/.NET SDK 打包链路。
- OAuth 登录仍可能需要用户在浏览器或设备码页面确认。
- 不保存或提交真实 OAuth token。

## 文件结构

```text
CodexToClaude/
├── CodexToClaude-GUI.cmd
├── scripts/
│   ├── CodexToClaude.ps1
│   └── CodexToClaude.UI.ps1
├── docs/
│   ├── manual.md
│   ├── claude-code-setup.md
│   └── project-guide.md
├── test/
│   └── Test-CodexToClaude.ps1
├── README.md
└── CLAUDE.local.md
```

## 主脚本职责

`scripts/CodexToClaude.ps1` 是唯一业务逻辑入口。

子命令：

- `install`：创建/更新 CLIProxyAPI 配置，必要时下载 exe。
- `login`：执行 Codex OAuth 登录。
- `configure`：合并更新 Claude Code `settings.json`。
- `start` / `stop` / `restart`：管理 CLIProxyAPI 进程。
- `status`：显示 exe、config、auth、端口、Claude settings 状态。
- `auth-status`：只检查 Codex OAuth auth 状态。
- `verify`：验证 `/v1/models`、`/v1/messages` 和 Claude Code stream-json。
- `doctor`：执行 status + verify。

## GUI 职责

`scripts/CodexToClaude.UI.ps1` 是 WinForms wrapper。

- GUI 只收集参数和调用 `CodexToClaude.ps1`。
- 不重复实现业务逻辑。
- `Install` / `Configure` 必须要求 `Port` 和 `ProxyUrl`。
- `ProxyUrl` 直连必须显式输入 `none` 或 `direct`。
- GUI 启动和登录后都要刷新 `Login status`。

## 配置写入规则

`config.yaml` 写入位置：

```text
~/.cli-proxy-api/config.yaml
```

核心字段：

```yaml
host: "127.0.0.1"
port: <用户提供>
proxy-url: "<用户提供；直连时省略>"
auth-dir: "~/.cli-proxy-api"
```

`payload.filter` 默认保留：

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

原因：Claude Code TUI 显示 Codex thinking 流时，中文片段可能重复字符；过滤 reasoning 后正常回答文本不受影响。

## Claude Code settings 合并规则

目标文件：

```text
~/.claude/settings.json
```

只更新 `env` 中这些键：

- `ANTHROPIC_AUTH_TOKEN`
- `ANTHROPIC_BASE_URL`
- `ANTHROPIC_DEFAULT_OPUS_MODEL`
- `ANTHROPIC_DEFAULT_SONNET_MODEL`
- `ANTHROPIC_DEFAULT_HAIKU_MODEL`
- `ANTHROPIC_DEFAULT_OPUS_MODEL_NAME`
- `ANTHROPIC_DEFAULT_SONNET_MODEL_NAME`
- `CLAUDE_CODE_EFFORT_LEVEL`

保留 `statusLine`、`permissions`、`language` 等其它字段。

## Login/auth 检查规则

只检查 `~/.cli-proxy-api` 根目录下的 `*.json`，并忽略 settings/test/temp 命名文件。

可用 auth 必须满足：

- JSON 可解析。
- `type` 为 `codex`。
- `disabled` 不是 `true`。

输出时允许显示：

- 文件名。
- email。
- expired。
- usable/issue 状态。

禁止显示：

- `access_token`
- `refresh_token`
- `id_token`

## Port 和 ProxyUrl 规则

- `Port` 必须是 1-65535。
- `ProxyUrl` 必须以 `http://`、`https://`、`socks5://` 开头，或为 `none/direct`。
- 安装和配置时不能猜代理；必须由用户显式提供。
- 若用户直连，也必须显式提供 `none`。

## 测试和验收

修改脚本后必跑：

```powershell
.\test\Test-CodexToClaude.ps1
```

涉及真实服务管理后必跑：

```powershell
.\scripts\CodexToClaude.ps1 status
.\scripts\CodexToClaude.ps1 restart
.\scripts\CodexToClaude.ps1 verify
```

GUI 修改后至少验证：

- `scripts/CodexToClaude.UI.ps1` 可被 PowerShell parser 解析。
- `CodexToClaude-GUI.cmd` 存在。

## 常见迭代任务

### 改模型默认值

修改 `scripts/CodexToClaude.ps1` param 默认值，并同步 README 示例。

### 改 GUI 字段

只改 `CodexToClaude.UI.ps1` 的参数收集和布局；业务逻辑仍放在 CLI 主脚本。

### 改登录诊断

优先改 `Get-AuthStatus` 和 `Write-AuthStatus`，GUI 通过 `auth-status -Json` 复用。

### 改启动逻辑

保持 `Start-Process` 显式传入：

```powershell
-FilePath <cli-proxy-api.exe>
-ArgumentList @('-config', '<config.yaml>')
-WorkingDirectory ~/.cli-proxy-api
```

不要退回双击 exe 或依赖当前目录。

## 安全约束

提交前检查：

```powershell
git status
git diff
```

不要提交 OAuth JSON、日志、token、真实 API key。
