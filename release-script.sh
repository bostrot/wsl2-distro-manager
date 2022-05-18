#!/bin/bash
# get version from pubspec
VERSION_NUM=$(cat pubspec.yaml | grep -o -P '(?<=version: ).*(?= #)')

# copy files
cp ./windows-dlls/* ./build/windows/runner/Release
cd ./build/windows/runner/Release
mv wsl2distromanager.msix ../wsl2distromanager-v$VERSION_NUM-signed-installer.msix
zip -r wsl2-distro-manager-v$VERSION_NUM.zip .

# check tag already exists
if [ "$(echo $(gh release view --json tagName) | sed -e 's/{"tagName":"\(.*\)"}/\1/')" != "v$VERSION_NUM" ]; 
then 
gh release create v$VERSION_NUM wsl2-distro-manager-v$version.zip wsl2distromanager_signed_installer.msix --notes "This is an automated release." 
fi
