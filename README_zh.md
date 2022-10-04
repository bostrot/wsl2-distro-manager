
![Jenkins](https://img.shields.io/jenkins/build?jobUrl=https%3A%2F%2Fjenkins.aachen.dev%2Fjob%2Fwsl2-distro-manager&style=for-the-badge)
![GitHub Release Date](https://img.shields.io/github/release-date/bostrot/wsl2-distro-manager?style=for-the-badge)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/bostrot/wsl2-distro-manager?style=for-the-badge)
![GitHub closed issues](https://img.shields.io/github/issues-closed-raw/bostrot/wsl2-distro-manager?style=for-the-badge)
![GitHub](https://img.shields.io/github/license/bostrot/wsl2-distro-manager?style=for-the-badge)


# [WSL 发行版管理器](https://github.com/bostrot/wsl2-distro-manager)
使用 GUI 管理 WSL 实例的快速方法。

基于 Windows 设计指南，使用 Flutter 和 [fluent_ui](https://github.com/bdlukaa/fluent_ui) 制作。

![Preview with Darkmode](https://user-images.githubusercontent.com/7342321/161707979-f4c3091f-3f24-475e-87d4-0157caafab2a.png)

[Here](https://user-images.githubusercontent.com/7342321/161708030-4f39a89e-7a2d-4460-b002-da7a619d6302.png) is how it looks in Lightmode if you are into that.

## 安装

此应用程序已发布在 [Windows 应用商店](https://apps.microsoft.com/store/detail/wsl-manager/9NWS9K95NMJB?hl=en-us&gl=US).

\- or -

直接下载 [Releases](https://github.com/bostrot/wsl2-distro-manager/releases) page.

\- or -

`winget install Bostrot.WSLManager` (可能是过时的版本)

## 构建

启用 Flutter 桌面 `flutter config --enable-windows-desktop` (https://flutter.dev/desktop)

  flutter upgrade

运行 `flutter run -d windows` and build with `flutter build windows`

## 特征

* 列出 WSL
* 复制 WSL
* 删除 WSL
* 启动 WSL
* 重命名 WSL
* 创建 WSL
* 下载 WSL
* 从存储中选择 rootfs
* 快速操作（直接在您的实例上执行预定义脚本以进行快速配置）
* 下载并使用 Turnkey 或其他 LXC 容器（实验性，使用 Turnkey Wordpress 等进行测试）
* 为 rootfs 或 LXC 容器使用您自己的存储库
* 和更多...

## FAQ

### 如何访问我的交钥匙实例？ （例如 WordPress）

Turnkey 实例可以在控制台中使用 `turnkey-init` 启动。这将让您为您的服务选择新密码。
### 用 Turnkey 安装“fake_systemd”是什么意思？

由于 WSL 中尚未正式支持 systemd [fake_systemd](https://github.com/bostrot/fake-systemd) 是来自 @kvaps 的自定义分支，专门用于 WSL，因此 Turnkey 服务将在打开实例时实际启动.
## 贡献

非常欢迎您为这个项目做出贡献，以使其变得更好。

### 缺少发行版

如果您发现任何您认为应该添加的缺失发行版，请打开 [Distro request](https://github.com/bostrot/wsl2-distro-manager/issues/new?assignees=&labels=distro+request&template=distro-request.md&title=Add+a+new+distribution)。

### Docs

当前生成的 API 文档可用。你可以找到文档 [here](https://bostrot.github.io/wsl2-distro-manager/api/index.html).

### 代码贡献

如果您做出了代码贡献，请随时打开 PR 和/或 issuess。

### 语言贡献

本地化作为 json 文件保存在 `/lib/i18n/` 中。新语言可以直接添加到适当的 json 文件（例如`en.json`）中，也可以通过提供 GUI 的本地化 [windows/mac 应用程序](https://github.com/Flutterando/localization/releases) 添加。

由于 fluent_ui 包的一些限制，目前在文件名中不使用国家代码更容易，所以用 `en.json` 代替 `en_US.json`。

随意发布 PR :)

## 帮助

您需要更多帮助，但常见问题解答没有帮助？

通过 Telegram [@bostrot_bot](https://t.me/bostrot_bot) 与我联系。

或者只是打开一个 issue [here](https://github.com/bostrot/wsl2-distro-manager/issues)。

## Stuff

### 创建签名的 msix 包

（仅适用于拥有构建证书的维护者）

要创建签名的 msix 包，请将 .githooks 目录设置为您的 git hooks 目录：

  git config --local core.hooksPath .githooks/

然后它将更新版本号，构建签名并通过推送提交所有内容。这将从文件 `certs/pubspec.yaml` 中获取配置，并将版本（pubspec.yaml 中的`xxx`）替换为正在运行的 pubspec 文件中的当前版本。

您也可以通过将 msix 配置添加到 pubspec.yaml 文件的末尾来手动对其进行签名，然后运行“flutter pub run msix:create”
### 为什么是图形用户界面

WSL 很棒。它使得为您需要的项目或只是测试的项目启动具有不同系统的新工作场所变得非常简单。

### 其他

这个项目是用 [Flutter](https://flutter.dev/docs) for Desktop 制作的 :)
