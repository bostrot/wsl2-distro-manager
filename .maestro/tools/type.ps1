<#
.SYNOPSIS
Type literal text into the focused control of the app window.

.DESCRIPTION
Sends KEYEVENTF_UNICODE scan codes, which are interpreted independently of the
active keyboard layout. That matters here: the machine this runs on has a German
layout, so a VkKeyScan-based or SendKeys-based helper would mangle 'y'/'z', '@',
'/' and every bracket. It also means no character needs escaping -- '+', '^', '%',
'~', '(' and '{' are all typed literally, unlike with SendKeys.

Newlines in the text are sent as Enter. Use key.ps1 for shortcuts and named keys.

.EXAMPLE
.\type.ps1 "Ubuntu-24.04"
.EXAMPLE
.\type.ps1 -Text "C:\path\with spaces" -ClearFirst

.PARAMETER ClearFirst
Select-all then delete before typing, so the field ends up containing exactly
-Text rather than appending to whatever was there.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][AllowEmptyString()][string]$Text,
    [switch]$ClearFirst,
    [switch]$Enter,
    [int]$DelayMs = 60,
    [int]$CharDelayMs = 0,
    [switch]$NoFocus,
    [long]$Handle = 0,
    [string[]]$ProcessName,
    [string]$TitleMatch,
    [switch]$Quiet
)

. "$PSScriptRoot\_common.ps1"

$resolve = @{}
if ($Handle -ne 0) { $resolve.Handle = $Handle }
if ($ProcessName)  { $resolve.ProcessName = $ProcessName }
if ($TitleMatch)   { $resolve.TitleMatch = $TitleMatch }
$window = Get-AppWindow @resolve

Confirm-AppFocus -Window $window -NoFocus:$NoFocus

if ($ClearFirst) {
    & "$PSScriptRoot\key.ps1" 'ctrl+a' 'delete' -NoFocus -Quiet -Handle $window.HandleValue
}

if ($CharDelayMs -gt 0) {
    # Slow path, for fields with debounced validation or autocomplete that drops
    # characters delivered in one burst.
    foreach ($ch in [char[]]$Text) {
        [Maestro.Native]::TypeText([string]$ch)
        Start-Sleep -Milliseconds $CharDelayMs
    }
} else {
    [Maestro.Native]::TypeText($Text)
}

if ($Enter) {
    Start-Sleep -Milliseconds 80
    & "$PSScriptRoot\key.ps1" 'enter' -NoFocus -Quiet -Handle $window.HandleValue
}

if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }

if (-not $Quiet) {
    $shown = if ($Text.Length -gt 60) { $Text.Substring(0, 57) + '...' } else { $Text }
    Write-Host ("Typed '{0}' ({1} chars) into '{2}'" -f $shown, $Text.Length, $window.Title)
}
