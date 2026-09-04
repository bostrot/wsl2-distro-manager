/// The notices at the top of the AI dock ("needs a key", "why Send did
/// nothing", "request failed") carry a button. In a 360px dock the sentence
/// always wraps, and fluent's short InfoBar layout — a Wrap with no run
/// spacing — dropped the button straight onto the last line of text
/// (ai-tasks#15). The long layout stacks title and button with a gap.
///
/// There is no localization delegate here, so `.i18n()` returns the key it
/// was handed — which is what the finders match on.
// ignore_for_file: dangling_library_doc_comments

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wsl2distromanager/api/ai_service.dart';
import 'package:wsl2distromanager/api/vm/vm_platform.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/ai_chat_panel.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/notify.dart';

import 'mocks.dart';

void main() {
  /// The dock's width on a wide window (root_screen.dart).
  const dockWidth = 360.0;

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

  setUp(() {
    vmBackendBuilder = () => WSLApi(shell: MockShell());
  });

  tearDown(() {
    vmBackendBuilder = defaultVmBackendBuilder;
  });

  Future<void> pumpDock(WidgetTester tester,
      {Map<String, Object> prefsValues = const {}}) async {
    SharedPreferences.setMockInitialValues(prefsValues);
    prefs = await SharedPreferences.getInstance();
    await AiService().init();
    addTearDown(AiService().clearHistory);

    await tester.binding.setSurfaceSize(const Size(dockWidth, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        const FluentApp(home: ScaffoldPage(content: AiChatPanel())));
    await tester.pumpAndSettle();
  }

  /// The button of the InfoBar at [bar] must start below the bar's title
  /// with visible breathing room, rather than touching or overlapping it.
  void expectButtonBelowTitle(WidgetTester tester, Finder bar, String title) {
    final titleRect =
        tester.getRect(find.descendant(of: bar, matching: find.text(title)));
    final buttonRect =
        tester.getRect(find.descendant(of: bar, matching: find.byType(Button)));
    expect(buttonRect.top - titleRect.bottom, greaterThanOrEqualTo(8.0),
        reason: 'the button must not sit hard against the text above it');
    expect(buttonRect.left, closeTo(titleRect.left, 1.0),
        reason: 'stacked under the title, not trailing its last line');
    // And it still fits the dock.
    expect(buttonRect.right, lessThanOrEqualTo(dockWidth));
  }

  group('AI dock notices', () {
    testWidgets('"needs a key" keeps a gap above Open settings',
        (tester) async {
      await pumpDock(tester);

      final bar = find.byKey(const ValueKey('test-aichat-needs-key'));
      expect(bar, findsOneWidget);
      expect(tester.widget<InfoBar>(bar).isLong, isTrue);
      expectButtonBelowTitle(tester, bar, 'byok-required-text');
    });

    testWidgets('"needs a key" is gone once a key is configured',
        (tester) async {
      await pumpDock(tester, prefsValues: {'ByokApiKey': 'sk-test'});
      expect(find.byKey(const ValueKey('test-aichat-needs-key')), findsNothing);
    });

    testWidgets('a blocked Send keeps a gap above its action', (tester) async {
      await pumpDock(tester);

      await tester.enterText(find.byType(TextBox).first, 'hello');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Button, 'ai-send-text'));
      await tester.pumpAndSettle();

      // Blocking replaces the standing notice rather than doubling it. Under
      // the test binding the licence check is what blocks first, so the
      // notice is the Pro one with its Upgrade action.
      expect(find.byKey(const ValueKey('test-aichat-needs-key')), findsNothing);
      final bar = find.byKey(const ValueKey('test-aichat-blocked'));
      expect(bar, findsOneWidget);
      expect(tester.widget<InfoBar>(bar).isLong, isTrue);
      expectButtonBelowTitle(tester, bar, 'ai-chat-pro-required-text');
    });
  });
}
