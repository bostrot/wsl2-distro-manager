<h1 align="center">欢迎使用 WSL Manager 👋</h1>

![GitHub 发行日期](https://img.shields.io/github/release-date/bostrot/wsl2-distro-manager?style=for-the-badge&label=发行日期)
![GitHub Workflow](https://img.shields.io/github/actions/workflow/status/bostrot/wsl2-distro-manager/releaser.yml?branch=main&label=夜间构建&style=for-the-badge)
![GitHub 发行版（最新日期）](https://img.shields.io/github/v/release/bostrot/wsl2-distro-manager?style=for-the-badge&label=发行版)
[![文档](https://img.shields.io/badge/文档-WIKI-green?style=for-the-badge)](https://github.com/bostrot/wsl2-distro-manager/wiki)
[![GitLab 星标](https://img.shields.io/gitlab/stars/bostrot/wsl2-distro-manager?gitlab_url=https%3A%2F%2Fgitlab.com&label=GitLab&style=for-the-badge)](https://gitlab.com/bostrot/wsl2-distro-manager)
[![Discord](https://img.shields.io/discord/1100070299308937287?style=for-the-badge)](https://discord.gg/fY5uE5WRTP)


<p align='center'>
    <a href='./README.md'>English</a> | 简体中文 | <a href='./README_de.md'>Deutsch</a> | <a href='./README_es.md'>Español</a>| <a href='./README_ja.md'>日本語</a>
</p>

![暗色模式截图](https://user-images.githubusercontent.com/7342321/233077564-794d15dd-d8d6-48b2-aee6-20e67de3da29.png)

<details>
<summary>预览亮色模式</summary>

![亮色模式截图](https://user-images.githubusercontent.com/7342321/233077521-69bd6b3f-1e2a-48a1-a6df-2d346736cfb3.png)

</details>

> WSL Distro Manager 是一个免费且开源的应用程序，它提供了一个用户友好的图形界面来管理 Windows Subsystem for Linux（WSL）发行版。通过 WSL Distro Manager，您可以轻松地安装、卸载、更新、备份和恢复 WSL 发行版，以及配置它们的设置，并通过一次点击启动它们。WSL Distro Manager 还提供了一些额外的功能来增强您的 WSL 体验，例如在多台机器之间共享发行版，以及创建操作来快速完成重复性任务。无论您是 WSL 的初学者还是专家，WSL Distro Manager 都能帮助您充分发挥其优势。

## 🚀 功能

- [x] 管理 WSL 的实例
- [x] 下载并使用 Docker 镜像作为 WSL 实例 - 无需 Docker!
- [x] 快速操作（直接在您的实例上执行预定义的脚本以进行快速配置）
- [x] 下载并使用 Turnkey 或其他 LXC 容器（试验性的，已使用 Turnkey WordPress 等测试）
- [x] 使用您自己的 rootfs 或 LXC 容器的存储库
- [x] 还有更多...

## 📦 安装

<details>
<summary>Microsoft Store</summary>

此应用程序可在 [Microsoft Store](https://apps.microsoft.com/store/detail/wsl-manager/9NWS9K95NMJB?hl=zh-cn&gl=CN) 上获取。
</details>

<details>
<summary>直接下载</summary>

您可以从[Release](https://github.com/bostrot/wsl2-distro-manager/releases)页面直接下载此应用。最新版本是以压缩文件的形式提供的。
</details>

<details>
<summary>通过 Winget 安装</summary>

winget 软件包已经过时! 请改用 Windows 商店版本。

```sh
winget install Bostrot.WSLManager
```

</details>

<details>
<summary>通过 Chocolatey 安装</summary>

这个软件包是由社区（[@mikeee](https://github.com/mikeee/ChocoPackages)）维护的。这不是一个官方软件包。

```sh
choco install wsl2-distro-manager
```

</details>
<details>
<summary>安装夜间构建</summary>

最后的构建可以在“releaser”工作流中找到工件，或者通过[此链接](https://nightly.link/bostrot/wsl2-distro-manager/workflows/releaser/main/wsl2-distro-manager-nightly-archive.zip)获取。如果您更倾向于使用未签名的 `msix`，也可以使用[此链接](https://nightly.link/bostrot/wsl2-distro-manager/workflows/releaser/main/wsl2-distro-manager-nightly-msix.zip)。

</details>

## ⚙️ 构建

请确保已安装 [flutter](https://flutter.dev/desktop)：

```powershell
flutter config --enable-windows-desktop
flutter upgrade

flutter build windows # 构建应用
flutter run -d windows # 运行应用
```

## 作者

👤 **Eric Trenkel**

- 网站：[erictrenkel.com](https://erictrenkel.com)
- GitHub：[@bostrot](https://github.com/bostrot)
- LinkedIn：[@erictrenkel](https://linkedin.com/in/erictrenkel)

👥 **贡献者**

[![贡献者](https://contrib.rocks/image?repo=bostrot/wsl2-distro-manager)](https://github.com/bostrot/wsl2-distro-manager/graphs/contributors)

## 🤝 贡献

欢迎贡献、提出问题或功能请求！\
请随时查看 [issues 页面](https://github.com/bostrot/wsl2-distro-manager/issues)。
您也可以看一下[贡献指南](https://github.com/bostrot/wsl2-distro-manager/blob/main/CONTRIBUTING.md)。

## 显示您的支持

如果这个项目对您有帮助，请给一个 ⭐️！

## 📝 许可证

Copyright © 2023 [Eric Trenkel](https://github.com/bostrot).\
本项目是 [GPL-3.0](https://github.com/bostrot/wsl2-distro-manager/blob/main/LICENSE) 许可的。

---

_没有找到您要找的内容？请查看 [Wiki](https://github.com/bostrot/wsl2-distro-manager/wiki)_
