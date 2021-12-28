import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/api.dart';
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
      statusMsg: statusMsg,
      title: 'Delete \'${distroLabel(item)}\' permanently?',
      body: 'If you delete this Distro you won\'t be able to recover it.'
          ' Do you want to delete it?',
      submitText: 'Delete',
      submitInput: false,
      submitStyle: ButtonStyle(
        backgroundColor: ButtonState.all(Colors.red),
        foregroundColor: ButtonState.all(Colors.white),
      ),
      onSubmit: (inputText) {
        api.remove(item);
        statusMsg('DONE: Deleted $item.');
      });
}
