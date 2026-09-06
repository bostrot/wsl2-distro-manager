import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/apple/apple_vm_api.dart';
import 'package:wsl2distromanager/api/vm/vm_platform.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/nav/panelist.dart';
import 'package:wsl2distromanager/screens/template_screen.dart';

import 'mocks.dart';
import 'vm_backend_test.dart' show FakeBackend;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() {
    vmBackendBuilder = defaultVmBackendBuilder;
  });

  Set<String> paneKeys() => originalItems
      .map((item) => item.key)
      .whereType<Key>()
      .map((key) => key.toString())
      .toSet();

  group('navigation follows the backend features', () {
    test('WSL backend shows every destination', () {
      vmBackendBuilder = () => WSLApi(shell: MockShell());
      final keys = paneKeys();
      expect(keys, contains("[<'/quickactions'>]"));
      expect(keys, contains("[<'/templates'>]"));
      // The AI Workspace needs a local wsl.exe, so its entry follows the
      // host platform even on the WSL backend.
      expect(keys.contains("[<'/ai-workspace'>]"), Platform.isWindows);
      expect(keys, contains("[<'/package'>]"));
      expect(keys, contains("[<'/addinstance'>]"));
    });

    test('a backend without WSL features hides the WSL-only entries', () {
      vmBackendBuilder = FakeBackend.new;
      final keys = paneKeys();
      expect(keys, isNot(contains("[<'/quickactions'>]")));
      expect(keys, isNot(contains("[<'/ai-workspace'>]")));
      expect(keys, isNot(contains("[<'/package'>]")));
      // Templates and create stay: they are first-class on every backend.
      expect(keys, contains("[<'/templates'>]"));
      expect(keys, contains("[<'/addinstance'>]"));
    });
  });

  group('templates deprecation banner', () {
    late Directory dataDir;

    setUp(() async {
      dataDir = Directory.systemTemp.createTempSync('tpl-ui-test');
      await prefs.setString('DataPath', dataDir.path);
      Directory('${dataDir.path}/templates').createSync();
    });

    tearDown(() {
      if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const FluentApp(home: TemplatePage()));
      await tester.pump();
    }

    testWidgets('shown on the WSL backend, which has distro packages',
        (tester) async {
      File('${dataDir.path}/templates/base.ext4').writeAsStringSync('x');
      await prefs.setStringList('templates', ['base']);
      vmBackendBuilder = () => WSLApi(shell: MockShell());

      await pump(tester);
      expect(
          find.byKey(const ValueKey('test-templates-deprecated')), findsOneWidget);
    });

    testWidgets('hidden on the Apple backend, where templates stay first-class',
        (tester) async {
      File('${dataDir.path}/templates/base.img').writeAsStringSync('x');
      await prefs.setStringList('templates', ['base']);
      vmBackendBuilder = () => AppleVmApi(
            helperPathOverride: '/fake/vmctl',
            storeDirOverride: '${dataDir.path}/vms',
          );

      await pump(tester);
      // The list itself renders (the template was adopted from disk) ...
      expect(find.textContaining('base'), findsWidgets);
      // ... but no deprecation banner.
      expect(
          find.byKey(const ValueKey('test-templates-deprecated')), findsNothing);
    });
  });
}
