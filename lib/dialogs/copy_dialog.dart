import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/api.dart';
import 'package:wsl2distromanager/dialogs/base_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/helpers.dart';

/// Copy Dialog
/// @param context: context
/// @param item: distro name
/// @param api: WSLApi
/// @param statusMsg: Function(String, {bool loading})
copyDialog(context, item, Function(String, {bool loading}) statusMsg) {
  WSLApi api = WSLApi();
  plausible.event(page: 'copy');
  dialog(
      context: context,
      item: item,
      statusMsg: statusMsg,
      title: 'Copy \'$item\'',
      body: 'Copy the WSL instance \'${distroLabel(item)}\' to a new instance'
          ' with this name.',
      submitText: 'Copy',
      submitStyle: const ButtonStyle(),
      onSubmit: (inputText) async {
        if (inputText.length > 0) {
          statusMsg('Copying $item. This might take a while...', loading: true);
          await api.copy(item, inputText);
          // Copy settings
          String? startPath = prefs.getString('StartPath_' + item) ?? '';
          String? startName = prefs.getString('StartUser_' + item) ?? '';
          prefs.setString('StartPath_' + item, startPath);
          prefs.setString('StartUser_' + item, startName);
          statusMsg('DONE: Copied ${distroLabel(item)} to $inputText.');
        } else {
          statusMsg('ERROR: Please enter a name for the new instance.');
        }
      });
}
