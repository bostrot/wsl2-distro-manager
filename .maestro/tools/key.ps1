<#
.SYNOPSIS
Send key chords to the app window.

.DESCRIPTION
Each argument is one chord: modifiers joined with '+' followed by a single key,
e.g. 'enter', 'ctrl+shift+p', 'alt+f4', 'down'. Chords are sent in order.

Real virtual-key events (SendInput) are used rather than SendKeys, so there is
no brace-escaping syntax to get wrong and no dependency on WinForms message
pumping. Arrow/navigation keys are flagged KEYEVENTF_EXTENDEDKEY, which some
apps check to distinguish them from the numpad.

Use type.ps1 for literal text -- this script is for named keys and shortcuts.

.EXAMPLE
.\key.ps1 enter
.EXAMPLE
.\key.ps1 ctrl+a delete
.EXAMPLE
.\key.ps1 tab -Repeat 3
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0, ValueFromRemainingArguments)][string[]]$Keys,
    [ValidateRange(1, 100)][int]$Repeat = 1,
    [int]$DelayMs = 60,
    [switch]$NoFocus,
    [long]$Handle = 0,
    [string[]]$ProcessName,
    [string]$TitleMatch,
    [switch]$Quiet
)

. "$PSScriptRoot\_common.ps1"

$VK = @{
    'backspace' = 0x08; 'bksp' = 0x08; 'tab' = 0x09; 'clear' = 0x0C
    'enter' = 0x0D; 'return' = 0x0D
    'pause' = 0x13; 'capslock' = 0x14; 'esc' = 0x1B; 'escape' = 0x1B
    'space' = 0x20; 'pageup' = 0x21; 'pgup' = 0x21; 'pagedown' = 0x22; 'pgdn' = 0x22
    'end' = 0x23; 'home' = 0x24
    'left' = 0x25; 'up' = 0x26; 'right' = 0x27; 'down' = 0x28
    'printscreen' = 0x2C; 'insert' = 0x2D; 'ins' = 0x2D; 'delete' = 0x2E; 'del' = 0x2E
    'win' = 0x5B; 'lwin' = 0x5B; 'rwin' = 0x5C; 'apps' = 0x5D; 'menu' = 0x5D
    'numlock' = 0x90; 'scrolllock' = 0x91
    'add' = 0x6B; 'subtract' = 0x6D; 'multiply' = 0x6A; 'divide' = 0x6F; 'decimal' = 0x6E
}
foreach ($i in 0..9)  { $VK["$i"] = 0x30 + $i; $VK["num$i"] = 0x60 + $i }
foreach ($c in [char[]]'abcdefghijklmnopqrstuvwxyz') { $VK["$c"] = [int][char]([string]$c).ToUpper() }
foreach ($i in 1..24) { $VK["f$i"] = 0x6F + $i }

# Keys that live on the extended (grey) key block; the flag matters to apps that
# inspect lParam bit 24.
$EXTENDED = @(0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2C, 0x2D, 0x2E, 0x5B, 0x5C, 0x5D, 0x90, 0x6F)

$MOD = @{ 'ctrl' = 0x11; 'control' = 0x11; 'shift' = 0x10; 'alt' = 0x12 }

function Resolve-Chord {
    param([string]$Chord)
    # @() is load-bearing: a chord with no '+' splits to a single string, and
    # $parts[-1] on a bare string returns its last *character*, not the key name.
    $parts = @($Chord.Trim().ToLower() -split '\+' | Where-Object { $_ -ne '' })
    if (-not $parts.Count) { throw "Empty key chord." }

    $mods = @()
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        $m = $parts[$i]
        if (-not $MOD.ContainsKey($m)) { throw "'$m' is not a modifier in chord '$Chord'. Use ctrl, shift or alt." }
        $mods += $MOD[$m]
    }
    $leaf = $parts[-1]
    if (-not $VK.ContainsKey($leaf)) {
        throw "Unknown key '$leaf' in chord '$Chord'. Known: $((($VK.Keys | Sort-Object) -join ', '))"
    }
    [pscustomobject]@{ Modifiers = $mods; Vk = $VK[$leaf]; Text = $Chord }
}

$chords = @($Keys | ForEach-Object { Resolve-Chord $_ })

$resolve = @{}
if ($Handle -ne 0) { $resolve.Handle = $Handle }
if ($ProcessName)  { $resolve.ProcessName = $ProcessName }
if ($TitleMatch)   { $resolve.TitleMatch = $TitleMatch }
$window = Get-AppWindow @resolve

Confirm-AppFocus -Window $window -NoFocus:$NoFocus

for ($r = 0; $r -lt $Repeat; $r++) {
    foreach ($chord in $chords) {
        foreach ($m in $chord.Modifiers) { [Maestro.Native]::Key([uint16]$m, $false, $false) }
        $ext = $EXTENDED -contains $chord.Vk
        [Maestro.Native]::Key([uint16]$chord.Vk, $false, $ext)
        Start-Sleep -Milliseconds 30
        [Maestro.Native]::Key([uint16]$chord.Vk, $true, $ext)
        # Release modifiers in reverse, mirroring a real keyboard.
        for ($i = $chord.Modifiers.Count - 1; $i -ge 0; $i--) {
            [Maestro.Native]::Key([uint16]$chord.Modifiers[$i], $true, $false)
        }
        if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
    }
}

if (-not $Quiet) {
    $suffix = if ($Repeat -gt 1) { " x$Repeat" } else { '' }
    Write-Host ("Sent {0}{1} to '{2}'" -f (($chords | ForEach-Object { $_.Text }) -join ' '), $suffix, $window.Title)
}
