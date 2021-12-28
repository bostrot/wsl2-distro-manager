import 'package:wsl2distromanager/dialogs/base_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/helpers.dart';

/// Rename Dialog
/// @param context: context
/// @param item: distro name
/// @param statusMsg: Function(String, {bool loading})
renameDialog(context, item, Function(String, {bool loading}) statusMsg) {
  dialog(
      context: context,
      item: item,
      statusMsg: statusMsg,
      title: 'Rename \'${distroLabel(item)}\'',
      body: 'Warning: Renaming will only change the label of the distro '
          'in this application. '
          '\n\nLeave this empty for the default name.',
      submitText: 'Rename',
      submitStyle: const ButtonStyle(),
      onSubmit: (inputText) {
        statusMsg('Renaming $item to $inputText...', loading: true);
        prefs.setString('DistroName_' + item, inputText);
        statusMsg('DONE: Renamed ${distroLabel(item)} to $inputText.');
      });
}
