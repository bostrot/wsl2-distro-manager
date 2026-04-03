<h1 align="center">Bienvenido a WSL Manager 👋</h1>

![Fecha de lanzamiento en GitHub](https://img.shields.io/github/release-date/bostrot/wsl2-distro-manager?style=for-the-badge)
![Flujo de trabajo en GitHub](https://img.shields.io/github/actions/workflow/status/bostrot/wsl2-distro-manager/releaser.yml?branch=main&label=nightly&style=for-the-badge)
![Última versión en GitHub](https://img.shields.io/github/v/release/bostrot/wsl2-distro-manager?style=for-the-badge)
[![Documentación](https://img.shields.io/badge/DOCUMENTACIÓN-WIKI-green?style=for-the-badge)](https://github.com/bostrot/wsl2-distro-manager/wiki)
[![Estrellas en GitLab](https://img.shields.io/gitlab/stars/bostrot/wsl2-distro-manager?gitlab_url=https%3A%2F%2Fgitlab.com&label=GitLab&style=for-the-badge)](https://gitlab.com/bostrot/wsl2-distro-manager)
[![Discord](https://img.shields.io/discord/1100070299308937287?style=for-the-badge)](https://discord.gg/fY5uE5WRTP)


<p align='center'>
    <a href='../README.md'>English</a> | <a href='./README_zh.md'>简体中文</a> | <a href='./README_zh_tw.md'>繁體中文</a> | <a href='./README_de.md'>Deutsch</a> | Español | <a href='./README_ja.md'>日本語</a> | <a href='./README_hu.md'>Magyar</a> | <a href='./README_pt.md'>Português</a> | <a href='./README_tr.md'>Türkçe</a>
</p>

![Captura de pantalla con Modo Oscuro](https://user-images.githubusercontent.com/7342321/233077564-794d15dd-d8d6-48b2-aee6-20e67de3da29.png)

<details>
<summary>Vista previa con Modo Claro</summary>

![Captura de pantalla con Modo Claro](https://user-images.githubusercontent.com/7342321/233077521-69bd6b3f-1e2a-48a1-a6df-2d346736cfb3.png)

</details>

> WSL Distro Manager es una aplicación gratuita y de código abierto que ofrece una interfaz gráfica amigable para la gestión de distribuciones del Subsistema de Windows para Linux (WSL). Con WSL Distro Manager, puedes instalar, desinstalar, actualizar, hacer copias de seguridad y restaurar distribuciones de WSL, así como configurar sus ajustes y lanzarlas con un solo clic. WSL Distro Manager también ofrece algunas características adicionales para mejorar tu experiencia con WSL, como compartir distribuciones entre varias máquinas y crear acciones para realizar tareas repetitivas rápidamente. Ya seas un principiante o un experto en WSL, WSL Distro Manager te ayudará a sacarle el máximo partido.

## 🚀 Características

- [x] Gestionar instancias de WSL
- [x] Descargar y usar imágenes de Docker como instancias de WSL - ¡sin Docker!
- [x] Acciones Rápidas (ejecutar scripts predefinidos directamente en tus instancias para configuraciones rápidas)
- [x] Descargar y usar contenedores Turnkey u otros contenedores LXC (experimental, probado con, p. ej., Turnkey WordPress)
- [x] Usar tu propio repositorio para rootfs' o contenedores LXC
- [x] y más...

## 📦 Instalación

<details>
<summary>Tienda de Microsoft</summary>

Esta aplicación está disponible en la [Tienda de Microsoft](https://apps.microsoft.com/store/detail/wsl-manager/9NWS9K95NMJB?hl=en-us&gl=US).
</details>

<details>
<summary>Descarga directa</summary>

Puedes obtener esta aplicación con una descarga directa desde la página de [Lanzamientos](https://github.com/bostrot/wsl2-distro-manager/releases). La última versión está disponible como un archivo zip.
</details>

<details>
<summary>Instalar vía Winget</summary>

```sh
winget install Bostrot.WSLManager
```

</details>

<details>
<summary>Instalar vía Scoop</summary>

```sh
scoop install extras/wsl2-distro-manager
```

</details>

<details>
<summary>Instalar vía Chocolatey</summary>

Este paquete es mantenido por la comunidad ([@mikeee](https://github.com/mikeee/ChocoPackages)). No es un paquete oficial.

```sh
choco install wsl2-distro-manager
```

</details>

<details>
<summary>Instalar una compilación nocturna</summary>

La última compilación se puede encontrar en los artefactos del flujo de trabajo "releaser" o a través de [este enlace](https://nightly.link/bostrot/wsl2-distro-manager/workflows/releaser/main/wsl2-distro-manager-nightly-archive.zip).

</details>

## ⚙️ Build

Asegúrate de que [flutter](https://flutter.dev/desktop) esté instalado:

```powershell
flutter config --enable-windows-desktop
flutter upgrade

flutter build windows # construirlo
flutter run -d windows # ejecutarlo
```

## Autor

👤 **Eric Trenkel**

- Sitio web: [erictrenkel.com](erictrenkel.com)
- GitHub: [@bostrot](https://github.com/bostrot)
- LinkedIn: [@erictrenkel](https://linkedin.com/in/erictrenkel)

👥 **Colaboradores**

[![Colaboradores](https://contrib.rocks/image?repo=bostrot/wsl2-distro-manager)](https://github.com/bostrot/wsl2-distro-manager/graphs/contributors)

## 🤝 Contribuir

¡Las contribuciones, problemas y solicitudes de características son bienvenidas!\
No dudes en consultar la [página de problemas](https://github.com/bostrot/wsl2-distro-manager/issues).
También puedes echar un vistazo a la [guía de contribución](https://github.com/bostrot/wsl2-distro-manager/blob/main/CONTRIBUTING.md).

## Muestra tu apoyo

¡Dale una ⭐️ si este proyecto te ayudó!

## 📝 Licencia

Derechos de autor © 2023 [Eric Trenkel](https://github.com/bostrot).\
Este proyecto está licenciado bajo [GPL-3.0](https://github.com/bostrot/wsl2-distro-manager/blob/main/LICENSE).

---

_¿No encontraste lo que buscabas? Echa un vistazo a la [Wiki](https://github.com/bostrot/wsl2-distro-manager/wiki)_
