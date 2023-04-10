import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/dialogs/base_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/components/constants.dart';

/// Copy Dialog
/// @param item: distro name
copyDialog(item) {
  WSLApi api = WSLApi();
  plausible.event(page: 'copy');
  dialog(
      item: item,
      title: '${'copy-text'.i18n()} \'$item\'',
      body: 'copyinstance-text'.i18n([distroLabel(item)]),
      submitText: 'copy-text'.i18n(),
      submitStyle: const ButtonStyle(),
      onSubmit: (inputText) async {
        if (inputText.length > 0) {
          Notify.message('copyinginstance-text'.i18n([item]), loading: true);

          final String path = prefs.getString('SaveLocation') ?? defaultPath;
          // Only allow A-Z, a-z, 0-9, and _ in distro names
          inputText = inputText.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
          String results;

          // Check if old distro has path
          String? oldDistroPath = prefs.getString('Path_$item');
          if (oldDistroPath != null && oldDistroPath.isNotEmpty) {
            // Stop distro
            await api.stop(item);
            // Copy vhd
            results = await api.copyVhd('$oldDistroPath\\ext4.vhdx', inputText,
                location: path);
          } else {
            // Export and import copy
            results = await api.copy(item, inputText, location: path);
          }

          // Error catching
          if (results.contains('Error')) {
            Notify.message(results, loading: false);
            return;
          }
          // Copy settings
          String? startPath = prefs.getString('StartPath_$item') ?? '';
          String? startName = prefs.getString('StartUser_$item') ?? '';
          prefs.setString('DistroName_$inputText', inputText);
          prefs.setString('StartPath_$inputText', startPath);
          prefs.setString('StartUser_$inputText', startName);
          // Save distro path
          prefs.setString('Path_$inputText', '$path\\$inputText');
          Notify.message(
              'donecopyinginstance-text'.i18n([distroLabel(item), inputText]),
              loading: false);
        } else {
          Notify.message('errorentername-text'.i18n(), loading: false);
        }
      });
}
