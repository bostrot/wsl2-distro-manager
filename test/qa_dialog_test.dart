/// The community snippet browser (audit CI-36).
///
/// `download()` used to catch its own failure, post a three-word toast and
/// return normally, so `qa_dialog.dart` popped the dialog and ran the success
/// callback exactly as it did on a good download — the user was told nothing
/// and left in front of a list that had not changed. On the way in, a failed
/// catalogue fetch rendered `Center(child: Text('errordownloading-text'))`:
/// three words, no reason, no retry.
///
/// There is no localization delegate here, so `.i18n()` returns the key it was
/// handed — which is what the assertions match on.
// ignore_for_file: dangling_library_doc_comments

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/components/qa_list.dart';
import 'package:wsl2distromanager/dialogs/qa_dialog.dart';

const String _infoYml = 'name: apt-upgrade\n'
    'description: Update every package\n'
    'version: 1.0.0\n'
    'author: bostrot\n'
    'license: MIT\n'
    'git: https://github.com/bostrot/wsl-scripts\n'
    'distro: ubuntu\n';

/// Serves the two-stage catalogue fetch and the per-snippet script fetch, and
/// can fail either one on demand.
class _ScriptsAdapter implements HttpClientAdapter {
  bool failCatalogue = false;
  bool failScript = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.path.contains('api.github.com')) {
      if (failCatalogue) {
        return ResponseBody.fromString('nope', 500);
      }
      return ResponseBody.fromString(
          jsonEncode([
            {'name': 'apt-upgrade'}
          ]),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
    }
    if (options.path.endsWith('info.yml')) {
      return ResponseBody.fromString(_infoYml, 200, headers: {
        Headers.contentTypeHeader: [Headers.textPlainContentType]
      });
    }
    if (options.path.endsWith('script.noshell')) {
      if (failScript) {
        return ResponseBody.fromString('gone', 404);
      }
      return ResponseBody.fromString('apt update && apt upgrade -y', 200,
          headers: {
            Headers.contentTypeHeader: [Headers.textPlainContentType]
          });
    }
    return ResponseBody.fromString('', 404);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _ScriptsAdapter adapter;
  late Dio dio;
  var callbackCount = 0;

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
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    // Process-lifetime cache: without this the second test is served the
    // first test's catalogue.
    QaListState.items = [];
    callbackCount = 0;
    adapter = _ScriptsAdapter();
    dio = Dio()..httpClientAdapter = adapter;
  });

  /// Opens the dialog over a real route so `Navigator.pop` has something to
  /// pop, and returns once the catalogue has loaded.
  Future<void> openDialog(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(FluentApp(
      home: ScaffoldPage(
        content: Builder(
          builder: (context) => Button(
            child: const Text('open'),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => CommunityDialog(
                callback: () => callbackCount++,
                dio: dio,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a downloaded snippet is confirmed and the dialog closes',
      (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('apt-upgrade'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('test-qa-download')));
    await tester.pumpAndSettle();

    expect(find.text('apt-upgrade'), findsNothing, reason: 'dialog is closed');
    expect(callbackCount, 1);
    expect(prefs.getStringList('quickSettingsTitles'), ['apt-upgrade']);
  });

  // The whole point of the finding: a failure that looks exactly like a
  // success. The dialog closed, the callback ran, and the only thing on
  // screen afterwards was a stale message from a different dialog.
  testWidgets('a failed download keeps the dialog open and says why',
      (tester) async {
    adapter.failScript = true;
    await openDialog(tester);

    await tester.tap(find.text('apt-upgrade'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('test-qa-download')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('test-qa-download-error')),
        findsOneWidget);
    expect(find.text('snippetdownloadfailed-text'), findsOneWidget);
    // Still open, still selectable, and nothing was written.
    expect(find.text('apt-upgrade'), findsOneWidget);
    expect(callbackCount, 0);
    expect(prefs.getStringList('quickSettingsTitles'), null);
  });

  testWidgets('Download with nothing selected says so instead of closing',
      (tester) async {
    await openDialog(tester);

    await tester.tap(find.byKey(const ValueKey('test-qa-download')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('test-qa-validation')), findsOneWidget);
    expect(find.text('snippetsselectone-text'), findsOneWidget);
    expect(find.text('apt-upgrade'), findsOneWidget, reason: 'still open');
    expect(callbackCount, 0);
  });

  // The catalogue is fetched once per process and cached in a static, so a
  // failed first load could not be retried without restarting the app.
  testWidgets('a catalogue that fails to load offers a retry that works',
      (tester) async {
    adapter.failCatalogue = true;
    await openDialog(tester);

    expect(find.byKey(const ValueKey('test-qa-load-error')), findsOneWidget);
    expect(find.text('snippetsloadfailed-text'), findsOneWidget);
    expect(find.byKey(const ValueKey('test-qa-retry')), findsOneWidget);

    adapter.failCatalogue = false;
    await tester.tap(find.byKey(const ValueKey('test-qa-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('test-qa-load-error')), findsNothing);
    expect(find.text('apt-upgrade'), findsOneWidget);
  });
}
