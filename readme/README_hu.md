<h1 align="center">Udvozlunk a WSL Managerben 👋</h1>

![GitHub Release Date](https://img.shields.io/github/release-date/bostrot/wsl2-distro-manager?style=for-the-badge)
![GitHub Workflow](https://img.shields.io/github/actions/workflow/status/bostrot/wsl2-distro-manager/releaser.yml?branch=main&label=nightly&style=for-the-badge)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/bostrot/wsl2-distro-manager?style=for-the-badge)
[![Documentation](https://img.shields.io/badge/DOCUMENTATION-WIKI-green?style=for-the-badge)](https://github.com/bostrot/wsl2-distro-manager/wiki)
[![GitLab stars](https://img.shields.io/gitlab/stars/bostrot/wsl2-distro-manager?gitlab_url=https%3A%2F%2Fgitlab.com&label=GitLab&style=for-the-badge)](https://gitlab.com/bostrot/wsl2-distro-manager)
[![Discord](https://img.shields.io/discord/1100070299308937287?style=for-the-badge)](https://discord.gg/fY5uE5WRTP)

<p align='center'>
    <a href='../README.md'>English</a> | <a href='./README_zh.md'>简体中文</a> | <a href='./README_zh_tw.md'>繁體中文</a> | <a href='./README_de.md'>Deutsch</a> | <a href='./README_es.md'>Español</a> | <a href='./README_ja.md'>日本語</a> | Magyar | <a href='./README_pt.md'>Português</a> | <a href='./README_tr.md'>Türkçe</a>
</p>

![Screenshot with Darkmode](https://user-images.githubusercontent.com/7342321/233077564-794d15dd-d8d6-48b2-aee6-20e67de3da29.png)

<details>
<summary>Vilagos mod elonezete</summary>

![Screenshot with Lightmode](https://user-images.githubusercontent.com/7342321/233077521-69bd6b3f-1e2a-48a1-a6df-2d346736cfb3.png)

</details>

> A WSL Distro Manager egy ingyenes es nyilt forraskodu alkalmazas, amely felhasznalobarat grafikus feluletet nyujt a Windows Subsystem for Linux (WSL) disztribuciok kezelesere. A WSL Distro Managerrel konnyeden telepithet, eltavolithat, frissithet, menthet es visszaallithat WSL disztrokat, valamint beallithatja azokat es egy kattintassal el is indithatja. Tovabbi funkciokkal is javitja a WSL elmenyt, peldaul disztrok megosztasaval tobb gep kozott, illetve gyors muveletek letrehozasaval az ismetlodo feladatokhoz.

## 🚀 Funkciok

- [x] WSL peldanyok kezelese
- [x] Docker image-ek letoltese es hasznalata WSL peldanykent - Docker nelkul
- [x] Gyors muveletek (elore definialt scriptek kozvetlen futtatasa a peldanyokon)
- [x] Turnkey vagy mas LXC kontenerek letoltese es hasznalata (kiserleti)
- [x] Sajat tarolo hasznalata rootfs vagy LXC kontenerekhez
- [x] es meg sok mas

## 📦 Telepites

<details>
<summary>Microsoft Store</summary>

Az alkalmazas elerheto a [Microsoft Store-ban](https://apps.microsoft.com/store/detail/wsl-manager/9NWS9K95NMJB?hl=en-us&gl=US).
</details>

<details>
<summary>Kozvetlen letoltes</summary>

Az alkalmazas kozvetlenul letoltheto a [Releases](https://github.com/bostrot/wsl2-distro-manager/releases) oldalrol. A legfrissebb verzio zip fajlkent erheto el.
</details>

<details>
<summary>Telepites Winget segitsegevel</summary>

```sh
winget install Bostrot.WSLManager
```

</details>

<details>
<summary>Telepites Scoop segitsegevel</summary>

```sh
scoop install extras/wsl2-distro-manager
```

</details>

<details>
<summary>Telepites Chocolatey segitsegevel</summary>

Ezt a csomagot a kozosseg tartja karban ([@mikeee](https://github.com/mikeee/ChocoPackages)). Nem hivatalos csomag.

```sh
choco install wsl2-distro-manager
```

</details>

<details>
<summary>Nightly build telepitese</summary>

A legutobbi build a "releaser" workflow artefaktjai kozott talalhato, vagy [ezen a linken](https://nightly.link/bostrot/wsl2-distro-manager/workflows/releaser/main/wsl2-distro-manager-nightly-archive.zip).

</details>

## ⚙️ Build

Gyozodjon meg rola, hogy a [flutter](https://flutter.dev/desktop) telepitve van:

```powershell
flutter config --enable-windows-desktop
flutter upgrade

flutter build windows # build
flutter run -d windows # futtatas
```

## Szerzo

👤 **Eric Trenkel**

- Weboldal: [erictrenkel.com](https://erictrenkel.com)
- GitHub: [@bostrot](https://github.com/bostrot)
- LinkedIn: [@erictrenkel](https://linkedin.com/in/erictrenkel)

👥 **Kozremukodok**

[![Contributors](https://contrib.rocks/image?repo=bostrot/wsl2-distro-manager)](https://github.com/bostrot/wsl2-distro-manager/graphs/contributors)

## 🤝 Hozzajarulas

A hozzajarulasokat, hibajelenteseket es funkciojavaslatokat szivesen fogadjuk.
Nezze meg az [issues oldalt](https://github.com/bostrot/wsl2-distro-manager/issues), illetve a [CONTRIBUTING utmutatot](https://github.com/bostrot/wsl2-distro-manager/blob/main/CONTRIBUTING.md).

## Tamasd a projektet

Adj egy csillagot, ha segitett ez a projekt.

## 📝 Licenc

Copyright © 2023 [Eric Trenkel](https://github.com/bostrot).\
Ez a projekt [GPL-3.0](https://github.com/bostrot/wsl2-distro-manager/blob/main/LICENSE) licenc alatt erheto el.

---

_Nem talaltad, amit kerestel? Nezd meg a [Wikit](https://github.com/bostrot/wsl2-distro-manager/wiki)._
