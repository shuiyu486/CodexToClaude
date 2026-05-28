# GUI 维护专题

本文件只记录 GUI 相关维护规则。跨领域架构、启停、版本和测试策略见 `../project-guide.md`。

## 边界

- GUI 脚本：`scripts/CodexToClaude.UI.ps1`。
- 双击入口：`CodexToClaude-GUI.cmd`。
- GUI 是 WinForms wrapper：只收集参数、展示状态、编排步骤并调用 `scripts/CodexToClaude.ps1`。
- 不在 GUI 中复制安装、登录、配置、启停、认证解析、git 更新、下载替换 exe 或写 settings 的业务逻辑。

## Provider 切换

- GUI 后端切换器显示 `Codex` / `OpenCode Go`。
- 切换 provider 时必须先保存当前后端输入值，再恢复新后端输入值。
- 切换后重置向导状态和布局。
- 两个后端的端口、安装目录、模型值独立保存。
- 代理地址当前是全局共享值，不按 provider 分开保存。

## 首次向导

快速开始向导顺序：

```text
Install -> Login -> Configure -> Restart -> Verify
```

- 每一步都调用 CLI 子命令。
- OCC 后端隐藏 Login 步骤，改用 API key 字段或 `${OC_GO_CC_API_KEY}`。
- 高级/诊断命令与主流程分区展示，避免退化为一排按钮墙。
- 版本管理在高级管理窗口；模型配置在主界面。

## 参数与代理输入

- `Install` / `Configure` 必须要求 `Port` 和代理选择。
- `ProxyMode` 支持 `Auto`、`Http`、`Socks5`、`Direct`。
- `Auto` / `Http` / `Socks5` 必须要求代理地址非空。
- `Direct` 模式应禁用或忽略代理地址输入。
- 代理、认证和 settings 合并细节见 `proxy-auth.md`。

## 语言与文案

- 用户可见文案集中在 `$I18N` 表。
- 新增用户可见文案必须同步 `zh-CN` 和 `en-US`。
- 界面文本通过稳定 key 绑定控件；不要把新文案散落在事件处理器里。
- 修改 GUI 文案或向导顺序时，同步 README 用户说明和 `docs/project-guide.md` 维护约定。

## 偏好文件

GUI 偏好文件保存到：

```text
~/.codextoclaude/ui-preferences.json
```

规则：

- 当前 schema 为 v2。
- 保存语言、首次向导完成状态、选中的后端和普通输入值。
- 保存 `proxyMode` 和 `proxyUrl`。
- 不保存 token、OAuth JSON、真实 API key 或日志内容。
- 每个 provider 的端口、安装目录、模型值独立存储。

## 命令输出与诊断

- GUI 执行 CLI 命令时，进程运行期间必须增量显示 stdout/stderr。
- GUI 不得通过 `cmd.exe /c` 拼接用户输入；应通过临时 wrapper 或等价的安全参数传递方式调用 CLI，避免命令注入和命令行泄露 API key。
- 临时 wrapper 调用 `scripts/CodexToClaude.ps1` 时必须使用 hashtable splatting（`@params`）传递脚本参数；不要用字符串数组 splatting 传 `-Provider` 等命名参数，Windows PowerShell 5.1 会把它们当作位置参数。
- 设备码登录会等待用户授权，不能等进程退出后才读取输出。
- GUI 启动和登录后都要刷新 Login status。
- 登录状态以 `auth-status -Json` 为唯一真源。
- 日志框必须随主窗口横向和纵向拉伸，保留换行和长行横向滚动。
- 输出日志片段前必须脱敏，不能包含 OAuth token、API key、bearer token 或完整 auth JSON；所有增量 stdout/stderr 都必须经过统一日志入口。

## PowerShell/WinForms gotchas

- .NET 属性赋值会向管线输出对象，必须用 `[void]()` 或 `$null =` 包裹。
- 尤其注意 `Apply-Language`、`Update-ProviderButtons`、`Switch-Provider`、`Set-WizardStepState`。
- 不要在顶层代码调用尚未定义的函数；顶层代码应位于函数定义之后。

示例：

```powershell
[void]($btn.Text = "Update")
[void]($label.ForeColor = [System.Drawing.Color]::ForestGreen)
```

## GUI 验收清单

GUI 修改后至少确认：

- `scripts/CodexToClaude.UI.ps1` 可被 PowerShell parser 解析。
- `CodexToClaude-GUI.cmd` 存在。
- 中英文切换后主要标签、按钮和弹窗文案可读。
- 快速向导仍按 `Install -> Login -> Configure -> Restart -> Verify` 调用 CLI。
- OCC 后端隐藏 Login 步骤并保留 API key 输入路径。
- 高级管理按钮只调用 CLI 子命令，不直接执行 git、下载、替换 exe 或写 settings。
- 诊断工具中的命令行代理环境变量按钮只调用 CLI `set-proxy-env`；不得在 GUI 中直接写环境变量。
