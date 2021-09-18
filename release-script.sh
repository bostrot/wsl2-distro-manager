#!/bin/bash
wget https://github.com/cli/cli/releases/download/v2.0.0/gh_2.0.0_linux_amd64.deb
dpkg -i gh_2.0.0_linux_amd64.deb
echo $GITHUB_TOKEN > token
gh auth login --with-token < token
version=$(cat pubspec.yaml | grep -o -P '(?<=version: ).*(?= #)')
echo $version
apt-get update && apt-get install -y zip
pwd
echo 'cp ./windows-dlls/* ./build/windows/runner/Release'
echo 'cd ./build/windows/runner/Release'
echo 'zip -r wsl2-distro-manager-v' . $version . '.zip .'
echo 'gh release create v' . $version . './build/windows --notes "This is an automated release."'
echo 'flutter build windows'