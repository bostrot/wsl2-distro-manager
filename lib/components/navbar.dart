import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:localization/localization.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/dialogs/create_dialog.dart';
import 'package:wsl2distromanager/dialogs/info_dialog.dart';
import 'package:wsl2distromanager/screens/actions_screen.dart';
import 'package:wsl2distromanager/screens/settings_screen.dart';
import 'package:wsl2distromanager/theme.dart';
import 'constants.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as flutter_acrylic;

class Navbar extends StatefulWidget {
  const Navbar({
    Key? key,
    required this.title,
    required this.child,
  }) : super(key: key);
  final String title;
  final Widget child;

  @override
  State<Navbar> createState() => _NavbarState();
}

bool hasPushed = false;

class _NavbarState extends State<Navbar> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppTheme(),
      builder: (context, _) {
        final appTheme = context.watch<AppTheme>();
        return Directionality(
          textDirection: appTheme.textDirection,
          child: NavigationPaneTheme(
              data: NavigationPaneThemeData(
                backgroundColor: appTheme.windowEffect !=
                        flutter_acrylic.WindowEffect.disabled
                    ? Colors.transparent
                    : null,
              ),
              child: NavigationView(
                pane: NavigationPane(items: [
                  PaneItemAction(
                    icon: const Icon(FluentIcons.info),
                    title: Text('about-text'.i18n()),
                    onTap: () {
                      infoDialog(
                          context, prefs, Notify.message, currentVersion);
                    },
                  ),
                  PaneItemAction(
                    icon: const Icon(FluentIcons.settings),
                    title: Text('settings-text'.i18n()),
                    onTap: () {
                      if (hasPushed) {
                        Navigator.pop(context);
                      }
                      Navigator.push(
                          context,
                          FluentPageRoute(
                              maintainState: true,
                              builder: (context) => const SettingsPage()));
                      hasPushed = true;
                    },
                  ),
                  PaneItemAction(
                    icon: const Icon(FluentIcons.settings_add),
                    title: Text('managequickactions-text'.i18n()),
                    onTap: () {
                      if (hasPushed) {
                        Navigator.pop(context);
                      }
                      Navigator.push(
                          context,
                          FluentPageRoute(
                              maintainState: true,
                              builder: (context) => const QuickPage()));
                      hasPushed = true;
                    },
                  ),
                  PaneItemAction(
                    icon: const Icon(FluentIcons.add),
                    title: Text('addinstance-text'.i18n()),
                    onTap: () {
                      createDialog(context, () => mounted, Notify.message);
                    },
                  ),
                ]),
                appBar: NavigationAppBar(
                  automaticallyImplyLeading: false,
                  title: () {
                    return DragToMoveArea(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text(widget.title),
                        ),
                      ),
                    );
                  }(),
                  actions:
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    ToggleSwitch(
                      content: const Text('Dark Mode'),
                      checked: FluentTheme.of(context).brightness.isDark,
                      onChanged: (v) {
                        if (v) {
                          setState(() {
                            appTheme.mode = ThemeMode.dark;
                          });
                        } else {
                          setState(() {
                            appTheme.mode = ThemeMode.light;
                          });
                        }
                      },
                    ),
                    const WindowButtons(),
                  ]),
                ),
                content: widget.child,
              )),
        );
      },
    );
  }
}

class WindowButtons extends StatelessWidget {
  const WindowButtons({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = FluentTheme.of(context);

    return SizedBox(
      width: 138,
      height: 50,
      child: WindowCaption(
        brightness: theme.brightness,
        backgroundColor: Colors.transparent,
      ),
    );
  }
}
