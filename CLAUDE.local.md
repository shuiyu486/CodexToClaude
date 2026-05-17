## 项目目标

CodexToClaude 将 Codex Plus/Pro 订阅通过 CLIProxyAPI 暴露为 Claude Code 可调用的 Anthropic-compatible 本地接口。

## 维护约定

- Windows PowerShell 优先；脚本需兼容 Windows PowerShell 5.1。
- 主入口是 `scripts/CodexToClaude.ps1`，子命令：`install/login/configure/start/stop/restart/status/auth-status/verify/doctor`。
- `port` 和 `proxy-url` 必须由用户显式提供；直连也必须显式确认 `none`/`direct`。
- 修改脚本后必跑：`.\test\Test-CodexToClaude.ps1`。
- 涉及真实环境启动逻辑后必跑：`.\scripts\CodexToClaude.ps1 restart` 和 `.\scripts\CodexToClaude.ps1 verify`。
- 禁止提交 Codex OAuth JSON、`access_token`、`refresh_token`、`id_token`、真实 API key、日志。
- `payload.filter` 过滤 `reasoning` / `reasoning.effort` 是为避免 Claude Code TUI 中文 thinking 流重复字符，不要随意删除。
- `Start-Process` 启动 CLIProxyAPI 时必须显式传 `-config`，并设置 `WorkingDirectory` 为 `~\.cli-proxy-api`。
- GUI 是 `scripts/CodexToClaude.UI.ps1`，双击入口是 `CodexToClaude-GUI.cmd`；GUI 只调用 CLI 主脚本，不重复业务逻辑。
- 详细项目背景和迭代指南按需读取 `docs/project-guide.md`。

## 文档分工

- `README.md` 面向普通用户和未来开源首页，保持友好、完整但不写维护细节。
- `docs/project-guide.md` 面向 Claude Code 维护/迭代，复杂背景按需读取，不塞进本文件。
- `docs/claude-code-setup.md` 面向新电脑自动化配置流程。
- `docs/手动安装与使用.md` 面向不用 CodexToClaude 工具、手动配置 CLIProxyAPI 的用户。
- 不再维护重复的 `docs/manual.md`；手动说明统一放到 `docs/手动安装与使用.md`。
