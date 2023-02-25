flutter build windows

# get version
$pubspec_file = Get-Content '.\pubspec.yaml'
$version = [regex]::Matches($pubspec_file, 'version: ([^/)]+) # Current version')[0].Groups[1].Value

If((Get-Content .\pubspec.yaml | ForEach-Object{$_ -match "msix_config"}) -contains $true) {
    # already present
} else {
    # msix config with current version
    (Get-Content .\certs\pubspec.yaml | Out-String).Replace("xxx", $version) | Add-Content .\pubspec.yaml
}
flutter pub run msix:create