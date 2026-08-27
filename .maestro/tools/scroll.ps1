<#
.SYNOPSIS
Scroll the wheel over a point in the app window.

.DESCRIPTION
Windows routes wheel events to the window under the *cursor*, not the focused
one, so the cursor is parked over the target first. With no -X/-Y that is the
centre of the window, which is the right default for the distro list.

-Amount is in wheel notches: negative scrolls down (the natural direction for
"show me more of the list"), positive scrolls up.

.EXAMPLE
.\scroll.ps1 -Amount -5
.EXAMPLE
.\scroll.ps1 -Amount 3 -X 400 -Y 500
.EXAMPLE
.\scroll.ps1 -Amount -2 -Horizontal
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][int]$Amount = -3,
    [Nullable[int]]$X = $null,
    [Nullable[int]]$Y = $null,
    [switch]$Horizontal,
    [ValidateRange(1, 20)][int]$Steps = 0,
    [int]$DelayMs = 80,
    [switch]$NoFocus,
    [long]$Handle = 0,
    [string[]]$ProcessName,
    [string]$TitleMatch,
    [switch]$Quiet
)

. "$PSScriptRoot\_common.ps1"

if ($Amount -eq 0) { throw "-Amount 0 would scroll nothing. Use a negative value to scroll down, positive to scroll up." }

$resolve = @{}
if ($Handle -ne 0) { $resolve.Handle = $Handle }
if ($ProcessName)  { $resolve.ProcessName = $ProcessName }
if ($TitleMatch)   { $resolve.TitleMatch = $TitleMatch }
$window = Get-AppWindow @resolve

Confirm-AppFocus -Window $window -NoFocus:$NoFocus

$bounds = Get-AppBounds -Window $window
$relX = if ($null -ne $X) { $X } else { [int]($bounds.Width / 2) }
$relY = if ($null -ne $Y) { $Y } else { [int]($bounds.Height / 2) }
$point = ConvertTo-ScreenPoint -Window $window -X $relX -Y $relY

[Maestro.Native]::SetCursorPos($point.X, $point.Y) | Out-Null
Start-Sleep -Milliseconds 60

# One notch at a time by default: a single large delta is treated as one event by
# some scroll views and under-scrolls compared with a real wheel.
if ($Steps -le 0) { $Steps = [Math]::Abs($Amount) }
$sign = [Math]::Sign($Amount)
$perStep = [int]([Math]::Abs($Amount) / $Steps)
$remainder = [Math]::Abs($Amount) - ($perStep * $Steps)

for ($i = 0; $i -lt $Steps; $i++) {
    $n = $perStep + $(if ($i -lt $remainder) { 1 } else { 0 })
    if ($n -eq 0) { continue }
    [Maestro.Native]::Wheel($sign * $n, [bool]$Horizontal)
    Start-Sleep -Milliseconds 40
}

if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }

if (-not $Quiet) {
    $axis = if ($Horizontal) { 'horizontally' } else { 'vertically' }
    $dir  = if ($Horizontal) { if ($sign -gt 0) { 'right' } else { 'left' } }
            else             { if ($sign -gt 0) { 'up' }    else { 'down' } }
    Write-Host ("Scrolled {0} notch(es) {1} ({2}) at window({3},{4})" -f [Math]::Abs($Amount), $axis, $dir, $relX, $relY)
}
