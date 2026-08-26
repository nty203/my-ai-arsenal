[CmdletBinding()]
param(
    [ValidateSet('Setup','Probe','Prompt','WaitIdle','StopDisconnected','Loop')][string]$Action,
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [string]$Prompt = '',
    [string]$ProfilePath = '',
    [string]$NodePath = '',
    [string]$NodeModulesPath = '',
    [int]$TimeoutMilliseconds = 45000,
    [int]$QuietMilliseconds = 3000,
    [int]$MaxLoops = 0,
    [int]$PollSeconds = 2,
    [int]$StartupTimeoutSeconds = 180,
    [int]$RunTimeoutSeconds = 3600,
    [int]$StartResponseTimeoutSeconds = 900,
    [int]$StartRetryCount = 3,
    [int]$StartRetryDelaySeconds = 5,
    [int]$DisconnectedGraceSeconds = 120,
    [int]$StaleHeartbeatSeconds = 900
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$DriverPath = Join-Path $PSScriptRoot 'chatgpt-browser-ui.mjs'
$SessionPath = Join-Path $ProjectRoot 'loop\runtime\chatgpt-browser-session.json'
$BrowserCandidates = @(
    'C:\Program Files\Google\Chrome\Application\chrome.exe',
    'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
    'C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe',
    'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
)
$BrowserPath = $BrowserCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
    if (-not [string]::IsNullOrWhiteSpace($env:CHATGPT_BROWSER_PROFILE)) {
        $ProfilePath = $env:CHATGPT_BROWSER_PROFILE
    } else {
        $ProfilePath = Join-Path $ProjectRoot 'loop\runtime\chatgpt-browser-profile'
    }
}
$ProfilePath = [IO.Path]::GetFullPath($ProfilePath)

if ([string]::IsNullOrWhiteSpace($NodePath)) {
    if (-not [string]::IsNullOrWhiteSpace($env:CHATGPT_NODE_PATH) -and (Test-Path -LiteralPath $env:CHATGPT_NODE_PATH)) {
        $NodePath = $env:CHATGPT_NODE_PATH
    } else {
        $nodeCommand = Get-Command 'node.exe' -ErrorAction SilentlyContinue
        if ($null -eq $nodeCommand) { $nodeCommand = Get-Command 'node' -ErrorAction SilentlyContinue }
        if ($null -ne $nodeCommand) { $NodePath = $nodeCommand.Source }
    }
}
if ([string]::IsNullOrWhiteSpace($NodePath) -and -not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    $runtimeRoot = Join-Path $env:USERPROFILE '.cache\codex-runtimes'
    if (Test-Path -LiteralPath $runtimeRoot) {
        $NodePath = Get-ChildItem -LiteralPath $runtimeRoot -Filter 'node.exe' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    }
}
if ([string]::IsNullOrWhiteSpace($NodePath) -or -not (Test-Path -LiteralPath $NodePath)) {
    throw 'Node.js was not found. Put node on PATH or set CHATGPT_NODE_PATH / -NodePath explicitly.'
}
$NodePath = [IO.Path]::GetFullPath($NodePath)

if ([string]::IsNullOrWhiteSpace($NodeModulesPath) -and -not [string]::IsNullOrWhiteSpace($env:CHATGPT_NODE_MODULES)) {
    $NodeModulesPath = $env:CHATGPT_NODE_MODULES
}
if ([string]::IsNullOrWhiteSpace($NodeModulesPath)) {
    $nodeDir = Split-Path -Parent $NodePath
    $moduleCandidates = @((Join-Path $PSScriptRoot 'node_modules'), (Join-Path $nodeDir 'node_modules'), (Join-Path (Split-Path -Parent $nodeDir) 'node_modules'))
    $NodeModulesPath = $moduleCandidates | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'playwright') } | Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($NodeModulesPath) -and -not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    $runtimeRoot = Join-Path $env:USERPROFILE '.cache\codex-runtimes'
    if (Test-Path -LiteralPath $runtimeRoot) {
        $playwrightPackage = Get-ChildItem -LiteralPath $runtimeRoot -Filter 'package.json' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Directory.Name -eq 'playwright' -and $_.Directory.Parent.Name -eq 'node_modules' } |
            Select-Object -First 1
        if ($null -ne $playwrightPackage) { $NodeModulesPath = $playwrightPackage.Directory.Parent.FullName }
    }
}
if ([string]::IsNullOrWhiteSpace($NodeModulesPath)) {
    throw 'Playwright was not found. Install it next to the driver/runtime or set CHATGPT_NODE_MODULES / -NodeModulesPath explicitly.'
}

if (-not (Test-Path -LiteralPath $DriverPath)) { throw "Browser driver is missing: $DriverPath" }
if (-not $BrowserPath) { throw 'Chrome, Brave, or Edge was not found.' }

$previousNodePath = $env:NODE_PATH
try {
    $env:NODE_PATH = $NodeModulesPath
    $arguments = @(
        $DriverPath,
        '--action', $Action,
        '--projectRoot', $ProjectRoot,
        '--profileDir', $ProfilePath,
        '--browserPath', $BrowserPath,
        '--sessionPath', $SessionPath,
        '--timeoutMs', [string]$TimeoutMilliseconds,
        '--quietMs', [string]$QuietMilliseconds,
        '--maxLoops', [string]$MaxLoops,
        '--pollSeconds', [string]$PollSeconds,
        '--startupTimeoutSeconds', [string]$StartupTimeoutSeconds,
        '--runTimeoutSeconds', [string]$RunTimeoutSeconds,
        '--startResponseTimeoutSeconds', [string]$StartResponseTimeoutSeconds,
        '--startRetryCount', [string]$StartRetryCount,
        '--startRetryDelaySeconds', [string]$StartRetryDelaySeconds,
        '--disconnectedGraceSeconds', [string]$DisconnectedGraceSeconds,
        '--staleHeartbeatSeconds', [string]$StaleHeartbeatSeconds
    )
    if (-not [string]::IsNullOrWhiteSpace($Prompt)) { $arguments += @('--prompt', $Prompt) }
    & $NodePath @arguments
    if ($LASTEXITCODE -ne 0) { throw "Browser UI action failed: $Action" }
} finally {
    $env:NODE_PATH = $previousNodePath
}
