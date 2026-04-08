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

// Runtime cache for distro links loaded from remote source or local images.json.
Map<String, String> distroRootfsLinks = {};

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
