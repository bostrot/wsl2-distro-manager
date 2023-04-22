import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/templates.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/dialogs/base_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/helpers.dart';

/// Copy Dialog
/// @param item: distro name
createTemplateDialog(item) {
  plausible.event(page: 'create_template');
  dialog(
      item: item,
      title: '${'copy-text'.i18n()} \'$item\'',
      body: 'copyinstance-text'.i18n([distroLabel(item)]),
      submitText: 'copy-text'.i18n(),
      submitStyle: const ButtonStyle(),
      onSubmit: (inputText) async {
        await Templates().useTemplate(item, inputText);
      });
}
