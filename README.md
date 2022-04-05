<a title="Made with Fluent Design" href="https://github.com/bdlukaa/fluent_ui">
  <img
    src="https://img.shields.io/badge/fluent-design-blue?style=flat-square&color=7A7574&labelColor=0078D7"
  />
</a>

# WSL Distro Manager

A quick way to manage your WSL instances with a GUI.

![Preview with Darkmode](https://user-images.githubusercontent.com/7342321/161707979-f4c3091f-3f24-475e-87d4-0157caafab2a.png)

[Here](https://user-images.githubusercontent.com/7342321/161708030-4f39a89e-7a2d-4460-b002-da7a619d6302.png) is how it looks in Lightmode if you are into that.

## Install

This app is available on the [Windows Store](https://www.microsoft.com/store/productId/9NWS9K95NMJB).

or 

as a direct download from the [Releases](https://github.com/bostrot/wsl2-distro-manager/releases) page.

or

`winget install Bostrot.WSLManager` (outdated version)

## Build

Enable Flutter Desktop `flutter config --enable-windows-desktop`

https://flutter.dev/desktop

Run with `flutter run -d windows` and build with `flutter build windows`

## Why

WSL is great. It makes it very simple to spin up new workplaces with different systems for the project you need or just testing.

## How to use

Fairly simple. Download the latest release from the releases Page and start wsl2distromanager.exe

## What works

- [x] Starting the program. YAY!
- [x] List WSL
- [x] Copy WSL
- [x] Delete WSL
- [x] Start WSL
- [X] Rename WSL
- [X] Create WSL
- [X] Download WSL
- [X] Select rootfs from storage

## FAQ

* There won't be Linux support. Just WSL. (Get it? Its a joke.)

## Stuff

```
This project is made with [Flutter](https://flutter.dev/docs) for Desktop :)

VS2022: either use Flutter master branch or set `_cmakeVisualStudioGeneratorIdentifier` in `flutter_tools/lib/src/windows/build_windows.dart` to `Visual Studio 17 2022` and rebuild with `flutter pub run test`. (as of https://github.com/flutter/flutter/issues/85922)

Sign package for Windows Store: flutter build windows && flutter pub run msix:create
```
