$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$payloadDir = Join-Path $PSScriptRoot 'payload'

$candidateBuildDirs = @(
    (Join-Path $repoRoot 'build\windows\x64\runner\Release'),
    (Join-Path $repoRoot 'build\windows\runner\Release')
)

$buildDir = $candidateBuildDirs | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $buildDir) {
    throw 'No Windows release build directory was found.'
}

New-Item -ItemType Directory -Path $payloadDir -Force | Out-Null
Get-ChildItem -Path $payloadDir -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin @('.gitkeep', '.gitignore') } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item -Path (Join-Path $buildDir '*') -Destination $payloadDir -Recurse -Force

Write-Host "Staged installer payload from $buildDir to $payloadDir"