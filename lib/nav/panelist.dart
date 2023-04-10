import 'package:fluent_ui/fluent_ui.dart' hide Page;
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/dialogs/create_dialog.dart';
import 'package:wsl2distromanager/dialogs/info_dialog.dart';
import 'package:wsl2distromanager/nav/linkaction.dart';
import 'package:wsl2distromanager/nav/router.dart';

final List<NavigationPaneItem> originalItems = [
  PaneItem(
    key: const Key('/'),
    icon: const Icon(FluentIcons.home),
    title: Text('homepage-text'.i18n()),
    body: const SizedBox.shrink(),
    onTap: () {
      if (router.location != '/') router.pushNamed('home');
    },
  ),
  PaneItem(
    key: const Key('/quickactions'),
    icon: const Icon(FluentIcons.settings_add),
    title: Text('managequickactions-text'.i18n()),
    body: const SizedBox.shrink(),
    onTap: () {
      if (router.location != '/quickactions') {
        router.pushNamed('quickactions');
      }
    },
  ),
  PaneItem(
    key: const Key('/addinstance'),
    icon: const Icon(FluentIcons.add),
    title: Text('addinstance-text'.i18n()),
    body: const SizedBox.shrink(),
    onTap: () {
      createDialog();
    },
  ),
];
final List<NavigationPaneItem> footerItems = [
  LinkPaneItemAction(
    icon: const Icon(FluentIcons.heart),
    title: Text('sponsor-text'.i18n()),
    link: 'https://github.com/sponsors/bostrot',
    body: const SizedBox.shrink(),
  ),
  PaneItemSeparator(),
  PaneItem(
    key: const Key('/settings'),
    icon: const Icon(FluentIcons.settings),
    title: Text('settings-text'.i18n()),
    body: const SizedBox.shrink(),
    onTap: () {
      if (router.location != '/settings') router.pushNamed('settings');
    },
  ),
  LinkPaneItemAction(
    icon: const Icon(FluentIcons.help),
    title: Text('documentation-text'.i18n()),
    link: 'https://github.com/bostrot/wsl2-distro-manager/wiki',
    body: const SizedBox.shrink(),
  ),
  PaneItem(
    key: const Key('/about'),
    icon: const Icon(FluentIcons.info),
    title: Text('about-text'.i18n()),
    body: const SizedBox.shrink(),
    onTap: () {
      infoDialog(prefs, currentVersion);
    },
  ),
];
