import 'package:fluent_ui/fluent_ui.dart' hide Page;
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/beta_badge.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/dialogs/create_dialog.dart';
import 'package:wsl2distromanager/dialogs/info_dialog.dart';
import 'package:wsl2distromanager/dialogs/mount_dialog.dart';
import 'package:wsl2distromanager/nav/linkaction.dart';
import 'package:wsl2distromanager/nav/router.dart';

final List<NavigationPaneItem> originalItems = [
  PaneItem(
    key: const Key('/'),
    icon: const Icon(FluentIcons.home),
    title: Text('homepage-text'.i18n()),
    body: const SizedBox.shrink(),
    onTap: () {
      if (router.state.uri.toString() != '/') {
        router.pushNamed('home');
      }
    },
  ),
  PaneItem(
    key: const Key('/quickactions'),
    icon: const Icon(FluentIcons.file_code),
    title: Text('managequickactions-text'.i18n()),
    body: const SizedBox.shrink(),
    onTap: () {
      if (router.state.uri.toString() != '/quickactions') {
        router.pushNamed('quickactions');
      }
    },
  ),
  PaneItem(
    key: const Key('/templates'),
    icon: const Icon(FluentIcons.file_template),
    title: Text('templates-text'.i18n()),
    body: const SizedBox.shrink(),
    onTap: () {
      if (router.state.uri.toString() != '/templates') {
        router.pushNamed('templates');
      }
    },
  ),
  PaneItem(
    key: const Key('/ai-workspace'),
    icon: const Icon(FluentIcons.robot),
    title: Text('ai-workspace-title'.i18n()),
    // infoBadge, not a Row in title — fluent_ui only extracts the pane
    // label from a literal Text title.
    infoBadge: const BetaBadge(),
    body: const SizedBox.shrink(),
    onTap: () {
      if (router.state.uri.toString() != '/ai-workspace') {
        router.pushNamed('ai-workspace');
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
  PaneItem(
    key: const Key('/mount'),
    icon: const Icon(FluentIcons.hard_drive),
    title: Text('mountdisk-text'.i18n()),
    body: const SizedBox.shrink(),
    onTap: () {
      showMountDialog();
    },
  ),
];
final List<NavigationPaneItem> footerItems = [
  PaneItem(
    key: const Key('/license'),
    icon: const Icon(FluentIcons.crown),
    title: Text('upgrade-pro-text'.i18n()),
    infoBadge: Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFFFBF00).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Text(
        'NEW',
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: Color(0xFFFFBF00),
        ),
      ),
    ),
    body: const SizedBox.shrink(),
    onTap: () {
      if (router.state.uri.toString() != '/license')
        router.pushNamed('license');
    },
  ),
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
      if (router.state.uri.toString() != '/settings')
        router.pushNamed('settings');
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
