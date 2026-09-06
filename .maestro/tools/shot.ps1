<#
.SYNOPSIS
Capture the app window to a PNG, cropped exactly to the visible frame.

.DESCRIPTION
Uses DWMWA_EXTENDED_FRAME_BOUNDS rather than GetWindowRect. GetWindowRect
includes the invisible resize border Windows 10/11 pads every window with --
measured at 7px left, right and bottom on this machine -- which is what made the
previous helper capture roughly 8px of desktop on every side. The DWM rectangle
is the frame the user actually sees, so the window content sits flush against
the image edges.

The window is focused and raised first (unless -NoFocus), because
CopyFromScreen reads real screen pixels: anything overlapping the window would
otherwise be baked into the capture.

.EXAMPLE
.\shot.ps1 -Path .maestro\screenshots\phase-01\home.png
.EXAMPLE
.\shot.ps1                     # -> .maestro\screenshots\<timestamp>.png

.OUTPUTS
The full path of the PNG that was written.
#>
[CmdletBinding()]
param(
    [string]$Path,
    [long]$Handle = 0,
    [string[]]$ProcessName,
    [string]$TitleMatch,
    [switch]$NoFocus,
    [int]$SettleMs = 400,
    [switch]$Raw,
    [switch]$Quiet
)

. "$PSScriptRoot\_common.ps1"
Add-Type -AssemblyName System.Drawing

$resolve = @{}
if ($Handle -ne 0) { $resolve.Handle = $Handle }
if ($ProcessName)  { $resolve.ProcessName = $ProcessName }
if ($TitleMatch)   { $resolve.TitleMatch = $TitleMatch }
$window = Get-AppWindow @resolve

Confirm-AppFocus -Window $window -NoFocus:$NoFocus

# Let the compositor finish drawing whatever the last action triggered.
if ($SettleMs -gt 0) { Start-Sleep -Milliseconds $SettleMs }

$b = Get-AppBounds -Window $window -Raw:$Raw
if ($b.Width -le 0 -or $b.Height -le 0) {
    throw "Window $($window.HandleValue) has no drawable area ($($b.Width)x$($b.Height)); is it minimised?"
}

if (-not $Path) {
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $Path  = Join-Path $MaestroRepoRoot ".maestro\screenshots\$stamp.png"
}
if (-not [System.IO.Path]::IsPathRooted($Path)) { $Path = Join-Path $MaestroRepoRoot $Path }

$dir = Split-Path -Parent $Path
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$bmp = $null; $gfx = $null
try {
    $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height,
                [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.CopyFromScreen($b.X, $b.Y, 0, 0,
        (New-Object System.Drawing.Size($b.Width, $b.Height)),
        [System.Drawing.CopyPixelOperation]::SourceCopy)
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    if ($gfx) { $gfx.Dispose() }
    if ($bmp) { $bmp.Dispose() }
}

if (-not $Quiet) {
    $kind = if ($Raw) { 'GetWindowRect (raw)' } else { 'DWM extended frame bounds' }
    Write-Host ("Captured {0}x{1} at ({2},{3}) via {4} -> {5}" -f $b.Width, $b.Height, $b.X, $b.Y, $kind, $Path)
}

$Path
