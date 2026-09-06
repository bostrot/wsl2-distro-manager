import 'package:fluent_ui/fluent_ui.dart';

const String title = 'WSL Distro Manager by Bostrot';

/// Where macOS users buy Pro. No Microsoft Store on the Mac, so the licence
/// is sold on the website and comes back as a key.
const String macBuyUrl = "https://wslmanager.com/buy";

/// Where Windows users buy Pro without going through the Microsoft Store.
/// Same shop and the same kind of key as the Mac licence; the `platform`
/// hint lets the page show the Windows price, and is ignored if it cannot.
const String windowsBuyUrl = "https://wslmanager.com/buy?platform=windows";

/// Turns a licence key into an entitlement. Answers
/// `{"valid": true, "plan": "pro", ...}` or `{"valid": false, ...}`.
const String licenseValidateUrl =
    'https://n8n.aachen.dev/webhook/wsl-manager/validate';
const String windowsStoreUrl = "https://www.microsoft.com/store/"
    "productId/9NWS9K95NMJB";

/// Opens the Store app straight on the review pane for this product.
const String storeReviewUrl =
    "ms-windows-store://review?ProductId=9NWS9K95NMJB";
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

String gitApiCommitsLink =
    'https://api.github.com/repos/bostrot/wsl-scripts/commits';

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

/// Locales the app ships translations for.
///
/// Every entry must have a lib/i18n/<locale>.json whose name matches the
/// locale's toString(): the localization delegate throws on a missing file and
/// the failed load leaves the app rendering nothing at all. Anything else is
/// mapped onto one of these by localeResolutionCallback in main.dart.
const supportedLocalesList = [
  Locale('en', ''), // en.json
  Locale('de', ''), // de.json
  Locale('es', ''), // es.json
  Locale('hu', ''), // hu.json
  Locale('ja', ''), // ja.json
  Locale('ko', ''), // ko.json
  Locale('pt', ''), // pt.json
  Locale('tr', ''), // tr.json
  Locale('zh', 'CN'), // zh_CN.json, simplified
  Locale('zh', 'TW'), // zh_TW.json, traditional
];

/// Language picker entries: the value stored in the `language` preference
/// mapped to the language's own name.
///
/// Keys are locale tags that name a file in lib/i18n, so a picked language
/// always has a translation to load.
const languageOptions = {
  'en': 'English',
  'de': 'Deutsch',
  'es': 'Español',
  'hu': 'Magyar',
  'ja': '日本語',
  'ko': '한국어',
  'pt': 'Português',
  'tr': 'Türkçe',
  'zh_CN': '简体中文',
  'zh_TW': '繁體中文',
};

String currentVersion = "1.0.0";
