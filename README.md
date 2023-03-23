<h1 align="center">Welcome to WSL Distro Manager 👋</h1>

![GitHub Workflow](https://img.shields.io/github/actions/workflow/status/bostrot/wsl2-distro-manager/releaser.yml?branch=main&label=nightly&style=for-the-badge)
![GitHub Release Date](https://img.shields.io/github/release-date/bostrot/wsl2-distro-manager?style=for-the-badge)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/bostrot/wsl2-distro-manager?style=for-the-badge)
[![Documentation](https://img.shields.io/badge/DOCUMENTATION-WIKI-green?style=for-the-badge)](https://github.com/bostrot/wsl2-distro-manager/wiki)
![GitHub](https://img.shields.io/github/license/bostrot/wsl2-distro-manager?style=for-the-badge)

<p align='center'>
    English | <a href='./README_zh.md'>简体中文</a>
</p>

![Preview with Darkmode](https://user-images.githubusercontent.com/7342321/161707979-f4c3091f-3f24-475e-87d4-0157caafab2a.png)

<details>
<summary>Preview with Lightmode</summary>

![Here](https://user-images.githubusercontent.com/7342321/161708030-4f39a89e-7a2d-4460-b002-da7a619d6302.png)

</details>

> WSL Distro Manager is a free and open source app that provides a user-friendly graphical interface for managing Windows Subsystem for Linux (WSL) distributions. With WSL Distro Manager, you can easily install, uninstall, update, backup and restore WSL distros, as well as configure their settings and launch them with a single click. WSL Distro Manager also offers some extra features to enhance your WSL experience, such as sharing Distros between multiple machines, and creating actions to quickly do repetitive tasks. Whether you are a beginner or an expert in WSL, WSL Distro Manager will help you get the most out of it.

## 🚀 Features

- [x] List WSL
- [x] Copy WSL
- [x] Delete WSL
- [x] Start WSL
- [x] Rename WSL
- [x] Create WSL
- [x] Download WSL
- [x] Select rootfs from storage
- [x] Quick Actions (execute pre-defined scripts directly on your instances for quick configurations)
- [x] Download and use Turnkey or other LXC containers (experimental, tested with e.g. Turnkey Wordpress)
- [x] Use your own repository for rootfs' or LXC containers
- [x] and more...

## 📦 Install

This app is available on the [Windows Store](https://apps.microsoft.com/store/detail/wsl-manager/9NWS9K95NMJB?hl=en-us&gl=US).

<details>
<summary>Direct download</summary>

You can get this app with a direct download from the [Releases](https://github.com/bostrot/wsl2-distro-manager/releases) page. The latest version is available as a zip file.
</details>

<details>
<summary>MSIX installer</summary>

The `msix` is signed with a test certificate so you need to allow it specifically. In PowerShell you can do following:

```powershell
Add-AppPackage -Path .\wsl2-distro-manager-v1.x.x-unsigned.msix -AllowUnsigned
```
</details>

<details>
<summary>Install via Winget</summary>

The winget package is outdated! Please use the Windows Store version instead.

```sh
winget install Bostrot.WSLManager
```

</details>

<details>
<summary>Install via Chocolatey</summary>

This package is maintained by the community ([@mikeee](https://github.com/mikeee/ChocoPackages)). It is not an official package.

```sh
choco install wsl2-distro-manager
```

</details>

<details>
<summary>Install a nightly build</summary>

The last build can be found as artificats in the "releaser" workflow or via [this link](https://nightly.link/bostrot/wsl2-distro-manager/workflows/releaser/main/wsl2-distro-manager-nightly-archive.zip). If you rather prefer an unsigned `msix` you can also use [this link](https://nightly.link/bostrot/wsl2-distro-manager/workflows/releaser/main/wsl2-distro-manager-nightly-msix.zip).

</details>

## ⚙️ Build

Make sure [flutter](https://flutter.dev/desktop) is installed:

```powershell
flutter config --enable-windows-desktop
flutter upgrade

flutter build windows # build it
flutter run -d windows # run it
```

## Author

👤 **Eric Trenkel**

- Website: [erictrenkel.com](erictrenkel.com)
- Github: [@bostrot](https://github.com/bostrot)
- LinkedIn: [@erictrenkel](https://linkedin.com/in/erictrenkel)

👥 **Contributors**

[![Contributors](https://contrib.rocks/image?repo=bostrot/wsl2-distro-manager)](https://github.com/bostrot/wsl2-distro-manager/graphs/contributors)

## 🤝 Contributing

Contributions, issues and feature requests are welcome!<br />Feel free to check [issues page](https://github.com/bostrot/wsl2-distro-manager/issues). You can also take a look at the [contributing guide](https://github.com/bostrot/wsl2-distro-manager/blob/main/CONTRIBUTING.md).

## Show your support

Give a ⭐️ if this project helped you!

## 📝 License

Copyright © 2023 [Eric Trenkel](https://github.com/bostrot).<br />
This project is [GPL-3.0](https://github.com/bostrot/wsl2-distro-manager/blob/main/LICENSE) licensed.

---

_Not found what you were looking for? Check out the [Wiki](https://github.com/bostrot/wsl2-distro-manager/wiki)_
