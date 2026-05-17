[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('install', 'login', 'configure', 'start', 'stop', 'restart', 'status', 'verify', 'doctor', 'help')]
    [string]$Command = 'help',

    [int]$Port,
    [string]$ProxyUrl,
    [string]$ApiKey = 'sk-cliproxy-local-dev-2026',
    [string]$InstallDir = (Join-Path $env:USERPROFILE '.cli-proxy-api'),
    [string]$ClaudeSettingsPath = (Join-Path $env:USERPROFILE '.claude\settings.json'),
    [string]$OpusModel = 'gpt-5.5(xhigh)',
    [string]$SonnetModel = 'gpt-5.3-codex(high)',
    [string]$HaikuModel = 'gpt-5.3-codex-spark(medium)',
    [switch]$Device,
    [switch]$Force,
    [switch]$SkipClaudeStreamCheck
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ProxyUrlProvided = $PSBoundParameters.ContainsKey('ProxyUrl')
$ExePath = Join-Path $InstallDir 'cli-proxy-api.exe'
$ConfigPath = Join-Path $InstallDir 'config.yaml'
$LogPath = Join-Path $InstallDir 'logs\main.log'

function Write-Step([string]$Message) { Write-Host ("`n>> " + $Message) -ForegroundColor Cyan }
function Write-OK([string]$Message) { Write-Host ("    [OK] " + $Message) -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host ("    [!!] " + $Message) -ForegroundColor Yellow }
function Write-Fail([string]$Message) { Write-Host ("    [X] " + $Message) -ForegroundColor Red }
function Write-Info([string]$Message) { Write-Host ("    .. " + $Message) -ForegroundColor Gray }

function Write-FileUtf8NoBom([string]$Path, [string]$Content) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::UTF8)
}

function Show-Help {
    Write-Host 'CodexToClaude' -ForegroundColor Cyan
    Write-Host 'Use Codex Plus/Pro through CLIProxyAPI in Claude Code.' -ForegroundColor Gray
    Write-Host ''
    Write-Host 'Commands:'
    Write-Host '  install     Install/update CLIProxyAPI config and optionally download executable'
    Write-Host '  login       Run Codex OAuth login through CLIProxyAPI'
    Write-Host '  configure   Merge Claude Code settings.json env values'
    Write-Host '  start       Start CLIProxyAPI in background'
    Write-Host '  stop        Stop CLIProxyAPI listening on configured port'
    Write-Host '  restart     Stop then start CLIProxyAPI and wait for readiness'
    Write-Host '  status      Show local setup status'
    Write-Host '  verify      Verify /v1/models and /v1/messages'
    Write-Host '  doctor      Run status and verify'
    Write-Host ''
    Write-Host 'Examples:'
    Write-Host '  .\scripts\CodexToClaude.ps1 install -Port 8317 -ProxyUrl "http://127.0.0.1:7897"'
    Write-Host '  .\scripts\CodexToClaude.ps1 install -Port 8317 -ProxyUrl none'
    Write-Host '  .\scripts\CodexToClaude.ps1 login -Device'
    Write-Host '  .\scripts\CodexToClaude.ps1 restart'
}

function Get-ConfigValue([string]$Name) {
    if (-not (Test-Path $ConfigPath)) { return $null }
    $raw = Get-Content $ConfigPath -Raw -Encoding UTF8
    $escaped = [regex]::Escape($Name)
    $m = [regex]::Match($raw, "(?m)^$escaped\s*:\s*`"?([^`"\r\n#]+)`"?\s*$")
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return $null
}

function Resolve-Port([bool]$RequirePrompt) {
    if ($Port -gt 0) { return $Port }
    $fromConfig = Get-ConfigValue 'port'
    if ($fromConfig -and ($fromConfig -match '^\d+$')) { return [int]$fromConfig }
    if (-not $RequirePrompt) { throw 'Missing port. Run configure or install with -Port first.' }
    while ($true) {
        $inputPort = Read-Host 'Enter CLIProxyAPI local listen port, for example 8317'
        if ($inputPort -match '^\d+$' -and [int]$inputPort -gt 0 -and [int]$inputPort -lt 65536) {
            return [int]$inputPort
        }
        Write-Warn 'Port must be a number from 1 to 65535.'
    }
}

function Normalize-ProxyUrl([string]$Value) {
    if ($null -eq $Value) { return $null }
    $v = $Value.Trim()
    if ($v -eq '') { return $null }
    if ($v -in @('none', 'direct', 'no', 'off', 'false')) { return '' }
    if ($v -notmatch '^(http|https|socks5)://') {
        throw 'proxy-url must start with http://, https://, or socks5://. Use none if no proxy is needed.'
    }
    return $v
}

function Resolve-ProxyUrl([bool]$RequirePrompt) {
    if ($ProxyUrlProvided) { return Normalize-ProxyUrl $ProxyUrl }
    $fromConfig = Get-ConfigValue 'proxy-url'
    if ($null -ne $fromConfig) { return Normalize-ProxyUrl $fromConfig }
    if (-not $RequirePrompt) { throw 'Missing proxy-url. Run configure or install with -ProxyUrl first; use -ProxyUrl none for direct access.' }
    while ($true) {
        $inputProxy = Read-Host 'Enter upstream proxy URL, for example http://127.0.0.1:7897; enter none for direct access'
        try {
            $normalized = Normalize-ProxyUrl $inputProxy
            if ($null -ne $normalized) { return $normalized }
        } catch {
            Write-Warn $_.Exception.Message
        }
    }
}

function Ensure-InstallDir { if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Force $InstallDir | Out-Null } }

function Download-CLIProxyApi {
    if (Test-Path $ExePath) {
        Write-OK "cli-proxy-api.exe exists: $ExePath"
        return
    }

    Write-Step 'Downloading CLIProxyAPI latest release'
    try {
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest' -UseBasicParsing
        $asset = $release.assets | Where-Object { $_.name -match '(windows|win)' -and $_.name -match '(amd64|x64|x86_64)' -and $_.name -match '\.(zip|exe)$' } | Select-Object -First 1
        if (-not $asset) { throw 'No Windows x64/amd64 asset found in latest release.' }
        $downloadPath = Join-Path $InstallDir $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath -UseBasicParsing
        if ($downloadPath -match '\.exe$') {
            Move-Item -Force $downloadPath $ExePath
        } else {
            $extractDir = Join-Path $InstallDir 'download-extract'
            if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
            Expand-Archive -Path $downloadPath -DestinationPath $extractDir -Force
            $exe = Get-ChildItem $extractDir -Recurse -Filter 'cli-proxy-api.exe' | Select-Object -First 1
            if (-not $exe) { throw 'Downloaded archive does not contain cli-proxy-api.exe.' }
            Copy-Item -Force $exe.FullName $ExePath
            Remove-Item $extractDir -Recurse -Force
            Remove-Item $downloadPath -Force
        }
        Write-OK "Downloaded: $ExePath"
    } catch {
        Write-Fail "Automatic download failed: $($_.Exception.Message)"
        Write-Info 'Download the Windows x64/amd64 release manually and place it at:'
        Write-Info "  $ExePath"
        throw
    }
}

function Write-Config([int]$ResolvedPort, [string]$ResolvedProxyUrl) {
    $proxyLine = ''
    if ($ResolvedProxyUrl -ne '') { $proxyLine = "proxy-url: `"$ResolvedProxyUrl`"`n" }
    $content = @"
# CLIProxyAPI config generated by CodexToClaude
host: "127.0.0.1"
port: $ResolvedPort
$proxyLine
remote-management:
  allow-remote: false
  secret-key: ""
  disable-control-panel: false

auth-dir: "~/.cli-proxy-api"

api-keys:
  - "$ApiKey"

quota-exceeded:
  switch-project: true
  switch-preview-model: true

request-retry: 3
debug: true
logging-to-file: true
logs-max-total-size-mb: 10

payload:
  filter:
    - models:
        - name: "gpt-*"
          protocol: "codex"
      params:
        - "reasoning"
        - "reasoning.effort"
"@
    Write-FileUtf8NoBom $ConfigPath $content
    Write-OK "Wrote config: $ConfigPath"
}

function Get-PortProcesses([int]$ResolvedPort) {
    $connections = Get-NetTCPConnection -LocalPort $ResolvedPort -ErrorAction SilentlyContinue
    if (-not $connections) { return @() }
    $ids = $connections | Select-Object -ExpandProperty OwningProcess -Unique
    $result = @()
    foreach ($id in $ids) {
        $proc = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($proc) { $result += $proc }
    }
    return $result
}

function Wait-PortFree([int]$ResolvedPort, [int]$TimeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ((Get-PortProcesses $ResolvedPort).Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 300
    }
    return $false
}

function Stop-CLIProxyApi([int]$ResolvedPort) {
    Write-Step "Stopping CLIProxyAPI on port $ResolvedPort"
    $procs = Get-PortProcesses $ResolvedPort
    if ($procs.Count -eq 0) {
        Write-OK 'No process is listening on the target port.'
        return
    }
    foreach ($proc in $procs) {
        if ($proc.ProcessName -eq 'cli-proxy-api' -or $proc.Path -eq $ExePath) {
            Stop-Process -Id $proc.Id -Force -Confirm:$false
            Write-OK "Stopped $($proc.ProcessName) pid=$($proc.Id)"
        } else {
            throw "Port $ResolvedPort is owned by $($proc.ProcessName) pid=$($proc.Id), not cli-proxy-api. Refusing to stop it."
        }
    }
    if (-not (Wait-PortFree $ResolvedPort 10)) { throw "Port $ResolvedPort was not released in time." }
}

function Wait-ServiceReady([int]$ResolvedPort, [int]$TimeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $healthUrl = "http://127.0.0.1:$ResolvedPort/healthz"
    while ((Get-Date) -lt $deadline) {
        try {
            Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 2 | Out-Null
            return $true
        } catch {
            if ((Get-PortProcesses $ResolvedPort).Count -gt 0) { return $true }
            Start-Sleep -Milliseconds 500
        }
    }
    return $false
}

function Start-CLIProxyApi([int]$ResolvedPort) {
    Write-Step "Starting CLIProxyAPI on port $ResolvedPort"
    if (-not (Test-Path $ExePath)) { throw "Missing executable: $ExePath" }
    if (-not (Test-Path $ConfigPath)) { throw "Missing config: $ConfigPath" }
    $existing = Get-PortProcesses $ResolvedPort
    if ($existing.Count -gt 0) {
        Write-OK "Port $ResolvedPort is already listening."
        return
    }
    $proc = Start-Process -FilePath $ExePath -ArgumentList @('-config', $ConfigPath) -WorkingDirectory $InstallDir -WindowStyle Minimized -PassThru
    Start-Sleep -Milliseconds 500
    if ($proc.HasExited) { throw "cli-proxy-api exited immediately with code $($proc.ExitCode)." }
    if (-not (Wait-ServiceReady $ResolvedPort 20)) {
        $tail = ''
        if (Test-Path $LogPath) { $tail = (Get-Content $LogPath -Tail 30 -ErrorAction SilentlyContinue | Out-String) }
        throw "CLIProxyAPI did not become ready on port $ResolvedPort.`n$tail"
    }
    Write-OK "Started cli-proxy-api pid=$($proc.Id)"
}

function Get-AuthFiles {
    if (-not (Test-Path $InstallDir)) { return @() }
    return @(Get-ChildItem $InstallDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'settings|test|temp' })
}

function Assert-AuthReady {
    $authFiles = Get-AuthFiles
    if ($authFiles.Count -eq 0) { throw "No Codex auth JSON found in $InstallDir. Run login first." }
    $valid = @()
    foreach ($file in $authFiles) {
        try {
            $json = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($json.type -eq 'codex' -and $json.disabled -ne $true) { $valid += $file }
        } catch {}
    }
    if ($valid.Count -eq 0) { throw 'No enabled Codex auth JSON found. Check disabled=false and type=codex.' }
    Write-OK "Enabled Codex auth files: $($valid.Count)"
}

function Set-JsonProperty([object]$Object, [string]$Name, [object]$Value) {
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { $prop.Value = $Value } else { $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value }
}

function Remove-JsonProperty([object]$Object, [string]$Name) {
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { $Object.PSObject.Properties.Remove($Name) }
}

function Configure-Claude([int]$ResolvedPort) {
    Write-Step 'Configuring Claude Code settings.json'
    $claudeDir = Split-Path -Parent $ClaudeSettingsPath
    if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Force $claudeDir | Out-Null }
    if (Test-Path $ClaudeSettingsPath) {
        $settings = Get-Content $ClaudeSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        $settings = New-Object PSObject
    }
    if (-not $settings.PSObject.Properties['env'] -or $null -eq $settings.env) {
        Set-JsonProperty $settings 'env' (New-Object PSObject)
    }
    Set-JsonProperty $settings.env 'ANTHROPIC_AUTH_TOKEN' $ApiKey
    Set-JsonProperty $settings.env 'ANTHROPIC_BASE_URL' "http://127.0.0.1:$ResolvedPort"
    Set-JsonProperty $settings.env 'ANTHROPIC_DEFAULT_OPUS_MODEL' $OpusModel
    Set-JsonProperty $settings.env 'ANTHROPIC_DEFAULT_SONNET_MODEL' $SonnetModel
    Set-JsonProperty $settings.env 'ANTHROPIC_DEFAULT_HAIKU_MODEL' $HaikuModel
    Set-JsonProperty $settings.env 'ANTHROPIC_DEFAULT_OPUS_MODEL_NAME' ($OpusModel -replace '\(.*\)$', '')
    Set-JsonProperty $settings.env 'ANTHROPIC_DEFAULT_SONNET_MODEL_NAME' ($SonnetModel -replace '\(.*\)$', '')
    Set-JsonProperty $settings.env 'CLAUDE_CODE_EFFORT_LEVEL' 'high'
    Remove-JsonProperty $settings.env 'ANTHROPIC_MODEL'
    $json = $settings | ConvertTo-Json -Depth 20
    Write-FileUtf8NoBom $ClaudeSettingsPath ($json + "`n")
    Write-OK "Updated: $ClaudeSettingsPath"
}

function Invoke-Models([int]$ResolvedPort) {
    $headers = @{ Authorization = "Bearer $ApiKey" }
    return Invoke-RestMethod -Uri "http://127.0.0.1:$ResolvedPort/v1/models" -Headers $headers -TimeoutSec 30
}

function Invoke-Message([int]$ResolvedPort) {
    $headers = @{
        'x-api-key' = $ApiKey
        'anthropic-version' = '2023-06-01'
        'Content-Type' = 'application/json'
    }
    $body = @{
        model = $SonnetModel
        max_tokens = 30
        messages = @(@{ role = 'user'; content = 'say hi in one word' })
    } | ConvertTo-Json -Depth 10
    return Invoke-RestMethod -Uri "http://127.0.0.1:$ResolvedPort/v1/messages" -Method Post -Headers $headers -Body $body -TimeoutSec 120
}

function Test-ClaudeStreamJson([int]$ResolvedPort) {
    if ($SkipClaudeStreamCheck) { return }
    $claude = Get-Command claude.exe -ErrorAction SilentlyContinue
    if (-not $claude) {
        Write-Warn 'claude.exe not found; skipping Claude Code stream-json check.'
        return
    }
    $env:ANTHROPIC_AUTH_TOKEN = $ApiKey
    $env:ANTHROPIC_BASE_URL = "http://127.0.0.1:$ResolvedPort"
    $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $SonnetModel
    $stdout = Join-Path $env:TEMP "ctc-claude-stdout-$([guid]::NewGuid().ToString()).txt"
    $stderr = Join-Path $env:TEMP "ctc-claude-stderr-$([guid]::NewGuid().ToString()).txt"
    try {
        $proc = Start-Process -FilePath $claude.Source -ArgumentList @('-p', 'Say OK in one word.', '--output-format=stream-json', '--include-partial-messages', '--verbose') -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $output = ''
        if (Test-Path $stdout) { $output += Get-Content $stdout -Raw -ErrorAction SilentlyContinue }
        if ($proc.ExitCode -ne 0) {
            $err = ''
            if (Test-Path $stderr) { $err = Get-Content $stderr -Raw -ErrorAction SilentlyContinue }
            throw "claude.exe exited with code $($proc.ExitCode). $err"
        }
    } finally {
        Remove-Item $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
    $thinkingCount = ([regex]::Matches($output, 'thinking_delta')).Count
    $textCount = ([regex]::Matches($output, 'text_delta')).Count
    if ($thinkingCount -ne 0) { throw "Claude stream-json still contains thinking_delta_count=$thinkingCount" }
    if ($textCount -eq 0) { throw 'Claude stream-json did not contain text_delta.' }
    Write-OK "Claude stream-json check passed: thinking_delta_count=0, text_delta_count=$textCount"
}

function Show-Status([int]$ResolvedPort) {
    Write-Step 'Status'
    if (Test-Path $ExePath) { Write-OK "Executable: $ExePath" } else { Write-Fail "Executable missing: $ExePath" }
    if (Test-Path $ConfigPath) { Write-OK "Config: $ConfigPath" } else { Write-Fail "Config missing: $ConfigPath" }
    $authFiles = Get-AuthFiles
    Write-Info "Auth JSON files in root: $($authFiles.Count)"
    $procs = Get-PortProcesses $ResolvedPort
    if ($procs.Count -gt 0) {
        foreach ($proc in $procs) { Write-OK "Listening on ${ResolvedPort}: $($proc.ProcessName) pid=$($proc.Id)" }
    } else {
        Write-Warn "Nothing is listening on $ResolvedPort"
    }
    if (Test-Path $ClaudeSettingsPath) {
        try {
            $settings = Get-Content $ClaudeSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $baseUrl = $settings.env.ANTHROPIC_BASE_URL
            if ($baseUrl -eq "http://127.0.0.1:$ResolvedPort") { Write-OK "Claude Code base URL: $baseUrl" }
            else { Write-Warn "Claude Code base URL: $baseUrl" }
        } catch {
            Write-Warn "Unable to parse Claude settings: $ClaudeSettingsPath"
        }
    } else {
        Write-Warn "Claude settings missing: $ClaudeSettingsPath"
    }
}

function Verify-Setup([int]$ResolvedPort) {
    Write-Step 'Verifying setup'
    Assert-AuthReady
    Start-CLIProxyApi $ResolvedPort
    $models = Invoke-Models $ResolvedPort
    $modelCount = 0
    if ($models.data) { $modelCount = @($models.data).Count }
    if ($modelCount -eq 0) { throw '/v1/models returned no models.' }
    Write-OK "/v1/models returned $modelCount models"
    $message = Invoke-Message $ResolvedPort
    $text = ''
    if ($message.content) {
        foreach ($part in $message.content) {
            if ($part.text) { $text += $part.text }
        }
    }
    if (-not $text) { throw '/v1/messages returned no text content.' }
    Write-OK "/v1/messages returned text: $text"
    Test-ClaudeStreamJson $ResolvedPort
}

switch ($Command) {
    'help' { Show-Help }
    'install' {
        Ensure-InstallDir
        $resolvedPort = Resolve-Port $true
        $resolvedProxy = Resolve-ProxyUrl $true
        Download-CLIProxyApi
        Write-Config $resolvedPort $resolvedProxy
        Write-OK 'Install/config step complete. Run login, configure, restart, verify next.'
    }
    'login' {
        Ensure-InstallDir
        if (-not (Test-Path $ExePath)) { Download-CLIProxyApi }
        $loginArg = '-codex-login'
        if ($Device) { $loginArg = '-codex-device-login' }
        & $ExePath -config $ConfigPath $loginArg
        Assert-AuthReady
    }
    'configure' {
        $resolvedPort = Resolve-Port $true
        $resolvedProxy = Resolve-ProxyUrl $true
        Ensure-InstallDir
        Write-Config $resolvedPort $resolvedProxy
        Configure-Claude $resolvedPort
    }
    'start' {
        $resolvedPort = Resolve-Port $false
        Start-CLIProxyApi $resolvedPort
    }
    'stop' {
        $resolvedPort = Resolve-Port $false
        Stop-CLIProxyApi $resolvedPort
    }
    'restart' {
        $resolvedPort = Resolve-Port $false
        Stop-CLIProxyApi $resolvedPort
        Start-CLIProxyApi $resolvedPort
    }
    'status' {
        $resolvedPort = Resolve-Port $false
        Show-Status $resolvedPort
    }
    'verify' {
        $resolvedPort = Resolve-Port $false
        Verify-Setup $resolvedPort
    }
    'doctor' {
        $resolvedPort = Resolve-Port $false
        Show-Status $resolvedPort
        Verify-Setup $resolvedPort
    }
}
