[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$SkillRoot = Split-Path -Parent $PSScriptRoot
$TemplateRoot = Join-Path $SkillRoot 'assets\template'
$Scratch = Join-Path $SkillRoot '.tmp-cli-loop-state-test'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function Set-Field([string]$Path, [string]$Name, [string]$Value) {
    $content = Get-Content $Path -Raw
    $pattern = "(?m)^- $([regex]::Escape($Name)):\s*.*$"
    if (-not [regex]::IsMatch($content, $pattern)) { throw "Missing field $Name in $Path" }
    $content = [regex]::Replace($content, $pattern, "- ${Name}: $Value", 1)
    Set-Content -Path $Path -Value $content -Encoding UTF8 -NoNewline
}

function Get-Field([string]$Path, [string]$Name) {
    $line = Get-Content $Path | Where-Object { $_ -match "^- $([regex]::Escape($Name)):\s*(.*)$" } | Select-Object -First 1
    if (-not $line) { return '' }
    return ([regex]::Match($line, "^- $([regex]::Escape($Name)):\s*(.*)$")).Groups[1].Value.Trim()
}

function Reset-Project {
    if (Test-Path $Scratch) { Remove-Item $Scratch -Recurse -Force }
    New-Item -ItemType Directory -Path $Scratch | Out-Null
    Copy-Item (Join-Path $TemplateRoot '*') $Scratch -Recurse -Force
    Push-Location $Scratch
    try {
        git init -q
        git config user.email 'loop-test@example.invalid'
        git config user.name 'CLI Loop Test'
    } finally { Pop-Location }
}

function Write-TestEnv([string]$Mode, [int]$Retries = 0, [int]$FailureThreshold = 2) {
    $envPath = Join-Path $Scratch 'loop\env.ps1'
    @"
`$PROJECT_PROFILE = 'cli'
`$SELECTED_CLI = 'fake'
`$VCS_PREFERENCE = 'git'
`$AGENT_CMD = 'powershell -NoProfile -ExecutionPolicy Bypass -File "fake-agent.ps1" -Mode $Mode'
`$SLEEP_SECONDS = 0
`$MAX_LOOPS = 1
`$AGENT_TIMEOUT_SECONDS = 30
`$MAX_RETRIES = $Retries
`$RETRY_BASE_SECONDS = 0
`$MAX_CONSECUTIVE_FAILURES = $FailureThreshold
`$QUALITY_COMMANDS = @()
`$ALLOW_AGENT_COMMIT = `$false
`$ALLOW_PUSH_OR_DEPLOY = `$false
`$RUNTIME_DIR = 'loop\runtime'
`$LOG_DIR = 'logs'
`$EXTRA_PATHS = @()
"@ | Set-Content $envPath -Encoding UTF8
}

$fakeAgent = @'
param([Parameter(Mandatory=$true)][string]$Mode)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$State = Join-Path $Root 'loop\RUN_STATE.md'
$Context = Join-Path $Root 'loop\runtime\RUN_CONTEXT.md'
$Counter = Join-Path $Root 'loop\runtime\fake-count.txt'

function Set-StateField([string]$Name, [string]$Value) {
    $content = Get-Content $State -Raw
    $pattern = "(?m)^- $([regex]::Escape($Name)):\s*.*$"
    $content = [regex]::Replace($content, $pattern, "- ${Name}: $Value", 1)
    Set-Content -Path $State -Value $content -Encoding UTF8 -NoNewline
}
function ContextField([string]$Name) {
    $line = Get-Content $Context | Where-Object { $_ -match "^- $([regex]::Escape($Name)):\s*(.*)$" } | Select-Object -First 1
    return ([regex]::Match($line, "^- $([regex]::Escape($Name)):\s*(.*)$")).Groups[1].Value.Trim()
}
function Start-Fresh([string]$RunId, [string]$Task) {
    Set-StateField 'state' 'RUNNING'
    Set-StateField 'active_task' $Task
    Set-StateField 'task_source' 'planned'
    Set-StateField 'run_id' $RunId
    Set-StateField 'started_at' ([DateTime]::UtcNow.ToString('o'))
    Set-StateField 'heartbeat_at' ([DateTime]::UtcNow.ToString('o'))
}
function Finish-Pass([string]$Result) {
    Set-StateField 'state' 'IDLE'
    Set-StateField 'active_task' 'none'
    Set-StateField 'task_source' 'none'
    Set-StateField 'heartbeat_at' ([DateTime]::UtcNow.ToString('o'))
    Set-StateField 'consecutive_failures' '0'
    Set-StateField 'circuit_open' 'false'
    Set-StateField 'last_result' $Result
    Set-StateField 'last_error' 'none'
}

$count = if (Test-Path $Counter) { [int](Get-Content $Counter -Raw) } else { 0 }
$count++
Set-Content $Counter $count -Encoding ASCII

switch ($Mode) {
    'fresh-pass' {
        if ((ContextField 'recovery_existing') -ne 'False') { throw 'fresh-pass unexpectedly marked recovery' }
        Start-Fresh ('fresh-' + [guid]::NewGuid().ToString('N')) 'TEST-FRESH'
        Finish-Pass 'PASS:TEST-FRESH'
        exit 0
    }
    'recover-after-crash' {
        if ($count -eq 1) {
            Start-Fresh 'recover-fixed-run' 'TEST-RECOVERY'
            exit 7
        }
        if ((ContextField 'recovery_existing') -ne 'True') { throw 'retry did not request recovery' }
        if ((ContextField 'baseline_run_id') -ne 'recover-fixed-run') { throw 'recovery run_id changed' }
        if ((ContextField 'baseline_active_task') -ne 'TEST-RECOVERY') { throw 'recovery task changed' }
        Set-StateField 'state' 'RECOVERING'
        Set-StateField 'heartbeat_at' ([DateTime]::UtcNow.ToString('o'))
        Finish-Pass 'PASS:TEST-RECOVERY'
        exit 0
    }
    'no-handshake' { exit 0 }
    'resume-existing' {
        if ((ContextField 'recovery_existing') -ne 'True') { throw 'explicit recovery context missing' }
        if ((ContextField 'baseline_run_id') -ne 'stale-run') { throw 'explicit recovery run_id mismatch' }
        if ((ContextField 'baseline_active_task') -ne 'TEST-STALE') { throw 'explicit recovery task mismatch' }
        Set-StateField 'state' 'RECOVERING'
        Set-StateField 'heartbeat_at' ([DateTime]::UtcNow.ToString('o'))
        Finish-Pass 'PASS:TEST-STALE'
        exit 0
    }
    default { throw "Unknown fake mode: $Mode" }
}
'@

try {
    Reset-Project
    Set-Content (Join-Path $Scratch 'fake-agent.ps1') $fakeAgent -Encoding UTF8
    Write-TestEnv -Mode 'fresh-pass'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scratch 'loop\loop.ps1')
    Assert-True ($LASTEXITCODE -eq 0) 'fresh PASS runner exit code'
    $statePath = Join-Path $Scratch 'loop\RUN_STATE.md'
    Assert-True ((Get-Field $statePath 'state') -eq 'IDLE') 'fresh PASS terminal state'
    Assert-True ((Get-Field $statePath 'last_result') -eq 'PASS:TEST-FRESH') 'fresh PASS terminal result'

    Reset-Project
    Set-Content (Join-Path $Scratch 'fake-agent.ps1') $fakeAgent -Encoding UTF8
    Write-TestEnv -Mode 'recover-after-crash' -Retries 1
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scratch 'loop\loop.ps1')
    Assert-True ($LASTEXITCODE -eq 0) 'recovery runner exit code'
    $statePath = Join-Path $Scratch 'loop\RUN_STATE.md'
    Assert-True ((Get-Field $statePath 'run_id') -eq 'recover-fixed-run') 'recovery preserved run_id'
    Assert-True ((Get-Field $statePath 'last_result') -eq 'PASS:TEST-RECOVERY') 'recovery terminal result'
    Assert-True ([int](Get-Content (Join-Path $Scratch 'loop\runtime\fake-count.txt') -Raw) -eq 2) 'recovery used exactly two fresh sessions'

    Reset-Project
    Set-Content (Join-Path $Scratch 'fake-agent.ps1') $fakeAgent -Encoding UTF8
    Write-TestEnv -Mode 'no-handshake'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scratch 'loop\loop.ps1')
    Assert-True ($LASTEXITCODE -eq 1) 'missing handshake must fail'
    $statePath = Join-Path $Scratch 'loop\RUN_STATE.md'
    Assert-True ((Get-Field $statePath 'state') -eq 'IDLE') 'runner repairs failed terminal state to IDLE'
    Assert-True ((Get-Field $statePath 'last_result') -eq 'FAIL:CLI_LOOP') 'runner publishes failure result'

    Reset-Project
    Set-Content (Join-Path $Scratch 'fake-agent.ps1') $fakeAgent -Encoding UTF8
    Write-TestEnv -Mode 'resume-existing'
    $statePath = Join-Path $Scratch 'loop\RUN_STATE.md'
    Set-Field $statePath 'state' 'RUNNING'
    Set-Field $statePath 'active_task' 'TEST-STALE'
    Set-Field $statePath 'task_source' 'planned'
    Set-Field $statePath 'run_id' 'stale-run'
    Set-Field $statePath 'last_result' 'NOT_RUN'
    $duplicate = Start-Process -FilePath (Get-Command powershell).Source -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $Scratch 'loop\loop.ps1')) -WindowStyle Hidden -Wait -PassThru
    Assert-True ($duplicate.ExitCode -ne 0) 'active run must refuse duplicate start without RecoverExisting'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Scratch 'loop\loop.ps1') -RecoverExisting
    Assert-True ($LASTEXITCODE -eq 0) 'explicit recovery runner exit code'
    Assert-True ((Get-Field $statePath 'run_id') -eq 'stale-run') 'explicit recovery preserved run_id'
    Assert-True ((Get-Field $statePath 'last_result') -eq 'PASS:TEST-STALE') 'explicit recovery terminal result'

    Write-Host 'CLI LOOP STATE TESTS PASS'
} finally {
    if (Test-Path $Scratch) { Remove-Item $Scratch -Recurse -Force }
}
