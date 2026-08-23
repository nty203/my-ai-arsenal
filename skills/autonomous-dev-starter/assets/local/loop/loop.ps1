[CmdletBinding()]
param([switch]$PreflightOnly)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$CmdExecutable = (Get-Command "cmd.exe" -ErrorAction Stop).Source
Set-Location $ProjectRoot
. (Join-Path $PSScriptRoot "env.ps1")

function Set-Default {
    param([string]$Name, $Value)
    if (-not (Get-Variable -Name $Name -Scope Script -ErrorAction SilentlyContinue)) {
        Set-Variable -Name $Name -Value $Value -Scope Script
    }
}

Set-Default "PROJECT_PROFILE" "auto"
Set-Default "SLEEP_SECONDS" 5
Set-Default "MAX_LOOPS" 0
Set-Default "AGENT_TIMEOUT_SECONDS" 1800
Set-Default "MAX_RETRIES" 2
Set-Default "RETRY_BASE_SECONDS" 10
Set-Default "MAX_CONSECUTIVE_FAILURES" 3
Set-Default "QUALITY_COMMANDS" @("git diff --check")
Set-Default "ALLOW_AGENT_COMMIT" $true
Set-Default "ALLOW_PUSH_OR_DEPLOY" $false
Set-Default "RUNTIME_DIR" "loop\runtime"
Set-Default "LOG_DIR" "logs"
Set-Default "EXTRA_PATHS" @()

foreach ($extraPath in $EXTRA_PATHS) {
    if ($extraPath -and (Test-Path $extraPath)) {
        $env:PATH = "$env:PATH;$extraPath"
    }
}

$RuntimePath = Join-Path $ProjectRoot $RUNTIME_DIR
$LogPath = Join-Path $ProjectRoot $LOG_DIR
New-Item -ItemType Directory -Force -Path $RuntimePath, $LogPath | Out-Null

function Test-Preflight {
    $required = @("loop\PROMPT.md", "docs\DESIGN.md", "docs\STATUS.md", "docs\feedback\INBOX.md")
    foreach ($file in $required) {
        if (-not (Test-Path (Join-Path $ProjectRoot $file))) {
            throw "Required file is missing: $file"
        }
    }
    if ([string]::IsNullOrWhiteSpace($AGENT_CMD)) {
        throw "AGENT_CMD is empty in loop\env.ps1"
    }
    & git rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Project root is not a Git repository: $ProjectRoot"
    }
}

function Write-RunContext {
    param([int]$LoopNumber, [int]$Attempt, [string]$PreviousFailure, [string]$LogFile)
    $quality = if ($QUALITY_COMMANDS.Count -gt 0) {
        ($QUALITY_COMMANDS | ForEach-Object { "- $_" }) -join [Environment]::NewLine
    } else {
        "- No extra orchestrator checks; PROMPT.md gates remain required"
    }
    $contextPath = Join-Path $RuntimePath "RUN_CONTEXT.md"
    @"
# Autonomous Loop Runtime Context

- generated_at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")
- project_root: $ProjectRoot
- project_profile: $PROJECT_PROFILE
- loop: $LoopNumber
- attempt: $Attempt
- log_file: $LogFile
- allow_agent_commit: $ALLOW_AGENT_COMMIT
- allow_push_or_deploy: $ALLOW_PUSH_OR_DEPLOY
- previous_failure: $PreviousFailure

## Orchestrator quality commands
$quality

This runtime handoff file must not be committed.
"@ | Set-Content -Path $contextPath -Encoding UTF8
}

function Invoke-LoggedCommand {
    param([string]$Command, [string]$LogFile, [int]$TimeoutSeconds, [string]$Label)
    Add-Content -Path $LogFile -Encoding UTF8 -Value @"

===== $Label | $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") =====
> $Command
"@
    $redirected = "$Command >> `"$LogFile`" 2>&1"
    $process = Start-Process -FilePath $CmdExecutable -ArgumentList @("/d", "/s", "/c", $redirected) -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        Start-Process -FilePath "taskkill.exe" -ArgumentList @("/PID", $process.Id, "/T", "/F") -WindowStyle Hidden -Wait | Out-Null
        Add-Content -Path $LogFile -Encoding UTF8 -Value "TIMEOUT after $TimeoutSeconds seconds"
        return 124
    }
    $process.Refresh()
    return $process.ExitCode
}

function Add-StatusEvent {
    param([int]$LoopNumber, [string]$State, [string]$Summary, [string]$LogFile, [string]$Validation)
    $statusPath = Join-Path $ProjectRoot "docs\STATUS.md"
    Add-Content -Path $statusPath -Encoding UTF8 -Value @"

## [$(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")] Orchestrator Loop $LoopNumber
- state: $State
- summary: $Summary
- log: $LogFile
- orchestrator_validation: $Validation
"@
}

function Wait-Interruptibly {
    param([int]$Seconds)
    for ($second = 0; $second -lt $Seconds; $second++) {
        if (Test-Path (Join-Path $ProjectRoot "loop\STOP")) { return $false }
        Start-Sleep -Seconds 1
    }
    return $true
}

Test-Preflight
if ($PreflightOnly) {
    Write-Host "Preflight PASS"
    Write-Host "Project: $ProjectRoot"
    Write-Host "Profile: $PROJECT_PROFILE"
    Write-Host "Agent: $AGENT_CMD"
    Write-Host "Quality commands: $($QUALITY_COMMANDS -join '; ')"
    exit 0
}

$circuitPath = Join-Path $RuntimePath "CIRCUIT_OPEN.md"
if (Test-Path $circuitPath) {
    throw "Circuit is open. Inspect and remove: $circuitPath"
}

$lockPath = Join-Path $RuntimePath "loop.lock"
$lockStream = $null
$ProcessExitCode = 0
try {
    $lockStream = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
} catch {
    throw "Another autonomous loop is already running. Lock: $lockPath"
}

try {
    $lockStream.SetLength(0)
    $lockBytes = [Text.Encoding]::UTF8.GetBytes("pid=$PID`nstarted=$(Get-Date -Format o)")
    $lockStream.Write($lockBytes, 0, $lockBytes.Length)
    $lockStream.Flush()
    $LoopCount = 0
    $ConsecutiveFailures = 0

    while ($true) {
        if (Test-Path (Join-Path $ProjectRoot "loop\STOP")) {
            Write-Host "loop\STOP found. Exiting."
            break
        }
        if ($MAX_LOOPS -gt 0 -and $LoopCount -ge $MAX_LOOPS) {
            Write-Host "MAX_LOOPS reached: $MAX_LOOPS"
            break
        }

        $LoopCount++
        $Success = $false
        $LastFailure = "none"
        $LastLogRelative = ""
        $ValidationSummary = "not-run"

        for ($Attempt = 1; $Attempt -le (1 + $MAX_RETRIES); $Attempt++) {
            if (Test-Path (Join-Path $ProjectRoot "loop\STOP")) { break }
            $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $LastLogRelative = "{0}\loop_{1}_L{2}_A{3}.log" -f $LOG_DIR, $Timestamp, $LoopCount, $Attempt
            $LastLogAbsolute = Join-Path $ProjectRoot $LastLogRelative
            Write-RunContext -LoopNumber $LoopCount -Attempt $Attempt -PreviousFailure $LastFailure -LogFile $LastLogRelative

            Write-Host "[Loop $LoopCount / Attempt $Attempt] Starting agent"
            $AgentExit = Invoke-LoggedCommand -Command $AGENT_CMD -LogFile $LastLogAbsolute -TimeoutSeconds $AGENT_TIMEOUT_SECONDS -Label "AGENT"

            if ($AgentExit -eq 0) {
                $FailedChecks = New-Object System.Collections.Generic.List[string]
                foreach ($check in $QUALITY_COMMANDS) {
                    $checkExit = Invoke-LoggedCommand -Command $check -LogFile $LastLogAbsolute -TimeoutSeconds $AGENT_TIMEOUT_SECONDS -Label "QUALITY GATE"
                    if ($checkExit -ne 0) { $FailedChecks.Add("$check (exit=$checkExit)") }
                }
                if ($FailedChecks.Count -eq 0) {
                    $Success = $true
                    $ValidationSummary = "PASS: $($QUALITY_COMMANDS -join '; ')"
                    break
                }
                $LastFailure = "Quality Gate failed: $($FailedChecks -join ', '); inspect $LastLogRelative"
                $ValidationSummary = $LastFailure
            } else {
                $LastFailure = "Agent exit code $AgentExit; inspect $LastLogRelative"
                $ValidationSummary = "agent-failed"
            }

            if ($Attempt -le $MAX_RETRIES) {
                $Backoff = [int]($RETRY_BASE_SECONDS * [math]::Pow(2, $Attempt - 1))
                Write-Host "$LastFailure"
                Write-Host "Retrying with a fresh session in $Backoff seconds"
                if (-not (Wait-Interruptibly -Seconds $Backoff)) { break }
            }
        }

        if ($Success) {
            $ConsecutiveFailures = 0
            $ProcessExitCode = 0
            Add-StatusEvent -LoopNumber $LoopCount -State "PASS" -Summary "Agent and orchestrator gates passed" -LogFile $LastLogRelative -Validation $ValidationSummary
            Write-Host "[Loop $LoopCount] PASS"
        } else {
            $ConsecutiveFailures++
            $ProcessExitCode = 1
            Add-StatusEvent -LoopNumber $LoopCount -State "FAIL" -Summary $LastFailure -LogFile $LastLogRelative -Validation $ValidationSummary
            Write-Host "[Loop $LoopCount] FAIL ($ConsecutiveFailures consecutive)"
            if ($ConsecutiveFailures -ge $MAX_CONSECUTIVE_FAILURES) {
                $circuitPath = Join-Path $RuntimePath "CIRCUIT_OPEN.md"
                @"
# Circuit Open

- opened_at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")
- consecutive_failures: $ConsecutiveFailures
- last_failure: $LastFailure
- last_log: $LastLogRelative

Inspect the cause, delete this file, and start the loop again.
"@ | Set-Content -Path $circuitPath -Encoding UTF8
                $ProcessExitCode = 2
                Add-StatusEvent -LoopNumber $LoopCount -State "BLOCKED" -Summary "Circuit opened after consecutive failures" -LogFile $LastLogRelative -Validation $ValidationSummary
                break
            }
        }

        Write-Host "Next loop in $SLEEP_SECONDS seconds"
        if (-not (Wait-Interruptibly -Seconds $SLEEP_SECONDS)) { break }
    }
} finally {
    if ($null -ne $lockStream) { $lockStream.Dispose() }
}

exit $ProcessExitCode
