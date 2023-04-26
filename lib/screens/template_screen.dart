import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/templates.dart';
import 'package:wsl2distromanager/components/helpers.dart';
import 'package:wsl2distromanager/dialogs/base_dialog.dart';

/// Template Screen
class TemplatePage extends StatefulWidget {
  const TemplatePage({super.key});

  @override
  State<TemplatePage> createState() => _TemplatePageState();
}

/// Template Screen State
class _TemplatePageState extends State<TemplatePage> {
  List<String> _templates = [];

  @override
  void initState() {
    super.initState();

    _templates = Templates().getTemplates();
  }

  @override
  Widget build(BuildContext context) {
    if (_templates.isEmpty) {
      return Center(
        child: Text('notemplates-text'.i18n()),
      );
    }
    // Scrollable list with template items
    return Padding(
        padding: const EdgeInsets.all(12.0),
        child: ListView.builder(
          itemCount: _templates.length,
          itemBuilder: (context, index) {
            var name = _templates[index];
            var size = Templates().getTemplateSize(name);
            if (size == '0 GB') {
              return const SizedBox();
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Expander(
                header: Text('$name ($size)'),
                content: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Button(
                        child: Row(
                          children: [
                            const Icon(FluentIcons.add),
                            const SizedBox(
                              width: 10.0,
                            ),
                            Text('createnewinstance-text'.i18n()),
                          ],
                        ),
                        onPressed: () => dialog(
                            item: name,
                            title: '${'copy-text'.i18n()} \'$name\'',
                            body: 'copyinstance-text'.i18n([distroLabel(name)]),
                            submitText: 'copy-text'.i18n(),
                            submitStyle: const ButtonStyle(),
                            onSubmit: (inputText) async {
                              await Templates().useTemplate(name, inputText);
                            })),
                    IconButton(
                      icon: const Icon(FluentIcons.delete),
                      onPressed: () {
                        dialog(
                            item: name,
                            title: 'deleteinstancequestion-text'
                                .i18n([distroLabel(name)]),
                            body: 'deleteinstancebody-text'.i18n(),
                            submitText: 'delete-text'.i18n(),
                            submitInput: false,
                            submitStyle: ButtonStyle(
                              backgroundColor: ButtonState.all(Colors.red),
                              foregroundColor: ButtonState.all(Colors.white),
                            ),
                            onSubmit: (inputText) async {
                              await Templates().deleteTemplate(name);
                              _templates.remove(name);
                              setState(() {});
                            });
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ));
  }
}
