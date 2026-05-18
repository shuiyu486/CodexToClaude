[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptPath = Join-Path $PSScriptRoot 'CodexToClaude.ps1'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$VersionPath = Join-Path $RepoRoot 'VERSION'
$DefaultInstallDir = Join-Path $RepoRoot 'cli-proxy-api'
$DefaultSettingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
$PrefsDir = Join-Path $env:USERPROFILE '.codextoclaude'
$PrefsPath = Join-Path $PrefsDir 'ui-preferences.json'
$script:CurrentLanguage = 'en-US'
$script:WizardCompleted = $false
$script:WizardStepLabels = @{}
$script:TextBindings = @()
$script:ApplyingLanguage = $false

$I18N = @{
    'en-US' = @{
        'app.title' = 'CodexToClaude'
        'app.subtitle' = 'Use Codex Plus/Pro in Claude Code'
        'language.label' = 'Language'
        'language.zh' = '中文'
        'language.en' = 'English'
        'status.checking' = 'Login status: checking...'
        'status.prefix' = 'Login status: '
        'status.unable' = 'Login status: unable to read auth status'
        'status.failed' = 'Login status: auth check failed'
        'settings.title' = 'Connection settings'
        'field.port' = 'Port'
        'field.proxy' = 'ProxyUrl'
        'field.apiKey' = 'ApiKey'
        'field.installDir' = 'InstallDir'
        'field.settings' = 'Claude settings'
        'hint.port' = 'Local CLIProxyAPI listen port. Claude Code uses http://127.0.0.1:<Port>. Example: 8317.'
        'hint.proxy' = 'Upstream proxy for Codex/OpenAI. Use http://127.0.0.1:7897, or type none for direct access.'
        'check.device' = 'Use device login'
        'check.skipStream' = 'Skip Claude stream check'
        'wizard.title' = 'Quick start wizard'
        'wizard.description' = 'Follow these steps for first-time setup. Each step calls the same CLI command shown in the log.'
        'wizard.completed' = 'Quick start wizard - completed'
        'wizard.step.install' = '1. Install CLIProxyAPI config'
        'wizard.step.login' = '2. Login to Codex'
        'wizard.step.configure' = '3. Configure Claude Code'
        'wizard.step.restart' = '4. Restart local service'
        'wizard.step.verify' = '5. Verify end-to-end'
        'wizard.run' = 'Run'
        'wizard.pending' = 'Pending'
        'wizard.running' = 'Running'
        'wizard.done' = 'Done'
        'wizard.failed' = 'Failed'
        'wizard.finishLog' = 'Quick start completed. Future launches will remember this.'
        'main.title' = 'Main flow'
        'advanced.title' = 'Advanced and diagnostics'
        'version.title' = 'Version management'
        'models.title' = 'Claude models'
        'log.title' = 'Log'
        'btn.install' = 'Install'
        'btn.login' = 'Login'
        'btn.configure' = 'Configure'
        'btn.restart' = 'Restart'
        'btn.verify' = 'Verify'
        'btn.start' = 'Start'
        'btn.stop' = 'Stop'
        'btn.status' = 'Status'
        'btn.doctor' = 'Doctor'
        'btn.refresh' = 'Refresh Login Status'
        'btn.openInstall' = 'Open Install Dir'
        'btn.openSettings' = 'Open Settings Dir'
        'btn.projectVersion' = 'Project Version'
        'btn.projectUpdate' = 'Update Project'
        'btn.proxyVersion' = 'CLIProxyAPI Version'
        'btn.proxyUpdate' = 'Update CLIProxyAPI'
        'btn.models' = 'Read Models'
        'btn.configureModels' = 'Save Models'
        'btn.advancedManagement' = 'Advanced Management'
        'btn.diagnostics' = 'Diagnostics'
        'field.opusModel' = 'Opus model'
        'field.sonnetModel' = 'Sonnet model'
        'field.haikuModel' = 'Haiku model'
        'dialog.invalidPortTitle' = 'Invalid Port'
        'dialog.invalidPortNumber' = 'Port must be a number, for example 8317.'
        'dialog.invalidPortRange' = 'Port must be in range 1-65535.'
        'dialog.proxyRequiredTitle' = 'ProxyUrl Required'
        'dialog.proxyRequired' = 'ProxyUrl is required. Use none if direct access works.'
        'dialog.invalidProxyTitle' = 'Invalid ProxyUrl'
        'dialog.invalidProxy' = 'ProxyUrl must start with http://, https://, socks5://, or be none/direct.'
        'log.settingsFallback' = 'Settings load failed; using defaults.'
        'log.loginHelp' = 'Login troubleshooting:'
        'log.loginHelp1' = '1. Check proxy, then rerun install/configure with the correct ProxyUrl.'
        'log.loginHelp2' = '2. Try Device Login.'
        'log.loginHelp3' = '3. Make sure Codex OAuth JSON is in the cli-proxy-api folder (inside the CodexToClaude project).'
        'log.loginHelp4' = '4. Make sure JSON has type=codex and disabled is not true.'
        'log.loginHelp5' = '5. Check the cli-proxy-api/logs/main.log file in the CodexToClaude project.'
    }
    'zh-CN' = @{
        'app.title' = 'CodexToClaude'
        'app.subtitle' = '在 Claude Code 中使用 Codex Plus/Pro'
        'language.label' = '界面语言'
        'language.zh' = '中文'
        'language.en' = 'English'
        'status.checking' = '登录状态：检查中...'
        'status.prefix' = '登录状态：'
        'status.unable' = '登录状态：无法读取认证状态'
        'status.failed' = '登录状态：认证检查失败'
        'settings.title' = '连接设置'
        'field.port' = '端口'
        'field.proxy' = '代理地址'
        'field.apiKey' = 'API Key'
        'field.installDir' = '安装目录'
        'field.settings' = 'Claude 配置'
        'hint.port' = 'CLIProxyAPI 本机监听端口。Claude Code 会访问 http://127.0.0.1:<Port>。示例：8317。'
        'hint.proxy' = 'CLIProxyAPI 访问 Codex/OpenAI 上游使用的代理。示例：http://127.0.0.1:7897；直连填 none。'
        'check.device' = '使用设备码登录'
        'check.skipStream' = '跳过 Claude stream 检查'
        'wizard.title' = '快速开始向导'
        'wizard.description' = '首次使用按顺序执行这些步骤。每一步都会调用日志中显示的同一个 CLI 命令。'
        'wizard.completed' = '快速开始向导 - 已完成'
        'wizard.step.install' = '1. 安装 CLIProxyAPI 配置'
        'wizard.step.login' = '2. 登录 Codex'
        'wizard.step.configure' = '3. 配置 Claude Code'
        'wizard.step.restart' = '4. 重启本地服务'
        'wizard.step.verify' = '5. 端到端验证'
        'wizard.run' = '执行'
        'wizard.pending' = '待执行'
        'wizard.running' = '执行中'
        'wizard.done' = '已完成'
        'wizard.failed' = '失败'
        'wizard.finishLog' = '快速开始已完成，后续启动会记住此状态。'
        'main.title' = '主流程'
        'advanced.title' = '高级与诊断'
        'version.title' = '版本管理'
        'models.title' = 'Claude 模型'
        'log.title' = '日志'
        'btn.install' = '安装'
        'btn.login' = '登录'
        'btn.configure' = '配置'
        'btn.restart' = '重启'
        'btn.verify' = '验证'
        'btn.start' = '启动'
        'btn.stop' = '停止'
        'btn.status' = '状态'
        'btn.doctor' = '诊断'
        'btn.refresh' = '刷新登录状态'
        'btn.openInstall' = '打开安装目录'
        'btn.openSettings' = '打开配置目录'
        'btn.projectVersion' = '项目版本'
        'btn.projectUpdate' = '更新项目'
        'btn.proxyVersion' = 'CLIProxyAPI 版本'
        'btn.proxyUpdate' = '更新 CLIProxyAPI'
        'btn.models' = '读取模型'
        'btn.configureModels' = '保存模型'
        'btn.advancedManagement' = '高级管理'
        'btn.diagnostics' = '诊断工具'
        'field.opusModel' = 'Opus 模型'
        'field.sonnetModel' = 'Sonnet 模型'
        'field.haikuModel' = 'Haiku 模型'
        'dialog.invalidPortTitle' = '端口无效'
        'dialog.invalidPortNumber' = '端口必须是数字，例如 8317。'
        'dialog.invalidPortRange' = '端口范围必须是 1-65535。'
        'dialog.proxyRequiredTitle' = '需要代理地址'
        'dialog.proxyRequired' = 'ProxyUrl 必须填写；如果可以直连，请填 none。'
        'dialog.invalidProxyTitle' = '代理地址无效'
        'dialog.invalidProxy' = 'ProxyUrl 必须以 http://、https://、socks5:// 开头，或填写 none/direct。'
        'log.settingsFallback' = '偏好设置读取失败，已使用默认值。'
        'log.loginHelp' = '登录排障建议：'
        'log.loginHelp1' = '1. 检查代理，然后使用正确的 ProxyUrl 重新运行 install/configure。'
        'log.loginHelp2' = '2. 尝试设备码登录。'
        'log.loginHelp3' = '3. 确认 Codex OAuth JSON 位于 CodexToClaude 项目内的 cli-proxy-api 目录。'
        'log.loginHelp4' = '4. 确认 JSON 中 type=codex 且 disabled 不是 true。'
        'log.loginHelp5' = '5. 查看 CodexToClaude 项目内 cli-proxy-api/logs/main.log 日志。'
    }
}

$WizardSteps = @(
    @{ Id = 'install'; TextKey = 'wizard.step.install'; Command = 'install'; NeedPortProxy = $true },
    @{ Id = 'login'; TextKey = 'wizard.step.login'; Command = 'login'; NeedPortProxy = $false },
    @{ Id = 'configure'; TextKey = 'wizard.step.configure'; Command = 'configure'; NeedPortProxy = $true },
    @{ Id = 'restart'; TextKey = 'wizard.step.restart'; Command = 'restart'; NeedPortProxy = $false },
    @{ Id = 'verify'; TextKey = 'wizard.step.verify'; Command = 'verify'; NeedPortProxy = $false }
)

function Get-DefaultLanguage {
    $culture = [System.Globalization.CultureInfo]::CurrentUICulture.Name
    if ($culture -like 'zh*') { return 'zh-CN' }
    return 'en-US'
}

function Get-ProjectVersion {
    if (-not (Test-Path $VersionPath)) { return 'v0.0.0.0' }
    $version = (Get-Content $VersionPath -Raw -Encoding UTF8).Trim()
    if ($version -notmatch '^v\d+\.\d+\.\d+\.\d+$') { return 'v0.0.0.0' }
    return $version
}

function New-DefaultPreferences {
    return @{
        schemaVersion = 1
        language = Get-DefaultLanguage
        firstRunCompleted = $false
        lastValues = @{
            port = '8317'
            proxyUrl = 'http://127.0.0.1:7897'
            apiKey = ''
            installDir = $DefaultInstallDir
            claudeSettingsPath = $DefaultSettingsPath
            opusModel = 'gpt-5.5'
            sonnetModel = 'gpt-5.4'
            haikuModel = 'gpt-5.4'
            useDeviceLogin = $false
            skipStreamCheck = $false
        }
    }
}

function Get-ObjectProperty([object]$Object, [string]$Name, [object]$Fallback) {
    if ($null -eq $Object) { return $Fallback }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Fallback
}

function Load-UiPreferences {
    $defaults = New-DefaultPreferences
    if (-not (Test-Path $PrefsPath)) { return $defaults }
    try {
        $raw = Get-Content $PrefsPath -Raw -Encoding UTF8
        $loaded = $raw | ConvertFrom-Json
        $last = Get-ObjectProperty $loaded 'lastValues' $null
        $defaults.language = Get-ObjectProperty $loaded 'language' $defaults.language
        if ($defaults.language -notin @('zh-CN', 'en-US')) { $defaults.language = Get-DefaultLanguage }
        $defaults.firstRunCompleted = [bool](Get-ObjectProperty $loaded 'firstRunCompleted' $defaults.firstRunCompleted)
        $defaults.lastValues.port = [string](Get-ObjectProperty $last 'port' $defaults.lastValues.port)
        $defaults.lastValues.proxyUrl = [string](Get-ObjectProperty $last 'proxyUrl' $defaults.lastValues.proxyUrl)
        $defaults.lastValues.installDir = [string](Get-ObjectProperty $last 'installDir' $defaults.lastValues.installDir)
        $defaults.lastValues.claudeSettingsPath = [string](Get-ObjectProperty $last 'claudeSettingsPath' $defaults.lastValues.claudeSettingsPath)
        $defaults.lastValues.opusModel = [string](Get-ObjectProperty $last 'opusModel' $defaults.lastValues.opusModel)
        $defaults.lastValues.sonnetModel = [string](Get-ObjectProperty $last 'sonnetModel' $defaults.lastValues.sonnetModel)
        $defaults.lastValues.haikuModel = [string](Get-ObjectProperty $last 'haikuModel' $defaults.lastValues.haikuModel)
        $defaults.lastValues.useDeviceLogin = [bool](Get-ObjectProperty $last 'useDeviceLogin' $defaults.lastValues.useDeviceLogin)
        $defaults.lastValues.skipStreamCheck = [bool](Get-ObjectProperty $last 'skipStreamCheck' $defaults.lastValues.skipStreamCheck)
        if ($defaults.lastValues.installDir -match '^[A-Za-z]:\\Users\\Demo\\') { $defaults.lastValues.installDir = $DefaultInstallDir }
        if ($defaults.lastValues.installDir -eq (Join-Path $env:USERPROFILE '.cli-proxy-api')) { $defaults.lastValues.installDir = $DefaultInstallDir }
        if ($defaults.lastValues.claudeSettingsPath -match '^[A-Za-z]:\\Users\\Demo\\') { $defaults.lastValues.claudeSettingsPath = $DefaultSettingsPath }
        return $defaults
    } catch {
        $defaults.settingsLoadFailed = $true
        return $defaults
    }
}

function Save-UiPreferences {
    if (-not (Test-Path $PrefsDir)) { New-Item -ItemType Directory -Force $PrefsDir | Out-Null }
    $script:Prefs.language = $script:CurrentLanguage
    $script:Prefs.firstRunCompleted = $script:WizardCompleted
    $script:Prefs.lastValues.port = $portBox.Text.Trim()
    $script:Prefs.lastValues.proxyUrl = $proxyBox.Text.Trim()
    $script:Prefs.lastValues.apiKey = ''
    $script:Prefs.lastValues.installDir = $installDirBox.Text.Trim()
    $script:Prefs.lastValues.claudeSettingsPath = $settingsPathBox.Text.Trim()
    $script:Prefs.lastValues.opusModel = $opusModelBox.Text.Trim()
    $script:Prefs.lastValues.sonnetModel = $sonnetModelBox.Text.Trim()
    $script:Prefs.lastValues.haikuModel = $haikuModelBox.Text.Trim()
    $script:Prefs.lastValues.useDeviceLogin = [bool]$deviceCheck.Checked
    $script:Prefs.lastValues.skipStreamCheck = [bool]$skipStreamCheck.Checked
    $json = $script:Prefs | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($PrefsPath, $json + "`n", [System.Text.Encoding]::UTF8)
}

function T([string]$Key) {
    $langTable = $I18N[$script:CurrentLanguage]
    if ($langTable -and $langTable.ContainsKey($Key)) { return $langTable[$Key] }
    $fallback = $I18N['en-US']
    if ($fallback.ContainsKey($Key)) { return $fallback[$Key] }
    return $Key
}

function Register-Text([object]$Control, [string]$Key) {
    $script:TextBindings += [pscustomobject]@{ Control = $Control; Key = $Key }
}

function Apply-Language {
    $script:ApplyingLanguage = $true
    try {
        foreach ($binding in $script:TextBindings) {
            $binding.Control.Text = T $binding.Key
        }
        $versionTitle = "$(T 'app.title') $(Get-ProjectVersion)"
        $form.Text = $versionTitle
        $title.Text = $versionTitle
        $zhItem = T 'language.zh'
        $enItem = T 'language.en'
        $languageBox.Items.Clear()
        [void]$languageBox.Items.Add($zhItem)
        [void]$languageBox.Items.Add($enItem)
        if ($script:CurrentLanguage -eq 'zh-CN') { $languageBox.SelectedItem = $zhItem } else { $languageBox.SelectedItem = $enItem }
        Update-WizardTitle
        foreach ($step in $WizardSteps) {
            if ($script:WizardStepLabels.ContainsKey($step.Id)) {
                $script:WizardStepLabels[$step.Id].Tag = T $step.TextKey
            }
            Set-WizardStepState $step.Id 'pending'
        }
    } finally {
        $script:ApplyingLanguage = $false
    }
}

function New-Label([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($W, $H)
    return $label
}

function New-TextBox([string]$Text, [int]$X, [int]$Y, [int]$W) {
    $box = New-Object System.Windows.Forms.TextBox
    $box.Text = $Text
    $box.Location = New-Object System.Drawing.Point($X, $Y)
    $box.Size = New-Object System.Drawing.Size($W, 24)
    return $box
}

function New-Button([string]$Text, [int]$X, [int]$Y, [int]$W) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($W, 34)
    return $button
}

function Append-Log([string]$Text) {
    $logBox.AppendText($Text + [Environment]::NewLine)
    $logBox.SelectionStart = $logBox.Text.Length
    $logBox.ScrollToCaret()
}

function Show-Message([string]$MessageKey, [string]$TitleKey) {
    [System.Windows.Forms.MessageBox]::Show((T $MessageKey), (T $TitleKey)) | Out-Null
}

function Validate-Inputs([bool]$RequireProxy) {
    if ($portBox.Text.Trim() -notmatch '^\d+$') {
        Show-Message 'dialog.invalidPortNumber' 'dialog.invalidPortTitle'
        return $false
    }
    $p = [int]$portBox.Text.Trim()
    if ($p -lt 1 -or $p -gt 65535) {
        Show-Message 'dialog.invalidPortRange' 'dialog.invalidPortTitle'
        return $false
    }
    if ($RequireProxy) {
        $proxy = $proxyBox.Text.Trim()
        if ($proxy -eq '') {
            Show-Message 'dialog.proxyRequired' 'dialog.proxyRequiredTitle'
            return $false
        }
        if ($proxy -notin @('none', 'direct') -and $proxy -notmatch '^(http|https|socks5)://') {
            Show-Message 'dialog.invalidProxy' 'dialog.invalidProxyTitle'
            return $false
        }
    }
    return $true
}

function Build-Args([string]$Command, [bool]$NeedPortProxy) {
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath, $Command)
    if ($NeedPortProxy -or $portBox.Text.Trim() -ne '') { $args += @('-Port', $portBox.Text.Trim()) }
    if ($NeedPortProxy -or $proxyBox.Text.Trim() -ne '') { $args += @('-ProxyUrl', $proxyBox.Text.Trim()) }
    if ($apiKeyBox.Text.Trim() -ne '') { $args += @('-ApiKey', $apiKeyBox.Text.Trim()) }
    if ($installDirBox.Text.Trim() -ne '') { $args += @('-InstallDir', $installDirBox.Text.Trim()) }
    if ($settingsPathBox.Text.Trim() -ne '') { $args += @('-ClaudeSettingsPath', $settingsPathBox.Text.Trim()) }
    if ($opusModelBox.Text.Trim() -ne '') { $args += @('-OpusModel', $opusModelBox.Text.Trim()) }
    if ($sonnetModelBox.Text.Trim() -ne '') { $args += @('-SonnetModel', $sonnetModelBox.Text.Trim()) }
    if ($haikuModelBox.Text.Trim() -ne '') { $args += @('-HaikuModel', $haikuModelBox.Text.Trim()) }
    if ($deviceCheck.Checked -and $Command -eq 'login') { $args += '-Device' }
    if ($skipStreamCheck.Checked) { $args += '-SkipClaudeStreamCheck' }
    return $args
}

function Build-WrapperScript {
    $wrapperPath = Join-Path $env:TEMP "ctc-wrap-$([guid]::NewGuid().ToString()).ps1"
    $content = @"
`$ErrorActionPreference = 'Stop'
& '$ScriptPath' @args *>&1
"@
    [System.IO.File]::WriteAllText($wrapperPath, $content, [System.Text.Encoding]::UTF8)
    return $wrapperPath
}

function Run-Command([string]$Command, [bool]$NeedPortProxy) {
    if ($NeedPortProxy -and -not (Validate-Inputs $true)) { return $false }
    if ((@('start','stop','restart','status','verify','doctor') -contains $Command) -and -not (Validate-Inputs $false)) { return $false }
    Save-UiPreferences
    Append-Log ""
    Append-Log "> $Command"
    $stdout = Join-Path $env:TEMP "ctc-ui-stdout-$([guid]::NewGuid().ToString()).txt"
    $wrapperPath = $null
    try {
        $cliFullArgs = Build-Args $Command $NeedPortProxy
        $wrapperPath = Build-WrapperScript
        $scriptIdx = [array]::IndexOf($cliFullArgs, $ScriptPath)
        $cliOnly = if ($scriptIdx -ge 0) { $cliFullArgs[($scriptIdx + 1)..($cliFullArgs.Count - 1)] } else { @() }
        $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $wrapperPath) + $cliOnly
        $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs -PassThru -NoNewWindow -RedirectStandardOutput $stdout
        while (-not $proc.HasExited) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 200
        }
        if (Test-Path $stdout) {
            $out = Get-Content $stdout -Raw -ErrorAction SilentlyContinue
            if ($out) { Append-Log $out.TrimEnd() }
        }
        Append-Log "ExitCode: $($proc.ExitCode)"
        if ($Command -eq 'login' -or $Command -eq 'install' -or $Command -eq 'configure') { Refresh-AuthStatus }
        return ($proc.ExitCode -eq 0)
    } catch {
        Append-Log "ERROR: $($_.Exception.Message)"
        if ($Command -eq 'login') { Append-LoginHelp }
        return $false
    } finally {
        Remove-Item $stdout -Force -ErrorAction SilentlyContinue
        if ($wrapperPath) { Remove-Item $wrapperPath -Force -ErrorAction SilentlyContinue }
    }
}

function Append-LoginHelp {
    Append-Log (T 'log.loginHelp')
    Append-Log (T 'log.loginHelp1')
    Append-Log (T 'log.loginHelp2')
    Append-Log (T 'log.loginHelp3')
    Append-Log (T 'log.loginHelp4')
    Append-Log (T 'log.loginHelp5')
}

function Refresh-AuthStatus {
    $stdout = Join-Path $env:TEMP "ctc-ui-auth-$([guid]::NewGuid().ToString()).json"
    $stderr = Join-Path $env:TEMP "ctc-ui-auth-$([guid]::NewGuid().ToString()).err"
    try {
        $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath, 'auth-status', '-Json')
        if ($installDirBox.Text.Trim() -ne '') { $args += @('-InstallDir', $installDirBox.Text.Trim()) }
        $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $raw = ''
        if (Test-Path $stdout) { $raw = Get-Content $stdout -Raw -ErrorAction SilentlyContinue }
        if ($raw) {
            $status = $raw | ConvertFrom-Json
            $loginStatusLabel.Text = (T 'status.prefix') + $status.message
            if ($status.status -eq 'logged_in') { $loginStatusLabel.ForeColor = [System.Drawing.Color]::ForestGreen }
            else { $loginStatusLabel.ForeColor = [System.Drawing.Color]::DarkOrange }
        } else {
            $loginStatusLabel.Text = T 'status.unable'
            $loginStatusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
        }
    } catch {
        $loginStatusLabel.Text = T 'status.failed'
        $loginStatusLabel.ForeColor = [System.Drawing.Color]::DarkRed
    } finally {
        Remove-Item $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Update-WizardTitle {
    if ($script:WizardCompleted) { $wizardGroup.Text = T 'wizard.completed' } else { $wizardGroup.Text = T 'wizard.title' }
}

function Set-WizardStepState([string]$StepId, [string]$State) {
    if (-not $script:WizardStepLabels.ContainsKey($StepId)) { return }
    $label = $script:WizardStepLabels[$StepId]
    $stateText = T "wizard.$State"
    $label.Text = "$($label.Tag)  [$stateText]"
    if ($State -eq 'done') { $label.ForeColor = [System.Drawing.Color]::ForestGreen }
    elseif ($State -eq 'failed') { $label.ForeColor = [System.Drawing.Color]::DarkRed }
    elseif ($State -eq 'running') { $label.ForeColor = [System.Drawing.Color]::RoyalBlue }
    else { $label.ForeColor = [System.Drawing.Color]::DimGray }
}

function Invoke-WizardStep([hashtable]$Step) {
    Set-WizardStepState $Step.Id 'running'
    $ok = Run-Command $Step.Command ([bool]$Step.NeedPortProxy)
    if ($ok) {
        Set-WizardStepState $Step.Id 'done'
        if ($Step.Id -eq 'verify') {
            $script:WizardCompleted = $true
            Save-UiPreferences
            Update-WizardTitle
            Append-Log (T 'wizard.finishLog')
        }
    } else {
        Set-WizardStepState $Step.Id 'failed'
    }
}

function Show-AdvancedManagementWindow {
    $advancedForm = New-Object System.Windows.Forms.Form
    $advancedForm.Text = T 'btn.advancedManagement'
    $advancedForm.Size = New-Object System.Drawing.Size(520, 230)
    $advancedForm.StartPosition = 'CenterParent'

    $versionGroup = New-Object System.Windows.Forms.GroupBox
    $versionGroup.Text = T 'version.title'
    $versionGroup.Location = New-Object System.Drawing.Point(16, 16)
    $versionGroup.Size = New-Object System.Drawing.Size(470, 145)
    $advancedForm.Controls.Add($versionGroup)

    $projectVersionBtn = New-Button (T 'btn.projectVersion') 18 34 200
    $projectVersionBtn.Add_Click({ Run-Command 'project-version' $false | Out-Null })
    $versionGroup.Controls.Add($projectVersionBtn)

    $projectUpdateBtn = New-Button (T 'btn.projectUpdate') 238 34 200
    $projectUpdateBtn.Add_Click({ Run-Command 'project-update' $false | Out-Null })
    $versionGroup.Controls.Add($projectUpdateBtn)

    $proxyVersionBtn = New-Button (T 'btn.proxyVersion') 18 84 200
    $proxyVersionBtn.Add_Click({ Run-Command 'cliproxy-version' $false | Out-Null })
    $versionGroup.Controls.Add($proxyVersionBtn)

    $proxyUpdateBtn = New-Button (T 'btn.proxyUpdate') 238 84 200
    $proxyUpdateBtn.Add_Click({ Run-Command 'cliproxy-update' $false | Out-Null })
    $versionGroup.Controls.Add($proxyUpdateBtn)

    [void]$advancedForm.ShowDialog($form)
}

function Show-DiagnosticsWindow {
    $diagForm = New-Object System.Windows.Forms.Form
    $diagForm.Text = T 'btn.diagnostics'
    $diagForm.Size = New-Object System.Drawing.Size(560, 310)
    $diagForm.StartPosition = 'CenterParent'

    $diagGroup = New-Object System.Windows.Forms.GroupBox
    $diagGroup.Text = T 'advanced.title'
    $diagGroup.Location = New-Object System.Drawing.Point(16, 16)
    $diagGroup.Size = New-Object System.Drawing.Size(510, 210)
    $diagForm.Controls.Add($diagGroup)

    $startBtn = New-Button (T 'btn.start') 18 34 105
    $startBtn.Add_Click({ Run-Command 'start' $false | Out-Null })
    $diagGroup.Controls.Add($startBtn)

    $stopBtn = New-Button (T 'btn.stop') 138 34 105
    $stopBtn.Add_Click({ Run-Command 'stop' $false | Out-Null })
    $diagGroup.Controls.Add($stopBtn)

    $statusBtn = New-Button (T 'btn.status') 258 34 105
    $statusBtn.Add_Click({ Run-Command 'status' $false | Out-Null })
    $diagGroup.Controls.Add($statusBtn)

    $doctorBtn = New-Button (T 'btn.doctor') 378 34 105
    $doctorBtn.Add_Click({ Run-Command 'doctor' $false | Out-Null })
    $diagGroup.Controls.Add($doctorBtn)

    $refreshBtn = New-Button (T 'btn.refresh') 18 88 225
    $refreshBtn.Add_Click({ Refresh-AuthStatus })
    $diagGroup.Controls.Add($refreshBtn)

    $openInstallBtn = New-Button (T 'btn.openInstall') 258 88 225
    $openInstallBtn.Add_Click({ if (Test-Path $installDirBox.Text.Trim()) { Start-Process $installDirBox.Text.Trim() } })
    $diagGroup.Controls.Add($openInstallBtn)

    $openSettingsBtn = New-Button (T 'btn.openSettings') 18 142 225
    $openSettingsBtn.Add_Click({ $dir = Split-Path -Parent $settingsPathBox.Text.Trim(); if (Test-Path $dir) { Start-Process $dir } })
    $diagGroup.Controls.Add($openSettingsBtn)

    [void]$diagForm.ShowDialog($form)
}

$script:Prefs = Load-UiPreferences
$script:CurrentLanguage = $script:Prefs.language
$script:WizardCompleted = [bool]$script:Prefs.firstRunCompleted

$form = New-Object System.Windows.Forms.Form
$form.Text = "$(T 'app.title') $(Get-ProjectVersion)"
$form.Size = New-Object System.Drawing.Size(980, 815)
$form.StartPosition = 'CenterScreen'
$form.SuspendLayout()

$title = New-Label ("$(T 'app.title') $(Get-ProjectVersion)") 16 14 260 26
$title.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($title)

$subtitle = New-Label (T 'app.subtitle') 285 18 380 22
$subtitle.ForeColor = [System.Drawing.Color]::DimGray
Register-Text $subtitle 'app.subtitle'
$form.Controls.Add($subtitle)

$languageLabel = New-Label (T 'language.label') 690 18 80 22
Register-Text $languageLabel 'language.label'
$form.Controls.Add($languageLabel)

$languageBox = New-Object System.Windows.Forms.ComboBox
$languageBox.DropDownStyle = 'DropDownList'
$languageBox.Location = New-Object System.Drawing.Point(775, 14)
$languageBox.Size = New-Object System.Drawing.Size(160, 24)
$form.Controls.Add($languageBox)

$loginStatusLabel = New-Label (T 'status.checking') 16 48 920 24
$form.Controls.Add($loginStatusLabel)

$settingsGroup = New-Object System.Windows.Forms.GroupBox
$settingsGroup.Text = T 'settings.title'
$settingsGroup.Location = New-Object System.Drawing.Point(16, 80)
$settingsGroup.Size = New-Object System.Drawing.Size(930, 205)
$settingsGroup.SuspendLayout()
Register-Text $settingsGroup 'settings.title'
$form.Controls.Add($settingsGroup)

$settingsGroup.Controls.Add((New-Label (T 'field.port') 14 30 120 22))
Register-Text $settingsGroup.Controls[$settingsGroup.Controls.Count - 1] 'field.port'
$portBox = New-TextBox $script:Prefs.lastValues.port 140 26 120
$settingsGroup.Controls.Add($portBox)
$portHint = New-Label (T 'hint.port') 275 30 630 22
$portHint.ForeColor = [System.Drawing.Color]::DimGray
Register-Text $portHint 'hint.port'
$settingsGroup.Controls.Add($portHint)

$settingsGroup.Controls.Add((New-Label (T 'field.proxy') 14 64 120 22))
Register-Text $settingsGroup.Controls[$settingsGroup.Controls.Count - 1] 'field.proxy'
$proxyBox = New-TextBox $script:Prefs.lastValues.proxyUrl 140 60 260
$settingsGroup.Controls.Add($proxyBox)
$proxyHint = New-Label (T 'hint.proxy') 415 64 490 22
$proxyHint.ForeColor = [System.Drawing.Color]::DimGray
Register-Text $proxyHint 'hint.proxy'
$settingsGroup.Controls.Add($proxyHint)

$settingsGroup.Controls.Add((New-Label (T 'field.apiKey') 14 98 120 22))
Register-Text $settingsGroup.Controls[$settingsGroup.Controls.Count - 1] 'field.apiKey'
$apiKeyBox = New-TextBox $script:Prefs.lastValues.apiKey 140 94 260
$settingsGroup.Controls.Add($apiKeyBox)

$settingsGroup.Controls.Add((New-Label (T 'field.installDir') 14 132 120 22))
Register-Text $settingsGroup.Controls[$settingsGroup.Controls.Count - 1] 'field.installDir'
$installDirBox = New-TextBox $script:Prefs.lastValues.installDir 140 128 540
$settingsGroup.Controls.Add($installDirBox)

$settingsGroup.Controls.Add((New-Label (T 'field.settings') 14 166 120 22))
Register-Text $settingsGroup.Controls[$settingsGroup.Controls.Count - 1] 'field.settings'
$settingsPathBox = New-TextBox $script:Prefs.lastValues.claudeSettingsPath 140 162 540
$settingsGroup.Controls.Add($settingsPathBox)

$deviceCheck = New-Object System.Windows.Forms.CheckBox
$deviceCheck.Text = T 'check.device'
$deviceCheck.Location = New-Object System.Drawing.Point(700, 94)
$deviceCheck.Size = New-Object System.Drawing.Size(190, 24)
$deviceCheck.Checked = [bool]$script:Prefs.lastValues.useDeviceLogin
Register-Text $deviceCheck 'check.device'
$settingsGroup.Controls.Add($deviceCheck)

$skipStreamCheck = New-Object System.Windows.Forms.CheckBox
$skipStreamCheck.Text = T 'check.skipStream'
$skipStreamCheck.Location = New-Object System.Drawing.Point(700, 128)
$skipStreamCheck.Size = New-Object System.Drawing.Size(210, 24)
$skipStreamCheck.Checked = [bool]$script:Prefs.lastValues.skipStreamCheck
Register-Text $skipStreamCheck 'check.skipStream'
$settingsGroup.Controls.Add($skipStreamCheck)

$wizardGroup = New-Object System.Windows.Forms.GroupBox
$wizardGroup.Location = New-Object System.Drawing.Point(16, 300)
$wizardGroup.Size = New-Object System.Drawing.Size(455, 215)
$wizardGroup.SuspendLayout()
Register-Text $wizardGroup 'wizard.title'
$form.Controls.Add($wizardGroup)

$wizardDescription = New-Label (T 'wizard.description') 14 24 420 38
$wizardDescription.ForeColor = [System.Drawing.Color]::DimGray
Register-Text $wizardDescription 'wizard.description'
$wizardGroup.Controls.Add($wizardDescription)

$wizardY = 70
foreach ($step in $WizardSteps) {
    $stepLabel = New-Label (T $step.TextKey) 18 $wizardY 295 24
    $stepLabel.Tag = T $step.TextKey
    $script:WizardStepLabels[$step.Id] = $stepLabel
    $wizardGroup.Controls.Add($stepLabel)

    $runButton = New-Button (T 'wizard.run') 325 ($wizardY - 4) 90
    Register-Text $runButton 'wizard.run'
    $stepForClick = $step
    $runButton.Add_Click({ Invoke-WizardStep $stepForClick }.GetNewClosure())
    $wizardGroup.Controls.Add($runButton)
    $wizardY += 28
}

$mainGroup = New-Object System.Windows.Forms.GroupBox
$mainGroup.Text = T 'main.title'
$mainGroup.Location = New-Object System.Drawing.Point(490, 300)
$mainGroup.Size = New-Object System.Drawing.Size(455, 100)
$mainGroup.SuspendLayout()
Register-Text $mainGroup 'main.title'
$form.Controls.Add($mainGroup)

$mainButtons = @(
    @('btn.install', 16, 34, 'install', $true),
    @('btn.login', 104, 34, 'login', $false),
    @('btn.configure', 192, 34, 'configure', $true),
    @('btn.restart', 290, 34, 'restart', $false),
    @('btn.verify', 365, 34, 'verify', $false)
)
foreach ($b in $mainButtons) {
    $btn = New-Button (T $b[0]) $b[1] $b[2] 78
    Register-Text $btn $b[0]
    $cmd = $b[3]
    $need = [bool]$b[4]
    $btn.Add_Click({ Run-Command $cmd $need | Out-Null }.GetNewClosure())
    $mainGroup.Controls.Add($btn)
}

$modelsGroup = New-Object System.Windows.Forms.GroupBox
$modelsGroup.Text = T 'models.title'
$modelsGroup.Location = New-Object System.Drawing.Point(490, 415)
$modelsGroup.Size = New-Object System.Drawing.Size(455, 170)
$modelsGroup.SuspendLayout()
Register-Text $modelsGroup 'models.title'
$form.Controls.Add($modelsGroup)

$modelsGroup.Controls.Add((New-Label (T 'field.opusModel') 14 30 90 22))
Register-Text $modelsGroup.Controls[$modelsGroup.Controls.Count - 1] 'field.opusModel'
$opusModelBox = New-TextBox $script:Prefs.lastValues.opusModel 110 26 220
$modelsGroup.Controls.Add($opusModelBox)

$modelsGroup.Controls.Add((New-Label (T 'field.sonnetModel') 14 64 90 22))
Register-Text $modelsGroup.Controls[$modelsGroup.Controls.Count - 1] 'field.sonnetModel'
$sonnetModelBox = New-TextBox $script:Prefs.lastValues.sonnetModel 110 60 220
$modelsGroup.Controls.Add($sonnetModelBox)

$modelsGroup.Controls.Add((New-Label (T 'field.haikuModel') 14 98 90 22))
Register-Text $modelsGroup.Controls[$modelsGroup.Controls.Count - 1] 'field.haikuModel'
$haikuModelBox = New-TextBox $script:Prefs.lastValues.haikuModel 110 94 220
$modelsGroup.Controls.Add($haikuModelBox)

$readModelsBtn = New-Button (T 'btn.models') 345 43 90
Register-Text $readModelsBtn 'btn.models'
$readModelsBtn.Add_Click({ Run-Command 'models' $false | Out-Null })
$modelsGroup.Controls.Add($readModelsBtn)

$saveModelsBtn = New-Button (T 'btn.configureModels') 345 85 90
Register-Text $saveModelsBtn 'btn.configureModels'
$saveModelsBtn.Add_Click({ Run-Command 'configure-models' $false | Out-Null })
$modelsGroup.Controls.Add($saveModelsBtn)

$toolsGroup = New-Object System.Windows.Forms.GroupBox
$toolsGroup.Text = T 'advanced.title'
$toolsGroup.Location = New-Object System.Drawing.Point(16, 530)
$toolsGroup.Size = New-Object System.Drawing.Size(455, 55)
$toolsGroup.SuspendLayout()
Register-Text $toolsGroup 'advanced.title'
$form.Controls.Add($toolsGroup)

$advancedManagementBtn = New-Button (T 'btn.advancedManagement') 28 16 185
Register-Text $advancedManagementBtn 'btn.advancedManagement'
$advancedManagementBtn.Add_Click({ Show-AdvancedManagementWindow })
$toolsGroup.Controls.Add($advancedManagementBtn)

$diagnosticsBtn = New-Button (T 'btn.diagnostics') 238 16 185
Register-Text $diagnosticsBtn 'btn.diagnostics'
$diagnosticsBtn.Add_Click({ Show-DiagnosticsWindow })
$toolsGroup.Controls.Add($diagnosticsBtn)

$logGroup = New-Object System.Windows.Forms.GroupBox
$logGroup.Text = T 'log.title'
$logGroup.Location = New-Object System.Drawing.Point(16, 600)
$logGroup.Size = New-Object System.Drawing.Size(930, 165)
$logGroup.SuspendLayout()
Register-Text $logGroup 'log.title'
$form.Controls.Add($logGroup)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(12, 24)
$logBox.Size = New-Object System.Drawing.Size(905, 128)
$logBox.Multiline = $true
$logBox.ScrollBars = 'Vertical'
$logBox.ReadOnly = $true
$logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$logGroup.Controls.Add($logBox)

$languageBox.Add_SelectedIndexChanged({
    if ($script:ApplyingLanguage) { return }
    $selected = [string]$languageBox.SelectedItem
    if ($selected -eq (T 'language.zh')) { $script:CurrentLanguage = 'zh-CN' }
    elseif ($selected -eq (T 'language.en')) { $script:CurrentLanguage = 'en-US' }
    Apply-Language
    Save-UiPreferences
})

$form.Add_FormClosing({ Save-UiPreferences })
$form.Add_Shown({
    $form.BeginInvoke([System.Action]{
        Refresh-AuthStatus
        if ($script:Prefs.settingsLoadFailed) { Append-Log (T 'log.settingsFallback') }
    }) | Out-Null
})

Apply-Language
$settingsGroup.ResumeLayout($false)
$wizardGroup.ResumeLayout($false)
$mainGroup.ResumeLayout($false)
$toolsGroup.ResumeLayout($false)
$modelsGroup.ResumeLayout($false)
$logGroup.ResumeLayout($false)
$form.ResumeLayout($false)
$form.PerformLayout()

[void]$form.ShowDialog()
