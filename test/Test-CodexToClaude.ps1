$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Script = Join-Path $RepoRoot 'scripts\CodexToClaude.ps1'
$UiScript = Join-Path $RepoRoot 'scripts\CodexToClaude.UI.ps1'
$GuiLauncher = Join-Path $RepoRoot 'CodexToClaude-GUI.cmd'
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

Write-Host "`nPassed: $Passed  Failed: $Failed" -ForegroundColor Cyan
if ($Failed -gt 0) { exit 1 }
