[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [string]$Prompt = '',
    [int]$MaxLoops = 0,
    [int]$PollSeconds = 2,
    [int]$StartupTimeoutSeconds = 180,
    [int]$RunTimeoutSeconds = 3600,
    [int]$StartResponseTimeoutSeconds = 900,
    [int]$StartRetryCount = 3,
    [int]$StartRetryDelaySeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$RunStatePath = Join-Path $ProjectRoot 'loop\RUN_STATE.md'
$TaskBoardPath = Join-Path $ProjectRoot 'docs\wiki\tasks\TASK_BOARD.md'
$StopPath = Join-Path $ProjectRoot 'loop\STOP'
$RuntimePath = Join-Path $ProjectRoot 'loop\runtime'
$UiScript = Join-Path $PSScriptRoot 'windows-ui.ps1'

if (-not (Test-Path $RunStatePath)) { throw "RUN_STATE missing: $RunStatePath" }
if (-not (Test-Path $UiScript)) { throw "UI helper missing: $UiScript" }
New-Item -ItemType Directory -Force -Path $RuntimePath | Out-Null
$StatusPath = Join-Path $RuntimePath 'chatgpt-remote-loop.json'
$LogPath = Join-Path $RuntimePath 'chatgpt-remote-loop.log'
$LockPath = Join-Path $RuntimePath 'chatgpt-remote-loop.lock'

if ([string]::IsNullOrWhiteSpace($Prompt)) {
    $Prompt = "$ProjectRoot 프로젝트에서 개발 계속. loop/EXECUTION.md와 loop/PROMPT.md를 먼저 읽고 chatgpt_remote 규약으로 정확히 한 iteration을 구현, 검증, 기록해. local AI CLI, push, deploy, credentials 접근은 금지한다."
}
function Get-RunField([string]$Name) {
    $line = Get-Content $RunStatePath | Where-Object { $_ -match "^- $([regex]::Escape($Name)):\s*(.*)$" } | Select-Object -First 1
    if (-not $line) { return '' }
    return ([regex]::Match($line, "^- $([regex]::Escape($Name)):\s*(.*)$")).Groups[1].Value.Trim()
}

function Get-Snapshot {
    [pscustomobject]@{
        state = Get-RunField 'state'
        active_task = Get-RunField 'active_task'
        run_id = Get-RunField 'run_id'
        heartbeat_at = Get-RunField 'heartbeat_at'
        circuit_open = Get-RunField 'circuit_open'
        last_result = Get-RunField 'last_result'
        last_error = Get-RunField 'last_error'
    }
}
function Test-AllTasksDone {
    if (-not (Test-Path $TaskBoardPath)) { return $false }
    $statuses = @(
        Get-Content $TaskBoardPath | ForEach-Object {
            if ($_ -match '^\|\s*[^|]+\s*\|\s*(BLOCKED|READY|CLAIMED|IN_PROGRESS|REVIEW|DONE)\s*\|') { $Matches[1].ToUpperInvariant() }
        }
    )
    if ($statuses.Count -eq 0) { return $false }
    return (@($statuses | Where-Object { $_ -ne 'DONE' }).Count -eq 0)
}

function Write-Status([string]$Phase, [int]$Loop, $Snapshot, [string]$Message) {
    [pscustomobject]@{
        pid = $PID
        phase = $Phase
        loop = $Loop
        updated_at = (Get-Date).ToString('o')
        project_root = $ProjectRoot
        state = $Snapshot.state
        active_task = $Snapshot.active_task
        run_id = $Snapshot.run_id
        last_result = $Snapshot.last_result
        message = $Message
    } | ConvertTo-Json | Set-Content $StatusPath -Encoding UTF8
    "$(Get-Date -Format o) phase=$Phase loop=$Loop state=$($Snapshot.state) message=$Message" | Add-Content $LogPath -Encoding UTF8
}
function Test-StopRequested {
    if (Test-Path $StopPath) { return $true }
    $snapshot = Get-Snapshot
    if ($snapshot.circuit_open -ieq 'true') { return $true }
    if ($snapshot.state -ieq 'CIRCUIT_OPEN' -or $snapshot.state -ieq 'PAUSED') { return $true }
    return $false
}

function Wait-Until([scriptblock]$Predicate, [int]$TimeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-StopRequested) { return $false }
        if (& $Predicate) { return $true }
        Start-Sleep -Seconds $PollSeconds
    }
    return $false
}

function Start-ChatIteration([int]$Loop) {
    $args = @(
        '-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',$UiScript,
        '-Action','ChatGPTPrompt','-ProcessName','ChatGPT','-Prompt',$Prompt,'-UseRemoteMention'
    )
    $result = & powershell.exe @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        $detail = (($result | ForEach-Object { $_.ToString().Trim() }) -join ' ')
        if ($detail.Length -gt 600) { $detail = $detail.Substring(0,600) }
        throw "ChatGPT UI launch failed on loop ${Loop}: $detail"
    }
    return $result
}

$lockStream = $null
try {
    $lockStream = [IO.File]::Open($LockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
} catch {
    throw "Another ChatGPT remote loop is already running: $LockPath"
}
try {
    $lockStream.SetLength(0)
    $bytes = [Text.Encoding]::UTF8.GetBytes("pid=$PID`nstarted=$(Get-Date -Format o)")
    $lockStream.Write($bytes,0,$bytes.Length)
    $lockStream.Flush()

    $loop = 0
    $projectComplete = $false
    while ($true) {
        if (Test-StopRequested) { break }
        if (Test-AllTasksDone) {
            $projectComplete = $true
            Write-Status 'PROJECT_COMPLETE' $loop (Get-Snapshot) 'All recognized Task Board rows are DONE; no new ChatGPT chat will be opened.'
            break
        }
        if ($MaxLoops -gt 0 -and $loop -ge $MaxLoops) { break }

        $snapshot = Get-Snapshot
        if ($snapshot.state -ieq 'RUNNING' -or $snapshot.state -ieq 'RECOVERING') {
            Write-Status 'WAIT_EXISTING' $loop $snapshot 'Waiting for the active ChatGPT iteration to finish.'
            $finished = Wait-Until { (Get-Snapshot).state -notmatch '^(RUNNING|RECOVERING)$' } $RunTimeoutSeconds
            if (-not $finished) { Write-Status 'TIMEOUT' $loop (Get-Snapshot) 'Existing iteration did not finish.'; break }
            continue
        }
        if ($snapshot.state -and $snapshot.state -ine 'IDLE') {
            Write-Status 'STOPPED' $loop $snapshot "State is not runnable: $($snapshot.state)"
            break
        }

        $loop++
        $baselineResult = $snapshot.last_result
        $baselineRunId = $snapshot.run_id
        $baselineHeartbeat = $snapshot.heartbeat_at
        $started = $false
        for ($attempt = 1; $attempt -le $StartRetryCount -and -not $started; $attempt++) {
            Write-Status 'LAUNCHING' $loop (Get-Snapshot) "Opening a fresh ChatGPT chat (attempt $attempt/$StartRetryCount)."
            try {
                [void](Start-ChatIteration $loop)
            } catch {
                Write-Status 'START_RETRY' $loop (Get-Snapshot) "ChatGPT UI launch failed on attempt $attempt/${StartRetryCount}: $($_.Exception.Message)"
                if ($attempt -lt $StartRetryCount) { Start-Sleep -Seconds $StartRetryDelaySeconds }
                continue
            }

            $started = Wait-Until {
                $now = Get-Snapshot
                $now.state -match '^(RUNNING|RECOVERING)$'
            } $StartupTimeoutSeconds

            if (-not $started -and -not (Test-StopRequested)) {
                # A slow first response can still be reading project state before
                # it publishes RUNNING. Never open a second chat while that
                # response is active; wait for UI idle, then re-check the state.
                Write-Status 'WAIT_START_UI' $loop (Get-Snapshot) 'No start handshake yet; waiting for the current ChatGPT response before any retry.'
                try {
                    & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $UiScript -Action ChatGPTWaitIdle -ProcessName ChatGPT -IdleTimeoutMilliseconds ($StartResponseTimeoutSeconds * 1000) -IdleQuietMilliseconds 3000 | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw 'ChatGPTWaitIdle returned non-zero.' }
                } catch {
                    Write-Status 'START_RESPONSE_TIMEOUT' $loop (Get-Snapshot) "Current ChatGPT response did not finish; no retry was opened: $($_.Exception.Message)"
                    break
                }
                $afterResponse = Get-Snapshot
                $started = $afterResponse.state -match '^(RUNNING|RECOVERING)$'
            }

            if (-not $started -and $attempt -lt $StartRetryCount -and -not (Test-StopRequested)) {
                Write-Status 'START_RETRY' $loop (Get-Snapshot) "No RUN_STATE start handshake on attempt $attempt/$StartRetryCount; retrying in a fresh chat."
                Start-Sleep -Seconds $StartRetryDelaySeconds
            }
        }
        if (-not $started) {
            Write-Status 'START_FAILED' $loop (Get-Snapshot) "ChatGPT failed to start the iteration after $StartRetryCount attempts."
            break
        }

        Write-Status 'RUNNING' $loop (Get-Snapshot) 'ChatGPT iteration started.'
        $completed = Wait-Until {
            $now = Get-Snapshot
            if ($now.state -match '^(RUNNING|RECOVERING)$') { return $false }
            if ($now.circuit_open -ieq 'true') { return $true }
            return ($now.last_result -and $now.last_result -ne $baselineResult)
        } $RunTimeoutSeconds

        $final = Get-Snapshot
        if (-not $completed) {
            Write-Status 'RUN_TIMEOUT' $loop $final 'ChatGPT iteration did not publish completion state in time.'
            break
        }

        Write-Status 'WAIT_UI_IDLE' $loop $final 'Project closeout is terminal; waiting for the current ChatGPT response to finish.'
        try {
            & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $UiScript -Action ChatGPTWaitIdle -ProcessName ChatGPT -IdleTimeoutMilliseconds 90000 -IdleQuietMilliseconds 3000 -ForceStopAfterTimeout | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'ChatGPTWaitIdle returned non-zero.' }
        } catch {
            Write-Status 'UI_IDLE_TIMEOUT' $loop $final "Current ChatGPT response did not finish cleanly: $($_.Exception.Message)"
            break
        }
        Write-Status 'COMPLETED' $loop $final 'Iteration closeout and ChatGPT response both completed; evaluating whether to continue.'
        if ($final.circuit_open -ieq 'true' -or $final.state -ieq 'CIRCUIT_OPEN') { break }
        if ($final.last_result -match '^(SKIP|BLOCKED|FAIL)') { break }
        if ($final.state -ine 'IDLE') { break }
    }

    if (-not $projectComplete) {
        Write-Status 'STOPPED' $loop (Get-Snapshot) 'Remote continuous loop exited cleanly.'
    }
} finally {
    if ($null -ne $lockStream) { $lockStream.Dispose() }
}
