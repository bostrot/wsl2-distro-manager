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

import 'fake_vmctl_shell.dart';

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

  /// The page opens on the cloud-image choice; this flips it to the ISO one.
  Future<void> chooseInstallerIso(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('test-vm-boot-installer-iso')));
    await tester.pumpAndSettle();
  }

  List<String> suggestionsOf(WidgetTester tester, String key) {
    final box = tester.widget<AutoSuggestBox<String>>(find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(AutoSuggestBox<String>)));
    return box.items.map((item) => item.label).toList();
  }

  final cloudImageNames = VmImageCatalog.entries
      .where((e) => e.isCloudImage)
      .map((e) => e.name)
      .toList();
  final isoNames = VmImageCatalog.entries
      .where((e) => !e.isCloudImage)
      .map((e) => e.name)
      .toList();

  testWidgets('the page opens on the cloud-image choice, listing only those',
      (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('test-vm-image')), findsOneWidget);
    expect(find.byKey(const ValueKey('test-vm-iso')), findsNothing);

    // bostrot/ai-tasks#5: cloud images and ISOs used to share one list.
    final labels = suggestionsOf(tester, 'test-vm-image');
    expect(labels, unorderedEquals(cloudImageNames));
    expect(cloudImageNames, isNotEmpty);
  });

  testWidgets('the installer-ISO choice swaps in a field listing only ISOs',
      (tester) async {
    await pump(tester);
    await chooseInstallerIso(tester);
    expect(find.byKey(const ValueKey('test-vm-iso')), findsOneWidget);
    expect(find.byKey(const ValueKey('test-vm-image')), findsNothing);

    final labels = suggestionsOf(tester, 'test-vm-iso');
    expect(labels, unorderedEquals(isoNames));
    for (final name in cloudImageNames) {
      expect(labels, isNot(contains(name)),
          reason: 'a cloud image is not an installer');
    }
  });

  testWidgets('switching the choice keeps what was typed under each',
      (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-image')), '/tmp/local.raw');
    await chooseInstallerIso(tester);
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-iso')), '/tmp/local.iso');

    await tester.tap(find.byKey(const ValueKey('test-vm-boot-cloud-image')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<AutoSuggestBox<String>>(find.descendant(
                of: find.byKey(const ValueKey('test-vm-image')),
                matching: find.byType(AutoSuggestBox<String>)))
            .controller
            ?.text,
        '/tmp/local.raw');

    await chooseInstallerIso(tester);
    expect(
        tester
            .widget<AutoSuggestBox<String>>(find.descendant(
                of: find.byKey(const ValueKey('test-vm-iso')),
                matching: find.byType(AutoSuggestBox<String>)))
            .controller
            ?.text,
        '/tmp/local.iso');
  });

  testWidgets('clicking the boot-source box lists the catalog before typing',
      (tester) async {
    await pump(tester);
    // Settle past fluent_ui's first-frame overlay reset.
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('test-vm-image'));
    final box = find.descendant(
        of: field, matching: find.byType(AutoSuggestBox<String>));
    expect(tester.state<AutoSuggestBoxState<String>>(box).isOverlayVisible,
        isFalse);

    await tester.tap(field);
    await tester.pumpAndSettle();

    // bostrot/ai-tasks#4: the list used to stay hidden until a keystroke.
    expect(tester.state<AutoSuggestBoxState<String>>(box).isOverlayVisible,
        isTrue);
    for (final name in cloudImageNames) {
      // The popup lives in the root overlay behind a transform follower,
      // which the default on-stage walk skips.
      expect(find.text(name, skipOffstage: false), findsOneWidget,
          reason: '$name should be listed');
    }
    for (final name in isoNames) {
      expect(find.text(name, skipOffstage: false), findsNothing,
          reason: '$name is an installer, not a cloud image');
    }
  });

  testWidgets('a Linux VM with no ISO and no image is refused', (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-name')), 'demo');
    // No cloud image chosen.
    await tester.tap(find.byKey(const ValueKey('test-vm-create-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('test-vm-boot-error')), findsOneWidget);
    expect(shell.calls.any((c) => c.contains('create')), isFalse,
        reason: 'a VM that could only fail must never reach vmctl');
    expect(catalog.downloaded, isEmpty);
  });

  testWidgets('a guest account name useradd would refuse never reaches vmctl',
      (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-name')), 'demo');
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-user')), 'Eric Trenkel');
    await tester.tap(find.byKey(const ValueKey('test-vm-create-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('test-vm-user-error')), findsOneWidget);
    // Refused here rather than by the helper: the name reaches an ssh
    // target and the .command script Terminal opens.
    expect(shell.calls.any((c) => c.contains('create')), isFalse);
  });

  testWidgets('a valid account name is passed through untouched',
      (tester) async {
    shell.exitCodes['create'] = 1;
    shell.errors['create'] = 'refused by test';
    await pump(tester);
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-name')), 'demo');
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-user')), 'eric_2');
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-image')), '/tmp/local.img');
    // Let the open suggestion list shrink to "no results" first.
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('test-vm-create-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('test-vm-user-error')), findsNothing);
    final create = shell.calls.lastWhere((c) => c.contains('create'));
    expect(create[create.indexOf('--user') + 1], 'eric_2');
  });

  testWidgets('switching the choice clears a stale boot-source error',
      (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-name')), 'demo');
    await tester.tap(find.byKey(const ValueKey('test-vm-create-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('test-vm-boot-error')), findsOneWidget);

    await chooseInstallerIso(tester);
    expect(find.byKey(const ValueKey('test-vm-boot-error')), findsNothing,
        reason: 'the complaint was about the cloud-image field');
  });

  testWidgets('only the chosen boot source counts', (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-name')), 'demo');
    // An ISO typed under the installer choice, then back to the (empty)
    // cloud-image choice: the ISO must not be silently used.
    await chooseInstallerIso(tester);
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-iso')), '/tmp/local.iso');
    await tester.tap(find.byKey(const ValueKey('test-vm-boot-cloud-image')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('test-vm-create-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('test-vm-boot-error')), findsOneWidget);
    expect(shell.calls.any((c) => c.contains('create')), isFalse);
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
    await chooseInstallerIso(tester);
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

  testWidgets('a cloud-image pick seeds the disk instead of attaching an ISO',
      (tester) async {
    shell.exitCodes['create'] = 1;
    shell.errors['create'] = 'refused by test';

    await pump(tester);
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-name')), 'demo');
    await tester.enterText(find.byKey(const ValueKey('test-vm-image')),
        'Debian 13 (cloud image)');
    // Focusing the box opened the full suggestion list, which is tall enough
    // to reach the create button; a frame lets it filter down to the match.
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('test-vm-create-button')));
    await tester.pumpAndSettle();

    final createCall = shell.calls.lastWhere((c) => c.contains('create'));
    expect(createCall, contains('--image'));
    expect(createCall[createCall.indexOf('--image') + 1],
        endsWith('Debian 13 (cloud image).iso'),
        reason: 'the downloaded file must seed the disk');
    expect(createCall.contains('--iso'), isFalse,
        reason: 'a cloud image is not an installer to attach');
  });

  testWidgets('a plain ISO path skips the catalog entirely', (tester) async {
    shell.exitCodes['create'] = 1;
    shell.errors['create'] = 'refused by test';

    await pump(tester);
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-name')), 'demo');
    await chooseInstallerIso(tester);
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-iso')), '/tmp/local.iso');
    await tester.tap(find.byKey(const ValueKey('test-vm-create-button')));
    await tester.pumpAndSettle();

    expect(catalog.downloaded, isEmpty);
    final createCall = shell.calls.lastWhere((c) => c.contains('create'));
    expect(createCall[createCall.indexOf('--iso') + 1], '/tmp/local.iso');
    expect(createCall.contains('--image'), isFalse);
  });

  testWidgets('a local disk image path seeds the disk', (tester) async {
    shell.exitCodes['create'] = 1;
    shell.errors['create'] = 'refused by test';

    await pump(tester);
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-name')), 'demo');
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-image')), '/tmp/template.raw');
    // As above: let the open suggestion list shrink to "no results" first.
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('test-vm-create-button')));
    await tester.pumpAndSettle();

    expect(catalog.downloaded, isEmpty);
    final createCall = shell.calls.lastWhere((c) => c.contains('create'));
    expect(createCall[createCall.indexOf('--image') + 1], '/tmp/template.raw');
    expect(createCall.contains('--iso'), isFalse);
  });

  testWidgets('a chosen service is queued as pending for first run',
      (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-name')), 'dbvm');
    await tester.enterText(
        find.byKey(const ValueKey('test-vm-image')), '/tmp/local.raw');
    // Focusing the box opens its catalog popup over the fields below; a
    // frame lets it shrink to the typed path (no match) before the click.
    await tester.pumpAndSettle();

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
    await chooseInstallerIso(tester);
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
