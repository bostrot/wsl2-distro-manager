import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/sync.dart';
import 'package:wsl2distromanager/dialogs/base_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/helpers.dart';

/// Sync Dialog
/// @param context: context
/// @param item: distro name
/// @param statusMsg: Function(String, {bool loading})
syncDialog(context, item, Function(String, {bool loading}) statusMsg) {
  dialog(
      context: context,
      item: item,
      title: 'syncfromserver-text'.i18n([distroLabel(item)]),
      body: 'syncwarning-text'.i18n([item]),
      submitText: 'yesoverride-text'.i18n(),
      submitInput: false,
      submitStyle: ButtonStyle(
        backgroundColor: ButtonState.all(Colors.red),
        foregroundColor: ButtonState.all(Colors.white),
      ),
      onSubmit: (inputText) {
        Sync sync = Sync.instance(item, statusMsg);
        sync.download();
      });
}
