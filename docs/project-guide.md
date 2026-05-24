# CodexToClaude 项目维护指南

## 目标

CodexToClaude 的目标是通过本地代理将多种后端暴露为 Claude Code 可调用的 Anthropic-compatible 接口。

```text
Claude Code → http://127.0.0.1:<Port> → CLIProxyAPI → Codex OAuth
                                    \-> oc-go-cc   → OpenCode Go
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
│   ├── CodexToClaude.ps1          ← 主调度 + 共享函数 + 命令分发
│   ├── CodexToClaude.UI.ps1       ← WinForms GUI
│   └── providers/
│       ├── cliproxy.ps1            ← CLIProxyAPI provider (CLIProxy-*)
│       └── occ.ps1                ← oc-go-cc provider (OCC-*)
├── docs/
│   ├── 手动安装与使用.md
│   ├── claude-code-setup.md
│   └── project-guide.md
├── test/
│   └── Test-CodexToClaude.ps1
├── README.md
└── CLAUDE.local.md
```

## 主脚本职责

`scripts/CodexToClaude.ps1` 是分发层：通过 `-Provider cliproxy|occ`（默认 cliproxy）参数选择后端，然后分发到对应 provider 函数。共享工具函数（Write-*, Configure-Claude, Test-ClaudeStreamJson 等）和项目级命令（project-version 等）保留在主脚本中。

`scripts/providers/cliproxy.ps1` 和 `scripts/providers/occ.ps1` 是后端 provider，各自实现前缀函数（CLIProxy-* / OCC-*）：InstallBinary, WriteConfig, StartProcess, StopProcess, GetAuthStatus, InvokeModels, InvokeMessage, GetLatestRelease, UpdateBinary, ShowVersion, ShowStatusDetail, GetConfigValue。

子命令（所有子命令尊重 `-Provider` 参数）：

- `install`：创建/更新 provider 配置，必要时下载 exe。
- `login`：仅 CLIProxyAPI 支持（Codex OAuth）；OCC 报错提示使用环境变量 `OC_GO_CC_API_KEY`。
- `configure`：写 provider config，合并更新 Claude Code `settings.json`。
- `start` / `stop` / `restart`：管理 provider 进程。两个后端可同时运行在不同端口。
- `status`：显示当前 provider 的 exe、config、auth、端口、Claude settings 状态。
- `auth-status`：CLIProxy 扫 OAuth JSON，OCC 检查 API key 环境变量/配置文件。
- `verify`：验证 `/v1/models`、`/v1/messages` 和 Claude Code stream-json。
- `doctor`：执行 status + verify。
- `project-version` / `project-update`：显示 `VERSION` 项目版本和 git 状态，并在工作区干净时安全快进更新。
- `cliproxy-version` / `cliproxy-update`：显示 CLIProxyAPI 本地/上游版本，并停服替换到 latest release。
- `models` / `configure-models`：查看或更新 Claude Code 使用的 Opus/Sonnet/Haiku 模型。

## GUI 职责

`scripts/CodexToClaude.UI.ps1` 是 WinForms wrapper。

- GUI 只收集参数、展示状态、编排步骤和调用 `CodexToClaude.ps1`。
- 不重复实现安装、登录、配置、启停、认证解析等业务逻辑。
- `Install` / `Configure` 必须要求 `Port` 和代理选择；`Direct` 模式可以不要求 `ProxyUrl`。
- GUI 代理模式为 `Auto`、`Http`、`Socks5`、`Direct`；`Auto` 是默认值。
- `ProxyUrl` 直连必须显式输入 `none/direct` 或选择 `Direct`。
- GUI 启动和登录后都要刷新 `Login status`。
- 登录状态以 `auth-status -Json` 为唯一真源。

## GUI 语言与首次向导维护约定

GUI 使用单文件数据驱动结构，仍不引入 Node/.NET 打包链路。

- 中英文文案集中在 `CodexToClaude.UI.ps1` 的 `$I18N` 表；新增用户可见文案必须同步 `zh-CN` 和 `en-US`。
- 界面文本通过稳定 key 绑定控件；不要把新文案散落在事件处理器里。
- 语言、首次向导完成状态和最近输入保存到 `~/.codextoclaude/ui-preferences.json`。
- 偏好文件保存 `proxyMode` 与 `proxyUrl`；代理地址当前为全局共享值，不按 provider 分开保存。
- 偏好文件只保存 UI 状态和普通输入，不保存 OAuth JSON、token、日志内容。
- 快速开始向导只映射 `Install -> Login -> Configure -> Restart -> Verify`，每步仍调用 CLI 子命令。
- 高级/诊断操作与首次向导分区展示，避免再次退化为按钮墙。
- 调整向导顺序或文案时，同步 README 的用户步骤、本文档的维护约定和 `CLAUDE.local.md` 的速记规则。
- 版本管理和 CLIProxyAPI 更新放在高级管理窗口，模型配置放在主界面；按钮只能调用 CLI 子命令，不在 GUI 中实现 git、下载、替换 exe 或写 settings 逻辑。

## 上游依赖与版本管理

项目版本号由仓库根目录 `VERSION` 文件维护，格式为 `v<major>.<minor>.<patch>.<build>`，例如 `v1.0.0.2`。`project-version` 和 GUI 标题/高级管理窗口应读取同一个版本源。

**版本自动迭代规则**：每次有意义的提交（新功能、bug 修复、重构）应自动递增 build 号（第四位）。major/minor/patch 的变更由维护者判断。实现方式：
- 每次提交前检查 `VERSION` 是否需要 bump
- 同步更新 `README.md` 中的版本徽章（`version-v1.0.0.x-lightgrey`）
- `project-version` 命令读取 `VERSION` 文件显示当前版本和 git 状态

CodexToClaude 基于 CLIProxyAPI 和 oc-go-cc 构建：
- CLIProxyAPI 负责本地 Anthropic-compatible API 与 Codex OAuth 能力的代理转换
- oc-go-cc 负责 Anthropic↔OpenAI 格式转换，面向 OpenCode Go 后端
- CodexToClaude 负责 Windows 友好的安装、配置、启停、诊断、更新和 GUI 编排

- 项目更新使用 `project-update`，只允许在 git 工作区干净时执行 `git fetch` + `git pull --ff-only`，避免覆盖用户未提交改动。
- 二进制更新使用 `cliproxy-update`（同时作用于当前 `-Provider`），流程是 stop -> 下载 latest release -> staged exe -> 备份旧 exe -> 删除旧 exe -> 移动 staged exe -> 如原本运行则 start。Windows PowerShell 5.1 下不要依赖 `Move-Item -Force` 覆盖已存在 exe；替换失败时必须从备份恢复并重启原有服务。
- 自动下载只选择 GitHub release 中 Windows x64 / amd64 的 zip 或 exe asset。
- 更新后必须保留 `-config` 和 `WorkingDirectory` 设为 `$InstallDir` 的启动契约。
- 修改版本管理逻辑后，除脚本测试外，涉及真实服务管理时仍需跑 `restart` 和 `verify`。

## 配置写入规则

`config.yaml` 写入位置：

```text
<repo-root>\cli-proxy-api\config.yaml
```

核心字段：

```yaml
host: "127.0.0.1"
port: <用户提供>
proxy-url: "<按 ProxyMode 规范化后的代理；直连时省略>"
auth-dir: "$InstallDir"
passthrough-headers: true
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
        - "thinking"
```

`passthrough-headers: true` 用于把上游 `X-Codex-*` / rate-limit headers 透传给 Claude Code 或状态栏插件，供用量限制显示和调试使用。

原因：Claude Code TUI 显示 Codex thinking 流时，中文片段可能重复字符，且 `gpt-5.5` 的长 thinking 流可能让主 agent 迟迟不返回；过滤 reasoning/thinking 后正常回答文本不受影响。

## 主 agent 卡住防护

`start` 和 `restart` 必须把 provider readiness 定义为 health endpoint 成功响应，而不是仅有 TCP 端口监听。端口拥有者判断只能使用 `Listen` 状态且 `OwningProcess > 0` 的 socket，避免把 Windows 残留的 `Idle pid=0` 连接误判为端口占用。CLIProxy 启动后必须同时启动 CodexToClaude watchdog；`stop` 必须关闭 watchdog。watchdog 监控启动后的新 `/v1/messages` 长请求，默认 30 秒仍未完成时自动重启当前 CLIProxy provider，等价于用户手动点 GUI 重启；恢复尝试后必须重置观察窗口，避免旧 stale request 留在日志尾部导致重复重启。watchdog 不得因为快速返回的 5xx 响应重启 provider，避免切断正在进行的 Claude Code 流式请求；这类短错误交给 Claude Code 自身 retry。高级用户可通过 `-WatchdogTimeoutSeconds` 调整长请求阈值。

`verify` 和 `doctor` 遇到可恢复的本地代理或 stream-json 探测失败时，可以自动重启当前 provider 一次并重试；`status` 必须保持只读，不得 start、stop、restart、重写 config 或切换代理模式。

Claude Code `stream-json` 检查必须有 60 秒 watchdog。若 `claude.exe` 探测在该窗口内不退出，脚本应终止该探测进程并报告 stream timeout，避免诊断命令自身无限挂起。

CLIProxy 诊断需要保持 bounded-retry 默认值可见：`request-retry: 1`、`max-retry-credentials: 1`、`max-retry-interval: 5`、`streaming.bootstrap-retries: 1`、`quota-exceeded.antigravity-credits: false`，并确认 `payload.filter` 覆盖 `reasoning`、`reasoning.effort` 和 `thinking`。输出日志片段前必须脱敏，不能包含 OAuth token、API key、bearer token 或完整 auth JSON。

`config.json`（oc-go-cc）写入位置：

```text
<repo-root>\oc-go-cc\config.json
```

核心字段：

```json
{
    "host": "127.0.0.1",
    "port": <用户提供>,
    "api_key": "<用户提供或 ${OC_GO_CC_API_KEY}>",
    "pid_file": "<InstallDir>\\oc-go-cc.pid",
    "hot_reload": false,
    "respect_requested_model": true,
    "models": {
        "deepseek-v4-pro": { "provider": "opencode-go", "model_id": "deepseek-v4-pro", "temperature": 0.7, "max_tokens": 384000, ... },
        "deepseek-v4-flash": { "provider": "opencode-go", "model_id": "deepseek-v4-flash", "temperature": 0.5, "max_tokens": 384000, ... },
        "default": { "provider": "opencode-go", "model_id": "deepseek-v4-pro", ... },
        "background": { ... },
        "think": { ... },
        "complex": { ... },
        "long_context": { ..., "context_threshold": 1000000 },
        "fast": { ... }
    },
    "fallbacks": { ... },
    "opencode_go": { "base_url": "...", "timeout_ms": 300000 },
    "proxy_url": "<按 ProxyMode 规范化后的代理；直连时省略>",
    "logging": { "level": "info", "requests": true }
}
```

- `api_key`：用户通过 GUI 的 ApiKey 字段或 CLI 的 `-ApiKey` 提供时写入真实值；否则写入 `${OC_GO_CC_API_KEY}` 占位符（oc-go-cc 在运行时通过环境变量插值解析）。
- `respect_requested_model`：设为 `true` 时绕过场景检测，直接按请求中的 model 名查找 `models` 条目。需要 oc-go-cc ≥ v0.1.5。老版本忽略此字段。
- `models`：
  - 顶层 key 既可以是**模型名**（`deepseek-v4-pro`、`deepseek-v4-flash`，对应 Claude Code 的 Opus/Sonnet/Haiku tier），也可以是**场景名**（`default`/`think`/`complex`/`background`/`long_context`/`fast`）。
  - 模型名条目：`deepseek-v4-pro`（Opus/Sonnet，temperature=0.7，max_tokens=384K）和 `deepseek-v4-flash`（Haiku，temperature=0.5，max_tokens=384K）。`respect_requested_model` 打开时 oc-go-cc 优先匹配这些 key。
  - 场景条目：作为 `respect_requested_model` 关闭时的 fallback 路由，均指向 `deepseek-v4-pro`。
  - 所有条目均配置 `reasoning_effort: "max"` 和 `thinking: { type: "enabled" }`。
- `fallbacks`：每个场景的故障转移链，同样指向 `deepseek-v4-pro`（利用 oc-go-cc 内置熔断器重试）。
- `context_threshold`：超过 1M tokens 触发 long_context 场景路由。
- `opencode_go.base_url`：上游 OpenCode Go API 端点。
- OCC 不支持 `payload.filter`，无 reasoning 过滤配置。

## Claude Code settings 合并规则

目标文件：

```text
~/.claude/settings.json
```

只更新 `env` 中这些键：

- `ANTHROPIC_AUTH_TOKEN`
- `ANTHROPIC_BASE_URL`
- `NO_PROXY`
- `no_proxy`
- `ANTHROPIC_DEFAULT_OPUS_MODEL`
- `ANTHROPIC_DEFAULT_SONNET_MODEL`
- `ANTHROPIC_DEFAULT_HAIKU_MODEL`
- `ANTHROPIC_DEFAULT_OPUS_MODEL_NAME`
- `ANTHROPIC_DEFAULT_SONNET_MODEL_NAME`
- `CLAUDE_CODE_EFFORT_LEVEL`（OCC 后端设为 `"max"`；CLIProxy 后端移除此键以配合 payload.filter 过滤 reasoning/thinking 参数）

保留 `statusLine`、`permissions`、`language` 等其它字段。`NO_PROXY` / `no_proxy` 必须包含 `127.0.0.1`、`localhost`、`::1` 以及当前 provider 的 `127.0.0.1:<Port>` / `localhost:<Port>`，防止 Claude Code 对本地 Anthropic-compatible endpoint 的请求被系统代理接管。

## Login/auth 检查规则

只检查 `<repo-root>\cli-proxy-api` 根目录下的 `*.json`，并忽略 settings/test/temp 命名文件。

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
- `ProxyMode` 为 `Auto`、`Http`、`Socks5`、`Direct`；默认 `Auto`。
- `ProxyUrl` 可以是 `host:port`，也可以以 `http://`、`https://`、`socks5://` 开头，或为 `none/direct`。
- 安装和配置时不能猜是否需要代理；必须由用户显式提供代理模式。
- `Auto` 先按 HTTP 写入，`verify` 遇到上游超时时可切换为同地址 SOCKS5 并持久化到 provider config；CLIProxy 同步更新 OAuth JSON 的 `proxy_url`。
- 若用户直连，也必须显式选择 `Direct` 或提供 `none`。

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
-WorkingDirectory $InstallDir
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

## PowerShell 编码约束

### 管线输出污染

.NET 属性赋值（如 `$btn.Text = "..."`、`$label.ForeColor = ...`）会向管线输出被赋值的对象。在函数中累积的管线输出会形成 `Object[]`，当意外进入算术表达式时触发 `[System.Object[]]` 不包含 `op_Subtraction` 错误。

**规则**：所有 .NET 属性赋值必须用 `[void]()` 或 `$null = ` 包裹。

```powershell
# 正确
[void]($btn.Text = "Update")
[void]($label.ForeColor = [System.Drawing.Color]::ForestGreen)

# 错误 — 会泄漏到管线
$btn.Text = "Update"
$label.ForeColor = [System.Drawing.Color]::ForestGreen
```

此规则尤其适用于以下函数：`Apply-Language`、`Update-ProviderButtons`、`Switch-Provider`、`Set-WizardStepState`。

### 函数定义顺序

PowerShell 不会在解析阶段提升函数定义。顶层代码（不在任何函数内的代码）必须在函数定义**之后**才能调用该函数。

```powershell
# 错误 — 顶层代码在函数定义前调用
Do-Something                    # 此时函数尚未注册
function Do-Something { ... }

# 正确 — 函数先定义，顶层代码后调用
function Do-Something { ... }
Do-Something
```

函数**内部**可以调用脚本中任何位置定义的其他函数，因为函数体延迟执行。

### 外部进程退出码

`try/catch` 不会捕获外部进程的非零退出码。调用外部 exe 后必须显式检查 `$LASTEXITCODE`。

```powershell
& $ExePath -config $ConfigPath $loginArg
if ($LASTEXITCODE -ne 0) { throw "Login failed with exit code $LASTEXITCODE." }
```

### 环境变量恢复

在函数中临时修改进程级环境变量后，必须在 `try/finally` 的 `finally` 块中恢复原始值。

### `$args` 自动变量

函数体内不要使用 `$args` 作为局部变量名；它是 PowerShell 的自动变量，遮蔽后会破坏未绑定参数的接收能力。改用 `$cliArgs`、`$authArgs` 等描述性名称。
