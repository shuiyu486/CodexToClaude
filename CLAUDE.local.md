CodexToClaude 通过本地代理将多种后端暴露为 Claude Code 可调用的 Anthropic-compatible 接口。

```text
Claude Code -> http://127.0.0.1:<Port> -> CLIProxyAPI -> Codex OAuth -> Codex models
                                     \-> oc-go-cc (serve) -> OpenCode Go models
```

## 架构速记

- Windows PowerShell 优先；脚本需兼容 Windows PowerShell 5.1，不引入 Node/.NET 打包链路。
- 主业务入口是 `scripts/CodexToClaude.ps1`；GUI、文档和测试都应围绕它，不复制业务逻辑。
- `scripts/providers/` 存放后端 provider 脚本（`cliproxy.ps1`、`occ.ps1`）；每个 provider 实现安装、配置、启停、认证、验证等函数，通过前缀（`CLIProxy-` / `OCC-`）区分。主脚本通过 `-Provider` 参数分发。
- GUI 是 `scripts/CodexToClaude.UI.ps1`，双击入口是 `CodexToClaude-GUI.cmd`；GUI 只收集参数、展示状态、编排步骤并调用 CLI 主脚本。
- CLIProxyAPI 安装目录默认是 `<repo-root>\cli-proxy-api`（git 排除）；旧版 `~\.cli-proxy-api` 会自动迁移。
- oc-go-cc 安装目录默认是 `<repo-root>\oc-go-cc`（git 排除）；从 `samueltuyizere/oc-go-cc` GitHub Release 下载二进制，AGPL-3.0 合规（下载模式，不嵌入源码）。

## 子命令职责

- `-Provider cliproxy|occ`：选择后端（默认 cliproxy）。所有子命令尊重此参数。
- `install`：创建/更新 provider config，必要时下载 exe。
- `login`：仅 CLIProxyAPI 支持（Codex OAuth）。OCC 通过 GUI 的 ApiKey 字段或 `-ApiKey` 参数写入 `config.json`；未提供时 fallback 为 `${OC_GO_CC_API_KEY}` 环境变量插值。OCC 的 login 命令会报错提示。
- `configure`：写 provider config，并合并更新 Claude Code `settings.json` 的 env。
- `start` / `stop` / `restart`：管理 provider 进程。两个后端可同时运行在不同端口。
- `status`：显示当前 provider 的 exe、config、auth、端口、Claude settings 状态。
- `auth-status`：检查 provider 认证状态；CLIProxy 扫 OAuth JSON，OCC 检查 API key 环境变量/配置文件。
- `verify`：验证 `/v1/models`、`/v1/messages` 和 Claude Code stream-json。
- `doctor`：执行 `status + verify`。
- `project-version` / `project-update`：查看 `VERSION` 项目版本和 git 状态；仅在工作区干净时安全快进更新。
- `cliproxy-version` / `cliproxy-update`：查看/更新当前 provider 二进制；更新流程必须停服、备份、替换、恢复启动。
- `models` / `configure-models`：查看/更新 Claude Code 的 Opus/Sonnet/Haiku 模型 env。不同 provider 使用不同默认模型。

## 不可破坏的行为契约

- 项目版本号单一真源是根目录 `VERSION`，格式如 `v1.0.0.1`；CLI/GUI/文档示例必须保持一致。

- `port` 和 `proxy-url` 必须由用户显式提供；直连也必须显式确认 `none`/`direct`。
- `ProxyUrl` 只接受 `http://`、`https://`、`socks5://`、`none`、`direct` 等明确值，不把空值猜成直连。
- `configure` 只合并更新 `~/.claude/settings.json` 的目标 `env` 键，保留 `statusLine`、`permissions`、`language` 等其它字段。
- `auth-status` 扫描 `$InstallDir` 根目录 JSON，且可用 auth 必须满足 `type=codex`、非 `disabled=true`。
- 禁止提交或输出 Codex OAuth JSON、`access_token`、`refresh_token`、`id_token`、真实 API key、日志。
- `payload.filter` 过滤 `reasoning` / `reasoning.effort` 是为避免 Claude Code TUI 中文 thinking 流重复字符，不要随意删除。
- `Start-Process` 启动 CLIProxyAPI 时必须显式传 `-config`，并设置 `WorkingDirectory` 为 `$InstallDir`。
- `Start-Process` 启动 oc-go-cc 时必须传 `serve -config <path> --port <port>`，并设置 `WorkingDirectory` 为 `$InstallDir`。启动前必须确保 config 中 `pid_file` 的父目录和 `$env:USERPROFILE\.config\oc-go-cc` 存在，否则 oc-go-cc ≥ v0.1.5 会因写 PID 失败直接退出。
- OCC config 为 JSON 格式；`respect_requested_model` 默认 `true`（最低要求 oc-go-cc v0.1.5），按请求 model 名直接匹配 `models` key，绕过场景检测；老版本忽略此字段。
- OCC config 中 `api_key` 默认写 `${OC_GO_CC_API_KEY}`，通过环境变量插值避免明文存储。
- OCC 不支持 OAuth login；`-Provider occ -Command login` 必须抛出明确错误消息。
- 版本号在 `VERSION` 文件中维护，格式 `v<major>.<minor>.<patch>.<build>`。每次有意义的提交（功能、修复、重构）应自动递增 build 号。修改与版本相关的代码后，同步更新 README 徽章和文档示例中的版本号。
- PowerShell 函数不在解析阶段提升；顶层代码必须在函数定义之后才能调用该函数。函数内部可以调用脚本中任何位置定义的其它函数（因为函数体延迟执行）。
- .NET 属性赋值（如 `$btn.Text = "..."`、`$label.ForeColor = ...`、`$form.Text = ...`）会向管线输出被赋值的对象。必须用 `[void]()` 或 `$null = ` 包裹，防止管线污染累积为 `Object[]` 干扰后续运算。此规则适用于所有 GUI 函数，尤其是 `Apply-Language`、`Update-ProviderButtons`、`Switch-Provider`、`Set-WizardStepState`。
- 调用外部程序后必须检查 `$LASTEXITCODE`；`try/catch` 不会捕获外部进程的非零退出码。
- `Start-Process` 前保存环境变量原始值，`try/finally` 中恢复。
- `UpdateBinary` 必须将下载+替换逻辑整体包裹在 try/catch 中，失败时若原本有运行的服务则重启之。
- 修改 `cliproxy-version`/`cliproxy-update` 逻辑时需确认对两种 provider 都适用（当前两个 `*-version`/`*-update` 命令共享 cliproxy 前缀但作用于当前 `-Provider`）。

## GUI 迭代速记

- GUI 语言切换使用 `CodexToClaude.UI.ps1` 内的 `$I18N` 表；新增用户可见文案必须同步 `zh-CN` 和 `en-US`。
- GUI 偏好文件只保存语言、首次向导完成状态、选中的后端和普通输入值，不保存 token、OAuth JSON 或日志。偏好文件 schema v2，每个后端的端口/安装目录/模型值独立存储。
- 快速开始向导顺序是 `Install -> Login -> Configure -> Restart -> Verify`；OCC 后端隐藏 Login 步骤（改用 API key 环境变量）。
- GUI 后端切换器（provider toggle buttons `Codex` / `OpenCode Go`）切换时自动保存当前后端输入值、恢复新后端的值、重置向导状态和布局。
- 高级/诊断命令与主流程分区展示，避免重新变成一排按钮墙。
- 修改 GUI 文案或向导顺序时，同步 `README.md` 的用户说明和 `docs/project-guide.md` 的维护约定。
- GUI 的版本管理在高级管理窗口，模型配置在主界面；按钮只能调用 CLI 子命令，不直接执行 git、下载、替换 exe 或写 settings。

## 验证标准

- 修改脚本后必跑：`.\test\Test-CodexToClaude.ps1`。
- 涉及真实环境启动逻辑后必跑：`.\scripts\CodexToClaude.ps1 restart` 和 `.\scripts\CodexToClaude.ps1 verify`。
- GUI 修改至少确认 `scripts/CodexToClaude.UI.ps1` 可解析、`CodexToClaude-GUI.cmd` 存在、中英文切换和快速向导关键路径可用。
- 提交前检查 `git status` 和 `git diff`，确认没有 OAuth JSON、token、真实 API key 或日志。

## 文档分工

- `README.md` 面向普通用户和未来开源首页，保持友好、完整但不写维护细节。
- `docs/project-guide.md` 面向 Claude Code 维护/迭代；改启动、认证、GUI 架构、测试流程时再读取。
- `docs/claude-code-setup.md` 面向新电脑自动化配置流程。
- `docs/手动安装与使用.md` 面向不用 CodexToClaude 工具、手动配置 CLIProxyAPI 的用户。
- 本文件只放高频背景、架构边界和不可破坏契约，不复制长手动教程。
