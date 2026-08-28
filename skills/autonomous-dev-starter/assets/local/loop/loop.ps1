[CmdletBinding()]
param(
    [switch]$PreflightOnly,
    [switch]$RecoverExisting
)

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
Set-Default "SELECTED_CLI" "auto"
Set-Default "VCS_PREFERENCE" "auto"
Set-Default "SLEEP_SECONDS" 5
Set-Default "MAX_LOOPS" 0
Set-Default "AGENT_TIMEOUT_SECONDS" 1800
Set-Default "MAX_RETRIES" 2
Set-Default "RETRY_BASE_SECONDS" 10
Set-Default "MAX_CONSECUTIVE_FAILURES" 3
Set-Default "QUALITY_COMMANDS" @()
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
$RunStatePath = Join-Path $ProjectRoot "loop\RUN_STATE.md"
New-Item -ItemType Directory -Force -Path $RuntimePath, $LogPath | Out-Null

function Get-VcsMode {
    $gitCommand = Get-Command "git" -ErrorAction SilentlyContinue
    $svnCommand = Get-Command "svn" -ErrorAction SilentlyContinue
    $gitInside = $false
    $svnInside = $false

    if ($null -ne $gitCommand) {
        $gitProbe = '"{0}" rev-parse --is-inside-work-tree >nul 2>nul' -f $gitCommand.Source
        & $CmdExecutable /d /s /c $gitProbe | Out-Null
        $gitInside = $LASTEXITCODE -eq 0
    }
    if ($null -ne $svnCommand) {
        $svnProbe = '"{0}" info --non-interactive >nul 2>nul' -f $svnCommand.Source
        & $CmdExecutable /d /s /c $svnProbe | Out-Null
        $svnInside = $LASTEXITCODE -eq 0
    }

    if ($VCS_PREFERENCE -eq "git") {
        if (-not $gitInside) { throw "VCS_PREFERENCE=git but this project is not a Git working tree." }
        return "git"
    }
    if ($VCS_PREFERENCE -eq "svn") {
        if (-not $svnInside) { throw "VCS_PREFERENCE=svn but this project is not an SVN working copy." }
        return "svn"
    }
    if ($VCS_PREFERENCE -ne "auto") { throw "Unsupported VCS_PREFERENCE: $VCS_PREFERENCE" }

    if ($gitInside -and $svnInside) {
        $gitRemotes = @(& $gitCommand.Source remote 2>$null | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($gitRemotes.Count -gt 0) { return "git" }
        return "svn"
    }
    if ($gitInside) { return "git" }
    if ($svnInside) { return "svn" }
    return "none"
}

$VCS_MODE = Get-VcsMode
if ($QUALITY_COMMANDS.Count -eq 0 -and $VCS_MODE -eq "git") {
    $QUALITY_COMMANDS = @("git diff --check")
}

function Get-RunField {
    param([string]$Name)
    if (-not (Test-Path $RunStatePath)) { return "" }
    $line = Get-Content $RunStatePath | Where-Object { $_ -match "^- $([regex]::Escape($Name)):\s*(.*)$" } | Select-Object -First 1
    if (-not $line) { return "" }
    return ([regex]::Match($line, "^- $([regex]::Escape($Name)):\s*(.*)$")).Groups[1].Value.Trim()
}

function Get-RunSnapshot {
    [pscustomobject]@{
        state = Get-RunField "state"
        project_state = Get-RunField "project_state"
        active_task = Get-RunField "active_task"
        task_source = Get-RunField "task_source"
        run_id = Get-RunField "run_id"
        heartbeat_at = Get-RunField "heartbeat_at"
        consecutive_failures = Get-RunField "consecutive_failures"
        circuit_open = Get-RunField "circuit_open"
        last_result = Get-RunField "last_result"
        last_error = Get-RunField "last_error"
    }
}

function Set-RunFields {
    param([hashtable]$Fields)
    if (-not (Test-Path $RunStatePath)) { throw "RUN_STATE missing: $RunStatePath" }
    $content = Get-Content $RunStatePath -Raw
    foreach ($entry in $Fields.GetEnumerator()) {
        $pattern = "(?m)^- $([regex]::Escape([string]$entry.Key)):\s*.*$"
        if (-not [regex]::IsMatch($content, $pattern)) {
            throw "RUN_STATE field missing: $($entry.Key)"
        }
        $replacement = "- $($entry.Key): $($entry.Value)"
        $content = [regex]::Replace($content, $pattern, $replacement, 1)
    }
    Set-Content -Path $RunStatePath -Value $content -Encoding UTF8 -NoNewline
}

function Publish-RunnerFailure {
    param([string]$Result, [string]$ErrorMessage, [int]$FailureCount, [switch]$OpenCircuit)
    $state = if ($OpenCircuit) { "CIRCUIT_OPEN" } else { "IDLE" }
    Set-RunFields @{
        state = $state
        active_task = "none"
        task_source = "none"
        heartbeat_at = (Get-Date).ToString("o")
        consecutive_failures = $FailureCount
        circuit_open = $(if ($OpenCircuit) { "true" } else { "false" })
        last_result = $Result
        last_error = $ErrorMessage
    }
}

function Test-TerminalHandshake {
    param($Before, $After, [bool]$RecoveryExisting)
    if ($After.state -match '^(RUNNING|RECOVERING)$') { return $false }
    if ([string]::IsNullOrWhiteSpace($After.last_result) -or $After.last_result -eq $Before.last_result) { return $false }
    if ([string]::IsNullOrWhiteSpace($After.run_id) -or $After.run_id -ieq 'none') { return $false }
    if ($RecoveryExisting) {
        if ($Before.run_id -and $Before.run_id -ine 'none' -and $After.run_id -ne $Before.run_id) { return $false }
    } else {
        if ($Before.run_id -and $Before.run_id -ine 'none' -and $After.run_id -eq $Before.run_id) { return $false }
    }
    return $true
}

function Test-ProjectComplete {
    $snapshot = Get-RunSnapshot
    return $snapshot.project_state -ieq "PROJECT_COMPLETE"
}

function Test-Preflight {
    $required = @("loop\EXECUTION.md", "loop\RUN_STATE.md", "loop\PROMPT.md", "docs\DESIGN.md", "docs\STATUS.md", "docs\feedback\INBOX.md")
    foreach ($file in $required) {
        if (-not (Test-Path (Join-Path $ProjectRoot $file))) {
            throw "Required file is missing: $file"
        }
    }
    if ([string]::IsNullOrWhiteSpace($AGENT_CMD)) {
        throw "AGENT_CMD is empty in loop\env.ps1"
    }
    if ($VCS_MODE -eq "none") {
        throw "Project root is not a Git or SVN working copy: $ProjectRoot"
    }
}

function Write-RunContext {
    param([int]$LoopNumber, [int]$Attempt, [string]$PreviousFailure, [string]$LogFile, [bool]$RecoveryExisting, [string]$BaselineState, [string]$BaselineActiveTask, [string]$BaselineRunId, [string]$BaselineResult)
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
- selected_cli: $SELECTED_CLI
- vcs_mode: $VCS_MODE
- loop: $LoopNumber
- attempt: $Attempt
- log_file: $LogFile
- recovery_existing: $RecoveryExisting
- baseline_state: $BaselineState
- baseline_active_task: $BaselineActiveTask
- baseline_run_id: $BaselineRunId
- baseline_last_result: $BaselineResult
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
    Write-Host "VCS: $VCS_MODE"
    Write-Host "Agent: $AGENT_CMD"
    Write-Host "Quality commands: $($QUALITY_COMMANDS -join '; ')"
    exit 0
}

$circuitPath = Join-Path $RuntimePath "CIRCUIT_OPEN.md"
if (Test-Path $circuitPath) {
    throw "Circuit is open. Inspect and remove: $circuitPath"
}

$initialSnapshot = Get-RunSnapshot
if ($initialSnapshot.circuit_open -ieq "true" -or $initialSnapshot.state -ieq "CIRCUIT_OPEN") {
    throw "RUN_STATE circuit is open. Resolve it before starting the CLI loop."
}
if ($initialSnapshot.state -ieq "PAUSED" -or $initialSnapshot.project_state -ieq "PAUSED") {
    Write-Host "Project is PAUSED. Exiting without starting a CLI session."
    exit 0
}
if ($initialSnapshot.project_state -ieq "PROJECT_COMPLETE") {
    Write-Host "PROJECT_COMPLETE reached. Exiting without creating more work."
    exit 0
}
if ($initialSnapshot.state -match '^(RUNNING|RECOVERING)$' -and -not $RecoverExisting) {
    throw "RUN_STATE already has an active run ($($initialSnapshot.run_id) / $($initialSnapshot.active_task)). Re-run with -RecoverExisting only after confirming the previous CLI process is no longer active."
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
    [int]$ConsecutiveFailures = 0
    [void][int]::TryParse($initialSnapshot.consecutive_failures, [ref]$ConsecutiveFailures)
    $AllowInitialRecovery = $RecoverExisting.IsPresent

    while ($true) {
        if (Test-ProjectComplete) {
            Write-Host "PROJECT_COMPLETE reached. Exiting without creating more work."
            break
        }
        if (Test-Path (Join-Path $ProjectRoot "loop\STOP")) {
            Write-Host "loop\STOP found. Exiting before the next iteration."
            break
        }
        if ($MAX_LOOPS -gt 0 -and $LoopCount -ge $MAX_LOOPS) {
            Write-Host "MAX_LOOPS reached: $MAX_LOOPS"
            break
        }

        $entrySnapshot = Get-RunSnapshot
        if ($entrySnapshot.circuit_open -ieq "true" -or $entrySnapshot.state -ieq "CIRCUIT_OPEN") {
            Write-Host "Circuit is open in RUN_STATE. Exiting."
            $ProcessExitCode = 2
            break
        }
        if ($entrySnapshot.state -ieq "PAUSED" -or $entrySnapshot.project_state -ieq "PAUSED") {
            Write-Host "Project is PAUSED. Exiting."
            break
        }
        if ($entrySnapshot.state -match '^(RUNNING|RECOVERING)$' -and -not ($LoopCount -eq 0 -and $AllowInitialRecovery)) {
            throw "Refusing to start a duplicate CLI session for active run $($entrySnapshot.run_id)."
        }

        $LoopCount++
        $Success = $false
        $TerminalDisposition = "NONE"
        $TerminalResult = ""
        $LastFailure = "none"
        $LastLogRelative = ""
        $ValidationSummary = "not-run"
        $StopAfterFailure = $false

        for ($Attempt = 1; $Attempt -le (1 + $MAX_RETRIES); $Attempt++) {
            if (Test-Path (Join-Path $ProjectRoot "loop\STOP")) { break }

            $before = Get-RunSnapshot
            $RecoveryThisAttempt = $before.state -match '^(RUNNING|RECOVERING)$'
            if ($Attempt -eq 1 -and $RecoveryThisAttempt -and -not ($LoopCount -eq 1 -and $AllowInitialRecovery)) {
                throw "Unexpected active RUN_STATE before CLI launch: $($before.run_id) / $($before.active_task)"
            }

            $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $LastLogRelative = "{0}\loop_{1}_L{2}_A{3}.log" -f $LOG_DIR, $Timestamp, $LoopCount, $Attempt
            $LastLogAbsolute = Join-Path $ProjectRoot $LastLogRelative
            Write-RunContext -LoopNumber $LoopCount -Attempt $Attempt -PreviousFailure $LastFailure -LogFile $LastLogRelative -RecoveryExisting $RecoveryThisAttempt -BaselineState $before.state -BaselineActiveTask $before.active_task -BaselineRunId $before.run_id -BaselineResult $before.last_result

            if ($RecoveryThisAttempt) {
                Write-Host "[Loop $LoopCount / Attempt $Attempt] Recovering run $($before.run_id) task $($before.active_task) in a fresh CLI session"
            } else {
                Write-Host "[Loop $LoopCount / Attempt $Attempt] Starting a fresh CLI session"
            }

            $AgentExit = Invoke-LoggedCommand -Command $AGENT_CMD -LogFile $LastLogAbsolute -TimeoutSeconds $AGENT_TIMEOUT_SECONDS -Label "AGENT"
            $after = Get-RunSnapshot

            if ($AgentExit -eq 0) {
                if (-not (Test-TerminalHandshake -Before $before -After $after -RecoveryExisting $RecoveryThisAttempt)) {
                    $LastFailure = "CLI session exited 0 without a valid RUN_STATE terminal handshake; inspect $LastLogRelative"
                    $ValidationSummary = "terminal-handshake-failed"
                } else {
                    $TerminalResult = $after.last_result
                    if ($TerminalResult -match '^PASS:') {
                        $FailedChecks = New-Object System.Collections.Generic.List[string]
                        foreach ($check in $QUALITY_COMMANDS) {
                            $checkExit = Invoke-LoggedCommand -Command $check -LogFile $LastLogAbsolute -TimeoutSeconds $AGENT_TIMEOUT_SECONDS -Label "QUALITY GATE"
                            if ($checkExit -ne 0) { $FailedChecks.Add("$check (exit=$checkExit)") }
                        }
                        if ($FailedChecks.Count -eq 0) {
                            $Success = $true
                            $TerminalDisposition = "PASS"
                            $ValidationSummary = "PASS: $($QUALITY_COMMANDS -join '; ')"
                            break
                        }
                        $LastFailure = "Post-session Quality Gate failed: $($FailedChecks -join ', '); inspect $LastLogRelative"
                        $ValidationSummary = $LastFailure
                        $StopAfterFailure = $true
                    } elseif ($TerminalResult -match '^SKIP:') {
                        $Success = $true
                        $TerminalDisposition = "SKIP"
                        $ValidationSummary = "terminal-skip"
                        break
                    } elseif ($TerminalResult -match '^BLOCKED:') {
                        $TerminalDisposition = "BLOCKED"
                        $LastFailure = "Agent reported $TerminalResult"
                        $ValidationSummary = "agent-blocked"
                        $StopAfterFailure = $true
                    } elseif ($TerminalResult -match '^FAIL:') {
                        $TerminalDisposition = "FAIL"
                        $LastFailure = "Agent reported $TerminalResult"
                        $ValidationSummary = "agent-failed-terminal"
                        $StopAfterFailure = $true
                    } else {
                        $LastFailure = "Unexpected terminal result '$TerminalResult'; inspect $LastLogRelative"
                        $ValidationSummary = "unexpected-terminal-result"
                        $StopAfterFailure = $true
                    }
                }
            } else {
                $LastFailure = "Agent exit code $AgentExit; inspect $LastLogRelative"
                $ValidationSummary = "agent-process-failed"
                if ($after.last_result -match '^(BLOCKED|FAIL):' -and $after.state -notmatch '^(RUNNING|RECOVERING)$') {
                    $TerminalResult = $after.last_result
                    $TerminalDisposition = if ($TerminalResult -match '^BLOCKED:') { "BLOCKED" } else { "FAIL" }
                    $StopAfterFailure = $true
                }
            }

            if ($StopAfterFailure) { break }
            if ($Attempt -le $MAX_RETRIES) {
                $Backoff = [int]($RETRY_BASE_SECONDS * [math]::Pow(2, $Attempt - 1))
                Write-Host "$LastFailure"
                $retrySnapshot = Get-RunSnapshot
                if ($retrySnapshot.state -match '^(RUNNING|RECOVERING)$') {
                    Write-Host "Retrying the exact active run in a fresh CLI session in $Backoff seconds"
                } else {
                    Write-Host "Retrying with a fresh CLI session in $Backoff seconds"
                }
                if (-not (Wait-Interruptibly -Seconds $Backoff)) { break }
            }
        }

        $AllowInitialRecovery = $false
        if ($Success) {
            $ConsecutiveFailures = 0
            $ProcessExitCode = 0
            if ($TerminalDisposition -eq "SKIP") {
                Add-StatusEvent -LoopNumber $LoopCount -State "SKIP" -Summary $TerminalResult -LogFile $LastLogRelative -Validation $ValidationSummary
                Write-Host "[Loop $LoopCount] $TerminalResult"
                break
            }

            Add-StatusEvent -LoopNumber $LoopCount -State "PASS" -Summary $TerminalResult -LogFile $LastLogRelative -Validation $ValidationSummary
            Write-Host "[Loop $LoopCount] $TerminalResult"
            if (Test-ProjectComplete) {
                Write-Host "PROJECT_COMPLETE reached after loop $LoopCount. Exiting."
                break
            }
            Write-Host "Next loop in $SLEEP_SECONDS seconds"
            if (-not (Wait-Interruptibly -Seconds $SLEEP_SECONDS)) { break }
            continue
        }

        $ConsecutiveFailures++
        $ProcessExitCode = 1
        Add-StatusEvent -LoopNumber $LoopCount -State "FAIL" -Summary $LastFailure -LogFile $LastLogRelative -Validation $ValidationSummary
        Write-Host "[Loop $LoopCount] FAIL ($ConsecutiveFailures consecutive): $LastFailure"

        $failureResult = if ($TerminalResult -match '^(BLOCKED|FAIL):') { $TerminalResult } else { "FAIL:CLI_LOOP" }
        if ($ConsecutiveFailures -ge $MAX_CONSECUTIVE_FAILURES) {
            @"
# Circuit Open

- opened_at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")
- consecutive_failures: $ConsecutiveFailures
- last_failure: $LastFailure
- last_log: $LastLogRelative

Inspect the cause, delete this file, and start the loop again.
"@ | Set-Content -Path $circuitPath -Encoding UTF8
            Publish-RunnerFailure -Result "FAIL:CIRCUIT_OPEN" -ErrorMessage $LastFailure -FailureCount $ConsecutiveFailures -OpenCircuit
            $ProcessExitCode = 2
            Add-StatusEvent -LoopNumber $LoopCount -State "BLOCKED" -Summary "Circuit opened after consecutive failures" -LogFile $LastLogRelative -Validation $ValidationSummary
        } else {
            Publish-RunnerFailure -Result $failureResult -ErrorMessage $LastFailure -FailureCount $ConsecutiveFailures
        }
        break
    }
} finally {
    if ($null -ne $lockStream) { $lockStream.Dispose() }
}

exit $ProcessExitCode
