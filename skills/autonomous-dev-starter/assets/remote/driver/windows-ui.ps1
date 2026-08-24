[CmdletBinding()]
param(
    [ValidateSet('ListWindows','Activate','ChatGPTProbeLayout','ChatGPTProbePlugin','ChatGPTPrompt','ChatGPTContinueCurrent','ChatGPTSubmitPending','ChatGPTRoutePending','ChatGPTWaitIdle')]
    [string]$Action,
    [string]$ProcessName = 'ChatGPT',
    [string]$TitleContains = '',
    [string]$Prompt = '',
    [switch]$UseRemoteMention,
    [int]$IdleTimeoutMilliseconds = 120000,
    [int]$IdleQuietMilliseconds = 3000,
    [switch]$ForceStopAfterTimeout,
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
    $activated = $false
    if (-not ('ChatGPTWin32Window' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ChatGPTWin32Window {
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr SetActiveWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
}
'@
    }
    # Background PowerShell is subject to Windows foreground-lock rules. Temporarily
    # joining the active input queue makes the promotion deterministic.
    [void][ChatGPTWin32Window]::ShowWindowAsync($Process.MainWindowHandle, 9)
    $foreground = [ChatGPTWin32Window]::GetForegroundWindow()
    $foregroundThread = [uint32]0
    $foregroundProcessId = [uint32]0
    if ($foreground -ne [IntPtr]::Zero) { $foregroundThread = [ChatGPTWin32Window]::GetWindowThreadProcessId($foreground, [ref]$foregroundProcessId) }
    $currentThread = [ChatGPTWin32Window]::GetCurrentThreadId()
    $attached = $false
    try {
        if ($foregroundThread -and $foregroundThread -ne $currentThread) { $attached = [ChatGPTWin32Window]::AttachThreadInput($currentThread, $foregroundThread, $true) }
        [void][ChatGPTWin32Window]::BringWindowToTop($Process.MainWindowHandle)
        [void][ChatGPTWin32Window]::SetActiveWindow($Process.MainWindowHandle)
        try { $activated = [bool]$shell.AppActivate($Process.Id) } catch {}
        [void][ChatGPTWin32Window]::SetForegroundWindow($Process.MainWindowHandle)
    } finally {
        if ($attached) { [void][ChatGPTWin32Window]::AttachThreadInput($currentThread, $foregroundThread, $false) }
    }
    Start-Sleep -Milliseconds 250
    try {
        Add-Type -AssemblyName UIAutomationClient
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($Process.MainWindowHandle)
        if ($root) {
            try { $root.SetFocus(); $activated = $true } catch {}
            Ensure-MouseNative
            $rr = $root.Current.BoundingRectangle
            $x = [int]($rr.X + ($rr.Width * 0.5))
            $y = [int]($rr.Y + [math]::Min(18, [math]::Max(8, $rr.Height * 0.02)))
            [void][ChatGPTMouseNative]::SetCursorPos($x, $y)
            [ChatGPTMouseNative]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
            [ChatGPTMouseNative]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
            Start-Sleep -Milliseconds 300
            $activated = $true
        }
    } catch {}
    $deadline = (Get-Date).AddSeconds(4)
    while ((Get-Date) -lt $deadline) {
        if ([ChatGPTWin32Window]::GetForegroundWindow() -eq $Process.MainWindowHandle) { return $shell }
        Start-Sleep -Milliseconds 100
    }
    throw "ChatGPT window ($($Process.Id)) did not become the foreground window."
}
function Get-AllElements($root) {
    return $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
}
function Ensure-MouseNative {
    if (-not ('ChatGPTMouseNative' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ChatGPTMouseNative {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, int data, UIntPtr extraInfo);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extraInfo);
}
'@
    }
}
function Send-NativeKey([byte]$VirtualKey) {
    Ensure-MouseNative
    [ChatGPTMouseNative]::keybd_event($VirtualKey,0,0,[UIntPtr]::Zero)
    [ChatGPTMouseNative]::keybd_event($VirtualKey,0,2,[UIntPtr]::Zero)
    Start-Sleep -Milliseconds 80
}
function Send-NativeCtrlKey([byte]$VirtualKey) {
    Ensure-MouseNative
    [ChatGPTMouseNative]::keybd_event(0x11,0,0,[UIntPtr]::Zero)
    [ChatGPTMouseNative]::keybd_event($VirtualKey,0,0,[UIntPtr]::Zero)
    [ChatGPTMouseNative]::keybd_event($VirtualKey,0,2,[UIntPtr]::Zero)
    [ChatGPTMouseNative]::keybd_event(0x11,0,2,[UIntPtr]::Zero)
    Start-Sleep -Milliseconds 100
}
function Clear-ComposerNative {
    Send-NativeCtrlKey 0x41
    Send-NativeKey 0x08
}
function Paste-ClipboardNative { Send-NativeCtrlKey 0x56 }
function Get-Composer($root) {
    $best = $null
    foreach ($e in (Get-AllElements $root)) {
        try {
            $r = $e.Current.BoundingRectangle
            if ($e.Current.ControlType -ne [System.Windows.Automation.ControlType]::Edit) { continue }
            if ($e.Current.IsOffscreen -or -not $e.Current.IsEnabled -or $r.Width -lt 500) { continue }
            if ($null -eq $best -or $r.Y -gt $best.Current.BoundingRectangle.Y) { $best = $e }
        } catch {}
    }
    return $best
}
function Wait-ComposerStable($root, [int]$TimeoutMilliseconds = 10000) {
    $deadline = (Get-Date).AddMilliseconds($TimeoutMilliseconds)
    $lastKey = ''
    $stableCount = 0
    while ((Get-Date) -lt $deadline) {
        try {
            $composer = Get-Composer $root
            if ($composer) {
                $r = $composer.Current.BoundingRectangle
                $key = '{0:F0},{1:F0},{2:F0},{3:F0}' -f $r.X,$r.Y,$r.Width,$r.Height
                if ($key -eq $lastKey -and $r.Width -ge 500 -and $r.Height -ge 30) { $stableCount++ } else { $stableCount = 1; $lastKey = $key }
                if ($stableCount -ge 3) { return $composer }
            }
        } catch { $stableCount = 0; $lastKey = '' }
        Start-Sleep -Milliseconds 250
    }
    throw 'ChatGPT composer did not become stable in time.'
}
function Wait-NewChatWebViewReady($root, [int]$TimeoutMilliseconds = 20000) {
    # A stable composer across two sampling windows is the WebView-ready signal.
    [void](Wait-ComposerStable $root $TimeoutMilliseconds)
    Start-Sleep -Milliseconds 500
    return (Wait-ComposerStable $root 5000)
}
function Focus-Composer($root, [int]$Attempts = 12) {
    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        try {
            $composer = Get-Composer $root
            if ($composer) { $composer.SetFocus(); return $composer }
        } catch {}
        Start-Sleep -Milliseconds 200
    }
    throw 'ChatGPT composer could not be focused after retries.'
}
function Click-Composer($root, [int]$Attempts = 12) {
    Ensure-MouseNative
    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        try {
            $composer = Get-Composer $root
            if ($composer) {
                $r = $composer.Current.BoundingRectangle
                $x = [int]($r.X + [math]::Min([math]::Max(60, $r.Width * 0.35), $r.Width - 60))
                $y = [int]($r.Y + [math]::Max(10, $r.Height / 2))
                [void][ChatGPTMouseNative]::SetCursorPos($x, $y)
                [ChatGPTMouseNative]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
                [ChatGPTMouseNative]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
                Start-Sleep -Milliseconds 150
                return $composer
            }
        } catch {}
        Start-Sleep -Milliseconds 200
    }
    throw 'ChatGPT composer could not be clicked after retries.'
}
function Get-NewChatButton($root) {
    $rr = $root.Current.BoundingRectangle
    $exact = @()
    foreach ($e in (Get-AllElements $root)) {
        try {
            if ($e.Current.ControlType -ne [System.Windows.Automation.ControlType]::Button) { continue }
            if ($e.Current.IsOffscreen -or -not $e.Current.IsEnabled) { continue }
            if (([string]$e.Current.Name).Trim() -notin @('새 채팅','New chat')) { continue }
            $r = $e.Current.BoundingRectangle
            if ($r.X -lt ($rr.X + ($rr.Width * 0.35)) -and $r.Y -lt ($rr.Y + ($rr.Height * 0.30))) { $exact += $e }
        } catch {}
    }
    if ($exact.Count -gt 0) {
        return $exact | Sort-Object { $_.Current.BoundingRectangle.Y } | Select-Object -First 1
    }
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
function Test-ComposerInWorkMode($root) {
    $composer = Get-Composer $root
    if (-not $composer) { return $false }
    $label = "$(Get-ComposerValue $composer) $([string]$composer.Current.Name)"
    return $label -match '(?i)(Work 시작|Start Work|with Work)'
}
function Ensure-ChatMode($root) {
    $chat = Find-VisibleElementByExactName $root @('Chat') ([System.Windows.Automation.ControlType]::Button)
    if ($chat) {
        if (-not (Click-Element $chat)) { throw 'Chat mode control was found but could not be clicked.' }
    } elseif (Test-ComposerInWorkMode $root) {
        # Reference point from the Chat/Work segmented control. Both axes scale
        # with the live window bounds, so maximized and restored layouts agree.
        [void](Click-WindowRatio $root 0.645 0.045 'Chat mode fallback')
    } else {
        return $true
    }
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
        if (-not (Test-ComposerInWorkMode $root)) { return $true }
    }
    throw 'Chat mode could not be confirmed; Work mode remained active.'
}
function Get-AddMenuButton($root, $composer) {
    $cr = $composer.Current.BoundingRectangle
    $best = $null
    foreach ($e in (Get-AllElements $root)) {
        try {
            if ($e.Current.ControlType -ne [System.Windows.Automation.ControlType]::Button) { continue }
            if ($e.Current.IsOffscreen -or -not $e.Current.IsEnabled) { continue }
            $name = ([string]$e.Current.Name).Trim()
            if ($name -notmatch '(?i)^(파일 등 추가|Add files|Add files and more)$') { continue }
            $r = $e.Current.BoundingRectangle
            if ($r.Y -ge ($cr.Y - 30) -and $r.Y -le ($cr.Y + $cr.Height + 30)) { $best = $e; break }
        } catch {}
    }
    return $best
}
function Find-RemotePluginMenuItem($root, $composer) {
    $cr = $composer.Current.BoundingRectangle
    $best = $null
    $bestWidth = [double]::MaxValue
    foreach ($e in (Get-AllElements $root)) {
        try {
            if ($e.Current.IsOffscreen -or -not $e.Current.IsEnabled) { continue }
            $name = ([string]$e.Current.Name).Replace("`r",' ').Replace("`n",' ').Trim()
            if ($name -notmatch '(?i)^AI Folder Remote(?:\s|$)') { continue }
            $r = $e.Current.BoundingRectangle
            $isActionable = $e.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -or
                $e.Current.ControlType -eq [System.Windows.Automation.ControlType]::ListItem -or
                $e.Current.ControlType -eq [System.Windows.Automation.ControlType]::MenuItem
            if (-not $isActionable) { continue }
            # The committed token is small and overlaps the composer. The menu
            # row is wider or sits outside that band; only return the menu row.
            $overlapsComposer = $r.Y -lt ($cr.Y + $cr.Height) -and ($r.Y + $r.Height) -gt $cr.Y
            if ($overlapsComposer -and $r.Width -lt 320) { continue }
            if ($r.Width -lt $bestWidth) { $best = $e; $bestWidth = $r.Width }
        } catch {}
    }
    return $best
}
function Test-RemotePluginCommitted($root, $composer) {
    $cr = $composer.Current.BoundingRectangle
    foreach ($e in (Get-AllElements $root)) {
        try {
            if ($e.Current.IsOffscreen) { continue }
            $name = ([string]$e.Current.Name).Trim()
            if ($name -ne 'AI Folder Remote') { continue }
            $r = $e.Current.BoundingRectangle
            if ($r.Width -le 360 -and $r.Y -lt ($cr.Y + $cr.Height + 30) -and ($r.Y + $r.Height) -gt ($cr.Y - 30)) { return $true }
        } catch {}
    }
    return $false
}
function Select-RemotePluginFromAddMenu($root, $composer) {
    $add = Get-AddMenuButton $root $composer
    if ($add) {
        if (-not (Click-Element $add)) { throw 'ChatGPT add-menu button could not be clicked.' }
    } else {
        [void](Click-ComposerRatio $root $composer 0.025 0.78 'composer add-menu fallback')
    }

    $item = $null
    $rr = $root.Current.BoundingRectangle
    $cr = $composer.Current.BoundingRectangle
    $scrollX = [int]([math]::Min($rr.X + ($rr.Width * 0.65), $cr.X + 260))
    $scrollY = [int]([math]::Max($rr.Y + 150, $cr.Y - 220))
    for ($attempt = 0; $attempt -lt 12 -and -not $item; $attempt++) {
        Start-Sleep -Milliseconds 300
        $item = Find-RemotePluginMenuItem $root $composer
        if (-not $item -and $attempt -ge 2) { Scroll-Native $scrollX $scrollY -480 }
    }
    if (-not $item) { throw 'AI Folder Remote was not found in the add menu after proportional scrolling.' }
    if (-not (Click-Element $item)) { throw 'AI Folder Remote add-menu item could not be clicked.' }

    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
        $current = Get-Composer $root
        if ($current -and (Test-RemotePluginCommitted $root $current)) { return $current }
    }
    throw 'AI Folder Remote was clicked but no committed composer token was detected.'
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
function Click-Element($element) {
    if (-not $element) { return $false }
    try {
        Ensure-MouseNative
        $r = $element.Current.BoundingRectangle
        if ($r.Width -le 0 -or $r.Height -le 0) { return $false }
        $x = [int]($r.X + ($r.Width / 2))
        $y = [int]($r.Y + ($r.Height / 2))
        [void][ChatGPTMouseNative]::SetCursorPos($x, $y)
        [ChatGPTMouseNative]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
        [ChatGPTMouseNative]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
        Start-Sleep -Milliseconds 250
        return $true
    } catch { return $false }
}
function Find-RemoteMentionCandidate($root) {
    try {
        $composer = Get-Composer $root
        if (-not $composer) { return $null }
        $cr = $composer.Current.BoundingRectangle
        $matches = @()
        foreach ($e in (Get-AllElements $root)) {
            try {
                if ($e.Current.IsOffscreen -or -not $e.Current.IsEnabled) { continue }
                if ($e.Current.Name -notmatch '(?i)^AI Folder Remote') { continue }
                $r = $e.Current.BoundingRectangle
                if ($r.Y -lt ($cr.Y - 800) -or $r.Y -gt ($cr.Y + 300)) { continue }
                $matches += $e
            } catch {}
        }
        $actionable = $matches | Where-Object {
            $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -or $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::ListItem
        } | Select-Object -First 1
        if ($actionable) { return $actionable }
        return $matches | Select-Object -First 1
    } catch {}
    return $null
}
function Wait-RemoteMentionCandidate($root, [int]$Attempts = 12) {
    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        Start-Sleep -Milliseconds 250
        $candidate = Find-RemoteMentionCandidate $root
        if ($candidate) { return $candidate }
    }
    return $null
}
function Click-WindowRatio($root, [double]$XRatio, [double]$YRatio, [string]$Purpose) {
    Ensure-MouseNative
    $rr = $root.Current.BoundingRectangle
    if ($rr.Width -lt 800 -or $rr.Height -lt 500) { throw "ChatGPT window is too small for proportional click: $Purpose" }
    $x = [int]($rr.X + ($rr.Width * $XRatio))
    $y = [int]($rr.Y + ($rr.Height * $YRatio))
    [void][ChatGPTMouseNative]::SetCursorPos($x, $y)
    [ChatGPTMouseNative]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
    [ChatGPTMouseNative]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
    return [pscustomobject]@{ x=$x; y=$y; x_ratio=$XRatio; y_ratio=$YRatio; purpose=$Purpose }
}
function Click-ComposerRatio($root, $composer, [double]$XRatio, [double]$YRatio, [string]$Purpose) {
    Ensure-MouseNative
    $cr = $composer.Current.BoundingRectangle
    if ($cr.Width -lt 400 -or $cr.Height -lt 30) { throw "ChatGPT composer is not large enough for proportional click: $Purpose" }
    $x = [int]($cr.X + ($cr.Width * $XRatio))
    $y = [int]($cr.Y + ($cr.Height * $YRatio))
    [void][ChatGPTMouseNative]::SetCursorPos($x, $y)
    [ChatGPTMouseNative]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
    [ChatGPTMouseNative]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
    return [pscustomobject]@{ x=$x; y=$y; x_ratio=$XRatio; y_ratio=$YRatio; purpose=$Purpose }
}
function Scroll-Native([int]$X, [int]$Y, [int]$Delta) {
    Ensure-MouseNative
    [void][ChatGPTMouseNative]::SetCursorPos($X, $Y)
    [ChatGPTMouseNative]::mouse_event(0x0800,0,0,$Delta,[UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}
function Find-VisibleElementByExactName($root, [string[]]$Names, $ControlType = $null) {
    foreach ($e in (Get-AllElements $root)) {
        try {
            if ($e.Current.IsOffscreen -or -not $e.Current.IsEnabled) { continue }
            if ($null -ne $ControlType -and $e.Current.ControlType -ne $ControlType) { continue }
            $name = ([string]$e.Current.Name).Trim()
            if ($Names -contains $name) { return $e }
        } catch {}
    }
    return $null
}
function Wait-RemoteMentionDismissed($root, [int]$Attempts = 8) {
    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        Start-Sleep -Milliseconds 250
        if (-not (Find-RemoteMentionCandidate $root)) { return $true }
    }
    return $false
}
function Select-RemoteMention($root, $composer, $shell) {
    $candidate = $null
    for ($inputAttempt = 1; $inputAttempt -le 3 -and -not $candidate; $inputAttempt++) {
        [void](Activate-Window (Get-TargetWindow))
        $composer = Click-Composer $root
        Clear-ComposerNative
        [System.Windows.Forms.Clipboard]::SetText('@AI Folder Remote')
        Paste-ClipboardNative
        Start-Sleep -Milliseconds 500
        $current = Get-Composer $root
        $currentValue = Get-ComposerValue $current
        if ($currentValue -notmatch '(?i)AI Folder Remote') { Start-Sleep -Milliseconds 350; continue }
        $candidate = Wait-RemoteMentionCandidate $root 20
        if (-not $candidate) { Start-Sleep -Milliseconds 350 }
    }
    if (-not $candidate) { throw 'AI Folder Remote mention picker did not appear.' }
    # SetFocus is not selection for WebView list rows. Use a physical click so
    # the mention is committed as a chip before the prompt is pasted.
    if (-not (Click-Element $candidate)) { throw 'AI Folder Remote mention could not be selected.' }
    if (-not (Wait-RemoteMentionDismissed $root)) { throw 'AI Folder Remote mention picker remained visible after click.' }
    Start-Sleep -Milliseconds 600
    [void](Handle-ContinueInChat $root 1200)
    $composer = Click-Composer $root
    Send-NativeKey 0x20
}
function Find-ContinueInChatButton($root) {
    $buttons = @()
    $rr = $root.Current.BoundingRectangle
    foreach ($e in (Get-AllElements $root)) {
        if ($e.Current.ControlType -ne [System.Windows.Automation.ControlType]::Button) { continue }
        if ($e.Current.IsOffscreen -or -not $e.Current.IsEnabled) { continue }
        $name = [string]$e.Current.Name
        if ($name -match '(?i)(continue.*chat|keep.*chat|chat.*continue)') { return $e }
        $r = $e.Current.BoundingRectangle
        if ($r.Y -gt ($rr.Y + ($rr.Height * 0.55)) -and $r.X -gt ($rr.X + ($rr.Width * 0.45)) -and $r.Width -ge 90 -and $r.Width -le 320 -and $r.Height -ge 38 -and $r.Height -le 80) { $buttons += $e }
    }
    $work = $buttons | Where-Object { ([string]$_.Current.Name) -match '(?i)Work' } | Select-Object -First 1
    if ($work) {
        $wr = $work.Current.BoundingRectangle
        return $buttons | Where-Object {
            $r = $_.Current.BoundingRectangle
            $r.X -lt $wr.X -and [math]::Abs($r.Y - $wr.Y) -le 25
        } | Sort-Object { $work.Current.BoundingRectangle.X - $_.Current.BoundingRectangle.X } | Select-Object -First 1
    }
    return $null
}
function Handle-ContinueInChat($root, [int]$TimeoutMilliseconds = 30000) {
    $deadline = (Get-Date).AddMilliseconds($TimeoutMilliseconds)
    while ((Get-Date) -lt $deadline) {
        $button = Find-ContinueInChatButton $root
        if ($button -and (Invoke-Element $button)) { Start-Sleep -Milliseconds 700; return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}
function Get-UnicodeText([int[]]$Codes) {
    return -join ($Codes | ForEach-Object { [char]$_ })
}
function Test-ChatGPTBusy($root) {
    $stopKo = Get-UnicodeText @(0xC911,0xC9C0)
    foreach ($e in (Get-AllElements $root)) {
        try {
            if ($e.Current.IsOffscreen) { continue }
            $name = [string]$e.Current.Name
            if ($name -match '(?i)(stop generating|stop response|cancel generation)') { return $true }
            if ($e.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and $name.Contains($stopKo)) { return $true }
        } catch {}
    }
    return $false
}
function Find-StopGeneratingButton($root) {
    $stopKo = Get-UnicodeText @(0xC911,0xC9C0)
    foreach ($e in (Get-AllElements $root)) {
        try {
            if ($e.Current.IsOffscreen -or -not $e.Current.IsEnabled) { continue }
            if ($e.Current.ControlType -ne [System.Windows.Automation.ControlType]::Button) { continue }
            $name = [string]$e.Current.Name
            if ($name -match '(?i)^(stop|stop generating|stop response|cancel generation)$') { return $e }
            if ($name -eq $stopKo) { return $e }
        } catch {}
    }
    return $null
}
function Wait-ChatGPTIdle($root, [int]$TimeoutMilliseconds = 120000, [int]$QuietMilliseconds = 3000) {
    $deadline = (Get-Date).AddMilliseconds($TimeoutMilliseconds)
    $quietSince = $null
    while ((Get-Date) -lt $deadline) {
        if (Test-ChatGPTBusy $root) { $quietSince = $null }
        else {
            if ($null -eq $quietSince) { $quietSince = Get-Date }
            if (((Get-Date) - $quietSince).TotalMilliseconds -ge $QuietMilliseconds) { return $true }
        }
        Start-Sleep -Milliseconds 500
    }
    return $false
}
function Wait-ComposerEmpty($root, [int]$TimeoutMilliseconds = 4000) {
    $deadline = (Get-Date).AddMilliseconds($TimeoutMilliseconds)
    while ((Get-Date) -lt $deadline) {
        $current = Get-Composer $root
        if (-not $current -or [string]::IsNullOrWhiteSpace((Get-ComposerValue $current))) { return $true }
        Start-Sleep -Milliseconds 200
    }
    return $false
}
function Invoke-ComposerSubmit($root, $composer, $shell) {
    $composer = Click-Composer $root
    Send-NativeKey 0x0D
    [void](Handle-ContinueInChat $root 1500)
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
    if ($send) { [void](Invoke-Element $send); [void](Handle-ContinueInChat $root 1500) }
    return (Wait-ComposerEmpty $root 4000)
}switch ($Action) {
    'ChatGPTWaitIdle' {
        $target = Get-TargetWindow
        if (-not $target) { throw 'ChatGPT desktop window was not found.' }
        if ($DryRun) { [pscustomobject]@{ action='ChatGPTWaitIdle'; dry_run=$true } | ConvertTo-Json -Compress; break }
        Add-Type -AssemblyName UIAutomationClient
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($target.MainWindowHandle)
        if (-not $root) { throw 'ChatGPT UI Automation root was not found.' }
        $idle = Wait-ChatGPTIdle $root $IdleTimeoutMilliseconds $IdleQuietMilliseconds
        $forced = $false
        if (-not $idle -and $ForceStopAfterTimeout) {
            $stopButton = Find-StopGeneratingButton $root
            if ($stopButton -and (Click-Element $stopButton)) {
                $forced = $true
                $idle = Wait-ChatGPTIdle $root 10000 $IdleQuietMilliseconds
            }
        }
        if (-not $idle) { throw 'ChatGPT response did not become idle before timeout.' }
        [pscustomobject]@{ action='ChatGPTWaitIdle'; idle=$true; quiet_ms=$IdleQuietMilliseconds; forced_stop=$forced } | ConvertTo-Json -Compress
        break
    }
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
    'ChatGPTProbeLayout' {
        $target = Get-TargetWindow
        if (-not $target) { throw 'ChatGPT desktop window was not found.' }
        Add-Type -AssemblyName UIAutomationClient
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($target.MainWindowHandle)
        if (-not $root) { throw 'ChatGPT UI Automation root was not found.' }
        $rr = $root.Current.BoundingRectangle
        $composer = Get-Composer $root
        $cr = if ($composer) { $composer.Current.BoundingRectangle } else { $null }
        $newChat = Get-NewChatButton $root
        $add = if ($composer) { Get-AddMenuButton $root $composer } else { $null }
        [pscustomobject]@{
            action='ChatGPTProbeLayout'; pid=$target.Id
            window=@{ x=[int]$rr.X; y=[int]$rr.Y; width=[int]$rr.Width; height=[int]$rr.Height }
            composer=if($cr){ @{ x=[int]$cr.X; y=[int]$cr.Y; width=[int]$cr.Width; height=[int]$cr.Height; name=[string]$composer.Current.Name } }else{$null}
            new_chat_found=[bool]$newChat; add_menu_found=[bool]$add; work_mode=[bool](Test-ComposerInWorkMode $root)
            fallback=@{ chat=@{x_ratio=0.645;y_ratio=0.045}; add=@{composer_x_ratio=0.025;composer_y_ratio=0.78} }
        } | ConvertTo-Json -Depth 5 -Compress
        break
    }
    'ChatGPTProbePlugin' {
        $target = Get-TargetWindow
        if (-not $target) { throw 'ChatGPT desktop window was not found.' }
        if ($DryRun) { [pscustomobject]@{action='ChatGPTProbePlugin';dry_run=$true}|ConvertTo-Json -Compress; break }
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName UIAutomationClient
        [void](Activate-Window $target)
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($target.MainWindowHandle)
        $newChat = Get-NewChatButton $root
        if ($newChat) { [void](Click-Element $newChat) } else { [void](Click-WindowRatio $root 0.055 0.095 'new chat fallback') }
        [void](Activate-Window $target)
        $composer = Wait-NewChatWebViewReady $root 20000
        [void](Ensure-ChatMode $root)
        $composer = Wait-NewChatWebViewReady $root 10000
        $composer = Select-RemotePluginFromAddMenu $root $composer
        [pscustomobject]@{ action='ChatGPTProbePlugin'; chat_mode=$true; plugin_committed=$true; submitted=$false; window_width=[int]$root.Current.BoundingRectangle.Width; window_height=[int]$root.Current.BoundingRectangle.Height } | ConvertTo-Json -Compress
        break
    }
    'ChatGPTContinueCurrent' {
        $target = Get-TargetWindow
        if (-not $target) { throw 'ChatGPT desktop window was not found.' }
        if ([string]::IsNullOrWhiteSpace($Prompt)) { throw 'Prompt is required.' }
        if ($DryRun) { [pscustomobject]@{action='ChatGPTContinueCurrent';prompt_chars=$Prompt.Length;dry_run=$true}|ConvertTo-Json -Compress; break }
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName UIAutomationClient
        $shell = Activate-Window $target
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($target.MainWindowHandle)
        $composer = Wait-NewChatWebViewReady $root 10000
        [void](Ensure-ChatMode $root)
        $previousClipboard = [System.Windows.Forms.Clipboard]::GetDataObject()
        try {
            if ($UseRemoteMention) { $composer = Select-RemotePluginFromAddMenu $root $composer }
            $composer = Click-Composer $root
            [System.Windows.Forms.Clipboard]::SetText($Prompt)
            Paste-ClipboardNative
            Start-Sleep -Milliseconds 300
            $ok = Invoke-ComposerSubmit $root $composer $shell
            if (-not $ok) { throw 'Recovery prompt remained in the current composer after submit retries.' }
            $routeHandled = Handle-ContinueInChat $root 30000
        } finally {
            if ($null -ne $previousClipboard) { [System.Windows.Forms.Clipboard]::SetDataObject($previousClipboard, $true) }
        }
        [pscustomobject]@{action='ChatGPTContinueCurrent';remote_mention=[bool]$UseRemoteMention;prompt_chars=$Prompt.Length;submitted=$true;route_handled=[bool]$routeHandled}|ConvertTo-Json -Compress
        break
    }
    'ChatGPTRoutePending' {
        $target = Get-TargetWindow
        if (-not $target) { throw 'ChatGPT desktop window was not found.' }
        if ($DryRun) { [pscustomobject]@{ action='ChatGPTRoutePending'; dry_run=$true } | ConvertTo-Json -Compress; break }
        Add-Type -AssemblyName UIAutomationClient
        [void](Activate-Window $target)
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($target.MainWindowHandle)
        $handled = Handle-ContinueInChat $root 5000
        [pscustomobject]@{ action='ChatGPTRoutePending'; route_handled=[bool]$handled } | ConvertTo-Json -Compress
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
        $composer = Focus-Composer $root
        $before = Get-ComposerValue $composer
        if ([string]::IsNullOrWhiteSpace($before)) { [pscustomobject]@{ action='ChatGPTSubmitPending'; submitted=$false; reason='composer_empty' } | ConvertTo-Json -Compress; break }
        $ok = Invoke-ComposerSubmit $root $composer $shell
        if (-not $ok) { throw 'Pending ChatGPT prompt remained in the composer after submit retries.' }
        $routeHandled = Handle-ContinueInChat $root 30000
        [pscustomobject]@{ action='ChatGPTSubmitPending'; submitted=$true; submitted_verified=$true; route_handled=[bool]$routeHandled; previous_chars=$before.Length } | ConvertTo-Json -Compress
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
        if ($newChat) {
            if (-not (Click-Element $newChat)) { throw 'ChatGPT new-chat control could not be clicked.' }
        } else {
            [void](Click-WindowRatio $root 0.055 0.095 'new chat fallback')
        }
        # Navigation re-renders the WebView; re-check foreground before typing.
        [void](Activate-Window $target)
        $composer = Wait-NewChatWebViewReady $root 20000
        [void](Ensure-ChatMode $root)
        $composer = Wait-NewChatWebViewReady $root 10000
        $composer = Click-Composer $root
        $previousClipboard = [System.Windows.Forms.Clipboard]::GetDataObject()
        try {
            if ($UseRemoteMention) { $composer = Select-RemotePluginFromAddMenu $root $composer }
            $composer = Click-Composer $root
            [System.Windows.Forms.Clipboard]::SetText($Prompt)
            Paste-ClipboardNative
            Start-Sleep -Milliseconds 300
            $ok = Invoke-ComposerSubmit $root $composer $shell
            if (-not $ok) { throw 'ChatGPT prompt remained in the composer after submit retries.' }
            $routeHandled = Handle-ContinueInChat $root 30000
        } finally {
            if ($null -ne $previousClipboard) { [System.Windows.Forms.Clipboard]::SetDataObject($previousClipboard, $true) }
        }
        [pscustomobject]@{ action='ChatGPTPrompt'; process=$target.ProcessName; pid=$target.Id; strategy='UIAutomation'; remote_mention=[bool]$UseRemoteMention; prompt_chars=$Prompt.Length; submitted=$true; submitted_verified=$true; route_handled=[bool]$routeHandled; dry_run=$false } | ConvertTo-Json -Compress
        break
    }
}
