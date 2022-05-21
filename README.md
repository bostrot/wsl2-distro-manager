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

Enable Flutter Desktop `flutter config --enable-windows-desktop` (https://flutter.dev/desktop)

As there are problems with bitsdojo_window with the new flutter versions it is easier for now to use an old release candidate:

  flutter channel flutter-2.8-candidate.20
  flutter upgrade

Run with `flutter run -d windows` and build with `flutter build windows`

## Why

WSL is great. It makes it very simple to spin up new workplaces with different systems for the project you need or just testing.

## How to use

Fairly simple. Download the latest release from the releases Page and start wsl2distromanager.exe

## Features

* Starting the program. YAY!
* Quick Actions (execute pre-defined scripts directly on your instances for quick configurations)
* Download and use Turnkey or other LXC containers (experimental, tested with e.g. Turnkey Wordpress)
* Use your own repository for rootfs' or LXC containers
* List WSL
* Copy WSL
* Delete WSL
* Start WSL
* Rename WSL
* Create WSL
* Download WSL
* Select rootfs from storage
* and more but I am tired of writing already ... Feel free to open a PR.

## What works

- [x] Starting the program. YAY!
- [X] Quick Actions
- [x] List WSL
- [x] Copy WSL
- [x] Delete WSL
- [x] Start WSL
- [X] Rename WSL
- [X] Create WSL
- [X] Download WSL
- [X] Select rootfs from storage
- [X] Use turnkey/LXC images as base

## FAQ

### How do I access my Turnkey instance? (e.g. Wordpress)

Turnkey instances can be inited with `turnkey-init` in console. This will let you choose new passwords for your services.

### What does it mean that it installs "fake_systemd" with Turnkey?

As systemd is not officially supported in WSL (yet) [fake_systemd](https://github.com/bostrot/fake-systemd) is a custom fork from @kvaps specifically for WSL so that Turnkey services will actually startup when opening the instance.

## Help

You need more help but the FAQ did not help? 

Contact me on Telegram [@bostrot_bot](https://t.me/bostrot_bot).

Or just open an issue here.

## Stuff

### Create signed msix package

(Only for maintainers with build certificate)

To create a signed msix package set the .githooks directory as your git hooks directory:

  git config --local core.hooksPath .githooks/

Then it will update version numbers, build sign and commit everything with the push. This will take the configuration from the file `certs/pubspec.yaml` and replace the version (`xxx` in the pubspec.yaml) with the current version from the running pubspec file.

You can also sign it manually by adding the msix config to the end of the pubspec.yaml file and then run `flutter pub run msix:create`



```
This project is made with [Flutter](https://flutter.dev/docs) for Desktop :)

Sign package for Windows Store: flutter build windows && flutter pub run msix:create
```
