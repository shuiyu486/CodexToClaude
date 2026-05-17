$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Script = Join-Path $RepoRoot 'scripts\CodexToClaude.ps1'
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

TestCase 'PowerShell syntax parses' {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Script, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw ($errors | Select-Object -First 1 | Out-String) }
}

TestCase 'Help command runs' {
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

Write-Host "`nPassed: $Passed  Failed: $Failed" -ForegroundColor Cyan
if ($Failed -gt 0) { exit 1 }
