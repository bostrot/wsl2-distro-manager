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
      statusMsg: statusMsg,
      title: 'Sync \'${distroLabel(item)}\' from the server',
      body: 'Warning: Syncing will shutdown WSL and override the distro '
          '"$item" completely! There is no way to turn back! A backup is advised.'
          '\n\nAre you sure you want to continue?',
      submitText: 'Yes, sync (override)',
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
