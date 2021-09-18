$pattern = "version: (.*?) \#"
$string = Get-Content pubspec.yaml
$wsl2_manager_version = [regex]::match($string, $pattern).Groups[1].Value
Copy-Item ./windows-dlls/* ./build/windows/runner/Release
Compress-Archive -Path ./build/windows/runner/Release/* -DestinationPath .\wsl2-distro-manager-v$wsl2_manager_version.zip
Write-Output 'gh release create v$wsl2_manager_version ./build/windows/runner/Release/wsl2-distro-manager-v$wsl2_manager_version.zip --notes "This is an automated release."'
