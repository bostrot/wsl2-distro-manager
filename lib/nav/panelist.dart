import 'package:fluent_ui/fluent_ui.dart' hide Page;
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/beta_badge.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';
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
      navigateGuarded('home', path: '/');
    },
  ),
  PaneItem(
    key: const Key('/quickactions'),
    icon: const Icon(FluentIcons.file_code),
    title: Text('managequickactions-text'.i18n()),
    body: const SizedBox.shrink(),
    onTap: () {
      navigateGuarded('quickactions', path: '/quickactions');
    },
  ),
  PaneItem(
    key: const Key('/templates'),
    icon: const Icon(FluentIcons.file_template),
    title: Text('templates-text'.i18n()),
    body: const SizedBox.shrink(),
    onTap: () {
      navigateGuarded('templates', path: '/templates');
    },
  ),
  PaneItem(
    key: const Key('/ai-workspace'),
    icon: const Icon(FluentIcons.robot),
    title: Text('ai-workspace-title'.i18n()),
    // infoBadge, not a Row in title — fluent_ui only extracts the pane
    // label from a literal Text title. Below fluent's 1008px threshold the
    // pane is a 48px icon rail and the badge has nowhere to go but *over*
    // the robot glyph, hiding the page's only affordance (audit LN-10,
    // PS-10) — so compact mode gets a corner dot instead of the full pill.
    infoBadge: Builder(
      builder: (context) => MediaQuery.of(context).size.width < 1008
          ? Semantics(
              label: 'beta-badge-label-text'.i18n(),
              excludeSemantics: true,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: BetaBadge.color,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : const BetaBadge(),
    ),
    body: const SizedBox.shrink(),
    onTap: () {
      navigateGuarded('ai-workspace', path: '/ai-workspace');
    },
  ),
  PaneItem(
    key: const Key('/addinstance'),
    icon: const Icon(FluentIcons.add),
    title: Text('addinstance-text'.i18n()),
    body: const SizedBox.shrink(),
    onTap: () {
      navigateGuarded('addinstance', path: '/addinstance');
    },
  ),
  PaneItem(
    key: const Key('/package'),
    icon: const Icon(FluentIcons.package),
    title: Text('custompackage-text'.i18n()),
    body: const SizedBox.shrink(),
    onTap: () {
      navigateGuarded('package', path: '/package');
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

/// Rebuilt on every access: the label and badge depend on the licence state,
/// and a PaneItem title has to be a real Text — fluent_ui reads the string out
/// of it, so a builder widget renders an empty entry.
List<NavigationPaneItem> get footerItems => [
      PaneItem(
        key: const Key('/license'),
        icon: const Icon(FluentIcons.crown),
        title: Text(LicenseManager().isPro
            ? 'license-text'.i18n()
            : 'upgrade-pro-text'.i18n()),
        infoBadge: LicenseManager().isPro
            ? null
            // IA-10: the pill is decoration next to the pane label, so it
            // needs a name of its own to be announced as anything. Accent,
            // not amber: the same amber pill used to mean "immature feature"
            // in five places and "buy this" here, and measured 1.35:1 on the
            // light wash besides (audit PS-09, TL-05).
            : Builder(builder: (context) {
                final dark = FluentTheme.of(context).brightness.isDark;
                return Semantics(
                  label: 'new-badge-label-text'.i18n(),
                  excludeSemantics: true,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.blue.normal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      'NEW',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color:
                            dark ? Colors.blue.lightest : Colors.blue.darkest,
                      ),
                    ),
                  ),
                );
              }),
        body: const SizedBox.shrink(),
        onTap: () {
          navigateGuarded('license', path: '/license');
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
          navigateGuarded('settings', path: '/settings');
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
