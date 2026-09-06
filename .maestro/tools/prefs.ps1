<#
.SYNOPSIS
Read, patch, back up and restore the app's shared_preferences.json with the app
stopped, so an audit run starts from a known state.

.DESCRIPTION
The app rewrites shared_preferences.json on exit, so any edit made while it is
running is silently lost. This script refuses to touch the file while an
instance is alive; pass -StopApp to close it first.

-Baseline applies the click-through audit baseline: English, light theme, and
every once-per-start dialog (first start, changelog, rating prompt, interrupted
move recovery, motd) pre-dismissed, so screenshots are comparable across runs
and no modal covers the screen under audit.

Window geometry is deliberately NOT part of the baseline -- resize.ps1 owns
that, and the app rewrites the saved size on exit anyway.

.EXAMPLE
.\prefs.ps1 -Baseline -StopApp
.EXAMPLE
.\prefs.ps1 -Set @{ language = 'ja'; themeMode = 'dark' } -StopApp
.EXAMPLE
.\prefs.ps1 -Show language, themeMode
.EXAMPLE
.\prefs.ps1 -Backup "$env:TEMP\prefs.bak.json"; .\prefs.ps1 -Restore "$env:TEMP\prefs.bak.json" -StopApp

.OUTPUTS
The path of the preferences file; with -Show, the requested keys.
#>
[CmdletBinding()]
param(
    [hashtable]$Set,
    [string[]]$Remove,
    [switch]$Baseline,
    [string]$Backup,
    [string]$Restore,
    [string[]]$Show,
    [switch]$StopApp,
    [switch]$Quiet
)

. "$PSScriptRoot\_common.ps1"

$PrefsPath = Join-Path $env:APPDATA 'com.bostrot\WSL Distro Manager\shared_preferences.json'
$KeyPrefix = 'flutter.'

function Write-Step { param([string]$m) if (-not $Quiet) { Write-Host "==> $m" } }

function Resolve-PrefKey {
    param([string]$Key)
    if ($Key.StartsWith($KeyPrefix)) { return $Key }
    return "$KeyPrefix$Key"
}

function Read-Prefs {
    if (-not (Test-Path $PrefsPath)) {
        throw "No preferences file at $PrefsPath. Start the app once so it creates one."
    }
    # ReadAllText(Encoding.UTF8) strips a BOM; Get-Content without -Encoding
    # would decode UTF-8 as ANSI and mangle every non-ASCII value in the file.
    $text = [System.IO.File]::ReadAllText($PrefsPath, [System.Text.Encoding]::UTF8)
    return $text.TrimStart([char]0xFEFF) | ConvertFrom-Json
}

function Write-Prefs {
    param($Data)
    # No BOM: the Dart side decodes the file as plain UTF-8 JSON and a BOM is a
    # parse error, which surfaces as "all settings reset" rather than a crash.
    $json = $Data | ConvertTo-Json -Compress -Depth 20
    [System.IO.File]::WriteAllText($PrefsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Set-PrefValue {
    param($Data, [string]$Key, $Value)
    $full = Resolve-PrefKey $Key
    if ($Data.PSObject.Properties.Name -contains $full) {
        $Data.$full = $Value
    } else {
        $Data | Add-Member -NotePropertyName $full -NotePropertyValue $Value
    }
}

function Get-PubspecVersion {
    $line = Select-String -Path (Join-Path $MaestroRepoRoot 'pubspec.yaml') -Pattern '^version:\s*(\S+)' | Select-Object -First 1
    if (-not $line) { throw "No 'version:' line in pubspec.yaml." }
    # main.dart overwrites currentVersion from package_info at runtime, so the
    # pubspec version -- not constants.dart -- is what init compares against.
    return $line.Matches[0].Groups[1].Value
}

# ---- 1. the app must not be running ----------------------------------------
$running = @(Get-Process -Name $MaestroAppProcessNames -ErrorAction SilentlyContinue)
if ($running.Count) {
    if (-not $StopApp) {
        throw "WSL Manager is running (pid $(($running | ForEach-Object { $_.Id }) -join ', ')). It rewrites the prefs file on exit, so edits made now would be lost. Re-run with -StopApp."
    }
    Write-Step "Stopping $($running.Count) running instance(s) so the prefs write survives"
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Process -Name $MaestroAppProcessNames -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 300
    }
    if (Get-Process -Name $MaestroAppProcessNames -ErrorAction SilentlyContinue) {
        throw "An instance refused to exit; kill it by hand."
    }
    Start-Sleep -Milliseconds 700   # let the exit-time prefs write finish
}

# ---- 2. backup / restore ----------------------------------------------------
if ($Backup) {
    if (-not (Test-Path $PrefsPath)) { throw "Nothing to back up: $PrefsPath does not exist." }
    $backupParent = Split-Path -Parent $Backup
    if ($backupParent -and -not (Test-Path $backupParent)) { New-Item -ItemType Directory -Path $backupParent -Force | Out-Null }
    Copy-Item -LiteralPath $PrefsPath -Destination $Backup -Force
    Write-Step "Backed up preferences to $Backup"
}

if ($Restore) {
    if (-not (Test-Path $Restore)) { throw "No backup at $Restore." }
    Copy-Item -LiteralPath $Restore -Destination $PrefsPath -Force
    Write-Step "Restored preferences from $Restore"
}

# ---- 3. patch ---------------------------------------------------------------
$changed = $false
$data = Read-Prefs

if ($Baseline) {
    $appVersion = Get-PubspecVersion
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $baselineValues = [ordered]@{
        language             = 'en'
        themeMode            = 'light'
        version              = $appVersion   # skips the first-start dialog
        LastChangelogVersion = $appVersion   # skips the changelog dialog
        RatingPromptDone     = $true         # WSLM_FORCE_PRO makes the app look Store-installed, so this fires
        LastMotd             = $today        # skips the once-a-day motd banner
    }
    foreach ($k in $baselineValues.Keys) { Set-PrefValue $data $k $baselineValues[$k] }
    foreach ($k in @('MoveOp_Distro', 'MoveOp_BackupPath')) {
        $full = Resolve-PrefKey $k
        if ($data.PSObject.Properties.Name -contains $full) { $data.PSObject.Properties.Remove($full) }
    }
    $changed = $true
    Write-Step "Applied audit baseline (en / light / v$appVersion, startup dialogs pre-dismissed)"
}

if ($Set) {
    foreach ($k in $Set.Keys) {
        Set-PrefValue $data $k $Set[$k]
        Write-Step "Set $(Resolve-PrefKey $k) = $($Set[$k])"
    }
    $changed = $true
}

if ($Remove) {
    foreach ($k in $Remove) {
        $full = Resolve-PrefKey $k
        if ($data.PSObject.Properties.Name -contains $full) {
            $data.PSObject.Properties.Remove($full)
            Write-Step "Removed $full"
        } else {
            Write-Step "Not present: $full"
        }
    }
    $changed = $true
}

if ($changed) { Write-Prefs $data }

# ---- 4. report --------------------------------------------------------------
if ($Show) {
    $data = Read-Prefs
    foreach ($k in $Show) {
        $full = Resolve-PrefKey $k
        if ($data.PSObject.Properties.Name -contains $full) {
            [pscustomobject]@{ Key = $full; Value = $data.$full }
        } else {
            [pscustomobject]@{ Key = $full; Value = $null }
        }
    }
} else {
    $PrefsPath
}
