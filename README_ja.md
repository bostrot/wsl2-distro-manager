<h1 align="center">WSL Manager へようこそ 👋</h1>

![GitHub Release Date](https://img.shields.io/github/release-date/bostrot/wsl2-distro-manager?style=for-the-badge)
![GitHub Workflow](https://img.shields.io/github/actions/workflow/status/bostrot/wsl2-distro-manager/releaser.yml?branch=main&label=nightly&style=for-the-badge)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/bostrot/wsl2-distro-manager?style=for-the-badge)
[![Documentation](https://img.shields.io/badge/DOCUMENTATION-WIKI-green?style=for-the-badge)](https://github.com/bostrot/wsl2-distro-manager/wiki)
[![GitLab stars](https://img.shields.io/gitlab/stars/bostrot/wsl2-distro-manager?gitlab_url=https%3A%2F%2Fgitlab.com&label=GitLab&style=for-the-badge)](https://gitlab.com/bostrot/wsl2-distro-manager)
[![Discord](https://img.shields.io/discord/1100070299308937287?style=for-the-badge)](https://discord.gg/fY5uE5WRTP)


<p align='center'>
    <a href='./README.md'>English</a> | <a href='./README_zh.md'>简体中文</a> | <a href='./README_de.md'>Deutsch</a> | <a href='./README_es.md'>Español</a> | 日本語
</p>

![Screenshot with Darkmode](https://user-images.githubusercontent.com/7342321/233077564-794d15dd-d8d6-48b2-aee6-20e67de3da29.png)

<details>
<summary>ライトモードでのプレビュー</summary>

![Screenshot with Lightmode](https://user-images.githubusercontent.com/7342321/233077521-69bd6b3f-1e2a-48a1-a6df-2d346736cfb3.png)

</details>

> WSL Distro Manager は、Windows Subsystem for Linux (WSL) ディストリビューションを管理するための使いやすいグラフィカルインターフェースを提供する無料のオープンソースアプリです。WSL Distro Manager を使えば、WSL ディストロのインストール、アンインストール、更新、バックアップ、復元が簡単に行えるほか、設定を構成したり、ワンクリックで起動したりすることができます。WSL Distro Manager は、複数のマシン間でディストロを共有したり、繰り返し行うタスクを素早く実行するためのアクションを作成したりするなど、WSL体験を向上させるための追加機能も提供しています。WSLの初心者でもエキスパートでも、WSL Distro Manager は WSL を最大限に活用するお手伝いをします。

## 🚀 機能

- [x] WSL インスタンスの管理
- [x] Docker イメージを WSL インスタンスとしてダウンロードして使用 - Docker なしで！
- [x] クイックアクション（インスタンス上で事前定義されたスクリプトを直接実行し、素早く設定を行う）
- [x] Turnkey やその他の LXC コンテナのダウンロードと使用（実験的、例：Turnkey WordPressでテスト済み）
- [x] rootfs や LXC コンテナ用の独自のリポジトリを使用
- [x] その他多数...

## 📦 インストール

<details>
<summary>Microsoft Store</summary>

このアプリは [Microsoft Store](https://apps.microsoft.com/store/detail/wsl-manager/9NWS9K95NMJB?hl=en-us&gl=US) で入手できます。
</details>

<details>
<summary>直接ダウンロード</summary>

[リリース](https://github.com/bostrot/wsl2-distro-manager/releases) ページから直接ダウンロードできます。最新バージョンは zip ファイルとして利用可能です。
</details>

<details>
<summary>Winget 経由でインストール</summary>

winget パッケージは古くなっています！代わりに Windows Store バージョンを使用してください。

```sh
winget install Bostrot.WSLManager
```

</details>

<details>
<summary>Chocolatey 経由でインストール</summary>

このパッケージはコミュニティ（[@mikeee](https://github.com/mikeee/ChocoPackages)）によってメンテナンスされています。公式パッケージではありません。

```sh
choco install wsl2-distro-manager
```

</details>

<details>
<summary>ナイトリービルドをインストール</summary>

最新のビルドは "releaser" ワークフローのアーティファクトとして、または[このリンク](https://nightly.link/bostrot/wsl2-distro-manager/workflows/releaser/main/wsl2-distro-manager-nightly-archive.zip)から見つけることができます。署名されていない `msix` を希望する場合は、[このリンク](https://nightly.link/bostrot/wsl2-distro-manager/workflows/releaser/main/wsl2-distro-manager-nightly-msix.zip)も使用できます。

</details>

## ⚙️ ビルド

[flutter](https://flutter.dev/desktop) がインストールされていることを確認してください：

```powershell
flutter config --enable-windows-desktop
flutter upgrade

flutter build windows # ビルド
flutter run -d windows # 実行
```

## 著者

👤 **Eric Trenkel**

- ウェブサイト: [erictrenkel.com](erictrenkel.com)
- GitHub: [@bostrot](https://github.com/bostrot)
- LinkedIn: [@erictrenkel](https://linkedin.com/in/erictrenkel)

👥 **コントリビューター**

[![Contributors](https://contrib.rocks/image?repo=bostrot/wsl2-distro-manager)](https://github.com/bostrot/wsl2-distro-manager/graphs/contributors)

## 🤝 コントリビューション

コントリビューション、イシュー、機能リクエストは歓迎します！\
[issues ページ](https://github.com/bostrot/wsl2-distro-manager/issues)をご確認ください。
[contributing guide](https://github.com/bostrot/wsl2-distro-manager/blob/main/CONTRIBUTING.md) もご覧ください。

## サポートを示す

このプロジェクトが役に立った場合は ⭐️ をお願いします！

## 📝 ライセンス

Copyright © 2023 [Eric Trenkel](https://github.com/bostrot).\
このプロジェクトは [GPL-3.0](https://github.com/bostrot/wsl2-distro-manager/blob/main/LICENSE) ライセンスです。

---

_お探しの情報が見つかりませんでしたか？[Wiki](https://github.com/bostrot/wsl2-distro-manager/wiki) をご確認ください_