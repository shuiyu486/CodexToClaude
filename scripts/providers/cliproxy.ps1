# CLIProxyAPI provider functions
# Dot-sourced by CodexToClaude.ps1; accesses script-scope $InstallDir, $ExePath, $ConfigPath, $ApiKey, $LogPath

function CLIProxy-MoveLegacyInstall {
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

function CLIProxy-GetLatestRelease {
    # Primary: non-API approach (no auth required, works without GH_TOKEN)
    $result = Get-GitHubReleaseFallback 'router-for-me/CLIProxyAPI' '(windows|win).*(amd64|x64|x86_64).*\.(zip|exe)$' @('cli-proxy-api.exe', 'cli-proxy-api-windows-amd64.exe', 'CLIProxyAPI-windows-amd64.exe', 'cli-proxy-api-windows-amd64.zip', 'CLIProxyAPI-windows-amd64.zip', 'CLIProxyAPI_windows_amd64.zip')
    if ($result) { return $result }

    # Fallback: GitHub API (may need GH_TOKEN to avoid rate limits)
    $headers = @{ 'User-Agent' = 'CodexToClaude' }
    if ($env:GH_TOKEN) { $headers['Authorization'] = "Bearer $env:GH_TOKEN" }
    elseif ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }
    try {
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest' -UseBasicParsing -Headers $headers -TimeoutSec 30
        $asset = $release.assets | Where-Object { $_.name -match '(windows|win)' -and $_.name -match '(amd64|x64|x86_64)' -and $_.name -match '\.(zip|exe)$' } | Select-Object -First 1
        if (-not $asset) { throw 'No Windows x64/amd64 asset found in latest release.' }
        return [pscustomobject]@{ release = $release; asset = $asset }
    } catch {
        throw "GitHub API request failed: $($_.Exception.Message). Set GH_TOKEN env var to avoid rate limits, or download manually."
    }
}

function CLIProxy-InstallAsset([string]$DownloadUrl, [string]$AssetName, [string]$DestinationPath) {
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

function CLIProxy-InstallBinary {
    if (Test-Path $ExePath) {
        CLIProxy-UpdateBinary
        return
    }
    Write-Step 'Downloading CLIProxyAPI latest release'
    try {
        $latest = CLIProxy-GetLatestRelease
        $downloadUrl = $latest.asset.browser_download_url
        $assetName = $latest.asset.name
        Write-Info "Latest: $($latest.release.tag_name)  Asset: $assetName"
        CLIProxy-InstallAsset $downloadUrl $assetName $ExePath
        Write-OK "Downloaded: $ExePath"
    } catch {
        Write-Fail "Automatic download failed: $($_.Exception.Message)"
        Write-Info 'You can still proceed. Download the asset manually:'
        Write-Info '  1. Open https://github.com/router-for-me/CLIProxyAPI/releases/latest'
        Write-Info '  2. Download the Windows x64/amd64 asset'
        Write-Info "  3. Place cli-proxy-api.exe at: $ExePath"
        Write-Info '  4. Set GH_TOKEN env var (optional) to avoid GitHub API rate limits'
    }
}

function CLIProxy-SyncAuthMetadata([string]$ResolvedProxyUrl, [bool]$SyncProxyUrl) {
    Ensure-InstallDir
    $updated = 0
    foreach ($file in (Get-ChildItem $InstallDir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try {
            $auth = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($auth.type -ne 'codex' -or $auth.disabled -eq $true) { continue }
            if ($SyncProxyUrl) {
                if ($ResolvedProxyUrl) {
                    Set-JsonProperty $auth 'proxy_url' $ResolvedProxyUrl
                } else {
                    Remove-JsonProperty $auth 'proxy_url'
                }
            }
            if (-not $auth.PSObject.Properties['websockets']) {
                Set-JsonProperty $auth 'websockets' $true
            }
            Write-FileUtf8NoBom $file.FullName (ConvertTo-JsonIndent2 $auth 20)
            $updated++
        } catch { }
    }
    if ($updated -gt 0) { Write-OK "Synced Codex OAuth metadata on $updated auth file(s)." }
}

function CLIProxy-SyncAuthProxyUrl([string]$ResolvedProxyUrl) {
    CLIProxy-SyncAuthMetadata $ResolvedProxyUrl $true
}

function CLIProxy-SyncAuthWebsockets {
    CLIProxy-SyncAuthMetadata '' $false
}

function CLIProxy-WriteConfig([int]$ResolvedPort, [string]$ResolvedProxyUrl) {
    $proxyLine = ''
    if ($ResolvedProxyUrl -ne '') { $proxyLine = "proxy-url: `"$ResolvedProxyUrl`"`n" }
    $safeCodexUserAgent = $CodexUserAgent
    if ([string]::IsNullOrWhiteSpace($safeCodexUserAgent)) {
        $safeCodexUserAgent = 'codex_cli_rs/0.114.0 (Mac OS 14.2.0; x86_64) vscode/1.111.0'
    }
    $safeCodexUserAgent = $safeCodexUserAgent -replace "'", "''"
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

passthrough-headers: true

codex-header-defaults:
  user-agent: '$safeCodexUserAgent'

quota-exceeded:
  switch-project: true
  switch-preview-model: true
  antigravity-credits: false

request-retry: 1
max-retry-credentials: 1
max-retry-interval: 5
streaming:
  bootstrap-retries: 1
  keepalive-seconds: 15
# Keep debug + file logging enabled so CLIProxyAPI v7.1.61+ records Codex backend request IDs.
debug: true
logging-to-file: true
logs-max-total-size-mb: 10
error-logs-max-files: 5
"@
    Write-FileUtf8NoBom $ConfigPath $content
    CLIProxy-SyncAuthProxyUrl $ResolvedProxyUrl
    Write-OK "Wrote config: $ConfigPath"
}

function CLIProxy-GetConfigValue([string]$Name) {
    if (-not (Test-Path $ConfigPath)) { return $null }
    $raw = Get-Content $ConfigPath -Raw -Encoding UTF8
    $escaped = [regex]::Escape($Name)
    $m = [regex]::Match($raw, "(?m)^$escaped\s*:\s*`"?([^`"\r\n#]+)`"?\s*$")
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return $null
}

function CLIProxy-GetRiskDiagnostics {
    $items = @()
    if (-not (Test-Path $ConfigPath)) { return @([pscustomobject]@{ Level = 'warn'; Message = "CLIProxy config missing: $ConfigPath" }) }
    $raw = Get-Content $ConfigPath -Raw -Encoding UTF8

    $requestRetry = CLIProxy-GetConfigValue 'request-retry'
    if ($requestRetry -and [int]$requestRetry -gt 1) { $items += [pscustomobject]@{ Level = 'warn'; Message = "request-retry=$requestRetry may make upstream failures look like hangs; recommended value is 1." } }

    $maxRetryCredentials = CLIProxy-GetConfigValue 'max-retry-credentials'
    if (-not $maxRetryCredentials) { $items += [pscustomobject]@{ Level = 'warn'; Message = 'max-retry-credentials is missing; recommended value is 1.' } }
    elseif ([int]$maxRetryCredentials -gt 1) { $items += [pscustomobject]@{ Level = 'warn'; Message = "max-retry-credentials=$maxRetryCredentials may extend failures across credentials; recommended value is 1." } }

    $maxRetryInterval = CLIProxy-GetConfigValue 'max-retry-interval'
    if ($maxRetryInterval -and [int]$maxRetryInterval -gt 5) { $items += [pscustomobject]@{ Level = 'warn'; Message = "max-retry-interval=$maxRetryInterval may delay failure visibility; recommended value is 5." } }

    if ($raw -match '(?m)^\s*bootstrap-retries:\s*(\d+)') {
        if ([int]$matches[1] -gt 1) { $items += [pscustomobject]@{ Level = 'warn'; Message = "streaming.bootstrap-retries=$($matches[1]) may delay stream failures; recommended value is 1." } }
    } else {
        $items += [pscustomobject]@{ Level = 'warn'; Message = 'streaming.bootstrap-retries is missing; recommended value is 1.' }
    }

    if ($raw -notmatch '(?m)^\s*antigravity-credits:\s*false\s*$') {
        $items += [pscustomobject]@{ Level = 'warn'; Message = 'quota-exceeded.antigravity-credits should be false to avoid unexpected fallback paths.' }
    }

    $debug = CLIProxy-GetConfigValue 'debug'
    if ($debug -ne 'true') { $items += [pscustomobject]@{ Level = 'warn'; Message = 'debug should be true so CLIProxyAPI records Codex backend request IDs for diagnostics.' } }

    $loggingToFile = CLIProxy-GetConfigValue 'logging-to-file'
    if ($loggingToFile -ne 'true') { $items += [pscustomobject]@{ Level = 'warn'; Message = 'logging-to-file should be true so Codex backend request IDs are kept in logs/main.log.' } }

    $logsMaxTotalSizeMb = CLIProxy-GetConfigValue 'logs-max-total-size-mb'
    if (-not $logsMaxTotalSizeMb) { $items += [pscustomobject]@{ Level = 'warn'; Message = 'logs-max-total-size-mb is missing; recommended value is 10.' } }
    elseif ([int]$logsMaxTotalSizeMb -le 0) { $items += [pscustomobject]@{ Level = 'warn'; Message = "logs-max-total-size-mb=$logsMaxTotalSizeMb disables log cleanup; recommended value is 10." } }

    $errorLogsMaxFiles = CLIProxy-GetConfigValue 'error-logs-max-files'
    if (-not $errorLogsMaxFiles) { $items += [pscustomobject]@{ Level = 'warn'; Message = 'error-logs-max-files is missing; recommended value is 5.' } }
    elseif ([int]$errorLogsMaxFiles -le 0) { $items += [pscustomobject]@{ Level = 'warn'; Message = "error-logs-max-files=$errorLogsMaxFiles disables error log cleanup; recommended value is 5." } }

    if ($raw -match 'payload:\s*[\s\S]*filter:') {
        $items += [pscustomobject]@{ Level = 'warn'; Message = 'payload.filter is present; CLIProxy defaults to passing through reasoning/thinking/effort parameters. Keep this legacy filter only if you intentionally want local request rewriting.' }
    }

    $configProxy = Read-ConfigProxyUrl
    if ($configProxy) {
        foreach ($file in (CLIProxy-GetAuthFiles)) {
            try {
                $auth = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($auth.type -eq 'codex' -and $auth.disabled -ne $true -and $auth.proxy_url -and $auth.proxy_url -ne $configProxy) {
                    $items += [pscustomobject]@{ Level = 'warn'; Message = "Auth file $($file.Name) proxy_url differs from config proxy-url." }
                }
            } catch { }
        }
    }
    return $items
}

function CLIProxy-GetAuthFiles {
    if (-not (Test-Path $InstallDir)) { return @() }
    return @(Get-ChildItem $InstallDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'settings|test|temp|^codextoclaude-' })
}

function CLIProxy-GetAuthStatus {
    $authFiles = CLIProxy-GetAuthFiles
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

function Read-ConfigProxyUrl {
    if (-not (Test-Path $ConfigPath)) { return $null }
    try {
        $yaml = Get-Content $ConfigPath -Raw -Encoding UTF8
        if ($yaml -match 'proxy-url:\s*"([^"]+)"') { return $matches[1] }
        if ($yaml -match "proxy-url:\s*'([^']+)'") { return $matches[1] }
    } catch { }
    return $null
}

function CLIProxy-StartProcess([int]$ResolvedPort) {
    Write-Step "Starting CLIProxyAPI on port $ResolvedPort"
    if (-not (Test-Path $ExePath)) { throw "Missing executable: $ExePath" }
    if (-not (Test-Path $ConfigPath)) { throw "Missing config: $ConfigPath" }
    $existing = Get-PortProcesses $ResolvedPort
    if ($existing.Count -gt 0) {
        foreach ($proc in $existing) {
            $nameMatch = $proc.ProcessName -eq 'cli-proxy-api'
            $pathMatch = $false
            if (-not $nameMatch) {
                try { $pathMatch = ($proc.Path -eq $ExePath) } catch { }
            }
            if (-not ($nameMatch -or $pathMatch)) {
                throw "Port $ResolvedPort is owned by $($proc.ProcessName) pid=$($proc.Id), not cli-proxy-api. Refusing to reuse it."
            }
        }
        $health = Test-ServiceHealth $ResolvedPort '/healthz' 2
        if ($health.Healthy) {
            Write-OK "Port $ResolvedPort is already listening and healthy."
            Start-ProviderWatchdog $ResolvedPort
            return
        }
        $tail = Get-SafeLogTail $LogPath 30
        $detail = if ($tail) { "`nRecent CLIProxy log:`n$tail" } else { '' }
        throw "CLIProxyAPI is listening on port $ResolvedPort but health check failed: $($health.Error). Run verify or restart to recover.$detail"
    }
    $stderr = Join-Path $env:TEMP "cliproxystart-$([guid]::NewGuid().ToString()).err"
    $prevHttpsProxy = [Environment]::GetEnvironmentVariable('HTTPS_PROXY')
    $prevHttpProxy = [Environment]::GetEnvironmentVariable('HTTP_PROXY')
    try {
        # Read proxy-url from config and inject as env vars so Go net/http can use it
        $cfgProxy = Read-ConfigProxyUrl
        if ($cfgProxy) {
            $env:HTTPS_PROXY = $cfgProxy
            $env:HTTP_PROXY = $cfgProxy
            Write-Info "Proxy injected: $cfgProxy"
        }
        $proc = Start-Process -FilePath $ExePath -ArgumentList @('-config', $ConfigPath) -WorkingDirectory $InstallDir -WindowStyle Minimized -PassThru -RedirectStandardError $stderr
        Start-Sleep -Milliseconds 500
        if ($proc.HasExited) {
            $errText = ''
            if (Test-Path $stderr) { $errText = Get-Content $stderr -Raw -ErrorAction SilentlyContinue }
            $detail = if ($errText) { "`n$errText" } else { ' (no output captured)' }
            throw "cli-proxy-api exited immediately with code $($proc.ExitCode).$detail"
        }
        if (-not (Wait-ServiceReady $ResolvedPort 20 '/healthz')) {
            $tail = ''
            if (Test-Path $stderr) { $tail = Get-SafeTextTail (Get-Content $stderr -Raw -ErrorAction SilentlyContinue) 30 }
            if (-not $tail -and (Test-Path $LogPath)) { $tail = Get-SafeLogTail $LogPath 30 }
            throw "CLIProxyAPI did not become ready on port $ResolvedPort.`n$tail"
        }
        Write-OK "Started cli-proxy-api pid=$($proc.Id)"
        Start-ProviderWatchdog $ResolvedPort
    } finally {
        Remove-Item $stderr -Force -ErrorAction SilentlyContinue
        $env:HTTPS_PROXY = $prevHttpsProxy
        $env:HTTP_PROXY = $prevHttpProxy
    }
}

function CLIProxy-StopProcess([int]$ResolvedPort) {
    Write-Step "Stopping CLIProxyAPI on port $ResolvedPort"
    Stop-ProviderWatchdog
    $procs = Get-PortProcesses $ResolvedPort
    if ($procs.Count -eq 0) {
        Write-OK 'No process is listening on the target port.'
        return
    }
    foreach ($proc in $procs) {
        $nameMatch = $proc.ProcessName -eq 'cli-proxy-api'
        $pathMatch = $false
        if (-not $nameMatch) {
            try { $pathMatch = ($proc.Path -eq $ExePath) } catch { }
        }
        if ($nameMatch -or $pathMatch) {
            Stop-Process -Id $proc.Id -Force -Confirm:$false
            Write-OK "Stopped $($proc.ProcessName) pid=$($proc.Id)"
        } else {
            throw "Port $ResolvedPort is owned by $($proc.ProcessName) pid=$($proc.Id), not cli-proxy-api. Refusing to stop it."
        }
    }
    if (-not (Wait-PortFree $ResolvedPort 10)) { throw "Port $ResolvedPort was not released in time." }
}

function CLIProxy-InvokeModels([int]$ResolvedPort) {
    $headers = @{ Authorization = "Bearer $ApiKey" }
    return Invoke-RestMethod -Uri "http://127.0.0.1:$ResolvedPort/v1/models" -Headers $headers -TimeoutSec 30
}

function CLIProxy-InvokeMessage([int]$ResolvedPort, [string]$Model) {
    $headers = @{
        'x-api-key' = $ApiKey
        'anthropic-version' = '2023-06-01'
        'Content-Type' = 'application/json'
    }
    $body = @{
        model = $Model
        max_tokens = 30
        messages = @(@{ role = 'user'; content = 'say hi in one word' })
    } | ConvertTo-Json -Depth 10
    return Invoke-RestMethod -Uri "http://127.0.0.1:$ResolvedPort/v1/messages" -Method Post -Headers $headers -Body $body -TimeoutSec 120
}

function CLIProxy-GetLocalVersion {
    if (-not (Test-Path $ExePath)) { return 'missing' }
    $info = (Get-Item $ExePath).VersionInfo
    if ($info.ProductVersion) { return $info.ProductVersion }
    if ($info.FileVersion) { return $info.FileVersion }
    return 'installed'
}

function CLIProxy-ShowVersion {
    Write-Step 'CLIProxyAPI version'
    Write-Info "Executable: $ExePath"
    Write-Info "Local: $(CLIProxy-GetLocalVersion)"
    try {
        $latest = CLIProxy-GetLatestRelease
        Write-Info "Latest: $($latest.release.tag_name)"
        Write-Info "Asset: $($latest.asset.name)"
    } catch {
        Write-Warn "Unable to read latest release: $($_.Exception.Message)"
    }
}

function CLIProxy-UpdateBinary {
    Write-Step 'Updating CLIProxyAPI latest release'
    Ensure-InstallDir
    $resolvedPort = $null
    $wasRunning = $false
    try {
        $resolvedPort = Resolve-Port $false
        $wasRunning = ((Get-PortProcesses $resolvedPort).Count -gt 0)
        if ($wasRunning) { CLIProxy-StopProcess $resolvedPort }
    } catch {
        Write-Warn "Could not determine or stop running service: $($_.Exception.Message)"
    }

    $backup = $null
    try {
        $latest = CLIProxy-GetLatestRelease
        $staged = Join-Path $InstallDir 'cli-proxy-api.new.exe'
        if (Test-Path $staged) { Remove-Item $staged -Force }
        CLIProxy-InstallAsset $latest.asset.browser_download_url $latest.asset.name $staged
        if (-not (Test-Path $staged)) { throw 'Downloaded CLIProxyAPI executable was not created.' }
        if (Test-Path $ExePath) {
            $backup = Join-Path $InstallDir "cli-proxy-api.backup-$(Get-Date -Format 'yyyyMMddHHmmss').exe"
            Copy-Item -Force $ExePath $backup
            Write-Info "Backup: $backup"
            Remove-Item $ExePath -Force
        }
        Move-Item $staged $ExePath
        Write-OK "Updated CLIProxyAPI to latest release: $($latest.release.tag_name)"
    } catch {
        Write-Fail "Download or install failed: $($_.Exception.Message)"
        if ($backup -and (Test-Path $backup)) {
            Copy-Item -Force $backup $ExePath
            Write-Warn 'Restored previous cli-proxy-api.exe after update failure.'
        }
        if ($wasRunning -and $null -ne $resolvedPort) {
            try { CLIProxy-StartProcess $resolvedPort } catch {
                Write-Warn "Could not restart service after update failure: $($_.Exception.Message)"
            }
        }
        throw
    }

    if ($wasRunning -and $null -ne $resolvedPort) {
        try {
            CLIProxy-StartProcess $resolvedPort
        } catch {
            if ($backup -and (Test-Path $backup)) {
                Copy-Item -Force $backup $ExePath
                Write-Warn 'Restored previous cli-proxy-api.exe after restart failure.'
            }
            throw
        }
    }
}

function CLIProxy-ShowStatusDetail([int]$ResolvedPort) {
    if (Test-Path $ExePath) { Write-OK "Executable: $ExePath" } else { Write-Fail "Executable missing: $ExePath" }
    if (Test-Path $ConfigPath) { Write-OK "Config: $ConfigPath" } else { Write-Fail "Config missing: $ConfigPath" }
}
