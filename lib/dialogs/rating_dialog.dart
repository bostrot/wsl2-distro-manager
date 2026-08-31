import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:wsl2distromanager/api/license_manager.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';

/// Instances the user has to have created before the rating prompt appears.
const int _instancesBeforeAsking = 3;

/// Extra instances they have to create before a deferred prompt returns.
const int _instancesBeforeAskingAgain = 5;

/// Ask for a Store rating once the app has actually proven useful.
///
/// Only Store installs are asked: the review page is part of the Store
/// listing, so a GitHub build would be sent somewhere it cannot post.
Future<void> maybeShowRatingPrompt() async {
  if (!LicenseManager().isStoreLicensed) return;
  if (prefs.getBool('RatingPromptDone') ?? false) return;

  final created = prefs.getInt('InstancesCreated') ?? 0;
  final threshold = prefs.getInt('RatingPromptNextAt') ?? _instancesBeforeAsking;
  if (created < threshold) return;

  while (GlobalVariable.infobox.currentContext == null) {
    await Future.delayed(const Duration(milliseconds: 100));
  }
  plausible.event(page: 'rating_prompt');

  showDialog(
    context: GlobalVariable.infobox.currentContext!,
    builder: (context) => ContentDialog(
      constraints: const BoxConstraints(maxWidth: 460.0),
      title: Text('rate-title'.i18n()),
      content: Text('rate-text'.i18n(), style: const TextStyle(height: 1.4)),
      actions: [
        Button(
          child: Text('rate-never'.i18n()),
          onPressed: () {
            prefs.setBool('RatingPromptDone', true);
            Navigator.pop(context);
          },
        ),
        Button(
          child: Text('rate-later'.i18n()),
          onPressed: () {
            prefs.setInt(
                'RatingPromptNextAt', created + _instancesBeforeAskingAgain);
            Navigator.pop(context);
          },
        ),
        FilledButton(
          child: Text('rate-now'.i18n()),
          onPressed: () {
            prefs.setBool('RatingPromptDone', true);
            launchUrlString(storeReviewUrl);
            Navigator.pop(context);
          },
        ),
      ],
    ),
  );
}

/// Count a successful instance creation towards the rating prompt.
void recordInstanceCreated() {
  prefs.setInt('InstancesCreated', (prefs.getInt('InstancesCreated') ?? 0) + 1);
}
