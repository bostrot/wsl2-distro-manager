import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/analytics.dart';
import 'package:wsl2distromanager/components/helpers.dart';

/// This function displays a dialog box with the given [item], which is a widget
/// that is displayed in the dialog box. It also takes an optional [onSubmit]
/// parameter, which is a function that is called
/// when the user presses the submit button. The rest of the parameters are
/// optional and are used to customize the dialog box. The [onSubmit] function
/// is called with the text input by the user as a parameter. This function
/// returns a future that resolves when the dialog is closed.
dialog({
  required item,
  Function? onSubmit,
  bool bodyIsWidget = false,
  Widget bodyAsWidget = const Text(''),
  String title = '',
  String body = '',
  String submitText = '',
  ButtonStyle submitStyle = const ButtonStyle(),
  bool submitInput = true,
  bool centerText = false,
  String cancelText = '',
  Function? onCancel,
}) {
  // Get root context by Key
  final context = GlobalVariable.infobox.currentContext!;
  final controller = TextEditingController();
  plausible.event(page: 'base_dialog');
  showDialog(
    context: context,
    builder: (context) {
      return ContentDialog(
        constraints: const BoxConstraints(maxHeight: 500.0, maxWidth: 500.0),
        title: centerText ? Center(child: Text(title)) : Text(title),
        content: SingleChildScrollView(
          child: Column(
            children: [
              !bodyIsWidget
                  ? centerText
                      ? Center(child: Text(body))
                      : Text(body)
                  : SizedBox(
                      width: double.infinity,
                      height: 120.0,
                      child: SingleChildScrollView(child: bodyAsWidget)),
              submitInput
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10.0),
                      child: TextBox(
                        controller: controller,
                        placeholder: item,
                      ),
                    )
                  : const Text(''),
            ],
          ),
        ),
        actions: [
          submitText != ''
              ? Button(
                  style: submitStyle,
                  onPressed: () {
                    Navigator.pop(context);
                    if (onSubmit != null) {
                      onSubmit(controller.text);
                    }
                  },
                  child: Text(submitText))
              : Container(),
          Button(
              child: Text(cancelText == '' ? 'cancel-text'.i18n() : cancelText),
              onPressed: () {
                if (onCancel != null) {
                  onCancel();
                }
                Navigator.pop(context);
              }),
        ],
      );
    },
  );
}
