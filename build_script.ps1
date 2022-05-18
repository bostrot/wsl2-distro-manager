flutter build windows
If((Get-Content .\pubspec.yaml | ForEach-Object{$_ -match "msix_config"}) -contains $true) {
    # already present
} else {
    (Get-Content .\certs\pubspec.yaml | Out-String) | Add-Content .\pubspec.yaml
}
flutter pub run msix:create