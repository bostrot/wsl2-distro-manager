import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/dialogs/base_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/helpers.dart';

/// Delete Dialog
/// @param context: context
/// @param item: distro name
/// @param api: WSLApi
/// @param statusMsg: status message
deleteDialog(context, item, Function(String, {bool loading}) statusMsg) {
  WSLApi api = WSLApi();
  plausible.event(page: 'delete');
  dialog(
      context: context,
      item: item,
      title: 'deleteinstancequestion-text'.i18n([distroLabel(item)]),
      body: 'deleteinstancebody-text'.i18n(),
      submitText: 'delete-text'.i18n(),
      submitInput: false,
      submitStyle: ButtonStyle(
        backgroundColor: ButtonState.all(Colors.red),
        foregroundColor: ButtonState.all(Colors.white),
      ),
      onSubmit: (inputText) {
        api.remove(item);
        statusMsg('deletedinstance-text'.i18n([item]));
      });
}
