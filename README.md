
![Jenkins](https://img.shields.io/jenkins/build?jobUrl=https%3A%2F%2Fjenkins.aachen.dev%2Fjob%2Fwsl2-distro-manager&style=for-the-badge)
![GitHub Release Date](https://img.shields.io/github/release-date/bostrot/wsl2-distro-manager?style=for-the-badge)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/bostrot/wsl2-distro-manager?style=for-the-badge)
![GitHub closed issues](https://img.shields.io/github/issues-closed-raw/bostrot/wsl2-distro-manager?style=for-the-badge)
![GitHub](https://img.shields.io/github/license/bostrot/wsl2-distro-manager?style=for-the-badge)

<p align='center'>
    English | <a href='./README_zh.md'>简体中文</a>
</p>

# [WSL Distro Manager](https://github.com/bostrot/wsl2-distro-manager)
A quick way to manage your WSL instances with a GUI.

Made with Flutter and [fluent_ui](https://github.com/bdlukaa/fluent_ui) based on Windows design guidelines.

![Preview with Darkmode](https://user-images.githubusercontent.com/7342321/161707979-f4c3091f-3f24-475e-87d4-0157caafab2a.png)

[Here](https://user-images.githubusercontent.com/7342321/161708030-4f39a89e-7a2d-4460-b002-da7a619d6302.png) is how it looks in Lightmode if you are into that.

## Install

This app is available on the [Windows Store](https://apps.microsoft.com/store/detail/wsl-manager/9NWS9K95NMJB?hl=en-us&gl=US).

\- or -

as a direct download from the [Releases](https://github.com/bostrot/wsl2-distro-manager/releases) page.

\- or -

`winget install Bostrot.WSLManager` (outdated version)

\- or -

`choco install wsl2-distro-manager` (maintained by [@mikeee](https://github.com/mikeee/ChocoPackages))

## Build

Enable Flutter Desktop `flutter config --enable-windows-desktop` (https://flutter.dev/desktop)

  flutter upgrade

Run with `flutter run -d windows` and build with `flutter build windows`

## Features

* List WSL
* Copy WSL
* Delete WSL
* Start WSL
* Rename WSL
* Create WSL
* Download WSL
* Select rootfs from storage
* Quick Actions (execute pre-defined scripts directly on your instances for quick configurations)
* Download and use Turnkey or other LXC containers (experimental, tested with e.g. Turnkey Wordpress)
* Use your own repository for rootfs' or LXC containers
* and more...

## FAQ

### How do I access my Turnkey instance? (e.g. Wordpress)

Turnkey instances can be inited with `turnkey-init` in console. This will let you choose new passwords for your services.

### What does it mean that it installs "fake_systemd" with Turnkey?

As systemd is not officially supported in WSL (yet) [fake_systemd](https://github.com/bostrot/fake-systemd) is a custom fork from @kvaps specifically for WSL so that Turnkey services will actually startup when opening the instance.

## Contribute

You are very welcome to contribute to this project in order to make it better.

### Missing distributions

If you find any missing distribution that you think should be added please open a [Distro request](https://github.com/bostrot/wsl2-distro-manager/issues/new?assignees=&labels=distro+request&template=distro-request.md&title=Add+a+new+distribution).

### Docs

Currently generated API docs are available. You can find the documentation [here](https://bostrot.github.io/wsl2-distro-manager/api/index.html).

### Code contributions

If you have made a code contribution feel free to open a PR and/or an issue.

### Language contributions

Localizations are saved in `/lib/i18n/` as json files. New languages can be added either directly in the appropriate json file (e.g. `en.json`) or via the localizations [windows/mac application](https://github.com/Flutterando/localization/releases) which provides a GUI.

As of some restrictions with fluent_ui package currently it is easier not to use the country code in the file name so instead of `en_US.json` just `en.json`.

Feel free to publish a PR :)

## Help

You need more help but the FAQ did not help? 

Contact me on Telegram [@bostrot_bot](https://t.me/bostrot_bot).

Or just open an issue [here](https://github.com/bostrot/wsl2-distro-manager/issues).

## Stuff

### Create signed msix package

(Only for maintainers with build certificate)

To create a signed msix package set the .githooks directory as your git hooks directory:

  git config --local core.hooksPath .githooks/

Then it will update version numbers, build sign and commit everything with the push. This will take the configuration from the file `certs/pubspec.yaml` and replace the version (`xxx` in the pubspec.yaml) with the current version from the running pubspec file.

You can also sign it manually by adding the msix config to the end of the pubspec.yaml file and then run `flutter pub run msix:create`

### Why a GUI

WSL is great. It makes it very simple to spin up new workplaces with different systems for the project you need or just testing.

### Other

This project is made with [Flutter](https://flutter.dev/docs) for Desktop :)
