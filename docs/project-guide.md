# CodexToClaude 维护总路由

本文件是项目维护入口。只放跨领域规则和任务路由；GUI、代理/认证/settings 细节分别下沉到专题文档。

## 任务路由

| 任务 | 需要读取 |
|---|---|
| CLI 主流程、provider 分发、命令新增/改名 | 本文件 |
| 代理、认证、Claude settings、token 脱敏 | `docs/maintenance/proxy-auth.md` |
| GUI、i18n、首次向导、偏好文件 | `docs/maintenance/gui.md` |
| 用户安装/配置自动化流程 | `docs/claude-code-setup.md` |
| 手动安装教程、CLIProxyAPI 手动配置 | `docs/手动安装与使用.md` |

## 架构与入口

```text
Claude Code -> http://127.0.0.1:<Port> -> CLIProxyAPI -> Codex OAuth -> Codex models
                                     \-> oc-go-cc (serve) -> OpenCode Go models
```

- 主入口：`scripts/CodexToClaude.ps1`。
- GUI：`scripts/CodexToClaude.UI.ps1`；双击入口：`CodexToClaude-GUI.cmd`。
- Providers：`scripts/providers/cliproxy.ps1` 和 `scripts/providers/occ.ps1`。
- 测试：`test/Test-CodexToClaude.ps1`。
- 项目版本：根目录 `VERSION`，格式 `v<major>.<minor>.<patch>.<build>`。

## Provider 分层

主脚本负责：参数、共享工具函数、Claude settings 合并、命令分发、项目级命令。

每个 provider 负责自己的安装、配置、启停、认证、验证、版本和状态细节：

| Provider | 脚本 | 函数前缀 | 认证方式 |
|---|---|---|---|
| CLIProxyAPI | `scripts/providers/cliproxy.ps1` | `CLIProxy-*` | Codex OAuth JSON |
| oc-go-cc | `scripts/providers/occ.ps1` | `OCC-*` | API key / `${OC_GO_CC_API_KEY}` |

不要在 GUI 或文档脚本中复制 provider 业务逻辑；应调用主脚本子命令。

## 子命令职责

所有子命令尊重 `-Provider cliproxy|occ`，默认 `cliproxy`。

- `install`：创建/更新 provider config，必要时下载 exe。
- `login`：CLIProxy 执行 Codex OAuth；OCC 必须报错并提示 API key 方式。
- `configure`：写 provider config，并合并更新 Claude Code `settings.json` 的 env；可显式配置/清理 Claude Code 自动压缩阈值 override。
- `set-proxy-env`：按当前 `ProxyMode` / `ProxyUrl` 写入或清理用户级命令行代理环境变量，不设置 Windows 系统代理或 WinHTTP。
- `start` / `stop` / `restart`：管理 provider 进程；两个后端可在不同端口同时运行。
- `status`：只读状态检查；不得启动、停止、重写配置或切换代理。
- `auth-status`：检查当前 provider 认证状态。
- `verify`：验证 `/v1/models`、`/v1/messages` 和 Claude Code stream-json。
- `doctor`：执行 `status + verify`。
- `project-version` / `project-update`：查看项目版本和安全快进更新；dirty 工作区必须阻断更新。
- `cliproxy-version` / `cliproxy-update`：查看/更新当前 provider 二进制；名称历史遗留，但作用于当前 `-Provider`。
- `models` / `configure-models`：查看/更新 Claude Code 的 Opus/Sonnet/Haiku 模型 env。

## 启停与更新契约

- `Start-Process` 启动 CLIProxyAPI 时必须传 `-config <config.yaml>`，并设置 `WorkingDirectory = $InstallDir`。
- `Start-Process` 启动 oc-go-cc 时必须传 `serve -config <path> --port <port>`，并设置 `WorkingDirectory = $InstallDir`。
- 启动 oc-go-cc 前必须确保 config 中 `pid_file` 的父目录和 `$env:USERPROFILE\.config\oc-go-cc` 存在。
- provider readiness 以 health endpoint 成功响应为准，不只看 TCP 端口监听。
- 端口拥有者判断只使用 `Listen` 且 `OwningProcess > 0` 的 socket，避免误判 Windows `Idle pid=0`。
- `verify` / `doctor` 遇到可恢复的本地代理或 stream-json 探测失败时，可以自动重启当前 provider 一次并重试。
- Claude Code `stream-json` 检查必须有 60 秒 watchdog；超时要终止探测进程并报告 timeout。
- `UpdateBinary` 的下载、替换、恢复逻辑必须整体包在 `try/catch`；失败时若原本有运行服务则重启之。
- Windows PowerShell 5.1 下不要依赖 `Move-Item -Force` 覆盖已存在 exe；替换前备份旧 exe，失败时恢复。

## Watchdog 契约

- CLIProxy 启动后必须同时启动 CodexToClaude watchdog；`stop` 必须关闭 watchdog。
- Watchdog 只处理启动后的新 `/v1/messages` 长请求；默认 180 秒仍未完成时重启当前 CLIProxy provider，降低误杀正常长 reasoning/streaming 请求的概率，同时保留较快恢复。
- Watchdog 不得因快速返回的 5xx 重启 provider，避免切断 Claude Code 流式请求。
- `ProxyMode Auto` 下可在 HTTP/SOCKS5 间切换并记录状态；显式 `Http` / `Socks5` / `Direct` 不得被覆盖。
- Watchdog 子进程运行时读取持久化 proxy mode，不要把启动时的 `ProxyMode` 固化到命令行。
- Watchdog 的 Auto 代理状态写入 `$InstallDir\codextoclaude-state\watchdog-state.json`，不得放在 `auth-dir` 根层；旧版 `$InstallDir\codextoclaude-watchdog-state.json` 只用于迁移读取。

代理、auth JSON 和 settings env 的细节见 `docs/maintenance/proxy-auth.md`。

## 版本与文档同步

- `VERSION` 是项目版本单一真源。
- 每次有意义提交（功能、修复、重构）前递增 build 号。
- 修改与版本相关的代码后，同步 README 徽章和文档示例中的版本号。
- 用户入口变化先改 README；CLI/GUI 行为变化同步维护文档。
- 不要把 `docs/claude-code-setup.md` 和 `docs/手动安装与使用.md` 写成重复教程：前者给自动化安装，后者给纯手动用户。

## 测试矩阵

修改脚本后必跑：

```powershell
.\test\Test-CodexToClaude.ps1
```

涉及真实服务管理后补跑：

```powershell
.\scripts\CodexToClaude.ps1 status
.\scripts\CodexToClaude.ps1 restart
.\scripts\CodexToClaude.ps1 verify
```

按改动范围增加检查：

| 改动 | 额外验证 |
|---|---|
| 代理逻辑 | `Auto host:port -> http://...`、`Socks5 -> socks5://...`、`Direct` 省略代理并清理 CLIProxy auth `proxy_url`；命令行 env 只写 User 作用域并保留既有 `NO_PROXY` |
| GUI | UI 脚本可解析、`CodexToClaude-GUI.cmd` 存在、中英文切换、快速向导关键路径；命令输出增量读取且先脱敏；自动压缩 GUI k tokens 输入需转换为 CLI raw tokens |
| auth/status | 不输出 token；CLIProxy 只扫描 `$InstallDir` 根目录 JSON；OCC 检查 API key 来源 |
| settings 合并 | 只更新目标 env 键，保留 `statusLine`、`permissions`、`language` 等字段；自动压缩 Unset/未传不触碰，Enabled 写入两个 env，Disabled 删除两个 env |
| update 逻辑 | 停服、备份、替换、恢复启动；dirty 工作区阻断 project update |

提交前检查：

```powershell
git status
git diff
```

确认没有 OAuth JSON、token、真实 API key 或原始日志。

## PowerShell gotchas

- 顶层代码必须在函数定义之后调用函数；PowerShell 不在解析阶段提升函数定义。
- 函数内部可以调用脚本中任何位置定义的其它函数，因为函数体延迟执行。
- .NET 属性赋值会向管线输出对象；GUI 函数中用 `[void]($obj.Prop = ...)` 或 `$null = ...` 包裹。
- 调用外部程序后必须检查 `$LASTEXITCODE`；`try/catch` 不捕获外部 exe 的非零退出码。
- 临时修改进程级环境变量时，保存原值并在 `try/finally` 中恢复。
- 函数体内不要把 `$args` 当局部变量名；它是 PowerShell 自动变量。

## 常见迭代入口

- 改模型默认值：主脚本参数、GUI 默认/偏好、README 示例、手动安装文档一起检查。
- 改登录诊断：优先改 provider 的 auth status，再让 GUI 复用 `auth-status -Json`。
- 改 GUI 文案或向导：先读 `docs/maintenance/gui.md`。
- 改代理、settings 或认证：先读 `docs/maintenance/proxy-auth.md`。
- 改启动、更新或 watchdog：读本文件的生命周期契约，并根据涉及范围跑真实服务验证。
