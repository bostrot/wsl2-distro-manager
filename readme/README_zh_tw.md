<h1 align="center">歡迎使用 WSL Manager 👋</h1>

![GitHub 發行日期](https://img.shields.io/github/release-date/bostrot/wsl2-distro-manager?style=for-the-badge&label=發行日期)
![GitHub Workflow](https://img.shields.io/github/actions/workflow/status/bostrot/wsl2-distro-manager/releaser.yml?branch=main&label=夜間建置&style=for-the-badge)
![GitHub 發行版（最新）](https://img.shields.io/github/v/release/bostrot/wsl2-distro-manager?style=for-the-badge&label=發行版)
[![文件](https://img.shields.io/badge/文件-WIKI-green?style=for-the-badge)](https://github.com/bostrot/wsl2-distro-manager/wiki)
[![GitLab 星標](https://img.shields.io/gitlab/stars/bostrot/wsl2-distro-manager?gitlab_url=https%3A%2F%2Fgitlab.com&label=GitLab&style=for-the-badge)](https://gitlab.com/bostrot/wsl2-distro-manager)
[![Discord](https://img.shields.io/discord/1100070299308937287?style=for-the-badge)](https://discord.gg/fY5uE5WRTP)

<p align='center'>
    <a href='../README.md'>English</a> | <a href='./README_zh.md'>简体中文</a> | 繁體中文 | <a href='./README_de.md'>Deutsch</a> | <a href='./README_es.md'>Español</a> | <a href='./README_ja.md'>日本語</a> | <a href='./README_hu.md'>Magyar</a> | <a href='./README_pt.md'>Português</a> | <a href='./README_tr.md'>Türkçe</a>
</p>

![深色模式截圖](https://user-images.githubusercontent.com/7342321/233077564-794d15dd-d8d6-48b2-aee6-20e67de3da29.png)

<details>
<summary>淺色模式預覽</summary>

![淺色模式截圖](https://user-images.githubusercontent.com/7342321/233077521-69bd6b3f-1e2a-48a1-a6df-2d346736cfb3.png)

</details>

> WSL Distro Manager 是一款免費且開源的應用程式，提供友善的圖形化介面來管理 Windows Subsystem for Linux（WSL）發行版。透過 WSL Distro Manager，您可以輕鬆安裝、解除安裝、更新、備份與還原 WSL 發行版，並可設定選項並一鍵啟動。它也提供額外功能來提升使用體驗，例如在多台機器間共享發行版，以及建立快速動作來執行重複性工作。

## 🚀 功能

- [x] 管理 WSL 實例
- [x] 下載並使用 Docker 映像作為 WSL 實例 - 無需 Docker
- [x] 快速動作（直接在實例中執行預先定義的腳本）
- [x] 下載並使用 Turnkey 或其他 LXC 容器（實驗性）
- [x] 使用自訂儲存庫提供 rootfs 或 LXC 容器
- [x] 以及更多...

## 📦 安裝

<details>
<summary>Microsoft Store</summary>

此應用程式可於 [Microsoft Store](https://apps.microsoft.com/store/detail/wsl-manager/9NWS9K95NMJB?hl=zh-tw&gl=TW) 取得。
</details>

<details>
<summary>直接下載</summary>

您可以在 [Releases](https://github.com/bostrot/wsl2-distro-manager/releases) 頁面直接下載。最新版本以 zip 檔提供。
</details>

<details>
<summary>透過 Winget 安裝</summary>

```sh
winget install Bostrot.WSLManager
```

</details>

<details>
<summary>透過 Chocolatey 安裝</summary>

此套件由社群維護（[@mikeee](https://github.com/mikeee/ChocoPackages)），非官方套件。

```sh
choco install wsl2-distro-manager
```

</details>

<details>
<summary>安裝 Nightly 建置版本</summary>

最新 Nightly 建置可在 "releaser" 工作流程的 artifacts 中找到，或透過[此連結](https://nightly.link/bostrot/wsl2-distro-manager/workflows/releaser/main/wsl2-distro-manager-nightly-archive.zip)下載。

</details>

## ⚙️ 建置

請先確認已安裝 [flutter](https://flutter.dev/desktop)：

```powershell
flutter config --enable-windows-desktop
flutter upgrade

flutter build windows # 建置
flutter run -d windows # 執行
```

## 作者

👤 **Eric Trenkel**

- 網站: [erictrenkel.com](https://erictrenkel.com)
- GitHub: [@bostrot](https://github.com/bostrot)
- LinkedIn: [@erictrenkel](https://linkedin.com/in/erictrenkel)

👥 **貢獻者**

[![Contributors](https://contrib.rocks/image?repo=bostrot/wsl2-distro-manager)](https://github.com/bostrot/wsl2-distro-manager/graphs/contributors)

## 🤝 貢獻

歡迎提交貢獻、問題回報與功能建議。
請查看 [issues 頁面](https://github.com/bostrot/wsl2-distro-manager/issues)，也可參考[貢獻指南](https://github.com/bostrot/wsl2-distro-manager/blob/main/CONTRIBUTING.md)。

## 支持這個專案

如果此專案對您有幫助，請給一顆星。

## 📝 授權

Copyright © 2023 [Eric Trenkel](https://github.com/bostrot).\
本專案採用 [GPL-3.0](https://github.com/bostrot/wsl2-distro-manager/blob/main/LICENSE) 授權。

---

_還沒找到你要的內容？請查看 [Wiki](https://github.com/bostrot/wsl2-distro-manager/wiki)。_
