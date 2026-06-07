# CodexToClaude 常驻上下文

CodexToClaude 通过本地代理把多个后端暴露为 Claude Code 可调用的 Anthropic-compatible 接口。

```text
Claude Code -> http://127.0.0.1:<Port> -> CLIProxyAPI -> Codex OAuth -> Codex models
                                     \-> oc-go-cc (serve) -> OpenCode Go models
```

## 先读什么

| 任务 | 先读 |
|---|---|
| 改 CLI 主流程、provider 分发、版本/更新、watchdog、测试策略 | `docs/project-guide.md` |
| 改代理、认证、Claude settings env 合并、token 脱敏 | `docs/maintenance/proxy-auth.md` |
| 改 GUI、i18n、首次向导、provider 切换、偏好文件 | `docs/maintenance/gui.md` |
| 新电脑自动安装/配置 Claude Code | `docs/claude-code-setup.md` |
| 手动安装 CLIProxyAPI 或手动配置用户教程 | `docs/手动安装与使用.md` |

只读取当前任务需要的文档；不要为了小改动一次性加载全部维护文档。

## 架构边界

- Windows PowerShell 5.1 优先；脚本需兼容 Windows PowerShell 5.1，不引入 Node/.NET 打包链路。
- 主业务入口是 `scripts/CodexToClaude.ps1`；GUI、文档和测试都围绕它，不复制业务逻辑。
- provider 位于 `scripts/providers/`：`cliproxy.ps1` 用 `CLIProxy-*`，`occ.ps1` 用 `OCC-*`；主脚本通过 `-Provider cliproxy|occ` 分发。
- GUI 是 `scripts/CodexToClaude.UI.ps1`，双击入口是 `CodexToClaude-GUI.cmd`；GUI 只收集参数、展示状态、编排步骤并调用 CLI 主脚本。
- CLIProxyAPI 默认安装到 `<repo-root>\cli-proxy-api`；oc-go-cc 默认安装到 `<repo-root>\oc-go-cc`，二者均 git 排除。

## 不可破坏契约

- `Port` 和代理模式必须由用户显式提供；直连必须显式选择 `ProxyMode Direct` 或提供 `ProxyUrl none/direct`，不要把空值猜成直连。
- `ProxyMode` 支持 `Auto`、`Http`、`Socks5`、`Direct`；显式 `Http` / `Socks5` / `Direct` 不得被自动切换覆盖。
- `Direct` 必须省略 provider 代理字段；CLIProxy 还必须删除 Codex OAuth JSON 中残留的 `proxy_url`。
- `configure` 只合并更新 `~/.claude/settings.json` 的目标 `env` 键，保留 `statusLine`、`permissions`、`language` 等其它字段。
- 禁止提交或输出 Codex OAuth JSON、`access_token`、`refresh_token`、`id_token`、真实 API key、原始日志。
- CLIProxy 默认不生成 `payload.filter`，透传 `reasoning` / `reasoning.effort` / `thinking`，让 Claude Code 当前 `/effort` / `effortLevel` 决定请求语义；如需规避 thinking 流展示问题，只能由用户手动添加兼容过滤配置。
- `Start-Process` 启动 provider 时必须显式传 config，并设置 `WorkingDirectory` 为 `$InstallDir`。
- OCC 不支持 OAuth login；`-Provider occ -Command login` 必须给出明确错误。
- 版本号单一真源是根目录 `VERSION`；有意义提交前递增 build，并同步 README 徽章和文档示例中的版本号。

## 验证标准

- 修改脚本后必跑：`.	est\Test-CodexToClaude.ps1`。
- 修改代理逻辑时，测试覆盖 `Auto` 归一化、`Socks5` 写入、`Direct` 省略代理字段并清理 CLIProxy auth `proxy_url`。
- 涉及真实环境启动逻辑后必跑：`.\scripts\CodexToClaude.ps1 restart` 和 `.\scripts\CodexToClaude.ps1 verify`。
- GUI 修改至少确认 UI 脚本可解析、`CodexToClaude-GUI.cmd` 存在、中英文切换和快速向导关键路径可用。
- 提交前检查 `git status` 和 `git diff`，确认没有 OAuth JSON、token、真实 API key 或日志。
