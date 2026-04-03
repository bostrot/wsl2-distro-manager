<h1 align="center">Bem-vindo ao WSL Manager 👋</h1>

![GitHub Release Date](https://img.shields.io/github/release-date/bostrot/wsl2-distro-manager?style=for-the-badge)
![GitHub Workflow](https://img.shields.io/github/actions/workflow/status/bostrot/wsl2-distro-manager/releaser.yml?branch=main&label=nightly&style=for-the-badge)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/bostrot/wsl2-distro-manager?style=for-the-badge)
[![Documentation](https://img.shields.io/badge/DOCUMENTATION-WIKI-green?style=for-the-badge)](https://github.com/bostrot/wsl2-distro-manager/wiki)
[![GitLab stars](https://img.shields.io/gitlab/stars/bostrot/wsl2-distro-manager?gitlab_url=https%3A%2F%2Fgitlab.com&label=GitLab&style=for-the-badge)](https://gitlab.com/bostrot/wsl2-distro-manager)
[![Discord](https://img.shields.io/discord/1100070299308937287?style=for-the-badge)](https://discord.gg/fY5uE5WRTP)

<p align='center'>
    <a href='../README.md'>English</a> | <a href='./README_zh.md'>简体中文</a> | <a href='./README_zh_tw.md'>繁體中文</a> | <a href='./README_de.md'>Deutsch</a> | <a href='./README_es.md'>Español</a> | <a href='./README_ja.md'>日本語</a> | <a href='./README_hu.md'>Magyar</a> | Português | <a href='./README_tr.md'>Türkçe</a>
</p>

![Screenshot with Darkmode](https://user-images.githubusercontent.com/7342321/233077564-794d15dd-d8d6-48b2-aee6-20e67de3da29.png)

<details>
<summary>Pre-visualizacao em modo claro</summary>

![Screenshot with Lightmode](https://user-images.githubusercontent.com/7342321/233077521-69bd6b3f-1e2a-48a1-a6df-2d346736cfb3.png)

</details>

> O WSL Distro Manager e um aplicativo gratuito e de codigo aberto que oferece uma interface grafica amigavel para gerenciar distribuicoes do Windows Subsystem for Linux (WSL). Com ele, voce pode instalar, desinstalar, atualizar, fazer backup e restaurar distros WSL com facilidade, alem de configurar opcoes e inicia-las com um clique. Ele tambem inclui recursos extras, como compartilhar distros entre varias maquinas e criar acoes para automatizar tarefas repetitivas.

## 🚀 Recursos

- [x] Gerenciar instancias WSL
- [x] Baixar e usar imagens Docker como instancias WSL - sem Docker
- [x] Acoes rapidas (executar scripts predefinidos diretamente nas instancias)
- [x] Baixar e usar containers Turnkey ou outros containers LXC (experimental)
- [x] Usar seu proprio repositorio para rootfs ou containers LXC
- [x] e muito mais...

## 📦 Instalacao

<details>
<summary>Microsoft Store</summary>

Este aplicativo esta disponivel na [Microsoft Store](https://apps.microsoft.com/store/detail/wsl-manager/9NWS9K95NMJB?hl=en-us&gl=US).
</details>

<details>
<summary>Download direto</summary>

Voce pode baixar este aplicativo diretamente na pagina de [Releases](https://github.com/bostrot/wsl2-distro-manager/releases). A versao mais recente esta disponivel como arquivo zip.
</details>

<details>
<summary>Instalar via Winget</summary>

```sh
winget install Bostrot.WSLManager
```

</details>

<details>
<summary>Instalar via Scoop</summary>

```sh
scoop install extras/wsl2-distro-manager
```

</details>

<details>
<summary>Instalar via Chocolatey</summary>

Este pacote e mantido pela comunidade ([@mikeee](https://github.com/mikeee/ChocoPackages)). Nao e um pacote oficial.

```sh
choco install wsl2-distro-manager
```

</details>

<details>
<summary>Instalar uma build nightly</summary>

A ultima build pode ser encontrada nos artefatos do workflow "releaser" ou por [este link](https://nightly.link/bostrot/wsl2-distro-manager/workflows/releaser/main/wsl2-distro-manager-nightly-archive.zip).

</details>

## ⚙️ Build

Garanta que o [flutter](https://flutter.dev/desktop) esteja instalado:

```powershell
flutter config --enable-windows-desktop
flutter upgrade

flutter build windows # compilar
flutter run -d windows # executar
```

## Autor

👤 **Eric Trenkel**

- Website: [erictrenkel.com](https://erictrenkel.com)
- GitHub: [@bostrot](https://github.com/bostrot)
- LinkedIn: [@erictrenkel](https://linkedin.com/in/erictrenkel)

👥 **Contribuidores**

[![Contributors](https://contrib.rocks/image?repo=bostrot/wsl2-distro-manager)](https://github.com/bostrot/wsl2-distro-manager/graphs/contributors)

## 🤝 Contribuicao

Contribuicoes, issues e sugestoes de funcionalidades sao bem-vindas.
Consulte a [pagina de issues](https://github.com/bostrot/wsl2-distro-manager/issues) e o [guia de contribuicao](https://github.com/bostrot/wsl2-distro-manager/blob/main/CONTRIBUTING.md).

## Mostre seu apoio

De uma estrela se este projeto ajudou voce.

## 📝 Licenca

Copyright © 2023 [Eric Trenkel](https://github.com/bostrot).\
Este projeto esta licenciado sob [GPL-3.0](https://github.com/bostrot/wsl2-distro-manager/blob/main/LICENSE).

---

_Nao encontrou o que procurava? Veja a [Wiki](https://github.com/bostrot/wsl2-distro-manager/wiki)._
