# oc-go-cc (OpenCode Go) provider functions
# Dot-sourced by CodexToClaude.ps1; accesses script-scope $InstallDir, $ExePath, $ConfigPath, $ApiKey
# oc-go-cc repo: https://github.com/samueltuyizere/oc-go-cc

$script:OCCMinVersion = [Version]'0.1.5'

function OCC-GetBinaryVersion {
    if (-not (Test-Path $ExePath)) { return $null }
    try {
        $output = & $ExePath --version 2>&1
        if ($LASTEXITCODE -eq 0 -and $output) {
            if ($output -match '(\d+\.\d+\.\d+)') {
                return [Version]$matches[1]
            }
        }
    } catch { }
    $info = (Get-Item $ExePath).VersionInfo
    if ($info.ProductVersion -and $info.ProductVersion -match '(\d+\.\d+\.\d+)') {
        return [Version]$matches[1]
    }
    if ($info.FileVersion -and $info.FileVersion -match '(\d+\.\d+\.\d+)') {
        return [Version]$matches[1]
    }
    return $null
}

function OCC-GetLatestRelease {
    # Primary: non-API approach (no auth required, works without GH_TOKEN)
    $result = Get-GitHubReleaseFallback 'samueltuyizere/oc-go-cc' '(windows|win).*\.(zip|exe)$' @('oc-go-cc_windows-amd64.exe', 'oc-go-cc_windows-arm64.exe', 'oc-go-cc.exe', 'oc-go-cc-windows-amd64.exe', 'oc-go-cc-windows-amd64.zip')
    if ($result) { return $result }

    # Fallback: GitHub API (may need GH_TOKEN to avoid rate limits)
    $headers = @{ 'User-Agent' = 'CodexToClaude' }
    if ($env:GH_TOKEN) { $headers['Authorization'] = "Bearer $env:GH_TOKEN" }
    elseif ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }
    try {
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/samueltuyizere/oc-go-cc/releases/latest' -UseBasicParsing -Headers $headers -TimeoutSec 30
        $asset = $release.assets | Where-Object { $_.name -match '(windows|win)' -and $_.name -match '\.(zip|exe)$' } | Select-Object -First 1
        if (-not $asset) { throw 'No Windows asset found in latest oc-go-cc release.' }
        return [pscustomobject]@{ release = $release; asset = $asset }
    } catch {
        throw "GitHub API request failed: $($_.Exception.Message). Set GH_TOKEN env var to avoid rate limits, or download manually."
    }
}

function OCC-InstallAsset([string]$DownloadUrl, [string]$AssetName, [string]$DestinationPath) {
    Ensure-InstallDir
    $downloadPath = Join-Path $InstallDir $AssetName
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $downloadPath -UseBasicParsing
    if ($downloadPath -match '\.exe$') {
        Move-Item -Force $downloadPath $DestinationPath
    } else {
        $extractDir = Join-Path $InstallDir 'download-extract'
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
        Expand-Archive -Path $downloadPath -DestinationPath $extractDir -Force
        $exe = Get-ChildItem $extractDir -Recurse -Filter 'oc-go-cc.exe' | Select-Object -First 1
        if (-not $exe) { throw 'Downloaded archive does not contain oc-go-cc.exe.' }
        Copy-Item -Force $exe.FullName $DestinationPath
        Remove-Item $extractDir -Recurse -Force
        Remove-Item $downloadPath -Force
    }
}

function OCC-InstallBinary {
    if (Test-Path $ExePath) {
        Write-OK "oc-go-cc.exe exists: $ExePath"
        return
    }
    Write-Step 'Downloading oc-go-cc latest release'
    try {
        $latest = OCC-GetLatestRelease
        $downloadUrl = $latest.asset.browser_download_url
        $assetName = $latest.asset.name
        Write-Info "Latest: $($latest.release.tag_name)  Asset: $assetName"
        OCC-InstallAsset $downloadUrl $assetName $ExePath
        Write-OK "Downloaded: $ExePath"
    } catch {
        Write-Fail "Automatic download failed: $($_.Exception.Message)"
        Write-Info 'You can still proceed. Download the asset manually:'
        Write-Info '  1. Open https://github.com/samueltuyizere/oc-go-cc/releases/latest'
        Write-Info '  2. Download the Windows asset'
        Write-Info "  3. Place oc-go-cc.exe at: $ExePath"
        Write-Info '  4. Set GH_TOKEN env var (optional) to avoid GitHub API rate limits'
    }
}

function OCC-WriteConfig([int]$ResolvedPort, [string]$ResolvedProxyUrl) {
    $key = if ($ApiKey -and $ApiKey -ne 'sk-cliproxy-local-dev-2026') { $ApiKey } else { '${OC_GO_CC_API_KEY}' }
    $config = [ordered]@{
        host = '127.0.0.1'
        port = $ResolvedPort
        api_key = $key
        pid_file = (Join-Path $InstallDir 'oc-go-cc.pid')
        hot_reload = $false
        respect_requested_model = $true
        models = [ordered]@{
            'deepseek-v4-pro' = [ordered]@{
                provider = 'opencode-go'
                model_id = 'deepseek-v4-pro'
                temperature = 0.7
                max_tokens = 384000
                reasoning_effort = 'max'
                thinking = [ordered]@{ type = 'enabled' }
            }
            'deepseek-v4-flash' = [ordered]@{
                provider = 'opencode-go'
                model_id = 'deepseek-v4-flash'
                temperature = 0.5
                max_tokens = 384000
                reasoning_effort = 'max'
                thinking = [ordered]@{ type = 'enabled' }
            }
            default = [ordered]@{
                provider = 'opencode-go'
                model_id = 'deepseek-v4-pro'
                temperature = 0.7
                max_tokens = 4096
                reasoning_effort = 'max'
                thinking = [ordered]@{ type = 'enabled' }
            }
            background = [ordered]@{
                provider = 'opencode-go'
                model_id = 'deepseek-v4-pro'
                temperature = 0.5
                max_tokens = 2048
                reasoning_effort = 'max'
                thinking = [ordered]@{ type = 'enabled' }
            }
            think = [ordered]@{
                provider = 'opencode-go'
                model_id = 'deepseek-v4-pro'
                temperature = 0.7
                max_tokens = 8192
                reasoning_effort = 'max'
                thinking = [ordered]@{ type = 'enabled' }
            }
            complex = [ordered]@{
                provider = 'opencode-go'
                model_id = 'deepseek-v4-pro'
                temperature = 0.7
                max_tokens = 4096
                reasoning_effort = 'max'
                thinking = [ordered]@{ type = 'enabled' }
            }
            long_context = [ordered]@{
                provider = 'opencode-go'
                model_id = 'deepseek-v4-pro'
                temperature = 0.7
                max_tokens = 16384
                context_threshold = 1000000
                reasoning_effort = 'max'
                thinking = [ordered]@{ type = 'enabled' }
            }
            fast = [ordered]@{
                provider = 'opencode-go'
                model_id = 'deepseek-v4-pro'
                temperature = 0.7
                max_tokens = 4096
                reasoning_effort = 'max'
                thinking = [ordered]@{ type = 'enabled' }
            }
        }
        fallbacks = [ordered]@{
            default = @(
                [ordered]@{ provider = 'opencode-go'; model_id = 'deepseek-v4-pro'; reasoning_effort = 'max'; thinking = [ordered]@{ type = 'enabled' } }
                [ordered]@{ provider = 'opencode-go'; model_id = 'deepseek-v4-pro'; reasoning_effort = 'max'; thinking = [ordered]@{ type = 'enabled' } }
            )
            think = @(
                [ordered]@{ provider = 'opencode-go'; model_id = 'deepseek-v4-pro'; reasoning_effort = 'max'; thinking = [ordered]@{ type = 'enabled' } }
            )
            complex = @(
                [ordered]@{ provider = 'opencode-go'; model_id = 'deepseek-v4-pro'; reasoning_effort = 'max'; thinking = [ordered]@{ type = 'enabled' } }
            )
            long_context = @(
                [ordered]@{ provider = 'opencode-go'; model_id = 'deepseek-v4-pro'; reasoning_effort = 'max'; thinking = [ordered]@{ type = 'enabled' } }
            )
            fast = @(
                [ordered]@{ provider = 'opencode-go'; model_id = 'deepseek-v4-pro'; reasoning_effort = 'max'; thinking = [ordered]@{ type = 'enabled' } }
            )
        }
        opencode_go = [ordered]@{
            base_url = 'https://opencode.ai/zen/go/v1/chat/completions'
            timeout_ms = 300000
        }
        logging = [ordered]@{
            level = 'info'
            requests = $true
        }
    }
    if ($ResolvedProxyUrl -ne '') {
        $config.proxy_url = $ResolvedProxyUrl
    }
    $dir = Split-Path -Parent $ConfigPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $json = $config | ConvertTo-Json -Depth 10
    Write-FileUtf8NoBom $ConfigPath $json
    Write-OK "Wrote oc-go-cc config: $ConfigPath"
    $binVer = OCC-GetBinaryVersion
    if ($null -eq $binVer) {
        if (Test-Path $ExePath) {
            Write-Warn "Cannot determine oc-go-cc version. respect_requested_model requires v$($script:OCCMinVersion) or later."
        }
    } elseif ($binVer -lt $script:OCCMinVersion) {
        Write-Warn "oc-go-cc $binVer is too old. respect_requested_model requires v$($script:OCCMinVersion) or later. Run cliproxy-update to update."
    }
}

function OCC-GetConfigValue([string]$Name) {
    if (-not (Test-Path $ConfigPath)) { return $null }
    try {
        $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $propName = $Name
        if ($Name -eq 'proxy-url') { $propName = 'proxy_url' }
        $prop = $config.PSObject.Properties[$propName]
        if ($prop) { return $prop.Value }
    } catch { }
    return $null
}

function OCC-GetAuthStatus {
    $keyFromEnv = $env:OC_GO_CC_API_KEY
    $keyFromConfig = $null
    if (Test-Path $ConfigPath) {
        try {
            $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $rawKey = $config.api_key
            if ($rawKey -and $rawKey -ne 'YOUR_OPENCODE_API_KEY' -and $rawKey -ne '${OC_GO_CC_API_KEY}') { $keyFromConfig = $rawKey }
        } catch { }
    }
    $hasKey = ($keyFromEnv -or $keyFromConfig)
    if ($hasKey) {
        $source = if ($keyFromEnv) { 'environment' } else { 'config.json' }
        return [pscustomobject]@{
            status = 'configured'
            message = "API key found in $source"
            authCount = 1
            usableCount = 1
            auths = @([pscustomobject]@{ file = $source; validJson = $true; type = 'api_key'; email = '-'; expired = $null; disabled = $false; usable = $true; issue = $null })
            suggestions = @()
        }
    }
    return [pscustomobject]@{
        status = 'not_configured'
        message = 'No API key configured. Enter your OpenCode Go key in the ApiKey field and run Configure.'
        authCount = 0
        usableCount = 0
        auths = @()
        suggestions = @(
            'Enter your OpenCode Go API key in the ApiKey field and run Configure.',
            'Or set the OC_GO_CC_API_KEY environment variable.'
        )
    }
}

function OCC-StartProcess([int]$ResolvedPort) {
    Write-Step "Starting oc-go-cc on port $ResolvedPort"
    if (-not (Test-Path $ExePath)) { throw "Missing executable: $ExePath" }
    if (-not (Test-Path $ConfigPath)) { throw "Missing config: $ConfigPath" }
    $pidDir = $null
    try {
        $cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $pidFile = $cfg.pid_file
        if ($pidFile) {
            $pidDir = Split-Path -Parent $pidFile
            if (-not (Test-Path $pidDir)) { New-Item -ItemType Directory -Force $pidDir | Out-Null }
        }
    } catch { }
    $defaultPidDir = Join-Path $env:USERPROFILE '.config\oc-go-cc'
    if (-not (Test-Path $defaultPidDir)) { New-Item -ItemType Directory -Force $defaultPidDir | Out-Null }
    $existing = Get-PortProcesses $ResolvedPort
    if ($existing.Count -gt 0) {
        foreach ($proc in $existing) {
            $nameMatch = $proc.ProcessName -eq 'oc-go-cc'
            $pathMatch = $false
            if (-not $nameMatch) {
                try { $pathMatch = ($proc.Path -eq $ExePath) } catch { }
            }
            if (-not ($nameMatch -or $pathMatch)) {
                throw "Port $ResolvedPort is owned by $($proc.ProcessName) pid=$($proc.Id), not oc-go-cc. Refusing to reuse it."
            }
        }
        $health = Test-ServiceHealth $ResolvedPort '/health' 2
        if ($health.Healthy) {
            Write-OK "Port $ResolvedPort is already listening and healthy."
            return
        }
        throw "oc-go-cc is listening on port $ResolvedPort but health check failed: $($health.Error). Run verify or restart to recover."
    }
    $stdout = Join-Path $env:TEMP "occ-start-$([guid]::NewGuid().ToString()).out"
    $stderr = Join-Path $env:TEMP "occ-start-$([guid]::NewGuid().ToString()).err"
    try {
        $proc = Start-Process -FilePath $ExePath -ArgumentList @('serve', '--config', $ConfigPath, '--port', $ResolvedPort) -WorkingDirectory $InstallDir -WindowStyle Minimized -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        Start-Sleep -Milliseconds 500
        if ($proc.HasExited) {
            $errText = ''
            if (Test-Path $stderr) { $errText = Get-Content $stderr -Raw -ErrorAction SilentlyContinue }
            if (-not $errText -and (Test-Path $stdout)) { $errText = Get-Content $stdout -Raw -ErrorAction SilentlyContinue }
            $detail = if ($errText) { "`n$errText" } else { ' (no output captured)' }
            throw "oc-go-cc exited immediately with code $($proc.ExitCode).$detail"
        }
        if (-not (Wait-ServiceReady $ResolvedPort 20 '/health')) {
            $errText = ''
            if (Test-Path $stderr) { $errText = Get-Content $stderr -Raw -ErrorAction SilentlyContinue }
            throw "oc-go-cc did not become ready on port $ResolvedPort.`n$errText"
        }
        Write-OK "Started oc-go-cc pid=$($proc.Id)"
    } finally {
        Remove-Item $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

function OCC-StopProcess([int]$ResolvedPort) {
    Write-Step "Stopping oc-go-cc on port $ResolvedPort"
    $procs = Get-PortProcesses $ResolvedPort
    if ($procs.Count -eq 0) {
        Write-OK 'No process is listening on the target port.'
        return
    }
    foreach ($proc in $procs) {
        $nameMatch = $proc.ProcessName -eq 'oc-go-cc'
        $pathMatch = $false
        if (-not $nameMatch) {
            try { $pathMatch = ($proc.Path -eq $ExePath) } catch { }
        }
        if ($nameMatch -or $pathMatch) {
            Stop-Process -Id $proc.Id -Force -Confirm:$false
            Write-OK "Stopped $($proc.ProcessName) pid=$($proc.Id)"
        } else {
            throw "Port $ResolvedPort is owned by $($proc.ProcessName) pid=$($proc.Id), not oc-go-cc. Refusing to stop it."
        }
    }
    if (-not (Wait-PortFree $ResolvedPort 10)) { throw "Port $ResolvedPort was not released in time." }
}

function OCC-InvokeModels([int]$ResolvedPort) {
    # oc-go-cc does not expose /v1/models; verify server is up via /health
    try {
        $health = Invoke-RestMethod -Uri "http://127.0.0.1:$ResolvedPort/health" -TimeoutSec 10
    } catch {
        throw "oc-go-cc health check failed on port $ResolvedPort. Is the server running?"
    }
    # Return synthetic models list for verify compatibility
    return [pscustomobject]@{ data = @([pscustomobject]@{ id = 'oc-go-cc-proxy' }) }
}

function OCC-InvokeMessage([int]$ResolvedPort, [string]$Model) {
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
    try {
        return Invoke-RestMethod -Uri "http://127.0.0.1:$ResolvedPort/v1/messages" -Method Post -Headers $headers -Body $body -TimeoutSec 120
    } catch [System.Net.WebException] {
        $respBody = ''
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $respBody = $reader.ReadToEnd()
            $reader.Close()
        } catch { }
        throw "/v1/messages failed (model: $Model): $respBody"
    }
}

function OCC-GetLocalVersion {
    if (-not (Test-Path $ExePath)) { return 'missing' }
    $info = (Get-Item $ExePath).VersionInfo
    if ($info.ProductVersion) { return $info.ProductVersion }
    if ($info.FileVersion) { return $info.FileVersion }
    return 'installed'
}

function OCC-ShowVersion {
    Write-Step 'oc-go-cc version'
    Write-Info "Executable: $ExePath"
    Write-Info "Local: $(OCC-GetLocalVersion)"
    try {
        $latest = OCC-GetLatestRelease
        Write-Info "Latest: $($latest.release.tag_name)"
        Write-Info "Asset: $($latest.asset.name)"
    } catch {
        Write-Warn "Unable to read latest release: $($_.Exception.Message)"
    }
}

function OCC-UpdateBinary {
    Write-Step 'Updating oc-go-cc to latest release'
    Ensure-InstallDir
    $resolvedPort = $null
    $wasRunning = $false
    try {
        $resolvedPort = Resolve-Port $false
        $wasRunning = ((Get-PortProcesses $resolvedPort).Count -gt 0)
        if ($wasRunning) { OCC-StopProcess $resolvedPort }
    } catch {
        Write-Warn "Could not determine or stop running service: $($_.Exception.Message)"
    }

    $backup = $null
    try {
        $latest = OCC-GetLatestRelease
        $staged = Join-Path $InstallDir 'oc-go-cc.new.exe'
        if (Test-Path $staged) { Remove-Item $staged -Force }
        OCC-InstallAsset $latest.asset.browser_download_url $latest.asset.name $staged
        if (-not (Test-Path $staged)) { throw 'Downloaded oc-go-cc executable was not created.' }
        if (Test-Path $ExePath) {
            $backup = Join-Path $InstallDir "oc-go-cc.backup-$(Get-Date -Format 'yyyyMMddHHmmss').exe"
            Copy-Item -Force $ExePath $backup
            Write-Info "Backup: $backup"
            Remove-Item $ExePath -Force
        }
        Move-Item $staged $ExePath
        Write-OK "Updated oc-go-cc to latest release: $($latest.release.tag_name)"
    } catch {
        Write-Fail "Download or install failed: $($_.Exception.Message)"
        if ($backup -and (Test-Path $backup)) {
            Copy-Item -Force $backup $ExePath
            Write-Warn 'Restored previous oc-go-cc.exe after update failure.'
        }
        if ($wasRunning -and $null -ne $resolvedPort) {
            try { OCC-StartProcess $resolvedPort } catch {
                Write-Warn "Could not restart service after update failure: $($_.Exception.Message)"
            }
        }
        throw
    }

    if ($wasRunning -and $null -ne $resolvedPort) {
        try {
            OCC-StartProcess $resolvedPort
        } catch {
            if ($backup -and (Test-Path $backup)) {
                Copy-Item -Force $backup $ExePath
                Write-Warn 'Restored previous oc-go-cc.exe after restart failure.'
            }
            throw
        }
    }
}

function OCC-ShowStatusDetail([int]$ResolvedPort) {
    if (Test-Path $ExePath) { Write-OK "Executable: $ExePath" } else { Write-Fail "Executable missing: $ExePath" }
    if (Test-Path $ConfigPath) { Write-OK "Config: $ConfigPath" } else { Write-Fail "Config missing: $ConfigPath" }
}
