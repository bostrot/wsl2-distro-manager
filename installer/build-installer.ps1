$ErrorActionPreference = 'Stop'

$installerDir = $PSScriptRoot
$issPath = Join-Path $installerDir 'setup.iss'
$outputPath = Join-Path $installerDir 'wsl2-distro-manager-setup.exe'
$pubspecPath = Join-Path (Split-Path -Parent $installerDir) 'pubspec.yaml'
$codeDependenciesPath = Join-Path $installerDir 'CodeDependencies.iss'
$codeDependenciesUrl = 'https://raw.githubusercontent.com/DomGries/InnoDependencyInstaller/master/CodeDependencies.iss'

if (-not (Test-Path $issPath)) {
    throw "Inno Setup script not found: $issPath"
}

if (-not (Test-Path $pubspecPath)) {
    throw "pubspec.yaml not found: $pubspecPath"
}

if (-not (Test-Path $codeDependenciesPath)) {
    Write-Host 'Downloading CodeDependencies.iss for InnoDependencyInstaller...'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $codeDependenciesUrl -OutFile $codeDependenciesPath
}

$pubspec = Get-Content $pubspecPath -Raw
$versionMatch = [regex]::Match($pubspec, 'version:\s*([^\s#]+)')
if (-not $versionMatch.Success) {
    throw 'Could not parse version from pubspec.yaml.'
}
$appVersion = $versionMatch.Groups[1].Value

$iscc = (Get-Command iscc -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
if (-not $iscc) {
    $regInstallLocation = $null
    $regPaths = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1'
    )
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $regInstallLocation = (Get-ItemProperty $regPath -ErrorAction SilentlyContinue).InstallLocation
            if ($regInstallLocation) { break }
        }
    }

    $isccCandidates = @(
        ($(if ($regInstallLocation) { Join-Path $regInstallLocation 'ISCC.exe' })),
        ($(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe' })),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
    )
    $iscc = $isccCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

if (-not $iscc) {
    throw 'Inno Setup compiler (ISCC.exe) was not found. Install Inno Setup 6 and retry.'
}

& (Join-Path $installerDir 'stage-payload.ps1')

if (Test-Path $outputPath) {
    Remove-Item $outputPath -Force
}

$isccOutput = & $iscc "/DAppVersion=$appVersion" $issPath 2>&1
$isccExitCode = $LASTEXITCODE
if ($isccExitCode -ne 0) {
    if ($isccOutput) {
        $isccOutput | Out-Host
    }
    throw "Inno Setup compilation failed with exit code $isccExitCode."
}

if (-not (Test-Path $outputPath)) {
    throw "Installer build did not produce: $outputPath"
}

Write-Host "Installer created: $outputPath"