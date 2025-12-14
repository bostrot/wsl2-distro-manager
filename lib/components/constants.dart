import 'package:fluent_ui/fluent_ui.dart';

const String title = 'WSL Distro Manager by Bostrot';

const String windowsStoreUrl = "https://www.microsoft.com/store/"
    "productId/9NWS9K95NMJB";
const String defaultPath = 'C:\\WSL2-Distros';
const int chunkSize = 16 * 1024;
const String updateUrl =
    'https://api.github.com/repos/bostrot/wsl2-distro-manager/releases';

const String motdUrl =
    'https://raw.githubusercontent.com/bostrot/wsl2-distro-manager/main/motd.json';

const String defaultRepoLink =
    'http://ftp.halifax.rwth-aachen.de/turnkeylinux/images/proxmox/';

const String gitRepoLink = 'https://n8n.aachen.dev/webhook/cdn/images.json';

String gitApiScriptsLink =
    'https://api.github.com/repos/bostrot/wsl-scripts/contents/scripts';

String repoScripts =
    'https://rawcdn.githack.com/bostrot/wsl-scripts/main/scripts/';

const String githubIssues =
    'https://github.com/bostrot/wsl2-distro-manager/issues/new/choose';

const String errorUrl =
    'https://n8n.aachen.dev/webhook/error-logging-1866548e-233f-4c09-a257-9f3deab055b3';

String explorerPath = '\\\\wsl.localhost';

// Wiki links
const String wikiDocker =
    'https://github.com/bostrot/wsl2-distro-manager/wiki/Features#docker-images';

// https://docs.microsoft.com/en-us/windows/wsl/install-on-server
Map<String, String> distroRootfsLinks = {
  'Ubuntu 24.04':
      'https://cloud-images.ubuntu.com/wsl/releases/24.04/current/ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz',
  'Ubuntu 22.04':
      'https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64-root.tar.xz',
  'Ubuntu 21.04':
      'https://cloud-images.ubuntu.com/releases/hirsute/release/ubuntu-21.04-server-cloudimg-amd64-wsl.rootfs.tar.gz',
  'Fedora 37':
      'https://github.com/bostrot/wsl2-distro-manager/releases/download/v1.4.0/fedora-37-x86_64.tar',
  'Rocky Linux 9':
      'https://raw.githubusercontent.com/rocky-linux/sig-cloud-instance-images/Rocky-9.1.20230215-Base-x86_64/layer.tar.xz',
  'Alpine 3.21.0':
      'https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/alpine-minirootfs-3.21.0-x86_64.tar.gz',
  'Debian 10':
      'https://github.com/bostrot/wsl2-distro-manager/releases/download/v0.6.1/debian_rootfs_x64.tar.gz',
  'Kali Linux':
      'https://github.com/bostrot/wsl2-distro-manager/releases/download/v0.6.1/kalilinux_rootfs_x64.tar.gz',
  'OpenSUSE':
      'https://github.com/bostrot/wsl2-distro-manager/releases/download/v0.6.1/opensuse_rootfs_x64.tar.gz',
  'SLES 12':
      'https://github.com/bostrot/wsl2-distro-manager/releases/download/v0.6.1/sles12_rootfs_x64.tar.gz',
  'SLES 15':
      'https://github.com/bostrot/wsl2-distro-manager/releases/download/v0.6.1/sles15_rootfs_x64.tar.gz',
  'Fedora 36':
      'https://github.com/bostrot/wsl2-distro-manager/releases/download/v1.4.0/fedora-36-x86_64.tar',
  'Ubuntu 20.04':
      'https://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-amd64-root.tar.xz',
  'Ubuntu 19.04':
      'https://cloud-images.ubuntu.com/releases/disco/release/ubuntu-19.04-server-cloudimg-amd64-wsl.rootfs.tar.gz',
  'Ubuntu 18.04':
      'https://cloud-images.ubuntu.com/releases/bionic/release/ubuntu-18.04-server-cloudimg-amd64-wsl.rootfs.tar.gz',
  'Ubuntu 16.04':
      'https://cloud-images.ubuntu.com/releases/xenial/release/ubuntu-16.04-server-cloudimg-amd64-wsl.rootfs.tar.gz',
};

const supportedLocalesList = [
  Locale('en', ''), // English, no country code
  Locale('de', ''), // German, no country code
  Locale('pt', ''), // Portuguese, no country code
  Locale('hu', ''), // Hungarian, no country code
  Locale('zh', ''), // Chinese, simplified
  Locale('zh', 'TW'), // Chinese, taiwan (traditional)
  Locale('zh', 'HK'), // Chinese, hongkong (traditional)
  Locale('es', ''), // Spanish, no country code
  Locale('tr', ''), // Turkish, no country code
  Locale('ja', ''), // Japanese, no country code
];

String currentVersion = "1.0.0";
