<h1 align="center">Welcome to WSL Manager 👋</h1>

![GitHub Release Date](https://img.shields.io/github/release-date/bostrot/wsl2-distro-manager?style=for-the-badge)
![GitHub Workflow](https://img.shields.io/github/actions/workflow/status/bostrot/wsl2-distro-manager/releaser.yml?branch=main&label=nightly&style=for-the-badge)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/bostrot/wsl2-distro-manager?style=for-the-badge)
[![Documentation](https://img.shields.io/badge/DOCUMENTATION-WIKI-green?style=for-the-badge)](https://github.com/bostrot/wsl2-distro-manager/wiki)
[![GitLab stars](https://img.shields.io/gitlab/stars/bostrot/wsl2-distro-manager?gitlab_url=https%3A%2F%2Fgitlab.com&label=GitLab&style=for-the-badge)](https://gitlab.com/bostrot/wsl2-distro-manager)
[![Discord](https://img.shields.io/discord/1100070299308937287?style=for-the-badge)](https://discord.gg/fY5uE5WRTP)


<p align='center'>
    English | <a href='./readme/README_zh.md'>简体中文</a> | <a href='./readme/README_zh_tw.md'>繁體中文</a> | <a href='./readme/README_de.md'>Deutsch</a> | <a href='./readme/README_es.md'>Español</a> | <a href='./readme/README_ja.md'>日本語</a> | <a href='./readme/README_hu.md'>Magyar</a> | <a href='./readme/README_pt.md'>Português</a> | <a href='./readme/README_tr.md'>Türkçe</a>
</p>

![Screenshot with Darkmode](https://user-images.githubusercontent.com/7342321/233077564-794d15dd-d8d6-48b2-aee6-20e67de3da29.png)

<details>
<summary>Preview with Lightmode</summary>

![Screenshot with Lightmode](https://user-images.githubusercontent.com/7342321/233077521-69bd6b3f-1e2a-48a1-a6df-2d346736cfb3.png)

</details>

> WSL Distro Manager is a free and open source app that provides a user-friendly graphical interface for managing Windows Subsystem for Linux (WSL) distributions. With WSL Distro Manager, you can easily install, uninstall, update, backup and restore WSL distros, as well as configure their settings and launch them with a single click. WSL Distro Manager also offers some extra features to enhance your WSL experience, such as sharing Distros between multiple machines, and creating actions to quickly do repetitive tasks. Whether you are a beginner or an expert in WSL, WSL Distro Manager will help you get the most out of it.

## 🚀 Features

- [x] Manage WSL instances
- [x] Download and use Docker images as WSL instances - without Docker!
- [x] Quick Actions (execute pre-defined scripts directly on your instances for quick configurations)
- [x] Download and use Turnkey or other LXC containers (experimental, tested with e.g. Turnkey WordPress)
- [x] Use your own repository for rootfs' or LXC containers
- [x] and more...

## 📦 Install

<details>
<summary>Microsoft Store</summary>

This app is available on the [Microsoft Store](https://apps.microsoft.com/store/detail/wsl-manager/9NWS9K95NMJB?hl=en-us&gl=US).
</details>

<details>
<summary>Direct download</summary>

You can get this app with a direct download from the [Releases](https://github.com/bostrot/wsl2-distro-manager/releases) page. The latest version is available as a zip file.
</details>

<details>
<summary>Install via Winget</summary>

```sh
winget install Bostrot.WSLManager
```

</details>

<details>
<summary>Install via Scoop</summary>

```sh
scoop install extras/wsl2-distro-manager
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

The latest nightly build is available as an artifact in the "releaser" workflow or via [this link](https://nightly.link/bostrot/wsl2-distro-manager/workflows/releaser/main/wsl2-distro-manager-nightly-archive.zip).

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

- Website: [erictrenkel.com](https://erictrenkel.com)
- GitHub: [@bostrot](https://github.com/bostrot)
- LinkedIn: [@erictrenkel](https://linkedin.com/in/erictrenkel)

👥 **Contributors**

[![Contributors](https://contrib.rocks/image?repo=bostrot/wsl2-distro-manager)](https://github.com/bostrot/wsl2-distro-manager/graphs/contributors)

## 🤝 Contributing

Contributions, issues and feature requests are welcome!\
Feel free to check the [issues page](https://github.com/bostrot/wsl2-distro-manager/issues).
You can also take a look at the [contributing guide](https://github.com/bostrot/wsl2-distro-manager/blob/main/CONTRIBUTING.md).

## Show your support

Give a ⭐️ if this project helped you!

## 📝 License

Copyright © 2023 [Eric Trenkel](https://github.com/bostrot).\
This project is [GPL-3.0](https://github.com/bostrot/wsl2-distro-manager/blob/main/LICENSE) licensed.

---

_Not found what you were looking for? Check out the [Wiki](https://github.com/bostrot/wsl2-distro-manager/wiki)_
