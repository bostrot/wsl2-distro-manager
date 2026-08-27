<#
.SYNOPSIS
Bring the app window to the foreground and keep it there.

.DESCRIPTION
SetForegroundWindow alone is unreliable: Windows refuses it unless the caller
already owns the foreground, and background apps (installers, toasts, IDE
popups) steal it back. This loops -- attach to the foreground thread's input
queue and try again, and if some other window still holds the foreground,
minimise that window -- until GetForegroundWindow() equals the app handle.

Windows that are never minimised: the app itself, the shell/desktop, and
anything listed in -Protect.

.EXAMPLE
.\focus.ps1
.EXAMPLE
.\focus.ps1 -Handle 1247890 -TimeoutSeconds 30

.OUTPUTS
The window info object (Handle, ProcessId, ProcessName, Title).
#>
[CmdletBinding()]
param(
    [long]$Handle = 0,
    [string[]]$ProcessName,
    [string]$TitleMatch,
    [int]$TimeoutSeconds = 15,
    [switch]$NoMinimize,
    [string[]]$Protect = @(),
    [switch]$Quiet
)

. "$PSScriptRoot\_common.ps1"

$resolve = @{}
if ($Handle -ne 0)   { $resolve.Handle = $Handle }
if ($ProcessName)    { $resolve.ProcessName = $ProcessName }
if ($TitleMatch)     { $resolve.TitleMatch = $TitleMatch }
$window = Get-AppWindow @resolve

$shell    = [Maestro.Native]::GetShellWindow()
$desktop  = [Maestro.Native]::GetDesktopWindow()
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$minimized = New-Object System.Collections.Generic.List[string]
$attempt = 0

while ($true) {
    $attempt++
    if ([Maestro.Native]::ForceForeground($window.Handle)) { break }

    $fg = [Maestro.Native]::GetForegroundWindow()

    if ($fg -ne [IntPtr]::Zero -and $fg -ne $window.Handle -and
        $fg -ne $shell -and $fg -ne $desktop -and -not $NoMinimize) {

        $title = [Maestro.Native]::GetTitle($fg)
        $class = [Maestro.Native]::GetClass($fg)

        # WorkerW / Progman are the desktop itself; minimising them does nothing
        # useful and can flash the shell.
        $isShellClass = $class -in @('Progman', 'WorkerW', 'Shell_TrayWnd')
        $isProtected  = $Protect | Where-Object { $title -like "*$_*" }

        if (-not $isShellClass -and -not $isProtected) {
            [Maestro.Native]::ShowWindow($fg, [Maestro.Native]::SW_MINIMIZE) | Out-Null
            $label = if ($title) { $title } else { "<untitled $class>" }
            if (-not $minimized.Contains($label)) { $minimized.Add($label) }
            if (-not $Quiet) { Write-Host "  focus: minimised '$label' to stop it stealing the foreground" }
        }
    }

    if ((Get-Date) -ge $deadline) {
        $holder = [Maestro.Native]::GetTitle([Maestro.Native]::GetForegroundWindow())
        throw "Could not focus '$($window.Title)' within ${TimeoutSeconds}s after $attempt attempts; foreground is held by '$holder'."
    }
    Start-Sleep -Milliseconds 200
}

if (-not $Quiet) {
    Write-Host "Focused '$($window.Title)' (hwnd $($window.HandleValue), pid $($window.ProcessId)) after $attempt attempt(s)."
    if ($minimized.Count) { Write-Host "Minimised along the way: $($minimized -join ', ')" }
}

$window
