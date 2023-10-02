<h1 align="center">Willkommen zum WSL Manager 👋</h1>

![GitHub Release Date](https://img.shields.io/github/release-date/bostrot/wsl2-distro-manager?style=for-the-badge)
![GitHub Workflow](https://img.shields.io/github/actions/workflow/status/bostrot/wsl2-distro-manager/releaser.yml?branch=main&label=nightly&style=for-the-badge)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/bostrot/wsl2-distro-manager?style=for-the-badge)
[![Documentation](https://img.shields.io/badge/DOCUMENTATION-WIKI-green?style=for-the-badge)](https://github.com/bostrot/wsl2-distro-manager/wiki)
[![GitLab stars](https://img.shields.io/gitlab/stars/bostrot/wsl2-distro-manager?gitlab_url=https%3A%2F%2Fgitlab.com&label=GitLab&style=for-the-badge)](https://gitlab.com/bostrot/wsl2-distro-manager)
[![Discord](https://img.shields.io/discord/1100070299308937287?style=for-the-badge)](https://discord.gg/fY5uE5WRTP)

<p align='center'>
    <a href='./README.md'>English</a> | <a href='./README_zh.md'>简体中文</a> | Deutsch
</p>

![Screenshot with Darkmode](https://user-images.githubusercontent.com/7342321/233077564-794d15dd-d8d6-48b2-aee6-20e67de3da29.png)

<details>
<summary>Preview with Lightmode</summary>

![Screenshot with Lightmode](https://user-images.githubusercontent.com/7342321/233077521-69bd6b3f-1e2a-48a1-a6df-2d346736cfb3.png)

</details>

> WSL Distro Manager ist eine kostenlose und quelloffene Anwendung, die eine benutzerfreundliche grafische Oberfläche für die Verwaltung von Windows Subsystem for Linux (WSL) Distributionen bietet. Mit WSL Distro Manager lassen sich WSL-Distributionen einfach installieren, deinstallieren, aktualisieren, sichern und wiederherstellen sowie ihre Einstellungen konfigurieren und mit einem einzigen Klick starten. Der WSL Distro Manager bietet außerdem einige zusätzliche Funktionen, um Ihre WSL-Erfahrung zu verbessern, z. B. die gemeinsame Nutzung von Distros auf mehreren Rechnern und das Erstellen von Aktionen zur schnellen Erledigung sich wiederholender Aufgaben. Egal, ob Sie WSL-Einsteiger oder -Experte sind, der WSL Distro Manager wird Ihnen helfen, das Beste aus der WSL herauszuholen.

## Features 🚀

- [x] Verwalten von WSL-Instanzen
- [x] Herunterladen und Verwenden von Docker-Images als WSL-Instanzen - ohne Docker!
- [x] Quick Actions (Ausführung vordefinierter Skripte direkt auf Ihren Instanzen für schnelle Konfigurationen)
- [x] Herunterladen und Verwenden von Turnkey oder anderen LXC-Containern (experimentell, getestet mit z.B. Turnkey WordPress)
- [x] Verwenden Sie Ihr eigenes Repository für rootfs' oder LXC-Container
- [x] und mehr...

## 📦 Installieren

Diese App ist im [Windows Store](https://apps.microsoft.com/store/detail/wsl-manager/9NWS9K95NMJB?hl=en-us&gl=US) erhältlich.

<Details>
<summary>Direkter Download</summary>

Sie können diese App über einen direkten Download von der Seite [Releases](https://github.com/bostrot/wsl2-distro-manager/releases) beziehen. Die aktuelle Version ist als Zip-Datei verfügbar.
</details>

<Details>
<summary>MSIX Installer</summary>

Das `msix` ist mit einem Testzertifikat signiert, so dass man es speziell zulassen muss. In der PowerShell kann man folgendes tun:

```Powershell
Add-AppPackage -Path .\wsl2-distro-manager-v1.x.x-unsigned.msix -AllowUnsigned
```
</details>

<Details>
<summary>Installation über Winget</summary>

Das winget-Paket ist veraltet! Bitte verwenden Sie stattdessen die Windows Store Version.

```sh
winget install Bostrot.WSLManager
```

</details>

<Details>
<summary>Installation über Chocolatey</summary>

Dieses Paket wird von der Community gepflegt ([@mikeee](https://github.com/mikeee/ChocoPackages)). Es handelt sich nicht um ein offizielles Paket.

```sh
choco install wsl2-distro-manager
```

</details>

<Details>
<summary>Installieren eines nächtlichen Builds</summary>

Den letzten Build findet man als Artefakte im "releaser"-Workflow oder über [diesen Link](https://nightly.link/bostrot/wsl2-distro-manager/workflows/releaser/main/wsl2-distro-manager-nightly-archive.zip). Wer lieber ein unsigniertes `msix` bevorzugt, kann auch [diesen Link](https://nightly.link/bostrot/wsl2-distro-manager/workflows/releaser/main/wsl2-distro-manager-nightly-msix.zip) verwenden.

</details>

## ⚙️ Build

Stellen Sie sicher, dass [flutter](https://flutter.dev/desktop) installiert ist:

```powershell
flutter config --enable-windows-desktop
flutter upgrade

flutter build windows # Bauen Sie es
flutter run -d windows # Ausführen
```

## Autor

👤 **Eric Trenkel**

- Website: [erictrenkel.com](erictrenkel.com)
- Github: [@bostrot](https://github.com/bostrot)
- LinkedIn: [@erictrenkel](https://linkedin.com/in/erictrenkel)

👥 **Beitragende**

[![Contributors](https://contrib.rocks/image?repo=bostrot/wsl2-distro-manager)](https://github.com/bostrot/wsl2-distro-manager/graphs/contributors)

## 🤝 Contributing

Beiträge, Probleme und Funktionswünsche sind willkommen!
Schauen Sie auf der [issues page](https://github.com/bostrot/wsl2-distro-manager/issues) nach. 
Sie können auch einen Blick auf den [Contributing Guide](https://github.com/bostrot/wsl2-distro-manager/blob/main/CONTRIBUTING.md) werfen.

## Zeigen Sie Ihre Unterstützung

Gib eine ⭐️ wenn dieses Projekt dir geholfen hat!

## 📝 Lizenz

Copyright © 2023 [Eric Trenkel](https://github.com/bostrot).\
Dieses Projekt ist [GPL-3.0](https://github.com/bostrot/wsl2-distro-manager/blob/main/LICENSE) lizenziert.

---

Nicht gefunden, was Sie gesucht haben? Schauen Sie im [Wiki](https://github.com/bostrot/wsl2-distro-manager/wiki)_
