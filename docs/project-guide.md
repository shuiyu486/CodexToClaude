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
- `project-version` / `project-update`：显示 `VERSION` 项目版本和 git 状态，并在工作区干净时安全快进更新。
- `cliproxy-version` / `cliproxy-update`：显示 CLIProxyAPI 本地/上游版本，并停服替换到 latest release。
- `models` / `configure-models`：查看或更新 Claude Code 使用的 Opus/Sonnet/Haiku 模型。

## GUI 职责

`scripts/CodexToClaude.UI.ps1` 是 WinForms wrapper。

- GUI 只收集参数、展示状态、编排步骤和调用 `CodexToClaude.ps1`。
- 不重复实现安装、登录、配置、启停、认证解析等业务逻辑。
- `Install` / `Configure` 必须要求 `Port` 和 `ProxyUrl`。
- `ProxyUrl` 直连必须显式输入 `none` 或 `direct`。
- GUI 启动和登录后都要刷新 `Login status`。
- 登录状态以 `auth-status -Json` 为唯一真源。

## GUI 语言与首次向导维护约定

GUI 使用单文件数据驱动结构，仍不引入 Node/.NET 打包链路。

- 中英文文案集中在 `CodexToClaude.UI.ps1` 的 `$I18N` 表；新增用户可见文案必须同步 `zh-CN` 和 `en-US`。
- 界面文本通过稳定 key 绑定控件；不要把新文案散落在事件处理器里。
- 语言、首次向导完成状态和最近输入保存到 `~/.codextoclaude/ui-preferences.json`。
- 偏好文件只保存 UI 状态和普通输入，不保存 OAuth JSON、token、日志内容。
- 快速开始向导只映射 `Install -> Login -> Configure -> Restart -> Verify`，每步仍调用 CLI 子命令。
- 高级/诊断操作与首次向导分区展示，避免再次退化为按钮墙。
- 调整向导顺序或文案时，同步 README 的用户步骤、本文档的维护约定和 `CLAUDE.local.md` 的速记规则。
- 版本管理和 CLIProxyAPI 更新放在高级管理窗口，模型配置放在主界面；按钮只能调用 CLI 子命令，不在 GUI 中实现 git、下载、替换 exe 或写 settings 逻辑。

## 上游依赖与版本管理

项目版本号由仓库根目录 `VERSION` 文件维护，格式为 `v<major>.<minor>.<patch>.<build>`，例如 `v1.0.0.1`。`project-version` 和 GUI 标题/高级管理窗口应读取同一个版本源。

CodexToClaude 基于 CLIProxyAPI 构建；CLIProxyAPI 负责本地 Anthropic-compatible API 与 Codex OAuth 能力的代理转换，CodexToClaude 负责 Windows 友好的安装、配置、启停、诊断、更新和 GUI 编排。

- 项目更新使用 `project-update`，只允许在 git 工作区干净时执行 `git fetch` + `git pull --ff-only`，避免覆盖用户未提交改动。
- CLIProxyAPI 更新使用 `cliproxy-update`，流程是 stop -> 下载 latest release -> 备份旧 exe -> 替换 -> 如原本运行则 start。
- CLIProxyAPI 自动下载仍只选择 GitHub release 中 Windows x64 / amd64 的 zip 或 exe asset。
- 更新 CLIProxyAPI 后必须保留 `-config` 和 `WorkingDirectory=~/.cli-proxy-api` 启动契约。
- 修改版本管理逻辑后，除脚本测试外，涉及真实服务管理时仍需跑 `restart` 和 `verify`。

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
- 中英文切换后主要标签、按钮和弹窗文案可读。
- 首次向导步骤仍按 `Install -> Login -> Configure -> Restart -> Verify` 调用 CLI。

## 常见迭代任务

### 改模型默认值

修改 `scripts/CodexToClaude.ps1` param 默认值，并同步 GUI 默认偏好、README 示例和手动安装文档。GUI 保存模型时应调用 `configure-models`，不要直接写 `settings.json`。

### 改 GUI 字段

只改 `CodexToClaude.UI.ps1` 的参数收集、布局、文案表和步骤编排；业务逻辑仍放在 CLI 主脚本。新增用户可见文案必须同时补齐 `zh-CN` 和 `en-US`。

### 改登录诊断

优先改 `Get-AuthStatus` 和 `Write-AuthStatus`，GUI 通过 `auth-status -Json` 复用。

### 改版本更新逻辑

项目自更新必须保持 dirty 工作区阻断和 `pull --ff-only`；CLIProxyAPI 更新必须先停服、备份旧 exe、替换后恢复启动。不要让 GUI 绕过这些 CLI 约束。

### 改启动逻辑

保持 `Start-Process` 显式传入：

```powershell
-FilePath <cli-proxy-api.exe>
-ArgumentList @('-config', '<config.yaml>')
-WorkingDirectory ~/.cli-proxy-api
```

不要退回双击 exe 或依赖当前目录。

## 文档分工

- `README.md`：开源首页，面向最终用户，优先介绍 GUI 和最短路径。
- `docs/claude-code-setup.md`：给 Claude Code 在新机器上自动安装/配置时读取。
- `docs/手动安装与使用.md`：给用户手动安装 CLIProxyAPI、手动改配置时读取。
- `docs/project-guide.md`：给 Claude Code 修改、迭代本项目时按需读取。

文档更新原则：

- 用户入口变化先改 README。
- CLI/GUI 行为变化同步改 `project-guide.md`。
- 手动 CLIProxyAPI 流程变化同步改 `docs/手动安装与使用.md`。
- 避免维护两个内容重复的 manual 文档。

## 安全约束

提交前检查：

```powershell
git status
git diff
```

不要提交 OAuth JSON、日志、token、真实 API key。
