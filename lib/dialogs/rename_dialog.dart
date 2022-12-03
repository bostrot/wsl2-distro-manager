import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/notify.dart';
import 'package:wsl2distromanager/dialogs/base_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/helpers.dart';

/// Rename Dialog
/// @param context: context
/// @param item: distro name
renameDialog(context, item) {
  dialog(
      context: context,
      item: item,
      title: '${'rename-text'.i18n()} \'${distroLabel(item)}\'',
      body: 'renameinfo-text'.i18n(),
      submitText: 'Rename',
      submitStyle: const ButtonStyle(),
      onSubmit: (inputText) {
        Notify.message(
            'renaminginstance-text'.i18n([distroLabel(item), inputText]),
            loading: true);
        prefs.setString('DistroName_$item', inputText);
        Notify.message(
            'renamedinstance-text'.i18n([distroLabel(item), inputText]));
      });
}
