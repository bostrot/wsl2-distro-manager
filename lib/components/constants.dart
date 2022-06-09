const String currentVersion = "1.3.1";
const String windowsStoreUrl = "https://www.microsoft.com/store/"
    "productId/9NWS9K95NMJB";
const String defaultPath = 'C:\\WSL2-Distros\\';
const int chunkSize = 512 * 1024;
const String updateUrl =
    'https://api.github.com/repos/bostrot/wsl2-distro-manager/releases';

const String motdUrl =
    'https://raw.githubusercontent.com/bostrot/wsl2-distro-manager/main/motd.json';

const String defaultRepoLink =
    'http://ftp.halifax.rwth-aachen.de/turnkeylinux/images/proxmox/';

const String gitRepoLink =
    'https://raw.githubusercontent.com/bostrot/wsl2-distro-manager/adjusted_repos/images.json';

// https://docs.microsoft.com/en-us/windows/wsl/install-on-server
Map<String, String> distroRootfsLinks = {
  'Ubuntu 21.04':
      'https://cloud-images.ubuntu.com/releases/hirsute/release/ubuntu-21.04-server-cloudimg-amd64-wsl.rootfs.tar.gz',
  'Ubuntu 20.04':
      'https://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-amd64-wsl.rootfs.tar.gz',
  'Ubuntu 19.04':
      'https://cloud-images.ubuntu.com/releases/disco/release/ubuntu-19.04-server-cloudimg-amd64-wsl.rootfs.tar.gz',
  'Ubuntu 18.04':
      'https://cloud-images.ubuntu.com/releases/bionic/release/ubuntu-18.04-server-cloudimg-amd64-wsl.rootfs.tar.gz',
  'Ubuntu 16.04':
      'https://cloud-images.ubuntu.com/releases/xenial/release/ubuntu-16.04-server-cloudimg-amd64-wsl.rootfs.tar.gz',
  'Alpine':
      'https://dl-cdn.alpinelinux.org/alpine/v3.15/releases/x86_64/alpine-minirootfs-3.15.0-x86_64.tar.gz',
  'Debian':
      'https://github.com/bostrot/wsl2-distro-manager/releases/download/v0.6.1/debian_rootfs_x64.tar.gz',
  'Kali Linux':
      'https://github.com/bostrot/wsl2-distro-manager/releases/download/v0.6.1/kalilinux_rootfs_x64.tar.gz',
  'OpenSUSE':
      'https://github.com/bostrot/wsl2-distro-manager/releases/download/v0.6.1/opensuse_rootfs_x64.tar.gz',
  'SLES 12':
      'https://github.com/bostrot/wsl2-distro-manager/releases/download/v0.6.1/sles12_rootfs_x64.tar.gz',
  'SLES 15':
      'https://github.com/bostrot/wsl2-distro-manager/releases/download/v0.6.1/sles15_rootfs_x64.tar.gz',
};
