# CodexToClaude

> 使Codex Plus/Pro订阅可以在claude code中使用

CodexToClaude 是一个 Windows 优先的小工具。它通过 CLIProxyAPI 把你的 Codex Plus/Pro OAuth 登录转换成本机 Anthropic-compatible API，让 Claude Code 可以访问本机接口并使用 Codex 模型。

```text
Claude Code → http://127.0.0.1:<Port> → CLIProxyAPI → Codex OAuth → Codex models
```

## 适合谁

- 已经有 Codex Plus/Pro 订阅。
- 想在 Claude Code 中使用 Codex 模型。
- 希望少手动改配置，最好有 GUI 一键操作。
- 使用 Windows，或者至少能运行 PowerShell。

## 你需要先知道两个值

安装和测试前必须明确：

| 名称 | 说明 | 示例 |
|---|---|---|
| `Port` | CLIProxyAPI 在本机监听的端口，Claude Code 会访问 `http://127.0.0.1:<Port>` | `8317` |
| `ProxyUrl` | CLIProxyAPI 访问 Codex/OpenAI 上游时使用的代理 | `http://127.0.0.1:7897` |

如果你的网络可以直连上游，请把 `ProxyUrl` 显式填为：

```text
none
```

不要留空。留空会让安装后的验证结果不明确。

## 推荐方式：使用 GUI

双击：

```text
CodexToClaude-GUI.cmd
```

GUI 中按顺序操作：

1. 填写 `Port`，例如 `8317`。
2. 填写 `ProxyUrl`，例如 `http://127.0.0.1:7897`；直连填 `none`。
3. 点击 `Install`。
4. 点击 `Login`。
   - 如果普通登录不方便，勾选 `Use device login` 后再点 `Login`。
5. 确认顶部 `Login status` 显示已登录。
6. 点击 `Configure`。
7. 点击 `Restart`。
8. 点击 `Verify`。

GUI 会显示当前登录状态，并在登录失败时给出排障建议。

## CLI 用法

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
.\scripts\CodexToClaude.ps1 configure -Port 8317 -ProxyUrl none
```

常用检查：

```powershell
.\scripts\CodexToClaude.ps1 status
.\scripts\CodexToClaude.ps1 auth-status
.\scripts\CodexToClaude.ps1 doctor
```

## Login 状态说明

`Login` 完成后，程序会检查 `~/.cli-proxy-api` 根目录下的 OAuth JSON：

- 是否存在 auth JSON。
- 是否为 `type=codex`。
- 是否没有 `disabled=true`。
- 是否能识别邮箱和过期时间。

不会打印 `access_token`、`refresh_token`、`id_token`。

如果登录失败，优先尝试：

1. 确认代理可用，并重新运行 `install/configure -ProxyUrl ...`。
2. 改用设备码登录：`.\scripts\CodexToClaude.ps1 login -Device`。
3. 确认 OAuth JSON 位于 `~/.cli-proxy-api` 根目录，不在嵌套子目录。
4. 确认 JSON 中 `type` 为 `codex`，且没有 `disabled: true`。
5. 查看 `~/.cli-proxy-api/logs/main.log`。

## 它会改哪些文件

| 文件 | 用途 |
|---|---|
| `~/.cli-proxy-api/config.yaml` | CLIProxyAPI 运行配置 |
| `~/.cli-proxy-api/cli-proxy-api.exe` | CLIProxyAPI 可执行文件 |
| `~/.cli-proxy-api/codex-*.json` | Codex OAuth 登录文件 |
| `~/.claude/settings.json` | Claude Code 访问本机代理的配置 |

`settings.json` 会被合并更新，只替换 Claude Code 使用本地代理所需的 `env` 字段，不会覆盖 `statusLine`、`permissions` 等其它配置。

## 关于 thinking 输出

CodexToClaude 默认在 CLIProxyAPI config 中写入：

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

原因是 Claude Code TUI 在显示 Codex thinking 流时，中文片段可能出现重复字符。过滤 reasoning 后，正常回答文本不受影响。

## 安全说明

不要提交：

- Codex OAuth JSON。
- `access_token`、`refresh_token`、`id_token`。
- 真实 API key。
- 日志文件。

仓库 `.gitignore` 已排除常见敏感文件，但提交前仍应检查：

```powershell
git status
git diff
```

## 开发与维护

运行测试：

```powershell
.\test\Test-CodexToClaude.ps1
```

真实环境验收：

```powershell
.\scripts\CodexToClaude.ps1 restart
.\scripts\CodexToClaude.ps1 verify
```

详细项目维护说明见：

```text
docs/project-guide.md
```
