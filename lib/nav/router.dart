import 'package:fluent_ui/fluent_ui.dart' hide Page;
import 'package:go_router/go_router.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/nav/root_screen.dart';
import 'package:wsl2distromanager/screens/actions_screen.dart';
import 'package:wsl2distromanager/screens/home_screen.dart';
import 'package:wsl2distromanager/screens/settings_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();
final router = GoRouter(
  navigatorKey: rootNavigatorKey,
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return RootPage(
          key: GlobalVariable.root,
          shellContext: _shellNavigatorKey.currentContext,
          state: state,
          child: child,
        );
      },
      routes: [
        /// Home
        GoRoute(
          path: '/',
          name: 'home',
          builder: (context, state) => const HomePage(
            title: "WSL Manager",
          ),
        ),

        /// Settings
        GoRoute(
          path: '/settings',
          name: 'settings',
          builder: (context, state) => const SettingsPage(),
        ),

        /// Quick Actions
        GoRoute(
          path: '/quickactions',
          name: 'quickactions',
          builder: (context, state) => const QuickPage(),
        ),
      ],
    ),
  ],
);
