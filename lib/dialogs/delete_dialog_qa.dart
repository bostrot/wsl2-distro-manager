import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/api/quick_actions.dart';
import 'package:wsl2distromanager/dialogs/base_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// QuickActions Delete Dialog
/// @param context: context
/// @param {QuickActionItem} item: QuickActionItem
deleteQaDialog(context, QuickActionItem item, Function callback) {
  plausible.event(page: 'delete_qa');
  dialog(
      context: context,
      item: item,
      title: 'deleteinstancequestion-text'.i18n([item.name]),
      body: 'deleteinstancebody-text'.i18n(),
      submitText: 'delete-text'.i18n(),
      submitInput: false,
      submitStyle: ButtonStyle(
        backgroundColor: ButtonState.all(Colors.red),
        foregroundColor: ButtonState.all(Colors.white),
      ),
      onSubmit: (inputText) {
        QuickAction.removeFromPrefs(item);
        callback();
      });
}
