import 'package:fluent_ui/fluent_ui.dart';
import 'package:wsl2distromanager/components/analytics.dart';

dialog({
  required BuildContext context,
  required item,
  required Function statusMsg,
  Function? onSubmit,
  String title = '',
  String body = '',
  String submitText = '',
  ButtonStyle submitStyle = const ButtonStyle(),
  bool submitInput = true,
  bool centerText = false,
  String cancelText = 'Cancel',
  Function? onCancel,
}) {
  final controller = TextEditingController();
  plausible.event(page: title.split(' ')[0].toLowerCase());
  showDialog(
    context: context,
    builder: (context) {
      return ContentDialog(
        title: centerText ? Center(child: Text(title)) : Text(title),
        content: Column(
          children: [
            centerText ? Center(child: Text(body)) : Text(body),
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
                  child: Text(submitText),
                  style: submitStyle,
                  onPressed: () {
                    Navigator.pop(context);
                    if (onSubmit != null) {
                      onSubmit(controller.text);
                    }
                  })
              : Container(),
          Button(
              child: Text(cancelText),
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
