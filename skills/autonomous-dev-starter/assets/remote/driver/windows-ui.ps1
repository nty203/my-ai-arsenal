[CmdletBinding()]
param(
    [ValidateSet('ListWindows','Activate','ChatGPTPrompt','ChatGPTSubmitPending')]
    [string]$Action,
    [string]$ProcessName = 'ChatGPT',
    [string]$TitleContains = '',
    [string]$Prompt = '',
    [switch]$UseRemoteMention,
    [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TargetWindow {
    $items = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 }
    if ($ProcessName) { $items = $items | Where-Object { $_.ProcessName -ieq $ProcessName } }
    if ($TitleContains) { $items = $items | Where-Object { $_.MainWindowTitle -like "*$TitleContains*" } }
    return $items | Select-Object -First 1
}
function Activate-Window([System.Diagnostics.Process]$Process) {
    $shell = New-Object -ComObject WScript.Shell
    if (-not $shell.AppActivate($Process.Id)) { throw "Unable to activate ChatGPT window ($($Process.Id))." }
    Start-Sleep -Milliseconds 250
    return $shell
}
function Get-AllElements($root) {
    return $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
}
function Get-Composer($root) {
    $best = $null
    foreach ($e in (Get-AllElements $root)) {
        $r = $e.Current.BoundingRectangle
        if ($e.Current.ControlType -ne [System.Windows.Automation.ControlType]::Edit) { continue }
        if ($e.Current.IsOffscreen -or -not $e.Current.IsEnabled -or $r.Width -lt 500) { continue }
        if ($null -eq $best -or $r.Y -gt $best.Current.BoundingRectangle.Y) { $best = $e }
    }
    return $best
}function Get-NewChatButton($root) {
    $rr = $root.Current.BoundingRectangle
    $best = $null
    foreach ($e in (Get-AllElements $root)) {
        $r = $e.Current.BoundingRectangle
        if ($e.Current.ControlType -ne [System.Windows.Automation.ControlType]::Button) { continue }
        if ($e.Current.IsOffscreen -or -not $e.Current.IsEnabled) { continue }
        $looksLikeSidebarRow = $r.X -lt ($rr.X + 500) -and $r.Y -gt ($rr.Y + 100) -and $r.Y -lt ($rr.Y + 280) -and $r.Width -gt 250 -and $r.Height -ge 40 -and $r.Height -le 70
        if ($looksLikeSidebarRow -and ($null -eq $best -or $r.Width -gt $best.Current.BoundingRectangle.Width)) { $best = $e }
    }
    return $best
}
function Get-ComposerValue($composer) {
    if (-not $composer) { return '' }
    try {
        $pattern = $composer.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $value = [string]$pattern.Current.Value
        $name = [string]$composer.Current.Name
        if ($value.Trim() -eq $name.Trim()) { return '' }
        return $value
    } catch { return '' }
}
function Invoke-Element($element) {
    if (-not $element) { return $false }
    try { $element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); return $true } catch {}
    try { $element.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); return $true } catch {}
    try { $element.SetFocus(); return $true } catch {}
    return $false
}
function Find-RemoteMentionCandidate($root, $composer) {
    $cr = $composer.Current.BoundingRectangle
    foreach ($e in (Get-AllElements $root)) {
        if ($e.Current.IsOffscreen -or -not $e.Current.IsEnabled) { continue }
        if ($e.Current.Name -notmatch '(?i)^AI Folder Remote') { continue }
        $r = $e.Current.BoundingRectangle
        if ($r.Y -lt ($cr.Y - 800) -or $r.Y -gt ($cr.Y + 300)) { continue }
        if ($e.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -or $e.Current.ControlType -eq [System.Windows.Automation.ControlType]::ListItem) { return $e }
    }
    return $null
}
function Wait-RemoteMentionCandidate($root, $composer, [int]$Attempts = 12) {
    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        Start-Sleep -Milliseconds 250
        $candidate = Find-RemoteMentionCandidate $root $composer
        if ($candidate) { return $candidate }
    }
    return $null
}
function Select-RemoteMention($root, $composer, $shell) {
    $composer.SetFocus()
    [System.Windows.Forms.Clipboard]::SetText('@AI Folder Remote')
    $shell.SendKeys('^v')
    $candidate = Wait-RemoteMentionCandidate $root $composer
    if (-not $candidate) {
        $composer.SetFocus()
        $shell.SendKeys('^a{BACKSPACE}')
        $shell.SendKeys('@')
        [System.Windows.Forms.Clipboard]::SetText('AI Folder Remote')
        $shell.SendKeys('^v')
        $candidate = Wait-RemoteMentionCandidate $root $composer
    }
    if (-not $candidate) { throw 'AI Folder Remote mention picker did not appear.' }
    if (-not (Invoke-Element $candidate)) { throw 'AI Folder Remote mention could not be selected.' }
    Start-Sleep -Milliseconds 300
    [void](Handle-ContinueInChat $root)
    $shell.SendKeys(' ')
}
function Handle-ContinueInChat($root) {
    for ($attempt = 0; $attempt -lt 12; $attempt++) {
        foreach ($e in (Get-AllElements $root)) {
            if ($e.Current.ControlType -ne [System.Windows.Automation.ControlType]::Button) { continue }
            if ($e.Current.IsOffscreen -or -not $e.Current.IsEnabled) { continue }
            $name = [string]$e.Current.Name
            if ($name -match '(?i)Chat' -and $name -notmatch '(?i)ChatGPT') {
                if (Invoke-Element $e) { Start-Sleep -Milliseconds 500; return $true }
            }
        }
        Start-Sleep -Milliseconds 300
    }
    return $false
}
function Wait-ComposerEmpty($root, [int]$TimeoutMilliseconds = 4000) {
    $deadline = [Environment]::TickCount64 + $TimeoutMilliseconds
    while ([Environment]::TickCount64 -lt $deadline) {
        $current = Get-Composer $root
        if (-not $current -or [string]::IsNullOrWhiteSpace((Get-ComposerValue $current))) { return $true }
        Start-Sleep -Milliseconds 200
    }
    return $false
}
function Invoke-ComposerSubmit($root, $composer, $shell) {
    $composer.SetFocus()
    $shell.SendKeys('{ENTER}')
    [void](Handle-ContinueInChat $root)
    if (Wait-ComposerEmpty $root 3500) { return $true }
    $after = Get-Composer $root
    if (-not $after) { return $true }
    $cr = $after.Current.BoundingRectangle
    $send = $null
    foreach ($e in (Get-AllElements $root)) {
        $r = $e.Current.BoundingRectangle
        if ($e.Current.ControlType -ne [System.Windows.Automation.ControlType]::Button) { continue }
        if ($e.Current.IsOffscreen -or -not $e.Current.IsEnabled) { continue }
        if ($r.Y -lt ($cr.Y - 20) -or $r.Y -gt ($cr.Y + $cr.Height + 100)) { continue }
        if ($r.X -lt ($cr.X + ($cr.Width * 0.65))) { continue }
        if ($r.Width -lt 35 -or $r.Width -gt 80 -or $r.Height -lt 35 -or $r.Height -gt 80) { continue }
        if ($null -eq $send -or $r.X -gt $send.Current.BoundingRectangle.X) { $send = $e }
    }
    if ($send) { [void](Invoke-Element $send); [void](Handle-ContinueInChat $root) }
    return (Wait-ComposerEmpty $root 4000)
}switch ($Action) {
    'ListWindows' {
        Get-Process | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object ProcessName, Id, MainWindowTitle | ConvertTo-Json -Depth 3 -Compress
        break
    }
    'Activate' {
        $target = Get-TargetWindow
        if (-not $target) { throw 'Target window was not found.' }
        if (-not $DryRun) { [void](Activate-Window $target) }
        [pscustomobject]@{ action='Activate'; process=$target.ProcessName; pid=$target.Id; title=$target.MainWindowTitle; dry_run=[bool]$DryRun } | ConvertTo-Json -Compress
        break
    }
    'ChatGPTSubmitPending' {
        $target = Get-TargetWindow
        if (-not $target) { throw 'ChatGPT desktop window was not found.' }
        if ($DryRun) { [pscustomobject]@{ action='ChatGPTSubmitPending'; dry_run=$true } | ConvertTo-Json -Compress; break }
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName UIAutomationClient
        $shell = Activate-Window $target
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($target.MainWindowHandle)
        $composer = Get-Composer $root
        if (-not $composer) { throw 'ChatGPT composer control was not found.' }
        $before = Get-ComposerValue $composer
        if ([string]::IsNullOrWhiteSpace($before)) { [pscustomobject]@{ action='ChatGPTSubmitPending'; submitted=$false; reason='composer_empty' } | ConvertTo-Json -Compress; break }
        $ok = Invoke-ComposerSubmit $root $composer $shell
        if (-not $ok) { throw 'Pending ChatGPT prompt remained in the composer after submit retries.' }
        [pscustomobject]@{ action='ChatGPTSubmitPending'; submitted=$true; submitted_verified=$true; previous_chars=$before.Length } | ConvertTo-Json -Compress
        break
    }    'ChatGPTPrompt' {
        $target = Get-TargetWindow
        if (-not $target) { throw 'ChatGPT desktop window was not found.' }
        if ([string]::IsNullOrWhiteSpace($Prompt)) { throw 'Prompt is required.' }
        if ($DryRun) {
            [pscustomobject]@{ action='ChatGPTPrompt'; strategy='UIAutomation'; remote_mention=[bool]$UseRemoteMention; prompt_chars=$Prompt.Length; submit_verification=$true; dry_run=$true } | ConvertTo-Json -Compress
            break
        }
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName UIAutomationClient
        $shell = Activate-Window $target
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($target.MainWindowHandle)
        if (-not $root) { throw 'ChatGPT UI Automation root was not found.' }
        $newChat = Get-NewChatButton $root
        if (-not $newChat) { throw 'ChatGPT new-chat control was not found.' }
        if (-not (Invoke-Element $newChat)) { throw 'ChatGPT new-chat control could not be invoked.' }
        Start-Sleep -Milliseconds 650
        $composer = Get-Composer $root
        if (-not $composer) { throw 'ChatGPT composer control was not found.' }
        $previousClipboard = [System.Windows.Forms.Clipboard]::GetDataObject()
        try {
            if ($UseRemoteMention) { Select-RemoteMention $root $composer $shell }
            $composer = Get-Composer $root
            $composer.SetFocus()
            [System.Windows.Forms.Clipboard]::SetText($Prompt)
            $shell.SendKeys('^v')
            Start-Sleep -Milliseconds 250
            $ok = Invoke-ComposerSubmit $root $composer $shell
            if (-not $ok) { throw 'ChatGPT prompt remained in the composer after submit retries.' }
        } finally {
            if ($null -ne $previousClipboard) { [System.Windows.Forms.Clipboard]::SetDataObject($previousClipboard, $true) }
        }
        [pscustomobject]@{ action='ChatGPTPrompt'; process=$target.ProcessName; pid=$target.Id; strategy='UIAutomation'; remote_mention=[bool]$UseRemoteMention; prompt_chars=$Prompt.Length; submitted=$true; submitted_verified=$true; dry_run=$false } | ConvertTo-Json -Compress
        break
    }
}