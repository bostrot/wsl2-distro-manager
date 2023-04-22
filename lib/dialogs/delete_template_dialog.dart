import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/templates.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/dialogs/base_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/helpers.dart';

/// Delete Template Dialog
deleteTemplateDialog(item, Function() callback) {
  plausible.event(page: 'delete');
  dialog(
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
        Templates().deleteTemplate(item);
      });
}
