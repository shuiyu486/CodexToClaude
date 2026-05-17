[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptPath = Join-Path $PSScriptRoot 'CodexToClaude.ps1'
$DefaultInstallDir = Join-Path $env:USERPROFILE '.cli-proxy-api'
$DefaultSettingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'

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
    $button.Size = New-Object System.Drawing.Size($W, 30)
    return $button
}

function Append-Log([string]$Text) {
    $logBox.AppendText($Text + [Environment]::NewLine)
    $logBox.SelectionStart = $logBox.Text.Length
    $logBox.ScrollToCaret()
}

function Validate-Inputs([bool]$RequireProxy) {
    if ($portBox.Text.Trim() -notmatch '^\d+$') {
        [System.Windows.Forms.MessageBox]::Show('Port must be a number, for example 8317.', 'Invalid Port') | Out-Null
        return $false
    }
    $p = [int]$portBox.Text.Trim()
    if ($p -lt 1 -or $p -gt 65535) {
        [System.Windows.Forms.MessageBox]::Show('Port must be in range 1-65535.', 'Invalid Port') | Out-Null
        return $false
    }
    if ($RequireProxy) {
        $proxy = $proxyBox.Text.Trim()
        if ($proxy -eq '') {
            [System.Windows.Forms.MessageBox]::Show('ProxyUrl is required. Use none if direct access works.', 'ProxyUrl Required') | Out-Null
            return $false
        }
        if ($proxy -notin @('none', 'direct') -and $proxy -notmatch '^(http|https|socks5)://') {
            [System.Windows.Forms.MessageBox]::Show('ProxyUrl must start with http://, https://, socks5://, or be none/direct.', 'Invalid ProxyUrl') | Out-Null
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
    if ($deviceCheck.Checked -and $Command -eq 'login') { $args += '-Device' }
    if ($skipStreamCheck.Checked) { $args += '-SkipClaudeStreamCheck' }
    return $args
}

function Run-Command([string]$Command, [bool]$NeedPortProxy) {
    if ($NeedPortProxy -and -not (Validate-Inputs $true)) { return }
    if ((@('start','stop','restart','status','verify','doctor') -contains $Command) -and -not (Validate-Inputs $false)) { return }
    Append-Log ""
    Append-Log "> $Command"
    $stdout = Join-Path $env:TEMP "ctc-ui-stdout-$([guid]::NewGuid().ToString()).txt"
    $stderr = Join-Path $env:TEMP "ctc-ui-stderr-$([guid]::NewGuid().ToString()).txt"
    try {
        $args = Build-Args $Command $NeedPortProxy
        $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if (Test-Path $stdout) {
            $out = Get-Content $stdout -Raw -ErrorAction SilentlyContinue
            if ($out) { Append-Log $out.TrimEnd() }
        }
        if (Test-Path $stderr) {
            $err = Get-Content $stderr -Raw -ErrorAction SilentlyContinue
            if ($err) { Append-Log $err.TrimEnd() }
        }
        Append-Log "ExitCode: $($proc.ExitCode)"
        if ($Command -eq 'login' -or $Command -eq 'install' -or $Command -eq 'configure') { Refresh-AuthStatus }
    } catch {
        Append-Log "ERROR: $($_.Exception.Message)"
        if ($Command -eq 'login') { Append-LoginHelp }
    } finally {
        Remove-Item $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Append-LoginHelp {
    Append-Log 'Login troubleshooting:'
    Append-Log '1. Check proxy, then rerun install/configure with the correct ProxyUrl.'
    Append-Log '2. Try Device Login.'
    Append-Log '3. Make sure Codex OAuth JSON is in ~/.cli-proxy-api root.'
    Append-Log '4. Make sure JSON has type=codex and disabled is not true.'
    Append-Log '5. Check ~/.cli-proxy-api/logs/main.log.'
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
            $loginStatusLabel.Text = "Login status: $($status.message)"
            if ($status.status -eq 'logged_in') { $loginStatusLabel.ForeColor = [System.Drawing.Color]::ForestGreen }
            else { $loginStatusLabel.ForeColor = [System.Drawing.Color]::DarkOrange }
        } else {
            $loginStatusLabel.Text = 'Login status: unable to read auth status'
            $loginStatusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
        }
    } catch {
        $loginStatusLabel.Text = 'Login status: auth check failed'
        $loginStatusLabel.ForeColor = [System.Drawing.Color]::DarkRed
    } finally {
        Remove-Item $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'CodexToClaude'
$form.Size = New-Object System.Drawing.Size(920, 720)
$form.StartPosition = 'CenterScreen'

$title = New-Label 'CodexToClaude - Use Codex Plus/Pro in Claude Code' 16 14 760 26
$title.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($title)

$loginStatusLabel = New-Label 'Login status: checking...' 16 44 850 24
$form.Controls.Add($loginStatusLabel)

$form.Controls.Add((New-Label 'Port' 16 82 120 22))
$portBox = New-TextBox '8317' 150 78 120
$form.Controls.Add($portBox)
$portHint = New-Label 'Local CLIProxyAPI listen port. Claude Code uses http://127.0.0.1:<Port>. Example: 8317.' 285 82 580 22
$portHint.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($portHint)

$form.Controls.Add((New-Label 'ProxyUrl' 16 118 120 22))
$proxyBox = New-TextBox 'http://127.0.0.1:7897' 150 114 260
$form.Controls.Add($proxyBox)
$proxyHint = New-Label 'Upstream proxy for Codex/OpenAI. Use http://127.0.0.1:7897, or type none for direct access.' 425 118 440 22
$proxyHint.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($proxyHint)

$form.Controls.Add((New-Label 'ApiKey' 16 154 120 22))
$apiKeyBox = New-TextBox 'sk-cliproxy-local-dev-2026' 150 150 260
$form.Controls.Add($apiKeyBox)

$form.Controls.Add((New-Label 'InstallDir' 16 190 120 22))
$installDirBox = New-TextBox $DefaultInstallDir 150 186 540
$form.Controls.Add($installDirBox)

$form.Controls.Add((New-Label 'Claude settings' 16 226 120 22))
$settingsPathBox = New-TextBox $DefaultSettingsPath 150 222 540
$form.Controls.Add($settingsPathBox)

$deviceCheck = New-Object System.Windows.Forms.CheckBox
$deviceCheck.Text = 'Use device login'
$deviceCheck.Location = New-Object System.Drawing.Point(150, 258)
$deviceCheck.Size = New-Object System.Drawing.Size(150, 24)
$form.Controls.Add($deviceCheck)

$skipStreamCheck = New-Object System.Windows.Forms.CheckBox
$skipStreamCheck.Text = 'Skip Claude stream check'
$skipStreamCheck.Location = New-Object System.Drawing.Point(315, 258)
$skipStreamCheck.Size = New-Object System.Drawing.Size(190, 24)
$form.Controls.Add($skipStreamCheck)

$buttons = @(
    @('Install', 16, 300, 'install', $true),
    @('Login', 116, 300, 'login', $false),
    @('Configure', 216, 300, 'configure', $true),
    @('Start', 336, 300, 'start', $false),
    @('Stop', 436, 300, 'stop', $false),
    @('Restart', 536, 300, 'restart', $false),
    @('Status', 636, 300, 'status', $false),
    @('Verify', 736, 300, 'verify', $false),
    @('Doctor', 16, 340, 'doctor', $false)
)
foreach ($b in $buttons) {
    $btn = New-Button $b[0] $b[1] $b[2] 90
    $cmd = $b[3]
    $need = [bool]$b[4]
    $btn.Add_Click({ Run-Command $cmd $need }.GetNewClosure())
    $form.Controls.Add($btn)
}

$refreshBtn = New-Button 'Refresh Login Status' 116 340 160
$refreshBtn.Add_Click({ Refresh-AuthStatus })
$form.Controls.Add($refreshBtn)

$openInstallBtn = New-Button 'Open Install Dir' 286 340 130
$openInstallBtn.Add_Click({ if (Test-Path $installDirBox.Text.Trim()) { Start-Process $installDirBox.Text.Trim() } })
$form.Controls.Add($openInstallBtn)

$openSettingsBtn = New-Button 'Open Settings Dir' 426 340 140
$openSettingsBtn.Add_Click({ $dir = Split-Path -Parent $settingsPathBox.Text.Trim(); if (Test-Path $dir) { Start-Process $dir } })
$form.Controls.Add($openSettingsBtn)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(16, 390)
$logBox.Size = New-Object System.Drawing.Size(870, 270)
$logBox.Multiline = $true
$logBox.ScrollBars = 'Vertical'
$logBox.ReadOnly = $true
$logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($logBox)

$form.Add_Shown({ Refresh-AuthStatus })
[void]$form.ShowDialog()
