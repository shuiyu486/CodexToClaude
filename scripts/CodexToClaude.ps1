[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('install', 'login', 'configure', 'start', 'stop', 'restart', 'status', 'auth-status', 'verify', 'doctor', 'project-version', 'project-update', 'cliproxy-version', 'cliproxy-update', 'models', 'configure-models', 'help')]
    [string]$Command = 'help',

    # --- Provider selection ---
    [ValidateSet('cliproxy', 'occ')]
    [string]$Provider = 'cliproxy',

    # --- Common parameters ---
    [int]$Port,
    [string]$ProxyUrl,
    [string]$ApiKey = 'sk-cliproxy-local-dev-2026',
    [string]$InstallDir,
    [string]$ClaudeSettingsPath = (Join-Path $env:USERPROFILE '.claude\settings.json'),
    [string]$OpusModel,
    [string]$SonnetModel,
    [string]$HaikuModel,
    [switch]$Device,
    [switch]$Force,
    [switch]$SkipClaudeStreamCheck,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ProxyUrlProvided = $PSBoundParameters.ContainsKey('ProxyUrl')

# ============================================================
# Provider metadata & path initialization
# ============================================================
$script:ProviderMeta = @{
    cliproxy = @{
        Name = 'CLIProxyAPI'
        Prefix = 'CLIProxy'
        DefaultPort = 8317
        ExeName = 'cli-proxy-api.exe'
        ConfigFile = 'config.yaml'
        InstallDirName = 'cli-proxy-api'
        HealthEndpoint = '/healthz'
        SupportsLogin = $true
    }
    occ = @{
        Name = 'oc-go-cc'
        Prefix = 'OCC'
        DefaultPort = 3456
        ExeName = 'oc-go-cc.exe'
        ConfigFile = 'config.json'
        InstallDirName = 'oc-go-cc'
        HealthEndpoint = '/health'
        SupportsLogin = $false
    }
}

$PMeta = $script:ProviderMeta[$Provider]
$InstallDirProvided = $PSBoundParameters.ContainsKey('InstallDir')

if (-not $InstallDirProvided) {
    $InstallDir = Join-Path (Split-Path -Parent $PSScriptRoot) $PMeta.InstallDirName
}

$ExePath = Join-Path $InstallDir $PMeta.ExeName
$ConfigPath = Join-Path $InstallDir $PMeta.ConfigFile
$LogPath = Join-Path $InstallDir 'logs\main.log'

# Default models per provider
$script:DefaultModels = @{
    cliproxy = @{ Opus = 'gpt-5.5'; Sonnet = 'gpt-5.4'; Haiku = 'gpt-5.4' }
    occ = @{ Opus = 'deepseek-v4-pro'; Sonnet = 'deepseek-v4-pro'; Haiku = 'deepseek-v4-flash' }
}

if (-not $PSBoundParameters.ContainsKey('OpusModel')) { $OpusModel = $script:DefaultModels[$Provider].Opus }
if (-not $PSBoundParameters.ContainsKey('SonnetModel')) { $SonnetModel = $script:DefaultModels[$Provider].Sonnet }
if (-not $PSBoundParameters.ContainsKey('HaikuModel')) { $HaikuModel = $script:DefaultModels[$Provider].Haiku }

# ============================================================
# Dot-source provider scripts
# ============================================================
$ProviderDir = Join-Path $PSScriptRoot 'providers'
. (Join-Path $ProviderDir 'cliproxy.ps1')
. (Join-Path $ProviderDir 'occ.ps1')

# ============================================================
# Utility functions (shared, provider-agnostic)
# ============================================================
function Write-Step([string]$Message) { Write-Host ("`n>> " + $Message) -ForegroundColor Cyan }
function Write-OK([string]$Message) { Write-Host ("    [OK] " + $Message) -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host ("    [!!] " + $Message) -ForegroundColor Yellow }
function Write-Fail([string]$Message) { Write-Host ("    [X] " + $Message) -ForegroundColor Red }
function Write-Info([string]$Message) { Write-Host ("    .. " + $Message) -ForegroundColor Gray }

function Get-GitHubReleaseFallback([string]$Repo, [string]$AssetRegex, [string[]]$NameCandidates) {
    try {
        $atom = Invoke-WebRequest -Uri "https://github.com/$Repo/releases.atom" -UseBasicParsing -Headers @{ 'User-Agent' = 'CodexToClaude' } -TimeoutSec 30
        $tagMatch = [regex]::Match($atom.Content, '<link rel="alternate" type="text/html" href="https://github\.com/[^/]+/[^/]+/releases/tag/([^"]+)"')
        if (-not $tagMatch.Success) { return $null }
        $tag = $tagMatch.Groups[1].Value
        $release = [pscustomobject]@{ tag_name = $tag }
        foreach ($candidate in $NameCandidates) {
            $url = "https://github.com/$Repo/releases/download/$tag/$candidate"
            try {
                $response = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -Headers @{ 'User-Agent' = 'CodexToClaude' } -TimeoutSec 15
                if ($response.StatusCode -eq 200) {
                    $asset = [pscustomobject]@{ name = $candidate; browser_download_url = $url }
                    return [pscustomobject]@{ release = $release; asset = $asset }
                }
            } catch { }
        }
    } catch { }
    return $null
}

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
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function ConvertTo-JsonIndent2([object]$InputObject, [int]$MaxDepth) {
    $json = $InputObject | ConvertTo-Json -Depth $MaxDepth
    $lines = $json -split "`r`n"
    $level = 0
    $result = foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '') { continue }
        if ($trimmed -match '^[}\]]') { $level = [Math]::Max(0, $level - 1) }
        $indented = ('  ' * $level) + $trimmed
        if ($trimmed -match '[{\[]$') { $level++ }
        $indented
    }
    return ($result -join "`r`n")
}

function Show-Help {
    Write-Host "CodexToClaude $(Get-ProjectVersion)" -ForegroundColor Cyan
    Write-Host 'Use Codex Plus/Pro and OpenCode Go through local proxies in Claude Code.' -ForegroundColor Gray
    Write-Host ''
    Write-Host 'Commands:'
    Write-Host '  install      Install/update proxy config and optionally download executable'
    Write-Host '  login        Run authentication (Codex OAuth only; OCC uses API key env var)'
    Write-Host '  configure    Write proxy config and merge Claude Code settings.json env values'
    Write-Host '  start        Start the proxy server in background'
    Write-Host '  stop         Stop the proxy server listening on configured port'
    Write-Host '  restart      Stop then start and wait for readiness'
    Write-Host '  status       Show local setup status for current provider'
    Write-Host '  auth-status  Show authentication status for current provider'
    Write-Host '  verify       Verify /v1/models and /v1/messages'
    Write-Host '  doctor       Run status and verify'
    Write-Host '  project-version   Show CodexToClaude VERSION and git status'
    Write-Host '  project-update    Safely update CodexToClaude with git pull --ff-only'
    Write-Host '  cliproxy-version  Show local and latest proxy binary version'
    Write-Host '  cliproxy-update   Stop, update, and restart proxy binary to latest release'
    Write-Host '  models            Show configured Claude model env values'
    Write-Host '  configure-models  Update Claude model env values'
    Write-Host ''
    Write-Host 'Provider selection: -Provider cliproxy|occ (default: cliproxy)' -ForegroundColor Yellow
    Write-Host "  cliproxy  CLIProxyAPI (Codex/OAI)     default port: $($script:ProviderMeta.cliproxy.DefaultPort)"
    Write-Host "  occ       oc-go-cc (OpenCode Go)      default port: $($script:ProviderMeta.occ.DefaultPort)"
    Write-Host ''
    Write-Host 'Required setup values:' -ForegroundColor Yellow
    Write-Host '  -Port      Local proxy listen port. Claude Code uses http://127.0.0.1:<Port>.'
    Write-Host '  -ProxyUrl  Upstream proxy for API access. Example: http://127.0.0.1:7897'
    Write-Host '             If your network can access upstream directly, explicitly use: -ProxyUrl none'
    Write-Host ''
    Write-Host 'Examples:'
    Write-Host '  .\scripts\CodexToClaude.ps1 install -Port 8317 -ProxyUrl "http://127.0.0.1:7897"'
    Write-Host '  .\scripts\CodexToClaude.ps1 install -Provider occ -Port 3456 -ProxyUrl none'
    Write-Host '  .\scripts\CodexToClaude.ps1 login -Device'
    Write-Host '  .\scripts\CodexToClaude.ps1 restart'
}

# ============================================================
# Provider-aware wrapper functions
# ============================================================
function Get-ConfigValue([string]$Name) {
    $func = "$($PMeta.Prefix)-GetConfigValue"
    return & $func $Name
}

function Get-AuthStatus {
    $func = "$($PMeta.Prefix)-GetAuthStatus"
    return & $func
}

# ============================================================
# Shared infrastructure functions
# ============================================================
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
        Write-Host 'ProxyUrl is the upstream proxy used to access API endpoints.' -ForegroundColor Yellow
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

function Resolve-Port([bool]$RequirePrompt) {
    if ($Port -gt 0) {
        if ($InstallDirProvided) {
            $script:InstallDir = $InstallDir
            $script:ExePath = Join-Path $InstallDir $PMeta.ExeName
            $script:ConfigPath = Join-Path $InstallDir $PMeta.ConfigFile
            $script:LogPath = Join-Path $InstallDir 'logs\main.log'
        }
        return $Port
    }
    if (-not $InstallDirProvided) {
        $fromConfig = Get-ConfigValue 'port'
        if ($fromConfig -and ($fromConfig -match '^\d+$')) { return [int]$fromConfig }
    }
    if (-not $RequirePrompt) {
        throw "Missing port. Run configure/install with -Port first. Example: .\scripts\CodexToClaude.ps1 configure -Provider $Provider -Port $($PMeta.DefaultPort) -ProxyUrl http://127.0.0.1:7897"
    }
    while ($true) {
        Write-Host ''
        Write-Host "Port is the local $($PMeta.Name) listen port. Claude Code will call http://127.0.0.1:<Port>." -ForegroundColor Yellow
        Write-Host "Default: $($PMeta.DefaultPort)" -ForegroundColor Gray
        $inputPort = Read-Host 'Enter Port'
        if ($inputPort -match '^\d+$' -and [int]$inputPort -gt 0 -and [int]$inputPort -lt 65536) {
            if ($InstallDirProvided) {
                $script:InstallDir = $InstallDir
                $script:ExePath = Join-Path $InstallDir $PMeta.ExeName
                $script:ConfigPath = Join-Path $InstallDir $PMeta.ConfigFile
                $script:LogPath = Join-Path $InstallDir 'logs\main.log'
            }
            return [int]$inputPort
        }
        Write-Warn 'Port must be a number from 1 to 65535.'
    }
}

function Ensure-InstallDir { if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Force $InstallDir | Out-Null } }

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

function Wait-ServiceReady([int]$ResolvedPort, [int]$TimeoutSeconds, [string]$HealthEndpoint) {
    if (-not $HealthEndpoint) { $HealthEndpoint = $PMeta.HealthEndpoint }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $healthUrl = "http://127.0.0.1:$ResolvedPort$HealthEndpoint"
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

function Write-AuthStatus([object]$Status) {
    if ($Json) {
        $Status | ConvertTo-Json -Depth 8
        return
    }
    if ($Status.status -eq 'logged_in' -or $Status.status -eq 'configured') { Write-OK $Status.message } else { Write-Warn $Status.message }
    foreach ($auth in $Status.auths) {
        $safeEmail = $auth.email
        if (-not $safeEmail) { $safeEmail = '-' }
        Write-Info "auth=$($auth.file) type=$($auth.type) email=$safeEmail disabled=$($auth.disabled) usable=$($auth.usable) issue=$($auth.issue) expires=$($auth.expired)"
    }
    if ($Status.status -ne 'logged_in' -and $Status.status -ne 'configured') {
        Write-Info 'Recommended fixes:'
        foreach ($s in $Status.suggestions) { Write-Info "  - $s" }
    }
}

function Assert-AuthReady {
    $status = Get-AuthStatus
    if (-not $status.usableCount -or $status.usableCount -eq 0) {
        Write-AuthStatus $status
        throw 'No enabled auth found.'
    }
    Write-OK "Enabled auth: $($status.usableCount)"
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
    Set-JsonProperty $settings.env 'ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME' ($HaikuModel -replace '\(.*\)$', '')
    if ($Provider -eq 'occ') {
        Set-JsonProperty $settings.env 'CLAUDE_CODE_EFFORT_LEVEL' 'max'
    } else {
        Remove-JsonProperty $settings.env 'CLAUDE_CODE_EFFORT_LEVEL'
    }
    Remove-JsonProperty $settings.env 'ANTHROPIC_MODEL'
    $outJson = ConvertTo-JsonIndent2 $settings 20
    Write-FileUtf8NoBom $ClaudeSettingsPath ($outJson + "`n")
    Write-OK "Updated: $ClaudeSettingsPath  (provider=$Provider, port=$ResolvedPort)"
}

function Get-InvokeModels {
    $func = "$($PMeta.Prefix)-InvokeModels"
    return & $func $args[0]
}

function Get-InvokeMessage {
    $func = "$($PMeta.Prefix)-InvokeMessage"
    return & $func $args[0] $SonnetModel
}

function Test-ClaudeStreamJson([int]$ResolvedPort) {
    if ($SkipClaudeStreamCheck) { return }
    $claude = Get-Command claude.exe -ErrorAction SilentlyContinue
    if (-not $claude) {
        Write-Warn 'claude.exe not found; skipping Claude Code stream-json check.'
        return
    }
    $origToken = $env:ANTHROPIC_AUTH_TOKEN
    $origUrl = $env:ANTHROPIC_BASE_URL
    $origModel = $env:ANTHROPIC_DEFAULT_SONNET_MODEL
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
        $env:ANTHROPIC_AUTH_TOKEN = $origToken
        $env:ANTHROPIC_BASE_URL = $origUrl
        $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $origModel
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
    $showDetail = "$($PMeta.Prefix)-ShowStatusDetail"
    & $showDetail $ResolvedPort
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
            else { Write-Warn "Claude Code base URL: $baseUrl (does not match port $ResolvedPort)" }
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
    $startFunc = "$($PMeta.Prefix)-StartProcess"
    & $startFunc $ResolvedPort
    $models = Get-InvokeModels $ResolvedPort
    $modelCount = 0
    if ($models.data) { $modelCount = @($models.data).Count }
    if ($modelCount -eq 0) { throw '/v1/models returned no models.' }
    Write-OK "/v1/models returned $modelCount models"
    $message = Get-InvokeMessage $ResolvedPort
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

# ============================================================
# Project management functions (shared)
# ============================================================
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

# ============================================================
# Claude Code settings functions (shared)
# ============================================================
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
    $outJson = ConvertTo-JsonIndent2 $settings 20
    Write-FileUtf8NoBom $ClaudeSettingsPath ($outJson + "`n")
    Write-OK "Updated model settings: $ClaudeSettingsPath"
}

# ============================================================
# Command dispatch
# ============================================================
switch ($Command) {
    'help' { Show-Help }

    'install' {
        if ($Provider -eq 'cliproxy') { CLIProxy-MoveLegacyInstall }
        Ensure-InstallDir
        $resolvedPort = Resolve-Port $true
        $resolvedProxy = Resolve-ProxyUrl $true
        $installFunc = "$($PMeta.Prefix)-InstallBinary"
        & $installFunc
        $writeFunc = "$($PMeta.Prefix)-WriteConfig"
        & $writeFunc $resolvedPort $resolvedProxy
        Write-OK 'Install/config step complete. Run login, configure, restart, verify next.'
    }

    'login' {
        if (-not $PMeta.SupportsLogin) {
            throw "Provider '$($PMeta.Name)' does not support OAuth login. Set the API key via environment variable or config."
        }
        if ($Provider -eq 'cliproxy') { CLIProxy-MoveLegacyInstall }
        Ensure-InstallDir
        if (-not (Test-Path $ExePath)) {
            $installFunc = "$($PMeta.Prefix)-InstallBinary"
            & $installFunc
        }
        if (-not (Test-Path $ConfigPath)) { Write-Warn 'Config is missing. Run install/configure first if login fails.' }
        $loginArg = '-codex-login'
        if ($Device) { $loginArg = '-codex-device-login' }
        try {
            & $ExePath -config $ConfigPath $loginArg
            if ($LASTEXITCODE -ne 0) {
                throw "Login command exited with code $LASTEXITCODE. Check logs for details."
            }
        } catch {
            Write-Fail "Login command failed: $($_.Exception.Message)"
            $status = Get-AuthStatus
            Write-AuthStatus $status
            throw
        }
        $status = Get-AuthStatus
        Write-AuthStatus $status
        if ($status.status -ne 'logged_in') { throw 'Login finished but no usable auth was found.' }
    }

    'configure' {
        $resolvedPort = Resolve-Port $true
        $resolvedProxy = Resolve-ProxyUrl $true
        Ensure-InstallDir
        $writeFunc = "$($PMeta.Prefix)-WriteConfig"
        & $writeFunc $resolvedPort $resolvedProxy
        Configure-Claude $resolvedPort
    }

    'start' {
        if ($Provider -eq 'cliproxy') { CLIProxy-MoveLegacyInstall }
        $resolvedPort = Resolve-Port $false
        $startFunc = "$($PMeta.Prefix)-StartProcess"
        & $startFunc $resolvedPort
    }

    'stop' {
        $resolvedPort = Resolve-Port $false
        $stopFunc = "$($PMeta.Prefix)-StopProcess"
        & $stopFunc $resolvedPort
    }

    'restart' {
        if ($Provider -eq 'cliproxy') { CLIProxy-MoveLegacyInstall }
        $resolvedPort = Resolve-Port $false
        $stopFunc = "$($PMeta.Prefix)-StopProcess"
        $startFunc = "$($PMeta.Prefix)-StartProcess"
        & $stopFunc $resolvedPort
        & $startFunc $resolvedPort
    }

    'status' {
        if ($Provider -eq 'cliproxy') { CLIProxy-MoveLegacyInstall }
        $resolvedPort = Resolve-Port $false
        Show-Status $resolvedPort
    }

    'auth-status' {
        $status = Get-AuthStatus
        Write-AuthStatus $status
        if ($status.status -ne 'logged_in' -and $status.status -ne 'configured') { exit 1 }
    }

    'verify' {
        if ($Provider -eq 'cliproxy') { CLIProxy-MoveLegacyInstall }
        $resolvedPort = Resolve-Port $false
        Verify-Setup $resolvedPort
    }

    'doctor' {
        if ($Provider -eq 'cliproxy') { CLIProxy-MoveLegacyInstall }
        $resolvedPort = Resolve-Port $false
        Show-Status $resolvedPort
        Verify-Setup $resolvedPort
    }

    'project-version' { Show-ProjectVersion }
    'project-update' { Update-Project }

    'cliproxy-version' {
        $showFunc = "$($PMeta.Prefix)-ShowVersion"
        & $showFunc
    }

    'cliproxy-update' {
        $updateFunc = "$($PMeta.Prefix)-UpdateBinary"
        & $updateFunc
    }

    'models' { Show-ClaudeModels }
    'configure-models' { Configure-ClaudeModels }
}
