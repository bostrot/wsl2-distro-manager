import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/apple/apple_vm_api.dart';
import 'package:wsl2distromanager/api/apple/vm_image_catalog.dart';
import 'package:wsl2distromanager/api/cancellation.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/api/recipes/recipe_service.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/screens/create_vm_screen.dart';

import 'apple_vm_api_test.dart' show FakeVmctlShell;

/// A catalog whose network is a canned resolution and an instant "download".
class _FakeCatalog implements VmImageCatalog {
  _FakeCatalog(this.dataDir, {this.failWith});
  final Directory dataDir;
  final Object? failWith;
  final List<String> downloaded = [];

  @override
  Future<String> download(VmIsoCatalogEntry entry,
      {void Function(int, int)? onProgress,
      CancelSignal? cancelSignal}) async {
    if (failWith != null) throw failWith!;
    onProgress?.call(50, 100);
    downloaded.add(entry.name);
    final path = '${dataDir.path}/isos/${entry.name}.iso';
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1]);
    return path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dataDir;
  late FakeVmctlShell shell;
  late _FakeCatalog catalog;

  setUpAll(() {
    Notify();
    Notify.message = (msg,
        {duration,
        severity = InfoBarSeverity.info,
        loading = false,
        useWidget = false,
        leadingIcon = true,
        dynamic widget}) {};
  });

  setUp(() async {
    dataDir = Directory.systemTemp.createTempSync('create-vm-screen-test');
    SharedPreferences.setMockInitialValues({'DataPath': dataDir.path});
    prefs = await SharedPreferences.getInstance();
    shell = FakeVmctlShell();
    shell.responses['list'] = '{"vms":[]}';
    catalog = _FakeCatalog(dataDir);
    appleVmApiBuilder = () => AppleVmApi(
          shell: shell,
          helperPathOverride: '/fake/vmctl',
          storeDirOverride: '${dataDir.path}/vms',
          earlyExitProbeDelay: Duration.zero,
        );
    vmImageCatalogBuilder = () => catalog;
  });

  tearDown(() {
    appleVmApiBuilder = () {
      final backend = AppleVmApi();
      return backend;
    };
    vmImageCatalogBuilder = VmImageCatalog.new;
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        const FluentApp(home: ScaffoldPage(content: CreateVmPage())));
    await tester.pump();
  }

  testWidgets('the installer box suggests the curated ISO catalog',
      (tester) async {
    await pump(tester);
    final box = tester.widget<AutoSuggestBox<String>>(
        find.byKey(const ValueKey('test-vm-iso')));
    final labels = box.items.map((item) => item.label).toList();
    expect(labels, containsAll(VmImageCatalog.names));
  });

  testWidgets('a Linux VM with no ISO and no image is refused', (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-name')), 'demo');
    // No installer, no base image.
    await tester.tap(find.byKey(const ValueKey('test-vm-create-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('test-vm-boot-error')), findsOneWidget);
    expect(shell.calls.any((c) => c.contains('create')), isFalse,
        reason: 'a VM that could only fail must never reach vmctl');
    expect(catalog.downloaded, isEmpty);
  });

  testWidgets('a catalog pick is downloaded and its local path used',
      (tester) async {
    // Creation itself fails, keeping the test off the router; the wiring
    // under test is catalog → download → create arguments.
    shell.exitCodes['create'] = 1;
    shell.errors['create'] = 'refused by test';

    await pump(tester);
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-name')), 'demo');
    await tester.enterText(find.byKey(const ValueKey('test-vm-iso')),
        'Alpine Linux (virt)');
    await tester.tap(find.byKey(const ValueKey('test-vm-create-button')));
    await tester.pumpAndSettle();

    expect(catalog.downloaded, ['Alpine Linux (virt)']);
    final createCall = shell.calls.lastWhere((c) => c.contains('create'));
    final isoArg = createCall[createCall.indexOf('--iso') + 1];
    expect(isoArg, endsWith('Alpine Linux (virt).iso'),
        reason: 'the backend must get the cached file, not the catalog name');
  });

  testWidgets('a plain path skips the catalog entirely', (tester) async {
    shell.exitCodes['create'] = 1;
    shell.errors['create'] = 'refused by test';

    await pump(tester);
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-name')), 'demo');
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-iso')), '/tmp/local.iso');
    await tester.tap(find.byKey(const ValueKey('test-vm-create-button')));
    await tester.pumpAndSettle();

    expect(catalog.downloaded, isEmpty);
    final createCall = shell.calls.lastWhere((c) => c.contains('create'));
    expect(createCall[createCall.indexOf('--iso') + 1], '/tmp/local.iso');
  });

  testWidgets('a chosen service is queued as pending for first run',
      (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-name')), 'dbvm');
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-iso')), '/tmp/local.iso');

    // Pick Postgres from the service dropdown.
    await tester.tap(find.byKey(const ValueKey('test-vm-recipe')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PostgreSQL — PostgreSQL 16 database server.').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('test-vm-create-button')));
    await tester.pumpAndSettle();

    // The VM was created and the recipe queued to install on first run.
    expect(shell.calls.any((c) => c.contains('create')), isTrue);
    expect(prefs.getString(RecipeService.pendingKey('dbvm')), 'postgres');
  });

  testWidgets('a failed download stops the create and re-enables the form',
      (tester) async {
    catalog = _FakeCatalog(dataDir, failWith: Exception('mirror down'));
    vmImageCatalogBuilder = () => catalog;

    await pump(tester);
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-name')), 'demo');
    await tester.enterText(find.byKey(const ValueKey('test-vm-iso')),
        'Alpine Linux (virt)');
    await tester.tap(find.byKey(const ValueKey('test-vm-create-button')));
    await tester.pumpAndSettle();

    // No create reached the helper, and the button is usable again.
    expect(shell.calls.where((c) => c.contains('create')), isEmpty);
    final button =
        find.byKey(const ValueKey('test-vm-create-button'));
    expect(tester.widget<Button>(find.descendant(
                of: button, matching: find.byWidgetPredicate((w) => w is Button))
            .first)
        .onPressed, isNotNull);
  });
}
