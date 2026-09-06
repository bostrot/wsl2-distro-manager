<#
.SYNOPSIS
Kill any running instance, start the app, wait for it to settle, focus it and
print the window handle.

.DESCRIPTION
The sequence matters:

  1. Kill every existing wsl2distromanager.exe and wait for the handles to go
     away. The app rewrites shared_preferences.json on exit, so a stale instance
     lingering in the background will clobber prefs edits made mid-session.
  2. Start the app.
  3. Wait for a window to appear (a `flutter run` build can take minutes, hence
     -BuildTimeoutSeconds), then wait a further -SettleSeconds.

     That second wait is not padding. The app restores its saved window geometry
     shortly after the window is first shown; resizing inside that window races
     the restore and the window silently snaps back. Ten seconds is enough.
  4. Focus, optionally resize, print the handle.

.EXAMPLE
.\launch.ps1
.EXAMPLE
.\launch.ps1 -Mode exe -Width 1400 -Height 900
.EXAMPLE
.\launch.ps1 -ForcePro                 # adds --dart-define=WSLM_FORCE_PRO=true

.PARAMETER Mode
  run     `flutter run -d windows` (debug). Default -- hot reload available and
          the only mode in which the WSLM_FORCE_PRO debug gate can apply.
  profile `flutter run -d windows --profile`
  release `flutter run -d windows --release`
  exe     Launch an already-built binary from build\windows\x64\runner\.

.OUTPUTS
The window info object; the handle is also printed on its own line.
#>
[CmdletBinding()]
param(
    [ValidateSet('run', 'profile', 'release', 'exe')][string]$Mode = 'run',
    [Nullable[int]]$Width = $null,
    [Nullable[int]]$Height = $null,
    [int]$SettleSeconds = 10,
    [int]$BuildTimeoutSeconds = 600,
    [switch]$ForcePro,
    [string]$Exe,
    [string]$LogPath,
    [switch]$KillFlutter,
    [switch]$NoFocus,
    [switch]$Quiet
)

. "$PSScriptRoot\_common.ps1"

function Write-Step { param([string]$m) if (-not $Quiet) { Write-Host "==> $m" } }

# ---- 1. kill any running instance ------------------------------------------
$stale = @(Get-Process -Name $MaestroAppProcessNames -ErrorAction SilentlyContinue)
if ($stale.Count) {
    Write-Step "Stopping $($stale.Count) running instance(s): pid $(($stale | ForEach-Object { $_.Id }) -join ', ')"
    $stale | Stop-Process -Force -ErrorAction SilentlyContinue
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Process -Name $MaestroAppProcessNames -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 300
    }
    if (Get-Process -Name $MaestroAppProcessNames -ErrorAction SilentlyContinue) {
        throw "An instance refused to exit; kill it by hand before relaunching."
    }
    Start-Sleep -Milliseconds 500   # let the prefs file finish being written
}

# `flutter run` holds a lock on build\ and keeps a dart daemon alive. Opt-in
# because the user may have their own unrelated flutter session running.
if ($KillFlutter) {
    $orphans = @(Get-Process -Name 'flutter_tester', 'dart' -ErrorAction SilentlyContinue)
    if ($orphans.Count) {
        Write-Step "Stopping $($orphans.Count) leftover flutter/dart process(es)"
        $orphans | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

# ---- 2. start ---------------------------------------------------------------
if (-not $LogPath) { $LogPath = Join-Path $env:TEMP 'maestro-wslm-launch.log' }
$errPath = [System.IO.Path]::ChangeExtension($LogPath, '.err.log')

if ($Mode -eq 'exe') {
    if (-not $Exe) {
        $candidates = @(
            "$MaestroRepoRoot\build\windows\x64\runner\Release\wsl2distromanager.exe",
            "$MaestroRepoRoot\build\windows\x64\runner\Debug\wsl2distromanager.exe"
        )
        $Exe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $Exe) {
            throw "No built binary found. Looked in:`n  $($candidates -join "`n  ")`nRun ``flutter build windows`` first, or use -Mode run."
        }
    }
    Write-Step "Starting $Exe"
    if ($ForcePro) { Write-Warning "-ForcePro is ignored in -Mode exe: the gate is a compile-time dart-define, so it must be passed to a build. Use -Mode run." }
    $proc = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path -Parent $Exe) -PassThru
} else {
    $flutter = (Get-Command flutter -ErrorAction SilentlyContinue)
    if (-not $flutter) { throw "'flutter' is not on PATH. Add the Flutter SDK bin directory, or use -Mode exe." }

    $flutterArgs = @('run', '-d', 'windows')
    switch ($Mode) {
        'profile' { $flutterArgs += '--profile' }
        'release' { $flutterArgs += '--release' }
    }
    if ($ForcePro) {
        $flutterArgs += '--dart-define=WSLM_FORCE_PRO=true'
        if ($Mode -ne 'run') { Write-Warning "WSLM_FORCE_PRO is gated behind kDebugMode; it has no effect in a $Mode build." }
    }

    Write-Step "flutter $($flutterArgs -join ' ')   (log: $LogPath)"
    Write-Step "Building -- this can take several minutes on a cold build directory."
    $proc = Start-Process -FilePath $flutter.Source -ArgumentList $flutterArgs `
                          -WorkingDirectory $MaestroRepoRoot `
                          -RedirectStandardOutput $LogPath -RedirectStandardError $errPath `
                          -WindowStyle Hidden -PassThru
}

# ---- 3. wait for the window -------------------------------------------------
$deadline = (Get-Date).AddSeconds($BuildTimeoutSeconds)
$window = $null
while ((Get-Date) -lt $deadline) {
    if ($proc.HasExited -and $Mode -ne 'exe') {
        $tail = if (Test-Path $LogPath) { (Get-Content $LogPath -Tail 25) -join "`n" } else { '<no output>' }
        throw "flutter exited with code $($proc.ExitCode) before a window appeared.`n--- last lines of $LogPath ---`n$tail"
    }
    $window = try { Get-AppWindow } catch { $null }
    if ($window) { break }
    Start-Sleep -Milliseconds 500
}
if (-not $window) {
    throw "No app window appeared within ${BuildTimeoutSeconds}s. Check $LogPath."
}

Write-Step "Window appeared (hwnd $($window.HandleValue), pid $($window.ProcessId)); waiting ${SettleSeconds}s for the saved geometry to be restored."
Start-Sleep -Seconds $SettleSeconds

# ---- 4. focus and place -----------------------------------------------------
if (-not $NoFocus) { & "$PSScriptRoot\focus.ps1" -Handle $window.HandleValue -Quiet:$Quiet | Out-Null }

if ($null -ne $Width -or $null -ne $Height) {
    $b = Get-AppBounds -Window $window
    $w = if ($null -ne $Width)  { $Width }  else { $b.Width }
    $h = if ($null -ne $Height) { $Height } else { $b.Height }
    & "$PSScriptRoot\resize.ps1" -Handle $window.HandleValue -Width $w -Height $h -Quiet:$Quiet | Out-Null
}

$window = Get-AppWindow -Handle $window.HandleValue
$bounds = Get-AppBounds -Window $window

if (-not $Quiet) {
    Write-Host ""
    Write-Host "Ready: '$($window.Title)'  pid $($window.ProcessId)  $($bounds.Width)x$($bounds.Height) at ($($bounds.X),$($bounds.Y))"
}
Write-Host $window.HandleValue

$window
