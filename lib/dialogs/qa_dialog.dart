import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/qa_list.dart';
import 'package:wsl2distromanager/dialogs/info_dialog.dart';

/// Community Dialog
/// @param context: context
/// @param api: WSLApi
/// @param statusMsg: Function(String, {bool loading})
void communityDialog(context, Function callback) {
  // Global Key
  final GlobalKey<QaListState> qaKey = GlobalKey<QaListState>();
  plausible.event(page: 'open_community_dialog');
  showDialog(
    context: context,
    builder: (context) {
      return ContentDialog(
        content: SizedBox(
          height: MediaQuery.of(context).size.height,
          child: Column(
            children: [
              Expanded(
                child: QaList(
                  key: qaKey,
                ),
              ),
              ClickableUrl(
                clickEvent: "community_actions_url_clicked",
                url: 'https://github.com/bostrot/wsl-scripts#contribute',
                text: 'shareyourquickaction-text'.i18n(),
              ),
            ],
          ),
        ),
        actions: [
          Button(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text('cancel-text'.i18n()),
          ),
          Button(
            onPressed: () async {
              // Download selected
              await qaKey.currentState?.download();
              callback();
              // Navigator.pop(context);
            },
            child: Text('download-text'.i18n()),
          ),
        ],
      );
    },
  );
}
