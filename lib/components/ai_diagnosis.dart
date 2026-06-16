import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/ai_service.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/components/notify.dart';

/// Shows an AI-powered diagnosis for the given error message.
/// For Pro users: sends error to AI and shows response as a toast.
/// For non-Pro users: shows upgrade prompt with context about AI diagnosis.
Future<void> diagnoseWithAi(String errorMessage) async {
  final license = LicenseManager();

  if (!license.isPro) {
    Notify.message('upgrade-prompt-error'.i18n(),
        duration: const Duration(seconds: 5));
    return;
  }

  if (!AiService().hasQueriesRemaining) {
    Notify.message('ai-query-limit-text'.i18n());
    return;
  }

  try {
    Notify.message('ai-generating-text'.i18n(), loading: true);
    final diagnosis = await AiService().diagnoseError(errorMessage);
    if (diagnosis.isNotEmpty) {
      Notify.message(diagnosis, duration: const Duration(seconds: 30));
    } else {
      Notify.message('ai-error-text'.i18n());
    }
  } catch (_) {
    Notify.message('ai-error-text'.i18n());
  }
}

/// Small inline button that triggers AI diagnosis for the given error.
/// Only visible when placed in context where errors are shown.
class AiDiagnoseButton extends StatelessWidget {
  final String errorMessage;

  const AiDiagnoseButton({super.key, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return Button(
      onPressed: () => diagnoseWithAi(errorMessage),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FluentIcons.chat, size: 12),
          const SizedBox(width: 4),
          Text('ai-diagnose-text'.i18n()),
        ],
      ),
    );
  }
}
