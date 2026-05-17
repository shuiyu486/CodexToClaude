CodexToClaude 将 Codex Plus/Pro 订阅通过 CLIProxyAPI 暴露为 Claude Code 可调用的 Anthropic-compatible 本地接口。

```text
Claude Code -> http://127.0.0.1:<Port> -> CLIProxyAPI -> Codex OAuth -> Codex models
```

## 架构速记

- Windows PowerShell 优先；脚本需兼容 Windows PowerShell 5.1，不引入 Node/.NET 打包链路。
- 主业务入口是 `scripts/CodexToClaude.ps1`；GUI、文档和测试都应围绕它，不复制业务逻辑。
- GUI 是 `scripts/CodexToClaude.UI.ps1`，双击入口是 `CodexToClaude-GUI.cmd`；GUI 只收集参数、展示状态、编排步骤并调用 CLI 主脚本。
- CLIProxyAPI 安装目录默认是 `~\.cli-proxy-api`；GUI 偏好保存到 `~\.codextoclaude\ui-preferences.json`。

## 子命令职责

- `install`：创建/更新 CLIProxyAPI config，必要时下载 exe。
- `login`：执行 Codex OAuth 登录，可用 `-Device` 走设备码登录。
- `configure`：写 CLIProxyAPI config，并合并更新 Claude Code `settings.json` 的 env。
- `start` / `stop` / `restart`：管理本机 CLIProxyAPI 进程。
- `status`：显示 exe、config、auth、端口、Claude settings 状态。
- `auth-status`：检查 Codex OAuth auth 状态；GUI 通过 `auth-status -Json` 读取登录状态。
- `verify`：验证 `/v1/models`、`/v1/messages` 和 Claude Code stream-json。
- `doctor`：执行 `status + verify`。
- `project-version` / `project-update`：查看 `VERSION` 项目版本和 git 状态；仅在工作区干净时安全快进更新。
- `cliproxy-version` / `cliproxy-update`：查看/更新 CLIProxyAPI；更新流程必须停服、备份、替换、恢复启动。
- `models` / `configure-models`：查看/更新 Claude Code 的 Opus/Sonnet/Haiku 模型 env。

## 不可破坏的行为契约

- 项目版本号单一真源是根目录 `VERSION`，格式如 `v1.0.0.1`；CLI/GUI/文档示例必须保持一致。

- `port` 和 `proxy-url` 必须由用户显式提供；直连也必须显式确认 `none`/`direct`。
- `ProxyUrl` 只接受 `http://`、`https://`、`socks5://`、`none`、`direct` 等明确值，不把空值猜成直连。
- `configure` 只合并更新 `~/.claude/settings.json` 的目标 `env` 键，保留 `statusLine`、`permissions`、`language` 等其它字段。
- `auth-status` 只扫描 `~/.cli-proxy-api` 根目录 JSON，且可用 auth 必须满足 `type=codex`、非 `disabled=true`。
- 禁止提交或输出 Codex OAuth JSON、`access_token`、`refresh_token`、`id_token`、真实 API key、日志。
- `payload.filter` 过滤 `reasoning` / `reasoning.effort` 是为避免 Claude Code TUI 中文 thinking 流重复字符，不要随意删除。
- `Start-Process` 启动 CLIProxyAPI 时必须显式传 `-config`，并设置 `WorkingDirectory` 为 `~\.cli-proxy-api`。

## GUI 迭代速记

- GUI 语言切换使用 `CodexToClaude.UI.ps1` 内的 `$I18N` 表；新增用户可见文案必须同步 `zh-CN` 和 `en-US`。
- GUI 偏好文件只保存语言、首次向导完成状态和普通输入值，不保存 token、OAuth JSON 或日志。
- 快速开始向导顺序是 `Install -> Login -> Configure -> Restart -> Verify`；每一步仍调用 CLI 子命令。
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
