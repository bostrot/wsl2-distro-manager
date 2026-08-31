<#
.SYNOPSIS
Click at a window-relative point.

.DESCRIPTION
(0,0) is the top-left of the visible frame -- the same origin shot.ps1 captures
from, so coordinates read off a screenshot with an image viewer land on the right
pixel. Negative values count back from the right/bottom edge.

The window is focused first (unless -NoFocus); a click delivered to a background
window is swallowed by Windows as a mere activation click.

.EXAMPLE
.\click.ps1 -X 120 -Y 260
.EXAMPLE
.\click.ps1 -X 400 -Y 300 -Count 2          # double click
.EXAMPLE
.\click.ps1 -X -40 -Y 20 -Button right      # 40px in from the right edge
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][int]$X,
    [Parameter(Mandatory, Position = 1)][int]$Y,
    [ValidateSet('left', 'right', 'middle')][string]$Button = 'left',
    [ValidateRange(1, 10)][int]$Count = 1,
    [int]$DelayMs = 90,
    [switch]$MoveOnly,
    [switch]$Screen,
    [switch]$NoFocus,
    [switch]$RestoreCursor,
    [long]$Handle = 0,
    [string[]]$ProcessName,
    [string]$TitleMatch,
    [switch]$Quiet
)

. "$PSScriptRoot\_common.ps1"

$down, $up = switch ($Button) {
    'left'   { [Maestro.Native]::MOUSEEVENTF_LEFTDOWN,   [Maestro.Native]::MOUSEEVENTF_LEFTUP }
    'right'  { [Maestro.Native]::MOUSEEVENTF_RIGHTDOWN,  [Maestro.Native]::MOUSEEVENTF_RIGHTUP }
    'middle' { [Maestro.Native]::MOUSEEVENTF_MIDDLEDOWN, [Maestro.Native]::MOUSEEVENTF_MIDDLEUP }
}

$resolve = @{}
if ($Handle -ne 0) { $resolve.Handle = $Handle }
if ($ProcessName)  { $resolve.ProcessName = $ProcessName }
if ($TitleMatch)   { $resolve.TitleMatch = $TitleMatch }
$window = Get-AppWindow @resolve

Confirm-AppFocus -Window $window -NoFocus:$NoFocus

if ($Screen) {
    $point = [pscustomobject]@{ X = $X; Y = $Y; RelativeX = $X; RelativeY = $Y }
} else {
    $point = ConvertTo-ScreenPoint -Window $window -X $X -Y $Y
}

$origin = $null
if ($RestoreCursor) {
    $p = New-Object Maestro.POINT
    if ([Maestro.Native]::GetCursorPos([ref]$p)) { $origin = $p }
}

[Maestro.Native]::SetCursorPos($point.X, $point.Y) | Out-Null
Start-Sleep -Milliseconds 60   # let hover state settle before pressing

if (-not $MoveOnly) {
    for ($i = 0; $i -lt $Count; $i++) {
        if ($i -gt 0) { Start-Sleep -Milliseconds 80 }   # under the 500ms double-click threshold
        [Maestro.Native]::MouseButton($down)
        Start-Sleep -Milliseconds 40
        [Maestro.Native]::MouseButton($up)
    }
}

if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
if ($origin) { [Maestro.Native]::SetCursorPos($origin.X, $origin.Y) | Out-Null }

if (-not $Quiet) {
    $verb = if ($MoveOnly) { 'Moved to' } else { "${Count}x $Button click at" }
    Write-Host ("{0} window({1},{2}) = screen({3},{4})" -f $verb, $point.RelativeX, $point.RelativeY, $point.X, $point.Y)
}
