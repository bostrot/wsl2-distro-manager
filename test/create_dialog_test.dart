/// Tests for lib/dialogs/create_dialog.dart — the create form's validation and
/// failure reporting.
///
/// Covers CI-12 ("Create default user" with an empty username used to import
/// the distro, skip the account and still report success) and CI-17 (every
/// failure path has to take the "Creating instance..." spinner down with it).
// ignore_for_file: dangling_library_doc_comments

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/dialogs/create_dialog.dart';

void main() {
  late List<String> messages;
  late List<bool> spinners;

  setUpAll(() {
    Notify();
    Notify.message = (msg,
        {duration,
        severity = InfoBarSeverity.info,
        loading = false,
        useWidget = false,
        leadingIcon = true,
        dynamic widget}) {
      messages.add(msg.toString());
      spinners.add(loading);
    };
  });

  setUp(() async {
    messages = [];
    spinners = [];
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('supportsDefaultUser', () {
    test('is false for the source types that hide the toggle', () {
      expect(supportsDefaultUser(CreateSourceType.turnkey), isFalse);
      expect(supportsDefaultUser(CreateSourceType.docker), isFalse);
      expect(supportsDefaultUser(CreateSourceType.vhdx), isFalse);
    });

    test('is true for the source types that show it', () {
      expect(supportsDefaultUser(CreateSourceType.repo), isTrue);
      expect(supportsDefaultUser(CreateSourceType.local), isTrue);
      expect(supportsDefaultUser(CreateSourceType.dockerLocalImage), isTrue);
    });
  });

  group('createInstance', () {
    test('refuses to start when a default user was asked for but not named',
        () async {
      final error = ValueNotifier<CreateFailure?>(null);
      final ok = await createInstance(
        TextEditingController(text: 'Ubuntu-Test'),
        TextEditingController(),
        WSLApi(),
        TextEditingController(text: 'Ubuntu'),
        TextEditingController(text: '   '),
        requireUser: true,
        onError: error,
      );

      expect(ok, isFalse);
      expect(error.value, isNotNull);
      expect(error.value!.message, 'errorenterusername-text');
      // A form the user can simply correct is not worth an AI diagnosis.
      expect(error.value!.diagnosable, isFalse);
      error.dispose();
    });

    test('leaves no spinner running behind a failure', () async {
      final error = ValueNotifier<CreateFailure?>(null);
      await createInstance(
        TextEditingController(text: 'Ubuntu-Test'),
        TextEditingController(),
        WSLApi(),
        TextEditingController(text: 'Ubuntu'),
        TextEditingController(),
        requireUser: true,
        onError: error,
      );

      // CI-17: the banner carries the text, so the status bar is cleared
      // rather than left spinning for the rest of the session.
      expect(messages.last, '');
      expect(spinners, everyElement(isFalse));
      error.dispose();
    });

    test('reports an empty name before it touches WSL', () async {
      final error = ValueNotifier<CreateFailure?>(null);
      final ok = await createInstance(
        TextEditingController(),
        TextEditingController(),
        WSLApi(),
        TextEditingController(text: 'Ubuntu'),
        TextEditingController(),
        onError: error,
      );

      expect(ok, isFalse);
      expect(error.value!.message, 'errorentername-text');
      error.dispose();
    });
  });
}
