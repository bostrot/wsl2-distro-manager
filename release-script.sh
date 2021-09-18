#!/bin/bash
version=$(cat pubspec.yaml | grep -o -P '(?<=version: ).*(?= #)')
cp ./windows-dlls/* ./build/windows/runner/Release
cd ./build/windows/runner/Release
zip -r wsl2-distro-manager-v$version.zip .
gh release create v$version wsl2-distro-manager-v$version.zip --notes "This is an automated release."
