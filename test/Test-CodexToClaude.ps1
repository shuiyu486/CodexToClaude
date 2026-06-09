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

function Get-FunctionAst([string]$Path, [string]$Name) {
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "Could not parse $Path." }
    $func = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)
    if (-not $func) { throw "Could not locate function $Name." }
    return $func
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

TestCase 'GUI streams command output while process runs' {
    $source = Get-Content $UiScript -Raw -Encoding UTF8
    if ($source -notmatch 'function\s+Read-NewOutput') { throw 'GUI should read command output incrementally.' }
    if ($source -notmatch 'while\s*\(\s*-not\s+\$proc\.HasExited\s*\)[\s\S]{0,220}Read-NewOutput') { throw 'GUI should append stdout before the command exits so device login codes are visible.' }
    if ($source -notmatch '\$deviceCheck\.Checked\s+-and\s+\$Command\s+-eq\s+''login''[\s\S]{0,80}''-Device''') { throw 'GUI login should pass -Device when device login is checked.' }
}

TestCase 'GUI log box resizes and preserves readable output' {
    $source = Get-Content $UiScript -Raw -Encoding UTF8
    if ($source -notmatch 'function\s+Normalize-LogText') { throw 'GUI should normalize log newlines before appending.' }
    if ($source -notmatch '\$logGroup\.Anchor\s*=\s*\[System\.Windows\.Forms\.AnchorStyles\]::Top\s+-bor\s+\[System\.Windows\.Forms\.AnchorStyles\]::Bottom\s+-bor\s+\[System\.Windows\.Forms\.AnchorStyles\]::Left\s+-bor\s+\[System\.Windows\.Forms\.AnchorStyles\]::Right') { throw 'Log group should resize with the main window.' }
    if ($source -notmatch '\$logBox\.Anchor\s*=\s*\[System\.Windows\.Forms\.AnchorStyles\]::Top\s+-bor\s+\[System\.Windows\.Forms\.AnchorStyles\]::Bottom\s+-bor\s+\[System\.Windows\.Forms\.AnchorStyles\]::Left\s+-bor\s+\[System\.Windows\.Forms\.AnchorStyles\]::Right') { throw 'Log text box should resize with the log group.' }
    if ($source -notmatch '\$logBox\.ScrollBars\s*=\s*''Both''' -or $source -notmatch '\$logBox\.WordWrap\s*=\s*\$false') { throw 'Log box should keep command output readable with horizontal scrolling.' }
}

TestCase 'GUI command runner avoids shell injection and redacts logs' {
    $source = Get-Content $UiScript -Raw -Encoding UTF8
    if ($source -match "Start-Process\s+-FilePath\s+'cmd\.exe'") { throw 'GUI command runner must not invoke cmd.exe /c with user input.' }
    if ($source -notmatch 'Build-WrapperScript\s+\$cliArgs') { throw 'GUI should pass CLI args through a generated wrapper script.' }
    if ($source -notmatch '\$params\s*=\s*@\{' -or $source -notmatch '&\s+\$scriptLiteral\s+@params') { throw 'GUI wrapper should use hashtable splatting for Windows PowerShell script parameters.' }
    if ($source -notmatch 'RedirectStandardOutput\s+\$stdout' -or $source -notmatch 'RedirectStandardError\s+\$stderr') { throw 'GUI should capture stdout and stderr without cmd.exe redirection.' }
    if ($source -notmatch '\$wrapperPath\.exitcode' -or $source -notmatch 'WriteAllText\(\$exitCodeLiteral' -or $source -notmatch 'Get-Content\s+\$exitCodePath') { throw 'GUI should persist and read wrapper exit code instead of relying only on Process.ExitCode.' }
    if ($source -notmatch 'exit\s+`\$exitCode') { throw 'GUI wrapper should exit with the same code it records.' }
    if ($source -notmatch '`\$exitCode\s*=\s*1\s*\r?\n\s*Write-Error\s+`\$_\.Exception\.Message\s+-ErrorAction\s+Continue') { throw 'GUI wrapper should record failure before writing non-terminating error output.' }
    if ($source -notmatch 'function\s+Redact-UiLogText') { throw 'GUI log redaction helper missing.' }
    if ($source -notmatch 'CheckToolSearch') { throw 'GUI wrapper should recognize -CheckToolSearch as a switch parameter.' }
    if ($source -notmatch 'Normalize-LogText\s+\(Redact-UiLogText\s+\$Text\)') { throw 'Append-Log should redact before writing to the log box.' }
    foreach ($pattern in @('Authorization', 'Bearer', 'access_token', 'refresh_token', 'id_token', 'x-api-key', 'sk-')) {
        if ($source -notmatch [regex]::Escape($pattern)) { throw "GUI redaction missing pattern: $pattern" }
    }
}

TestCase 'Wait-ServiceReady requires health endpoint success' {
    $func = Get-FunctionAst $Script 'Wait-ServiceReady'
    $body = $func.Body.Extent.Text
    if ($body -match 'Get-PortProcesses[\s\S]{0,160}\$ResolvedPort[\s\S]{0,160}-gt\s+0[\s\S]{0,120}return\s+\$true') {
        throw 'Wait-ServiceReady must not treat a listening port as service-ready without a successful health response.'
    }
    if ($body -notmatch 'Test-ServiceHealth') {
        throw 'Wait-ServiceReady should still probe the provider health endpoint through Test-ServiceHealth.'
    }
}

TestCase 'Claude stream-json check uses bounded watchdog' {
    $func = Get-FunctionAst $Script 'Test-ClaudeStreamJson'
    $body = $func.Body.Extent.Text
    $commands = @($func.Body.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
    foreach ($cmd in $commands) {
        if ($cmd.GetCommandName() -eq 'Start-Process' -and $cmd.Extent.Text -match '--output-format=stream-json' -and $cmd.Extent.Text -match '(^|\s)-Wait(\s|$)') {
            throw 'Claude stream-json check must not use Start-Process -Wait without a watchdog.'
        }
    }
    if ($body -notmatch '\$streamTimeoutSeconds\s*=\s*60') {
        throw 'Claude stream-json watchdog must be 60 seconds.'
    }
    if ($body -notmatch 'stream-json check timed out after 60 seconds') {
        throw 'Claude stream-json timeout error message must be stable for diagnostics.'
    }
    if ($body -notmatch 'Stop-Process\s+-Id\s+\$proc\.Id') {
        throw 'Claude stream-json watchdog must stop the hung claude.exe process.'
    }
    if ($body -match [regex]::Escape('payload.filter may need update')) {
        throw 'Claude stream-json diagnostics must not recommend restoring payload.filter.'
    }
    if ($body -notmatch 'thinking_delta_count') {
        throw 'Claude stream-json diagnostics should report thinking_delta_count.'
    }
}

TestCase 'Status remains read-only' {
    $func = Get-FunctionAst $Script 'Show-Status'
    $body = $func.Body.Extent.Text
    $commands = @($func.Body.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
    $commandNames = @($commands | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
    foreach ($blocked in @('Stop-Process', 'Start-Process', 'Try-AutoSwitchToSocks5', 'Configure-Claude')) {
        if ($commandNames -contains $blocked) {
            throw 'Show-Status must diagnose only and must not start, stop, restart, switch proxy, or rewrite settings.'
        }
    }
    if ($body -notmatch 'Test-ServiceHealth') {
        throw 'Show-Status should include a read-only health snapshot.'
    }
}

TestCase 'Redaction helper contains required sensitive patterns' {
    $source = Get-Content $Script -Raw -Encoding UTF8
    if ($source -notmatch 'function\s+Redact-SensitiveText') { throw 'Redact-SensitiveText function missing.' }
    foreach ($pattern in @('Authorization', 'Bearer', 'access_token', 'refresh_token', 'id_token', 'x-api-key', 'sk-')) {
        if ($source -notmatch [regex]::Escape($pattern)) { throw "Redaction helper missing pattern: $pattern" }
    }
}

TestCase 'Provider start validates health for existing listeners' {
    $clip = Get-Content (Join-Path $RepoRoot 'scripts\providers\cliproxy.ps1') -Raw -Encoding UTF8
    $occ = Get-Content (Join-Path $RepoRoot 'scripts\providers\occ.ps1') -Raw -Encoding UTF8
    if ($clip -notmatch 'Test-ServiceHealth\s+\$ResolvedPort\s+''/healthz''') { throw 'CLIProxy existing listener path must check /healthz.' }
    if ($occ -notmatch 'Test-ServiceHealth\s+\$ResolvedPort\s+''/health''') { throw 'OCC existing listener path must check /health.' }
    if ($clip -match 'Port \$ResolvedPort is already listening\."\s*\r?\n\s*return') { throw 'CLIProxy must not return success for any existing listener without health.' }
    if ($occ -match 'Port \$ResolvedPort is already listening\."\s*\r?\n\s*return') { throw 'OCC must not return success for any existing listener without health.' }
}

TestCase 'CLIProxy risk diagnostics checks hang-prone configuration' {
    $clip = Get-Content (Join-Path $RepoRoot 'scripts\providers\cliproxy.ps1') -Raw -Encoding UTF8
    if ($clip -notmatch 'function\s+CLIProxy-GetRiskDiagnostics') { throw 'CLIProxy-GetRiskDiagnostics missing.' }
    foreach ($field in @('request-retry', 'max-retry-credentials', 'max-retry-interval', 'bootstrap-retries', 'antigravity-credits')) {
        if ($clip -notmatch [regex]::Escape($field)) { throw "CLIProxy risk diagnostics missing check for $field" }
    }
    if ($clip -match [regex]::Escape('payload.filter should remove reasoning, reasoning.effort, and thinking')) { throw 'CLIProxy risk diagnostics should not require payload filtering.' }
}

TestCase 'Port process detection ignores stale TCP connections' {
    $source = Get-Content $Script -Raw -Encoding UTF8
    if ($source -notmatch "\.State\s+-eq\s+'Listen'") { throw 'Get-PortProcesses should only treat listening sockets as port owners.' }
    if ($source -notmatch '\.OwningProcess\s+-gt\s+0') { throw 'Get-PortProcesses should ignore Idle pid=0 connections.' }
    if ($source -notmatch 'netstat\s+-ano\s+-p\s+tcp') { throw 'Get-PortProcesses should fallback to netstat when Get-NetTCPConnection misses a listener.' }
    if ($source -notmatch [regex]::Escape('LISTENING\s+(\d+)')) { throw 'Get-PortProcesses netstat fallback should only match listening TCP owners.' }
}

TestCase 'Verify uses a single restart recovery attempt' {
    $source = Get-Content $Script -Raw -Encoding UTF8
    if ($source -notmatch 'function\s+Invoke-VerifyCore') { throw 'Invoke-VerifyCore function missing.' }
    if ($source -notmatch 'function\s+Invoke-VerifyWithRecovery') { throw 'Invoke-VerifyWithRecovery function missing.' }
    if ($source -notmatch '\$recoveryAttempted\s*=\s*\$false') { throw 'Verify recovery must track a single attempt.' }
    if ($source -notmatch 'Attempting one restart recovery before retrying verify') { throw 'Verify recovery message missing.' }
}

TestCase 'Verify reports actionable Cloudflare and auth suspension hints' {
    $source = Get-Content $Script -Raw -Encoding UTF8
    if ($source -notmatch 'function\s+Get-RecentProviderFailureHint') { throw 'Provider failure hint helper missing.' }
    foreach ($pattern in @('Enable JavaScript and cookies to continue', 'cf_chl', 'backend-api/codex/responses', 'auth_unavailable', 'payment_required')) {
        if ($source -notmatch [regex]::Escape($pattern)) { throw "Provider failure hint missing pattern: $pattern" }
    }
    if ($source -notmatch 'Write-RecentProviderFailureHint\s+\$firstHint' -or $source -notmatch 'Write-RecentProviderFailureHint\s+\$finalHint') {
        throw 'Verify recovery should print provider failure hints before and after restart recovery.'
    }
}

TestCase 'Verify exposes optional advanced compatibility checks' {
    $source = Get-Content $Script -Raw -Encoding UTF8
    if ($source -notmatch '\[switch\]\$CheckTools') { throw 'verify should expose -CheckTools.' }
    if ($source -notmatch '\[switch\]\$CheckPromptCaching') { throw 'verify should expose -CheckPromptCaching.' }
    if ($source -notmatch '\[switch\]\$CheckToolSearch') { throw 'verify should expose -CheckToolSearch.' }
    if ($source -notmatch 'function\s+Invoke-ToolUseVerify') { throw 'Tool-use verify helper missing.' }
    if ($source -notmatch 'function\s+Invoke-PromptCachingVerify') { throw 'Prompt caching verify helper missing.' }
    if ($source -notmatch 'function\s+Invoke-ToolSearchVerify') { throw 'ToolSearch verify helper missing.' }
    if ($source -notmatch 'if \(\$CheckToolSearch\) \{ Invoke-ToolSearchVerify \$ResolvedPort \}') { throw 'Advanced verify should run ToolSearch only when requested.' }
    if ($source -notmatch 'function\s+Verify-Setup\(\[int\]\$ResolvedPort\)\s*\{\s*Invoke-VerifyWithRecovery\s+\$ResolvedPort\s*Invoke-AdvancedVerify\s+\$ResolvedPort') { throw 'Verify setup should run advanced checks outside restart recovery.' }
}

TestCase 'CLIProxy watchdog auto-recovers long stream requests' {
    $source = Get-Content $Script -Raw -Encoding UTF8
    $clip = Get-Content (Join-Path $RepoRoot 'scripts\providers\cliproxy.ps1') -Raw -Encoding UTF8
    foreach ($name in @('Get-LongRunningProxyRequests', 'Invoke-ProviderWatchdog', 'Start-ProviderWatchdog', 'Stop-ProviderWatchdog', 'Get-WatchdogProcess', 'Quote-ProcessArgument', 'Get-AutoProxyToggle', 'Add-AutoProxyStaleEvent', 'Get-AutoProxyPinnedScheme')) {
        if ($source -notmatch "function\s+$name") { throw "$name function missing." }
    }
    foreach ($cmd in @('watchdog-run', 'watchdog-start', 'watchdog-stop')) {
        if ($source -notmatch [regex]::Escape("'$cmd'")) { throw "Command missing: $cmd" }
    }
    if ($source -notmatch '\$WatchdogTimeoutSeconds\s*=\s*60') { throw 'Watchdog timeout should be 60 seconds.' }
    if ($source -notmatch '\$script:AutoProxyDecisionWindowSeconds\s*=\s*600') { throw 'Auto proxy decision window should be 10 minutes.' }
    if ($source -notmatch '\$script:AutoProxyDecisionMinEvents\s*=\s*3') { throw 'Auto proxy decision should require multiple stale events.' }
    if ($source -notmatch '\$script:AutoProxyPinSeconds\s*=\s*1800') { throw 'Auto proxy pin duration should be 30 minutes.' }
    if ($source -notmatch 'function\s+Get-EffectiveProxyMode') { throw 'ProxyMode should be persisted for watchdog subprocesses.' }
    if ($source -match "'watchdog-run'[\s\S]{0,240}'-ProxyMode'") { throw 'Watchdog subprocess should not pin ProxyMode; it should read persisted mode at runtime.' }
    if ($source -notmatch '\(Get-EffectiveProxyMode\)\s+-ne\s+''Auto''') { throw 'Watchdog auto proxy decisions must only apply in effective Auto mode.' }
    if ($source -notmatch '\[datetime\]::TryParse') { throw 'Watchdog should ignore malformed matching log timestamps.' }
    if ($source -notmatch 'Get-CimInstance\s+Win32_Process') { throw 'Watchdog PID handling should validate process identity.' }
    if ($source -notmatch 'codextoclaude-state' -or $source -notmatch 'watchdog-state\.json') { throw 'Watchdog should persist Auto proxy decision state outside auth-dir root.' }
    if ($source -notmatch 'codextoclaude-watchdog-state\.json') { throw 'Watchdog should migrate the legacy Auto proxy decision state file.' }
    if ($source -notmatch 'codextoclaude-proxy-mode\.txt') { throw 'ProxyMode should be persisted beside provider config.' }
    if ($source -notmatch 'auto-switched proxy' -or $source -notmatch 'auto-kept proxy') { throw 'Watchdog should log switched and kept Auto proxy decisions.' }
    if ($source -notmatch 'Convert-ProxyUrlScheme\s+\$currentProxy\s+\$nextScheme') { throw 'Watchdog should toggle between HTTP and Socks5 proxy schemes.' }
    if ($source -notmatch '\$watchStartedAt\s*=\s*Get-Date[\s\S]*catch') { throw 'Watchdog should reset its observation window after recovery.' }
    if ($source -match 'recent 5xx failures') { throw 'Watchdog should not restart the provider for fast 5xx responses.' }
    if ($clip -notmatch 'Start-ProviderWatchdog\s+\$ResolvedPort') { throw 'CLIProxy start should start watchdog.' }
    if ($clip -notmatch 'Stop-ProviderWatchdog') { throw 'CLIProxy stop should stop watchdog.' }
}

TestCase 'CLIProxy update replaces existing exe safely' {
    $clip = Get-Content (Join-Path $RepoRoot 'scripts\providers\cliproxy.ps1') -Raw -Encoding UTF8
    if ($clip -notmatch 'Remove-Item\s+\$ExePath\s+-Force') { throw 'CLIProxy update should remove the existing exe before Move-Item on Windows PowerShell 5.1.' }
    if ($clip -notmatch 'Restored previous cli-proxy-api\.exe after update failure') { throw 'CLIProxy update should restore backup after replacement failure.' }
}

TestCase 'OCC update replaces existing exe safely' {
    $occ = Get-Content (Join-Path $RepoRoot 'scripts\providers\occ.ps1') -Raw -Encoding UTF8
    if ($occ -notmatch 'Remove-Item\s+\$ExePath\s+-Force') { throw 'OCC update should remove the existing exe before Move-Item on Windows PowerShell 5.1.' }
    if ($occ -notmatch 'Restored previous oc-go-cc\.exe after update failure') { throw 'OCC update should restore backup after replacement failure.' }
}

TestCase 'CLIProxy install refreshes existing exe from latest release' {
    $func = Get-FunctionAst (Join-Path $RepoRoot 'scripts\providers\cliproxy.ps1') 'CLIProxy-InstallBinary'
    $body = $func.Body.Extent.Text
    if ($body -match 'if\s*\(Test-Path\s+\$ExePath\)\s*\{[\s\S]{0,160}cli-proxy-api\.exe exists[\s\S]{0,80}return') {
        throw 'CLIProxy install must not skip update checks when cli-proxy-api.exe already exists.'
    }
    if ($body -notmatch 'CLIProxy-UpdateBinary') {
        throw 'CLIProxy install should use the safe update flow when an exe exists.'
    }
}

TestCase 'Install writes provider config before binary update can restart service' {
    $source = Get-Content $Script -Raw -Encoding UTF8
    $installMatch = [regex]::Match($source, "'install'\s*\{(?<body>[\s\S]*?)\r?\n\s*\}\r?\n\r?\n\s*'login'")
    if (-not $installMatch.Success) { throw 'Could not locate install command dispatch.' }
    $body = $installMatch.Groups['body'].Value
    $writeIndex = $body.IndexOf('& $writeFunc $resolvedPort $resolvedProxy')
    $installIndex = $body.IndexOf('& $installFunc')
    if ($writeIndex -lt 0 -or $installIndex -lt 0) { throw 'Install dispatch should call both provider WriteConfig and InstallBinary.' }
    if ($writeIndex -gt $installIndex) { throw 'Install must write config before updating an existing binary, because update may restart the service.' }
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

TestCase 'set-proxy-env configures User-scope CLI environment only' {
    $source = Get-Content $Script -Raw -Encoding UTF8
    if ($source -notmatch "'set-proxy-env'") { throw 'set-proxy-env command missing.' }
    if ($source -notmatch 'User-scope command-line proxy env') { throw 'Help should describe User-scope command-line proxy env values.' }
    if ($source -match 'Machine-scope') { throw 'set-proxy-env must not describe Machine-scope environment changes.' }
    if ($source -notmatch 'SetEnvironmentVariable\(\$Name, \$Value, ''User''\)') { throw 'set-proxy-env should write User-scope environment variables.' }
    if ($source -notmatch '\[AllowNull\(\)\]\[string\]\$Value') { throw 'Direct mode clearing should pass null through to SetEnvironmentVariable.' }
    if ($source -notmatch 'Send-EnvironmentChangeBroadcast') { throw 'set-proxy-env should broadcast User environment changes.' }
    if ($source -notmatch 'Merge-NoProxyValue') { throw 'set-proxy-env should preserve existing NO_PROXY entries.' }
    foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy', 'NO_PROXY', 'no_proxy')) {
        if ($source -notmatch [regex]::Escape($name)) { throw "set-proxy-env missing environment variable: $name" }
    }
    foreach ($blocked in @('netsh', 'WinHTTP', 'Internet Settings', 'ProxyEnable', 'ProxyServer', 'git config', 'npm config', 'HKCU:', 'HKLM:', 'Set-ItemProperty')) {
        if ($source -match [regex]::Escape($blocked)) { throw "set-proxy-env must not touch system proxy settings: $blocked" }
    }
    if ($source -notmatch 'if \(\$ResolvedProxyUrl -eq ''''\) \{ Set-UserEnvironmentVariable \$name \$null \}') { throw 'Direct mode should clear proxy environment variables.' }
    if ($source -notmatch 'Get-LocalNoProxyItems[\s\S]*127\.0\.0\.1[\s\S]*localhost[\s\S]*::1[\s\S]*127\.0\.0\.1:\$ResolvedPort[\s\S]*localhost:\$ResolvedPort') { throw 'NO_PROXY should include local provider addresses.' }
    if ($source -notmatch 'ToLowerInvariant\(\).*@\(''none'', ''direct'', ''no'', ''off'', ''false''\)') { throw 'Direct proxy sentinels should be case-insensitive.' }
}

TestCase 'GUI exposes set-proxy-env diagnostics action' {
    $source = Get-Content $UiScript -Raw -Encoding UTF8
    if ($source -notmatch 'btn\.setProxyEnv') { throw 'GUI should include set proxy env text key.' }
    if ($source -notmatch 'Run-Command ''set-proxy-env'' \$true') { throw 'GUI should call set-proxy-env with current port/proxy fields.' }
}

TestCase 'GUI exposes auto compact configure options' {
    $source = Get-Content $UiScript -Raw -Encoding UTF8
    foreach ($key in @('field.autoCompact', 'field.autoCompactWindow', 'field.autoCompactPct', 'hint.autoCompact', 'dialog.autoCompactRequired', 'dialog.autoCompactInvalid')) {
        if ($source -notmatch [regex]::Escape($key)) { throw "GUI auto compact text key missing: $key" }
    }
    foreach ($text in @('Claude auto-compact threshold', 'Context window (K tokens)', 'Trigger pct (%)', 'Claude 自动压缩阈值', '上下文窗口(k tokens)', '触发比例(%)')) {
        if ($source -notmatch [regex]::Escape($text)) { throw "GUI auto compact clear text missing: $text" }
    }
    foreach ($name in @('autoCompactBox', 'autoCompactWindowBox', 'autoCompactPctBox', 'Update-AutoCompactState', 'Validate-AutoCompactInputs', 'Convert-KTokensToRawTokens')) {
        if ($source -notmatch [regex]::Escape($name)) { throw "GUI auto compact control or helper missing: $name" }
    }
    if ($source -notmatch [regex]::Escape('$Command -eq ''configure''') -or $source -notmatch "'-AutoCompact'") { throw 'GUI should pass auto compact args only through configure.' }
    if ($source -notmatch [regex]::Escape('$autoCompact -ne ''Unset''')) { throw 'GUI should omit auto compact CLI args when unset.' }
    if ($source -notmatch "'-AutoCompactWindow'" -or $source -notmatch "'-AutoCompactPct'") { throw 'GUI should pass auto compact window and pct when enabled.' }
    if ($source -notmatch '\*\s*1000' -or $source -notmatch '\[int\]::MaxValue') { throw 'GUI should convert K tokens to raw tokens and guard CLI int range.' }
    if ($source -notmatch 'Convert-KTokensToRawTokens\s+\$autoCompactWindowBox\.Text') { throw 'GUI should convert auto compact window before passing it to CLI.' }
    if ($source -match "'-AutoCompactWindow',\s*\$autoCompactWindowBox\.Text\.Trim\(\)") { throw 'GUI should not pass K-token textbox directly as raw AutoCompactWindow.' }
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
        if ($settings.env.ENABLE_TOOL_SEARCH -ne 'true') { throw 'Claude settings should enable ToolSearch by default.' }
        if ($settings.env.NO_PROXY -notmatch '127\.0\.0\.1' -or $settings.env.NO_PROXY -notmatch 'localhost' -or $settings.env.NO_PROXY -notmatch '127\.0\.0\.1:18317') { throw 'Claude settings should bypass proxies for the local provider URL.' }
        if ($settings.env.no_proxy -ne $settings.env.NO_PROXY) { throw 'Claude settings should write both NO_PROXY and no_proxy.' }
        if ($settings.env.ANTHROPIC_DEFAULT_OPUS_MODEL -ne 'gpt-5.5') { throw 'Default Opus model mismatch.' }
        if ($settings.env.ANTHROPIC_DEFAULT_SONNET_MODEL -ne 'gpt-5.4') { throw 'Default Sonnet model mismatch.' }
        if ($settings.env.ANTHROPIC_DEFAULT_HAIKU_MODEL -ne 'gpt-5.4') { throw 'Default Haiku model mismatch.' }
        if ($settings.env.PSObject.Properties['CLAUDE_CODE_AUTO_COMPACT_WINDOW']) { throw 'Auto compact window env should not be created by default.' }
        if ($settings.env.PSObject.Properties['CLAUDE_AUTOCOMPACT_PCT_OVERRIDE']) { throw 'Auto compact pct env should not be created by default.' }
        if ($settings.env.PSObject.Properties['CLAUDE_CODE_EFFORT_LEVEL']) { throw 'CLIProxy should not force Claude effort level.' }
        if ($config -notmatch '(?m)^passthrough-headers:\s*true\r?$') { throw 'CLIProxy should forward upstream response headers.' }
        if ($config -notmatch '(?m)^request-retry:\s*1\r?$') { throw 'CLIProxy request retry should be bounded.' }
        if ($config -notmatch '(?m)^max-retry-credentials:\s*1\r?$') { throw 'CLIProxy credential retry should be bounded.' }
        if ($config -notmatch '(?m)^\s*antigravity-credits:\s*false\r?$') { throw 'CLIProxy should not fall back to Antigravity credits by default.' }
        if ($config -match '(?m)^payload:\s*$' -or $config -match '(?m)^\s*filter:\s*$') { throw 'CLIProxy should pass through Claude reasoning and thinking by default.' }
        if ($config -match [regex]::Escape('reasoning.effort') -or $config -match '(?m)^\s*-\s*"thinking"\s*$') { throw 'CLIProxy should not filter Claude reasoning or thinking by default.' }
        if ($settings.env.ANTHROPIC_DEFAULT_OPUS_MODEL_NAME -ne 'gpt-5.5') { throw 'Default Opus model name mismatch.' }
        if ($settings.env.ANTHROPIC_DEFAULT_SONNET_MODEL_NAME -ne 'gpt-5.4') { throw 'Default Sonnet model name mismatch.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'Configure preserves non-env Claude settings' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-settings"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $installDir = Join-Path $fakeHome '.cli-proxy-api'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    New-Item -ItemType Directory (Split-Path -Parent $settingsPath) -Force | Out-Null
    try {
        $initial = [pscustomobject]@{
            statusLine = [pscustomobject]@{ type = 'command'; command = 'ctc-status' }
            permissions = [pscustomobject]@{ allow = @('Bash(git status:*)') }
            language = 'zh-CN'
            env = [pscustomobject]@{
                EXISTING_KEY = 'keep-me'
                ENABLE_TOOL_SEARCH = 'false'
                CLAUDE_CODE_EFFORT_LEVEL = 'max'
                CLAUDE_CODE_AUTO_COMPACT_WINDOW = '111111'
                CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = '66'
            }
        } | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($settingsPath, $initial, [System.Text.Encoding]::UTF8)
        & $Script configure -Port 18327 -ProxyUrl none -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($settings.statusLine.command -ne 'ctc-status') { throw 'statusLine should be preserved.' }
        if (@($settings.permissions.allow)[0] -ne 'Bash(git status:*)') { throw 'permissions should be preserved.' }
        if ($settings.language -ne 'zh-CN') { throw 'language should be preserved.' }
        if ($settings.env.EXISTING_KEY -ne 'keep-me') { throw 'existing env values should be preserved.' }
        if ($settings.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW -ne '111111') { throw 'Auto compact window env should be preserved when unset.' }
        if ($settings.env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE -ne '66') { throw 'Auto compact pct env should be preserved when unset.' }
        if ($settings.env.PSObject.Properties['CLAUDE_CODE_EFFORT_LEVEL']) { throw 'CLIProxy configure should remove stale Claude effort env.' }
        if ($settings.env.ENABLE_TOOL_SEARCH -ne 'true') { throw 'ToolSearch should be enabled by configure.' }
        if ($settings.env.ANTHROPIC_BASE_URL -ne 'http://127.0.0.1:18327') { throw 'Claude base URL should be updated.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'AutoCompact Enabled writes Claude settings env' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-autocompact-enabled"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $installDir = Join-Path $fakeHome '.cli-proxy-api'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    try {
        & $Script configure -Port 18329 -ProxyMode Direct -InstallDir $installDir -ClaudeSettingsPath $settingsPath -AutoCompact Enabled -AutoCompactWindow 120000 -AutoCompactPct 70 2>&1 | Out-Null
        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($settings.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW -ne '120000') { throw 'Auto compact window env mismatch.' }
        if ($settings.env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE -ne '70') { throw 'Auto compact pct env mismatch.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'AutoCompact Disabled removes Claude settings env' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-autocompact-disabled"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $installDir = Join-Path $fakeHome '.cli-proxy-api'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    New-Item -ItemType Directory (Split-Path -Parent $settingsPath) -Force | Out-Null
    try {
        $initial = [pscustomobject]@{
            env = [pscustomobject]@{
                EXISTING_KEY = 'keep-me'
                CLAUDE_CODE_AUTO_COMPACT_WINDOW = '120000'
                CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = '70'
            }
        } | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($settingsPath, $initial, [System.Text.Encoding]::UTF8)
        & $Script configure -Port 18330 -ProxyMode Direct -InstallDir $installDir -ClaudeSettingsPath $settingsPath -AutoCompact Disabled 2>&1 | Out-Null
        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($settings.env.EXISTING_KEY -ne 'keep-me') { throw 'Disabled should preserve unrelated env values.' }
        if ($settings.env.PSObject.Properties['CLAUDE_CODE_AUTO_COMPACT_WINDOW']) { throw 'Disabled should remove auto compact window env.' }
        if ($settings.env.PSObject.Properties['CLAUDE_AUTOCOMPACT_PCT_OVERRIDE']) { throw 'Disabled should remove auto compact pct env.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'AutoCompact Enabled requires window and pct' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-autocompact-required"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $installDir = Join-Path $fakeHome '.cli-proxy-api'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    try {
        $failed = $false
        try { & $Script configure -Port 18331 -ProxyMode Direct -InstallDir $installDir -ClaudeSettingsPath $settingsPath -AutoCompact Enabled -AutoCompactWindow 120000 2>&1 | Out-Null } catch { $failed = $true; if ($_.Exception.Message -notmatch 'requires -AutoCompactWindow and -AutoCompactPct') { throw } }
        if (-not $failed) { throw 'AutoCompact Enabled should fail without pct.' }

        $failed = $false
        try { & $Script configure -Port 18331 -ProxyMode Direct -InstallDir $installDir -ClaudeSettingsPath $settingsPath -AutoCompact Enabled -AutoCompactPct 70 2>&1 | Out-Null } catch { $failed = $true; if ($_.Exception.Message -notmatch 'requires -AutoCompactWindow and -AutoCompactPct') { throw } }
        if (-not $failed) { throw 'AutoCompact Enabled should fail without window.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'AutoCompact validates window and pct range' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-autocompact-range"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $installDir = Join-Path $fakeHome '.cli-proxy-api'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    try {
        $failed = $false
        try { & $Script configure -Port 18332 -ProxyMode Direct -InstallDir $installDir -ClaudeSettingsPath $settingsPath -AutoCompact Enabled -AutoCompactWindow 0 -AutoCompactPct 70 2>&1 | Out-Null } catch { $failed = $true; if ($_.Exception.Message -notmatch 'AutoCompactWindow must be greater than 0') { throw } }
        if (-not $failed) { throw 'AutoCompact Enabled should reject window=0.' }

        $failed = $false
        try { & $Script configure -Port 18332 -ProxyMode Direct -InstallDir $installDir -ClaudeSettingsPath $settingsPath -AutoCompact Enabled -AutoCompactWindow 120000 -AutoCompactPct 101 2>&1 | Out-Null } catch { $failed = $true; if ($_.Exception.Message -notmatch 'AutoCompactPct must be in range 1-100') { throw } }
        if (-not $failed) { throw 'AutoCompact Enabled should reject pct outside 1-100.' }

        $failed = $false
        try { & $Script configure -Port 18332 -ProxyMode Direct -InstallDir $installDir -ClaudeSettingsPath $settingsPath -AutoCompactWindow 120000 -AutoCompactPct 70 2>&1 | Out-Null } catch { $failed = $true; if ($_.Exception.Message -notmatch 'can only be used with -AutoCompact Enabled') { throw } }
        if (-not $failed) { throw 'AutoCompact window/pct should require -AutoCompact Enabled.' }
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

TestCase 'CLIProxy config writes Codex User-Agent fallback' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-ua"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $installDir = Join-Path $fakeHome '.cli-proxy-api'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    try {
        & $Script configure -Port 18328 -ProxyMode Direct -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        $config = Get-Content (Join-Path $installDir 'config.yaml') -Raw -Encoding UTF8
        if ($config -notmatch 'codex-header-defaults:\s*\r?\n\s+user-agent: ''codex_cli_rs/0\.114\.0 \(Mac OS 14\.2\.0; x86_64\) vscode/1\.111\.0''') {
            throw 'CLIProxy config should include the default Codex User-Agent fallback.'
        }

        & $Script configure -Port 18328 -ProxyMode Direct -InstallDir $installDir -ClaudeSettingsPath $settingsPath -CodexUserAgent "codex 'custom' ua" 2>&1 | Out-Null
        $config = Get-Content (Join-Path $installDir 'config.yaml') -Raw -Encoding UTF8
        if ($config -notmatch "user-agent: 'codex ''custom'' ua'") { throw 'Custom Codex User-Agent should be single-quote escaped in YAML.' }
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
        $mode = (Get-Content (Join-Path $installDir 'codextoclaude-proxy-mode.txt') -Raw -Encoding UTF8).Trim()
        if ($mode -ne 'Auto') { throw 'Auto mode should be persisted for watchdog subprocesses.' }
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
        $mode = (Get-Content (Join-Path $installDir 'codextoclaude-proxy-mode.txt') -Raw -Encoding UTF8).Trim()
        if ($mode -ne 'Socks5') { throw 'Socks5 mode should be persisted for watchdog subprocesses.' }
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
        if ($updated.websockets -ne $true) { throw 'Direct mode should add missing auth websockets=true.' }
        $mode = (Get-Content (Join-Path $installDir 'codextoclaude-proxy-mode.txt') -Raw -Encoding UTF8).Trim()
        if ($mode -ne 'Direct') { throw 'Direct mode should be persisted for watchdog subprocesses.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'CLIProxy auth metadata preserves explicit websockets false' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-ws-false"
    $installDir = Join-Path $fakeHome '.cli-proxy-api'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    New-Item -ItemType Directory $installDir -Force | Out-Null
    try {
        $auth = @{ type = 'codex'; email = 'user@example.com'; disabled = $false; websockets = $false; note = 'keep-me' } | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText((Join-Path $installDir 'codex-user.json'), $auth, [System.Text.Encoding]::UTF8)
        & $Script configure -Port 18327 -ProxyMode Http -ProxyUrl '127.0.0.1:7897' -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        $updated = Get-Content (Join-Path $installDir 'codex-user.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($updated.proxy_url -ne 'http://127.0.0.1:7897') { throw 'Http mode should sync auth proxy_url.' }
        if ($updated.websockets -ne $false) { throw 'Explicit auth websockets=false should be preserved.' }
        if ($updated.note -ne 'keep-me') { throw 'Unknown auth fields should be preserved.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'ProxyMode reuses configured target with explicit scheme' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-mode-reuse"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $installDir = Join-Path $fakeHome '.cli-proxy-api'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    try {
        & $Script configure -Port 18323 -ProxyMode Auto -ProxyUrl '127.0.0.1:7897' -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        & $Script configure -Port 18323 -ProxyMode Socks5 -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        $config = Get-Content (Join-Path $installDir 'config.yaml') -Raw -Encoding UTF8
        if ($config -notmatch 'proxy-url: "socks5://127\.0\.0\.1:7897"') { throw 'Socks5 mode should rewrite reused config target to socks5.' }
        & $Script configure -Port 18323 -ProxyMode Http -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        $config = Get-Content (Join-Path $installDir 'config.yaml') -Raw -Encoding UTF8
        if ($config -notmatch 'proxy-url: "http://127\.0\.0\.1:7897"') { throw 'Http mode should rewrite reused config target to http.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'Persisted Direct mode is reused without ProxyUrl' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-direct-reuse"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $installDir = Join-Path $fakeHome '.cli-proxy-api'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    try {
        & $Script configure -Port 18324 -ProxyMode Direct -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        & $Script configure -Port 18324 -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        $config = Get-Content (Join-Path $installDir 'config.yaml') -Raw -Encoding UTF8
        if ($config -match '(?m)^proxy-url:') { throw 'Persisted Direct mode should be reused when ProxyMode is omitted.' }
        $mode = (Get-Content (Join-Path $installDir 'codextoclaude-proxy-mode.txt') -Raw -Encoding UTF8).Trim()
        if ($mode -ne 'Direct') { throw 'Persisted Direct mode should remain Direct.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'Explicit ProxyUrl exits persisted Direct mode' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-direct-to-proxy"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $installDir = Join-Path $fakeHome '.cli-proxy-api'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    try {
        & $Script configure -Port 18325 -ProxyMode Direct -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        & $Script configure -Port 18325 -ProxyUrl '127.0.0.1:7897' -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        $config = Get-Content (Join-Path $installDir 'config.yaml') -Raw -Encoding UTF8
        if ($config -notmatch 'proxy-url: "http://127\.0\.0\.1:7897"') { throw 'Explicit ProxyUrl should not be ignored after Direct mode.' }
        $mode = (Get-Content (Join-Path $installDir 'codextoclaude-proxy-mode.txt') -Raw -Encoding UTF8).Trim()
        if ($mode -ne 'Auto') { throw 'Explicit ProxyUrl without ProxyMode should return to Auto mode.' }
    } finally {
        Remove-Item $fakeHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

TestCase 'Explicit direct ProxyUrl keeps Direct mode' {
    $fakeHome = Join-Path $env:TEMP "ctc-test-$(Get-Date -Format 'HHmmss')-direct-sentinel"
    New-Item -ItemType Directory $fakeHome -Force | Out-Null
    $installDir = Join-Path $fakeHome '.cli-proxy-api'
    $settingsPath = Join-Path $fakeHome '.claude\settings.json'
    try {
        & $Script configure -Port 18326 -ProxyMode Auto -ProxyUrl '127.0.0.1:7897' -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        & $Script configure -Port 18326 -ProxyUrl 'none' -InstallDir $installDir -ClaudeSettingsPath $settingsPath 2>&1 | Out-Null
        $config = Get-Content (Join-Path $installDir 'config.yaml') -Raw -Encoding UTF8
        if ($config -match '(?m)^proxy-url:') { throw 'Explicit direct ProxyUrl should omit proxy-url.' }
        $mode = (Get-Content (Join-Path $installDir 'codextoclaude-proxy-mode.txt') -Raw -Encoding UTF8).Trim()
        if ($mode -ne 'Direct') { throw 'Explicit direct ProxyUrl should persist Direct mode.' }
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
        if ($settings.env.ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME -ne 'gpt-haiku-test') { throw 'Haiku model name mismatch.' }
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
        if ($settings.env.CLAUDE_CODE_EFFORT_LEVEL -ne 'max') { throw 'OCC should keep Claude effort level max.' }
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
