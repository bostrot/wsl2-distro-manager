import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show OffsetLayer;

import 'package:fluent_ui/fluent_ui.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:localization/localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/main.dart';
import 'package:wsl2distromanager/nav/router.dart';

/// Walks every screen of the macOS app the way a user would — real taps on
/// the real backend — and captures each screen to PNG for visual review.
///
/// The VM parts run against the actual vmctl helper through an isolated
/// temp store (seeded via the DataPath preference, which both the store and
/// the helper lookup honour); when no built helper can be found they are
/// skipped rather than failed, so the file stays runnable anywhere.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (!Platform.isMacOS) {
    test('macOS walkthrough only runs on macOS', () {});
    return;
  }

  late Directory dataDir;
  final shotsDir = Directory(
      '${Directory.systemTemp.path}/wslmanager-walkthrough-shots')
    ..createSync(recursive: true);

  /// The vmctl built by scripts/build_macos.sh, if this machine has one.
  String? locateVmctl() {
    final candidates = [
      Platform.environment['VMCTL_PATH'],
      '${Platform.environment['PWD'] ?? ''}/macos/vmctl/.build/release/vmctl',
      '${Platform.environment['HOME'] ?? ''}/Documents/projects/code/wslmanager/macos/vmctl/.build/release/vmctl',
    ];
    for (final c in candidates) {
      if (c != null && c.isNotEmpty && File(c).existsSync()) return c;
    }
    return null;
  }

  Future<void> snap(WidgetTester tester, String name) async {
    try {
      final view = tester.binding.renderViews.first;
      final layer = view.debugLayer;
      if (layer is! OffsetLayer) return;
      final image = await layer.toImage(Offset.zero & view.size);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      File('${shotsDir.path}/$name.png')
          .writeAsBytesSync(bytes.buffer.asUint8List());
    } catch (error) {
      debugPrint('snap $name failed: $error');
    }
  }

  setUp(() async {
    dataDir = Directory.systemTemp.createTempSync('walkthrough-data');
    // Seeding version suppresses the first-start dialog, whose modal
    // barrier would otherwise swallow every tap (see AGENTS.md); DataPath
    // isolates the VM store; language pins the strings the finders use.
    SharedPreferences.setMockInitialValues({
      'version': currentVersion,
      'LastChangelogVersion': currentVersion,
      'DataPath': dataDir.path,
      'language': 'en',
    });
    prefs = await SharedPreferences.getInstance();
    GlobalVariable.aiPanelVisible = false;
    final vmctl = locateVmctl();
    if (vmctl != null) {
      final target = File('${dataDir.path}/bin/vmctl')
        ..parent.createSync(recursive: true);
      File(vmctl).copySync(target.path);
      Process.runSync('chmod', ['+x', target.path]);
    }
  });

  tearDown(() {
    GlobalVariable.aiPanelVisible = false;
    GlobalVariable.testProEnabled = false;
    LicenseManager.storeInstallCheckOverride = null;
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
  });

  Future<void> boot(WidgetTester tester) async {
    await tester.pumpWidget(const WSLManager());
    await tester.pumpAndSettle(const Duration(seconds: 3));
    // The router is a global singleton, so it still points wherever the
    // previous test left it.
    router.goNamed('home');
    await tester.pumpAndSettle();
  }

  testWidgets('home: VM-backend nav, empty state leads to Create VM',
      (tester) async {
    await boot(tester);
    await snap(tester, '01-home');

    // WSL-only destinations are gone; the shared ones are present.
    expect(find.text('managequickactions-text'.i18n()), findsNothing);
    expect(find.text('custompackage-text'.i18n()), findsNothing);
    expect(find.text('ai-workspace-title'.i18n()), findsNothing);
    expect(find.text('mountdisk-text'.i18n()), findsNothing);

    if (locateVmctl() != null) {
      // Empty store: the list shows the no-instances state whose CTA leads
      // to the VM create page.
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('noinstancesfound-text'.i18n()), findsOneWidget,
          reason: 'an empty VM store must read as "no instances", not as '
              'an error');
      await tester.tap(find.text('addinstance-text'.i18n()).last,
          warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('test-vm-name')), findsOneWidget);
      await snap(tester, '02-create-vm-via-cta');
    }
  });

  testWidgets('create VM page: validation, guest switch, real create',
      (tester) async {
    await boot(tester);
    router.pushNamed('addinstance');
    await tester.pumpAndSettle();
    await snap(tester, '03-create-vm');

    // Wrong: empty name must be refused inline.
    await tester.tap(find.byKey(const ValueKey('test-vm-create-button')),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('test-vm-name-error')), findsOneWidget);

    // The macOS guest branch swaps the form fields.
    await tester.tap(find.byKey(const ValueKey('test-vm-guest-os')),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('macOS').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('test-vm-restore-image')), findsOneWidget);
    expect(find.byKey(const ValueKey('test-vm-iso')), findsNothing);
    await snap(tester, '04-create-vm-macos-guest');
    await tester.tap(find.byKey(const ValueKey('test-vm-guest-os')),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Linux').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    if (locateVmctl() == null) return;

    // Right: a named create builds a real (blank-disk) VM in the temp store.
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-name')), 'walkthrough');
    await tester.tap(find.byKey(const ValueKey('test-vm-create-button')),
        warnIfMissed: false);
    // vmctl create runs ssh-keygen + hdiutil; give it a moment.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (File('${dataDir.path}/vms/walkthrough/config.json').existsSync()) {
        break;
      }
    }
    expect(File('${dataDir.path}/vms/walkthrough/config.json').existsSync(),
        isTrue,
        reason: 'Create must produce a VM in the store');
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // A successful create leaves the page towards home, where the new VM
    // is listed as a row.
    expect(find.byKey(const ValueKey('test-vm-name')), findsNothing,
        reason: 'the create page must close itself after a successful create');
    expect(find.textContaining('walkthrough'), findsWidgets);
    await snap(tester, '05-home-with-vm');

    // Starting a VM with nothing bootable must fail loudly, not report
    // success over a window that closed itself.
    await tester.tap(find.byKey(const ValueKey('test-listitem-start')),
        warnIfMissed: false);
    // The explanation lands after the ~4s early-exit probe and expires with
    // the notification bar, so poll rather than wait-then-look.
    final marker =
        'vmstoppedimmediately-text'.i18n().split('\n').first.substring(0, 30);
    var explained = false;
    for (var i = 0; i < 30 && !explained; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      explained = find.textContaining(marker).evaluate().isNotEmpty;
    }
    await snap(tester, '06-start-nothing-bootable');
    expect(explained, isTrue,
        reason: 'the early-exit explanation must reach the status bar');
  });

  testWidgets('templates: first-class on macOS, no deprecation banner',
      (tester) async {
    // A template file on disk is adopted into the list.
    final templates = Directory('${dataDir.path}/templates')
      ..createSync(recursive: true);
    File('${templates.path}/base.img').writeAsStringSync('x');
    await boot(tester);
    router.pushNamed('templates');
    await tester.pumpAndSettle();
    await snap(tester, '07-templates');
    expect(find.textContaining('base'), findsWidgets);
    expect(find.byKey(const ValueKey('test-templates-deprecated')),
        findsNothing);
  });

  testWidgets('license: buys on wslmanager.com, no AI Workspace row',
      (tester) async {
    await boot(tester);
    router.pushNamed('license');
    await tester.pumpAndSettle();
    await snap(tester, '08-license');
    expect(find.text('web-buy-btn'.i18n()), findsOneWidget);
    expect(find.text('store-buy-btn'.i18n()), findsNothing);
    expect(find.text('web-price-text'.i18n()), findsOneWidget);
    expect(find.text('ai-workspace-feature'.i18n()), findsNothing);
    expect(find.text('core-vm-management-feature'.i18n()), findsOneWidget);
  });

  testWidgets('settings: only backend-relevant sections and controls',
      (tester) async {
    await boot(tester);
    router.pushNamed('settings');
    await tester.pumpAndSettle();
    await snap(tester, '09-settings');

    expect(find.text('generalsettings-text'.i18n()), findsOneWidget);
    expect(find.text('dockersettings-text'.i18n()), findsNothing);
    expect(find.text('syncsettings-text'.i18n()), findsNothing);
    expect(find.text('globalconfiguration-text'.i18n()), findsNothing);
    expect(find.text('experimental-text'.i18n()), findsNothing);
    expect(find.text('editwslconfig-text'.i18n()), findsNothing);
    expect(find.text('stopwsl-text'.i18n()), findsNothing);

    // The general section opens and holds no remote-WSL toggle.
    await tester.tap(find.text('generalsettings-text'.i18n()),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('remote-wsl-over-ssh-text'.i18n()), findsNothing);
    await snap(tester, '10-settings-general');
  });

  testWidgets('dark mode toggle flips the theme', (tester) async {
    await boot(tester);
    final toggle = find.widgetWithText(ToggleSwitch, 'darkmode-text'.i18n());
    expect(toggle, findsOneWidget);
    final before =
        FluentTheme.of(tester.element(find.byType(NavigationView))).brightness;
    await tester.tap(toggle, warnIfMissed: false);
    await tester.pumpAndSettle();
    final after =
        FluentTheme.of(tester.element(find.byType(NavigationView))).brightness;
    expect(after, isNot(before));
    await snap(tester, '11-theme-flipped');
  });
}
