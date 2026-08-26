[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [string]$Prompt = '',
    [string]$ProfilePath = '',
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
$RuntimePath = Join-Path $ProjectRoot 'loop\runtime'
$UiScript = Join-Path $PSScriptRoot 'browser-ui.ps1'
$RunStatePath = Join-Path $ProjectRoot 'loop\RUN_STATE.md'
$LockPath = Join-Path $RuntimePath 'chatgpt-browser-loop.lock'
$OtherLockPaths = @(
    (Join-Path $RuntimePath 'chatgpt-remote-loop.lock'),
    (Join-Path $RuntimePath 'chatgpt-profile-browser-loop.lock')
)

if (-not (Test-Path -LiteralPath $RunStatePath)) { throw "RUN_STATE missing: $RunStatePath" }
if (-not (Test-Path -LiteralPath $UiScript)) { throw "Browser UI helper missing: $UiScript" }
New-Item -ItemType Directory -Force -Path $RuntimePath | Out-Null

foreach ($otherLockPath in $OtherLockPaths) {
    if (-not (Test-Path -LiteralPath $otherLockPath)) { continue }
    $probe = $null
    try {
        $probe = [IO.File]::Open($otherLockPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    } catch {
        throw "Another ChatGPT loop is already running: $otherLockPath"
    } finally {
        if ($null -ne $probe) { $probe.Dispose() }
    }
}

$lockStream = $null
try {
    $lockStream = [IO.File]::Open($LockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
} catch {
    throw "Another ChatGPT browser loop is already running: $LockPath"
}

try {
    $lockStream.SetLength(0)
    $bytes = [Text.Encoding]::UTF8.GetBytes("pid=$PID`nstarted=$(Get-Date -Format o)")
    $lockStream.Write($bytes,0,$bytes.Length)
    $lockStream.Flush()

    $arguments = @(
        '-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',$UiScript,
        '-Action','Loop',
        '-ProjectRoot',$ProjectRoot,
        '-MaxLoops',$MaxLoops,
        '-PollSeconds',$PollSeconds,
        '-StartupTimeoutSeconds',$StartupTimeoutSeconds,
        '-RunTimeoutSeconds',$RunTimeoutSeconds,
        '-StartResponseTimeoutSeconds',$StartResponseTimeoutSeconds,
        '-StartRetryCount',$StartRetryCount,
        '-StartRetryDelaySeconds',$StartRetryDelaySeconds,
        '-DisconnectedGraceSeconds',$DisconnectedGraceSeconds,
        '-StaleHeartbeatSeconds',$StaleHeartbeatSeconds
    )
    if (-not [string]::IsNullOrWhiteSpace($Prompt)) { $arguments += @('-Prompt',$Prompt) }
    if (-not [string]::IsNullOrWhiteSpace($ProfilePath)) { $arguments += @('-ProfilePath',$ProfilePath) }
    & powershell.exe @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Persistent-profile ChatGPT browser loop failed.' }
} finally {
    if ($null -ne $lockStream) { $lockStream.Dispose() }
}
