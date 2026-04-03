<h1 align="center">WSL Manager'a Hos Geldiniz 👋</h1>

![GitHub Release Date](https://img.shields.io/github/release-date/bostrot/wsl2-distro-manager?style=for-the-badge)
![GitHub Workflow](https://img.shields.io/github/actions/workflow/status/bostrot/wsl2-distro-manager/releaser.yml?branch=main&label=nightly&style=for-the-badge)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/bostrot/wsl2-distro-manager?style=for-the-badge)
[![Documentation](https://img.shields.io/badge/DOCUMENTATION-WIKI-green?style=for-the-badge)](https://github.com/bostrot/wsl2-distro-manager/wiki)
[![GitLab stars](https://img.shields.io/gitlab/stars/bostrot/wsl2-distro-manager?gitlab_url=https%3A%2F%2Fgitlab.com&label=GitLab&style=for-the-badge)](https://gitlab.com/bostrot/wsl2-distro-manager)
[![Discord](https://img.shields.io/discord/1100070299308937287?style=for-the-badge)](https://discord.gg/fY5uE5WRTP)

<p align='center'>
    <a href='../README.md'>English</a> | <a href='./README_zh.md'>简体中文</a> | <a href='./README_zh_tw.md'>繁體中文</a> | <a href='./README_de.md'>Deutsch</a> | <a href='./README_es.md'>Español</a> | <a href='./README_ja.md'>日本語</a> | <a href='./README_hu.md'>Magyar</a> | <a href='./README_pt.md'>Português</a> | Türkçe
</p>

![Screenshot with Darkmode](https://user-images.githubusercontent.com/7342321/233077564-794d15dd-d8d6-48b2-aee6-20e67de3da29.png)

<details>
<summary>Acik tema onizlemesi</summary>

![Screenshot with Lightmode](https://user-images.githubusercontent.com/7342321/233077521-69bd6b3f-1e2a-48a1-a6df-2d346736cfb3.png)

</details>

> WSL Distro Manager, Windows Subsystem for Linux (WSL) dagitimlarini yonetmek icin kullanici dostu bir grafik arayuz sunan, ucretsiz ve acik kaynakli bir uygulamadir. WSL dagitimlarini kolayca kurabilir, kaldirabilir, guncelleyebilir, yedekleyebilir ve geri yukleyebilir; ayarlari yapilandirip tek tikla baslatabilirsiniz. Ayrica birden fazla makine arasinda distro paylasimi ve tekrar eden isler icin hizli eylemler gibi ek ozellikler sunar.

## 🚀 Ozellikler

- [x] WSL orneklerini yonetme
- [x] Docker image'larini WSL ornegi olarak indirme ve kullanma - Docker olmadan
- [x] Hizli Eylemler (onceden tanimli script'leri dogrudan orneklerde calistirma)
- [x] Turnkey veya diger LXC container'larini indirme ve kullanma (deneysel)
- [x] rootfs veya LXC container'lari icin kendi deponuzu kullanma
- [x] ve daha fazlasi...

## 📦 Kurulum

<details>
<summary>Microsoft Store</summary>

Bu uygulama [Microsoft Store](https://apps.microsoft.com/store/detail/wsl-manager/9NWS9K95NMJB?hl=en-us&gl=US) uzerinde bulunabilir.
</details>

<details>
<summary>Dogrudan indirme</summary>

Uygulamayi [Releases](https://github.com/bostrot/wsl2-distro-manager/releases) sayfasindan dogrudan indirebilirsiniz. En guncel surum zip dosyasi olarak sunulur.
</details>

<details>
<summary>Winget ile kurulum</summary>

```sh
winget install Bostrot.WSLManager
```

</details>

<details>
<summary>Scoop ile kurulum</summary>

```sh
scoop install extras/wsl2-distro-manager
```

</details>

<details>
<summary>Chocolatey ile kurulum</summary>

Bu paket topluluk tarafindan surdurulmektedir ([@mikeee](https://github.com/mikeee/ChocoPackages)). Resmi paket degildir.

```sh
choco install wsl2-distro-manager
```

</details>

<details>
<summary>Nightly build kurulum</summary>

En son build, "releaser" workflow artefaktlari icinde veya [bu baglanti](https://nightly.link/bostrot/wsl2-distro-manager/workflows/releaser/main/wsl2-distro-manager-nightly-archive.zip) uzerinden bulunabilir.

</details>

## ⚙️ Derleme

[flutter](https://flutter.dev/desktop) kurulu oldugundan emin olun:

```powershell
flutter config --enable-windows-desktop
flutter upgrade

flutter build windows # derle
flutter run -d windows # calistir
```

## Yazar

👤 **Eric Trenkel**

- Website: [erictrenkel.com](https://erictrenkel.com)
- GitHub: [@bostrot](https://github.com/bostrot)
- LinkedIn: [@erictrenkel](https://linkedin.com/in/erictrenkel)

👥 **Katkida Bulunanlar**

[![Contributors](https://contrib.rocks/image?repo=bostrot/wsl2-distro-manager)](https://github.com/bostrot/wsl2-distro-manager/graphs/contributors)

## 🤝 Katki

Katkilar, hata bildirimleri ve ozellik talepleri memnuniyetle karsilanir.
[issues sayfasina](https://github.com/bostrot/wsl2-distro-manager/issues) goz atabilir ve [katki kilavuzunu](https://github.com/bostrot/wsl2-distro-manager/blob/main/CONTRIBUTING.md) inceleyebilirsiniz.

## Desteginizi gosterin

Bu proje yardimci olduysa bir yildiz verin.

## 📝 Lisans

Copyright © 2023 [Eric Trenkel](https://github.com/bostrot).\
Bu proje [GPL-3.0](https://github.com/bostrot/wsl2-distro-manager/blob/main/LICENSE) lisansi ile yayinlanmistir.

---

_Aradiginizi bulamadin mi? [Wiki](https://github.com/bostrot/wsl2-distro-manager/wiki) sayfasina bakin._
