import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/components/analytics.dart';

dialog({
  required BuildContext context,
  required item,
  required Function statusMsg,
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
  final controller = TextEditingController();
  plausible.event(page: title.split(' ')[0].toLowerCase());
  showDialog(
    context: context,
    builder: (context) {
      return ContentDialog(
        constraints: const BoxConstraints(maxHeight: 300.0, maxWidth: 400.0),
        title: centerText ? Center(child: Text(title)) : Text(title),
        content: Column(
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
