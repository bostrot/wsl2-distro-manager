import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/constants.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/logging.dart';

/// Bug dialog
bugDialog() {
  // Get root context by Key
  final context = GlobalVariable.infobox.currentContext!;

  plausible.event(page: 'bug_dialog');
  // Show dialog that asks if the user wants to upload the log file or just open a github issue or cancel
  showDialog(
    context: context,
    builder: (context) => ContentDialog(
      title: const Text('🐞 Bug Report'),
      content: Text('report-text'.i18n()),
      actions: [
        SizedBox(
          height: 50.0,
          child: Button(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('cancelreport-text'.i18n()),
          ),
        ),
        SizedBox(
          height: 50.0,
          child: Button(
            onPressed: () {
              Navigator.of(context).pop();
              // Open github issue
              launchUrlString(githubIssues);
            },
            child: Text('githubissue-text'.i18n()),
          ),
        ),
        SizedBox(
          height: 50.0,
          child: Button(
            onPressed: () {
              Navigator.of(context).pop();
              // Upload log file
              uploadLog();
            },
            child: Text('uploadlogfile-text'.i18n()),
          ),
        ),
      ],
    ),
  );
}
