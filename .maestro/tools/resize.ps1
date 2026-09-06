<#
.SYNOPSIS
Move and resize the app window to an exact visible size.

.DESCRIPTION
Calls MoveWindow directly. It deliberately does NOT call
ShowWindow(SW_RESTORE) first: the app restores its own geometry from
shared_preferences during startup, and a restore issued while that is still in
flight races it -- the window snaps back to the saved size a moment later and the
resize looks like it silently did nothing. Wait ~10s after launch (launch.ps1
already does) and just move the window. If the window really is minimised, pass
-Restore to opt into the SW_RESTORE call.

-Width/-Height are the *visible* size, matching what shot.ps1 captures. Windows
10/11 pad every window with an invisible resize border, so the rectangle
MoveWindow consumes is larger than the frame you see; the difference between
GetWindowRect and the DWM frame bounds is measured at call time and added, which
means asking for 1280x800 gives a 1280x800 PNG. Pass -Raw to feed the numbers to
MoveWindow untouched instead.

.EXAMPLE
.\resize.ps1 -Width 1280 -Height 800
.EXAMPLE
.\resize.ps1 -Width 1600 -Height 900 -X 40 -Y 40

.OUTPUTS
The resulting visible bounds.
#>
[CmdletBinding()]
param(
    [int]$Width = 1280,
    [int]$Height = 800,
    [Nullable[int]]$X = $null,
    [Nullable[int]]$Y = $null,
    [long]$Handle = 0,
    [string[]]$ProcessName,
    [string]$TitleMatch,
    [switch]$Raw,
    [switch]$Restore,
    [switch]$NoFocus,
    [switch]$Quiet
)

. "$PSScriptRoot\_common.ps1"

if ($Width -lt 200 -or $Height -lt 150) { throw "Refusing to resize to ${Width}x${Height}; that is smaller than the app's minimum usable size." }

$resolve = @{}
if ($Handle -ne 0) { $resolve.Handle = $Handle }
if ($ProcessName)  { $resolve.ProcessName = $ProcessName }
if ($TitleMatch)   { $resolve.TitleMatch = $TitleMatch }
$window = Get-AppWindow @resolve

# Only ever restore on explicit request -- see the race described above.
if ($Restore -and [Maestro.Native]::IsIconic($window.Handle)) {
    [Maestro.Native]::ShowWindow($window.Handle, [Maestro.Native]::SW_RESTORE) | Out-Null
    Start-Sleep -Milliseconds 300
}

$frame = Get-AppBounds -Window $window          # what the user sees
$outer = Get-AppBounds -Window $window -Raw     # what MoveWindow speaks

if ($Raw) {
    $padW = 0; $padH = 0; $padX = 0; $padY = 0
} else {
    $padW = $outer.Width  - $frame.Width          # invisible border, left + right
    $padH = $outer.Height - $frame.Height         # invisible border, bottom
    $padX = $frame.X - $outer.X                   # left border thickness
    $padY = $frame.Y - $outer.Y                   # top border thickness (usually 0)
}

$targetX = if ($null -ne $X) { $X - $padX } else { $outer.X }
$targetY = if ($null -ne $Y) { $Y - $padY } else { $outer.Y }

if (-not [Maestro.Native]::MoveWindow($window.Handle, $targetX, $targetY,
                                      $Width + $padW, $Height + $padH, $true)) {
    throw "MoveWindow failed for hwnd $($window.HandleValue) (win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))."
}

if (-not $NoFocus) { Confirm-AppFocus -Window $window }
Start-Sleep -Milliseconds 250

$after = Get-AppBounds -Window $window
$dw = $after.Width - $Width; $dh = $after.Height - $Height

if (-not $Quiet) {
    Write-Host ("Resized to {0}x{1} at ({2},{3}); border compensation {4}x{5}px." -f `
        $after.Width, $after.Height, $after.X, $after.Y, $padW, $padH)
}
if ([Math]::Abs($dw) -gt 2 -or [Math]::Abs($dh) -gt 2) {
    Write-Warning ("Window settled at {0}x{1}, {2}x{3}px off the request. The app may still be restoring its saved geometry -- wait longer after launch, or it has hit a minimum-size constraint." -f $after.Width, $after.Height, $dw, $dh)
}

$after
