import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/api/wsl.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/dialogs/base_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/helpers.dart';

/// Copy Dialog
/// @param item: distro name
copyDialog(item) {
  WSLApi api = WSLApi();
  plausible.event(page: 'copy');
  dialog(
      item: item,
      title: '${'copy-text'.i18n()} \'$item\'',
      // A copy is an export + import (or a VHD copy) of the whole distro, and
      // it stops the source first. None of that was said anywhere before the
      // user committed to it (audit CI-31).
      body: '${'copyinstance-text'.i18n([
            distroLabel(item)
          ])}\n\n${'copyinstancewarning-text'.i18n()}',
      submitText: 'copy-text'.i18n(),
      submitStyle: const ButtonStyle(),
      onSubmit: (inputText) async {
        if (inputText.length > 0) {
          Notify.message('copyinginstance-text'.i18n([item]), loading: true);

          // Only allow A-Z, a-z, 0-9, and _ in distro names
          inputText = inputText.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
          String results;
          final useRemoteWsl = prefs.getBool('UseRemoteWSL') ?? false;

          // Check if old distro has path
          String? oldDistroPath = prefs.getString('Path_$item');
          if (oldDistroPath != null && oldDistroPath.isNotEmpty) {
            // Stop distro
            await api.stop(item);
            // Copy vhd
            results = await api.copyVhd(item, inputText);
          } else {
            // Export and import copy
            results = await api.copy(item, inputText);
          }

          // Error catching
          if (results.contains('Error')) {
            Notify.message(results,
                severity: InfoBarSeverity.error, loading: false);
            return;
          }
          // Copy settings
          String? startPath = prefs.getString('StartPath_$item') ?? '';
          String? startName = prefs.getString('StartUser_$item') ?? '';
          prefs.setString('DistroName_$inputText', inputText);
          prefs.setString('StartPath_$inputText', startPath);
          prefs.setString('StartUser_$inputText', startName);
          // Save distro path
          prefs.setString(
              'Path_$inputText',
              useRemoteWsl
                  ? api.remoteInstallPath(inputText)
                  : getInstancePath(inputText).path);
          Notify.message(
              'donecopyinginstance-text'.i18n([distroLabel(item), inputText]),
              severity: InfoBarSeverity.success,
              loading: false);
        } else {
          Notify.message('errorentername-text'.i18n(),
              severity: InfoBarSeverity.error, loading: false);
        }
      });
}
