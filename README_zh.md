<h1 align="center">欢迎加入WSL Manager 👋</h1>

![License](https://img.shields.io/github/license/bostrot/wsl2-distro-manager?style=for-the-badge)
![GitHub Release Date](https://img.shields.io/github/release-date/bostrot/wsl2-distro-manager?style=for-the-badge)
![GitHub Workflow](https://img.shields.io/github/actions/workflow/status/bostrot/wsl2-distro-manager/releaser.yml?branch=main&label=nightly&style=for-the-badge)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/bostrot/wsl2-distro-manager?style=for-the-badge)
[![Documentation](https://img.shields.io/badge/DOCUMENTATION-WIKI-green?style=for-the-badge)](https://github.com/bostrot/wsl2-distro-manager/wiki)
[![GitLab stars](https://img.shields.io/gitlab/stars/bostrot/wsl2-distro-manager?gitlab_url=https%3A%2F%2Fgitlab.com&label=GitLab&style=for-the-badge)](https://gitlab.com/bostrot/wsl2-distro-manager)

<p align='center'>
    <a href='./README.md'>English</a> | 简体中文 | <a href='./README_de.md'>Deutsch</a>
</p>

![Screenshot with Darkmode](https://user-images.githubusercontent.com/7342321/233077564-794d15dd-d8d6-48b2-aee6-20e67de3da29.png)

<details>
<summary>Preview with Lightmode</summary>

![Screenshot with Lightmode](https://user-images.githubusercontent.com/7342321/233077521-69bd6b3f-1e2a-48a1-a6df-2d346736cfb3.png)

</details>

> WSL Distro Manager是一个免费的开源应用程序，它提供了一个用户友好的图形界面来管理Windows Subsystem for Linux（WSL）发行版。通过WSL发行版管理器，你可以轻松地安装、卸载、更新、备份和恢复WSL发行版，以及配置它们的设置，并通过一次点击启动它们。WSL发行版管理器还提供了一些额外的功能来增强你的WSL体验，例如在多台机器之间共享发行版，以及创建动作来快速完成重复性任务。无论你是WSL的初学者还是专家，WSL发行版管理器都能帮助你获得最大的收益。

## 🚀功能

- [x] 管理WSL的实例
- [x] 下载并使用Docker镜像作为WSL实例 - 无需Docker!
- [x] 快速行动（直接在你的实例上执行预定义的脚本以进行快速配置）
- [x] 下载并使用Turnkey或其他LXC容器（试验性的，用Turnkey WordPress等测试）。
- [x] 使用您自己的rootfs'或LXC容器的存储库
- [x] 还有更多...

## 📦安装

此应用程序可在[Windows Store](https://apps.microsoft.com/store/detail/wsl-manager/9NWS9K95NMJB?hl=en-us&gl=US)上使用。

<details><br />
<summary>直接下载</summary

你可以从[Release](https://github.com/bostrot/wsl2-distro-manager/releases)页面直接下载此应用。最新版本是以压缩文件的形式提供的。
</details>

<details><br />
<summary>MSIX安装器</summary>

`msix`是用一个测试证书签名的，所以你需要特别允许它。在PowerShell中，你可以做以下工作：

```powershell
Add-AppPackage -Path .\wsl2-distro-manager-v1.x.x-unsigned.msix -AllowUnsigned
```
</details>

<details>
<summary>通过 Winget 安装</summary>。

winget软件包已经过期! 请使用Windows商店版本代替。

```sh
winget install Bostrot.WSLManager
```

</details>

<details
<summary>通过Chocolatey安装</summary>。

这个软件包是由社区（[@mikeee](https://github.com/mikeee/ChocoPackages)）维护的。它不是一个官方软件包。

```sh
choco install wsl2-distro-manager
```

</details>

<details>
<summary>安装一个夜间构建</summary>。

最后的构建可以在 "releaser "工作流中找到工件，或者通过[这个链接](https://nightly.link/bostrot/wsl2-distro-manager/workflows/releaser/main/wsl2-distro-manager-nightly-archive.zip)。如果你更喜欢无符号的`msix`，你也可以使用[此链接](https://nightly.link/bostrot/wsl2-distro-manager/workflows/releaser/main/wsl2-distro-manager-nightly-msix.zip)。

</details>

## ⚙️ 构建

确保[flutter](https://flutter.dev/desktop)已经安装：

```powershell
flutter config --enable-windows-desktop
flutter升级

flutter build windows # build it
flutter run -d windows # run it
```

## 作者

👤 **Eric Trenkel**

- 网站： [erictrenkel.com](erictrenkel.com)
- Github： [@bostrot](https://github.com/bostrot)
- LinkedIn： [@erictrenkel](https://linkedin.com/in/erictrenkel)

👥 **贡献者**

[![Contributors](https://contrib.rocks/image?repo=bostrot/wsl2-distro-manager)](https://github.com/bostrot/wsl2-distro-manager/graphs/contributors)

## 🤝 贡献者

欢迎贡献、问题和功能请求！（欢迎）。
请随时查看[问题页面](https://github.com/bostrot/wsl2-distro-manager/issues)。
你也可以看一下[贡献指南](https://github.com/bostrot/wsl2-distro-manager/blob/main/CONTRIBUTING.md)。

## 显示你的支持

如果这个项目帮助了你，请给⭐️!

## 📝 许可证

Copyright © 2023 [Eric Trenkel] (https://github.com/bostrot).\
本项目是[GPL-3.0](https://github.com/bostrot/wsl2-distro-manager/blob/main/LICENSE)许可的。

---

_没有找到你要找的东西？请查看[Wiki](https://github.com/bostrot/wsl2-distro-manager/wiki)_
