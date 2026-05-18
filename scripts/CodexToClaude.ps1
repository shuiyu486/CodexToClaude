[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('install', 'login', 'configure', 'start', 'stop', 'restart', 'status', 'auth-status', 'verify', 'doctor', 'project-version', 'project-update', 'cliproxy-version', 'cliproxy-update', 'models', 'configure-models', 'help')]
    [string]$Command = 'help',

    [int]$Port,
    [string]$ProxyUrl,
    [string]$ApiKey = 'sk-cliproxy-local-dev-2026',
    [string]$InstallDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'cli-proxy-api'),
    [string]$ClaudeSettingsPath = (Join-Path $env:USERPROFILE '.claude\settings.json'),
    [string]$OpusModel = 'gpt-5.5',
    [string]$SonnetModel = 'gpt-5.4',
    [string]$HaikuModel = 'gpt-5.4',
    [switch]$Device,
    [switch]$Force,
    [switch]$SkipClaudeStreamCheck,
    [switch]$Json
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

function Get-ProjectVersion {
    $versionPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'VERSION'
    if (-not (Test-Path $versionPath)) { return 'v0.0.0.0' }
    $version = (Get-Content $versionPath -Raw -Encoding UTF8).Trim()
    if ($version -notmatch '^v\d+\.\d+\.\d+\.\d+$') { return 'v0.0.0.0' }
    return $version
}

function Write-FileUtf8NoBom([string]$Path, [string]$Content) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::UTF8)
}

function Show-Help {
    Write-Host "CodexToClaude $(Get-ProjectVersion)" -ForegroundColor Cyan
    Write-Host 'Use Codex Plus/Pro through CLIProxyAPI in Claude Code.' -ForegroundColor Gray
    Write-Host ''
    Write-Host 'Commands:'
    Write-Host '  install      Install/update CLIProxyAPI config and optionally download executable'
    Write-Host '  login        Run Codex OAuth login through CLIProxyAPI'
    Write-Host '  configure    Merge Claude Code settings.json env values'
    Write-Host '  start        Start CLIProxyAPI in background'
    Write-Host '  stop         Stop CLIProxyAPI listening on configured port'
    Write-Host '  restart      Stop then start CLIProxyAPI and wait for readiness'
    Write-Host '  status       Show local setup status'
    Write-Host '  auth-status  Show Codex OAuth login/auth status'
    Write-Host '  verify       Verify /v1/models and /v1/messages'
    Write-Host '  doctor       Run status and verify'
    Write-Host '  project-version   Show CodexToClaude VERSION and git status'
    Write-Host '  project-update    Safely update CodexToClaude with git pull --ff-only'
    Write-Host '  cliproxy-version  Show local and latest CLIProxyAPI version'
    Write-Host '  cliproxy-update   Stop, update, and restart CLIProxyAPI latest release'
    Write-Host '  models            Show configured Claude model env values'
    Write-Host '  configure-models  Update Claude model env values'
    Write-Host ''
    Write-Host 'Required setup values:' -ForegroundColor Yellow
    Write-Host '  -Port      Local CLIProxyAPI listen port. Claude Code uses http://127.0.0.1:<Port>. Example: 8317'
    Write-Host '  -ProxyUrl  Upstream proxy for Codex/OpenAI access. Example: http://127.0.0.1:7897'
    Write-Host '             If your network can access upstream directly, explicitly use: -ProxyUrl none'
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
    if (-not $RequirePrompt) {
        throw 'Missing port. Run configure/install with -Port first. Example: .\scripts\CodexToClaude.ps1 configure -Port 8317 -ProxyUrl http://127.0.0.1:7897'
    }
    while ($true) {
        Write-Host ''
        Write-Host 'Port is the local CLIProxyAPI listen port. Claude Code will call http://127.0.0.1:<Port>.' -ForegroundColor Yellow
        Write-Host 'Example: 8317' -ForegroundColor Gray
        $inputPort = Read-Host 'Enter Port'
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
    if (-not $RequirePrompt) {
        throw 'Missing proxy-url. Run configure/install with -ProxyUrl first. Use -ProxyUrl none for direct access.'
    }
    while ($true) {
        Write-Host ''
        Write-Host 'ProxyUrl is the upstream proxy used by CLIProxyAPI to access Codex/OpenAI.' -ForegroundColor Yellow
        Write-Host 'Example: http://127.0.0.1:7897' -ForegroundColor Gray
        Write-Host 'If direct access works, enter none. Do not leave it blank.' -ForegroundColor Gray
        $inputProxy = Read-Host 'Enter ProxyUrl'
        try {
            $normalized = Normalize-ProxyUrl $inputProxy
            if ($null -ne $normalized) { return $normalized }
            Write-Warn 'ProxyUrl cannot be blank. Use none for direct access.'
        } catch {
            Write-Warn $_.Exception.Message
        }
    }
}

function Ensure-InstallDir { if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Force $InstallDir | Out-Null } }

function Move-LegacyInstall {
    $legacyDir = Join-Path $env:USERPROFILE '.cli-proxy-api'
    if (-not (Test-Path $legacyDir)) { return }
    $legacyItems = Get-ChildItem $legacyDir -ErrorAction SilentlyContinue
    if (-not $legacyItems -or $legacyItems.Count -eq 0) { return }
    if ((Join-Path $legacyDir 'config.yaml') -eq $ConfigPath) { return }
    Write-Step 'Migrating legacy install from ~/.cli-proxy-api'
    Ensure-InstallDir
    $copied = 0
    foreach ($item in $legacyItems) {
        $dest = Join-Path $InstallDir $item.Name
        if (Test-Path $dest) {
            Write-Info "Skip (exists): $($item.Name)"
            continue
        }
        if ($item.PSIsContainer) {
            Copy-Item $item.FullName $dest -Recurse -Force
        } else {
            Copy-Item $item.FullName $dest -Force
        }
        Write-Info "Migrated: $($item.Name)"
        $copied++
    }
    if ($copied -gt 0) {
        Write-OK "Migrated $copied items to $InstallDir. You may remove $legacyDir when ready."
    }
}

function Get-CLIProxyLatestRelease {
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest' -UseBasicParsing
    $asset = $release.assets | Where-Object { $_.name -match '(windows|win)' -and $_.name -match '(amd64|x64|x86_64)' -and $_.name -match '\.(zip|exe)$' } | Select-Object -First 1
    if (-not $asset) { throw 'No Windows x64/amd64 asset found in latest release.' }
    return [pscustomobject]@{ release = $release; asset = $asset }
}

function Install-CLIProxyAsset([string]$DownloadUrl, [string]$AssetName, [string]$DestinationPath) {
    Ensure-InstallDir
    $downloadPath = Join-Path $InstallDir $AssetName
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $downloadPath -UseBasicParsing
    if ($downloadPath -match '\.exe$') {
        Move-Item -Force $downloadPath $DestinationPath
    } else {
        $extractDir = Join-Path $InstallDir 'download-extract'
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
        Expand-Archive -Path $downloadPath -DestinationPath $extractDir -Force
        $exe = Get-ChildItem $extractDir -Recurse -Filter 'cli-proxy-api.exe' | Select-Object -First 1
        if (-not $exe) { throw 'Downloaded archive does not contain cli-proxy-api.exe.' }
        Copy-Item -Force $exe.FullName $DestinationPath
        Remove-Item $extractDir -Recurse -Force
        Remove-Item $downloadPath -Force
    }
}

function Download-CLIProxyApi {
    if (Test-Path $ExePath) {
        Write-OK "cli-proxy-api.exe exists: $ExePath"
        return
    }

    Write-Step 'Downloading CLIProxyAPI latest release'
    try {
        $latest = Get-CLIProxyLatestRelease
        Install-CLIProxyAsset $latest.asset.browser_download_url $latest.asset.name $ExePath
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

auth-dir: "$($InstallDir.Replace('\', '/'))"

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

function Get-AuthStatus {
    $authFiles = Get-AuthFiles
    $items = @()
    foreach ($file in $authFiles) {
        $item = [ordered]@{
            file = $file.Name
            validJson = $false
            type = $null
            email = $null
            expired = $null
            disabled = $null
            usable = $false
            issue = $null
        }
        try {
            $authJson = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $item.validJson = $true
            $item.type = $authJson.type
            $item.email = $authJson.email
            $item.expired = $authJson.expired
            $item.disabled = $authJson.disabled
            if ($authJson.type -ne 'codex') { $item.issue = 'not_codex' }
            elseif ($authJson.disabled -eq $true) { $item.issue = 'disabled' }
            else { $item.usable = $true }
        } catch {
            $item.issue = 'invalid_json'
        }
        $items += [pscustomobject]$item
    }
    $usable = @($items | Where-Object { $_.usable })
    $status = 'not_logged_in'
    $message = 'No auth JSON found. Run login first.'
    if ($items.Count -gt 0 -and $usable.Count -eq 0) {
        if (@($items | Where-Object { $_.issue -eq 'disabled' }).Count -gt 0) {
            $status = 'disabled'
            $message = 'Codex auth JSON found but disabled=true.'
        } elseif (@($items | Where-Object { $_.issue -eq 'not_codex' }).Count -gt 0) {
            $status = 'invalid_type'
            $message = 'Auth JSON found, but no enabled type=codex auth is available.'
        } else {
            $status = 'invalid'
            $message = 'Auth JSON found, but it is invalid or unusable.'
        }
    } elseif ($usable.Count -gt 0) {
        $status = 'logged_in'
        $first = $usable | Select-Object -First 1
        $identity = $first.email
        if (-not $identity) { $identity = $first.file }
        $message = "Logged in: $identity; usable auths=$($usable.Count)"
        if ($first.expired) { $message += "; expires=$($first.expired)" }
    }
    return [pscustomobject]@{
        status = $status
        message = $message
        authCount = $items.Count
        usableCount = $usable.Count
        auths = $items
        suggestions = @(
            'Check that your proxy works, then rerun install/configure with the correct -ProxyUrl.',
            'Try device login: .\scripts\CodexToClaude.ps1 login -Device',
            "Make sure the Codex OAuth JSON is in $InstallDir, not a nested auths folder.",
            'Make sure the JSON has type=codex and does not have disabled=true.',
            "Check $InstallDir/logs/main.log for upstream or OAuth errors."
        )
    }
}

function Write-AuthStatus([object]$Status) {
    if ($Json) {
        $Status | ConvertTo-Json -Depth 8
        return
    }
    if ($Status.status -eq 'logged_in') { Write-OK $Status.message } else { Write-Warn $Status.message }
    foreach ($auth in $Status.auths) {
        $safeEmail = $auth.email
        if (-not $safeEmail) { $safeEmail = '-' }
        Write-Info "auth=$($auth.file) type=$($auth.type) email=$safeEmail disabled=$($auth.disabled) usable=$($auth.usable) issue=$($auth.issue) expires=$($auth.expired)"
    }
    if ($Status.status -ne 'logged_in') {
        Write-Info 'Recommended fixes:'
        foreach ($s in $Status.suggestions) { Write-Info "  - $s" }
    }
}

function Assert-AuthReady {
    $status = Get-AuthStatus
    if ($status.status -ne 'logged_in') {
        Write-AuthStatus $status
        throw 'No enabled Codex auth JSON found.'
    }
    Write-OK "Enabled Codex auth files: $($status.usableCount)"
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
    $outJson = $settings | ConvertTo-Json -Depth 20
    Write-FileUtf8NoBom $ClaudeSettingsPath ($outJson + "`n")
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
    $authStatus = Get-AuthStatus
    Write-AuthStatus $authStatus
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

function Get-RepoRoot { return (Split-Path -Parent $PSScriptRoot) }

function Invoke-Git([string[]]$Arguments) {
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $git) { throw 'git.exe not found. Install Git for Windows before using project update.' }
    $output = & $git.Source -C (Get-RepoRoot) @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output | Out-String).Trim() }
    return $output
}

function Get-GitOutput([string[]]$Arguments) {
    try { return ((Invoke-Git $Arguments) | Out-String).Trim() } catch { return $null }
}

function Show-ProjectVersion {
    Write-Step 'CodexToClaude project version'
    $root = Get-RepoRoot
    if (-not (Test-Path (Join-Path $root '.git'))) { throw "Not a git repository: $root" }
    $branch = Get-GitOutput @('rev-parse', '--abbrev-ref', 'HEAD')
    $sha = Get-GitOutput @('rev-parse', '--short', 'HEAD')
    $status = Get-GitOutput @('status', '--porcelain')
    $dirty = -not [string]::IsNullOrWhiteSpace($status)
    $upstream = Get-GitOutput @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
    Write-Info "Version: $(Get-ProjectVersion)"
    Write-Info "Repository: $root"
    Write-Info "Branch: $branch"
    Write-Info "Commit: $sha"
    if ($upstream) { Write-Info "Upstream: $upstream" } else { Write-Warn 'No upstream branch configured.' }
    if ($dirty) { Write-Warn 'Working tree: dirty' } else { Write-OK 'Working tree: clean' }
}

function Update-Project {
    Write-Step 'Updating CodexToClaude project'
    $status = Get-GitOutput @('status', '--porcelain')
    if (-not [string]::IsNullOrWhiteSpace($status)) {
        throw 'Working tree is not clean. Commit or remove local changes before project-update.'
    }
    $upstream = Get-GitOutput @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
    if (-not $upstream) { throw 'No upstream branch configured. Set an upstream before project-update.' }
    $before = Get-GitOutput @('rev-parse', '--short', 'HEAD')
    Invoke-Git @('fetch') | Out-Null
    Invoke-Git @('pull', '--ff-only') | ForEach-Object { if ($_ -and $_.ToString().Trim()) { Write-Info $_ } }
    $after = Get-GitOutput @('rev-parse', '--short', 'HEAD')
    if ($before -eq $after) { Write-OK "Already up to date: $after" } else { Write-OK "Updated: $before -> $after" }
}

function Get-CLIProxyLocalVersion {
    if (-not (Test-Path $ExePath)) { return 'missing' }
    $info = (Get-Item $ExePath).VersionInfo
    if ($info.ProductVersion) { return $info.ProductVersion }
    if ($info.FileVersion) { return $info.FileVersion }
    return 'installed'
}

function Show-CLIProxyVersion {
    Write-Step 'CLIProxyAPI version'
    Write-Info "Executable: $ExePath"
    Write-Info "Local: $(Get-CLIProxyLocalVersion)"
    try {
        $latest = Get-CLIProxyLatestRelease
        Write-Info "Latest: $($latest.release.tag_name)"
        Write-Info "Asset: $($latest.asset.name)"
    } catch {
        Write-Warn "Unable to read latest release: $($_.Exception.Message)"
    }
}

function Update-CLIProxyApi {
    Write-Step 'Updating CLIProxyAPI latest release'
    Ensure-InstallDir
    $resolvedPort = $null
    $wasRunning = $false
    try {
        $resolvedPort = Resolve-Port $false
        $wasRunning = ((Get-PortProcesses $resolvedPort).Count -gt 0)
        if ($wasRunning) { Stop-CLIProxyApi $resolvedPort }
    } catch {
        Write-Warn "Could not determine or stop running service: $($_.Exception.Message)"
    }

    $latest = Get-CLIProxyLatestRelease
    $staged = Join-Path $InstallDir 'cli-proxy-api.new.exe'
    if (Test-Path $staged) { Remove-Item $staged -Force }
    Install-CLIProxyAsset $latest.asset.browser_download_url $latest.asset.name $staged
    if (-not (Test-Path $staged)) { throw 'Downloaded CLIProxyAPI executable was not created.' }
    $backup = $null
    if (Test-Path $ExePath) {
        $backup = Join-Path $InstallDir "cli-proxy-api.backup-$(Get-Date -Format 'yyyyMMddHHmmss').exe"
        Copy-Item -Force $ExePath $backup
        Write-Info "Backup: $backup"
    }
    Move-Item -Force $staged $ExePath
    Write-OK "Updated CLIProxyAPI to latest release: $($latest.release.tag_name)"
    if ($wasRunning -and $null -ne $resolvedPort) {
        try {
            Start-CLIProxyApi $resolvedPort
        } catch {
            if ($backup -and (Test-Path $backup)) {
                Copy-Item -Force $backup $ExePath
                Write-Warn 'Restored previous cli-proxy-api.exe after restart failure.'
            }
            throw
        }
    }
}

function Get-ClaudeSettings {
    if (Test-Path $ClaudeSettingsPath) { return (Get-Content $ClaudeSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json) }
    return (New-Object PSObject)
}

function Ensure-ClaudeEnv([object]$Settings) {
    if (-not $Settings.PSObject.Properties['env'] -or $null -eq $Settings.env) {
        Set-JsonProperty $Settings 'env' (New-Object PSObject)
    }
}

function Set-ClaudeModelEnv([object]$Settings) {
    Ensure-ClaudeEnv $Settings
    Set-JsonProperty $Settings.env 'ANTHROPIC_DEFAULT_OPUS_MODEL' $OpusModel
    Set-JsonProperty $Settings.env 'ANTHROPIC_DEFAULT_SONNET_MODEL' $SonnetModel
    Set-JsonProperty $Settings.env 'ANTHROPIC_DEFAULT_HAIKU_MODEL' $HaikuModel
    Set-JsonProperty $Settings.env 'ANTHROPIC_DEFAULT_OPUS_MODEL_NAME' ($OpusModel -replace '\(.*\)$', '')
    Set-JsonProperty $Settings.env 'ANTHROPIC_DEFAULT_SONNET_MODEL_NAME' ($SonnetModel -replace '\(.*\)$', '')
    Remove-JsonProperty $Settings.env 'ANTHROPIC_MODEL'
}

function Show-ClaudeModels {
    Write-Step 'Claude model settings'
    $settings = Get-ClaudeSettings
    Ensure-ClaudeEnv $settings
    $opus = $settings.env.ANTHROPIC_DEFAULT_OPUS_MODEL
    $sonnet = $settings.env.ANTHROPIC_DEFAULT_SONNET_MODEL
    $haiku = $settings.env.ANTHROPIC_DEFAULT_HAIKU_MODEL
    if (-not $opus) { $opus = $OpusModel }
    if (-not $sonnet) { $sonnet = $SonnetModel }
    if (-not $haiku) { $haiku = $HaikuModel }
    Write-Info "Opus: $opus"
    Write-Info "Sonnet: $sonnet"
    Write-Info "Haiku: $haiku"
}

function Configure-ClaudeModels {
    Write-Step 'Configuring Claude model settings'
    $claudeDir = Split-Path -Parent $ClaudeSettingsPath
    if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Force $claudeDir | Out-Null }
    $settings = Get-ClaudeSettings
    Set-ClaudeModelEnv $settings
    $outJson = $settings | ConvertTo-Json -Depth 20
    Write-FileUtf8NoBom $ClaudeSettingsPath ($outJson + "`n")
    Write-OK "Updated model settings: $ClaudeSettingsPath"
}

switch ($Command) {
    'help' { Show-Help }
    'install' {
        Move-LegacyInstall
        Ensure-InstallDir
        $resolvedPort = Resolve-Port $true
        $resolvedProxy = Resolve-ProxyUrl $true
        Download-CLIProxyApi
        Write-Config $resolvedPort $resolvedProxy
        Write-OK 'Install/config step complete. Run login, configure, restart, verify next.'
    }
    'login' {
        Move-LegacyInstall
        Ensure-InstallDir
        if (-not (Test-Path $ExePath)) { Download-CLIProxyApi }
        if (-not (Test-Path $ConfigPath)) { Write-Warn 'Config is missing. Run install/configure first if login fails.' }
        $loginArg = '-codex-login'
        if ($Device) { $loginArg = '-codex-device-login' }
        try {
            & $ExePath -config $ConfigPath $loginArg
        } catch {
            Write-Fail "Login command failed: $($_.Exception.Message)"
            $status = Get-AuthStatus
            Write-AuthStatus $status
            throw
        }
        $status = Get-AuthStatus
        Write-AuthStatus $status
        if ($status.status -ne 'logged_in') { throw 'Login finished but no usable Codex auth was found.' }
    }
    'configure' {
        $resolvedPort = Resolve-Port $true
        $resolvedProxy = Resolve-ProxyUrl $true
        Ensure-InstallDir
        Write-Config $resolvedPort $resolvedProxy
        Configure-Claude $resolvedPort
    }
    'start' {
        Move-LegacyInstall
        $resolvedPort = Resolve-Port $false
        Start-CLIProxyApi $resolvedPort
    }
    'stop' {
        $resolvedPort = Resolve-Port $false
        Stop-CLIProxyApi $resolvedPort
    }
    'restart' {
        Move-LegacyInstall
        $resolvedPort = Resolve-Port $false
        Stop-CLIProxyApi $resolvedPort
        Start-CLIProxyApi $resolvedPort
    }
    'status' {
        Move-LegacyInstall
        $resolvedPort = Resolve-Port $false
        Show-Status $resolvedPort
    }
    'auth-status' {
        $status = Get-AuthStatus
        Write-AuthStatus $status
        if ($status.status -ne 'logged_in') { exit 1 }
    }
    'verify' {
        Move-LegacyInstall
        $resolvedPort = Resolve-Port $false
        Verify-Setup $resolvedPort
    }
    'doctor' {
        Move-LegacyInstall
        $resolvedPort = Resolve-Port $false
        Show-Status $resolvedPort
        Verify-Setup $resolvedPort
    }
    'project-version' { Show-ProjectVersion }
    'project-update' { Update-Project }
    'cliproxy-version' { Show-CLIProxyVersion }
    'cliproxy-update' { Update-CLIProxyApi }
    'models' { Show-ClaudeModels }
    'configure-models' { Configure-ClaudeModels }
}
