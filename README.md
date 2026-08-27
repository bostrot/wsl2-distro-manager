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

![WSL Distro Manager, dark theme](./readme/images/home-dark.png)

<details>
<summary>Preview with light theme</summary>

![WSL Distro Manager, light theme](./readme/images/home-light.png)

</details>

> **WSL Distro Manager** is a free, open source GUI for the Windows Subsystem
> for Linux. Install, copy, rename, move, back up and delete WSL distros
> without memorising a single `wsl.exe` flag — plus templates, saved command
> snippets, disk mounting, `.wslconfig` editing, remote WSL over SSH, and an
> MCP server that lets AI agents drive your WSL environment.

## 🚀 Features

**Manage distros**
- [x] Install from a built-in catalogue, or bring your own rootfs
- [x] Copy, rename, move to another drive, back up and delete instances
- [x] Compact virtual disks to reclaim space WSL never gives back
- [x] Supports Ubuntu, Debian, Alpine, Kali Linux, openSUSE, SLES and anything else WSL accepts

**Get instances running faster**
- [x] Use any Docker image as a distro — Docker itself is not required
- [x] Save a configured distro as a template and spin up fresh copies from it
- [x] Turnkey Linux and other LXC containers (experimental)
- [x] Snippets: keep your setup commands in the app and run them on any instance
- [x] Point the app at your own repository of rootfs images

**Configure without editing files by hand**
- [x] systemd, automount, default user, start command and start path per distro
- [x] Memory, processors, swap, networking mode, DNS and the rest of `.wslconfig`
- [x] Mount a physical disk or a VHD into WSL, with partition and filesystem control

**Work the way you already do**
- [x] Open Windows Terminal, VS Code or Explorer straight inside a distro
- [x] Manage WSL on a *different* Windows machine over SSH
- [x] Sync a distro between two machines on your network
- [x] Dark and light themes, available in nine languages

**Pro** *(optional one-time purchase on the Microsoft Store — not a subscription)*
- [x] **AI Workspace** — run Hermes Agent, OpenClaw and Open WebUI in a dedicated, isolated WSL distro
- [x] **MCP server** — expose WSL to Claude Desktop and other MCP clients; agents can list distros, run commands and drive real terminal sessions
- [x] **AI assistant** — configuration help, script generation and error diagnosis

> The AI assistant features run on **your own** OpenAI-compatible API key. No AI
> service is hosted or included, there is no quota, and no requests pass through
> anyone else's servers. Pro unlocks the features in the app; it does not buy AI
> credits. See [Free vs Pro](https://github.com/bostrot/wsl2-distro-manager/wiki/Pro-Version).

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

Copyright © 2026 [Eric Trenkel](https://github.com/bostrot).\
This project is [GPL-3.0](https://github.com/bostrot/wsl2-distro-manager/blob/main/LICENSE) licensed.

---

_Not found what you were looking for? Check out the [Wiki](https://github.com/bostrot/wsl2-distro-manager/wiki)_
