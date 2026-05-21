$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Script = Join-Path $RepoRoot 'scripts\CodexToClaude.ps1'
$UiScript = Join-Path $RepoRoot 'scripts\CodexToClaude.UI.ps1'
$GuiLauncher = Join-Path $RepoRoot 'CodexToClaude-GUI.cmd'
$VersionFile = Join-Path $RepoRoot 'VERSION'
$Passed = 0
$Failed = 0

function TestCase([string]$Name, [scriptblock]$Body) {
    Write-Host "`n=== TEST: $Name ===" -ForegroundColor Cyan
    try {
        & $Body
        Write-Host "PASS: $Name" -ForegroundColor Green
        $script:Passed++
    } catch {
        Write-Host "FAIL: $Name -- $($_.Exception.Message)" -ForegroundColor Red
        $script:Failed++
    }
}

function Assert-Syntax([string]$Path) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw ($errors | Select-Object -First 1 | Out-String) }
}

TestCase 'CLI PowerShell syntax parses' {
    Assert-Syntax $Script
}

TestCase 'GUI PowerShell syntax parses' {
    Assert-Syntax $UiScript
}

TestCase 'GUI launcher exists' {
    if (-not (Test-Path $GuiLauncher)) { throw 'CodexToClaude-GUI.cmd missing.' }
    $content = Get-Content $GuiLauncher -Raw
    if ($content -notmatch 'CodexToClaude.UI.ps1') { throw 'GUI launcher does not start UI script.' }
}


TestCase 'Project VERSION file exists and is semantic' {
    if (-not (Test-Path $VersionFile)) { throw 'VERSION file missing.' }
    $version = (Get-Content $VersionFile -Raw -Encoding UTF8).Trim()
    if ($version -notmatch '^v\d+\.\d+\.\d+\.\d+$') { throw "VERSION format mismatch: $version" }
    & $Script project-version
}

TestCase 'Help command runs and explains Port ProxyUrl' {
    & $Script help
}

TestCase 'ProxyUrl none configure writes no proxy-url line' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $installDir = Join-Path $fakeHome '.cli-proxy-api'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    try {
        & $Script configure -Port 18317 -ProxyUrl none -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        $config = Get-Content (Join-Path $installDir 'config.yaml') -Raw -Encoding UTF8
        if ($config -match '(?m)^proxy-url:') { throw 'proxy-url should be omitted for none.' }
        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($settings.env.ANTHROPIC_BASE_URL -ne 'http://127.0.0.1:18317') { throw 'Claude base URL mismatch.' }
        if ($settings.env.ANTHROPIC_DEFAULT_OPUS_MODEL -ne 'gpt-5.5') { throw 'Default Opus model mismatch.' }
        if ($settings.env.ANTHROPIC_DEFAULT_SONNET_MODEL -ne 'gpt-5.4') { throw 'Default Sonnet model mismatch.' }
        if ($settings.env.ANTHROPIC_DEFAULT_HAIKU_MODEL -ne 'gpt-5.4') { throw 'Default Haiku model mismatch.' }
        if ($settings.env.ANTHROPIC_DEFAULT_OPUS_MODEL_NAME -ne 'gpt-5.5') { throw 'Default Opus model name mismatch.' }
        if ($settings.env.ANTHROPIC_DEFAULT_SONNET_MODEL_NAME -ne 'gpt-5.4') { throw 'Default Sonnet model name mismatch.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'ProxyUrl writes explicit proxy-url line' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-proxy"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $installDir = Join-Path $fakeHome '.cli-proxy-api'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    try {
        & $Script configure -Port 18318 -ProxyUrl 'http://127.0.0.1:7897' -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        $config = Get-Content (Join-Path $installDir 'config.yaml') -Raw -Encoding UTF8
        if ($config -notmatch 'proxy-url: "http://127\.0\.0\.1:7897"') { throw 'proxy-url line missing.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'ProxyMode Auto accepts host port and writes HTTP proxy-url' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-auto"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $installDir = Join-Path $fakeHome '.cli-proxy-api'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    try {
        & $Script configure -Port 18320 -ProxyMode Auto -ProxyUrl '127.0.0.1:7897' -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        $config = Get-Content (Join-Path $installDir 'config.yaml') -Raw -Encoding UTF8
        if ($config -notmatch 'proxy-url: "http://127\.0\.0\.1:7897"') { throw 'Auto mode should default host:port to HTTP proxy-url.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'ProxyMode Socks5 writes socks5 proxy-url' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-socks"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $installDir = Join-Path $fakeHome '.cli-proxy-api'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    try {
        & $Script configure -Port 18321 -ProxyMode Socks5 -ProxyUrl '127.0.0.1:7897' -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        $config = Get-Content (Join-Path $installDir 'config.yaml') -Raw -Encoding UTF8
        if ($config -notmatch 'proxy-url: "socks5://127\.0\.0\.1:7897"') { throw 'Socks5 mode should write socks5 proxy-url.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'ProxyMode Direct removes CLIProxy auth proxy_url' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-direct"
    $installDir = Join-Path $fakeHome '.cli-proxy-api'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    New-Item -ItemType Directory $installDir -Force | Out-Null
    try {
        $auth = @{ type = 'codex'; email = 'user@example.com'; disabled = $false; proxy_url = 'http://127.0.0.1:7897' } | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText((Join-Path $installDir 'codex-user.json'), $auth, [System.Text.Encoding]::UTF8)
        & $Script configure -Port 18322 -ProxyMode Direct -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        $config = Get-Content (Join-Path $installDir 'config.yaml') -Raw -Encoding UTF8
        if ($config -match '(?m)^proxy-url:') { throw 'Direct mode should omit proxy-url.' }
        $updated = Get-Content (Join-Path $installDir 'codex-user.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($updated.PSObject.Properties['proxy_url']) { throw 'Direct mode should remove auth proxy_url.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'Configure models writes Claude model env values' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-models"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    try {
        & $Script configure-models -ClaudeSettingsPath $settingsPath -OpusModel 'gpt-opus-test(high)' -SonnetModel 'gpt-sonnet-test(medium)' -HaikuModel 'gpt-haiku-test(low)' 2>&1 | Out-Null
        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($settings.env.ANTHROPIC_DEFAULT_OPUS_MODEL -ne 'gpt-opus-test(high)') { throw 'Opus model mismatch.' }
        if ($settings.env.ANTHROPIC_DEFAULT_SONNET_MODEL -ne 'gpt-sonnet-test(medium)') { throw 'Sonnet model mismatch.' }
        if ($settings.env.ANTHROPIC_DEFAULT_HAIKU_MODEL -ne 'gpt-haiku-test(low)') { throw 'Haiku model mismatch.' }
        if ($settings.env.ANTHROPIC_DEFAULT_OPUS_MODEL_NAME -ne 'gpt-opus-test') { throw 'Opus model name mismatch.' }
        if ($settings.env.ANTHROPIC_DEFAULT_SONNET_MODEL_NAME -ne 'gpt-sonnet-test') { throw 'Sonnet model name mismatch.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'Auth status JSON does not expose tokens' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-auth"
    $installDir = Join-Path $fakeHome '.cli-proxy-api'
    New-Item -ItemType Directory $installDir -Force | Out-Null
    try {
        $auth = @{
            type = 'codex'
            email = 'user@example.com'
            expired = '2099-01-01T00:00:00Z'
            disabled = $false
            access_token = 'SECRET_ACCESS'
            refresh_token = 'SECRET_REFRESH'
            id_token = 'SECRET_ID'
        } | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText((Join-Path $installDir 'codex-user-plus.json'), $auth, [System.Text.Encoding]::UTF8)
        $output = & $Script auth-status -InstallDir $installDir -Json 2>&1 | Out-String
        if ($output -match 'SECRET_ACCESS|SECRET_REFRESH|SECRET_ID') { throw 'Auth status leaked token fields.' }
        $parsed = $output | ConvertFrom-Json
        if ($parsed.status -ne 'logged_in') { throw 'Expected logged_in auth status.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'OCC configure writes config.json' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-occ"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $installDir = Join-Path $fakeHome 'oc-go-cc'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    try {
        & $Script configure -Provider occ -Port 13456 -ProxyUrl none -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        $config = Get-Content (Join-Path $installDir 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($config.port -ne 13456) { throw "OCC config port mismatch: $($config.port)" }
        if ($config.host -ne '127.0.0.1') { throw "OCC config host mismatch: $($config.host)" }
        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($settings.env.ANTHROPIC_BASE_URL -ne 'http://127.0.0.1:13456') { throw 'Claude base URL mismatch for OCC.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'OCC configure writes proxy_url when set' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-occ-proxy"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $installDir = Join-Path $fakeHome 'oc-go-cc'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    try {
        & $Script configure -Provider occ -Port 13457 -ProxyUrl 'http://127.0.0.1:7897' -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        $config = Get-Content (Join-Path $installDir 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($config.proxy_url -ne 'http://127.0.0.1:7897') { throw 'proxy_url missing or mismatched in OCC config.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'OCC login throws clear message' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-occ-login"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $installDir = Join-Path $fakeHome 'oc-go-cc'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    try {
        $null = & $Script configure -Provider occ -Port 13458 -ProxyUrl none -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        $threw = $false
        try {
            & $Script login -Provider occ -InstallDir $installDir 2>&1 | Out-Null
        } catch {
            $threw = $true
            if ($_.Exception.Message -notmatch 'does not support') {
                throw "Expected clear error about login not supported. Got: $($_.Exception.Message)"
            }
        }
        if (-not $threw) { throw 'Expected login to throw for OCC, but it did not.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'Both providers configure separate install dirs' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-dual"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $clipDir = Join-Path $fakeHome 'cli-proxy-api'
    $occDir = Join-Path $fakeHome 'oc-go-cc'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    try {
        & $Script configure -Provider cliproxy -Port 18319 -ProxyUrl none -InstallDir $clipDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        & $Script configure -Provider occ -Port 13459 -ProxyUrl none -InstallDir $occDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        if (-not (Test-Path (Join-Path $clipDir 'config.yaml'))) { throw 'CLIProxy config.yaml missing.' }
        if (-not (Test-Path (Join-Path $occDir 'config.json'))) { throw 'OCC config.json missing.' }
        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($settings.env.ANTHROPIC_BASE_URL -ne 'http://127.0.0.1:13459') { throw 'Claude base URL should point to last configured provider (OCC).' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'OCC auth-status returns configured status' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-occ-auth"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $installDir = Join-Path $fakeHome 'oc-go-cc'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    try {
        & $Script configure -Provider occ -Port 13460 -ProxyUrl none -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        $output = & $Script auth-status -Provider occ -InstallDir $installDir -Json 2>&1 | Out-String
        $parsed = $output | ConvertFrom-Json
        if ($parsed.status -ne 'not_configured') { throw "Expected not_configured, got: $($parsed.status)" }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'OCC provider syntax parses' {
    Assert-Syntax (Join-Path $RepoRoot 'scripts\providers\occ.ps1')
}

TestCase 'CLIProxy provider syntax parses' {
    Assert-Syntax (Join-Path $RepoRoot 'scripts\providers\cliproxy.ps1')
}

Write-Host "`nPassed: $Passed  Failed: $Failed" -ForegroundColor Cyan
if ($Failed -gt 0) { exit 1 }
exit 0
